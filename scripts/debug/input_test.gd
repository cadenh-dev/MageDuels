class_name InputTest
extends Node

## Exercises the real input path: unicode chant keys, Enter, Shift, and rooting.
## Run with: godot --headless -- --input

var _checks := 0
var _failures: Array[String] = []
var main: Node
var p: Wizard
var _last_stats: Dictionary = {}


func run(p_main: Node) -> int:
	main = p_main
	print("INPUT: start")
	Game.player_wand = "emberwood"
	Game.enemy_wand = "frostglass"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)
	Game.reset_match("ai")
	main._build_duel()
	p = main.player as Wizard
	p.input_enabled = true
	p.cast_fired.connect(_on_cast)
	main.ai.active = false
	main.duel_active = true
	main.round_running = true

	var spell: SpellDef = p.current_spell(0)
	var incant: String = spell.incantation_compact()
	if Game.cast_mode == Game.CAST_CHANT:
		main._cast_input(0)
	else:
		_check("classic quickcast accepted", p.quickcast(0))
		p.begin_chant(0)
	_check("prepare/chant begins", p.chanting)
	await get_tree().process_frame

	for i in incant.length():
		_send_char(incant.substr(i, 1))
		await get_tree().process_frame
	_check("unicode keys advance the chant", p.chant_text == incant, "typed='%s' expected='%s'" % [p.chant_text, incant])

	await get_tree().create_timer(p.typed_charge_time() + 0.1, false).timeout
	var page_before: int = p.page
	_send_key(KEY_ENTER, KEY_ENTER, 13)
	await get_tree().process_frame
	_check("enter completes the overcast", not p.chanting)
	_check("overcast spent mana", p.mana < p.max_mana - 1.0, "mana=%.1f" % p.mana)

	_send_key(KEY_SHIFT, KEY_SHIFT, 0)
	await get_tree().process_frame
	_check("shift swaps the page", p.page != page_before, "page=%d" % p.page)
	_send_key(KEY_SHIFT, KEY_SHIFT, 0, false)

	# Rooting: movement input must not move a chanting wizard.
	p.mana = p.max_mana
	p.begin_chant(0)
	await get_tree().process_frame
	var before: Vector3 = p.global_position
	_send_key(KEY_A, KEY_A, 97)
	await get_tree().create_timer(0.35, false).timeout
	_send_key(KEY_A, KEY_A, 97, false)
	_check("chant roots the player", before.distance_to(p.global_position) < 0.08, "moved %.2f" % before.distance_to(p.global_position))
	p.cancel_chant()
	p.begin_chant(0)
	_send_key(KEY_BACKSPACE, KEY_BACKSPACE, 8)
	await get_tree().process_frame
	_check("empty backspace cancels", not p.chanting)
	p.begin_chant(0)
	_send_key(KEY_ESCAPE, KEY_ESCAPE, 0)
	await get_tree().process_frame
	_check("escape cancels chant", not p.chanting)

	# Controller route: one face button per rune word, rooted until resolved.
	p.mana = p.max_mana
	spell = p.current_spell(0)
	incant = spell.incantation_compact()
	_check("controller sequence chant starts", p.begin_chant(0, false, true))
	var words := spell.incantation().split(" ", false)
	for word_index in words.size():
		p.controller_chant_button(word_index)
	_check("controller word sequence types spell", p.chant_text == incant)
	var root_before := p.global_position
	await get_tree().create_timer(p.typed_charge_time() + 0.1, false).timeout
	_check("controller sequence auto casts", not p.chanting)
	_check("controller sequence stays rooted", root_before.distance_to(p.global_position) < 0.08)
	p.begin_chant(0, false, true)
	p.controller_chant_button(1)
	_check("wrong controller button behaves as typo", p.chant_typos == 1 and p.chant_text.is_empty())
	_check("controller typo rewinds word index", p.controller_word_index == 0)
	for word_index in words.size():
		p.controller_chant_button(word_index)
	_check("controller chant recovers after typo", p.chant_text == incant)
	var typos_before_extra := p.chant_typos
	p.controller_chant_button(0)
	_check("extra controller press after final word is ignored", p.chant_typos == typos_before_extra and p.chant_text == incant)
	p.cancel_chant()

	# Wheel face buttons must not fall through to the normal cast actions.
	main._chant_wheel_open = true
	var face_a := InputEventJoypadButton.new()
	face_a.button_index = JOY_BUTTON_A
	face_a.pressed = true
	main._unhandled_input(face_a)
	_check("wheel face button does not start a keyboard chant", not p.chanting)
	var lb_release := InputEventJoypadButton.new()
	lb_release.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb_release.pressed = false
	main._unhandled_input(lb_release)
	_check("wheel release starts controller chant", p.chanting and p.controller_chant)

	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_BACK
	back.pressed = true
	main._unhandled_input(back)
	_check("controller Back cancels chant", not p.chanting)
	p.begin_chant(0)
	main._chant_wheel_open = true
	var text_before_wheel_press := p.chant_text
	main._unhandled_input(face_a)
	_check("wheel swallows face buttons during an existing chant", p.chant_text == text_before_wheel_press)
	main._clear_chant_wheel()
	p.cancel_chant()

	p.begin_chant(0, false, true)
	main._chant_wheel_open = true
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	main._unhandled_input(start)
	if Game.cast_mode == Game.CAST_CHANT:
		_check("Start pauses during controller chant", main.is_paused)
		_check("pause closes spell wheel", not main._chant_wheel_open and not main.hud._spell_wheel.visible)
		main._unhandled_input(start)
		_check("Start resumes after controller chant pause", not main.is_paused)
	else:
		_check("classic controller chant input routing is unchanged", not main.is_paused and main._chant_wheel_open)
		main._clear_chant_wheel()
	p.cancel_chant()

	if Game.cast_mode == Game.CAST_CHANT:
		p.begin_chant(0, true)
		var assist_window := p.perfect_window()
		_check("assisted perfect window uses fixed minimum", is_equal_approx(assist_window.x, Wizard.CHANT_MIN_TIME * p.cast_time_mult), "start=%.2f" % assist_window.x)
		_check("assisted perfect window does not invert", assist_window.x <= assist_window.y, "window=%.2f..%.2f" % [assist_window.x, assist_window.y])
		p.cancel_chant()

	# Assisted overcast: hold for the full charge, no typing.
	p.mana = p.max_mana
	_check("assisted chant begins", p.begin_chant(0, true))
	await get_tree().create_timer(p.assist_charge_time() + 0.15, false).timeout
	_check("assisted chant auto-casts", not p.chanting, "chanting=%s" % p.chanting)
	_check("assisted cast spent mana", p.mana < p.max_mana - 1.0, "mana=%.1f" % p.mana)
	_check("assisted flag clears", not p.assisted_chant)

	p.mana = p.max_mana
	_last_stats = {}
	_check("perfect window opens", p.begin_chant(0, true))
	await get_tree().create_timer((p.perfect_window().x + p.perfect_window().y) * 0.5, false).timeout
	_check("release inside window casts", p.assist_release())
	_check("perfect release flagged", bool(_last_stats.get("perfect", false)), str(_last_stats.get("perfect", false)))

	p.mana = p.max_mana
	p.begin_chant(0, true)
	await get_tree().create_timer(p.typed_charge_time() * 0.4, false).timeout
	_check("releasing early cancels assist", not p.assist_release() and not p.chanting)

	var has_joy := false
	for ev in InputMap.action_get_events("cast_1"):
		if ev is InputEventJoypadButton:
			has_joy = true
	_check("controller face-button mapping present", has_joy)
	var has_trigger := false
	for ev in InputMap.action_get_events("assist_chant"):
		if ev is InputEventJoypadMotion:
			has_trigger = true
	_check("controller trigger mapping present", has_trigger)
	var has_wheel := false
	for ev in InputMap.action_get_events("chant_wheel"):
		if ev is InputEventJoypadButton:
			has_wheel = true
	_check("controller chant wheel binding present", has_wheel)
	main._chant_wheel_open = true
	main._clear_duel()
	_check("duel teardown clears and hides the chant wheel", not main._chant_wheel_open and main.hud == null)

	print("INPUT: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("INPUT: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1


func _on_cast(_wiz: Wizard, _spell: SpellDef, stats: Dictionary, _origin: Vector3, _direction: Vector3) -> void:
	_last_stats = stats


func _send_char(ch: String) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.unicode = ch.unicode_at(0)
	ev.keycode = ch.unicode_at(0)
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.pressed = false
	up.unicode = ch.unicode_at(0)
	up.keycode = ch.unicode_at(0)
	Input.parse_input_event(up)


func _send_key(keycode: int, physical: int, unicode: int, pressed: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.pressed = pressed
	ev.keycode = keycode
	ev.physical_keycode = physical
	ev.unicode = unicode
	Input.parse_input_event(ev)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)
