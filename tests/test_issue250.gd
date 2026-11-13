extends Node
## Regression check for issue #250: the circular arena level.
##
## The level's indestructible ground is a circle with a radius of 10
## character widths (the figure visual is 64 px wide -> radius 640), the
## destructible part is an external ring layer with an outer radius of
## 20 character widths (1280), and three teams are staged by default.
##
## Run headless: godot --headless res://tests/test_issue250.tscn
## Exit code 0 = pass.

const CHAR_WIDTH := 64.0
const ARENA_CENTER := Vector2(1280, 1280)

const LEVEL := preload("res://scenes/levels/Level5.tscn")


func _ready() -> void:
	var ok := true
	var level := LEVEL.instantiate()
	add_child(level)
	# Let _ready + GameConfig.apply (deferred queue_frees) settle.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- Indestructible core: one gravity source, a circle of 10 widths. ---
	var sources := get_tree().get_nodes_in_group("gravity_source")
	var core: Node = sources[0] if sources.size() == 1 else null
	var core_ok: bool = core != null \
			and core.get("radius") == 10.0 * CHAR_WIDTH
	print("ISSUE250 core_sources=", sources.size(), " radius10w=", core_ok)
	ok = ok and core_ok

	# --- Destructible ring: external layer, outer radius 20 widths. ---
	var chunks := get_tree().get_nodes_in_group("destructible_ground")
	var ring_ok := chunks.size() == 24
	var outer_ok := true
	var inner_ok := true
	for chunk in chunks:
		outer_ok = outer_ok and chunk.get("ring_outer") == 20.0 * CHAR_WIDTH
		inner_ok = inner_ok and chunk.get("ring_inner") == 10.0 * CHAR_WIDTH
	var ring_node := level.get_node_or_null("Ring")
	var container_ok := ring_node != null and ring_node.get_child_count() == 24 \
			and not ring_node.is_in_group("destructible_ground")
	print("ISSUE250 ring_chunks=", chunks.size(), " inner10w=", inner_ok,
			" outer20w=", outer_ok, " container=", container_ok)
	ok = ok and ring_ok and outer_ok and inner_ok and container_ok

	# --- Three teams by default (issue #208 team staging conventions). ---
	await get_tree().physics_frame
	var player_count := get_tree().get_nodes_in_group("player_team").size()
	var enemy_colors := {}
	for member in get_tree().get_nodes_in_group("enemy_team"):
		var body := member as Node2D
		if is_instance_valid(body):
			enemy_colors[body.get("team_color")] = true
	var teams_ok := player_count == 3 and enemy_colors.size() == 2
	print("ISSUE250 player_team=", player_count,
			" enemy_teams=", enemy_colors.size())
	ok = ok and teams_ok

	# --- A blast carves the ring chunk by chunk (issue #250 rework: pieces
	# inside the blast CIRCLE are removed, so the crater actually OPENS;
	# remainders are angular/radial halves; the far side stays solid). ---
	var top: Node = null
	var top_off := 999.0
	for chunk in get_tree().get_nodes_in_group("destructible_ground"):
		var off := absf(wrapf(float(chunk.get("arc_center")) + PI / 2.0, -PI, PI))
		if off < top_off:
			top_off = off
			top = chunk
	var blast_point := ARENA_CENTER + Vector2(0, -960.0)
	var top_found := top != null and top_off < 0.2
	if top_found:
		# The real explosions (Projectile/ProjectileBody._explode) carve EVERY
		# destructible chunk — the point sits on a sector boundary, so a
		# single-chunk blast would leave the neighbor solid.
		for chunk in get_tree().get_nodes_in_group("destructible_ground"):
			chunk.call("apply_blast", blast_point, 100.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after := get_tree().get_nodes_in_group("destructible_ground")
	var top_gone := not is_instance_valid(top)
	var count_changed := after.size() != 24
	var radial_split := false
	for chunk in after:
		if chunk.get("ring_inner") == 960.0 \
				or chunk.get("ring_outer") == 960.0:
			radial_split = true
			break
	# A ring point is "covered" while some remaining chunk's band and arc
	# contain its polar coordinates around the arena centre.
	var covered := func(p: Vector2) -> bool:
		var local := p - ARENA_CENTER
		var r := local.length()
		var a := local.angle()
		for chunk in after:
			if r >= float(chunk.get("ring_inner")) \
					and r <= float(chunk.get("ring_outer")) \
					and absf(wrapf(a - float(chunk.get("arc_center")), -PI, PI)) \
							<= float(chunk.get("arc_span")) / 2.0:
				return true
		return false
	var crater_open: bool = not bool(covered.call(blast_point))
	var far_side_kept: bool = bool(covered.call(ARENA_CENTER + Vector2(0, 960.0)))
	print("ISSUE250 carve top_gone=", top_gone, " top_found=", top_found,
			" top_off=", top_off, " chunks_after=", after.size(),
			" radial_split=", radial_split, " crater_open=", crater_open,
			" far_side_kept=", far_side_kept)
	ok = ok and top_found and top_gone \
			and count_changed and radial_split and crater_open and far_side_kept

	print("ISSUE250 ok=", ok)
	get_tree().quit(0 if ok else 1)
