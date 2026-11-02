class_name LoadingScreen
extends Control

## Boot screen. The audio bank bake and the shader warm-up run while this is up,
## so the first menu and the first duel do not stutter.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100

	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var glow := ColorRect.new()
	glow.color = Color(0.35, 0.22, 0.6, 0.08)
	glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	glow.size = Vector2(900, 360)
	glow.position = Vector2(-450, -180)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var title := UIKit.heading("SHIFTCAST", 72, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.42, 0.24, 0.78, 0.55))
	box.add_child(title)

	var kicker := UIKit.bold_label("FORGING THE ARENA", 16, UIKit.GOLD)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)

	var hint := UIKit.label("Baking voices  ·  compiling shaders  ·  lighting runes", 14, UIKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var bar := ColorRect.new()
	bar.color = Color(0.55, 0.42, 1.0, 0.35)
	bar.custom_minimum_size = Vector2(360, 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
