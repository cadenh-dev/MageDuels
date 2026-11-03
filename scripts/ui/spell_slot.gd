class_name SpellSlotWidget
extends Control

## HUD slot: key, spell name, incantation, mana cost, and modifier tag.

var spell: SpellDef
var key_text := "1"
var accent: Color = UIKit.ACCENT
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _name: Label
var _incant: Label
var _cost: Label
var _key: Label


func _ready() -> void:
	custom_minimum_size = Vector2(156, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	_refresh()


func setup(p_spell: SpellDef, p_key: String, p_selected: bool) -> void:
	spell = p_spell
	key_text = p_key
	selected = p_selected
	accent = UIKit.spell_color(spell)
	if is_node_ready():
		_refresh()
	queue_redraw()


func _build() -> void:
	if _name != null:
		return
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_key = UIKit.bold_label(key_text, 12, UIKit.MUTED)
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_key)

	_name = UIKit.bold_label("", 16, UIKit.INK)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_name)

	_incant = UIKit.label("", 10, UIKit.DIM)
	_incant.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_incant.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_incant)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_cost = UIKit.label("", 12, UIKit.MUTED)
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_cost)


func _refresh() -> void:
	if _name == null:
		return
	if spell == null:
		_name.text = "—"
		_incant.text = ""
		_cost.text = ""
		return
	_name.text = spell.display_name()
	_key.text = key_text
	_key.add_theme_color_override("font_color", accent)
	_incant.text = spell.incantation()
	var s := spell.base_stats()
	_incant.text = spell.incantation()
	var mod_name := str(spell.modifier_data().get("name", ""))
	if spell.modifier != "" and mod_name != "":
		_cost.text = "%d mana  ·  %s" % [roundi(float(s["mana"])), mod_name.to_upper()]
		_cost.add_theme_color_override("font_color", accent)
	else:
		_cost.text = "%d mana" % roundi(float(s["mana"]))
		_cost.add_theme_color_override("font_color", UIKit.MUTED)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UIKit.PANEL
	if selected:
		bg = UIKit.PANEL_LIGHT
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = accent if selected else Color(accent.r, accent.g, accent.b, 0.25)
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(9)
	sb.corner_detail = 8
	draw_style_box(sb, r)

	if selected:
		draw_rect(Rect2(9, size.y - 3, size.x - 18, 2), accent, true)
		draw_circle(Vector2(size.x - 14, 15), 3.5, Color(accent.r, accent.g, accent.b, 0.95))

	if spell != null:
		draw_rect(Rect2(0, 12, 3, size.y - 24), accent, true)
