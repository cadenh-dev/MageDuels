class_name SpellcraftTest
extends Node

## Headless checks for constructive spellcraft: every one of the 36 cells,
## the cross-material ward order, statuses and the overcast/fizzle rules.
## Run with: godot --headless -- --spellcraft

const H := 1.2

var arena: Arena
var p: Wizard
var e: Wizard
var failures: Array[String] = []
var checks := 0
var wand: Dictionary


func run(_main: Node) -> int:
	print("SPELLCRAFT: start")
	Game.cast_mode = Game.CAST_CLASSIC
	wand = SpellData.wand("apprentice")
	arena = Arena.new()
	add_child(arena)
	arena.build("neutral")
	var kit := Game.wizard_kit("apprentice")
	p = Wizard.new()
	p.setup("P", kit, SpellData.apprentice_pages(), false)
	arena.add_wizard(p)
	e = Wizard.new()
	e.setup("E", kit, SpellData.apprentice_pages(), false)
	arena.add_wizard(e)
	await _frames(3)

	await _fire_cells()
	await _frost_cells()
	await _storm_cells()
	await _earth_cells()
	await _arcane_cells()
	await _void_cells()
	await _cross_material()
	await _statuses()
	_scaling()

	print("SPELLCRAFT: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: %s" % f)
	print("SPELLCRAFT: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	return 0 if failures.is_empty() else 1


# ---- Fire -------------------------------------------------------------------

func _fire_cells() -> void:
	print("SPELLCRAFT: fire")
	await _reset()
	var before := e.hp
	_shoot(p, "fire", "bolt", Vector3(-5, H, 0), Vector3.RIGHT)
	await _wait(0.75)
	_check("Ember Dart hits and burns", e.hp < before and e.burn_time > 0.0, "hp %.1f burn %.2f" % [e.hp, e.burn_time])
	_check("Ember Dart leaves a fire patch where it lands", _zone_near("fire", e.global_position, 1.0) != null)

	# Fireball into a Stone Wall: explodes there, splashes the rival behind it.
	await _reset()
	_ward(e, "earth", Vector3(3.5, 0, 0), Vector3.LEFT)
	e.global_position = Vector3(4.6, 0, 0)
	before = e.hp
	var fb := _shoot(p, "fire", "orb", Vector3(-4, H, 0), Vector3.RIGHT)
	fb.homing = false
	await _wait(1.3)
	_check("Fireball explodes on a solid wall and splashes the rival behind it", e.hp < before, "hp %.1f -> %.1f" % [before, e.hp])
	_check("Fireball leaves burning ground r 2", _zone_near("fire", Vector3(3.5, 0, 0), 1.0, 2.0) != null)
	# Direct target takes only the direct hit (no splash on top).
	await _reset()
	before = e.hp
	var direct := _shoot(p, "fire", "orb", Vector3(3.5, H, 0), Vector3.RIGHT)
	var direct_damage := direct.damage
	await _wait(0.4)
	_check("Fireball direct target takes only the direct hit", absf((before - e.hp) - direct_damage) < 1.2, "took %.1f direct %.1f" % [before - e.hp, direct_damage])

	# Flame Jet: short (8 m) but wide (0.9 m).
	await _reset()
	e.global_position = Vector3(1.5, 0, 0.85)
	before = e.hp
	_cast_at(p, "fire", "beam", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Flame Jet hits anything within 0.9 m of the line", e.hp < before, "hp %.1f" % e.hp)
	await _reset()
	e.global_position = Vector3(4.5, 0, 0)
	before = e.hp
	_cast_at(p, "fire", "beam", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Flame Jet range is 8 m", is_equal_approx(e.hp, before), "hp %.1f" % e.hp)

	# Inferno Ring: burning band at r 4.0-4.8 for 3 s.
	await _reset()
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(4.4, 0, 0)
	_cast_at(p, "fire", "nova", Vector3.ZERO, Vector3.RIGHT)
	var band := _zone_of_shape("band")
	_check("Inferno Ring leaves a burning band r 4.0-4.8", band != null and is_equal_approx(band.inner, 4.0) and is_equal_approx(band.radius, 4.8))
	before = e.hp
	e.burn_time = 0.0
	await _wait(0.6)
	_check("standing in the band burns", e.hp < before and e.burn_time > 0.0, "hp %.1f -> %.1f" % [before, e.hp])

	# Heat Aura: no absorb, burns nearby enemies, melts frost, chill immune.
	await _reset()
	p.global_position = Vector3(0, 0, 0)
	e.global_position = Vector3(1.6, 0, 0)
	_cast_at(p, "fire", "aegis", Vector3.ZERO, Vector3.RIGHT)
	_check("Heat Aura has no absorb", p.has_shield("fire") and p.shield_hp <= 0.0)
	p.apply_chill(0.4, 2.0)
	_check("Heat Aura makes the caster immune to chill", p.slow_time <= 0.0 and p.chill_time <= 0.0)
	before = e.hp
	await _wait(0.6)
	_check("Heat Aura burns enemies within 2.2 m", e.hp < before and e.burn_time > 0.0, "hp %.1f -> %.1f" % [before, e.hp])
	e.global_position = Vector3(5, 0, 0)
	var shard := _shoot(e, "frost", "bolt", Vector3(4, H, 0), Vector3.LEFT)
	before = p.hp
	await _wait(0.4)
	_check("frost projectiles entering a Heat Aura melt", not is_instance_valid(shard) and is_equal_approx(p.hp, before), "p hp %.1f -> %.1f" % [before, p.hp])


# ---- Frost ------------------------------------------------------------------

func _frost_cells() -> void:
	print("SPELLCRAFT: frost")
	await _reset()
	_ward(e, "earth", Vector3(0, 0, 0), Vector3.LEFT)
	var count := arena.projectiles.get_child_count()
	_shoot(p, "frost", "bolt", Vector3(-3, H, 0), Vector3.RIGHT)
	await _wait(0.25)
	var frags := 0
	for c in arena.projectiles.get_children():
		if c is SpellProjectile and bool(c.stats.get("fragment", false)):
			frags += 1
			_check("Ice Shard fragments fly back out", (c as SpellProjectile).direction.x < 0.0)
	_check("Ice Shard shatters into 3 fragments on a wall", frags == 3, "fragments %d (proj before %d)" % [frags, count])

	await _reset()
	e.global_position = Vector3(5, 0, 2.5)
	var globe := _shoot(p, "frost", "orb", Vector3(-5, H, 0), Vector3.RIGHT)
	globe.homing = false
	await _wait(0.8)
	_check("Frost Globe leaves an ice trail", _zone_of_shape("strip", "frost") != null)
	await _reset()
	e.apply_chill(0.4, 2.0)
	_shoot(p, "frost", "orb", Vector3(3.5, H, 0), Vector3.RIGHT)
	await _wait(0.35)
	_check("Frost Globe direct hit freezes a chilled target", e.freeze_time > 0.0, "freeze %.2f" % e.freeze_time)

	await _reset()
	_cast_at(p, "frost", "beam", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Freeze Ray deep chill 60%", is_equal_approx(e.slow_amount, 0.6) and e.slow_time >= 2.4, "slow %.2f %.2fs" % [e.slow_amount, e.slow_time])
	_check("Freeze Ray coats the ground in ice", _zone_of_shape("strip", "frost") != null)

	await _reset()
	p.global_position = Vector3.ZERO
	e.global_position = Vector3(2.5, 0, 0)
	e.apply_chill(0.4, 2.0)
	_cast_at(p, "frost", "nova", Vector3.ZERO, Vector3.RIGHT)
	_check("Rime Burst freezes chilled targets", e.freeze_time > 0.0)
	_check("Rime Burst freezes the floor", _zone_near("frost", Vector3.ZERO, 0.5, 4.8) != null)

	# Ice Wall: blocks wizards, projectiles pass slowed at -25%, shatters.
	await _reset()
	var ice := _ward(p, "frost", Vector3(0, 0, 0), Vector3.RIGHT)
	e.global_position = Vector3(2.0, 0, 0)
	e.set_ai_move(Vector3.LEFT)
	await _wait(1.0)
	e.set_ai_move(Vector3.ZERO)
	_check("Ice Wall blocks wizards", e.global_position.x > 0.2, "x %.2f" % e.global_position.x)
	e.global_position = Vector3(5, 0, 0)
	var bolt := _shoot(p, "storm", "bolt", Vector3(-1.5, H, 0), Vector3.RIGHT)
	var speed0 := bolt.speed
	var dmg0 := bolt.damage
	await _wait(0.12)
	_check("Ice Wall lets a bolt through slowed 50%", is_instance_valid(bolt) and is_equal_approx(bolt.speed, speed0 * 0.5) and bolt.global_position.x > 0.0)
	_check("Ice Wall: the bolt loses 25% damage", is_instance_valid(bolt) and absf(bolt.damage - dmg0 * 0.75) < 0.01)
	_check("Ice Wall takes the bolt's damage", absf(ice.hp - (ice.max_hp - dmg0)) < 0.01, "hp %.1f" % ice.hp)
	e.global_position = Vector3(1.0, 0, 1.0)
	before_hp(e)
	ice.damage_wall(999.0, "storm")
	await _frames(2)
	_check("Ice Wall shatters at 0 HP", not is_instance_valid(ice) or ice.broken)
	_check("shattering Ice Wall hits enemies within 2.5 m and chills", e.hp < e.max_hp and e.chill_time > 0.0, "hp %.1f" % e.hp)

	# Ice Armor: absorb 30, chill immune, fire x2, shatters on break.
	await _reset()
	_cast_at(p, "frost", "aegis", Vector3.ZERO, Vector3.RIGHT)
	_check("Ice Armor absorbs 30", is_equal_approx(p.shield_hp, 30.0))
	p.apply_chill(0.4, 2.0)
	_check("Ice Armor makes the caster immune to chill", p.slow_time <= 0.0)
	p.take_damage(10.0, "fire", Vector3.ZERO, 0.0, true, {"attacker": e})
	_check("fire deals x2 to Ice Armor", is_equal_approx(p.shield_hp, 10.0), "shield %.1f" % p.shield_hp)
	e.global_position = p.global_position + Vector3(2.0, 0, 0)
	p.take_damage(20.0, "storm", e.global_position, 0.0, true, {"attacker": e})
	_check("broken Ice Armor shatters on nearby enemies", e.hp < e.max_hp and e.chill_time > 0.0, "e hp %.1f" % e.hp)


# ---- Storm ------------------------------------------------------------------

func _storm_cells() -> void:
	print("SPELLCRAFT: storm")
	await _reset()
	var spark := _shoot(p, "storm", "bolt", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Spark is the fastest bolt (26 m/s)", is_equal_approx(spark.speed, 26.0))
	var expected := spark.damage * 1.5
	await _wait(0.5)
	_check("Spark jolts and chains 50% back through the victim", e.stun_time > 0.0 and absf((e.max_hp - e.hp) - expected) < 0.6, "took %.1f expected %.1f" % [e.max_hp - e.hp, expected])

	await _reset()
	e.global_position = Vector3(0, 0, 2.6)
	var ball := _shoot(p, "storm", "orb", Vector3(0, H, 0), Vector3.RIGHT)
	ball.speed = 0.0
	await _wait(1.1)
	_check("Ball Lightning zaps the nearest enemy within 3.5 m", e.hp < e.max_hp and e.hp > e.max_hp - 12.0, "hp %.1f" % e.hp)

	await _reset()
	_ward(e, "earth", Vector3(0, 0, 0), Vector3.LEFT)
	# Beam at 45 degrees into a wall facing -x bounces back into the rival.
	e.global_position = Vector3(-3, 0, 3)
	p.global_position = Vector3(-3, 0, -3)
	_cast_at(p, "storm", "beam", Vector3(-3, H, -3), Vector3(1, 0, 1).normalized())
	_check("Chain Lance bounces once off a solid wall", e.hp < e.max_hp and e.stun_time > 0.0, "hp %.1f" % e.hp)

	await _reset()
	p.global_position = Vector3.ZERO
	e.global_position = Vector3(2.0, 0, 0)
	e.begin_chant(0)
	await _wait(0.2)
	_cast_at(p, "storm", "nova", Vector3.ZERO, Vector3.RIGHT)
	_check("Thunderclap jolts 0.5 s and breaks the chant", not e.chanting and e.stun_time > 0.4, "stun %.2f" % e.stun_time)
	e.global_position = Vector3(4.0, 0, 0)
	var hp4 := e.hp
	_cast_at(p, "storm", "nova", Vector3.ZERO, Vector3.RIGHT)
	_check("Thunderclap radius is 3.5 m", is_equal_approx(e.hp, hp4))

	# Tesla Fence: blocks nothing, jolts crossers, zaps nearby.
	await _reset()
	_ward(p, "storm", Vector3(0, 0, 0), Vector3.RIGHT)
	e.global_position = Vector3(1.0, 0, 0)
	e.set_ai_move(Vector3.LEFT)
	await _wait(0.6)
	e.set_ai_move(Vector3.ZERO)
	_check("Tesla Fence lets wizards cross", e.global_position.x < -0.3, "x %.2f" % e.global_position.x)
	_check("crossing a Tesla Fence jolts", e.hp < e.max_hp, "hp %.1f" % e.hp)
	e.global_position = Vector3(5, 0, 0)
	var through := _shoot(p, "fire", "bolt", Vector3(-2, H, 0), Vector3.RIGHT)
	await _wait(0.2)
	_check("Tesla Fence lets projectiles pass", is_instance_valid(through) and through.global_position.x > 0.5)

	# Static Shell: absorb 20, +15% speed, arcs back at attackers.
	await _reset()
	_cast_at(p, "storm", "aegis", Vector3.ZERO, Vector3.RIGHT)
	_check("Static Shell absorbs 20 and speeds you up 15%", is_equal_approx(p.shield_hp, 20.0) and is_equal_approx(p.move_speed_mult(), 1.15))
	_shoot(e, "earth", "bolt", Vector3(-3, H, 0), Vector3.LEFT)
	await _wait(0.35)
	_check("Static Shell arcs back at a direct attacker", e.hp < e.max_hp and e.stun_time > 0.0, "e hp %.1f" % e.hp)


# ---- Earth ------------------------------------------------------------------

func _earth_cells() -> void:
	print("SPELLCRAFT: earth")
	await _reset()
	var stone := _ward(e, "earth", Vector3(0, 0, 0), Vector3.LEFT)
	var sb := _shoot(p, "earth", "bolt", Vector3(-3, H, 0), Vector3.RIGHT)
	var sb_dmg := sb.damage
	await _wait(0.4)
	_check("Stone Bolt deals x1.5 to walls", absf((stone.max_hp - stone.hp) - sb_dmg * 1.5) < 0.05, "lost %.1f dmg %.1f" % [stone.max_hp - stone.hp, sb_dmg])

	await _reset()
	var ice := _ward(e, "frost", Vector3(0, 0, 0), Vector3.LEFT)
	var boulder := _shoot(p, "earth", "orb", Vector3(-3, H, 0), Vector3.RIGHT)
	_check("Boulder rolls low along the ground", boulder.global_position.y < 0.6)
	await _wait(1.1)
	_check("Boulder smashes an Ice Wall", not is_instance_valid(ice) or ice.broken)
	_check("Boulder keeps rolling into the rival", e.hp < e.max_hp, "hp %.1f" % e.hp)

	await _reset()
	_ward(e, "fire", Vector3(-1, 0, 0), Vector3.LEFT)
	stone = _ward(e, "earth", Vector3(2.5, 0, 0), Vector3.LEFT)
	_cast_at(p, "earth", "beam", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Fault Line ignores non-solid walls and is stopped by solid ones", is_equal_approx(e.hp, e.max_hp) and stone.hp < stone.max_hp, "e %.1f stone %.1f" % [e.hp, stone.hp])

	await _reset()
	p.global_position = Vector3.ZERO
	e.global_position = Vector3(2, 0, 0)
	stone = _ward(e, "earth", Vector3(-2.5, 0, 0), Vector3.LEFT)
	ice = _ward(e, "frost", Vector3(0, 0, 3), Vector3.LEFT)
	_cast_at(p, "earth", "nova", Vector3.ZERO, Vector3.RIGHT)
	await _frames(2)
	_check("Quake deals 20 to every wall in radius", is_equal_approx(stone.max_hp - stone.hp, 20.0), "stone lost %.1f" % (stone.max_hp - stone.hp))
	_check("Quake deals x2 to ice", not is_instance_valid(ice) or ice.broken, "40 vs 30 HP ice")
	_check("Quake staggers with heavy knockback", e.stun_time > 0.0 and e._knock.length() > 6.0, "knock %.1f" % e._knock.length())

	# Stone Wall: blocks wizards, bolts and beams; loses HP.
	await _reset()
	stone = _ward(p, "earth", Vector3(0, 0, 0), Vector3.RIGHT)
	e.global_position = Vector3(2.0, 0, 0)
	e.set_ai_move(Vector3.LEFT)
	await _wait(1.0)
	e.set_ai_move(Vector3.ZERO)
	_check("Stone Wall blocks wizards", e.global_position.x > 0.2, "x %.2f" % e.global_position.x)
	e.global_position = Vector3(5, 0, 0)
	_shoot(p, "fire", "bolt", Vector3(-2, H, 0), Vector3.RIGHT)
	await _wait(0.5)
	_check("Stone Wall blocks bolts", is_equal_approx(e.hp, e.max_hp))
	var hp_before := stone.hp
	_check("Stone Wall loses HP to bolts", stone.hp < stone.max_hp)
	_cast_at(p, "frost", "beam", Vector3(-2, H, 0), Vector3.RIGHT)
	_check("Stone Wall blocks beams and takes their damage", is_equal_approx(e.hp, e.max_hp) and stone.hp < hp_before)

	# Stoneskin.
	await _reset()
	_cast_at(p, "earth", "aegis", Vector3.ZERO, Vector3.RIGHT)
	_check("Stoneskin absorbs 45 and slows you 25%", is_equal_approx(p.shield_hp, 45.0) and is_equal_approx(p.move_speed_mult(), 0.75))
	p.take_damage(5.0, "earth", Vector3(-6, 0, 0), 9.0, true, {"attacker": e})
	p.shield_hp = 0.0
	p.take_damage(5.0, "storm", Vector3(-6, 0, 0), 9.0, true, {"attacker": e})
	_check("Stoneskin ignores knockback, stagger and jolt", p._knock.length() < 1.0 and p.stun_time <= 0.0, "knock %.2f stun %.2f" % [p._knock.length(), p.stun_time])


# ---- Arcane -----------------------------------------------------------------

func _arcane_cells() -> void:
	print("SPELLCRAFT: arcane")
	await _reset()
	_ward(e, "earth", Vector3(0, 0, 0), Vector3.LEFT)
	var mana_before := e.mana
	_shoot(p, "arcane", "bolt", Vector3(-5, H, 0), Vector3.RIGHT)
	await _wait(0.75)
	_check("Arcane Missile phases through a Stone Wall", e.hp < e.max_hp)
	_check("Arcane Missile burns mana", e.mana < mana_before - 6.0, "mana %.1f" % e.mana)

	await _reset()
	e.mana = 50.0
	p.mana = 50.0
	var sphere := _shoot(p, "arcane", "orb", Vector3(3, H, 0), Vector3.RIGHT)
	sphere.speed = 0.0
	await _wait(0.6)
	_check("Mana Sphere leeches mana from an enemy within 3 m", e.mana < 50.0 + e.mana_regen * 0.6 - 3.0 and p.mana > 50.0 + p.mana_regen * 0.6 + 3.0, "e %.1f p %.1f" % [e.mana, p.mana])
	sphere.speed = 8.0
	await _reset()
	_ward(e, "earth", Vector3(0, 0, 0), Vector3.LEFT)
	_shoot(p, "arcane", "orb", Vector3(-3, H, 0), Vector3.RIGHT)
	await _wait(1.4)
	_check("Mana Sphere phases through solid walls", e.hp < e.max_hp)

	await _reset()
	_ward(e, "earth", Vector3(0, 0, 0), Vector3.LEFT)
	var ray_stats := _stats("arcane", "beam")
	_cast_at(p, "arcane", "beam", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Arcane Ray passes a wall at -30% damage", absf((e.max_hp - e.hp) - float(ray_stats["damage"]) * 0.7) < 0.2, "took %.1f" % (e.max_hp - e.hp))

	await _reset()
	p.global_position = Vector3.ZERO
	e.global_position = Vector3(6, 0, 0)
	var incoming := _shoot(e, "fire", "bolt", Vector3(2.5, H, 0), Vector3.LEFT)
	_cast_at(p, "arcane", "nova", Vector3.ZERO, Vector3.RIGHT)
	_check("Repulse reflects enemy projectiles and flips ownership", incoming.caster == p and incoming.direction.x > 0.5)
	await _wait(0.4)
	_check("the repulsed bolt hits its original caster", e.hp < e.max_hp)

	await _reset()
	_ward(p, "arcane", Vector3(0, 0, 0), Vector3.RIGHT)
	var enemy_bolt := _shoot(e, "fire", "bolt", Vector3(2, H, 0), Vector3.LEFT)
	await _wait(0.2)
	_check("Mirror Ward reflects an enemy bolt and flips ownership", is_instance_valid(enemy_bolt) and enemy_bolt.caster == p and enemy_bolt.direction.x > 0.5)
	await _wait(0.4)
	_check("the reflected bolt damages its original caster", e.hp < e.max_hp)
	var own := _shoot(p, "fire", "bolt", Vector3(-2, H, 0), Vector3.RIGHT)
	await _wait(0.2)
	_check("own projectiles pass a Mirror Ward", is_instance_valid(own) and own.global_position.x > 0.5 and own.caster == p)
	p.global_position = Vector3(-1.0, 0, 0)
	p.set_ai_move(Vector3.RIGHT)
	await _wait(0.5)
	p.set_ai_move(Vector3.ZERO)
	_check("players pass a Mirror Ward", p.global_position.x > 0.5, "x %.2f" % p.global_position.x)
	await _reset()
	var mirror := _ward(p, "arcane", Vector3(0, 0, 0), Vector3.RIGHT)
	for i in 4:
		_shoot(e, "frost", "bolt", Vector3(2, H, -0.6 + 0.4 * i), Vector3.LEFT)
	await _wait(0.25)
	_check("Mirror Ward breaks after 4 reflections", not is_instance_valid(mirror) or mirror.broken)

	await _reset()
	p.mana = 60.0
	_cast_at(p, "arcane", "aegis", Vector3.ZERO, Vector3.RIGHT)
	p.take_damage(20.0, "fire", Vector3.ZERO, 0.0, true, {"attacker": e})
	_check("Mana Shield spends mana, not health", is_equal_approx(p.hp, p.max_hp) and absf(p.mana - 40.0) < 0.5, "hp %.1f mana %.1f" % [p.hp, p.mana])
	var regen_before := p.mana
	await _wait(0.3)
	_check("Mana Shield pauses mana regen", p.mana <= regen_before + 0.01)
	p.mana = 5.0
	p.take_damage(20.0, "storm", Vector3.ZERO, 0.0, false, {"attacker": e})
	_check("Mana Shield bleeds into health when mana runs out", p.mana <= 0.01 and absf(p.hp - (p.max_hp - 15.0)) < 0.5, "hp %.1f" % p.hp)


# ---- Void -------------------------------------------------------------------

func _void_cells() -> void:
	print("SPELLCRAFT: void")
	await _reset()
	p.hp = 50.0
	_shoot(p, "void", "bolt", Vector3(3.5, H, 0), Vector3.RIGHT)
	await _wait(0.4)
	_check("Void Dart pulls the target toward the caster", e.global_position.x < 4.3, "x %.2f" % e.global_position.x)
	_check("Void Dart drains health", p.hp > 50.0)

	await _reset()
	e.global_position = Vector3(2.5, 0, 0)
	var sing := _shoot(p, "void", "orb", Vector3(0, H, 0), Vector3.RIGHT)
	sing.speed = 0.0
	_shoot(e, "fire", "bolt", Vector3(1.6, H, 0), Vector3.LEFT)
	await _wait(0.25)
	_check("Singularity absorbs enemy projectiles", sing.absorbed == 1 and is_equal_approx(p.hp, p.max_hp), "absorbed %d" % sing.absorbed)
	await _wait(0.4)
	_check("Singularity pulls enemies toward it", e.global_position.x < 2.3, "x %.2f" % e.global_position.x)
	var expected := (12.0 + 3.0) * float(sing.stats.get("power", 1.0))
	e.global_position = Vector3(0.8, 0, 0)
	var hp0 := e.hp
	sing.lifetime = 0.01
	await _wait(0.1)
	_check("Singularity collapses for 12 + 3 per absorbed", absf((hp0 - e.hp) - expected) < 0.6, "took %.1f expected %.1f" % [hp0 - e.hp, expected])

	await _reset()
	p.hp = 50.0
	var siphon := _stats("void", "beam")
	_cast_at(p, "void", "beam", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Siphon drains 50% of its damage", absf(p.hp - (50.0 + float(siphon["damage"]) * 0.5)) < 0.3, "hp %.1f" % p.hp)
	await _wait(0.2)
	_check("Siphon pulls the target in", e.global_position.x < 4.2, "x %.2f" % e.global_position.x)
	await _reset()
	e.global_position = Vector3(13.0 - 5.0 + 4.5, 0, 0)
	_cast_at(p, "void", "beam", Vector3(-5, H, 0), Vector3.RIGHT)
	_check("Siphon range is 12 m", is_equal_approx(e.hp, e.max_hp))

	await _reset()
	p.global_position = Vector3.ZERO
	e.global_position = Vector3(4.0, 0, 0)
	_cast_at(p, "void", "nova", Vector3.ZERO, Vector3.RIGHT)
	await _wait(0.3)
	_check("Implosion pulls everything inward", e.global_position.x < 3.0, "x %.2f" % e.global_position.x)

	# Rift.
	await _reset()
	p.hp = 50.0
	_ward(p, "void", Vector3(0, 0, 0), Vector3.RIGHT)
	var eaten := _shoot(e, "earth", "bolt", Vector3(2, H, 0), Vector3.LEFT)
	var eaten_damage := eaten.damage
	await _wait(0.3)
	_check("Rift consumes an enemy bolt", not is_instance_valid(eaten) and is_equal_approx(p.hp, 50.0 + eaten_damage * 0.25), "p hp %.2f" % p.hp)
	var own := _shoot(p, "earth", "bolt", Vector3(-2, H, 0), Vector3.RIGHT)
	await _wait(0.25)
	_check("own projectiles pass a Rift", is_instance_valid(own) and own.global_position.x > 0.5)
	await _reset()
	_ward(p, "void", Vector3(0, 0, 0), Vector3.RIGHT)
	e.global_position = Vector3(0.3, 0, 0)
	await _wait(0.4)
	_check("enemies inside a Rift are slowed 25%", is_equal_approx(e.slow_amount, 0.25), "slow %.2f" % e.slow_amount)
	e.global_position = Vector3(5, 0, 0)
	var hp_e := e.hp
	_cast_at(e, "storm", "beam", Vector3(4, H, 0), Vector3.LEFT)
	_check("Rift stops enemy beams", is_equal_approx(p.hp, p.max_hp) and is_equal_approx(e.hp, hp_e))

	# Void Shroud: swallows exactly 2 (3 overcast).
	await _reset()
	p.hp = 50.0
	_cast_at(p, "void", "aegis", Vector3.ZERO, Vector3.RIGHT)
	var swallowed := 0
	for i in 3:
		var hp_before := p.hp
		p.take_damage(10.0, "fire", Vector3.ZERO, 0.0, false, {"attacker": e, "projectile": true})
		if p.hp >= hp_before:
			swallowed += 1
	_check("Void Shroud swallows exactly 2 projectile hits", swallowed == 2, "swallowed %d" % swallowed)
	_check("Void Shroud heals 25% of each swallowed hit", absf(p.hp - (50.0 + 5.0 - 10.0)) < 0.2, "hp %.1f" % p.hp)
	await _reset()
	_cast_at(p, "void", "aegis", Vector3.ZERO, Vector3.RIGHT, SpellDef.OVERCAST_MULT)
	swallowed = 0
	for i in 4:
		var hp_before := p.hp
		p.take_damage(10.0, "fire", Vector3.ZERO, 0.0, false, {"attacker": e, "projectile": true})
		if p.hp >= hp_before:
			swallowed += 1
	_check("overcast Void Shroud swallows 3", swallowed == 3, "swallowed %d" % swallowed)
	await _reset()
	_cast_at(p, "void", "aegis", Vector3.ZERO, Vector3.RIGHT)
	p.take_damage(10.0, "fire", Vector3.ZERO, 0.0, false, {"attacker": e, "beam": true})
	_check("beams and novas still hit through a Void Shroud", p.hp < p.max_hp)


# ---- Cross-material -----------------------------------------------------------

func _cross_material() -> void:
	print("SPELLCRAFT: cross-material")
	# Flame Sheet: wizard and bolt pass, wizard burns, bolt ignites.
	await _reset()
	_ward(p, "fire", Vector3(0, 0, 0), Vector3.RIGHT)
	e.global_position = Vector3(1.2, 0, 0)
	e.set_ai_move(Vector3.LEFT)
	await _wait(0.7)
	e.set_ai_move(Vector3.ZERO)
	_check("Flame Sheet lets a wizard through", e.global_position.x < -0.6, "x %.2f" % e.global_position.x)
	_check("Flame Sheet burns the wizard", e.hp < e.max_hp and e.burn_total >= 12.0, "hp %.1f burn %.1f" % [e.hp, e.burn_total])
	await _reset()
	_ward(e, "fire", Vector3(0, 0, 0), Vector3.LEFT)
	var bolt := _shoot(p, "storm", "bolt", Vector3(-2, H, 0), Vector3.RIGHT)
	await _wait(0.1)
	_check("Flame Sheet lets a bolt through and ignites it", is_instance_valid(bolt) and bolt.ignited and bolt.global_position.x > 0.2)
	await _wait(0.3)
	_check("the ignited bolt burns on hit", e.burn_time > 0.0)
	await _reset()
	_ward(e, "fire", Vector3(0, 0, 0), Vector3.LEFT)
	var melt := _shoot(p, "frost", "bolt", Vector3(-2, H, 0), Vector3.RIGHT)
	await _wait(0.3)
	_check("Frost bolt melts in a Flame Sheet", not is_instance_valid(melt) and is_equal_approx(e.hp, e.max_hp))

	await _reset()
	var stone := _ward(e, "earth", Vector3(0, 0, 0), Vector3.LEFT)
	var piercing := _shoot(p, "fire", "bolt", Vector3(-2, H, 0), Vector3.RIGHT, "pierce")
	await _wait(0.6)
	_check("Pierce passes one Stone Wall", e.hp < e.max_hp and is_equal_approx(stone.hp, stone.max_hp))
	await _reset()
	_ward(e, "earth", Vector3(-1, 0, 0), Vector3.LEFT)
	_ward(e, "earth", Vector3(1, 0, 0), Vector3.LEFT)
	_shoot(p, "fire", "bolt", Vector3(-3, H, 0), Vector3.RIGHT, "pierce")
	await _wait(0.6)
	_check("Pierce passes only one wall", is_equal_approx(e.hp, e.max_hp))
	piercing = null

	# Ownership after reflection: drain credit goes to the reflector.
	await _reset()
	p.hp = 50.0
	_ward(p, "arcane", Vector3(0, 0, 0), Vector3.RIGHT)
	e.hp = 60.0
	_shoot(e, "void", "bolt", Vector3(2, H, 0), Vector3.LEFT)
	await _wait(0.5)
	_check("a reflected Void Dart drains for the reflector", p.hp > 50.0 and e.hp < 60.0, "p %.1f e %.1f" % [p.hp, e.hp])


# ---- Statuses -----------------------------------------------------------------

func _statuses() -> void:
	print("SPELLCRAFT: statuses")
	await _reset()
	e.apply_chill(0.4, 2.0)
	_check("first chill only slows", e.freeze_time <= 0.0 and e.slow_time > 0.0)
	e.apply_chill(0.4, 2.0)
	_check("second chill while chilled freezes", is_equal_approx(e.freeze_time, Wizard.FREEZE_TIME))
	_check("freeze roots movement", e.is_rooted_by_status())
	await _wait(0.8)
	e.apply_chill(0.4, 2.0)
	_check("freeze immunity: no refreeze within 3 s", e.freeze_time <= 0.0)
	e.freeze_immune = 0.0
	e.apply_chill(0.4, 2.0)
	_check("freeze returns once immunity ends", e.freeze_time > 0.0)

	await _reset()
	e.begin_chant(0)
	await _wait(0.2)
	e.freeze_time = 0.0
	e.chill_time = 1.0
	e.apply_chill(0.4, 2.0)
	_check("Freeze does not break a chant", e.chanting and e.freeze_time > 0.0)
	e.apply_jolt(Wizard.JOLT_TIME)
	_check("Jolt breaks a chant", not e.chanting and e.stun_time > 0.0)
	await _reset()
	e.take_damage(4.0, "storm", Vector3.ZERO, 0.0, true, {"attacker": p})
	_check("storm hits jolt for 0.25 s", is_equal_approx(e.stun_time, Wizard.JOLT_TIME))
	await _reset()
	e.global_position = Vector3(5, 0, 0)
	e.take_damage(4.0, "void", Vector3.ZERO, 0.0, true, {"pull_to": Vector3.ZERO, "pull": 2.0})
	_check("pull is negative knockback toward the source", e._knock.x < -5.0, "knock %.2f" % e._knock.x)

	# Unit A: a primed spell must not outlive its caster.
	await _reset()
	e.begin_chant(0)
	for ch in e.current_spell(0).incantation_compact():
		e.chant_key(ch)
	await _wait(e.typed_charge_time() + 0.1)
	_check("rival primes", e.primed_slot == 0)
	e.take_damage(9999.0, "void", Vector3.ZERO)
	_check("death discards the primed spell", e.primed_slot < 0 and e.get_primed_spell() == null)
	_check("a dead wizard cannot release", not e.release_primed())


# ---- Scaling ------------------------------------------------------------------

func _scaling() -> void:
	print("SPELLCRAFT: scaling")
	var plain := _stats("fire", "bolt")
	var over := _stats("fire", "bolt", "", SpellDef.OVERCAST_MULT)
	var fizzle := _stats("fire", "bolt")
	SpellDef.apply_fizzle(fizzle)
	_check("zone dps scales x(1 + (m-1) x 0.5) on overcast", is_equal_approx(float(over["zone_mult"]), float(plain["zone_mult"]) * 1.7), "%.3f vs %.3f" % [float(over["zone_mult"]), float(plain["zone_mult"])])
	_check("zone dps x0.5 on fizzle", is_equal_approx(float(fizzle["zone_mult"]), float(plain["zone_mult"]) * 0.5))
	_check("hazard durations x0.5 on fizzle", is_equal_approx(float(fizzle["dur_mult"]), 0.5))
	_check("direct damage x m", absf(float(over["damage"]) - float(plain["damage"]) * 2.4) < 0.1)
	var wall_plain := _stats("earth", "wall")
	var wall_over := _stats("earth", "wall", "", SpellDef.OVERCAST_MULT)
	var wall_heavy := _stats("earth", "wall", "heavy")
	var wall_fizzle := _stats("earth", "wall")
	SpellDef.apply_fizzle(wall_fizzle)
	_check("wall HP x(1 + (m-1) x 0.6) on overcast", is_equal_approx(float(wall_over["wall_hp"]), 60.0 * 1.84), "%.1f" % float(wall_over["wall_hp"]))
	_check("Heavy: +45% wall HP", is_equal_approx(float(wall_heavy["wall_hp"]), 87.0))
	_check("wall HP and duration x0.5 on fizzle", is_equal_approx(float(wall_fizzle["wall_hp"]), 30.0) and is_equal_approx(float(wall_fizzle["duration"]), 4.0))
	_check("plain Stone Wall has 60 HP for 8 s", is_equal_approx(float(wall_plain["wall_hp"]), 60.0) and is_equal_approx(float(wall_plain["duration"]), 8.0))
	var armor_over := _stats("frost", "aegis", "", SpellDef.ASSIST_OVERCAST_MULT)
	var armor_fizzle := _stats("frost", "aegis")
	SpellDef.apply_fizzle(armor_fizzle)
	_check("shield absorb x(1 + (m-1) x 0.6) on assisted overcast", absf(float(armor_over["shield"]) - 30.0 * 1.54) < 0.06, "%.1f" % float(armor_over["shield"]))
	_check("shield absorb x0.5 on fizzle", is_equal_approx(float(armor_fizzle["shield"]), 15.0))
	var perfect := _stats("frost", "aegis", "", SpellDef.ASSIST_OVERCAST_MULT)
	SpellDef.apply_perfect(perfect)
	var m := SpellDef.ASSIST_OVERCAST_MULT * 1.15
	_check("perfect release follows the rule for m x 1.15", absf(float(perfect["shield"]) - 30.0 * (1.0 + (m - 1.0) * 0.6)) < 0.1, "%.2f" % float(perfect["shield"]))
	_check("Mirror Ward +2 reflections when m >= 1.9", int(_stats("arcane", "wall", "", SpellDef.ASSIST_OVERCAST_MULT)["reflections"]) == 6 and int(_stats("arcane", "wall")["reflections"]) == 4)
	_check("Heavy: +45% zone dps", is_equal_approx(float(_stats("fire", "wall", "heavy")["zone_mult"]), 1.45))
	var names_ok := SpellDef.new("fire", "nova", "heavy").display_name() == "Heavy Inferno Ring" and SpellDef.new("fire", "bolt", "track").display_name() == "Seeking Ember Dart"
	_check("display name = modifier prefix + cell name", names_ok)


# ---- Helpers ------------------------------------------------------------------

func _stats(element: String, form: String, modifier: String = "", mult: float = 1.0) -> Dictionary:
	return SpellDef.new(element, form, modifier).resolved_stats(wand, mult > 1.0, mult)


## Spawn one projectile cell at an explicit origin and direction.
func _shoot(caster: Wizard, element: String, form: String, origin: Vector3, dir: Vector3, modifier: String = "") -> SpellProjectile:
	var count := arena.projectiles.get_child_count()
	var spell := SpellDef.new(element, form, modifier)
	arena.spawn_spell(caster, spell, spell.resolved_stats(wand, false), origin, dir)
	return arena.projectiles.get_child(count) as SpellProjectile


func _cast_at(caster: Wizard, element: String, form: String, origin: Vector3, dir: Vector3, mult: float = 1.0) -> void:
	var spell := SpellDef.new(element, form)
	arena.spawn_spell(caster, spell, spell.resolved_stats(wand, mult > 1.0, mult), origin, dir)


## Place a ward of ``owner`` centred on ``at`` facing ``facing``.
func _ward(owner: Wizard, element: String, at: Vector3, facing: Vector3) -> SpellWall:
	var spell := SpellDef.new(element, "wall")
	var wall := SpellWall.new()
	wall.setup_ward({"arena": arena, "owner": owner, "element": element, "stats": spell.resolved_stats(wand, false)})
	arena.walls.add_child(wall)
	wall.global_position = at
	wall.rotation.y = atan2(facing.x, facing.z)
	return wall


func _zone_near(element: String, at: Vector3, tolerance: float, radius: float = -1.0) -> SpellZone:
	for z in arena.active_zones():
		if z.element == element and Vector2(z.global_position.x - at.x, z.global_position.z - at.z).length() <= tolerance:
			if radius < 0.0 or is_equal_approx(z.radius, radius):
				return z
	return null


func _zone_of_shape(shape: String, element: String = "") -> SpellZone:
	for z in arena.active_zones():
		if z.shape == shape and (element == "" or z.element == element):
			return z
	return null


func before_hp(w: Wizard) -> float:
	return w.hp


func _reset() -> void:
	for container in [arena.projectiles, arena.walls, arena.zones]:
		for c in container.get_children():
			c.free()
	for w in [p, e]:
		w.alive = true
		w.hp = w.max_hp
		w.mana = w.max_mana
		w.cancel_chant()
		w.discard_primed()
		w._clear_shield()
		w.burn_time = 0.0
		w.burn_total = 0.0
		w.slow_time = 0.0
		w.slow_amount = 0.0
		w.stun_time = 0.0
		w.chill_time = 0.0
		w.freeze_time = 0.0
		w.freeze_immune = 0.0
		w._knock = Vector3.ZERO
		w._drift = Vector3.ZERO
		w._arc_cooldown = 0.0
		w.set_ai_move(Vector3.ZERO)
		w.velocity = Vector3.ZERO
	p.global_position = Vector3(-5, 0, 0)
	e.global_position = Vector3(5, 0, 0)
	await _frames(2)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		failures.append(label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout
