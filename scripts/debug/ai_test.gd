class_name AITest
extends Node

## Verifies the rival's telegraph: it chants visibly, completes honestly, and can be interrupted.
## Run with: godot --headless -- --ai

var _checks := 0
var _failures: Array[String] = []
var main: Node
var _chant_started_ms := -1
var _observed_cast_duration := -1.0


func run(p_main: Node) -> int:
	main = p_main
	print("AI: start")
	Game.player_wand = "emberwood"
	Game.enemy_wand = "frostglass"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)
	Game.reset_match("ai")
	main._build_duel()
	main.enemy.chant_changed.connect(_on_enemy_chant_changed)
	main.enemy.cast_fired.connect(_on_enemy_cast)
	main.enemy.input_enabled = true
	if Game.cast_mode == Game.CAST_CHANT:
		_check("chant AI uses the documented 45 WPM band", is_equal_approx(main.ai._typing_wpm(), 45.0))
		main.enemy.page = 0
		main.ai._page_swap_timer = -0.1
		main.ai._cast_timer = 999.0
		main.ai._chant_cooldown = 999.0
		main.ai._think_move(0.0)
		_check("chant AI swaps to page B", main.enemy.page == 1, "page=%d" % main.enemy.page)
		main.enemy.page = 0
		var saved_page: Array = main.enemy.pages[0]
		main.enemy.pages[0] = [SpellDef.new("earth", "wall"), null, null, null]
		main.enemy.mana = main.enemy.max_mana
		_check("chant AI can begin a wall chant", main.ai._try_begin_chant() and main.enemy.current_spell(main.enemy.chant_slot).form == "wall")
		main.enemy.cancel_chant()
		main.enemy.pages[0] = saved_page
	else:
		_check("classic AI retains fast typing interval", main.enemy.begin_chant(0))
		main.ai._state_timer = 0.0
		main.ai._tick_windup(0.01)
		_check("classic AI typing stays at 0.09–0.14s per character", main.ai._typing_interval >= 0.09 and main.ai._typing_interval <= 0.14, "interval=%.3f" % main.ai._typing_interval)
		main.enemy.cancel_chant()
	main.ai.active = true
	main.ai._chant_cooldown = 0.0
	main.player.max_hp = 9999.0
	main.player.hp = 9999.0
	main.round_running = true
	main.duel_active = true

	_check("archetype title", main.ai.rival_title == "EVERFROST ZONER", main.ai.rival_title)

	if not await _until(func() -> bool: return main.enemy.chanting, 12.0, "rival starts a chant"):
		return _finish()
	_check("chant roots the rival", main.enemy.velocity.length() < 0.5, "vel=%.2f" % main.enemy.velocity.length())

	var completed := await _until(func() -> bool: return main.enemy.primed_slot >= 0, 7.0, "rival primes spell after chant")
	_check("chant resolves", completed)
	if Game.cast_mode == Game.CAST_CHANT:
		await _until(func() -> bool: return main.enemy.primed_slot < 0 and _observed_cast_duration >= 0.0, 2.0, "rival moves and releases primed spell")
		var spell: SpellDef = main.enemy.current_spell(main.enemy.last_cast_slot)
		var expected_min := float(spell.incantation_compact().length()) * 60.0 / (45.0 * 5.0)
		_check("chant-only AI waits for simulated typing", _observed_cast_duration >= expected_min,
			"duration=%.2fs min=%.2fs" % [_observed_cast_duration, expected_min])
	_check("recovery window opens", main.ai.state in [AIWizard.State.PRIMED, AIWizard.State.RECOVER, AIWizard.State.MOVE], "state=%d" % main.ai.state)

	# Force a second chant and break it with direct damage.
	main.ai._chant_cooldown = 0.0
	main.ai.state = AIWizard.State.MOVE
	if not await _until(func() -> bool: return main.enemy.chanting, 10.0, "rival starts a second chant"):
		return _finish()
	await get_tree().create_timer(0.25, false).timeout
	main.enemy.take_damage(1.0, "void", main.player.global_position, 0.0)
	_check("chip damage does not break chant", main.enemy.chanting)
	main.enemy.take_damage(12.0, "void", main.player.global_position, 0.0)
	_check("direct hit interrupts rival", not main.enemy.chanting)
	await get_tree().create_timer(0.15, false).timeout
	_check("rival leaves the chant state", main.ai.state != AIWizard.State.WINDUP and main.ai.state != AIWizard.State.TYPING, "state=%d" % main.ai.state)

	# Let it move again and land at least one spell on the stationary caster.
	main.ai._chant_cooldown = 4.0
	var hurt := await _until(func() -> bool: return main.player.hp < main.player.max_hp, 14.0, "rival lands a spell")
	_check("rival can still deal damage", hurt)

	print("AI: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("AI: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1


func _until(condition: Callable, timeout: float, label: String) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if condition.call():
			return true
		await get_tree().create_timer(0.1, false).timeout
		elapsed += 0.1
	_check(label, false)
	return false


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _finish() -> int:
	print("AI: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("AI: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1


func _on_enemy_chant_changed(wizard: Wizard, active: bool) -> void:
	if wizard == main.enemy and active and _chant_started_ms < 0:
		_chant_started_ms = Time.get_ticks_msec()


func _on_enemy_cast(wizard: Wizard, _spell: SpellDef, _stats: Dictionary, _origin: Vector3, _direction: Vector3) -> void:
	if wizard == main.enemy and _chant_started_ms >= 0:
		_observed_cast_duration = float(Time.get_ticks_msec() - _chant_started_ms) / 1000.0
		_chant_started_ms = -1
