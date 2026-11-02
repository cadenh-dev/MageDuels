class_name AIWizard
extends Node

## Duel AI with an honest, interruptible chant.
##
## State machine: MOVE -> WINDUP -> TYPING -> RECOVER -> MOVE
## - WINDUP (0.35-0.60s) is the visible tell: the wizard is rooted and labelled CHANTING.
## - TYPING feeds real keystrokes through Wizard.chant_key(), never faking the text.
## - Any direct damage interrupts the chant, so the player can punish it.
## - RECOVER leaves a 0.4-0.9s window with no casts.
##
## Behaviour is keyed to the rival's wand, so each fight reads differently.

enum State { MOVE, WINDUP, TYPING, RECOVER }

const ARCHETYPES := {
	"apprentice": {
		"title": "THE RIVAL",
		"range": 6.2,
		"strafe": 1.0,
		"aggression": 1.0,
		"chant_gap": 1.0,
		"preferred": ["fire", "frost", "storm", "arcane", "void", "earth"],
		"forms": ["bolt", "beam", "orb", "nova", "wall", "aegis"],
		"windup": Vector2(0.38, 0.58),
	},
	"emberwood": {
		"title": "CINDER VANGUARD",
		"range": 4.7,
		"strafe": 0.55,
		"aggression": 1.25,
		"chant_gap": 0.80,
		"preferred": ["fire", "earth"],
		"forms": ["bolt", "nova", "beam"],
		"windup": Vector2(0.32, 0.50),
	},
	"frostglass": {
		"title": "EVERFROST ZONER",
		"range": 8.3,
		"strafe": 0.95,
		"aggression": 0.88,
		"chant_gap": 1.25,
		"preferred": ["frost", "arcane"],
		"forms": ["orb", "beam", "wall", "aegis"],
		"windup": Vector2(0.40, 0.60),
	},
	"stormbone": {
		"title": "TEMPEST TRICKSTER",
		"range": 6.3,
		"strafe": 1.45,
		"aggression": 1.05,
		"chant_gap": 1.00,
		"preferred": ["storm", "void"],
		"forms": ["bolt", "beam", "orb"],
		"windup": Vector2(0.34, 0.52),
	},
	"voidheart": {
		"title": "VOIDHEART REVENANT",
		"range": 6.0,
		"strafe": 1.15,
		"aggression": 1.10,
		"chant_gap": 0.95,
		"preferred": ["void", "arcane"],
		"forms": ["orb", "nova"],
		"windup": Vector2(0.36, 0.55),
	},
}

var wizard: Wizard
var target: Wizard
var arena: Arena
var active := true
var difficulty := 1.0
var state := State.MOVE
var archetype: Dictionary = ARCHETYPES["emberwood"]
var rival_title := "RIVAL"

var _state_timer := 0.0
var _cast_timer := 1.2
var _strafe := 1.0
var _range_target := 7.0
var _chant_cooldown := 12.0
var _chant_slot := 0
var _typing_index := 0
var _typing_timer := 0.0
var _typing_interval := 0.11
var _chant_timeout := 0.0
var _page_swap_timer := 9.0
var _aim_offset := Vector3.ZERO
var _aim_timer := 0.0


static func title_for(wand_id: String) -> String:
	var arch: Dictionary = ARCHETYPES.get(wand_id, {})
	return str(arch.get("title", "RIVAL"))


func setup(p_wizard: Wizard, p_target: Wizard, p_arena: Arena) -> void:
	wizard = p_wizard
	target = p_target
	arena = p_arena
	# Run before the wizards consume their movement in physics.
	process_physics_priority = -10

	var wand_id := str(wizard.kit.get("wand_id", "emberwood"))
	archetype = ARCHETYPES.get(wand_id, ARCHETYPES["emberwood"])
	rival_title = str(archetype["title"])
	_range_target = float(archetype["range"]) + randf_range(-0.6, 0.6)
	_cast_timer = randf_range(0.6, 1.4)
	_chant_cooldown = randf_range(7.0, 12.0) * float(archetype["chant_gap"])
	_page_swap_timer = randf_range(7.0, 12.0)
	_strafe = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if not active or wizard == null or not is_instance_valid(wizard) or not wizard.is_alive():
		return
	if target == null or not is_instance_valid(target) or not target.is_alive():
		wizard.set_ai_move(Vector3.ZERO)
		return

	wizard.set_aim_world(target.global_position + target.velocity * 0.14 + _aim_offset)
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		_aim_timer = randf_range(0.35, 0.7)
		_aim_offset = Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))

	_cast_timer -= delta
	_chant_cooldown -= delta
	_page_swap_timer -= delta
	_state_timer -= delta

	match state:
		State.MOVE:
			_think_move(delta)
		State.WINDUP:
			_tick_windup(delta)
		State.TYPING:
			_tick_typing(delta)
		State.RECOVER:
			wizard.set_ai_move(_strafe_move(0.55))
			if _state_timer <= 0.0:
				state = State.MOVE
				_cast_timer = minf(_cast_timer, 0.35)


func _think_move(_delta: float) -> void:
	_move()

	if _chant_cooldown <= 0.0 and _can_see_target() and _nearest_projectile_distance() > 4.2:
		if _try_begin_chant():
			return
		_chant_cooldown = 4.0

	if _page_swap_timer <= 0.0:
		_page_swap_timer = randf_range(8.0, 13.0)
		if not wizard.chanting:
			wizard.swap_page()

	if _cast_timer <= 0.0:
		_cast_timer = randf_range(0.8, 1.6) / (difficulty * float(archetype["aggression"]))
		_quick_cast()


func _tick_windup(delta: float) -> void:
	wizard.set_ai_move(Vector3.ZERO)
	if not wizard.chanting:
		_enter_recover(0.35)
		return
	if _state_timer <= 0.0:
		state = State.TYPING
		_typing_index = 0
		_typing_timer = 0.0
		_typing_interval = randf_range(0.09, 0.14)
		_chant_timeout = 3.5
		wizard.set_ai_move(Vector3.ZERO)
	else:
		# Small pulses make the wind-up readable from across the arena.
		if randf() < delta * 8.0:
			Fx.burst(arena.effects, wizard.get_muzzle_position(), wizard.wand.get("color", Color.WHITE), 2, 1.4, 0.04, 0.25)


func _tick_typing(delta: float) -> void:
	wizard.set_ai_move(Vector3.ZERO)
	if not wizard.chanting:
		_enter_recover(0.45)
		return

	_chant_timeout -= delta
	if _chant_timeout <= 0.0:
		wizard.cancel_chant()
		_enter_recover(0.5)
		return

	var spell := wizard.current_spell(_chant_slot)
	if spell == null:
		wizard.cancel_chant()
		_enter_recover(0.5)
		return

	var incant := spell.incantation_compact()
	_typing_timer -= delta
	if _typing_index < incant.length() and _typing_timer <= 0.0:
		wizard.chant_key(incant.substr(_typing_index, 1))
		_typing_index += 1
		_typing_timer = _typing_interval

	if _typing_index >= incant.length() and wizard.chant_progress() >= 1.0:
		wizard.chant_finish()
		if wizard.chanting:
			# Finish was rejected (rare); try again shortly.
			_typing_timer = 0.15
		else:
			_enter_recover(randf_range(0.4, 0.9))


func _enter_recover(seconds: float) -> void:
	state = State.RECOVER
	_state_timer = seconds
	_cast_timer = maxf(_cast_timer, seconds * 0.5)
	_chant_cooldown = maxf(_chant_cooldown, 3.0)


func _try_begin_chant() -> bool:
	var options: Array[int] = []
	for slot in 4:
		var spell := wizard.current_spell(slot)
		if spell == null or wizard.cooldowns[slot] > 0.0:
			continue
		if spell.form == "wall":
			continue
		var stats := spell.resolved_stats(wizard.wand, true)
		if wizard.mana < float(stats["mana"]) + 5.0:
			continue
		options.append(slot)
	if options.is_empty():
		return false

	var chant_scores: Dictionary = {}
	for slot in options:
		chant_scores[slot] = _score_spell(wizard.current_spell(slot))
	options.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(float(chant_scores[a]), float(chant_scores[b])):
			return a < b
		return float(chant_scores[a]) > float(chant_scores[b])
	)
	_chant_slot = options[0]
	if not wizard.begin_chant(_chant_slot):
		return false

	state = State.WINDUP
	var windup: Vector2 = archetype["windup"]
	_state_timer = randf_range(windup.x, windup.y)
	_chant_cooldown = randf_range(9.0, 15.0) * float(archetype["chant_gap"])
	return true


func _quick_cast() -> void:
	var options: Array[int] = []
	for slot in 4:
		if wizard.cooldowns[slot] > 0.0:
			continue
		var spell := wizard.current_spell(slot)
		if spell == null:
			continue
		var stats := spell.resolved_stats(wizard.wand, false)
		if wizard.mana < float(stats["mana"]):
			continue
		options.append(slot)
	if options.is_empty():
		return

	var scores: Dictionary = {}
	for slot in options:
		scores[slot] = _score_spell(wizard.current_spell(slot))
	options.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(float(scores[a]), float(scores[b])):
			return a < b
		return float(scores[a]) > float(scores[b])
	)

	if wizard.hp / wizard.max_hp < 0.45 and randf() < 0.4:
		for slot in options:
			var form := wizard.current_spell(slot).form
			if form == "wall" or form == "aegis":
				wizard.quickcast(slot)
				return

	wizard.quickcast(options[0])


func _score_spell(spell: SpellDef) -> float:
	var score := 1.0
	if spell.element in archetype["preferred"]:
		score += 0.8
	if spell.form in archetype["forms"]:
		score += 0.45
	if spell.form == "wall":
		score += 1.2 if wizard.hp / wizard.max_hp < 0.6 else -0.6
	if spell.form == "aegis":
		score += 1.4 if wizard.hp / wizard.max_hp < 0.55 else -0.5
	if spell.form == "nova" and wizard.global_position.distance_to(target.global_position) > 5.5:
		score -= 0.8
	if spell.form == "beam" and not _can_see_target():
		score -= 1.2
	score += randf() * 0.25
	return score


func _move() -> void:
	wizard.set_ai_move(_strafe_move(1.0))


func _strafe_move(scale: float) -> Vector3:
	var to := target.global_position - wizard.global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
	var move := Vector3.ZERO

	if dist > _range_target + 1.2:
		move += dir * 0.85
	elif dist < _range_target - 1.3:
		move -= dir * 0.9

	var side := Vector3(-dir.z, 0, dir.x) * _strafe
	move += side * float(archetype["strafe"]) * 0.8

	# Avoid the rim.
	var flat := Vector2(wizard.global_position.x, wizard.global_position.z)
	if flat.length() > 7.2:
		move -= Vector3(flat.x, 0, flat.y).normalized() * 1.2

	# Sidestep incoming fire.
	if _nearest_projectile_distance() < 3.0:
		move += side * 0.9

	return move.normalized() * minf(1.0, move.length()) * scale


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
		if wizard.chanting:
			wizard.cancel_chant()
