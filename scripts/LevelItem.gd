class_name LevelItem
extends RigidBody2D
## Issue #364: items at the game level — first aid kits, weapon bundles
## and tool bundles dropped on the field (one per round from the second
## round on, see TurnController/LevelItems). Any character that reaches
## an item picks it up:
##  FIRST AID KIT — white square with a red cross; heals 60 HP.
##  WEAPON BUNDLE — khaki square; +1 use of a random weapon (shotgun the
##                  easiest find, railgun the hardest, spear never — it
##                  is already infinite).
##  TOOL BUNDLE   — orange square; +1 use of a random tool (switch the
##                  easiest, teleport the hardest). No bundle is ever
##                  empty.
## Every item has 1 HP: any weapon that damages it makes it explode
## with the GRENADE's radius and damage. Those two numbers are deliberate
## COPIES of Weapon.gd's GRENADE_BLAST (100) / GRENADE_DAMAGE (40) — the
## issue orders "don't connect these values, just copy them". Items obey
## the level's gravity like grenades and mines (issues #216/#293) and
## every item action goes to the action log (issue #252).
## Built in code like ProjectileBody — no scene assets.

enum Kind { FIRST_AID, WEAPON_BUNDLE, TOOL_BUNDLE }

## Issue #364: a first aid kit heals 60 HP.
const HEAL_AMOUNT := 60
## Issue #364: an item dies to a single point of damage, like a mine
## (the issue #281 rule).
const ITEM_HP := 1
## Issue #364: a detonated item bursts with the grenade's radius and
## damage — copied from Weapon.gd (GRENADE_BLAST 100.0 / GRENADE_DAMAGE
## 40) on purpose, NOT preloaded ("don't connect these values").
const BLAST_RADIUS := 100.0
const BLAST_DAMAGE := 40
## Issue #364: every item is as wide as a character (issue #270: one
## character width = the 64 px body size).
const Stats := preload("res://scripts/CharacterStats.gd")
const SIZE := Stats.BODY_SIZE
## Issue #364: a living character this close to the item's centre takes
## it — about three quarters of a character width, so a figure walking
## up to the item picks it up immediately.
const PICKUP_RADIUS := 0.75 * SIZE
## Issue #364: bundle weights, keyed by the WeaponInventory.WEAPONS /
## ToolInventory.TOOLS indices. Weapon: shotgun easiest, railgun
## hardest, spear (3) absent forever. Tool: switch easiest, teleport
## hardest. Nothing can roll "no item".
## Issue #526: the pistol joins at the mine's tier (weight 3).
## Issue #527: the baseball bat joins at the same tier (weight 3).
const WEAPON_BUNDLE_WEIGHTS := {0: 6, 1: 4, 2: 4, 4: 3, 5: 2, 6: 1, 7: 3, 8: 3}
const TOOL_BUNDLE_WEIGHTS := {0: 6, 1: 1, 2: 4, 3: 3}

const WeaponPanel := preload("res://scripts/WeaponInventory.gd")
const ToolState := preload("res://scripts/ToolInventory.gd")
const ProjectileBodyScript := preload("res://scripts/ProjectileBody.gd")

var kind: int = Kind.FIRST_AID
var _hp := ITEM_HP
var _picked := false
var _exploded := false


## Issue #364: human name of an item kind (action log).
static func kind_name(k: int) -> String:
	match k:
		Kind.FIRST_AID:
			return "first aid kit"
		Kind.WEAPON_BUNDLE:
			return "weapon bundle"
		_:
			return "tool bundle"


## Issue #364: the weapon inside a weapon bundle — weighted roll over
## every weapon EXCEPT the spear; shotgun is the easiest find, the
## railgun the hardest, "nothing" impossible.
static func roll_weapon() -> int:
	return _weighted_pick(WEAPON_BUNDLE_WEIGHTS)


## Issue #364: the tool inside a tool bundle — switch is the easiest
## find, the teleport the hardest, "nothing" impossible.
static func roll_tool() -> int:
	return _weighted_pick(TOOL_BUNDLE_WEIGHTS)


## Weighted pick over {index: weight} — a roll of 1..total walks the
## table and lands on one key with exactly its share of the chance.
static func _weighted_pick(weights: Dictionary) -> int:
	var total := 0
	for weight in weights.values():
		total += int(weight)
	var roll := randi_range(1, total)
	for key in weights:
		roll -= int(weights[key])
		if roll <= 0:
			return int(key)
	return int(weights.keys()[0])


func _ready() -> void:
	# Issue #364: explosions find items through this group — the same
	# chain rule the mines use (issue #281).
	add_to_group("level_items")
	# Layer 4 (projectiles) like the mine, so rockets and pellets can
	# also detonate an item with a direct hit.
	collision_layer = 4
	# Issue #374: the item must collide with other objects — the world
	# terrain (1), BOTH teams' characters (2 = NPCs, 8 = players) and
	# everything else on layer 4 (other items, mines, projectiles). A
	# pair forms when either body masks the other, so no other file has
	# to grow a mask bit; characters still take the item through
	# PICKUP_RADIUS, and contact with a figure now picks it up too (see
	# _on_body_entered) so a bundle landing on someone never balances on
	# a head just outside the radius.
	collision_mask = 1 | 2 | 4 | 8
	gravity_scale = 0.0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.2
	physics_material_override = mat
	# Issue #374: two 64 px bodies touch at about SIZE px between
	# centres, which is OUTSIDE the 0.75 * SIZE pickup radius — watch
	# contacts so a resting touch with a character still takes the item.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(SIZE, SIZE)
	shape.shape = rect
	add_child(shape)
	_build_visual()


## Issue #364: a plain square per kind, drawn in code — white with a red
## cross (first aid), khaki (weapons), orange (tools).
func _build_visual() -> void:
	var base := ColorRect.new()
	base.offset_left = -SIZE / 2.0
	base.offset_top = -SIZE / 2.0
	base.offset_right = SIZE / 2.0
	base.offset_bottom = SIZE / 2.0
	base.color = Color(0.95, 0.95, 0.95, 1)
	if kind == Kind.WEAPON_BUNDLE:
		base.color = Color(0.55, 0.5, 0.28, 1)
	elif kind == Kind.TOOL_BUNDLE:
		base.color = Color(1.0, 0.55, 0.1, 1)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	if kind == Kind.FIRST_AID:
		var cross := Color(0.85, 0.1, 0.1, 1)
		var hbar := ColorRect.new()
		hbar.offset_left = -20.0
		hbar.offset_top = -6.0
		hbar.offset_right = 20.0
		hbar.offset_bottom = 6.0
		hbar.color = cross
		hbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hbar)
		var vbar := ColorRect.new()
		vbar.offset_left = -6.0
		vbar.offset_top = -20.0
		vbar.offset_right = 6.0
		vbar.offset_bottom = 20.0
		vbar.color = cross
		vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vbar)

## Issue #374: the item now physically collides with characters, so a
## falling bundle can come to rest ON a figure — bodies touch at about
## SIZE px between centres while PICKUP_RADIUS is only 0.75 * SIZE.
## Treat contact with a LIVING character exactly like the proximity
## loop in _physics_process: the touching figure takes the item.
func _on_body_entered(body: Node2D) -> void:
	if _picked or _exploded:
		return
	for group in ["player_team", "enemy_team"]:
		if body.is_in_group(group):
			var hp = body.get("health")
			if hp is int and hp > 0:
				_pickup(body)
			return


func _physics_process(_delta: float) -> void:
	if _picked or _exploded:
		return
	# Issue #364: any LIVING character of either team that reaches the
	# item takes it — a proximity check every physics frame, like the
	# mine's trigger in ProjectileBody, so figures pick bundles up
	# mid-stride without needing to collide with them.
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or not is_instance_valid(body):
				continue
			var hp = body.get("health")
			if hp is int and hp > 0 \
					and body.global_position.distance_to(global_position) \
					<= PICKUP_RADIUS:
				_pickup(body)
				return


## Issue #364: hand the item's effect to the taker. First aid heals the
## FIGURE (+60, capped at MAX_HEALTH); bundles add +1 use of the rolled
## weapon/tool to the taker's TEAM budget. Every pickup is logged.
func _pickup(taker: Node2D) -> void:
	if _picked or _exploded:
		return
	_picked = true
	var who: Variant = "someone"
	if taker.get("display_name") != null:
		who = taker.get("display_name")
	var team := TurnController.team_id_of(taker)
	match kind:
		Kind.FIRST_AID:
			if taker.has_method("heal"):
				taker.heal(HEAL_AMOUNT)
			DebugInfo.log("%s takes a first aid kit (+%d HP)"
					% [str(who), HEAL_AMOUNT])
		Kind.WEAPON_BUNDLE:
			var weapon := roll_weapon()
			WeaponInventory.grant_weapon(team, weapon)
			DebugInfo.log("%s found a weapon bundle: %s +1"
					% [str(who), WeaponPanel.WEAPONS[weapon]])
		_:
			var tool := roll_tool()
			WeaponInventory.grant_tool(team, tool)
			DebugInfo.log("%s found a tool bundle: %s +1"
					% [str(who), ToolState.TOOLS[tool]])
	queue_free()


## Issue #364 (mine rule of #281): one point of damage is all it takes.
## The optional attacker argument accepts every caller shape — blasts
## pass only the amount, pellets pass the shooter as well.
func take_damage(_amount: int, _attacker: Node2D = null) -> void:
	if _exploded or _picked:
		return
	_hp -= maxi(1, _amount)
	if _hp <= 0:
		_explode()


## Issue #364: the grenade blast copy — same behaviour as a grenade
## detonation (ProjectileBody._explode): destructible ground carves,
## every figure in the radius takes BLAST_DAMAGE, other 1-HP objects
## (mines, items) chain-detonate, and a fading blast ring shows the
## radius as a live turn effect (issue #244).
func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	DebugInfo.log("a %s explodes" % kind_name(kind))
	for ground in get_tree().get_nodes_in_group("destructible_ground"):
		ground.apply_blast(global_position, BLAST_RADIUS)
	var targets: Array = []
	targets.append_array(get_tree().get_nodes_in_group("player_team"))
	targets.append_array(get_tree().get_nodes_in_group("enemy_team"))
	for node in targets:
		var body := node as Node2D
		if body != null and body.has_method("take_damage") \
				and body.global_position.distance_to(global_position) \
				<= BLAST_RADIUS:
			body.take_damage(BLAST_DAMAGE)
	for group in ["mines", "level_items"]:
		for node in get_tree().get_nodes_in_group(group):
			var other := node as Node2D
			if other == null or other == self or not is_instance_valid(other):
				continue
			if other.has_method("take_damage") \
					and other.global_position.distance_to(global_position) \
					<= BLAST_RADIUS:
				other.take_damage(BLAST_DAMAGE)
	var ring := ProjectileBodyScript.BlastRing.new()
	ring.radius = BLAST_RADIUS
	ring.position = global_position
	ring.z_index = 50
	ring.add_to_group("turn_effects")
	if get_parent() != null:
		get_parent().add_child(ring)
	queue_free()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Issue #364: items are subject to gravity — the LEVEL's gravity,
	# exactly the ladder the grenades follow (issues #216/#293).
	state.linear_velocity += _level_gravity() * Stats.GRAVITY * state.step


func _level_gravity() -> Vector2:
	if LevelTerrain.has_sources(self):
		return LevelTerrain.gravity_vector(self)
	return Vector2.DOWN
