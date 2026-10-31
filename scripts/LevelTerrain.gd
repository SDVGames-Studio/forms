class_name LevelTerrain
extends RefCounted
## Issue #190: terrain gravity helper.
##
## Indestructible ground is the only gravity source; gravity acceleration
## points along the normal of the NEAREST indestructible surface. Destructible
## ground never contributes gravity. Levels without authored gravity sources
## keep the legacy global-down / central-line behavior.

static func has_sources(figure: Node2D) -> bool:
	return figure.get_tree().get_first_node_in_group("gravity_source") != null


## Unit gravity direction at the figure's position — toward the nearest
## indestructible surface. Defaults to straight down.
static func gravity_vector(figure: Node2D) -> Vector2:
	var best_dir := Vector2.DOWN
	var best_dist := INF
	for source in figure.get_tree().get_nodes_in_group("gravity_source"):
		var body := source as Node2D
		var shape_node := body.get_node_or_null("Shape") as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var local := body.to_local(figure.global_position)
		var dir: Vector2
		var dist: float
		var circle := shape_node.shape as CircleShape2D
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
		else:
			var rect_shape := shape_node.shape as RectangleShape2D
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
