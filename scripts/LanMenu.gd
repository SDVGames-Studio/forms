extends Control
## LAN multiplayer lobby (issue #551, reworked by issue #649): one
## player HOSTS a game, the others type the host's address and
## CONNECT — and everyone fills a NICKNAME first (issue #649): the
## nickname rides the connection into the shared lobby.
##
## The ENet peer and the player roster now live in the LanSession
## autoload (issue #649), so the connection OUTLIVES this screen: the
## host's NEXT — and every connected player, automatically on
## connect — moves into the SAME level setup menu
## (LevelConfigMenu), the shared lobby where the host builds the
## match and assigns each team to the computer, themselves, or one of
## the connected players by nickname. Turning the connection into a
## synchronized shared match (figures moving over the wire) is the
## next step.
##
## Back/Esc (issue #303) always closes the connection first — no peer
## outlives the game.

const DEFAULT_PORT := 24565

@onready var _host_button: Button = %HostButton
@onready var _next_button: Button = %NextButton
@onready var _nickname_edit: LineEdit = %NicknameEdit
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
	# Issue #649: the nickname persists between runs.
	_nickname_edit.text = LanSession.saved_nickname()
	_next_button.visible = false
	_host_button.pressed.connect(_on_host_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_connect_button.pressed.connect(_on_connect_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	# Issue #649: the connection itself lives in LanSession — this
	# screen only reacts to it.
	LanSession.players_changed.connect(_refresh_players)
	LanSession.client_connected.connect(_on_client_connected)
	LanSession.connection_lost.connect(_on_connection_lost)
	_set_status("Type your nickname, then host a game or type the host's address and connect.")
	_refresh_players()


## Issue #303: Escape is the cancel button in every menu — here it
## means Back (close the connection, return to the main menu).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()


func _nickname() -> String:
	return _nickname_edit.text.strip_edges()


func _on_host_pressed() -> void:
	# Issue #649: the nickname is the player's identity in the shared
	# lobby — required before the connection starts.
	if _nickname().is_empty():
		_set_status("Type your nickname first — the other players see it in the lobby.")
		_nickname_edit.grab_focus()
		return
	var port := _port_value()
	if port <= 0:
		_set_status("Invalid port — enter a number between 1 and 65535.")
		return
	if not LanSession.host_game(port, _nickname()):
		_set_status("Could not host on port %d — is it already in use?" % port)
		return
	# Issue #649: once this machine hosts, the setup controls are done
	# — the nickname row included — and NEXT takes the host into the
	# shared level setup menu.
	_hide_setup_controls()
	_next_button.visible = true
	_next_button.grab_focus()
	var addresses := ", ".join(_lan_addresses())
	_set_status("Hosting as %s. On the other device connect to: %s (port %d)."
		% [LanSession.nickname, addresses, port])
	_refresh_players()


func _on_connect_pressed() -> void:
	if _nickname().is_empty():
		_set_status("Type your nickname first — the host sees it in the lobby.")
		_nickname_edit.grab_focus()
		return
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		_set_status("Type the host's address first (e.g. 192.168.1.7).")
		return
	var port := _port_value()
	if port <= 0:
		_set_status("Invalid port — enter a number between 1 and 65535.")
		return
	if not LanSession.join_game(address, port, _nickname()):
		_set_status("Could not start connecting to %s:%d." % [address, port])
		return
	_hide_setup_controls()
	_set_status("Connecting to %s:%d as %s ..." % [address, port, LanSession.nickname])
	_refresh_players()


func _on_client_connected() -> void:
	# Issue #649: a connected player lands in the SAME level setup
	# menu as the host — the shared lobby.
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_connection_lost(reason: String) -> void:
	# The client never made it into the shared lobby — back to the
	# setup controls so the player can retry.
	_show_setup_controls()
	_next_button.visible = false
	_set_status(reason)
	_refresh_players()


func _on_next_pressed() -> void:
	# Issue #643: the level is picked in the setup menu's top-line
	# drop-down; issue #649: the host AND the connected players sit in
	# that same menu — the shared lobby.
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_back_pressed() -> void:
	LanSession.shutdown()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _hide_setup_controls() -> void:
	_host_button.visible = false
	_nickname_edit.visible = false
	_address_edit.visible = false
	_port_edit.visible = false
	_connect_button.visible = false


func _show_setup_controls() -> void:
	_host_button.visible = true
	_nickname_edit.visible = true
	_address_edit.visible = true
	_port_edit.visible = true
	_connect_button.visible = true


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
	if not LanSession.active:
		_players_label.text = ""
		return
	var parts := LanSession.participants()
	if parts.is_empty():
		_players_label.text = ""
		return
	var names := ""
	for part in parts:
		if not names.is_empty():
			names += ", "
		names += str(part["nick"])
	_players_label.text = "PLAYERS: %d — %s" % [parts.size(), names]
