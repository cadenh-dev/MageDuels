class_name GDSyncTransport
extends NetTransport

## GD-Sync 1.0.2 adapter. The game protocol only sees NetTransport.
const ENUMS := preload("res://addons/GD-Sync/Scripts/Enums/Enums.gd")
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const PROTOCOL := OnlineSession.PROTOCOL
const CONNECT_TIMEOUT_MS := 25000
const LOBBY_TIMEOUT_MS := 12000

var _bound := false
var _hosting := false
var _in_lobby := false
var _starting := false
var _connection_ready := false
var _requested_code := ""
var _requested_options: Dictionary = {}
var _create_attempts := 0
var _create_retry_pending := false
var _create_retry_generation := 0
var _leaving := false
var bytes_sent := 0
var bytes_received := 0
var peer_join_events := 0
var _known_host_id := -1
var _peer_notified := false
var backend_ready := false
var _netdebug := false
var _debug_started_ms := 0
var _attempt_started_ms := 0
var _attempt_stage := ""

func _debug(event: String, details: String = "") -> void:
	if _netdebug:
		print("[NET %dms] transport %s%s" % [Time.get_ticks_msec() - _debug_started_ms, event, (" " + details) if not details.is_empty() else ""])

func _bind_signals() -> void:
	if _bound:
		return
	_bound = true
	if OS.has_feature("web"):
		_netdebug = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('netdebug') === '1'"))
	_debug_started_ms = Time.get_ticks_msec()
	GDSync.connected.connect(_on_connected)
	GDSync.connection_failed.connect(_on_connection_failed)
	GDSync.disconnected.connect(_on_disconnected)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_creation_failed.connect(_on_lobby_creation_failed)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.lobby_join_failed.connect(_on_lobby_join_failed)
	GDSync.client_joined.connect(_on_client_joined)
	GDSync.client_left.connect(_on_client_left)
	GDSync.host_changed.connect(_on_host_changed)
	GDSync.lobbies_received.connect(_on_lobbies_received)
	GDSync.expose_func(_on_packet)

func _ensure_connected() -> void:
	_bind_signals()
	if GDSync.is_active():
		_debug("already active")
		_on_connected()
	elif not _starting:
		_starting = true
		_attempt_started_ms = Time.get_ticks_msec()
		_attempt_stage = "connection"
		_debug("start_multiplayer called")
		GDSync.start_multiplayer()

func warm_up() -> void:
	if not backend_ready:
		_ensure_connected()

func host(options: Dictionary) -> void:
	_prepare_lobby_request()
	_hosting = true
	_requested_options = options.duplicate(true)
	_create_attempts = 0
	_create_retry_pending = false
	_create_retry_generation += 1
	if GDSync.is_active():
		_connection_ready = true
		_create_lobby()
	else:
		_connection_ready = false
		_ensure_connected()

func _create_lobby() -> void:
	if not _hosting or not GDSync.is_active():
		return
	_create_attempts += 1
	if _create_attempts > 6:
		failed.emit("Could not reserve a lobby code. Please try hosting again.")
		return
	room_code = _random_code()
	_attempt_started_ms = Time.get_ticks_msec()
	_attempt_stage = "lobby_create"
	_debug("lobby_create", "code=" + room_code)
	var tags := {"protocol": PROTOCOL, "cast_mode": str(_requested_options.get("cast_mode", "chant")),
		"host_name": str(_requested_options.get("host_name", "Wizard")).left(24), "state": "waiting"}
	GDSync.lobby_create(room_code, "", bool(_requested_options.get("public", false)), 2, tags)

func join(code: String) -> void:
	_prepare_lobby_request()
	_hosting = false
	_requested_code = code.strip_edges().to_upper()
	_attempt_started_ms = Time.get_ticks_msec()
	_attempt_stage = "lobby_join"
	_debug("join requested", "code=" + _requested_code)
	if GDSync.is_active():
		_connection_ready = true
		_debug("lobby_join", "code=" + _requested_code)
		GDSync.lobby_join(_requested_code)
	else:
		_connection_ready = false
		_ensure_connected()

func _prepare_lobby_request() -> void:
	if _in_lobby and GDSync.is_active():
		GDSync.lobby_leave()
	_in_lobby = false
	_requested_code = ""
	_requested_options.clear()
	_create_retry_pending = false
	_create_retry_generation += 1
	_known_host_id = -1
	_peer_notified = false
	room_code = ""
	backend_ready = GDSync.is_active()

func _on_connected() -> void:
	_debug("connected signal")
	if not GDSync.is_active():
		_debug("stale connected ignored", "plugin is inactive")
		return
	_attempt_stage = ""
	_starting = false
	backend_ready = true
	var controller: Object = GDSync.get("_connection_controller")
	if controller != null and controller.get("is_web_export"):
		_debug("relay connected", "hub=" + str(controller.get("web_hub_host")))
	if _connection_ready:
		return
	_connection_ready = true
	if _hosting and not _in_lobby:
		_create_lobby()
	elif not _hosting and not _requested_code.is_empty() and not _in_lobby:
		_debug("lobby_join", "code=" + _requested_code)
		GDSync.lobby_join(_requested_code)

func _on_connection_failed(error: int) -> void:
	_debug("connection_failed", "err=" + str(error))
	_attempt_stage = ""
	_starting = false
	backend_ready = false
	failed.emit(_connection_error(error))

func _on_disconnected() -> void:
	_debug("disconnected signal")
	if _leaving:
		return
	_in_lobby = false
	peer_left.emit()
	failed.emit("GD-Sync connection lost. Return to the menu and reconnect.")

func _on_lobby_created(name: String) -> void:
	_debug("lobby_created", "name=" + name)
	if _hosting and name == room_code:
		_attempt_started_ms = Time.get_ticks_msec()
		_attempt_stage = "lobby_join_after_create"
		_debug("lobby_join", "code=" + name)
		GDSync.lobby_join(name)

func _on_lobby_creation_failed(name: String, error: int) -> void:
	_debug("lobby_creation_failed", "name=" + name + " err=" + str(error))
	if not _hosting or name != room_code:
		return
	if _create_retry_required(error):
		_retry_lobby_create()
	else:
		_attempt_stage = ""
		failed.emit(_lobby_create_error(error))

static func _create_retry_required(error: int) -> bool:
	return error in [ENUMS.LOBBY_CREATION_ERROR.LOBBY_ALREADY_EXISTS, ENUMS.LOBBY_CREATION_ERROR.ON_COOLDOWN]

func _retry_lobby_create() -> void:
	if _create_retry_pending:
		return
	_create_retry_pending = true
	var generation := _create_retry_generation
	await get_tree().create_timer(3.1).timeout
	if generation != _create_retry_generation:
		return
	_create_retry_pending = false
	if _hosting:
		_create_lobby() # Generates a fresh code and uses the bounded attempt count.

func _on_lobby_joined(name: String) -> void:
	_debug("lobby_joined", "name=" + name)
	if name != room_code and name != _requested_code:
		return
	room_code = name
	_attempt_stage = ""
	_in_lobby = true
	_known_host_id = -1
	_peer_notified = false
	connected.emit()

func _on_lobby_join_failed(name: String, error: int) -> void:
	_debug("lobby_join_failed", "name=" + name + " err=" + str(error))
	if name == _requested_code or name == room_code:
		_attempt_stage = ""
		failed.emit(_lobby_join_error(error))

func _process(_delta: float) -> void:
	var timeout_ms := CONNECT_TIMEOUT_MS if _attempt_stage == "connection" else LOBBY_TIMEOUT_MS
	if _attempt_stage.is_empty() or Time.get_ticks_msec() - _attempt_started_ms < timeout_ms:
		return
	var stage := _attempt_stage
	_attempt_stage = ""
	_debug("timeout", "stage=" + stage)
	_starting = false
	_connection_ready = false
	backend_ready = false
	failed.emit("GD-Sync %s timed out. Please try again." % stage.replace("_", " "))

func _on_client_joined(client_id: int) -> void:
	_debug("client_joined", "id=" + str(client_id))
	if _in_lobby and client_id != GDSync.get_client_id():
		if is_host() or client_id == GDSync.get_host():
			_notify_peer_joined()

func _on_client_left(client_id: int) -> void:
	_debug("client_left", "id=" + str(client_id))
	if _in_lobby and client_id != GDSync.get_client_id():
		peer_left.emit()

func _on_host_changed(now_host: bool, _new_host_id: int) -> void:
	if not _in_lobby:
		return
	var host_id := GDSync.get_host()
	if _known_host_id < 0:
		_known_host_id = host_id
		if not now_host and host_id >= 0:
			_notify_peer_joined()
		return
	if host_id != _known_host_id:
		peer_left.emit()
		failed.emit("The host left. The match has ended.")

func _on_packet(payload: PackedByteArray) -> void:
	if not _in_lobby or payload.is_empty() or payload.size() > 49152:
		return
	var decoded: Variant = bytes_to_var(payload.decompress_dynamic(49152, FileAccess.COMPRESSION_DEFLATE))
	if not decoded is Dictionary or not decoded.get("type") is String:
		return
	bytes_received += payload.size()
	if bytes_received == payload.size():
		_debug("first message received", "bytes=" + str(payload.size()))
	var msg: Dictionary = decoded
	message_received.emit(msg)

func _notify_peer_joined() -> void:
	if _peer_notified:
		return
	_peer_notified = true
	peer_join_events += 1
	peer_joined.emit()

func send_reliable(msg: Dictionary) -> void:
	if not _in_lobby:
		return
	var payload := var_to_bytes(msg).compress(FileAccess.COMPRESSION_DEFLATE)
	if bytes_sent == 0:
		_debug("first message sent", "type=" + str(msg.get("type", "?")))
	bytes_sent += payload.size()
	if is_host():
		GDSync.call_func(_on_packet, payload)
	else:
		GDSync.call_func_on(GDSync.get_host(), _on_packet, payload)

func send_unreliable(msg: Dictionary) -> void:
	if not _in_lobby:
		return
	var payload := var_to_bytes(msg).compress(FileAccess.COMPRESSION_DEFLATE)
	if bytes_sent == 0:
		_debug("first message sent", "type=" + str(msg.get("type", "?")))
	bytes_sent += payload.size()
	if is_host():
		GDSync.call_func_unreliable(_on_packet, payload)
	else:
		GDSync.call_func_on_unreliable(GDSync.get_host(), _on_packet, payload)

func set_match_state(value: String) -> void:
	if _in_lobby and is_host():
		GDSync.lobby_set_tag("state", value)

func list_public_lobbies() -> Array:
	if not GDSync.is_active():
		_ensure_connected()
		await GDSync.connected
	return _format_lobbies(await _request_lobbies())

func _request_lobbies() -> Array:
	var received := {"lobbies": []}
	var callback := func(value: Array) -> void: received["lobbies"] = value
	GDSync.lobbies_received.connect(callback, CONNECT_ONE_SHOT)
	GDSync.get_public_lobbies()
	await GDSync.lobbies_received
	return received["lobbies"]

func _on_lobbies_received(values: Array) -> void:
	lobby_list_updated.emit(_format_lobbies(values))

func _format_lobbies(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if not value is Dictionary:
			continue
		var lobby: Dictionary = value
		var tags: Dictionary = lobby.get("Tags", {})
		if int(tags.get("protocol", -1)) != PROTOCOL or str(tags.get("state", "")) != "waiting" or int(lobby.get("PlayerCount", 0)) != 1:
			continue
		result.append({"code": str(lobby.get("Name", "")), "host_name": str(tags.get("host_name", lobby.get("Host", "Wizard"))),
			"players": int(lobby.get("PlayerCount", 0)), "cast_mode": str(tags.get("cast_mode", "chant"))})
	return result

func _random_code() -> String:
	var code := ""
	for _i in 5:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code

func _connection_error(error: int) -> String:
	if error == ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY:
		return "GD-Sync rejected its API keys. Check addons/GD-Sync/keys.cfg."
	if error == ENUMS.CONNECTION_FAILED.TIMEOUT:
		return "Could not connect to GD-Sync. Check your connection and try again."
	return "GD-Sync could not start (%d)." % error

func _lobby_create_error(error: int) -> String:
	if error == ENUMS.LOBBY_CREATION_ERROR.ON_COOLDOWN:
		return "Please wait a few seconds before creating another lobby."
	return "GD-Sync could not create the lobby (%d)." % error

func _lobby_join_error(error: int) -> String:
	if error == ENUMS.LOBBY_JOIN_ERROR.LOBBY_DOES_NOT_EXIST:
		return "Lobby not found. Check the code and try again."
	if error == ENUMS.LOBBY_JOIN_ERROR.LOBBY_IS_FULL:
		return "That lobby is full."
	if error == ENUMS.LOBBY_JOIN_ERROR.LOBBY_IS_CLOSED:
		return "That lobby is no longer accepting players."
	return "GD-Sync could not join the lobby (%d)." % error

func leave() -> void:
	_leaving = true
	_requested_code = ""
	_requested_options.clear()
	_create_retry_pending = false
	_create_retry_generation += 1
	if GDSync.is_active():
		if _in_lobby:
			GDSync.lobby_leave()
		_in_lobby = false
		GDSync.stop_multiplayer()
	_in_lobby = false
	_known_host_id = -1
	_peer_notified = false
	_hosting = false
	_starting = false
	backend_ready = false
	_connection_ready = false
	room_code = ""
	_leaving = false

func is_host() -> bool:
	return _in_lobby and GDSync.is_host()

func _exit_tree() -> void:
	leave()
