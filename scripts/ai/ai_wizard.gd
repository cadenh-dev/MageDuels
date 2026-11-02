class_name AIWizard
extends Node

## Simple but lively duel AI. Feeds the same Wizard API a human uses.

var wizard: Wizard
var target: Wizard
var arena: Arena
var active := true
var difficulty := 1.0

var _think := 0.0
var _cast_timer := 1.2
var _strafe := 1.0
var _range_target := 7.0
var _chant_cooldown := 12.0
var _chanting := false
var _chant_timer := 0.0
var _chant_spell_slot := 0
var _dodge_timer := 0.0


func setup(p_wizard: Wizard, p_target: Wizard, p_arena: Arena) -> void:
	wizard = p_wizard
	target = p_target
	arena = p_arena
	_range_target = randf_range(5.5, 8.5)
	_cast_timer = randf_range(0.6, 1.5)
	_chant_cooldown = randf_range(10.0, 16.0)


func _process(delta: float) -> void:
	if not active or wizard == null or not is_instance_valid(wizard) or not wizard.is_alive():
		return
	if target == null or not is_instance_valid(target) or not target.is_alive():
		wizard.set_ai_move(Vector3.ZERO)
		return

	_think -= delta
	_cast_timer -= delta
	_chant_cooldown -= delta
	_dodge_timer -= delta

	wizard.set_aim_world(target.global_position + target.velocity * 0.14)

	if _chanting:
		wizard.set_ai_move(Vector3.ZERO)
		_chant_timer -= delta
		if _chant_timer <= 0.0:
			var spell := wizard.current_spell(_chant_spell_slot)
			if spell != null:
				wizard.chant_text = spell.incantation_compact()
				wizard.chant_finish()
			_chanting = false
			_chant_cooldown = randf_range(9.0, 15.0)
			_cast_timer = randf_range(0.5, 1.0)
		return

	_move(delta)

	if _think <= 0.0:
		_think = randf_range(0.4, 0.9) / difficulty
		if randf() < 0.25:
			_strafe *= -1.0
		if randf() < 0.18:
			_range_target = randf_range(5.0, 8.5)

	if _chant_cooldown <= 0.0 and _can_see_target() and _nearest_projectile_distance() > 4.0:
		_try_begin_chant()
		return

	if _cast_timer <= 0.0:
		_cast_timer = randf_range(0.75, 1.7) / difficulty
		_quick_cast()


func _move(delta: float) -> void:
	var to := target.global_position - wizard.global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
	var move := Vector3.ZERO

	if dist > _range_target + 1.2:
		move += dir * 0.85
	elif dist < _range_target - 1.4:
		move -= dir * 0.9

	var side := Vector3(-dir.z, 0, dir.x) * _strafe
	move += side * 0.75

	# Avoid the rim.
	var flat := Vector2(wizard.global_position.x, wizard.global_position.z)
	if flat.length() > 7.2:
		move -= Vector3(flat.x, 0, flat.y).normalized() * 1.2

	# Sidestep incoming fire.
	if _nearest_projectile_distance() < 3.0:
		move += side * 0.9

	wizard.set_ai_move(move.normalized() * minf(1.0, move.length()))


func _quick_cast() -> void:
	var options: Array[int] = []
	for slot in 4:
		if wizard.cooldowns[slot] <= 0.0 and wizard.current_spell(slot) != null:
			var stats := wizard.current_spell(slot).resolved_stats(wizard.wand, false)
			if wizard.mana >= float(stats["mana"]):
				options.append(slot)
	if options.is_empty():
		return

	# Prefer a wall when hurt and pressured, otherwise cast whatever is ready.
	var spell_hp := wizard.hp / wizard.max_hp
	if spell_hp < 0.45 and randf() < 0.35:
		for slot in options:
			var sp := wizard.current_spell(slot)
			if sp.form == "wall":
				wizard.quickcast(slot)
				return
	options.shuffle()
	wizard.quickcast(options[0])


func _try_begin_chant() -> void:
	var slots: Array[int] = []
	for slot in 4:
		var sp := wizard.current_spell(slot)
		if sp == null:
			continue
		if wizard.cooldowns[slot] <= 0.0:
			var stats := sp.resolved_stats(wizard.wand, true)
			if wizard.mana >= float(stats["mana"]):
				slots.append(slot)
	if slots.is_empty():
		return
	_chant_spell_slot = slots[randi() % slots.size()]
	if wizard.begin_chant(_chant_spell_slot):
		_chanting = true
		_chant_timer = randf_range(0.7, 1.1)


func _nearest_projectile_distance() -> float:
	var best := 999.0
	if arena == null or not is_instance_valid(arena):
		return best
	for child in arena.projectiles.get_children():
		if child is SpellProjectile:
			var p := child as SpellProjectile
			if p.caster == wizard:
				continue
			var d := p.global_position.distance_to(wizard.global_position)
			if d < best:
				best = d
	return best


func _can_see_target() -> bool:
	if arena == null:
		return true
	var space := arena.get_world_3d().direct_space_state
	var from := wizard.global_position + Vector3.UP * 1.4
	var to := target.global_position + Vector3.UP * 1.1
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func stop() -> void:
	active = false
	if wizard != null and is_instance_valid(wizard):
		wizard.set_ai_move(Vector3.ZERO)
