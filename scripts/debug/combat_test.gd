class_name CombatTest
extends Node

## Headless checks for the spell system. Run with: godot --headless -- --test

var arena: Arena
var p: Wizard
var e: Wizard
var failures: Array[String] = []
var checks := 0


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
	p.cooldowns = [0.0, 0.0, 0.0, 0.0]
	p.set_aim_world(e.global_position)
	_check("wall cast accepted", p.quickcast(2))
	await _wait(0.25)
	var wall_count := 0
	for c in arena.walls.get_children():
		if c is SpellWall:
			wall_count += 1
	_check("wall spawned", wall_count == 1, "walls=%d" % wall_count)
	var blocked_before := e.hp
	p.cooldowns[0] = 0.0
	p.quickcast(0)
	await _wait(0.9)
	_check("wall blocks bolt", is_equal_approx(e.hp, blocked_before), "hp %.1f -> %.1f" % [blocked_before, e.hp])
	for w in arena.walls.get_children():
		w.queue_free()
	await _wait(0.1)

	# --- Nova -------------------------------------------------------------
	e.global_position = p.global_position + Vector3(2.0, 0, 0)
	p.set_aim_world(e.global_position)
	p.mana = p.max_mana
	p.cooldowns = [0.0, 0.0, 0.0, 0.0]
	e.hp = e.max_hp
	var nova_before := e.hp
	_check("nova cast accepted", p.quickcast(3))
	await _wait(0.2)
	_check("nova hits nearby rival", e.hp < nova_before, "hp %.1f -> %.1f" % [nova_before, e.hp])

	# --- Chant / overcast -------------------------------------------------
	e.global_position = Vector3(6, 0, 0)
	p.global_position = Vector3(-6, 0, 0)
	p.set_aim_world(e.global_position)
	p.mana = p.max_mana
	p.cooldowns = [0.0, 0.0, 0.0, 0.0]
	var spell := p.current_spell(0)
	var mana_before := p.mana
	_check("chant starts", p.begin_chant(0))
	var incant := spell.incantation_compact()
	for i in incant.length():
		p.chant_key(incant.substr(i, 1))
	_check("typing completes incantation", p.chant_text == incant, "typed '%s'" % p.chant_text)
	var e_hp_before := e.hp
	p.chant_finish()
	var spent := mana_before - p.mana
	await _wait(0.85)
	_check("overcast costs less mana", spent < float(spell.base_stats()["mana"]), "spent %.1f" % spent)
	var plain_damage := e_hp_before - e.hp
	_check("overcast deals damage", plain_damage > 0.0, "damage %.1f" % plain_damage)
	_check("overcast is empowered", plain_damage > 14.0, "damage %.1f" % plain_damage)

	# --- Page swap --------------------------------------------------------
	var old_page := p.page
	p.swap_page()
	_check("shift swaps page", p.page != old_page, "page %d" % p.page)
	p.swap_page()

	# --- Death ------------------------------------------------------------
	e.take_damage(9999.0, "void", Vector3.ZERO, 0.0)
	await _wait(0.1)
	_check("rival dies", not e.is_alive())

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
