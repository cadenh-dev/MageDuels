class_name MenuScreen
extends Control

const VolumeSliderRow := preload("res://scripts/ui/volume_slider.gd")

signal play_pressed
signal how_pressed
signal quit_pressed
signal online_pressed
var notice := ""

var _how_root: Control
var _play_button: Button
var _how_close: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := Backdrop.new()
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = -26
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(470, 0)
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var kicker := UIKit.bold_label("GAME OFF 2026   ·   THEME: SHIFT", 14, UIKit.GOLD)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_constant_override("outline_size", 4)
	kicker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	box.add_child(kicker)

	var title := UIKit.heading("SHIFTCAST", 94, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.42, 0.24, 0.78, 0.55))
	title.add_theme_color_override("font_shadow_color", Color(0.65, 0.42, 1.0, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	box.add_child(title)

	var subtitle := UIKit.label("Draft the boon.  Shift the duel.", 22, UIKit.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(UIKit.vspace(22))

	var play := UIKit.button("ENTER THE ARENA", 24)
	play.custom_minimum_size = Vector2(470, 58)
	play.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(play)
	_play_button = play
	var online_button := UIKit.ghost_button("ONLINE", 19)
	online_button.pressed.connect(func() -> void: online_pressed.emit())
	box.add_child(online_button)
	if not notice.is_empty():
		var message := UIKit.label(notice, 16, UIKit.GOLD)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(message)

	var how := UIKit.ghost_button("HOW TO PLAY", 19)
	how.custom_minimum_size = Vector2(470, 48)
	how.pressed.connect(func() -> void: how_pressed.emit())
	box.add_child(how)

	var cast_mode_button := UIKit.ghost_button("CAST MODE: CHANT ONLY", 16)
	cast_mode_button.custom_minimum_size = Vector2(470, 42)
	cast_mode_button.pressed.connect(func() -> void:
		var next := Game.CAST_CLASSIC if Game.cast_mode == Game.CAST_CHANT else Game.CAST_CHANT
		Game.set_cast_mode(next)
		cast_mode_button.text = "CAST MODE: %s" % ("CHANT ONLY" if next == Game.CAST_CHANT else "CLASSIC")
	)
	cast_mode_button.text = "CAST MODE: %s" % ("CHANT ONLY" if Game.cast_mode == Game.CAST_CHANT else "CLASSIC")
	box.add_child(cast_mode_button)

	var volume := VolumeSliderRow.new()
	volume.custom_minimum_size = Vector2(470, 22)
	box.add_child(volume)

	if not OS.has_feature("web"):
		var quit := UIKit.ghost_button("QUIT", 17)
		quit.custom_minimum_size = Vector2(470, 40)
		quit.pressed.connect(func() -> void: quit_pressed.emit())
		box.add_child(quit)

	var foot := UIKit.label("Win three rounds.  The loser picks the first boon.", 14, UIKit.DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -64
	foot.offset_bottom = -34
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(foot)

	var version := UIKit.label("v%s  ·  Godot 4.7" % Game.VERSION, 12, Color(0.5, 0.45, 0.62, 0.7))
	version.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	version.position = Vector2(-180, 16)
	version.custom_minimum_size = Vector2(160, 0)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)

	_how_root = _build_how_overlay()
	add_child(_how_root)
	play.grab_focus()


func _build_how_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := UIKit.panel(Color(0.08, 0.06, 0.14, 0.98), UIKit.ACCENT, 16)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(680, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := UIKit.heading("HOW TO PLAY", 38, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(UIKit.divider())

	var lines := [
		["BUILD", "Both duelists start with the Apprentice Wand and the same spellbook. Win rounds to earn boons."],
		["MOVE", "WASD moves. The mouse aims. Stay inside the glowing ring."],
		["CAST MODE", "CHANT ONLY is the default: press 1–4 to prepare, or SPACE to start a free chant, then type the ghosted runes and press ENTER. While chanting, letter keys type instead of moving; ESC or BACKSPACE on an empty line cancels. On controller, hold LB and aim with RS, then release LB to prepare; press A/B/X/Y for each word. BACK cancels and START pauses."],
		["CHANT", "Typed overcast deals ×2.4 damage for full mana. Half-typed still fires a ×0.5 FIZZLE; a direct hit can break the chant. Hold F / RMB / LT for assisted overcast. Choose CLASSIC for instant quickcasts and SPACE typed overcast."],
		["MODIFY", "Runes combine one element, one form, and one modifier. TRACK makes every projectile seek the rival — Fire + TRACK is a seeking bolt."],
		["DRAFT", "After each round the loser picks a boon first. Cards change your wand, add runes, or boost stats, and persist for the match."],
		["WIN", "First wizard to take three rounds wins. The arena element shifts every round and empowers matching spells by 15%."],
	]
	for entry in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var tag := UIKit.bold_label(entry[0], 15, UIKit.GOLD)
		tag.custom_minimum_size = Vector2(104, 0)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		row.add_child(tag)
		var text := UIKit.label(entry[1], 17, UIKit.INK)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(520, 0)
		row.add_child(text)
		box.add_child(row)

	box.add_child(UIKit.vspace(6))
	var close := UIKit.button("GOT IT", 20)
	close.pressed.connect(hide_how)
	box.add_child(close)
	_how_close = close
	return root


func show_how() -> void:
	_how_root.visible = true
	_how_root.modulate.a = 0.0
	if _how_close != null:
		_how_close.grab_focus()
	var tween := create_tween()
	tween.tween_property(_how_root, "modulate:a", 1.0, 0.15)


func hide_how() -> void:
	_how_root.visible = false
	if _play_button != null:
		_play_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _how_root.visible and event.is_action_pressed("pause"):
		hide_how()
		get_viewport().set_input_as_handled()
