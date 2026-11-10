extends Node
## Regression check for issue #446: TeamBlackboard centralizes the shared
## team state — focus target, team average HP, living ally/enemy counts
## and known enemy positions — keyed by TurnController team id. The board
## is refreshed from plain alive-figure arrays (once per turn, from the
## game logic), keeps its focus target while it still lives, and a real
## Npc agent reads the shared focus target through its OWN team id alone
## (never a reference to another bot); reset_blackboard() wipes everything.
##
## Run headless: godot --headless res://tests/test_issue446.tscn
## Exit code 0 = pass.

const Npc := preload("res://Npc.gd")


## Minimal figure stand-in: alive (health > 0), teamable, positionable.
class FakeFigure extends Node2D:
	var health := 50


func _ready() -> void:
	var ok := true
	TeamBlackboard.reset_blackboard()

	# --- Board fields update from the passed alive-figure arrays. ---
	var ally_a := FakeFigure.new()
	ally_a.health = 60
	ally_a.position = Vector2(100.0, 0.0)
	add_child(ally_a)
	var ally_b := FakeFigure.new()
	ally_b.health = 20
	ally_b.position = Vector2(300.0, 0.0)
	add_child(ally_b)
	var near := FakeFigure.new()
	near.position = Vector2(700.0, 0.0)
	add_child(near)
	var far := FakeFigure.new()
	far.position = Vector2(1200.0, 0.0)
	add_child(far)

	TeamBlackboard.update_team("enemy", [ally_a, ally_b], [near, far])
	ok = _expect(TeamBlackboard.get_living_allies("enemy") == 2,
			"living allies = 2, got %s" % TeamBlackboard.get_living_allies("enemy")) and ok
	ok = _expect(TeamBlackboard.get_living_enemies("enemy") == 2,
			"living enemies = 2, got %s" % TeamBlackboard.get_living_enemies("enemy")) and ok
	ok = _expect(is_equal_approx(TeamBlackboard.get_team_hp_avg("enemy"), 40.0),
			"team hp avg = 40, got %s" % TeamBlackboard.get_team_hp_avg("enemy")) and ok
	ok = _expect(TeamBlackboard.get_known_enemy_positions("enemy").size() == 2,
			"known enemy positions = 2, got %s"
					% TeamBlackboard.get_known_enemy_positions("enemy").size()) and ok
	# Ally centroid is (200, 0): `near` (700) beats `far` (1200).
	ok = _expect(TeamBlackboard.get_focus_target("enemy") == near,
			"focus target is the nearest living enemy") and ok

	# --- The focus target is RETAINED while it still lives. ---
	TeamBlackboard.update_team("enemy", [ally_a, ally_b], [near, far])
	ok = _expect(TeamBlackboard.get_focus_target("enemy") == near,
			"living focus target retained across updates") and ok

	# --- It dies: the next update reassigns and drops the corpse. ---
	near.health = 0
	TeamBlackboard.update_team("enemy", [ally_a, ally_b], [near, far])
	ok = _expect(TeamBlackboard.get_focus_target("enemy") == far,
			"dead focus target reassigned to the survivor") and ok
	ok = _expect(TeamBlackboard.get_living_enemies("enemy") == 1,
			"dead enemy no longer counted, got %s"
					% TeamBlackboard.get_living_enemies("enemy")) and ok

	# --- An agent reads the shared focus target with its team id ALONE ---
	# --- (no reference to any other bot) — a real Npc on the "enemy" side. ---
	var npc: CharacterBody2D = Npc.new()
	add_child(npc)  # default team "enemy" -> group "enemy_team"
	var closer := FakeFigure.new()
	closer.position = Vector2(200.0, 0.0)
	closer.add_to_group("player_team")
	add_child(closer)
	var farther := FakeFigure.new()
	farther.position = Vector2(500.0, 0.0)
	farther.add_to_group("player_team")
	add_child(farther)
	var mate := FakeFigure.new()
	mate.position = Vector2(600.0, 0.0)
	mate.add_to_group("enemy_team")
	add_child(mate)

	# Team centroid (600, 0) makes `farther` the assigned focus target,
	# even though `closer` is nearer to the Npc at (0, 0).
	TeamBlackboard.update_team("enemy", [mate], [closer, farther])
	ok = _expect(TeamBlackboard.get_focus_target("enemy") == farther,
			"focus assigned nearest to ally centroid") and ok
	ok = _expect(npc._nearest_opponent() == farther,
			"npc reads the shared focus target via team id only") and ok

	# --- reset_blackboard() wipes every field back to defaults. ---
	TeamBlackboard.reset_blackboard()
	ok = _expect(TeamBlackboard.get_focus_target("enemy") == null,
			"reset clears the focus target") and ok
	ok = _expect(TeamBlackboard.get_team_hp_avg("enemy") == 0.0
			and TeamBlackboard.get_living_allies("enemy") == 0
			and TeamBlackboard.get_living_enemies("enemy") == 0,
			"reset clears hp avg and living counts") and ok
	ok = _expect(TeamBlackboard.get_known_enemy_positions("enemy").is_empty(),
			"reset clears known enemy positions") and ok
	# With an empty board the Npc falls back to its own nearest scan.
	ok = _expect(npc._nearest_opponent() == closer,
			"empty board falls back to the nearest scan") and ok

	print("ISSUE446 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
