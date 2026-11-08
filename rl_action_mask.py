#!/usr/bin/env python3
"""Action-mask application for the Python training wrapper (issue #423).

The Godot environment ships one boolean array per discrete action head in
``info["action_mask"]`` on every training step (issue #410). The exported
ncnn model carries no masking logic, so BOTH consumption paths apply the
exact same convention — overwrite the logits of illegal actions with
ILLEGAL_LOGIT (-1e9, a large negative value) BEFORE sampling/argmax:

  training:  this module — the Python wrapper masks the policy logits
             before sampling (illegal slots softmax to ~0 probability,
             so a sampler can never draw them)
  inference: addons/godot_native_rl/controllers/action_mask.gd —
             ActionMask.apply_to_logits overwrites the same slots before
             ActionDecode's argmax/softmax in Godot

The constant is pinned across languages: rl_action_mask_check.py parses
``const ILLEGAL_LOGIT := -1.0e9`` out of action_mask.gd and asserts it
equals this module's ILLEGAL_LOGIT, so neither side can drift.

Stdlib-only and import-free of godot_rl/gymnasium/stable-baselines3, so
the functions are usable by the full trainer (see rl_connectivity_test.py)
and by the zero-dependency DoD check (rl_action_mask_check.py) alike.
Mirrors the Godot contract of ActionMask.gd: every discrete head must have
a mask entry of the head's exact size with at least one legal action (the
neutral index is always legal); an all-illegal head would argmax to slot 0
and softmax to a uniform draw — both nonsense — so it is rejected loudly
(ValueError) instead of silently applied.

Usage (DoD check): python3 rl_action_mask_check.py   (repository root)
"""

import math
import random

# The large negative value substituted for illegal logits — exactly
# representable in float32 (1e9 = 2^9 * 1953125); softmax against O(1)
# logits underflows it to 0 probability. Must equal ActionMask.ILLEGAL_LOGIT
# in addons/godot_native_rl/controllers/action_mask.gd (parity is asserted
# by rl_action_mask_check.py on every run).
ILLEGAL_LOGIT = -1.0e9


def _truth(value):
    """bool stays bool; int/float read as non-zero (the JSON wire round-trip
    turns False into 0); anything else is not a mask element -> None (invalid).
    Mirrors ActionMask._truth in Godot one-for-one."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return None


def validate_action_mask(action_mask, head_sizes):
    """True iff `action_mask` satisfies the cross-language contract for the
    discrete heads described by `head_sizes` ({head: size}):

      - every discrete head has an entry (a head the agent forgets is a
        drift bug — loud failure, not a silent full-legal fallback);
      - no unknown-head entries;
      - each entry is a sequence of the head's exact size whose elements
        are bools or 0/1 numbers (what the JSON wire round-trip produces);
      - every head keeps at least one legal action.
    """
    if not action_mask:
        return False
    for key in action_mask:
        if key not in head_sizes:
            return False
    for key, size in head_sizes.items():
        if key not in action_mask:
            return False
        values = action_mask[key]
        if not isinstance(values, (list, tuple)) or len(values) != size:
            return False
        any_legal = False
        for v in values:
            truth = _truth(v)
            if truth is None:
                return False
            if truth:
                any_legal = True
        if not any_legal:
            return False
    return True


def mask_logits(logits, mask, illegal_logit=ILLEGAL_LOGIT):
    """Copy `logits` with every illegal slot overwritten by `illegal_logit`;
    legal slots pass through untouched. Pure: `logits` is never mutated.
    Raises ValueError on a length mismatch or a non-mask element — a wrong
    mask silently applied is worse than a loud failure."""
    if len(logits) != len(mask):
        raise ValueError(
            "mask_logits: logits/mask length mismatch (%d vs %d)" % (len(logits), len(mask))
        )
    masked = list(logits)
    for i, v in enumerate(mask):
        truth = _truth(v)
        if truth is None:
            raise ValueError("mask_logits: mask[%d] is not a bool/0-1 element: %r" % (i, v))
        if not truth:
            masked[i] = illegal_logit
    return masked


def apply_action_masks(flat_logits, action_mask, head_order):
    """Flat MultiDiscrete application — the exact layout Godot's
    ActionMask.apply_to_logits walks: one contiguous segment per head in
    `head_order` (insertion order [(name, size), ...]), the sum of the
    sizes equal to len(flat_logits). Validates the mask first (loud
    ValueError, same contract as Godot's validate()) and returns a NEW
    list; `flat_logits` is never mutated."""
    head_sizes = dict(head_order)
    if not validate_action_mask(action_mask, head_sizes):
        raise ValueError("apply_action_masks: invalid action mask for heads %s" % list(head_order))
    if len(flat_logits) != sum(head_sizes.values()):
        raise ValueError(
            "apply_action_masks: flat output length %d != action space total %d"
            % (len(flat_logits), sum(head_sizes.values()))
        )
    out = list(flat_logits)
    index = 0
    for name, size in head_order:
        for i in range(size):
            if not _truth(action_mask[name][i]):
                out[index + i] = ILLEGAL_LOGIT
        index += size
    return out


def masked_softmax(logits, mask, illegal_logit=ILLEGAL_LOGIT):
    """Numerically stable softmax over the masked logits: illegal slots
    underflow to ~0 probability, legal slots keep their relative mass."""
    masked = mask_logits(logits, mask, illegal_logit)
    top = max(masked)
    exps = [math.exp(x - top) for x in masked]
    total = sum(exps)
    return [e / total for e in exps]


def argmax_masked(logits, mask):
    """Deterministic selection: the index of the largest LEGAL logit. An
    illegal slot can never win (mirrors argmax over ActionMask.apply_to_logits
    output in Godot). Raises ValueError for an all-illegal head or a bad mask."""
    best_index = -1
    best_value = None
    for i, v in enumerate(mask):
        truth = _truth(v)
        if truth is None:
            raise ValueError("argmax_masked: mask[%d] is not a bool/0-1 element: %r" % (i, v))
        if truth and (best_value is None or logits[i] > best_value):
            best_index = i
            best_value = logits[i]
    if best_index < 0:
        raise ValueError("argmax_masked: all-illegal head (the neutral index must stay legal)")
    return best_index


def sample_masked(logits, mask, rng=None, illegal_logit=ILLEGAL_LOGIT):
    """Stochastic selection: a categorical draw from the masked softmax —
    the training-time counterpart of argmax_masked (mirrors ActionDecode's
    stochastic path in Godot). `rng` (a random.Random) makes draws
    reproducible; None falls back to the global RNG."""
    probs = masked_softmax(logits, mask, illegal_logit)
    u = rng.random() if rng is not None else random.random()
    acc = 0.0
    for i, p in enumerate(probs):
        acc += p
        if u <= acc:
            return i
    # Floating-point summation can leave the cumulative just under 1.0;
    # fall back to the LAST legal slot (an illegal slot has ~0 probability
    # and can never be a meaningful sample).
    for i in range(len(mask) - 1, -1, -1):
        if _truth(mask[i]):
            return i
    raise ValueError("sample_masked: all-illegal head (the neutral index must stay legal)")


def format_decision(action, action_mask):
    """One log line carrying the chosen actions alongside their mask arrays
    (issue #423 DoD: "the mask arrays are logged alongside the chosen
    actions"): "attack=0 mask=10000000 | target=0 mask=1000 | …" — one
    `head=<chosen> mask=<bits>` pair per discrete head, head order = the
    mask dictionary's (the wire's action-space insertion order)."""
    parts = []
    for head, values in action_mask.items():
        bits = "".join("1" if _truth(v) else "0" for v in values)
        parts.append("%s=%s mask=%s" % (head, action.get(head, "?"), bits))
    return " | ".join(parts)


def log_decision(action, action_mask, logger=print):
    """Emit a format_decision line through `logger` (print by default) and
    return the line — the debug hook the training wrapper calls after every
    masked decision."""
    line = format_decision(action, action_mask)
    logger(line)
    return line
