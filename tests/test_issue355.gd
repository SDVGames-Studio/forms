extends Node
## Regression check for issue #355: the bot controller scaffold created from the
## editor's "NCNN AI Controller" script template.
##
## Asserts:
##   - res://scripts/BotController.gd extends NcnnAIController2D;
##   - the scaffold overrides the four required contract methods
##     (get_obs, get_reward, get_action_space, set_action);
##   - a node with the controller attached is automatically registered in
##     the "AGENT" group when the scene runs (base-class _ready).
##
## Run headless: godot --headless res://tests/test_issue355.tscn
## Exit code 0 = pass.

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []
	var controller: Script = load("res://scripts/BotController.gd")

	# Template contract: the scaffold inherits the 2D controller base.
	var base := controller.get_base_script()
	if base == null or base.resource_path != "res://addons/godot_native_rl/controllers/ncnn_ai_controller_2d.gd":
		failures.append("BotController.gd must extend NcnnAIController2D, got base %s" % str(base))

	# The four required contract methods are stubbed (overridden from the base).
	var src := controller.get_source_code()
	for m in ["get_obs", "get_reward", "get_action_space", "set_action"]:
		if not src.contains("\nfunc %s(" % m):
			failures.append("missing contract method stub: %s()" % m)

	# Runtime registration: an attached node joins the AGENT group automatically.
	var bot: Node2D = Node2D.new()
	bot.set_script(controller)
	add_child(bot)
	await get_tree().process_frame
	if not bot.is_in_group("AGENT"):
		failures.append("controller node must register in the AGENT group at runtime")
	if not (bot is NcnnAIController2D):
		failures.append("controller node must be a NcnnAIController2D")
	bot.queue_free()

	if failures.is_empty():
		print("ISSUE355 OK: bot controller scaffold registers in the AGENT group")
	else:
		for f in failures:
			print("ISSUE355 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
