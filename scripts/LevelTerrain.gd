class_name LevelTerrain
extends RefCounted
## Issue #190: terrain gravity helper.
##
## Indestructible ground is the only gravity source; gravity acceleration
## points along the normal of the NEAREST indestructible surface. Destructible
## ground never contributes gravity. Levels without authored gravity sources
## keep the legacy global-down / central-line behavior.
##
## Issue #270: slabs are now convex rounded-rect POLYGONS
## (CollisionPolygon2D) instead of RectangleShape2D — gravity toward one
## is computed as the direction to the closest point of its boundary,
## which is exact for a convex shape.


static func has_sources(figure: Node2D) -> bool:
	return figure.get_tree().get_first_node_in_group("gravity_source") != null


## Unit gravity direction at the figure's position — toward the nearest
## indestructible surface. Defaults to straight down.
static func gravity_vector(figure: Node2D) -> Vector2:
	var best_dir := Vector2.DOWN
	var best_dist := INF
	for source in figure.get_tree().get_nodes_in_group("gravity_source"):
		var body := source as Node2D
		var shape_node: Node2D = body.get_node_or_null("Shape")
		if shape_node == null:
			continue
		var local := body.to_local(figure.global_position)
		var dir: Vector2
		var dist: float
		var circle_shape := shape_node as CollisionShape2D
		var poly_shape := shape_node as CollisionPolygon2D
		var circle: CircleShape2D = null
		if circle_shape != null:
			circle = circle_shape.shape as CircleShape2D
		if circle != null:
			var offset := local
			if offset.length() < 1.0:
				dir = Vector2.DOWN
				dist = 0.0
			else:
				# Gravity along the surface normal: inward from outside,
				# outward if the figure somehow ends up inside the disc.
				dist = absf(offset.length() - circle.radius)
				dir = -offset.normalized() if offset.length() > circle.radius \
						else offset.normalized()
		elif poly_shape != null:
			# Issue #270: rounded-rect slab. The polygon points live in the
			# CollisionPolygon2D's space, which may sit below the body's
			# origin (the thickness guard extends downward).
			var closest := _closest_on_polygon(poly_shape.polygon,
					local - poly_shape.position)
			var to_surface := closest - (local - poly_shape.position)
			if to_surface.length() < 1.0:
				# Inside the slab: pull to the nearest face (outward).
				dist = 0.0
				dir = Vector2.UP
			else:
				dist = to_surface.length()
				dir = to_surface / dist
		else:
			if circle_shape == null or circle_shape.shape == null:
				continue
			var rect_shape := circle_shape.shape as RectangleShape2D
			if rect_shape == null:
				continue
			var rect := Rect2(-rect_shape.size / 2.0, rect_shape.size)
			var closest := Vector2(
					clampf(local.x, rect.position.x, rect.end.x),
					clampf(local.y, rect.position.y, rect.end.y))
			var to_surface := closest - local
			if to_surface.length() < 1.0:
				# Inside the slab: pull to the nearest face (up by convention).
				dist = 0.0
				dir = Vector2.UP
			else:
				dist = to_surface.length()
				dir = to_surface / dist
		if dist < best_dist:
			best_dist = dist
			best_dir = dir
	return best_dir


## Closest point to `p` on the boundary of a closed polygon (convex in
## practice — every slab is a rounded rect). Iterating the edges is exact
## for any convex shape.
static func _closest_on_polygon(pts: PackedVector2Array,
		p: Vector2) -> Vector2:
	if pts.is_empty():
		return p
	var best := pts[0]
	var best_d := p.distance_squared_to(pts[0])
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var ab := b - a
		var t := 0.5
		if ab.length_squared() > 0.0001:
			t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best
