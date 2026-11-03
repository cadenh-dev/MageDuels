class_name WandCard
extends Control

signal pressed(card)

var wand_id := "emberwood"
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var hovered := false:
	set(value):
		hovered = value
		queue_redraw()

var _accent: Color = UIKit.ACCENT
var _name_label: Label
var _affinity: Label
var _blurb: Label
var _stats: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(268, 384)
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_build()


func setup(p_wand_id: String) -> void:
	wand_id = p_wand_id
	var w: Dictionary = SpellData.wand(wand_id)
	_accent = w.get("color", UIKit.ACCENT)
	if is_node_ready():
		_refresh(w)
	queue_redraw()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 96)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_name_label = UIKit.heading("", 30, UIKit.INK)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)

	_affinity = UIKit.bold_label("", 14, UIKit.GOLD)
	_affinity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_affinity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_affinity)

	var blurb := UIKit.label("", 15, UIKit.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.custom_minimum_size = Vector2(0, 56)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(blurb)
	_blurb = blurb

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 3)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_stats)

	_refresh(SpellData.wand(wand_id))


func _refresh(w: Dictionary) -> void:
	_name_label.text = str(w.get("name", "Wand"))
	var aff: String = str(w.get("affinity", ""))
	var e: Dictionary = SpellData.ELEMENTS.get(aff, {})
	_affinity.text = "%s AFFINITY  ·  +%d%% DAMAGE" % [str(e.get("name", aff)).to_upper(), roundi(float(w.get("affinity_bonus", 0.0)) * 100.0)]
	_affinity.add_theme_color_override("font_color", _accent)
	_blurb.text = str(w.get("blurb", ""))

	for child in _stats.get_children():
		child.queue_free()
	var rows := [
		["HEALTH", "%d" % roundi(float(w.get("hp", 100.0)))],
		["MANA", "%d" % roundi(float(w.get("mana_max", 100.0)))],
		["RECOVERY", "%.1f/s" % float(w.get("mana_regen", 10.0))],
		["MOVE", "%.1f" % float(w.get("move_speed", 5.5))],
		["CAST SPEED", "%+d%%" % roundi((1.0 - float(w.get("cast_time_mult", 1.0))) * 100.0)],
	]
	for row in rows:
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := UIKit.label(row[0], 13, UIKit.DIM)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(k)
		var v := UIKit.bold_label(row[1], 14, UIKit.INK)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(v)
		_stats.add_child(h)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UIKit.PANEL
	if hovered:
		bg = UIKit.PANEL_LIGHT
	if selected:
		bg = Color(UIKit.PANEL_LIGHT.r, UIKit.PANEL_LIGHT.g, UIKit.PANEL_LIGHT.b, 1.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = _accent if selected else Color(_accent.r, _accent.g, _accent.b, 0.24)
	sb.set_border_width_all(3 if selected else 1)
	sb.set_corner_radius_all(14)
	draw_style_box(sb, r)

	if has_focus():
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color(0, 0, 0, 0)
		fb.border_color = _accent.lightened(0.35)
		fb.set_border_width_all(2)
		fb.set_corner_radius_all(16)
		draw_style_box(fb, Rect2(Vector2(-4, -4), size + Vector2(8, 8)))

	# Top aura
	var orb := Vector2(size.x * 0.5, 48)
	draw_circle(orb, 30.0, Color(_accent.r, _accent.g, _accent.b, 0.16))
	draw_circle(orb, 20.0, Color(_accent.r, _accent.g, _accent.b, 0.5))
	draw_circle(orb, 12.0, _accent.lightened(0.25))
	draw_arc(orb, 34.0, 0.0, TAU, 40, Color(_accent.r, _accent.g, _accent.b, 0.35), 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		pressed.emit(self)
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pressed.emit(self)
			accept_event()
