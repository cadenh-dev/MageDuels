class_name Wizard
extends CharacterBody3D

## A duelist. Owns health, mana, movement, spell slots and typing state.
## The arena resolves spawned spells; the AI/duel controllers feed aim and input.

signal health_changed(wizard, hp, max_hp)
signal mana_changed(wizard, mana, max_mana)
signal died(wizard)
signal cast_fired(wizard, spell, stats, origin, direction)
signal chant_changed(wizard, active)
signal chant_interrupted(wizard)
signal cast_blocked(wizard, reason)
signal damaged(wizard, amount)
signal shield_changed(wizard, shield_hp, shield_max)

const ARENA_RADIUS := 8.1
const HIT_HEIGHT := 0.9
## Charging a typed overcast is deliberately committal: longer than a quickcast
## window, long enough to be seen and interrupted.
const CHANT_MIN_TIME := 1.6
const CHANT_ASSIST_TIME := 2.3
const CHANT_PERFECT_END := 1.95

var wizard_name := "Wizard"
var is_player := false
var kit: Dictionary = {}
var wand: Dictionary = {}
var pages: Array = []
var page := 0
var selected_slot := 0
var last_cast_slot := 0

var max_hp := 100.0
var hp := 100.0
var max_mana := 100.0
var mana := 100.0
var mana_regen := 11.0
var move_speed := 5.5
var alive := true
var input_enabled := true

var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var cooldown_max: Array[float] = [0.4, 0.4, 0.4, 0.4]
var aim_point := Vector3.ZERO
var aim_override := Vector3.INF

var chanting := false
var chant_slot := -1
var chant_text := ""
var chant_typos := 0
var chant_elapsed := 0.0
var assisted_chant := false

var burn_time := 0.0
var burn_total := 0.0
var burn_tick := 0.0
var slow_time := 0.0
var slow_amount := 0.0
var stun_time := 0.0
var shield_hp := 0.0
var shield_max := 0.0
var shield_time := 0.0
var _shield_color := Color("8fe7ff")
var _shield_mesh: MeshInstance3D

var _knock := Vector3.ZERO
var _time := 0.0
var _bob := 0.0
var _model: Node3D
var _staff_light: OmniLight3D
var _muzzle: Node3D
var _bar_fill: MeshInstance3D
var _mana_fill: MeshInstance3D
var _bar_width := 1.3
var _crystal: MeshInstance3D
var _chant_label: Label3D
var _chant_ring: MeshInstance3D
var _flash_meshes: Array[MeshInstance3D] = []
var _flash_tween: Tween
var _base_emission: Dictionary = {}


func setup(p_name: String, p_kit: Dictionary, p_pages: Array, p_is_player: bool) -> void:
	wizard_name = p_name
	is_player = p_is_player
	kit = p_kit
	var wand_override: Variant = p_kit.get("wand", null)
	if wand_override is Dictionary:
		wand = wand_override
	else:
		wand = SpellData.wand(str(p_kit.get("wand_id", "emberwood")))
	pages = p_pages

	max_hp = float(p_kit.get("max_hp", 100.0))
	hp = max_hp
	max_mana = float(p_kit.get("max_mana", 100.0))
	mana = max_mana
	mana_regen = float(p_kit.get("mana_regen", 11.0))
	move_speed = float(p_kit.get("move_speed", 5.5))

	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	_cache_scene()
	_apply_visuals()
	if float(kit.get("start_shield", 0.0)) > 0.0:
		add_shield(float(kit["start_shield"]), 60.0, wand.get("color", Color("8fe7ff")))


func _ready() -> void:
	add_to_group("wizards")
	if is_instance_valid(Audio):
		Audio.register_wizard(self)


func _exit_tree() -> void:
	if is_instance_valid(Audio):
		Audio.unregister_wizard(self)


func _cache_scene() -> void:
	_model = get_node_or_null("Model") as Node3D
	_staff_light = get_node_or_null("Model/Staff/Light") as OmniLight3D
	_muzzle = get_node_or_null("Model/Staff/Muzzle") as Node3D
	_crystal = get_node_or_null("Model/Staff/Crystal") as MeshInstance3D
	_bar_fill = get_node_or_null("Bars/HealthFill") as MeshInstance3D
	_mana_fill = get_node_or_null("Bars/ManaFill") as MeshInstance3D
	_chant_ring = get_node_or_null("ChantRing") as MeshInstance3D
	_chant_label = get_node_or_null("ChantLabel") as Label3D
	_shield_mesh = get_node_or_null("Shield") as MeshInstance3D
	_flash_meshes.clear()
	for path in ["Model/Body", "Model/Head", "Model/Brim", "Model/Hat"]:
		var mi := get_node_or_null(path) as MeshInstance3D
		if mi != null:
			_flash_meshes.append(mi)


func _apply_visuals() -> void:
	var robe: Color = wand.get("color", Color("a78bfa"))
	var body := Fx.standard_material(robe.darkened(0.62))
	body.roughness = 0.85
	var head := Fx.standard_material(Color("e8c9a0"))
	head.roughness = 0.9
	_assign_material("Model/Body", body)
	_assign_material("Model/Trim", Fx.glow_material(robe.lightened(0.15), 1.2))
	_assign_material("Model/Head", head)
	_assign_material("Model/Beard", Fx.standard_material(Color("efe9ff")))
	_assign_material("Model/EyeL", Fx.glow_material(Color("bff6ff"), 3.0))
	_assign_material("Model/EyeR", Fx.glow_material(Color("bff6ff"), 3.0))
	_assign_material("Model/Brim", Fx.standard_material(robe.darkened(0.35)))
	_assign_material("Model/Hat", Fx.standard_material(robe.darkened(0.25)))
	_assign_material("Model/Staff/Shaft", Fx.standard_material(Color("4a3427")))
	_assign_material("Model/Staff/Collar", Fx.glow_material(robe, 1.6))
	_assign_material("Model/Staff/Crystal", Fx.glow_material(robe, 4.0))

	var ring := Fx.glow_material(Color(robe.r, robe.g, robe.b, 0.7), 1.4)
	ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_assign_material("Ring", ring)
	_assign_material("ChantRing", Fx.glow_material(Color("ffd166"), 3.0))

	if _staff_light != null:
		_staff_light.light_color = robe
		_staff_light.light_energy = 0.9
		_staff_light.omni_range = 2.6

	var shield := Fx.glow_material(Color(_shield_color.r, _shield_color.g, _shield_color.b, 0.22), 2.0)
	shield.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shield.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _shield_mesh != null:
		_shield_mesh.material_override = shield

	var back := Fx.standard_material(Color(0.03, 0.02, 0.07, 0.8), 0.0, true)
	back.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	back.no_depth_test = true
	back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_assign_material("Bars/Backing", back)

	var health := Fx.glow_material(Color("66f2a5") if is_player else Color("ff5d73"), 2.4)
	health.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	health.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	health.no_depth_test = true
	_assign_material("Bars/HealthFill", health)

	var mana := Fx.glow_material(Color("5bd1ff"), 2.0)
	mana.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mana.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mana.no_depth_test = true
	_assign_material("Bars/ManaFill", mana)
	_update_bars()


func _assign_material(path: String, mat: Material) -> void:
	var mi := get_node_or_null(path) as MeshInstance3D
	if mi != null:
		mi.material_override = mat


func _physics_process(delta: float) -> void:
	_time += delta
	_tick_timers(delta)
	if not alive:
		return

	var move := Vector3.ZERO
	if is_player and input_enabled and not chanting and stun_time <= 0.0:
		var x := Input.get_axis("move_left", "move_right")
		var f := Input.get_axis("move_back", "move_forward")
		move = Vector3(x, 0, -f)
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var jx := Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_X)
			var jy := Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y)
			if absf(jx) > 0.15 or absf(jy) > 0.15:
				move += Vector3(jx, 0, jy)
		move = move.limit_length(1.0)
	elif not is_player and not chanting:
		move = _ai_move.limit_length(1.0)

	var speed := move_speed
	if slow_time > 0.0:
		speed *= (1.0 - slow_amount)
	if chanting or stun_time > 0.0:
		move = Vector3.ZERO

	velocity = move * speed + _knock
	_knock = _knock.move_toward(Vector3.ZERO, 22.0 * delta)
	move_and_slide()

	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > ARENA_RADIUS:
		flat = flat.normalized() * ARENA_RADIUS
		global_position = Vector3(flat.x, 0.0, flat.y)
		var normal := Vector3(flat.x, 0.0, flat.y).normalized()
		var outward := _knock.dot(normal)
		if outward > 0.0:
			_knock -= normal * outward

	global_position.y = 0.0

	_animate(delta, move.length() > 0.01)
	_update_facing()
	_update_bars()


# ---- AI hook -------------------------------------------------------------

var _ai_move := Vector3.ZERO


func set_ai_move(dir: Vector3) -> void:
	_ai_move = dir


# ---- Casting -------------------------------------------------------------

func current_spell(slot: int = -1) -> SpellDef:
	var s := selected_slot if slot < 0 else slot
	if page < 0 or page >= pages.size():
		return null
	var row: Array = pages[page]
	if s < 0 or s >= row.size():
		return null
	return row[s]


func page_spells(p: int = -1) -> Array:
	var idx := page if p < 0 else p
	if idx < 0 or idx >= pages.size():
		return []
	return pages[idx]


func swap_page() -> void:
	if not alive or chanting or not input_enabled:
		return
	page = 1 - page
	selected_slot = clamp(selected_slot, 0, page_spells().size() - 1)
	Fx.burst(get_parent(), global_position + Vector3.UP * 1.4, wand.get("color", Color.WHITE), 14, 3.0, 0.06, 0.35)
	if _staff_light != null:
		_staff_light.light_energy = 2.4


func can_cast(slot: int, overcast: bool = false, overcast_mult: float = SpellDef.OVERCAST_MULT) -> Dictionary:
	if not alive:
		return {"ok": false, "reason": "You are down."}
	if stun_time > 0.0:
		return {"ok": false, "reason": "Staggered!"}
	var spell := current_spell(slot)
	if spell == null:
		return {"ok": false, "reason": "No spell in that slot."}
	if cooldowns[slot] > 0.001:
		return {"ok": false, "reason": "Recharging."}
	var stats := spell.resolved_stats(wand, overcast, overcast_mult)
	if mana < float(stats["mana"]):
		return {"ok": false, "reason": "Not enough mana."}
	return {"ok": true, "spell": spell, "stats": stats}


func quickcast(slot: int) -> bool:
	if chanting or not input_enabled:
		return false
	if slot < 0 or slot > 3:
		return false
	var check := can_cast(slot, false)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		return false
	_do_cast(slot, false, check)
	return true


func begin_chant(slot: int, p_assisted: bool = false) -> bool:
	if chanting or not alive or not input_enabled:
		return false
	var mult := SpellDef.ASSIST_OVERCAST_MULT if p_assisted else SpellDef.OVERCAST_MULT
	var check := can_cast(slot, true, mult)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		return false
	chanting = true
	assisted_chant = p_assisted
	chant_slot = slot
	chant_text = ""
	chant_typos = 0
	chant_elapsed = 0.0
	selected_slot = slot
	var spell: SpellDef = check["spell"]
	if _chant_label != null:
		_chant_label.text = spell.display_name().to_upper()
	_set_chant_fx(true)
	Fx.burst(get_parent(), global_position + Vector3.UP * 1.55, wand.get("color", Color.WHITE), 14, 3.5, 0.06, 0.45)
	chant_changed.emit(self, true)
	return true


func chant_key(character: String) -> void:
	if not chanting:
		return
	assisted_chant = false
	var spell := current_spell(chant_slot)
	if spell == null:
		cancel_chant()
		return
	var target := spell.incantation_compact()
	var next_char := target.substr(chant_text.length(), 1)
	if character.to_upper() == next_char:
		chant_text += next_char
	else:
		chant_typos += 1
		if chant_text.length() > 0:
			chant_text = ""
		chant_changed.emit(self, true)


func chant_backspace() -> void:
	if not chanting:
		return
	chant_text = chant_text.substr(0, maxi(0, chant_text.length() - 1))
	chant_changed.emit(self, true)


func chant_finish() -> void:
	if not chanting:
		return
	var spell := current_spell(chant_slot)
	if spell == null:
		cancel_chant()
		return
	if chant_elapsed < CHANT_MIN_TIME:
		cast_blocked.emit(self, "The runes are still forming…")
		return
	if chant_text != spell.incantation_compact():
		cancel_chant()
		return
	var check := can_cast(chant_slot, true, SpellDef.OVERCAST_MULT)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		cancel_chant()
		return
	_do_cast(chant_slot, true, check)


func chant_progress() -> float:
	var span := chant_time_target()
	return clampf(chant_elapsed / span, 0.0, 1.0)


## How long this chant needs to hold before it can be unleashed.
func chant_time_target() -> float:
	return CHANT_ASSIST_TIME if assisted_chant else CHANT_MIN_TIME


## The assisted hold's perfect-release window, as a (start, end) pair.
func perfect_window() -> Vector2:
	return Vector2(CHANT_MIN_TIME, CHANT_PERFECT_END)


func _finish_assisted() -> void:
	if not chanting:
		return
	var check := can_cast(chant_slot, true, SpellDef.ASSIST_OVERCAST_MULT)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		cancel_chant()
		return
	_do_cast(chant_slot, true, check, false)


## Release the assisted hold. Releasing before CHANT_MIN_TIME cancels; releasing
## in the CHANT_MIN_TIME..CHANT_PERFECT_END gold window is a perfect cast;
## releasing later still casts, but slower.
func assist_release() -> bool:
	if not chanting or not assisted_chant:
		return false
	if chant_elapsed < CHANT_MIN_TIME:
		cancel_chant()
		return false
	var perfect := chant_elapsed <= CHANT_PERFECT_END
	var check := can_cast(chant_slot, true, SpellDef.ASSIST_OVERCAST_MULT)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		cancel_chant()
		return false
	_do_cast(chant_slot, true, check, perfect)
	return true


func cancel_chant() -> void:
	if not chanting:
		return
	chanting = false
	assisted_chant = false
	chant_slot = -1
	chant_text = ""
	chant_elapsed = 0.0
	_set_chant_fx(false)
	chant_changed.emit(self, false)


func _do_cast(slot: int, overcast: bool, check: Dictionary, perfect: bool = false) -> void:
	var spell: SpellDef = check["spell"]
	var stats: Dictionary = check["stats"]
	if perfect and overcast:
		var bonus := 1.0 + SpellDef.PERFECT_DAMAGE_BONUS
		stats["damage"] = snappedf(float(stats["damage"]) * bonus, 0.1)
		stats["shield"] = snappedf(float(stats["shield"]) * bonus, 0.1)
	stats["perfect"] = perfect
	mana = maxf(0.0, mana - float(stats["mana"]))
	cooldowns[slot] = float(stats["cooldown"])
	cooldown_max[slot] = maxf(0.1, float(stats["cooldown"]))
	selected_slot = slot
	last_cast_slot = slot

	var origin := get_muzzle_position()
	var dir := get_aim_direction()
	Fx.burst(get_parent(), origin, stats["color"], 10, 4.0, 0.05, 0.25)
	if _staff_light != null:
		_staff_light.light_energy = 4.0
	chanting = false
	assisted_chant = false
	chant_slot = -1
	chant_text = ""
	chant_elapsed = 0.0
	_set_chant_fx(false)
	chant_changed.emit(self, false)
	mana_changed.emit(self, mana, max_mana)
	cast_fired.emit(self, spell, stats, origin, dir)


func _tick_timers(delta: float) -> void:
	_time += 0.0
	for i in cooldowns.size():
		cooldowns[i] = maxf(0.0, cooldowns[i] - delta)
	if alive and mana < max_mana:
		var regen := mana_regen * (0.5 if chanting else 1.0)
		mana = minf(max_mana, mana + regen * delta)
		mana_changed.emit(self, mana, max_mana)
	if _staff_light != null:
		_staff_light.light_energy = move_toward(_staff_light.light_energy, 0.9, 6.0 * delta)

	if burn_time > 0.0:
		burn_time -= delta
		burn_tick += delta
		if burn_tick >= 0.5:
			burn_tick -= 0.5
			var tick_damage := burn_total * 0.5 / 3.0
			_apply_direct_damage(tick_damage, Color("ff6b35"), false)
		if burn_time <= 0.0:
			burn_total = 0.0
	if slow_time > 0.0:
		slow_time -= delta
		if slow_time <= 0.0:
			slow_amount = 0.0
	if stun_time > 0.0:
		stun_time = maxf(0.0, stun_time - delta)
	if shield_time > 0.0:
		shield_time -= delta
		if shield_time <= 0.0:
			_clear_shield()
	if chanting:
		chant_elapsed += delta
		if assisted_chant and chant_text.is_empty() and chant_elapsed >= CHANT_ASSIST_TIME:
			_finish_assisted()


# ---- Damage --------------------------------------------------------------

func add_shield(amount: float, duration: float, color: Color = Color("8fe7ff")) -> void:
	if not alive:
		return
	_shield_color = color
	shield_max = maxf(shield_max, amount)
	shield_hp = maxf(shield_hp, amount)
	shield_time = maxf(shield_time, duration)
	if _shield_mesh != null:
		_shield_mesh.visible = true
		var mat := _shield_mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
			mat.emission = color
	shield_changed.emit(self, shield_hp, shield_max)


func _clear_shield() -> void:
	shield_hp = 0.0
	shield_max = 0.0
	shield_time = 0.0
	if _shield_mesh != null:
		_shield_mesh.visible = false
	shield_changed.emit(self, 0.0, 0.0)


func take_damage(amount: float, element: String, source_pos: Vector3, knockback: float = 0.0, apply_status: bool = true) -> void:
	if not alive:
		return

	var incoming := amount
	if shield_hp > 0.0:
		var absorbed := minf(shield_hp, incoming)
		shield_hp -= absorbed
		incoming -= absorbed
		Fx.burst(get_parent(), global_position + Vector3.UP * 1.0, _shield_color, 12, 3.5, 0.06, 0.35)
		if shield_hp <= 0.0:
			_clear_shield()
		else:
			shield_changed.emit(self, shield_hp, shield_max)
	if incoming <= 0.0:
		# The shield held: no damage, no status, no chant interrupt.
		return
	amount = incoming

	if chanting and amount >= 5.0 and chant_elapsed >= 0.15:
		cancel_chant()
		chant_interrupted.emit(self)
	_apply_direct_damage(amount, _element_color(element), true)

	if apply_status:
		match element:
			"fire":
				burn_time = maxf(burn_time, 3.0)
				burn_total = maxf(burn_total, 6.0)
			"frost":
				slow_time = maxf(slow_time, 2.0)
				slow_amount = maxf(slow_amount, 0.4)
			"earth":
				stun_time = maxf(stun_time, 0.35)
				if chanting:
					cancel_chant()
					chant_interrupted.emit(self)
			"arcane":
				mana = maxf(0.0, mana - 12.0)
				mana_changed.emit(self, mana, max_mana)

	if knockback > 0.0:
		var dir := (global_position - source_pos)
		dir.y = 0.0
		if dir.length() < 0.01:
			dir = Vector3.FORWARD
		_knock += dir.normalized() * knockback


func _apply_direct_damage(amount: float, color: Color, show_number: bool) -> void:
	if not alive:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(self, hp, max_hp)
	damaged.emit(self, amount)
	if show_number:
		Fx.damage_number(get_parent(), global_position + Vector3.UP * 1.9, amount, color)
		_flash()
		if _knock.length() < 3.0:
			_knock += Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	if not alive:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp > before:
		health_changed.emit(self, hp, max_hp)
		Fx.burst(get_parent(), global_position + Vector3.UP * 1.0, Color("66f2a5"), 10, 2.5, 0.06, 0.4)


func _die() -> void:
	if not alive:
		return
	alive = false
	cancel_chant()
	_clear_shield()
	Fx.burst(get_parent(), global_position + Vector3.UP * 1.0, wand.get("color", Color.WHITE), 40, 9.0, 0.12, 0.9)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_model, "rotation_degrees:z", 84.0, 0.55).set_ease(Tween.EASE_IN)
	tween.tween_property(_model, "position:y", 0.25, 0.55)
	tween.tween_property(_model, "scale", Vector3(1.0, 0.7, 1.0), 0.55)
	died.emit(self)


func is_alive() -> bool:
	return alive


func _flash() -> void:
	for mi in _flash_meshes:
		if mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_energy_multiplier = 2.0
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.07)
	_flash_tween.tween_callback(_clear_flash)


func _clear_flash() -> void:
	for mi in _flash_meshes:
		if mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override
			mat.emission_enabled = false
			mat.emission_energy_multiplier = 0.0


# ---- Helpers -------------------------------------------------------------

func _element_color(element: String) -> Color:
	var e: Dictionary = SpellData.ELEMENTS.get(element, {})
	return e.get("color", Color.WHITE)


func get_muzzle_position() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return global_position + Vector3.UP * 1.4


func get_aim_direction() -> Vector3:
	if aim_override != Vector3.INF:
		return aim_override.normalized()
	var origin := get_muzzle_position()
	var d := aim_point - origin
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3.FORWARD
	return d.normalized()


## Stable direction for the model's facing. Do not derive this from the staff
## muzzle: the muzzle rotates with the model, which can spiral at close range.
func get_center_aim_direction() -> Vector3:
	if aim_override != Vector3.INF:
		return aim_override.normalized()
	var d := aim_point - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3.FORWARD
	return d.normalized()


func set_aim_world(pos: Vector3) -> void:
	aim_point = pos


func _update_facing() -> void:
	if _model == null:
		return
	var d := get_center_aim_direction()
	var target_y := atan2(-d.x, -d.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, target_y, 0.28)


func _animate(delta: float, moving: bool) -> void:
	if _model == null:
		return
	if moving:
		_bob += delta * 9.0
	else:
		_bob = lerp(_bob, round(_bob / PI) * PI, delta * 3.0)
	_model.position.y = sin(_bob) * (0.05 if moving else 0.01)
	_model.rotation.z = sin(_bob * 0.5) * (0.035 if moving else 0.0)
	if chanting:
		_model.position.y += sin(_time * 18.0) * 0.015
		if _chant_ring != null:
			var s := 1.0 + sin(_time * 7.0) * 0.10
			_chant_ring.scale = Vector3(s, 1.0, s)
		if _crystal != null:
			var c := 1.15 + sin(_time * 10.0) * 0.16
			_crystal.scale = Vector3(c, c, c)
		if _chant_label != null:
			_chant_label.position.y = 3.25 + sin(_time * 3.0) * 0.05
	if _shield_mesh != null and _shield_mesh.visible:
		var sh := 1.0 + sin(_time * 6.0) * 0.03
		_shield_mesh.scale = Vector3(sh, sh, sh)


func _set_chant_fx(active: bool) -> void:
	if _chant_ring != null:
		_chant_ring.visible = active
	if _chant_label != null:
		_chant_label.visible = active
	if _crystal != null and not active:
		_crystal.scale = Vector3.ONE


func _update_bars() -> void:
	if _bar_fill == null:
		return
	var hp_ratio := clampf(hp / max_hp, 0.0, 1.0)
	var mana_ratio := clampf(mana / max_mana, 0.0, 1.0)
	_bar_fill.scale.x = maxf(0.001, hp_ratio)
	_bar_fill.position.x = -(1.0 - hp_ratio) * _bar_width * 0.5
	_mana_fill.scale.x = maxf(0.001, mana_ratio)
	_mana_fill.position.x = -(1.0 - mana_ratio) * _bar_width * 0.5
	var mat: StandardMaterial3D = _bar_fill.material_override
	if mat != null:
		if not is_player:
			mat.albedo_color = Color("ff5d73")
		elif hp_ratio > 0.55:
			mat.albedo_color = Color("66f2a5")
		elif hp_ratio > 0.25:
			mat.albedo_color = Color("ffd166")
		else:
			mat.albedo_color = Color("ff5d73")
