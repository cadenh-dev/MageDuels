extends Node

## Rendered FPS benchmark for the real duel.
##
##   godot --path . -- --fps
##
## Builds the shipped Arena 2.0 duel, keeps both wizards alive, and drives
## continuous combat (player quickcasts + assisted chants, live rival AI).
## Reports average, 1% low, and 0.1% low frame rate at 720p, 1080p, and 720p
## with vsync.
##
## Common options:
##   --fps-only=720p|1080p|720p-vsync   run one pass
##   --fps-seconds=N                    override the pass length
##   --fps-cold                         skip the spellbook warm-up
##   --fps-audio                        unmute (the benchmark is silent by default)
##
## Isolation switches used while tracking down first-use hitches:
##   --fps-idle  --fps-no-ai  --fps-no-chant  --fps-miss  --fps-one-spell
##   --fps-spell=PAGE,SLOT  --fps-custom=ELEMENT,FORM  --fps-no-audio
##   --fps-no-hud  --fps-log
##
## Hit-path isolation: --fps-hits lands one hit on the player every 0.32s with
## no AI and no casting. --fps-hit-part=number|flash|burst|shock|impact|beam
## drives one effect from that path instead of the full hit.

const PASSES := [
	{"name": "720p", "size": Vector2i(1280, 720), "vsync": false, "seconds": 15.0},
	{"name": "1080p", "size": Vector2i(1920, 1080), "vsync": false, "seconds": 12.0},
	{"name": "720p-vsync", "size": Vector2i(1280, 720), "vsync": true, "seconds": 10.0},
]

const CAST_INTERVAL := 0.32
const CHANT_INTERVAL := 4.0

var main: Node
var p: Wizard
var e: Wizard
var arena: Arena
var ai: AIWizard

var _bot_enabled := false
var _cast_accum := 0.0
var _chant_accum := 0.0
var _page := 0
var _rng := RandomNumberGenerator.new()
var _results: Array[Dictionary] = []
var _t0_us := 0
var _log_events := false
var _aim_miss := false
var _no_chant := false
var _one_spell := false
var _force_page := -1
var _force_slot := -1
var _hits := false
var _hit_no_number := false
var _hit_no_flash := false
var _hit_no_burst := false
var _hit_count := 0
var _hit_part := "full"


func run(p_main: Node) -> int:
	main = p_main
	await main._boot()

	# Benchmarks run unattended next to the user; keep the mixer silent unless
	# --fps-audio is passed. Playback still runs, so the workload is unchanged.
	if not ("--fps-audio" in OS.get_cmdline_user_args()):
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var no_audio := "--fps-no-audio" in OS.get_cmdline_user_args()
	# A real player's first menu click runs Audio._unlock_audio(), which warms
	# every baked stream. Benchmarks skip the menu, so do it explicitly.
	if not no_audio and not ("--fps-cold" in OS.get_cmdline_user_args()):
		Audio._unlock_audio()
		await get_tree().create_timer(2.0).timeout
	if no_audio:
		Audio._streams.clear()
		Audio._notes.clear()
		Audio._music_streams.clear()
		Audio._voices.clear()
		Audio._callouts.clear()

	var screen_size := DisplayServer.screen_get_size()
	var refresh := DisplayServer.screen_get_refresh_rate()
	print("FPS: adapter='%s' vendor='%s'" % [
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
	])
	print("FPS: cpu='%s'" % OS.get_processor_name())
	print("FPS: display=%dx%d @ %.0fHz initial_viewport=%s" % [
		screen_size.x, screen_size.y, refresh, str(get_viewport().get_visible_rect().size),
	])

	_rng.randomize()
	Game.start_arena()
	main._build_duel()
	p = main.player as Wizard
	e = main.enemy as Wizard
	arena = main.arena as Arena
	ai = main.ai as AIWizard
	if p == null or e == null or arena == null or ai == null:
		print("FPS: FAIL duel did not build")
		return 1

	p.input_enabled = true
	p.max_hp = 99999.0
	p.hp = p.max_hp
	p.mana = p.max_mana
	e.max_hp = 99999.0
	e.hp = e.max_hp
	e.mana = e.max_mana
	var args := OS.get_cmdline_user_args()
	var idle := "--fps-idle" in args
	var no_ai := "--fps-no-ai" in args
	var cold := "--fps-cold" in args
	_aim_miss = "--fps-miss" in args
	_no_chant = "--fps-no-chant" in args
	_one_spell = "--fps-one-spell" in args
	_log_events = "--fps-log" in args
	_hits = "--fps-hits" in args
	_hit_no_number = "--fps-hit-no-number" in args
	_hit_no_flash = "--fps-hit-no-flash" in args
	_hit_no_burst = "--fps-hit-no-burst" in args
	for arg in args:
		if arg.begins_with("--fps-hit-part="):
			_hit_part = arg.get_slice("=", 1)
	if "--fps-no-callouts" in args:
		Audio._callouts.clear()
	if "--fps-no-hud" in args and main.hud != null:
		main.hud.queue_free()
		main.hud = null
	ai.active = false
	main.duel_active = true
	main.round_running = true
	main._last_action_ms = Time.get_ticks_msec()

	Engine.max_fps = 0
	if not cold:
		await _warm_spellbook()
	if _hits:
		no_ai = true
		_no_chant = true
	ai.active = not idle and not no_ai
	_bot_enabled = not idle
	set_process(not idle)

	if _log_events:
		p.cast_fired.connect(func(_w, spell, _s, _o, _d) -> void:
			_log_event("player cast %s" % spell.display_name()))
		e.cast_fired.connect(func(_w, spell, _s, _o, _d) -> void:
			_log_event("rival cast %s" % spell.display_name()))
		p.chant_changed.connect(func(_w, active: bool) -> void:
			_log_event("player chant %s" % ("start" if active else "end")))
		e.chant_changed.connect(func(_w, active: bool) -> void:
			_log_event("rival chant %s" % ("start" if active else "end")))
		p.chant_interrupted.connect(func(_w) -> void: _log_event("player chant cut"))
		e.chant_interrupted.connect(func(_w) -> void: _log_event("rival chant cut"))
		_log_event("measurement start")

	var only := ""
	var seconds_override := 0.0
	for arg in args:
		if arg.begins_with("--fps-only="):
			only = arg.get_slice("=", 1)
		elif arg.begins_with("--fps-seconds="):
			seconds_override = maxf(0.25, arg.get_slice("=", 1).to_float())
		elif arg.begins_with("--fps-spell="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_force_page = int(parts[0])
				_force_slot = int(parts[1])
		elif arg.begins_with("--fps-custom="):
			var combo := arg.get_slice("=", 1).split(",")
			if combo.size() == 2:
				p.pages[0][0] = SpellDef.new(combo[0], combo[1])
				_force_page = 0
				_force_slot = 0

	# Let the real arena, HUD, and first AI casts settle before measuring.
	await get_tree().create_timer(2.0).timeout
	_t0_us = Time.get_ticks_usec()

	for cfg in PASSES:
		if only != "" and str(cfg["name"]) != only:
			continue
		var pass_cfg: Dictionary = cfg.duplicate()
		if seconds_override > 0.0:
			pass_cfg["seconds"] = seconds_override
		await _run_pass(pass_cfg)

	_bot_enabled = false
	set_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	_print_summary()
	return 0


func _process(delta: float) -> void:
	if not _bot_enabled or p == null or not is_instance_valid(p):
		return

	# Keep the test alive: the benchmark measures rendering, not match length.
	if not p.is_alive():
		p.hp = p.max_hp

	if _hits:
		_cast_accum += delta
		if _cast_accum >= CAST_INTERVAL:
			_cast_accum = 0.0
			_hit_once()
		return

	_cast_accum += delta
	if _cast_accum >= CAST_INTERVAL:
		_cast_accum = 0.0
		p.mana = p.max_mana
		if not p.chanting:
			if _force_slot >= 0:
				p.page = _force_page
				p.selected_slot = _force_slot
			elif _one_spell:
				p.page = 0
				p.selected_slot = 0
			else:
				p.page = _page
				p.selected_slot = _rng.randi_range(0, 3)
			if _aim_miss:
				p.set_aim_world(Vector3(0.0, 0.0, 30.0))
			elif e != null and is_instance_valid(e):
				p.set_aim_world(e.global_position)
			var spell_name := "?"
			if p.pages[p.page][p.selected_slot] is SpellDef:
				spell_name = (p.pages[p.page][p.selected_slot] as SpellDef).display_name()
			var cast_t0 := Time.get_ticks_usec()
			p.quickcast(p.selected_slot)
			var cast_ms := float(Time.get_ticks_usec() - cast_t0) / 1000.0
			if cast_ms > 25.0:
				print("FPS SLOWCAST %.1fms %s" % [cast_ms, spell_name])
			if _rng.randf() < 0.18:
				_page = 1 - _page

	if _no_chant:
		return
	_chant_accum += delta
	if _chant_accum >= CHANT_INTERVAL:
		_chant_accum = 0.0
		if not p.chanting:
			p.begin_chant(_rng.randi_range(0, 3), true)
			if _log_events:
				_log_event("bot assisted chant attempt")


## Land one real hit on the player, with only the hit path running.
func _hit_once() -> void:
	var elements := ["fire", "frost", "storm", "earth", "arcane", "void"]
	var element: String = elements[_rng.randi() % elements.size()]
	_hit_count += 1
	var t0 := Time.get_ticks_usec()
	match _hit_part:
		"number":
			Fx.damage_number(arena.effects, p.global_position + Vector3.UP * 1.9, 5.0, Color.WHITE)
		"flash":
			p._flash()
		"burst":
			Fx.burst(arena.effects, p.global_position + Vector3.UP * 1.0, Color.WHITE, 12, 3.5, 0.06, 0.35)
		"shield":
			p.add_shield(1.0, 5.0)
		"shock":
			Fx.shockwave(arena.effects, p.global_position, Color.WHITE, 3.0)
		"impact":
			arena.impact(p.global_position + Vector3.UP, Color.WHITE, 1.0)
		"beam":
			var tint: Color = SpellData.ELEMENTS.get(element, {}).get("color", Color.WHITE)
			Fx.beam(arena.effects, p.global_position + Vector3.UP * 1.4, e.global_position + Vector3.UP * 1.4, tint)
		"hud":
			p.damaged.emit(p, 5.0)
		_:
			p.take_damage(5.0, element, p.global_position + Vector3(0.0, 0.0, -6.0), 0.4)
			p.hp = p.max_hp
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if ms > 8.0:
		print("FPS SLOWHIT %.1fms %s" % [ms, element])


## Cast the real arena pages once, then render every element x form combo for
## long enough that particle trails and impact bursts actually draw. The boot
## warm-up only holds each spawn for two frames.
func _warm_spellbook() -> void:
	_log_event("spellbook warmup start")
	var saved_page := p.page
	for page in 2:
		for slot in 4:
			p.page = page
			p.selected_slot = slot
			p.mana = p.max_mana
			p.cancel_chant()
			p.set_aim_world(e.global_position)
			p.quickcast(slot)
			await get_tree().create_timer(0.45).timeout
	p.page = saved_page

	var wand := SpellData.wand("apprentice")
	var dir := (e.global_position - p.global_position).normalized()
	for element in SpellData.element_ids():
		for form in SpellData.form_ids():
			var spell := SpellDef.new(element, form)
			var stats := spell.resolved_stats(wand, false)
			arena.spawn_spell(p, spell, stats, p.get_muzzle_position(), dir)
	await get_tree().create_timer(2.0).timeout
	await get_tree().process_frame
	_reset_arena()
	await get_tree().process_frame
	_log_event("spellbook warmup end")


func _run_pass(cfg: Dictionary) -> void:
	var size: Vector2i = cfg["size"]
	var use_vsync: bool = cfg["vsync"]
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if use_vsync else DisplayServer.VSYNC_DISABLED
	)
	DisplayServer.window_set_size(size)
	DisplayServer.window_move_to_foreground()
	_reset_arena()
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	await get_tree().process_frame

	print("FPS pass=%s window=%s target=%s mode=%d focused=%s vsync=%s" % [
		cfg["name"],
		str(DisplayServer.window_get_size()),
		str(get_viewport().get_texture().get_size()),
		DisplayServer.window_get_mode(),
		str(DisplayServer.window_is_focused()),
		str(use_vsync),
	])

	var frames: Array[int] = []
	var draw_sum := 0.0
	var draw_peak := 0.0
	var stalls: Array[String] = []
	var start := Time.get_ticks_usec()
	var last := start
	var now := start
	var duration_us := int(float(cfg["seconds"]) * 1_000_000.0)

	while now - start < duration_us:
		await get_tree().process_frame
		now = Time.get_ticks_usec()
		var frame_us := now - last
		frames.append(frame_us)
		if frame_us > 100_000 and stalls.size() < 8:
			var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			var label := "t=%.1fs %.0fms cpu=%.1fms phys=%.1fms draws=%.0f" % [
				float(now - start) / 1_000_000.0, float(frame_us) / 1000.0,
				proc_ms, phys_ms,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			]
			stalls.append(label)
			if _log_events:
				print("FPS STALL %s" % label)
		last = now
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		draw_sum += draws
		draw_peak = maxf(draw_peak, draws)

	var count := frames.size()
	if count < 2:
		print("FPS: FAIL pass=%s produced no frames" % cfg["name"])
		return

	var sorted := frames.duplicate()
	sorted.sort()
	var total_us := 0
	var over_16 := 0
	var over_33 := 0
	for frame_us in frames:
		total_us += frame_us
		if frame_us > 16667:
			over_16 += 1
		if frame_us > 33333:
			over_33 += 1

	var elapsed_s := float(now - start) / 1_000_000.0
	var avg_ms := float(total_us) / float(count) / 1000.0
	var p50_ms := _percentile_ms(sorted, 0.50)
	var p95_ms := _percentile_ms(sorted, 0.95)
	var p99_ms := _percentile_ms(sorted, 0.99)
	var worst_ms := float(sorted[count - 1]) / 1000.0
	var low1_ms := _slowest_avg_ms(sorted, maxi(1, count / 100))
	var low01_ms := _slowest_avg_ms(sorted, maxi(1, count / 1000))
	var result := {
		"name": str(cfg["name"]),
		"window": DisplayServer.window_get_size(),
		"target": get_viewport().get_texture().get_size(),
		"seconds": elapsed_s,
		"frames": count,
		"avg_fps": 1000.0 / avg_ms,
		"low1_fps": 1000.0 / low1_ms,
		"low01_fps": 1000.0 / low01_ms,
		"worst_ms": worst_ms,
		"p50_ms": p50_ms,
		"p95_ms": p95_ms,
		"p99_ms": p99_ms,
		"over16_pct": 100.0 * float(over_16) / float(count),
		"over33_pct": 100.0 * float(over_33) / float(count),
		"draw_avg": draw_sum / float(count),
		"draw_peak": draw_peak,
	}
	_results.append(result)
	print("FPS pass=%s window=%s target=%s seconds=%.1f frames=%d avg=%.1ffps 1low=%.1ffps 0.1low=%.1ffps min=%.1ffps p50=%.2fms p95=%.2fms p99=%.2fms worst=%.2fms over16=%.1f%% over33=%.1f%% draws=%.0f/%.0f" % [
		result["name"],
		str(result["window"]),
		str(result["target"]),
		result["seconds"],
		count,
		result["avg_fps"],
		result["low1_fps"],
		result["low01_fps"],
		1000.0 / worst_ms,
		p50_ms,
		p95_ms,
		p99_ms,
		worst_ms,
		result["over16_pct"],
		result["over33_pct"],
		result["draw_avg"],
		result["draw_peak"],
	])
	if not stalls.is_empty():
		print("FPS stalls=%s" % ", ".join(stalls))


func _reset_arena() -> void:
	for group in [arena.projectiles, arena.walls, arena.effects]:
		if group == null:
			continue
		for node in group.get_children():
			node.queue_free()
	for wiz in [p, e]:
		if wiz == null or not is_instance_valid(wiz):
			continue
		wiz.cancel_chant()
		wiz._clear_shield()
		wiz.burn_time = 0.0
		wiz.slow_time = 0.0
		wiz.stun_time = 0.0
		wiz.hp = wiz.max_hp
		wiz.mana = wiz.max_mana
	Engine.time_scale = 1.0
	main._last_action_ms = Time.get_ticks_msec()


func _log_event(text: String) -> void:
	if not _log_events:
		return
	print("FPS EVENT t=%.2fs %s" % [float(Time.get_ticks_usec() - _t0_us) / 1_000_000.0, text])


func _percentile_ms(sorted: Array[int], pct: float) -> float:
	var index := clampi(int(round(pct * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return float(sorted[index]) / 1000.0


func _slowest_avg_ms(sorted: Array[int], take: int) -> float:
	var start := maxi(0, sorted.size() - take)
	var total := 0
	for i in range(start, sorted.size()):
		total += sorted[i]
	return float(total) / float(maxi(1, sorted.size() - start)) / 1000.0


func _print_summary() -> void:
	print("FPS SUMMARY")
	for row in _results:
		print("FPS RESULT %-10s avg=%.1f 1low=%.1f 0.1low=%.1f worst=%.2fms over16=%.1f%%" % [
			row["name"], row["avg_fps"], row["low1_fps"], row["low01_fps"],
			row["worst_ms"], row["over16_pct"],
		])
	if _results.is_empty():
		print("FPS: FAIL no passes completed")
