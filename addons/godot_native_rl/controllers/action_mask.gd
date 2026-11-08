class_name ActionMask
extends RefCounted

# Pure action-mask helper (#410): turn-based combat frequently produces illegal actions
# (attacking an out-of-range enemy, firing without a target, moving into an occupied
# tile). An agent may expose get_action_mask() -> {head: [bool, ...]} (True = legal),
# one boolean array per DISCRETE action head, recomputed at every decision step from
# live game state. This helper validates the mask against the action space and applies
# it to the raw policy logits by overwriting every illegal slot with ILLEGAL_LOGIT —
# a large negative value — BEFORE argmax/softmax, so an illegal action can never be
# selected deterministically and receives ~0 probability when sampling. The same
# convention the Python training side applies (logits[~mask] = -inf before sampling);
# the wire copy of the mask travels in the step message's info["action_mask"].
#
# Contract (validate enforces all of it):
#   - every DISCRETE head of the action space has an entry (a head the agent forgets
#     is a drift bug — loud failure, not silent full-legal fallback); continuous heads
#     never do (masking a mean vector is meaningless);
#   - each entry is an array of the head's exact size whose elements are bools (or 0/1
#     numbers — what JSON round-trips produce);
#   - every head keeps at least one legal action (the neutral index, e.g. "hold fire",
#     is always legal); an all-illegal head would argmax to slot 0 and softmax to a
#     uniform draw — both nonsense — so it is rejected up front.

# The large negative value substituted for illegal logits. Exactly representable in
# float32 (1e9 = 2^9 * 1953125); softmax against O(1) logits underflows it to 0 prob.
const ILLEGAL_LOGIT := -1.0e9

# {} when the agent supplies no mask (fully legal action space — current behavior);
# otherwise whatever get_action_mask() returned. Non-Dictionary returns warn and read
# as "no mask" rather than killing the step: a missing mask degrades to the old
# unmasked behavior, an INVALID one is rejected loudly by the caller via validate().
static func from_agent(agent) -> Dictionary:
	if agent == null or not agent.has_method("get_action_mask"):
		return {}
	var mask = agent.get_action_mask()
	if not (mask is Dictionary):
		push_warning("ActionMask.from_agent: get_action_mask() must return a Dictionary, got %s — ignoring the mask." % type_string(typeof(mask)))
		return {}
	return mask

# True iff `mask` satisfies the contract above for `action_space`'s discrete heads.
static func validate(mask: Dictionary, action_space: Dictionary) -> bool:
	if mask.is_empty():
		return false
	var discrete_sizes := {}
	for key in action_space.keys():
		var entry: Dictionary = action_space[key]
		if str(entry.get("action_type", "")) == "discrete":
			discrete_sizes[key] = int(entry.get("size", 0))
	for key in mask.keys():
		if not discrete_sizes.has(key):
			# Unknown head, or a mask entry for a continuous head — both wrong.
			return false
	for key in discrete_sizes.keys():
		if not mask.has(key):
			return false
		var values = mask[key]
		if not (values is Array or values is PackedFloat32Array \
				or values is PackedInt32Array or values is PackedByteArray):
			return false
		if values.size() != int(discrete_sizes[key]):
			return false
		var any_legal := false
		for v in values:
			var truth = _truth(v)
			if truth == null:
				return false
			if truth:
				any_legal = true
		if not any_legal:
			return false
	return true

# Copy `output` with every illegal discrete slot overwritten by ILLEGAL_LOGIT; legal
# slots and continuous segments pass through untouched. Pure: `output` is never
# mutated. Assumes validate() passed (sizes/keys already cross-checked).
static func apply_to_logits(output: PackedFloat32Array, mask: Dictionary, action_space: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array(output)
	var index := 0
	for key in action_space.keys():
		var entry: Dictionary = action_space[key]
		var size: int = int(entry.get("size", 0))
		if str(entry.get("action_type", "")) == "discrete":
			var values = mask[key]
			for i in range(size):
				if not bool(values[i]):
					out[index + i] = ILLEGAL_LOGIT
		index += size
	return out

# bool stays bool; int/float read as non-zero (the JSON wire round-trip turns false
# into 0); anything else is not a mask element -> null (invalid).
static func _truth(v):
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		_:
			return null
