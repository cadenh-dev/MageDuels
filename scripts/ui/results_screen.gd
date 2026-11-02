class_name ResultsScreen
extends Control

signal rematch_pressed
signal menu_pressed

var _won := false
var _score_player := 0
var _score_enemy := 0


func setup(won: bool, score_player: int, score_enemy: int) -> void:
	_won = won
	_score_player = score_player
	_score_enemy = score_enemy


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var accent := UIKit.GOLD if _won else UIKit.DANGER

	var bg := Backdrop.new()
	bg.accent = accent
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var kicker := UIKit.bold_label("THE DUEL IS DECIDED", 14, UIKit.MUTED)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)

	var title := UIKit.heading("VICTORY" if _won else "DEFEAT", 88, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(accent.r, accent.g, accent.b, 0.28))
	box.add_child(title)

	var sub := UIKit.label("The archmage yields." if _won else "The archmage takes the arena.", 20, UIKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(UIKit.vspace(16))

	var score := UIKit.heading("%d  —  %d" % [_score_player, _score_enemy], 46, UIKit.INK)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(score)

	var labels := HBoxContainer.new()
	labels.custom_minimum_size = Vector2(320, 0)
	labels.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(labels)
	for text in ["YOU", "RIVAL"]:
		var l := UIKit.label(text, 12, UIKit.DIM)
		l.custom_minimum_size = Vector2(160, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.add_child(l)

	box.add_child(UIKit.vspace(24))

	var again := UIKit.button("REMATCH", 22)
	again.custom_minimum_size = Vector2(420, 54)
	again.pressed.connect(func() -> void: rematch_pressed.emit())
	box.add_child(again)

	var menu := UIKit.ghost_button("RETURN TO MENU", 18)
	menu.custom_minimum_size = Vector2(420, 46)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(menu)

	var hint := UIKit.label("Tip: your spellbook persists between rematches. Tweak it from the menu.", 13, UIKit.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -64
	hint.offset_bottom = -34
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
