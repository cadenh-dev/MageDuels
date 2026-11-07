class_name OnlineSession
extends Node

signal state_changed
signal lobby_ready
signal message_received(msg: Dictionary)
signal disconnected(reason: String)

enum State { IDLE, HOSTING_WAITING, JOINING, IN_LOBBY, IN_MATCH, DISCONNECTED }
const PROTOCOL := 1
const TIMEOUT_MS := 12000
var state := State.IDLE
var transport: NetTransport
var room_code := ""
var local_name := "Wizard"
var remote_name := "Wizard"
var cast_mode := "chant"
var rtt_ms := 0
var status := ""
var protocol_version := PROTOCOL # Exposed for protocol compatibility tests.
var _silence_seconds := 0.0
var _waiting_for_resume := false
var _last_ping := 0
var _ping_stamp := -1
var _peer_present := false
var _saved_cast_mode := ""
var _game: Node

func _ready() -> void:
	_game = get_node("/root/Game")

func use_transport(value: NetTransport) -> void:
	leave()
	if transport != null:
		remove_child(transport)
		transport.queue_free()
	transport = value
	add_child(transport)
	transport.connected.connect(_connected)
	transport.peer_joined.connect(_peer_joined)
	transport.peer_left.connect(func() -> void: _disconnect("Your opponent disconnected."))
	transport.failed.connect(_disconnect)
	transport.message_received.connect(_receive)

func prepare_online() -> void:
	if transport == null:
		var args := OS.get_cmdline_user_args()
		var cli_enet := "--net-host" in args or "--net-join" in args
		var relay_cli := "--gdsync-probe" in args or "--gdsync-duel-host" in args or "--gdsync-duel-join" in args or "--gdsync-ui-host" in args or "--gdsync-ui-join" in args
		var use_enet := cli_enet or (OS.has_feature("headless") and not relay_cli)
		var script := "res://scripts/net/enet_transport.gd" if use_enet else "res://scripts/net/gdsync_transport.gd"
		use_transport(load(script).new())

func host(options: Dictionary) -> void:
	if transport == null:
		prepare_online()
	_reset_for_attempt()
	local_name = str(options.get("host_name", str(_game.player_name))).strip_edges().left(24)
	cast_mode = str(options.get("cast_mode", _game.cast_mode))
	_set_state(State.HOSTING_WAITING, "Waiting for an opponent")
	transport.host(options)
	room_code = transport.room_code
	state_changed.emit()

func join(code: String, player_name: String = "") -> void:
	if transport == null:
		prepare_online()
	_reset_for_attempt()
	local_name = (str(_game.player_name) if player_name.is_empty() else player_name).strip_edges().left(24)
	room_code = code
	_silence_seconds = 0.0
	_set_state(State.JOINING, "Connecting")
	transport.join(code)

func is_host() -> bool:
	return transport != null and transport.is_host()

func _connected() -> void:
	room_code = transport.room_code
	state_changed.emit()

func _peer_joined() -> void:
	_peer_present = true
	_silence_seconds = 0.0
	if not is_host():
		send_reliable({"type": "hello", "v": protocol_version, "name": local_name})

func _receive(msg: Dictionary) -> void:
	var kind := str(msg.get("type", ""))
	if kind == "bye":
		_disconnect("Your opponent left the match.")
		return
	if kind == "reject":
		_disconnect(str(msg.get("reason", "Connection rejected.")).left(160))
		return
	if is_host() and state == State.HOSTING_WAITING and kind == "hello":
		if int(msg.get("v", -1)) != protocol_version:
			send_reliable({"type": "reject", "reason": "Protocol version mismatch. Use the same game build."})
			# Let ENet flush the reliable rejection before closing.
			await get_tree().create_timer(0.25).timeout
			if state == State.HOSTING_WAITING:
				_disconnect("Protocol version mismatch. Use the same game build.")
			return
		remote_name = str(msg.get("name", "Wizard")).strip_edges().left(24)
		_silence_seconds = 0.0
		send_reliable({"type": "welcome", "v": protocol_version, "name": local_name, "mode": cast_mode, "code": room_code})
		_set_state(State.IN_LOBBY, "Opponent connected")
		lobby_ready.emit()
		return
	if not is_host() and state == State.JOINING and kind == "welcome":
		if int(msg.get("v", -1)) != protocol_version or msg.get("mode") not in ["chant", "classic"]:
			_disconnect("Protocol version mismatch.")
			return
		remote_name = str(msg.get("name", "Wizard")).left(24)
		cast_mode = str(msg["mode"])
		_saved_cast_mode = _game.cast_mode
		_game.cast_mode = cast_mode
		_set_state(State.IN_LOBBY, "Connected")
		lobby_ready.emit()
	if state not in [State.IN_LOBBY, State.IN_MATCH]:
		return
	_silence_seconds = 0.0
	if _waiting_for_resume:
		_waiting_for_resume = false
		status = "Connected"
		state_changed.emit()
	match kind:
		"ping": send_reliable({"type": "pong", "stamp": msg.get("stamp", 0)})
		"pong":
			if int(msg.get("stamp", -2)) == _ping_stamp:
				rtt_ms = Time.get_ticks_msec() - _ping_stamp
				state_changed.emit()
		_: message_received.emit(msg)

func begin_match() -> void:
	if transport != null:
		transport.set_match_state("in_match")
	_set_state(State.IN_MATCH, "In match")

func send_reliable(msg: Dictionary) -> void:
	if transport != null:
		transport.send_reliable(msg)

func send_unreliable(msg: Dictionary) -> void:
	if transport != null:
		transport.send_unreliable(msg)

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if state == State.JOINING or (state == State.HOSTING_WAITING and _peer_present) or state in [State.IN_LOBBY, State.IN_MATCH]:
		# Browsers can stop the main loop while a tab is hidden. Do not convert
		# the resulting one-frame delta into an immediate timeout.
		if delta <= 1.0:
			_silence_seconds += maxf(0.0, delta)
		if state in [State.IN_LOBBY, State.IN_MATCH]:
			if _silence_seconds >= 10.0 and not _waiting_for_resume:
				_waiting_for_resume = true
				status = "Opponent's tab is inactive / waiting…"
				state_changed.emit()
			if _silence_seconds >= 20.0:
				_disconnect("Connection timed out. Please reconnect.")
				return
		elif _silence_seconds >= float(TIMEOUT_MS) / 1000.0:
			_disconnect("Connection timed out. Please reconnect.")
			return
	if state in [State.IN_LOBBY, State.IN_MATCH] and now - _last_ping > 1000:
		_last_ping = now
		_ping_stamp = now
		send_reliable({"type": "ping", "stamp": now})

func leave() -> void:
	if transport != null:
		send_reliable({"type": "bye"})
		transport.set_match_state("waiting")
		transport.leave()
	_peer_present = false
	_silence_seconds = 0.0
	_waiting_for_resume = false
	room_code = ""
	if not _saved_cast_mode.is_empty():
		_game.cast_mode = _saved_cast_mode
		_saved_cast_mode = ""
	_set_state(State.IDLE, "")

func _reset_for_attempt() -> void:
	_peer_present = false
	_silence_seconds = 0.0
	_waiting_for_resume = false
	room_code = ""
	rtt_ms = 0
	if not _saved_cast_mode.is_empty():
		_game.cast_mode = _saved_cast_mode
		_saved_cast_mode = ""

func _disconnect(reason: String) -> void:
	if state == State.DISCONNECTED:
		return
	leave()
	_set_state(State.DISCONNECTED, reason)
	disconnected.emit(reason)

func _set_state(value: State, text: String) -> void:
	state = value
	status = text
	state_changed.emit()
