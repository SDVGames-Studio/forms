extends Node
## Issue #649: the LAN game menu rework — the NICKNAME requirement in
## the LAN menu, the LanSession autoload (peer + roster + the setup
## broadcast plumbing), and the level setup menu's shared-lobby
## behavior: the per-team driver options become Computer / <host> /
## <connected players> (host picks), and only a team's assigned driver
## may edit it.
##
## Run headless: godot --headless res://tests/test_issue649.tscn
## Exit code 0 = pass; the printed 649 verdicts are authoritative.

const PORT := 24599


func _ready() -> void:
	var driver := Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Driver extends Node:
	signal done(ok: bool)

	var _settings_backup: PackedByteArray = PackedByteArray()
	var _had_settings := false

	func run() -> void:
		var ok := true
		_backup()
		var phase_ok := await _phase_nickname_required()
		ok = phase_ok and ok
		phase_ok = await _phase_host_lobby()
		ok = phase_ok and ok
		phase_ok = await _phase_client_guard()
		ok = phase_ok and ok
		phase_ok = await _phase_offline_rows()
		ok = phase_ok and ok
		_restore()
		if ok:
			print("649 ok")
		else:
			print("649 FAIL")
		done.emit(ok)


## The LAN menu must refuse to host without a nickname (issue #649:
## the nickname is the player's identity in the shared lobby).
	func _phase_nickname_required() -> bool:
		var menu = load("res://scenes/menus/LanMenu.tscn").instantiate()
		get_tree().root.add_child.call_deferred(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		var failures: Array[String] = []
		var nick: LineEdit = menu.get_node("Layout/Columns/Nav/NicknameEdit")
		var status: Label = menu.get_node("Layout/Columns/Nav/StatusLabel")
		nick.text = "   "
		menu._on_host_pressed()
		if LanSession.active:
			failures.append("hosting started without a nickname")
		if not nick.visible:
			failures.append("setup controls hidden although hosting was refused")
		if not status.text.to_lower().contains("nickname"):
			failures.append("status does not ask for the nickname: %s" % status.text)
		menu._on_connect_pressed()
		if LanSession.active:
			failures.append("connecting started without a nickname")
		menu.queue_free()
		return _verdict("nickname-required", failures)


## Hosting opens the shared lobby: the roster carries the host's
## nickname, the driver drop-down offers Computer/<host nick> (host
## picks, nothing disabled), the assignment lands in LanSession, and
## only a team's driver may edit it — a remote edit reaches the host
## with the driver choice untouchable.
	func _phase_host_lobby() -> bool:
		var failures: Array[String] = []
		if not LanSession.host_game(PORT, "HostNick"):
			failures.append("could not host on port %d" % PORT)
		if not LanSession.active or not LanSession.is_host:
			failures.append("session not active as host")
		var parts := LanSession.participants()
		if parts.size() != 1 or int(parts[0]["peer"]) != 1 \
				or str(parts[0]["nick"]) != "HostNick":
			failures.append("roster wrong: %s" % str(parts))
		if LanSession.saved_nickname() != "HostNick":
			failures.append("nickname not persisted")
		var menu = load("res://scenes/menus/LevelConfigMenu.tscn").instantiate()
		get_tree().root.add_child.call_deferred(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var rows: VBoxContainer = menu.get_node(
			"Layout/Columns/Nav/TeamsPanel/TeamsBox/TeamsScroll/TeamsList")
		if rows.get_child_count() < 2:
			failures.append("no team rows in the lobby")
		else:
			var controller := _controller_of(rows.get_child(0))
			if controller == null:
				failures.append("row has no driver drop-down")
			else:
				if controller.item_count != 2 \
						or controller.get_item_text(0) != "Computer" \
						or controller.get_item_text(1) != "HostNick":
					failures.append("LAN driver options wrong")
				if controller.disabled:
					failures.append("host's driver picker disabled")
				if not menu._start_button.visible:
					failures.append("host lost the START button")
				# The host assigns themselves to team 0.
				controller.select(1)
				controller.emit_signal("item_selected", 1)
				await get_tree().process_frame
				if GameConfig.team_controller(0) != "player":
					failures.append("assignment did not make team 0 player-driven")
				if LanSession.team_peer(0) != 1:
					failures.append("assignment not recorded in LanSession")
		if not menu._can_edit_team(0):
			failures.append("host cannot edit a team")
		# Outside an RPC the sender id is 0 — pose as the assigned
		# driver and hand the host an edit; the driver choice itself
		# must survive it.
		LanSession.team_peers[0] = 0
		var team: Dictionary = GameConfig.teams[0].duplicate(true)
		team["label"] = "RemoteEdit"
		team["controller"] = "computer"
		LanSession._request_team_change(0, team)
		if str(GameConfig.teams[0]["label"]) != "RemoteEdit":
			failures.append("driver's edit not applied by the host")
		if GameConfig.team_controller(0) != "player":
			failures.append("driver choice overridden by an edit")
		menu.queue_free()
		LanSession.shutdown()
		if LanSession.active:
			failures.append("shutdown left the session alive")
		return _verdict("host-lobby", failures)


	## A connected player edits exactly the team assigned to them:
	## simulate the client's menu (only the session flags — the wire
	## itself is the next step of the LAN series).
	func _phase_client_guard() -> bool:
		LanSession.active = true
		LanSession.is_host = false
		LanSession.team_peers = {0: LanSession.my_peer_id()}
		var menu = load("res://scenes/menus/LevelConfigMenu.tscn").instantiate()
		get_tree().root.add_child.call_deferred(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var failures: Array[String] = []
		if menu._start_button.visible:
			failures.append("client sees the host's START button")
		if not menu._level_option.disabled:
			failures.append("client may pick the level")
		if not menu._add_team_button.disabled:
			failures.append("client may add teams")
		var rows: VBoxContainer = menu.get_node(
			"Layout/Columns/Nav/TeamsPanel/TeamsBox/TeamsScroll/TeamsList")
		var controller := _controller_of(rows.get_child(0))
		if controller == null or not controller.disabled:
			failures.append("client's driver picker is enabled")
		if not menu._can_edit_team(0):
			failures.append("assigned driver cannot edit their team")
		LanSession.team_peers[0] = 777
		if menu._can_edit_team(0):
			failures.append("a foreign peer may edit a team")
		menu.queue_free()
		LanSession.shutdown()
		return _verdict("client-guard", failures)

## Offline the menu keeps its classic Computer/Player controller pair.
	func _phase_offline_rows() -> bool:
		var menu = load("res://scenes/menus/LevelConfigMenu.tscn").instantiate()
		get_tree().root.add_child.call_deferred(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var failures: Array[String] = []
		var rows: VBoxContainer = menu.get_node(
			"Layout/Columns/Nav/TeamsPanel/TeamsBox/TeamsScroll/TeamsList")
		var controller := _controller_of(rows.get_child(0))
		if controller == null or controller.item_count != 2 \
				or controller.get_item_text(0) != "Computer" \
				or controller.get_item_text(1) != "Player":
			failures.append("offline controller options wrong")
		elif controller.disabled:
			failures.append("offline controller disabled")
		menu.queue_free()
		return _verdict("offline-rows", failures)


	func _controller_of(row: Node) -> OptionButton:
		for child in row.get_children():
			if child is OptionButton:
				return child
		return null


	func _verdict(phase: String, failures: Array[String]) -> bool:
		if failures.is_empty():
			print("649 %s ok" % phase)
			return true
		for failure in failures:
			push_error("649 %s FAIL: %s" % [phase, failure])
		return false


	func _backup() -> void:
		var file := FileAccess.open(LanSession.SETTINGS_PATH, FileAccess.READ)
		if file != null:
			_settings_backup = file.get_buffer(file.get_length())
			_had_settings = true


	func _restore() -> void:
		if _had_settings:
			var file := FileAccess.open(LanSession.SETTINGS_PATH, FileAccess.WRITE)
			file.store_buffer(_settings_backup)
		else:
			DirAccess.remove_absolute(LanSession.SETTINGS_PATH)
