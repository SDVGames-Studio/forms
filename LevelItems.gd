class_name LevelItems
extends Object
## Issue #364: the round drop — from the SECOND round on, ONE random
## item (first aid kit / weapon bundle / tool bundle) falls on a random
## spot of the level each round. TurnController counts the rounds (one
## round = every team acted once through the turn order) and calls the
## spawn below; the items themselves are LevelItem bodies built in code.

## The item drops from this far above the highest solid point of the
## terrain union, then gravity delivers it to the field.
const DROP_HEIGHT := 140.0
## Keep the drop this far from the left/right lips of the terrain union.
const SIDE_MARGIN := 60.0


## Issue #364: spawn one random item at a random spot of the level — a
## random x across the terrain, dropped from the sky above it. Returns
## the item, or null when the level has no measurable terrain.
static func spawn_random_item(level: Node) -> LevelItem:
	if level == null:
		return null
	var bounds: Variant = _terrain_bounds(level)
	if bounds == null:
		return null
	var area: Rect2 = bounds
	var item := LevelItem.new()
	item.kind = [LevelItem.Kind.FIRST_AID,
			LevelItem.Kind.WEAPON_BUNDLE,
			LevelItem.Kind.TOOL_BUNDLE].pick_random()
	item.global_position = Vector2(
			randf_range(area.position.x, area.end.x),
			area.position.y - DROP_HEIGHT)
	level.add_child(item)
	DebugInfo.log("a %s falls on the field" % LevelItem.kind_name(item.kind))
	return item


## Issue #364: the union rect of every solid ground (destructible and
## indestructible, slabs and discs) — the playfield an item may fall on.
## Null when the level has no grounds at all (menus, tests).
static func _terrain_bounds(level: Node) -> Variant:
	var rect: Variant = null
	for group in ["indestructible_ground", "destructible_ground"]:
		for node in level.get_tree().get_nodes_in_group(group):
			var ground := node as Node2D
			if ground == null or not is_instance_valid(ground):
				continue
			var piece := Rect2(ground.position, Vector2.ZERO)
			var rect_size = ground.get("rect_size")
			if rect_size is Vector2:
				piece = Rect2(ground.position - rect_size / 2.0, rect_size)
			else:
				var radius = ground.get("radius")
				if radius is float or radius is int:
					var r := float(radius)
					piece = Rect2(ground.position - Vector2(r, r),
							Vector2(r * 2.0, r * 2.0))
			rect = piece if rect == null else (rect as Rect2).merge(piece)
	if rect == null:
		return null
	# Margins: never drop on the very lip of the terrain union.
	return Rect2(
			(rect as Rect2).position + Vector2(SIDE_MARGIN, 0.0),
			(rect as Rect2).size - Vector2(SIDE_MARGIN * 2.0, 0.0))
