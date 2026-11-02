class_name SpellCard
extends Control

signal pressed(card)

var spell: SpellDef
var slot_index := 0
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var hovered := false:
	set(value):
		hovered = value
		queue_redraw()
var accent: Color = UIKit.ACCENT
var compact := false
var show_slot := true

var _title: Label
var _incant: Label
var _stats: Label
var _note: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(200, 104) if not compact else Vector2(170, 76)
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_build_ui()
	_refresh()


func setup(p_spell: SpellDef, p_slot: int = 0, p_compact: bool = false, p_show_slot: bool = true) -> void:
	spell = p_spell
	slot_index = p_slot
	compact = p_compact
	show_slot = p_show_slot
	accent = UIKit.spell_color(spell)
	custom_minimum_size = Vector2(200, 104) if not compact else Vector2(170, 76)
	if is_node_ready():
		_build_ui()
		_refresh()
	queue_redraw()


func _build_ui() -> void:
	if _title != null:
		return
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_title = UIKit.bold_label("", 19 if not compact else 15, UIKit.INK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_title)

	_incant = UIKit.bold_label("", 13 if not compact else 11, UIKit.GOLD)
	_incant.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_incant)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_stats = UIKit.label("", 13 if not compact else 11, UIKit.MUTED)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_stats)

	if not compact:
		_note = UIKit.label("", 12, UIKit.DIM)
		_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(_note)


func _refresh() -> void:
	if _title == null:
		return
	if spell == null:
		_title.text = "EMPTY SLOT"
		_title.add_theme_color_override("font_color", UIKit.DIM)
		_incant.text = ""
		_stats.text = "Select a rune to craft"
		if _note != null:
			_note.text = ""
		accent = UIKit.OUTLINE
		return
	_title.text = spell.display_name()
	_title.add_theme_color_override("font_color", UIKit.INK)
	_incant.text = spell.incantation()
	var s := spell.base_stats()
	_stats.text = "%d dmg  ·  %d mana  ·  %.2fs" % [roundi(float(s["damage"])), roundi(float(s["mana"])), float(s["cooldown"])]
	_stats.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if _note != null:
		_note.text = str(s["status"])
	var over := spell.resolved_stats(SpellData.wand(Game.player_wand), true)
	tooltip_text = "%s\n%s\n%s\nCast: %s\nTyped overcast: ×%.1f (%d dmg)" % [
		spell.display_name(), spell.incantation(), s["status"], _stats.text,
		SpellDef.OVERCAST_MULT, roundi(float(over["damage"]))
	]
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UIKit.PANEL
	var border := UIKit.OUTLINE
	var bw := 1
	if hovered:
		bg = UIKit.PANEL_LIGHT
	if selected:
		border = accent
		bw = 2
		bg = Color(accent.r, accent.g, accent.b, 0.10).blend(UIKit.PANEL)
	elif spell != null:
		border = Color(accent.r, accent.g, accent.b, 0.28)
	if has_focus():
		border = accent.lightened(0.25)
		bw = 2

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(11)
	draw_style_box(sb, r)

	if spell != null:
		draw_rect(Rect2(0, 12, 4, size.y - 24), accent, true)
		var orb := Vector2(size.x - 20, 18)
		draw_circle(orb, 5.5, Color(accent.r, accent.g, accent.b, 0.95))
		draw_circle(orb, 9.0, Color(accent.r, accent.g, accent.b, 0.18))
	else:
		var dash := Color(UIKit.OUTLINE.r, UIKit.OUTLINE.g, UIKit.OUTLINE.b, 0.9)
		for i in 3:
			var y := size.y * 0.5 + float(i - 1) * 8.0
			draw_line(Vector2(size.x - 54, y), Vector2(size.x - 18, y), dash, 1.0)

	if show_slot:
		var badge := Rect2(8, 7, 20, 18)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0, 0, 0, 0.35)
		bsb.set_corner_radius_all(5)
		draw_style_box(bsb, badge)
		var font := UIKit.bold_font()
		draw_string(font, badge.position + Vector2(6, 14), str(slot_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_click_feedback()
		pressed.emit(self)
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click_feedback()
			pressed.emit(self)
			accept_event()


func _click_feedback() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("ui_click", "UI")
