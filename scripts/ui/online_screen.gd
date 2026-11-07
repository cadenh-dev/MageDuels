class_name OnlineScreen
extends Control

signal cancel_pressed
var _name_field: LineEdit
var _code: LineEdit
var _status: Label
var _lobbies: VBoxContainer
var _actions: HBoxContainer

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
		button.pressed.connect(func() -> void:
			NetSession.leave()
			NetSession.host({"public": public, "host_name": Game.player_name, "cast_mode": Game.cast_mode})
		)
		_actions.add_child(button)
	var row := HBoxContainer.new()
	box.add_child(row)
	_code = LineEdit.new()
	_code.placeholder_text = "Room code / IP:port"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_code)
	var join_button := UIKit.button("JOIN", 18)
	join_button.pressed.connect(func() -> void: _join(_code.text))
	row.add_child(join_button)
	var refresh := UIKit.ghost_button("REFRESH PUBLIC LOBBIES", 17)
	refresh.pressed.connect(_refresh)
	box.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	box.add_child(scroll)
	_lobbies = VBoxContainer.new()
	scroll.add_child(_lobbies)
	_status = UIKit.label("", 17, UIKit.GOLD)
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

func _join(code: String) -> void:
	NetSession.leave()
	NetSession.join(code, Game.player_name)

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
		_lobbies.add_child(UIKit.label("No local lobbies. Join another desktop by IP:port.", 16, UIKit.MUTED))

func _update_status() -> void:
	_status.text = "%s\n%s  ·  %d ms" % [NetSession.status, NetSession.room_code, NetSession.rtt_ms]
	if NetSession.transport is ENetTransport:
		_status.text += "\nDesktop ENet: share your reachable IP:port. Public listing is local only."

func _exit_tree() -> void:
	if NetSession.state_changed.is_connected(_update_status):
		NetSession.state_changed.disconnect(_update_status)
