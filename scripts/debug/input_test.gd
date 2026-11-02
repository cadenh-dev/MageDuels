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
	_check("chant begins", p.begin_chant(0))
	await get_tree().process_frame

	for i in incant.length():
		_send_char(incant.substr(i, 1))
		await get_tree().process_frame
	_check("unicode keys advance the chant", p.chant_text == incant, "typed='%s' expected='%s'" % [p.chant_text, incant])

	await get_tree().create_timer(1.0, false).timeout
	var page_before: int = p.page
	_send_key(KEY_ENTER, KEY_ENTER, 13)
	await get_tree().process_frame
	_check("enter completes the overcast", not p.chanting)
	_check("cast went on cooldown", p.cooldowns[0] > 0.0, "cd=%.2f" % p.cooldowns[0])

	_send_key(KEY_SHIFT, KEY_SHIFT, 0)
	await get_tree().process_frame
	_check("shift swaps the page", p.page != page_before, "page=%d" % p.page)
	_send_key(KEY_SHIFT, KEY_SHIFT, 0, false)

	# Rooting: movement input must not move a chanting wizard.
	for i in p.cooldowns.size():
		p.cooldowns[i] = 0.0
	p.mana = p.max_mana
	p.begin_chant(0)
	await get_tree().process_frame
	var before: Vector3 = p.global_position
	_send_key(KEY_A, KEY_A, 97)
	await get_tree().create_timer(0.35, false).timeout
	_send_key(KEY_A, KEY_A, 97, false)
	_check("chant roots the player", before.distance_to(p.global_position) < 0.08, "moved %.2f" % before.distance_to(p.global_position))
	p.cancel_chant()

	# Assisted overcast: hold for 1.4s, no typing.
	for i in p.cooldowns.size():
		p.cooldowns[i] = 0.0
	p.mana = p.max_mana
	_check("assisted chant begins", p.begin_chant(0, true))
	await get_tree().create_timer(1.55, false).timeout
	_check("assisted chant auto-casts", not p.chanting, "chanting=%s" % p.chanting)
	_check("assisted cast went on cooldown", p.cooldowns[0] > 0.0, "cd=%.2f" % p.cooldowns[0])
	_check("assisted flag clears", not p.assisted_chant)

	for i in p.cooldowns.size():
		p.cooldowns[i] = 0.0
	p.mana = p.max_mana
	_last_stats = {}
	_check("perfect window opens", p.begin_chant(0, true))
	await get_tree().create_timer(1.0, false).timeout
	_check("release inside window casts", p.assist_release())
	_check("perfect release flagged", bool(_last_stats.get("perfect", false)), str(_last_stats.get("perfect", false)))

	for i in p.cooldowns.size():
		p.cooldowns[i] = 0.0
	p.mana = p.max_mana
	p.begin_chant(0, true)
	await get_tree().create_timer(0.2, false).timeout
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
