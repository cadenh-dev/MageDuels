class_name CastTiming
extends Node

## Measures the frame before a cast, the synchronous cast setup, and the first
## two process frames plus first two physics ticks after it.
##
## Run the real Arena spellbook:
##   godot --path . -- --cast-timing
## Run every element x form combination:
##   godot --path . -- --cast-timing-all
## Add --headless for CPU/tick timing without rendering.

var main: Node
var p: Wizard
var arena: Arena
var enemy: Wizard
var _rows: Array[Dictionary] = []
var _failures := 0


func run(p_main: Node, all_spells: bool = false) -> int:
	main = p_main
	print("CAST_TIMING: start mode=%s" % ("all element x form" if all_spells else "arena spellbook"))
	await main._boot()
	Game.start_arena()
	main._build_duel()
	p = main.player as Wizard
	enemy = main.enemy as Wizard
	arena = main.arena as Arena
	p.input_enabled = true
	main.ai.active = false
	main.duel_active = true
	main.round_running = true
	enemy.max_hp = 99999.0
	enemy.hp = 99999.0
	# Miss deliberately: impact/hitstop would contaminate the cast measurement.
	p.set_aim_world(Vector3(0.0, 0.0, 30.0))
	await get_tree().process_frame
	await get_tree().process_frame

	if all_spells:
		for element in SpellData.element_ids():
			for form in SpellData.form_ids():
				var spell := SpellDef.new(element, form)
				p.pages[0][0] = spell
				p.page = 0
				await _measure_cast(spell, 0, "all")
	else:
		for page in 2:
			p.page = page
			for slot in 4:
				var spell: SpellDef = p.pages[page][slot]
				await _measure_cast(spell, slot, "arena", page)

	_print_summary()
	return 0 if _failures == 0 else 1


func _measure_cast(spell: SpellDef, slot: int, mode: String, page: int = 0) -> void:
	if spell == null:
		_failures += 1
		print("CAST_TIMING: FAIL empty slot mode=%s page=%d slot=%d" % [mode, page, slot])
		return

	p.cooldowns[slot] = 0.0
	p.mana = p.max_mana
	p.stun_time = 0.0
	p.cancel_chant()
	p.page = page
	p.selected_slot = slot
	p.set_aim_world(Vector3(0.0, 0.0, 30.0))
	_clear_effects()
	await get_tree().process_frame
	await get_tree().process_frame

	# The last full frame before the cast.
	var pre_start := Time.get_ticks_usec()
	await get_tree().process_frame
	var pre_ms := float(Time.get_ticks_usec() - pre_start) / 1000.0

	var frames: Array[int] = []
	var ticks: Array[int] = []
	var on_frame := func() -> void: frames.append(Time.get_ticks_usec())
	var on_tick := func() -> void: ticks.append(Time.get_ticks_usec())
	get_tree().process_frame.connect(on_frame)
	get_tree().physics_frame.connect(on_tick)

	var cast_start := Time.get_ticks_usec()
	var ok := p.quickcast(slot)
	var cast_end := Time.get_ticks_usec()
	var cast_ms := float(cast_end - cast_start) / 1000.0

	var guard := 0
	while frames.size() < 2 or ticks.size() < 2:
		await get_tree().process_frame
		guard += 1
		if guard > 240:
			_failures += 1
			print("CAST_TIMING: missing frame/tick samples for '%s'" % spell.display_name())
			break
	get_tree().process_frame.disconnect(on_frame)
	get_tree().physics_frame.disconnect(on_tick)

	while frames.size() < 2:
		frames.append(cast_end)
	while ticks.size() < 2:
		ticks.append(cast_end)

	var frame1_ms := float(frames[0] - cast_end) / 1000.0
	var frame2_ms := float(frames[1] - frames[0]) / 1000.0
	var tick1_ms := float(ticks[0] - cast_end) / 1000.0
	var tick2_ms := float(ticks[1] - ticks[0]) / 1000.0

	var label := spell.display_name()
	if mode == "all":
		label = "%s %s" % [spell.element, spell.form]
	var row := {
		"mode": mode,
		"page": page,
		"slot": slot,
		"spell": label,
		"ok": ok,
		"pre_ms": pre_ms,
		"cast_ms": cast_ms,
		"frame1_ms": frame1_ms,
		"frame2_ms": frame2_ms,
		"tick1_ms": tick1_ms,
		"tick2_ms": tick2_ms,
	}
	_rows.append(row)
	if not ok:
		_failures += 1
	print("CAST_TIMING mode=%s page=%d slot=%d spell='%s' ok=%s pre=%.2f cast=%.2f f1=%.2f f2=%.2f t1=%.2f t2=%.2f" % [
		mode, page, slot, label, str(ok), pre_ms, cast_ms, frame1_ms, frame2_ms, tick1_ms, tick2_ms,
	])


func _clear_effects() -> void:
	if arena != null and is_instance_valid(arena):
		for group in [arena.projectiles, arena.walls, arena.effects]:
			if group == null:
				continue
			for node in group.get_children():
				node.queue_free()
	if p != null and is_instance_valid(p):
		p._clear_shield()
		p.burn_time = 0.0
		p.slow_time = 0.0
		p.stun_time = 0.0
	Engine.time_scale = 1.0


func _print_summary() -> void:
	var worst_cast := 0.0
	var worst_cast_name := ""
	var worst_after := 0.0
	var worst_after_name := ""
	for row in _rows:
		if float(row["cast_ms"]) > worst_cast:
			worst_cast = float(row["cast_ms"])
			worst_cast_name = str(row["spell"])
		var after := maxf(
			maxf(float(row["frame1_ms"]), float(row["frame2_ms"])),
			maxf(float(row["tick1_ms"]), float(row["tick2_ms"]))
		)
		if after > worst_after:
			worst_after = after
			worst_after_name = str(row["spell"])
	print("CAST_TIMING rows=%d failures=%d worst_cast=%.2fms (%s) worst_after=%.2fms (%s)" % [
		_rows.size(), _failures, worst_cast, worst_cast_name, worst_after, worst_after_name,
	])
	print("CAST_TIMING: %s" % ("PASS" if _failures == 0 else "FAIL"))
