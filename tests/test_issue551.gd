extends Node
## Issue #551 (step 1): the LAN lobby menu. The main menu offers a LAN
## GAME entry that opens LanMenu; the lobby can HOST (a real ENet
## server peer) and CONNECT to a host — verified over a REAL loopback
## ENet connection between two subtrees, each with its own
## SceneMultiplayer, in this one process. Leaving the screen closes
## the peer (no socket leaks).
##
## Run headless: godot --headless res://tests/test_issue551.tscn
## Exit code 0 = pass; the printed LAN ok= verdict is authoritative.

func _ready() -> void:
	# The driver must survive the scene changes it provokes, so it lives
	# directly under /root — change_scene_to_file only frees current_scene.
	# (The driver itself calls quit() when done: a lambda bound to THIS
	# scene's script instance would die with the scene change mid-test.)
	var driver := LanLobbyDriver.new()
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class LanLobbyDriver extends Node:

	const PORT := 24565

	func run() -> void:
		var ok := true

		# --- Main menu: the LAN GAME entry exists and opens LanMenu. ---
		var main: Node = load("res://scenes/Main.tscn").instantiate()
		add_child(main)
		await get_tree().process_frame
		var lan_button: Button = main.get_node_or_null("%LanGameButton")
		var entry_ok: bool = lan_button != null \
			and lan_button.text == "LAN GAME"
		print("LAN entry=", entry_ok)
		ok = ok and entry_ok
		main._on_lan_pressed()
		await get_tree().process_frame
		await get_tree().process_frame
		var navigated: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path \
			== "res://scenes/menus/LanMenu.tscn"
		print("LAN nav=", navigated)
		ok = ok and navigated

		# --- The lobby itself: host + join over a real loopback ENet
		# connection. Each subtree gets its own MultiplayerAPI so a real
		# client can connect to a real server in one process.
		var host_root := Node.new()
		host_root.name = "HostRoot"
		add_child(host_root)
		var client_root := Node.new()
		client_root.name = "ClientRoot"
		add_child(client_root)
		var host_api := SceneMultiplayer.new()
		var client_api := SceneMultiplayer.new()
		get_tree().set_multiplayer(host_api, host_root.get_path())
		get_tree().set_multiplayer(client_api, client_root.get_path())
		var host_menu: Node = \
			load("res://scenes/menus/LanMenu.tscn").instantiate()
		host_root.add_child(host_menu)
		var client_menu: Node = \
			load("res://scenes/menus/LanMenu.tscn").instantiate()
		client_root.add_child(client_menu)
		await get_tree().process_frame

		host_menu.get_node("%HostButton").pressed.emit()
		var hosting: bool = host_api.multiplayer_peer is ENetMultiplayerPeer \
			and host_api.is_server()
		print("LAN host=", hosting)
		ok = ok and hosting

		client_menu.get_node("%AddressEdit").text = "127.0.0.1"
		client_menu.get_node("%PortEdit").text = str(PORT)
		client_menu.get_node("%ConnectButton").pressed.emit()

		# ENet polls once per frame; a loopback connect settles fast.
		var connected := false
		for _i in range(180):
			await get_tree().process_frame
			if host_api.get_peers().size() > 0 \
					and client_api.get_peers().size() > 0:
				connected = true
				break
		# One more frame so the menus' signal handlers settle.
		await get_tree().process_frame
		var status_label: Label = client_menu.get_node("%StatusLabel")
		var host_players: Label = host_menu.get_node("%PlayersLabel")
		var join_ok: bool = connected \
			and "Connected to the host" in status_label.text \
			and host_players.text == "PLAYERS: 2"
		print("LAN join=", join_ok, " connected=", connected,
			" players=", host_players.text)
		ok = ok and join_ok

		# --- Leaving the screen closes the peer (no socket leaks). The
		# host closing also takes the client back offline (its menu
		# resets its own peer on server_disconnected).
		host_root.queue_free()
		var closed := false
		for _i in range(120):
			await get_tree().process_frame
			if host_api.multiplayer_peer is OfflineMultiplayerPeer \
					and client_api.multiplayer_peer is OfflineMultiplayerPeer:
				closed = true
				break
		print("LAN cleanup=", closed)
		ok = ok and closed

		print("LAN ok=", ok)
		# The driver lives under /root and is still alive here, so its quit
		# reliably terminates the headless run.
		get_tree().quit(0 if ok else 1)
