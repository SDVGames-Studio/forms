extends Node
## Regression check for issue #258: rework levels 1-4 so the minimum
## horizontal distance between separated indestructible grounds is
## 6 character widths (the figure visual is 64 px wide -> 384 px).
##
## Two indestructible grounds are "separated" when their horizontal spans
## do not overlap — the edge-to-edge gap a figure would have to cross.
## Grounds stacked above each other (overlapping spans, e.g. floating
## platforms over a level-wide floor) are connected by the floor and do
## not count as separated.
##
## Run headless: godot --headless res://tests/test_issue258.tscn
## Exit code 0 = pass.

const CHAR_WIDTH := 64.0
const MIN_GAP := 6.0 * CHAR_WIDTH
const LEVELS := [
	"res://Level.tscn",
	"res://Level2.tscn",
	"res://Level3.tscn",
	"res://Level4.tscn",
]


func _ready() -> void:
	var ok := true
	for level_path in LEVELS:
		var level: Node = load(level_path).instantiate()
		add_child(level)
		# Let _ready build the ground shapes and register the groups.
		await get_tree().physics_frame

		var grounds := get_tree().get_nodes_in_group("indestructible_ground")
		var spans := []  # [x_min, x_max] per ground, level coordinates.
		for ground in grounds:
			var body := ground as Node2D
			var radius := float(body.get("radius"))
			var x_min := body.position.x
			var x_max := body.position.x
			if radius > 0.0:
				x_min -= radius
				x_max += radius
			else:
				var rect: Vector2 = body.get("rect_size")
				x_min -= rect.x / 2.0
				x_max += rect.x / 2.0
			spans.append([x_min, x_max])

		var min_gap := INF
		for i in spans.size():
			for j in range(i + 1, spans.size()):
				# Overlapping horizontal spans = stacked, not separated.
				if spans[i][0] < spans[j][1] and spans[j][0] < spans[i][1]:
					continue
				var gap: float = maxf(spans[j][0] - spans[i][1],
						spans[i][0] - spans[j][1])
				min_gap = minf(min_gap, gap)

		var level_ok := grounds.size() > 0 and min_gap >= MIN_GAP - 0.5
		print("ISSUE258 ", level_path, " grounds=", grounds.size(),
				" min_gap=", min_gap, " ok=", level_ok)
		ok = ok and level_ok

		level.queue_free()
		await get_tree().physics_frame

	print("ISSUE258 ok=", ok)
	get_tree().quit(0 if ok else 1)
