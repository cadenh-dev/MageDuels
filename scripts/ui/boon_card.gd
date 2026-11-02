class_name BoonCard
extends Control

signal pressed(card)

var data: Dictionary = {}
var hovered := false:
	set(value):
		hovered = value
		queue_redraw()
var chosen := false:
	set(value):
		chosen = value
		queue_redraw()
var disabled := false:
	set(value):
		disabled = value
		mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
		queue_redraw()

var _accent: Color = UIKit.GOLD
var _name: Label
var _desc: Label
var _badge: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(286, 306)
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_build()


func setup(p_data: Dictionary) -> void:
	data = p_data
	_accent = data.get("color", UIKit.GOLD)
	if is_node_ready():
		_refresh()
	queue_redraw()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 112)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_name = UIKit.heading("", 30, UIKit.INK)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name)

	_desc = UIKit.label("", 16, UIKit.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.custom_minimum_size = Vector2(0, 70)
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_badge = UIKit.bold_label("", 12, UIKit.DIM)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_badge)

	_refresh()


func _refresh() -> void:
	if _name == null:
		return
	_name.text = str(data.get("name", "Boon"))
	_name.add_theme_color_override("font_color", _accent)
	_desc.text = str(data.get("desc", ""))
	var kind := str(data.get("kind", ""))
	_badge.text = {"wand": "WAND", "spell": "RUNE", "hp": "BOON", "mana": "BOON", "damage": "BOON", "cast": "BOON", "speed": "BOON", "shield": "BOON"}.get(kind, "BOON")


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UIKit.PANEL
	if hovered and not disabled:
		bg = UIKit.PANEL_LIGHT
	if chosen:
		bg = Color(_accent.r, _accent.g, _accent.b, 0.14).blend(UIKit.PANEL)
	if disabled and not chosen:
		bg = Color(0.05, 0.04, 0.08, 0.8)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = _accent if (chosen or has_focus()) else Color(_accent.r, _accent.g, _accent.b, 0.28)
	sb.set_border_width_all(3 if (chosen or has_focus()) else 1)
	sb.set_corner_radius_all(16)
	draw_style_box(sb, r)

	# Top color wash + sigil.
	draw_rect(Rect2(0, 0, size.x, 92), Color(_accent.r, _accent.g, _accent.b, 0.10), true)
	var orb := Vector2(size.x * 0.5, 50)
	draw_circle(orb, 28.0, Color(_accent.r, _accent.g, _accent.b, 0.16))
	draw_circle(orb, 18.0, Color(_accent.r, _accent.g, _accent.b, 0.55))
	draw_circle(orb, 9.0, _accent.lightened(0.3))
	draw_arc(orb, 32.0, 0.0, TAU, 40, Color(_accent.r, _accent.g, _accent.b, 0.4), 1.5, true)

	if disabled and not chosen:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35), true)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event.is_action_pressed("ui_accept"):
		pressed.emit(self)
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pressed.emit(self)
			accept_event()
