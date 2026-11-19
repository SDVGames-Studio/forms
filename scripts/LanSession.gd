extends Node
## LAN session autoload (issue #649): the ENet peer and the player
## roster of a LAN game, OUTLIVING the menu scenes. The LAN menu
## starts/joins the game (every player with a NICKNAME), and the level
## setup menu (LevelConfigMenu) becomes the SHARED lobby the host and
## the connected players all sit in while the host builds the match.
##
## The host is the authority: a joining client submits its nickname,
## the host owns the team set (GameConfig.teams) and the per-team
## driver assignments (team index → peer id in team_peers) and
## broadcasts the whole setup after every change. A connected player
## may edit exactly the teams the host assigned to them (name, color,
## members) — the edit travels to the host as a request and comes
## back inside the next setup broadcast. Turning the connection into
## a synchronized shared MATCH (figures moving over the wire) remains
## the next step, exactly as before this rework.

signal players_changed
signal setup_changed
signal client_connected
signal connection_lost(reason: String)

## The nickname persists between runs (user://lan_settings.cfg).
const SETTINGS_PATH := "user://lan_settings.cfg"
const NICK_KEY := "nickname"
const NICK_MAX := 16
## Room for a comfortable local lobby (host + 7 joiners) — mirrors
## the LanMenu constant.
const MAX_CLIENTS := 7

## True while a LAN game is live (hosted or joined).
var active := false
## True on the hosting machine — the authority of the lobby.
var is_host := false
## This player's nickname, set when hosting/joining.
var nickname := ""
## The host's driver assignments: team index → peer id (1 = the
## host). A team without an entry is computer-driven.
var team_peers: Dictionary = {}
## The host's last broadcast level pick (clients mirror it).
var setup_level: Dictionary = {}

var _players: Dictionary = {}
var _setup_open := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ------------------------------------------------------ host / join --

func host_game(port: int, nick: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_CLIENTS) != OK:
		return false
	_set_nickname(nick)
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	team_peers = {}
	setup_level = {}
	_setup_open = false
	_players = {1: nickname}
	players_changed.emit()
	return true


func join_game(address: String, port: int, nick: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return false
	_set_nickname(nick)
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	team_peers = {}
	setup_level = {}
	_setup_open = false
	_players = {}
	return true


func shutdown() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.close()
	# Back to a clean offline api: a closed ENet peer must not linger
	# as the active peer (assigning null does not reset it).
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	is_host = false
	team_peers = {}
	setup_level = {}
	_setup_open = false
	_players = {}


# --------------------------------------------------------- identity --

## The nickname stored from the previous run ("" when none).
func saved_nickname() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var stored := str(config.get_value("lan", NICK_KEY, ""))
		if not stored.is_empty():
			return stored
	return ""


func _set_nickname(nick: String) -> void:
	var cleaned := nick.strip_edges().substr(0, NICK_MAX)
	if cleaned.is_empty():
		cleaned = "Player"
	nickname = cleaned
	var config := ConfigFile.new()
	config.set_value("lan", NICK_KEY, cleaned)
	config.save(SETTINGS_PATH)


func my_peer_id() -> int:
	return multiplayer.get_unique_id()


## Every participant, the host first then the joiners by peer id:
## [{peer: int, nick: String}, ...].
func participants() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var ids := _players.keys()
	ids.sort()
	for id in ids:
		list.append({"peer": int(id), "nick": str(_players[id])})
	return list


## The nickname of one peer ("" when not known yet).
func player_nickname(peer_id: int) -> String:
	return str(_players.get(peer_id, ""))


## The peer driving a team (0 = the computer / nobody).
func team_peer(team_index: int) -> int:
	return int(team_peers.get(team_index, 0))


# ------------------------------------------------- host (authority) --

## Host: broadcast the whole setup (team set + driver assignments +
## the level pick) so every client's setup menu mirrors this one.
func push_setup(level_choice: Dictionary) -> void:
	if not (active and is_host):
		return
	_setup_open = true
	setup_level = level_choice.duplicate(true)
	_sync_setup.rpc(GameConfig.teams.duplicate(true), setup_level,
		team_peers.duplicate(true))


## Client: send an edit of an assigned team to the host — the host
## applies it and rebroadcasts the setup.
func submit_team_change(team_index: int, team: Dictionary) -> void:
	if active and not is_host:
		_request_team_change.rpc_id(1, team_index, team)


@rpc("any_peer", "call_remote", "reliable")
func _submit_nickname(nick: String) -> void:
	if not (active and is_host):
		return
	var sender := multiplayer.get_remote_sender_id()
	var cleaned := nick.strip_edges().substr(0, NICK_MAX)
	if cleaned.is_empty():
		cleaned = "Player %d" % sender
	_players[sender] = cleaned
	_sync_players.rpc(_players.duplicate(true))
	players_changed.emit()
	# A late joiner (the host already in the setup menu) gets the
	# current setup right away.
	if _setup_open:
		push_setup(setup_level)


@rpc("any_peer", "call_remote", "reliable")
func _request_team_change(team_index: int, team: Dictionary) -> void:
	if not (active and is_host):
		return
	var sender := multiplayer.get_remote_sender_id()
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	# Only the player the host ASSIGNED to this team may edit it — and
	# never the driver choice itself.
	if int(team_peers.get(team_index, 0)) != sender:
		return
	team["controller"] = str(GameConfig.teams[team_index].get("controller", "computer"))
	GameConfig.teams[team_index] = team
	setup_changed.emit()
	push_setup(setup_level)


# --------------------------------------------------- client (mirror) --

@rpc("authority", "call_remote", "reliable")
func _sync_players(players: Dictionary) -> void:
	if is_host:
		return
	_players = players.duplicate(true)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_setup(teams: Array, level: Dictionary, peers: Dictionary) -> void:
	if is_host:
		return
	GameConfig.teams = teams
	team_peers = peers.duplicate(true)
	setup_level = level.duplicate(true)
	GameConfig.level_path = str(level.get("path", ""))
	GameConfig.custom_level_name = str(level.get("custom_stem", ""))
	setup_changed.emit()


# ---------------------------------------------------- ENet callbacks --

func _on_peer_connected(_id: int) -> void:
	# The newcomer's nickname arrives with its _submit_nickname RPC.
	players_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if is_host:
		_players.erase(id)
		# Teams the leaving player drove fall back to the computer.
		for team_index in team_peers.keys():
			if int(team_peers[team_index]) == id:
				team_peers.erase(team_index)
				if team_index < GameConfig.teams.size():
					GameConfig.teams[team_index]["controller"] = "computer"
		_sync_players.rpc(_players.duplicate(true))
		if _setup_open:
			push_setup(setup_level)
		setup_changed.emit()
	players_changed.emit()


func _on_connected_to_server() -> void:
	# The client is in — hand the host its nickname right away and
	# move into the shared level setup menu (issue #649).
	_submit_nickname.rpc_id(1, nickname)
	if not is_host:
		client_connected.emit()


func _on_connection_failed() -> void:
	shutdown()
	connection_lost.emit(
		"Could not connect — check the address and port, and that a game is hosted.")


func _on_server_disconnected() -> void:
	shutdown()
	connection_lost.emit("The host closed the game.")
