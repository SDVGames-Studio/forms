extends Node2D
## Issue #252: the tiny debug arrow — a line from the character's CENTRE
## to the TOP of the figure, ending in a small arrowhead. Drawn in code
## (no assets) and only attached while the debug mode is on
## (DebugInfo.attach / GameConfig.debug_mode).
## Issue #298: the arrow points at the figure's top, so FigurePose
## align_to_gravity rotates this node with the body — under tilted gravity
## (the radial arena, sloped grounds) the arrow tilts with the figure
## instead of pointing world-up away from the figure's actual top.

## Centre (0,0) to the top of the figure including its health bar.
const LENGTH := 64.0
const HEAD := 8.0
const WIDTH := 2.0
const COLOR := Color(1.0, 0.9, 0.3, 0.9)


func _draw() -> void:
	draw_line(Vector2.ZERO, Vector2(0.0, -LENGTH + HEAD), COLOR, WIDTH)
	# Tiny arrowhead at the top end of the line.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-HEAD * 0.75, -LENGTH + HEAD),
		Vector2(HEAD * 0.75, -LENGTH + HEAD),
		Vector2(0.0, -LENGTH),
	]), COLOR)
