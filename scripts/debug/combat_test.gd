class_name CombatTest
extends Node

## Headless checks for the spell system. Run with: godot --headless -- --test

var arena: Arena
var p: Wizard
var e: Wizard
var failures: Array[String] = []
var checks := 0
var last_stats: Dictionary = {}


func run() -> int:
	print("TEST: building arena")
	Game.player_wand = "emberwood"
	Game.enemy_wand = "stormbone"
	Game.arena_element = "fire"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)

	arena = Arena.new()
	add_child(arena)
	arena.build("fire")

	p = Wizard.new()
	p.setup("P", Game.wizard_kit(Game.player_wand), _test_pages(), true)
	arena.add_wizard(p)
	p.global_position = Vector3(-6, 0, 0)

	e = Wizard.new()
	e.setup("E", Game.wizard_kit(Game.enemy_wand), _test_pages(), false)
	arena.add_wizard(e)
	e.global_position = Vector3(6, 0, 0)

	p.cast_fired.connect(_cast)
	e.cast_fired.connect(_cast)
	p.died.connect(func(w): print("TEST: player died"))

	await _wait(0.3)
	if Game.cast_mode == Game.CAST_CHANT:
		_check("quickcast gated in chant-only", not p.quickcast(0))
	# The rest of this suite checks spell resolution mechanics independently of
	# the selected player input mode. InputTest covers prepare and chant routing.
	Game.cast_mode = Game.CAST_CLASSIC

	# --- Projectile hit ---------------------------------------------------
	e.global_position = Vector3(6, 0, 0)
	p.set_aim_world(e.global_position)
	var before := e.hp
	_check("quickcast accepted", p.quickcast(0))
	await _wait(0.85)
	_check("bolt damages rival", e.hp < before, "hp %.1f -> %.1f" % [before, e.hp])
	_check("fire applies burn", e.burn_time > 0.0, "burn_time %.2f" % e.burn_time)

	# Burn tick math
	var burn_before := e.hp
	e._tick_timers(0.5)
	e._tick_timers(0.5)
	_check("burn ticks damage", e.hp < burn_before, "hp %.1f -> %.1f" % [burn_before, e.hp])
	e.burn_time = 0.0
	e.burn_total = 0.0
	e.hp = e.max_hp

	# --- Beam -------------------------------------------------------------
	e.global_position = Vector3(6, 0, 0)
	p.set_aim_world(e.global_position)
	var beam_before := e.hp
	_check("beam cast accepted", p.quickcast(1))
	await _wait(0.2)
	_check("beam hits instantly", e.hp < beam_before, "hp %.1f -> %.1f" % [beam_before, e.hp])
	e.slow_time = 0.0
	e.hp = e.max_hp
	e.global_position = Vector3(6, 0, 0)

	# --- Wall blocks ------------------------------------------------------
	p.mana = p.max_mana
	p.set_aim_world(e.global_position)
	_check("wall cast accepted", p.quickcast(2))
	await _wait(0.25)
	var wall_count := 0
	for c in arena.walls.get_children():
		if c is SpellWall:
			wall_count += 1
	_check("wall spawned", wall_count == 1, "walls=%d" % wall_count)
	var blocked_before := e.hp
	p.quickcast(0)
	await _wait(0.9)
	_check("wall blocks bolt", is_equal_approx(e.hp, blocked_before), "hp %.1f -> %.1f" % [blocked_before, e.hp])
	for w in arena.walls.get_children():
		w.queue_free()
	await _wait(0.1)

	# --- Aegis shield -----------------------------------------------------
	p.hp = p.max_hp
	p.burn_time = 0.0
	p.burn_total = 0.0
	p.add_shield(30.0, 3.0, Color("8fe7ff"))
	var hp_before_shield := p.hp
	p.take_damage(20.0, "fire", Vector3.ZERO, 0.0)
	_check("shield absorbs a hit", is_equal_approx(p.hp, hp_before_shield) and is_equal_approx(p.shield_hp, 10.0), "hp %.1f shield %.1f" % [p.hp, p.shield_hp])
	p.take_damage(20.0, "fire", Vector3.ZERO, 0.0)
	_check("shield breaks and bleeds through", p.hp < hp_before_shield and p.shield_hp <= 0.0, "hp %.1f shield %.1f" % [p.hp, p.shield_hp])
	p.burn_time = 0.0
	p.burn_total = 0.0
	p.hp = p.max_hp

	# --- Nova -------------------------------------------------------------
	e.global_position = p.global_position + Vector3(2.0, 0, 0)
	p.set_aim_world(e.global_position)
	p.mana = p.max_mana
	e.hp = e.max_hp
	var nova_before := e.hp
	_check("nova cast accepted", p.quickcast(3))
	await _wait(0.2)
	_check("nova hits nearby rival", e.hp < nova_before, "hp %.1f -> %.1f" % [nova_before, e.hp])

	# --- Tracking modifier ------------------------------------------------
	e.global_position = Vector3(6, 0, 0)
	p.global_position = Vector3(-6, 0, 0)
	e.hp = e.max_hp
	p.hp = p.max_hp
	var track := SpellDef.new("fire", "bolt", "track")
	var track_stats := track.resolved_stats(p.wand, false)
	_check("tracking modifier flags homing", bool(track_stats.get("homing", false)))
	_check("tracking has turn strength", float(track_stats.get("homing_strength", 0.0)) > 3.0)
	var count_before := arena.projectiles.get_child_count()
	arena.spawn_spell(p, track, track_stats, p.get_muzzle_position(), Vector3.BACK)
	await _wait(0.05)
	var proj: SpellProjectile = null
	if arena.projectiles.get_child_count() > count_before:
		proj = arena.projectiles.get_child(arena.projectiles.get_child_count() - 1)
	_check("tracking projectile spawned", proj != null)
	if proj != null:
		var away := (e.global_position - proj.global_position).normalized()
		var before_dot := proj.direction.dot(away)
		await _wait(0.25)
		away = (e.global_position - proj.global_position).normalized()
		_check("tracking curves toward rival", proj.direction.dot(away) > before_dot,
			"dot %.3f -> %.3f" % [before_dot, proj.direction.dot(away)])

	# --- Chant / overcast -------------------------------------------------
	e.global_position = Vector3(6, 0, 0)
	p.global_position = Vector3(-6, 0, 0)
	p.set_aim_world(e.global_position)
	p.mana = p.max_mana
	var spell := p.current_spell(0)
	var mana_before := p.mana
	_check("chant starts", p.begin_chant(0))
	var incant := spell.incantation_compact()
	for i in incant.length():
		p.chant_key(incant.substr(i, 1))
	_check("typing completes incantation", p.chant_text == incant, "typed '%s'" % p.chant_text)
	p.chant_finish()
	_check("windup blocks instant finish", p.chanting, "still chanting")
	await _wait(p.typed_charge_time() + 0.1)
	var e_hp_before := e.hp
	p.chant_finish()
	var spent := mana_before - p.mana
	await _wait(0.85)
	_check("overcast pays full mana", absf(spent - float(spell.base_stats()["mana"])) < 0.2, "spent %.1f" % spent)
	var plain_damage := e_hp_before - e.hp
	_check("overcast deals damage", plain_damage > 0.0, "damage %.1f" % plain_damage)
	_check("overcast is empowered", plain_damage > 14.0, "damage %.1f" % plain_damage)

	# --- Partial incantation / fizzle -------------------------------------
	e.hp = e.max_hp
	e.burn_time = 0.0
	e.burn_total = 0.0
	p.mana = p.max_mana
	p.set_aim_world(e.global_position)
	var fizzle_spell := p.current_spell(0)
	var fizzle_text := fizzle_spell.incantation_compact()
	var half := maxi(1, int(ceil(float(fizzle_text.length()) * Wizard.PARTIAL_CAST_RATIO)))
	last_stats = {}
	_check("partial chant starts", p.begin_chant(0))
	for i in half:
		p.chant_key(fizzle_text.substr(i, 1))
	_check("partial typing reaches half", p.chant_accuracy() >= Wizard.PARTIAL_CAST_RATIO, "acc=%.2f" % p.chant_accuracy())
	await _wait(p.typed_charge_time() + 0.1)
	var fizzle_hp := e.hp
	p.chant_finish()
	_check("partial incantation still casts", not p.chanting)
	_check("partial cast is flagged fizzle", bool(last_stats.get("fizzle", false)))
	await _wait(0.85)
	_check("fizzle deals reduced damage", e.hp < fizzle_hp and fizzle_hp - e.hp < 10.0, "damage %.1f" % (fizzle_hp - e.hp))
	_check("fizzle skips status riders", e.burn_time <= 0.0, "burn=%.2f" % e.burn_time)

	p.mana = p.max_mana
	last_stats = {}
	var low := maxi(0, half - 1)
	_check("low chant starts", p.begin_chant(0))
	for i in low:
		p.chant_key(fizzle_text.substr(i, 1))
	await _wait(p.typed_charge_time() + 0.1)
	p.chant_finish()
	_check("below half cancels instead", not p.chanting and last_stats.is_empty(), "stats=%s" % str(last_stats))

	# --- Chant interrupt --------------------------------------------------
	p.mana = p.max_mana
	_check("chant starts again", p.begin_chant(0))
	await _wait(0.25)
	p.take_damage(5.0, "void", Vector3.ZERO, 0.0)
	_check("direct damage interrupts chant", not p.chanting)

	# --- Page swap --------------------------------------------------------
	var old_page := p.page
	p.swap_page()
	_check("shift swaps page", p.page != old_page, "page %d" % p.page)
	p.swap_page()

	# --- Death ------------------------------------------------------------
	e.take_damage(9999.0, "void", Vector3.ZERO, 0.0)
	await _wait(0.1)
	_check("rival dies", not e.is_alive())
	if "--cast-mode" in OS.get_cmdline_user_args():
		var args := OS.get_cmdline_user_args()
		var mode_index := args.find("--cast-mode")
		if mode_index + 1 < args.size():
			Game.cast_mode = Game.CAST_CHANT if args[mode_index + 1] == "chant" else Game.CAST_CLASSIC

	print("TEST: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: %s" % f)
	print("TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	return 0 if failures.is_empty() else 1


func _test_pages() -> Array:
	var row_a: Array[SpellDef] = [
		SpellDef.new("fire", "bolt"),
		SpellDef.new("frost", "beam"),
		SpellDef.new("earth", "wall"),
		SpellDef.new("fire", "nova"),
	]
	var row_b: Array[SpellDef] = [
		SpellDef.new("storm", "bolt", "split"),
		SpellDef.new("void", "orb"),
		SpellDef.new("arcane", "beam", "quick"),
		SpellDef.new("frost", "wall"),
	]
	return [row_a, row_b]


func _cast(caster: Wizard, spell: SpellDef, stats: Dictionary, origin: Vector3, direction: Vector3) -> void:
	last_stats = stats
	arena.spawn_spell(caster, spell, stats, origin, direction)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		failures.append(label)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout
