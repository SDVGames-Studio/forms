extends Node
## Regression check for issue #258: rework levels 1-4 so the minimum
## distance between separated indestructible grounds is 6 character
## widths (the figure visual is 64 px wide -> 384 px) in BOTH axes:
##
##  - horizontally separated grounds (disjoint x spans): edge-to-edge
##    horizontal gap >= 384 px;
##  - vertically stacked grounds (overlapping x spans, disjoint y spans):
##    edge-to-edge vertical gap >= 384 px (owner rework 2026-11-02:
##    "level 4 - vertical distance between grounds is still small");
##  - grounds whose rects actually intersect (e.g. the level-1 hill
##    embedded in its floor) are connected, not separated - exempt.
##
## Run headless: godot --headless res://tests/test_issue258.tscn
## Exit code 0 = pass.

const CHAR_WIDTH := 64.0
const MIN_GAP := 6.0 * CHAR_WIDTH
const LEVELS := [
	"res://scenes/levels/Level.tscn",
	"res://scenes/levels/Level2.tscn",
	"res://scenes/levels/Level3.tscn",
	"res://scenes/levels/Level4.tscn",
]


func _ready() -> void:
	var ok := true
	for level_path in LEVELS:
		var level: Node = load(level_path).instantiate()
		add_child(level)
		# Let _ready build the ground shapes and register the groups.
		await get_tree().physics_frame

		var grounds := get_tree().get_nodes_in_group("indestructible_ground")
		var boxes := []  # [x_min, y_min, x_max, y_max] per ground, level coords.
		for ground in grounds:
			var body := ground as Node2D
			var radius := float(body.get("radius"))
			var box := [body.position.x, body.position.y, body.position.x, body.position.y]
			if radius > 0.0:
				box[0] -= radius
				box[1] -= radius
				box[2] += radius
				box[3] += radius
			else:
				var rect: Vector2 = body.get("rect_size")
				box[0] -= rect.x / 2.0
				box[1] -= rect.y / 2.0
				box[2] += rect.x / 2.0
				box[3] += rect.y / 2.0
			boxes.append(box)

		var min_h := INF
		var min_v := INF
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var a: Array = boxes[i]
				var b: Array = boxes[j]
				var x_overlap: bool = a[0] < b[2] and b[0] < a[2]
				var y_overlap: bool = a[1] < b[3] and b[1] < a[3]
				if x_overlap and y_overlap:
					continue  # intersecting = connected, not separated
				if x_overlap:
					# Stacked grounds: vertical edge-to-edge gap.
					min_v = minf(min_v, maxf(b[1] - a[3], a[1] - b[3]))
				else:
					# Side-by-side grounds: horizontal edge-to-edge gap.
					min_h = minf(min_h, maxf(b[0] - a[2], a[0] - b[2]))

		var level_ok := grounds.size() > 0 \
				and (min_h == INF or min_h >= MIN_GAP - 0.5) \
				and (min_v == INF or min_v >= MIN_GAP - 0.5)
		print("ISSUE258 ", level_path, " grounds=", grounds.size(),
				" min_h_gap=", min_h, " min_v_gap=", min_v, " ok=", level_ok)
		ok = ok and level_ok

		level.queue_free()
		await get_tree().physics_frame

	print("ISSUE258 ok=", ok)
	get_tree().quit(0 if ok else 1)
