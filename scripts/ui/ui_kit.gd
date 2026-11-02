class_name UIKit
extends RefCounted

## Shared look and feel. Every screen builds on these helpers.

const BG := Color("08060f")
const PANEL := Color("130e22")
const PANEL_LIGHT := Color("1d1533")
const PANEL_DARK := Color("0d0a17")
const INK := Color("efe9ff")
const MUTED := Color("9c93b8")
const DIM := Color("6f6789")
const ACCENT := Color("a78bfa")
const ACCENT_DARK := Color("6d4fd6")
const GOLD := Color("ffd166")
const DANGER := Color("ff5d73")
const HEAL := Color("66f2a5")
const MANA := Color("5bd1ff")
const OUTLINE := Color("342a52")

static var _cinzel: Font
static var _rajdhani: Font
static var _rajdhani_bold: Font


static func heading_font() -> Font:
	if _cinzel == null:
		if ResourceLoader.exists("res://assets/fonts/Cinzel.ttf"):
			_cinzel = load("res://assets/fonts/Cinzel.ttf")
		else:
			_cinzel = ThemeDB.fallback_font
	return _cinzel


static func body_font() -> Font:
	if _rajdhani == null:
		if ResourceLoader.exists("res://assets/fonts/Rajdhani-Regular.ttf"):
			_rajdhani = load("res://assets/fonts/Rajdhani-Regular.ttf")
		else:
			_rajdhani = ThemeDB.fallback_font
	return _rajdhani


static func bold_font() -> Font:
	if _rajdhani_bold == null:
		if ResourceLoader.exists("res://assets/fonts/Rajdhani-Bold.ttf"):
			_rajdhani_bold = load("res://assets/fonts/Rajdhani-Bold.ttf")
		else:
			_rajdhani_bold = body_font()
	return _rajdhani_bold


static func heading(text: String, size: int = 44, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", heading_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	return l


static func label(text: String, size: int = 20, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func bold_label(text: String, size: int = 20, color: Color = INK) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", bold_font())
	return l


static func panel_style(bg: Color = PANEL, border: Color = OUTLINE, radius: int = 14, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


static func panel(bg: Color = PANEL, border: Color = OUTLINE, radius: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border, radius))
	return p


static func button(text: String, font_size: int = 22, accent: Color = ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", bold_font())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.add_theme_stylebox_override("normal", _btn_style(Color("191229"), accent.darkened(0.55), 12))
	b.add_theme_stylebox_override("hover", _btn_style(accent.darkened(0.35), accent, 12))
	b.add_theme_stylebox_override("pressed", _btn_style(accent.darkened(0.1), accent.lightened(0.2), 12))
	b.add_theme_stylebox_override("focus", _btn_style(Color(0, 0, 0, 0), accent, 12))
	b.add_theme_stylebox_override("disabled", _btn_style(Color("120d1d"), Color("241c38"), 12))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func _btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func ghost_button(text: String, font_size: int = 18) -> Button:
	var b := button(text, font_size, Color("4a3f6b"))
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", INK)
	return b


static func divider(color: Color = OUTLINE) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(0, 1)
	return line


static func vspace(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func hspace(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	return c


static func centered_label(text: String, size: int = 20, color: Color = MUTED) -> Label:
	var l := label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


static func set_anchors_full(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func shade(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


static func spell_color(spell: SpellDef) -> Color:
	if spell == null:
		return MUTED
	return spell.element_data().get("color", MUTED)
