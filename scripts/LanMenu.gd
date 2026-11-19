extends Control
## LAN multiplayer lobby (issue #551, step 1 of the owner's allowed
## step-wise delivery): one player HOSTS a game, the other CONNECTS to
## the host's address on the local network. The screen establishes and
## shows the ENet connection between the two players; turning that
## connection into a synchronized shared match is the next step.
##
## Host: starts a server on the port below and shows this machine's LAN
## addresses to type on the other device. Join: type the host address,
## CONNECT. Back/Esc (issue #303) always closes the connection first —
## no peer outlives this screen.
##
## Issue #551 rework (owner follow-up 2026-11-16): once HOST GAME
## starts, the host's setup controls (HOST GAME, host address, port,
## CONNECT) disappear and a NEXT button appears, taking the host into
## the usual level flow — LevelConfigMenu (the level drop-down picks
## the map there since issue #643) → START runs
## the game. The ENet connection still does not drive a synchronized
## shared match — that remains the next step.

const DEFAULT_PORT := 24565
## Room for a comfortable local lobby (host + 7 joiners).
const MAX_CLIENTS := 7

@onready var _host_button: Button = %HostButton
@onready var _next_button: Button = %NextButton
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _connect_button: Button = %ConnectButton
@onready var _status_label: Label = %StatusLabel
@onready var _players_label: Label = %PlayersLabel
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	# Main-menu spec §9 (M4 hardening): adapt to the viewport width.
	MenuAdapt.apply(self)
	_port_edit.text = str(DEFAULT_PORT)
	_next_button.visible = false
	_host_button.pressed.connect(_on_host_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_connect_button.pressed.connect(_on_connect_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_set_status("Host a game, or type the host's address and connect.")
	_refresh_players()


## Issue #303: Escape is the cancel button in every menu — here it
## means Back (close the connection, return to the main menu).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()


func _on_host_pressed() -> void:
	var port := _port_value()
	if port <= 0:
		_set_status("Invalid port — enter a number between 1 and 65535.")
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_CLIENTS) != OK:
		_set_status("Could not host on port %d — is it already in use?" % port)
		return
	multiplayer.multiplayer_peer = peer
	# Issue #551 rework (owner follow-up): once this machine hosts, the
	# setup controls are done — the HOST GAME button and the join row
	# (host address, port, CONNECT) disappear and NEXT takes over,
	# leading into the level flow below.
	_host_button.visible = false
	_address_edit.visible = false
	_port_edit.visible = false
	_connect_button.visible = false
	_next_button.visible = true
	_next_button.grab_focus()
	var addresses := ", ".join(_lan_addresses())
	_set_status("Hosting. On the other device connect to: %s (port %d)."
		% [addresses, port])
	_refresh_players()


func _on_connect_pressed() -> void:
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		_set_status("Type the host's address first (e.g. 192.168.1.7).")
		return
	var port := _port_value()
	if port <= 0:
		_set_status("Invalid port — enter a number between 1 and 65535.")
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		_set_status("Could not start connecting to %s:%d." % [address, port])
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to %s:%d ..." % [address, port])
	_refresh_players()


func _on_next_pressed() -> void:
	# Issue #643: the levels menu is gone — the level is picked in the
	# setup menu's top-line drop-down now.
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_back_pressed() -> void:
	_shutdown_network()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


## Leaving the screen by any other path (scene change, quit) must not
## leave a socket behind.
func _exit_tree() -> void:
	_shutdown_network()


func _on_peer_connected(_id: int) -> void:
	if multiplayer.is_server():
		_set_status("A player connected — the shared match itself is the next step.")
	_refresh_players()


func _on_peer_disconnected(_id: int) -> void:
	_refresh_players()


func _on_connected_to_server() -> void:
	_set_status("Connected to the host — the shared match itself is the next step.")
	_refresh_players()


func _on_connection_failed() -> void:
	_shutdown_network()
	_set_status("Could not connect — check the address and port, and that a game is hosted.")
	_refresh_players()


func _on_server_disconnected() -> void:
	# Losing the host takes this client back offline so the player can
	# retry (host again or reconnect) on the same screen.
	_shutdown_network()
	_set_status("The host closed the game.")
	_refresh_players()


func _port_value() -> int:
	return _port_edit.text.strip_edges().to_int()


func _set_status(message: String) -> void:
	_status_label.text = message


## LAN-reachable IPv4 addresses of this machine (private ranges; the
## loopback fallback covers same-machine testing).
func _lan_addresses() -> Array[String]:
	var found: Array[String] = []
	for address: String in IP.get_local_addresses():
		if not address.contains("."):
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") \
				or address.begins_with("172.") or address == "127.0.0.1":
			found.append(address)
	if found.is_empty():
		found.append("127.0.0.1")
	return found


func _refresh_players() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		# multiplayer.get_peers() lists the REMOTE peers on this api (the
		# server lists its clients, a client lists the server), so the
		# local player is the +1.
		_players_label.text = "PLAYERS: %d" % (multiplayer.get_peers().size() + 1)
	else:
		_players_label.text = ""


func _shutdown_network() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.close()
	# Back to a clean offline api: a closed ENet peer must not linger
	# as the active peer (assigning null does not reset it).
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
