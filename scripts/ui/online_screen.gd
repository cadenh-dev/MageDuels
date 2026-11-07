class_name OnlineScreen
extends Control

signal cancel_pressed
var _name_field: LineEdit
var _code: LineEdit
var _status: Label
var _lobbies: VBoxContainer
var _actions: HBoxContainer
var _host_buttons: Array[Button] = []
var _join_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	box.add_child(UIKit.heading("ONLINE DUEL", 50))
	box.add_child(UIKit.label("Keyboard + mouse  ·  First to three", 18, UIKit.MUTED))
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Player name"
	_name_field.max_length = 24
	_name_field.text = Game.player_name
	_name_field.text_changed.connect(Game.set_player_name)
	box.add_child(_name_field)
	_actions = HBoxContainer.new()
	box.add_child(_actions)
	for public in [true, false]:
		var button := UIKit.button("HOST PUBLIC" if public else "HOST PRIVATE", 18)
		button.name = "HostPublicButton" if public else "HostPrivateButton"
		button.pressed.connect(func() -> void:
			NetSession.host({"public": public, "host_name": Game.player_name, "cast_mode": Game.cast_mode})
		)
		_actions.add_child(button)
		_host_buttons.append(button)
	var row := HBoxContainer.new()
	box.add_child(row)
	_code = LineEdit.new()
	_code.name = "RoomCodeField"
	_code.placeholder_text = "Room code"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_code)
	_join_button = UIKit.button("JOIN", 18)
	_join_button.name = "JoinButton"
	_join_button.pressed.connect(func() -> void: _join(_code.text))
	_code.text_submitted.connect(_join)
	row.add_child(_join_button)
	var refresh := UIKit.ghost_button("REFRESH PUBLIC LOBBIES", 17)
	refresh.pressed.connect(_refresh)
	box.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	box.add_child(scroll)
	_lobbies = VBoxContainer.new()
	scroll.add_child(_lobbies)
	_status = UIKit.label("", 17, UIKit.GOLD)
	_status.name = "OnlineStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var cancel := UIKit.ghost_button("CANCEL", 18)
	cancel.pressed.connect(func() -> void:
		NetSession.leave()
		cancel_pressed.emit()
	)
	box.add_child(cancel)
	NetSession.prepare_online()
	NetSession.state_changed.connect(_update_status)
	_update_status()
	_refresh()
	_process(0.0)

func _process(_delta: float) -> void:
	var transport := NetSession.transport
	var ready := not (transport is GDSyncTransport) or (transport as GDSyncTransport).backend_ready
	var busy := NetSession.state in [OnlineSession.State.JOINING, OnlineSession.State.HOSTING_WAITING, OnlineSession.State.IN_LOBBY, OnlineSession.State.IN_MATCH]
	for button in _host_buttons:
		button.disabled = not ready or busy
	_join_button.disabled = busy
	if not ready and NetSession.state == OnlineSession.State.IDLE:
		_status.text = "Connecting to server…"

func _join(code: String) -> void:
	var normalized := code.strip_edges().to_upper()
	_code.text = normalized
	if normalized.is_empty():
		_status.text = "Enter a room code."
		return
	NetSession.join(normalized, Game.player_name)

func _refresh() -> void:
	var lobbies := await NetSession.transport.list_public_lobbies()
	if not is_inside_tree():
		return
	for child in _lobbies.get_children():
		_lobbies.remove_child(child)
		child.queue_free()
	for lobby: Dictionary in lobbies:
		var button := UIKit.ghost_button("%s  ·  %s  ·  %d/2" % [lobby["host_name"], lobby["cast_mode"], lobby["players"]], 16)
		button.disabled = int(lobby["players"]) >= 2
		button.pressed.connect(func() -> void: _join(str(lobby["code"])))
		_lobbies.add_child(button)
	if lobbies.is_empty():
		var empty_text := "No open public duels — host one!" if NetSession.transport is GDSyncTransport else "No local lobbies. Join another desktop by IP:port."
		_lobbies.add_child(UIKit.label(empty_text, 16, UIKit.MUTED))

func _update_status() -> void:
	var ping := "—" if NetSession.rtt_ms <= 0 else "%d ms" % NetSession.rtt_ms
	_status.text = NetSession.status
	if not NetSession.room_code.is_empty():
		_status.text += "\n%s  ·  %s" % [NetSession.room_code, ping]
	elif NetSession.rtt_ms > 0:
		_status.text += "\n%s" % ping
	if NetSession.transport is ENetTransport:
		_status.text += "\nDesktop ENet: share your reachable IP:port. Public listing is local only."

func _exit_tree() -> void:
	if NetSession.state_changed.is_connected(_update_status):
		NetSession.state_changed.disconnect(_update_status)
