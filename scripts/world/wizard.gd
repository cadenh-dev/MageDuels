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
const CHANT_ONLY_CHAR_RATE := 8.0
const CHANT_ASSIST_TIME := 2.3
const CHANT_PERFECT_END := 1.95
## A failed incantation is not wasted if the caster got at least this far.
## It becomes a fizzle: half power, full mana.
const PARTIAL_CAST_RATIO := 0.5
const PARTIAL_CAST_MULT := 0.5
const PRIMED_LIMIT := 6.0

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
## Wand/boon multiplier on the chant windup. Lower is faster. Quickcasts have
## no per-spell cooldown: mana is the only repeat-cast cost.
var cast_time_mult := 1.0
var alive := true
var input_enabled := true
## Online controller supplies movement even for the locally labelled wizard.
var external_input := false

var aim_point := Vector3.ZERO
var aim_override := Vector3.INF

var chanting := false
var chant_slot := -1
var chant_text := ""
var chant_typos := 0
var chant_elapsed := 0.0
var assisted_chant := false
var controller_chant := false
var controller_word_index := 0
## Best correct-prefix length reached this chant, kept across typo resets so a
## late slip still leaves the player a weak partial cast.
var chant_best := 0
var primed_slot := -1
## Page the primed spell came from. Page swap is allowed while primed, so the
## primed spell must never be re-read through ``current_spell(primed_slot)``.
var primed_page := -1
var primed_remaining := 0.0
var primed_spell: SpellDef
var _primed_check: Dictionary = {}

const FREEZE_TIME := 0.6
const FREEZE_IMMUNITY := 3.0
const CHILL_SLOW := 0.4
const CHILL_TIME := 2.0
const JOLT_TIME := 0.25
const STAGGER_TIME := 0.35
const BURN_TOTAL := 6.0
const MANA_BURN := 12.0
## Wizards are on layer 2; solid wards (Stone Wall, Ice Wall) on layer 4.
const WALL_LAYER := 4

var burn_time := 0.0
var burn_total := 0.0
var burn_tick := 0.0
var slow_time := 0.0
var slow_amount := 0.0
var stun_time := 0.0
## Frost chill marker: a second chill while this runs freezes.
var chill_time := 0.0
var freeze_time := 0.0
var freeze_immune := 0.0
var shield_hp := 0.0
var shield_max := 0.0
var shield_time := 0.0
## Typed aegis: "" plain absorb (Barrier boon), or the aegis element. Fire is
## an aura, arcane pays damage from mana, void swallows projectile hits, and
## frost/storm/earth absorb with their own side effects.
var shield_element := ""
var shield_swallows := 0
var shield_stats: Dictionary = {}
var _arc_cooldown := 0.0
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
	cast_time_mult = clampf(float(p_kit.get("cast_time_mult", 1.0)), 0.35, 1.5)

	collision_layer = 2
	collision_mask = 1 | WALL_LAYER
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.46
	cyl.height = 2.3
	shape.shape = cyl
	shape.position = Vector3(0, 1.15, 0)
	add_child(shape)

	_build_model()
	_build_bars()
	_build_shield()
	if float(kit.get("start_shield", 0.0)) > 0.0:
		add_shield(float(kit["start_shield"]), 60.0, wand.get("color", Color("8fe7ff")))


func _ready() -> void:
	add_to_group("wizards")
	if is_instance_valid(Audio):
		Audio.register_wizard(self)


func _exit_tree() -> void:
	if is_instance_valid(Audio):
		Audio.unregister_wizard(self)


func _build_model() -> void:
	var robe: Color = wand.get("color", Color("a78bfa"))
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	_model = model

	# Robe
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.36
	capsule.height = 1.25
	capsule.radial_segments = 12
	capsule.rings = 6
	body.mesh = capsule
	body.position = Vector3(0, 0.74, 0)
	var robe_mat := Fx.flash_material(robe.darkened(0.62), 0.85)
	body.material_override = robe_mat
	model.add_child(body)
	_flash_meshes.append(body)

	# Robe trim
	var trim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.31
	torus.outer_radius = 0.4
	torus.rings = 16
	torus.ring_segments = 6
	trim.mesh = torus
	trim.position = Vector3(0, 0.36, 0)
	trim.material_override = Fx.glow_material(robe.lightened(0.15), 1.2)
	model.add_child(trim)

	# Head
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head_mesh.radial_segments = 14
	head_mesh.rings = 8
	head.mesh = head_mesh
	head.position = Vector3(0, 1.55, 0)
	head.material_override = Fx.flash_material(Color("e8c9a0"), 0.9)
	model.add_child(head)
	_flash_meshes.append(head)

	# Beard
	var beard := MeshInstance3D.new()
	var beard_mesh := CylinderMesh.new()
	beard_mesh.top_radius = 0.16
	beard_mesh.bottom_radius = 0.02
	beard_mesh.height = 0.34
	beard_mesh.radial_segments = 8
	beard.mesh = beard_mesh
	beard.position = Vector3(0, 1.38, -0.12)
	beard.rotation_degrees = Vector3(12, 0, 0)
	beard.material_override = Fx.standard_material(Color("efe9ff"))
	model.add_child(beard)

	# Eyes
	for x in [-0.075, 0.075]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.032
		eye_mesh.height = 0.064
		eye_mesh.radial_segments = 6
		eye_mesh.rings = 4
		eye.mesh = eye_mesh
		eye.position = Vector3(x, 1.59, -0.195)
		eye.material_override = Fx.glow_material(Color("bff6ff"), 3.0)
		model.add_child(eye)

	# Hat brim
	var brim := MeshInstance3D.new()
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.46
	brim_mesh.bottom_radius = 0.46
	brim_mesh.height = 0.055
	brim_mesh.radial_segments = 18
	brim.mesh = brim_mesh
	brim.position = Vector3(0, 1.72, 0)
	brim.material_override = Fx.flash_material(robe.darkened(0.35))
	model.add_child(brim)
	_flash_meshes.append(brim)

	# Hat cone
	var hat := MeshInstance3D.new()
	var hat_mesh := CylinderMesh.new()
	hat_mesh.top_radius = 0.0
	hat_mesh.bottom_radius = 0.33
	hat_mesh.height = 0.82
	hat_mesh.radial_segments = 16
	hat.mesh = hat_mesh
	hat.position = Vector3(0, 2.1, 0)
	hat.rotation_degrees = Vector3(-6, 0, 3)
	hat.material_override = Fx.flash_material(robe.darkened(0.25))
	model.add_child(hat)
	_flash_meshes.append(hat)

	# Staff
	var staff := Node3D.new()
	staff.name = "Staff"
	staff.position = Vector3(0.46, 0.0, -0.12)
	staff.rotation_degrees = Vector3(0, 0, -9)
	model.add_child(staff)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.035
	shaft_mesh.bottom_radius = 0.045
	shaft_mesh.height = 1.65
	shaft_mesh.radial_segments = 8
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0, 0.82, 0)
	shaft.material_override = Fx.standard_material(Color("4a3427"))
	staff.add_child(shaft)

	var collar := MeshInstance3D.new()
	var collar_mesh := TorusMesh.new()
	collar_mesh.inner_radius = 0.07
	collar_mesh.outer_radius = 0.11
	collar_mesh.rings = 10
	collar_mesh.ring_segments = 5
	collar.mesh = collar_mesh
	collar.position = Vector3(0, 1.5, 0)
	collar.rotation_degrees = Vector3(90, 0, 0)
	collar.material_override = Fx.glow_material(robe, 1.6)
	staff.add_child(collar)

	var crystal := MeshInstance3D.new()
	var crystal_mesh := SphereMesh.new()
	crystal_mesh.radius = 0.11
	crystal_mesh.height = 0.22
	crystal_mesh.radial_segments = 8
	crystal_mesh.rings = 5
	crystal.mesh = crystal_mesh
	crystal.position = Vector3(0, 1.68, 0)
	crystal.material_override = Fx.glow_material(robe, 4.0)
	staff.add_child(crystal)
	_crystal = crystal

	var light := OmniLight3D.new()
	light.light_color = robe
	light.light_energy = 0.9
	light.omni_range = 2.6
	light.position = Vector3(0, 1.68, 0)
	staff.add_child(light)
	_staff_light = light

	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 1.72, 0)
	staff.add_child(_muzzle)

	# Ground ring
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.68
	ring_mesh.rings = 22
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0.04, 0)
	ring.material_override = Fx.glow_material(Color(robe.r, robe.g, robe.b, 0.7), 1.4)
	ring.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(ring)

	# Chant telegraph: floating word + expanding ring.
	_chant_ring = MeshInstance3D.new()
	var chant_ring_mesh := TorusMesh.new()
	chant_ring_mesh.inner_radius = 0.92
	chant_ring_mesh.outer_radius = 1.06
	chant_ring_mesh.rings = 32
	chant_ring_mesh.ring_segments = 6
	_chant_ring.mesh = chant_ring_mesh
	_chant_ring.material_override = Fx.glow_material(Color("ffd166"), 3.0)
	_chant_ring.position = Vector3(0, 0.05, 0)
	_chant_ring.visible = false
	_chant_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_chant_ring)

	_chant_label = Label3D.new()
	_chant_label.text = "CHANTING"
	_chant_label.font_size = 48
	_chant_label.outline_size = 14
	_chant_label.modulate = Color("ffd166")
	_chant_label.outline_modulate = Color(0.03, 0.02, 0.06, 0.95)
	_chant_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_chant_label.no_depth_test = true
	_chant_label.pixel_size = 0.005
	_chant_label.position = Vector3(0, 3.25, 0)
	_chant_label.visible = false
	add_child(_chant_label)


func _build_shield() -> void:
	_shield_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.05
	sphere.height = 2.1
	sphere.radial_segments = 16
	sphere.rings = 8
	_shield_mesh.mesh = sphere
	var mat := Fx.glow_material(Color(_shield_color.r, _shield_color.g, _shield_color.b, 0.22), 2.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mesh.material_override = mat
	_shield_mesh.position = Vector3(0, 1.0, 0)
	_shield_mesh.visible = false
	_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield_mesh)


func _build_bars() -> void:
	var root := Node3D.new()
	root.name = "Bars"
	root.position = Vector3(0, 2.75, 0)
	add_child(root)

	var backing := MeshInstance3D.new()
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(_bar_width + 0.06, 0.2)
	backing.mesh = back_mesh
	var back_mat := Fx.standard_material(Color(0.03, 0.02, 0.07, 0.8), 0.0, true)
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	back_mat.no_depth_test = true
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backing.material_override = back_mat
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(backing)

	_bar_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(_bar_width, 0.1)
	_bar_fill.mesh = fill_mesh
	var fill_mat := Fx.glow_material(Color("66f2a5") if is_player else Color("ff5d73"), 2.4)
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.no_depth_test = true
	_bar_fill.material_override = fill_mat
	_bar_fill.position = Vector3(0, 0.035, 0)
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_bar_fill)

	_mana_fill = MeshInstance3D.new()
	var mana_mesh := QuadMesh.new()
	mana_mesh.size = Vector2(_bar_width, 0.06)
	_mana_fill.mesh = mana_mesh
	var mana_mat := Fx.glow_material(Color("5bd1ff"), 2.0)
	mana_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mana_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mana_mat.no_depth_test = true
	_mana_fill.material_override = mana_mat
	_mana_fill.position = Vector3(0, -0.06, 0)
	_mana_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_mana_fill)

	_update_bars()


func _physics_process(delta: float) -> void:
	_time += delta
	_tick_timers(delta)
	if not alive:
		return

	var move := Vector3.ZERO
	if is_player and not external_input and input_enabled and not chanting and stun_time <= 0.0:
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
	elif (not is_player or external_input) and not chanting:
		move = _ai_move.limit_length(1.0)

	var speed := move_speed * move_speed_mult()
	if chanting or is_rooted_by_status():
		move = Vector3.ZERO

	velocity = move * speed + _knock + _drift
	_drift = Vector3.ZERO
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
## Continuous external pull (Singularity) consumed by the next physics step.
var _drift := Vector3.ZERO


func add_drift(v: Vector3) -> void:
	_drift += v


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
	var stats := spell.resolved_stats(wand, overcast, overcast_mult)
	if mana < float(stats["mana"]):
		return {"ok": false, "reason": "Not enough mana."}
	return {"ok": true, "spell": spell, "stats": stats}


func quickcast(slot: int) -> bool:
	if chanting or primed_slot >= 0 or not input_enabled or (is_player and Game.cast_mode == Game.CAST_CHANT):
		return false
	if slot < 0 or slot > 3:
		return false
	var check := can_cast(slot, false)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		return false
	_do_cast(slot, false, check)
	return true


func begin_chant(slot: int, p_assisted: bool = false, p_controller: bool = false) -> bool:
	if chanting or primed_slot >= 0 or not alive or not input_enabled:
		if primed_slot >= 0:
			cast_blocked.emit(self, "Release your primed spell first.")
		return false
	var mult := SpellDef.ASSIST_OVERCAST_MULT if p_assisted else SpellDef.OVERCAST_MULT
	var check := can_cast(slot, true, mult)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		return false
	chanting = true
	assisted_chant = p_assisted
	controller_chant = p_controller
	controller_word_index = 0
	chant_slot = slot
	chant_text = ""
	chant_typos = 0
	chant_elapsed = 0.0
	chant_best = 0
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
		chant_best = maxi(chant_best, chant_text.length())
	else:
		chant_typos += 1
		if chant_text.length() > 0:
			chant_text = ""
	chant_changed.emit(self, true)


func chant_word(word: String) -> void:
	if not chanting:
		return
	var spell := current_spell(chant_slot)
	if spell == null:
		cancel_chant()
		return
	var next := spell.incantation().split(" ", false)
	var offset := 0
	for part in next:
		offset += str(part).length()
		if offset > chant_text.length():
			if str(part).to_upper() == word.to_upper():
				for ch in str(part):
					chant_key(ch)
			else:
				chant_key("#")
			return
	# No words remain: an extra face-button press is a typo.
	chant_key("#")


func controller_chant_button(button_index: int) -> void:
	if not chanting or not controller_chant:
		return
	var spell := current_spell(chant_slot)
	if spell == null:
		cancel_chant()
		return
	var words := spell.incantation().split(" ", false)
	if controller_word_index >= words.size():
		return
	if button_index == controller_word_index and controller_word_index < words.size():
		chant_word(str(words[controller_word_index]))
		controller_word_index += 1
	else:
		chant_key("#")
		controller_word_index = 0


func chant_backspace() -> void:
	if not chanting:
		return
	if chant_text.is_empty():
		cancel_chant()
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
	var full := spell.incantation_compact()
	if chant_text == full:
		if chant_elapsed < typed_charge_time():
			return
		_prime_chant()
		return
	# A failed incantation still fires if the caster reached at least half of
	# it. The fizzle is deliberately worse than a quickcast (×0.5 power) and
	# still pays full mana, so it is a consolation, not a combo.
	var ratio := chant_accuracy()
	if ratio < PARTIAL_CAST_RATIO:
		cast_blocked.emit(self, "Keep chanting")
		return
	if chant_elapsed < typed_charge_time():
		cast_blocked.emit(self, "The runes are still forming…")
		return
	var partial := can_cast(chant_slot, false)
	if not bool(partial["ok"]):
		cast_blocked.emit(self, str(partial["reason"]))
		cancel_chant()
		return
	var stats: Dictionary = partial["stats"]
	SpellDef.apply_fizzle(stats)
	stats["partial_ratio"] = ratio
	_do_cast(chant_slot, false, partial)


func _prime_chant() -> void:
	var check := can_cast(chant_slot, true, SpellDef.OVERCAST_MULT)
	if not bool(check["ok"]):
		cast_blocked.emit(self, str(check["reason"]))
		cancel_chant()
		return
	_primed_check = check
	primed_slot = chant_slot
	primed_page = page
	primed_spell = check["spell"]
	primed_remaining = PRIMED_LIMIT
	_set_primed_tint(check["spell"], true)
	mana = maxf(0.0, mana - float(check["stats"]["mana"]))
	mana_changed.emit(self, mana, max_mana)
	chanting = false
	assisted_chant = false
	controller_chant = false
	chant_slot = -1
	chant_text = ""
	chant_elapsed = 0.0
	chant_best = 0
	_set_chant_fx(true)
	chant_changed.emit(self, false)


func release_primed() -> bool:
	if primed_slot < 0 or not alive or _primed_check.is_empty():
		return false
	var slot := primed_slot
	var spell := primed_spell
	var check := _primed_check
	# Soft-lock reads the primed spell, so aim before clearing the primed state.
	var dir := get_aim_direction()
	_clear_primed()
	_set_chant_fx(false)
	_set_primed_tint(spell, false)
	# Mana was paid when the spell primed.
	check["stats"]["mana"] = 0.0
	_do_cast(slot, true, check, false, dir)
	return true


## The spell that is loaded right now, independent of the current page.
## Clients do not hold ``_primed_check``; they resolve the replicated page/slot.
func get_primed_spell() -> SpellDef:
	if primed_slot < 0:
		return null
	if primed_spell != null:
		return primed_spell
	if primed_page < 0 or primed_page >= pages.size():
		return null
	var row: Array = pages[primed_page]
	return row[primed_slot] if primed_slot < row.size() else null


func _clear_primed() -> void:
	primed_slot = -1
	primed_page = -1
	primed_remaining = 0.0
	primed_spell = null
	_primed_check = {}


func discard_primed() -> void:
	if primed_slot < 0:
		return
	var spell := get_primed_spell()
	_clear_primed()
	_set_chant_fx(false)
	_set_primed_tint(spell, false)
	Fx.burst(get_parent(), global_position + Vector3.UP * 1.3, wand.get("color", Color.WHITE), 10, 2.4, 0.05, 0.25)
	chant_changed.emit(self, false)


## Best correct-prefix length / full incantation length, kept across typos.
func chant_accuracy() -> float:
	var spell := current_spell(chant_slot)
	if spell == null:
		return 0.0
	var full := spell.incantation_compact()
	return clampf(float(maxi(chant_text.length(), chant_best)) / float(maxi(1, full.length())), 0.0, 1.0)


func chant_progress() -> float:
	var span := chant_time_target()
	return clampf(chant_elapsed / span, 0.0, 1.0)


## How long this chant needs to hold before it can be unleashed.
func chant_time_target() -> float:
	return assist_charge_time() if assisted_chant else typed_charge_time()


func typed_charge_time() -> float:
	if Game.cast_mode == Game.CAST_CHANT:
		var spell := current_spell(chant_slot)
		return (float(spell.incantation_compact().length()) / CHANT_ONLY_CHAR_RATE) * cast_time_mult if spell != null else 1.0
	return CHANT_MIN_TIME * cast_time_mult


func assist_charge_time() -> float:
	return CHANT_ASSIST_TIME * cast_time_mult


## The assisted hold's perfect-release window, as a (start, end) pair.
func perfect_window() -> Vector2:
	var start := CHANT_MIN_TIME * cast_time_mult
	if Game.cast_mode == Game.CAST_CHANT and not assisted_chant:
		start = typed_charge_time()
	return Vector2(start, CHANT_PERFECT_END * cast_time_mult)


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
	if chant_elapsed < CHANT_MIN_TIME * cast_time_mult:
		cancel_chant()
		return false
	var perfect := chant_elapsed <= perfect_window().y
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
	controller_chant = false
	chant_slot = -1
	chant_text = ""
	chant_elapsed = 0.0
	chant_best = 0
	_set_chant_fx(false)
	chant_changed.emit(self, false)


func _do_cast(slot: int, overcast: bool, check: Dictionary, perfect: bool = false, aim_dir: Vector3 = Vector3.ZERO) -> void:
	var spell: SpellDef = check["spell"]
	var stats: Dictionary = check["stats"]
	if perfect and overcast:
		SpellDef.apply_perfect(stats)
	stats["perfect"] = perfect
	mana = maxf(0.0, mana - float(stats["mana"]))
	selected_slot = slot
	last_cast_slot = slot

	var origin := get_muzzle_position()
	var dir := aim_dir if aim_dir != Vector3.ZERO else get_aim_direction()
	Fx.burst(get_parent(), origin, stats["color"], 10, 4.0, 0.05, 0.25)
	if _staff_light != null:
		_staff_light.light_energy = 4.0
	chanting = false
	assisted_chant = false
	controller_chant = false
	chant_slot = -1
	chant_text = ""
	chant_elapsed = 0.0
	chant_best = 0
	_set_chant_fx(false)
	chant_changed.emit(self, false)
	mana_changed.emit(self, mana, max_mana)
	cast_fired.emit(self, spell, stats, origin, dir)


func _tick_timers(delta: float) -> void:
	_time += 0.0
	if alive and mana < max_mana:
		var regen := mana_regen * (0.5 if chanting else (0.0 if primed_slot >= 0 or has_shield("arcane") else 1.0))
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
	if chill_time > 0.0:
		chill_time = maxf(0.0, chill_time - delta)
	if freeze_time > 0.0:
		freeze_time = maxf(0.0, freeze_time - delta)
	if freeze_immune > 0.0:
		freeze_immune = maxf(0.0, freeze_immune - delta)
	if _arc_cooldown > 0.0:
		_arc_cooldown = maxf(0.0, _arc_cooldown - delta)
	if shield_time > 0.0:
		shield_time -= delta
		if shield_time <= 0.0:
			_clear_shield()
	if chanting:
		chant_elapsed += delta
		if assisted_chant and chant_text.is_empty() and chant_elapsed >= assist_charge_time():
			_finish_assisted()
		elif current_spell(chant_slot) != null and chant_text == current_spell(chant_slot).incantation_compact() and chant_elapsed >= typed_charge_time():
			_prime_chant()
	if primed_slot >= 0:
		primed_remaining -= delta
		if primed_remaining <= 0.0:
			discard_primed()


# ---- Damage --------------------------------------------------------------

func add_shield(amount: float, duration: float, color: Color = Color("8fe7ff"), element: String = "", stats: Dictionary = {}) -> void:
	if not alive:
		return
	_shield_color = color
	if element != shield_element or shield_time <= 0.0:
		# A different aegis replaces the current one outright.
		shield_hp = 0.0
		shield_max = 0.0
		shield_time = 0.0
	shield_element = element
	shield_stats = stats
	shield_swallows = maxi(shield_swallows if element == "void" else 0, int(stats.get("swallows", 0)))
	shield_max = maxf(shield_max, amount)
	shield_hp = maxf(shield_hp, amount)
	shield_time = maxf(shield_time, duration)
	if element == "earth":
		_knock = Vector3.ZERO
	if element in ["frost", "fire"]:
		slow_time = 0.0
		slow_amount = 0.0
		chill_time = 0.0
		freeze_time = 0.0
	_show_shield(color)
	shield_changed.emit(self, shield_hp, shield_max)


func _show_shield(color: Color) -> void:
	if _shield_mesh != null:
		_shield_mesh.visible = true
		var mat := _shield_mesh.material_override as StandardMaterial3D
		if mat != null:
			var alpha := 0.34 if shield_element in ["earth", "frost"] else 0.22
			mat.albedo_color = Color(color.r, color.g, color.b, alpha)
			mat.emission = color


func _clear_shield() -> void:
	shield_hp = 0.0
	shield_max = 0.0
	shield_time = 0.0
	shield_element = ""
	shield_swallows = 0
	shield_stats = {}
	if _shield_mesh != null:
		_shield_mesh.visible = false
	shield_changed.emit(self, 0.0, 0.0)


## True while an aegis of this element is up ("" = any plain absorb).
func has_shield(element: String) -> bool:
	return shield_time > 0.0 and shield_element == element


func is_chill_immune() -> bool:
	return has_shield("frost") or has_shield("fire")


## Stoneskin: immune to knockback, pull, stagger and jolt.
func is_cc_immune() -> bool:
	return has_shield("earth")


func is_rooted_by_status() -> bool:
	return stun_time > 0.0 or freeze_time > 0.0


func move_speed_mult() -> float:
	var mult := 1.0
	if slow_time > 0.0 and not has_shield("frost"):
		mult *= 1.0 - slow_amount
	if shield_time > 0.0:
		mult *= float(SpellData.cell(shield_element, "aegis").get("move_mult", 1.0))
	return mult


## HUD text for the active aegis.
func shield_label() -> String:
	if shield_time <= 0.0:
		return ""
	match shield_element:
		"fire": return "HEAT AURA  %.1fs" % shield_time
		"arcane": return "MANA SHIELD  %.1fs" % shield_time
		"void": return "SHROUD  ×%d" % shield_swallows
		"frost": return "ICE ARMOR  %d" % ceili(shield_hp)
		"storm": return "STATIC SHELL  %d" % ceili(shield_hp)
		"earth": return "STONESKIN  %d" % ceili(shield_hp)
	return "SHIELD  %d" % ceili(shield_hp) if shield_hp > 0.0 else ""


func _arena() -> Node:
	var parent := get_parent()
	if parent != null and parent.has_method("on_shield_broken"):
		return parent
	return null


## Apply one hit. ``hit`` carries cell riders and context:
## attacker (Wizard), projectile (bool), direct (bool, default true),
## quiet (no damage number), burn (total), ignite (bool), chill / chill_time,
## can_freeze (bool, default true), jolt, stagger, mana_burn,
## pull_to (Vector3) + pull (metres). Returns the health actually lost.
func take_damage(amount: float, element: String, source_pos: Vector3, knockback: float = 0.0, apply_status: bool = true, hit: Dictionary = {}) -> float:
	if not alive:
		return 0.0
	var attacker: Variant = hit.get("attacker", null)
	var direct := bool(hit.get("direct", true))
	var incoming := amount

	if direct and has_shield("storm") and _arc_cooldown <= 0.0 and attacker is Wizard and attacker != self:
		_arc_cooldown = float(SpellData.cell(shield_element, "aegis").get("arc_cooldown", 0.5))
		var a := _arena()
		if a != null:
			a.static_arc(self, attacker)

	if bool(hit.get("projectile", false)) and has_shield("void") and shield_swallows > 0:
		shield_swallows -= 1
		heal(incoming * float(SpellData.cell(shield_element, "aegis").get("heal", 0.25)))
		Fx.burst(get_parent(), global_position + Vector3.UP * 1.0, _shield_color, 16, 2.0, 0.07, 0.4)
		if shield_swallows <= 0:
			_clear_shield()
		else:
			shield_changed.emit(self, shield_hp, shield_max)
		return 0.0

	if has_shield("arcane") and mana > 0.0:
		var paid := minf(mana, incoming)
		mana -= paid
		incoming -= paid
		mana_changed.emit(self, mana, max_mana)
		Fx.burst(get_parent(), global_position + Vector3.UP * 1.0, _shield_color, 10, 3.0, 0.06, 0.3)

	if shield_hp > 0.0 and incoming > 0.0:
		# Fire melts ice armor twice as fast.
		var factor := 2.0 if shield_element == "frost" and element == "fire" else 1.0
		var cost := incoming * factor
		var absorbed := minf(shield_hp, cost)
		shield_hp -= absorbed
		incoming -= absorbed / factor
		Fx.burst(get_parent(), global_position + Vector3.UP * 1.0, _shield_color, 12, 3.5, 0.06, 0.35)
		if shield_hp <= 0.001:
			var broken := shield_element
			var broken_stats := shield_stats
			_clear_shield()
			var a := _arena()
			if a != null:
				a.on_shield_broken(self, broken, broken_stats)
		else:
			shield_changed.emit(self, shield_hp, shield_max)
	if incoming <= 0.001:
		# The shield held: no damage, no status, no chant interrupt.
		return 0.0
	amount = incoming

	if chanting and amount >= 5.0 and chant_elapsed >= 0.15:
		cancel_chant()
		chant_interrupted.emit(self)
	_apply_direct_damage(amount, _element_color(element), not bool(hit.get("quiet", false)))
	if not alive:
		return amount

	if apply_status:
		var burn := float(hit.get("burn", BURN_TOTAL if element == "fire" else 0.0))
		if bool(hit.get("ignite", false)):
			burn = maxf(burn, BURN_TOTAL)
		if burn > 0.0:
			burn_time = maxf(burn_time, 3.0)
			burn_total = maxf(burn_total, burn)
		if element == "frost" or hit.has("chill"):
			apply_chill(float(hit.get("chill", CHILL_SLOW)), float(hit.get("chill_time", CHILL_TIME)), bool(hit.get("can_freeze", true)))
		var jolt := float(hit.get("jolt", JOLT_TIME if element == "storm" else 0.0))
		if jolt > 0.0:
			apply_jolt(jolt)
		var stagger := float(hit.get("stagger", STAGGER_TIME if element == "earth" else 0.0))
		if stagger > 0.0 and not is_cc_immune():
			stun_time = maxf(stun_time, stagger)
			if chanting:
				cancel_chant()
				chant_interrupted.emit(self)
		var burn_mana := float(hit.get("mana_burn", MANA_BURN if element == "arcane" else 0.0))
		if burn_mana > 0.0:
			mana = maxf(0.0, mana - burn_mana)
			mana_changed.emit(self, mana, max_mana)

	if not is_cc_immune():
		if knockback > 0.0:
			var dir := (global_position - source_pos)
			dir.y = 0.0
			if dir.length() < 0.01:
				dir = Vector3.FORWARD
			_knock += dir.normalized() * knockback
		if hit.has("pull_to") and float(hit.get("pull", 0.0)) > 0.0:
			pull_toward(hit["pull_to"], float(hit["pull"]))
	return amount


## Chill slows; a second chill while chilled freezes (rooted, 3 s immunity
## after). Zones refresh the slow without counting as a fresh chill.
func apply_chill(amount: float, time: float, can_freeze: bool = true) -> void:
	if not alive or is_chill_immune():
		return
	if can_freeze and chill_time > 0.0 and freeze_time <= 0.0 and freeze_immune <= 0.0:
		freeze_time = FREEZE_TIME
		freeze_immune = FREEZE_TIME + FREEZE_IMMUNITY
		Fx.burst(get_parent(), global_position + Vector3.UP * 0.8, Color("bff6ff"), 18, 2.5, 0.08, 0.5)
	chill_time = maxf(chill_time, time)
	apply_slow(amount, time)


func apply_slow(amount: float, time: float) -> void:
	if not alive or has_shield("frost"):
		return
	slow_time = maxf(slow_time, time)
	slow_amount = maxf(slow_amount, amount)


## Jolt: a short stun that breaks chants. Freeze never does.
func apply_jolt(time: float) -> void:
	if not alive or is_cc_immune():
		return
	stun_time = maxf(stun_time, time)
	if chanting:
		cancel_chant()
		chant_interrupted.emit(self)


## Negative knockback: an impulse that travels ``metres`` toward ``point``
## under the usual knockback decay (22 m/s^2), never overshooting it.
func pull_toward(point: Vector3, metres: float) -> void:
	if not alive or is_cc_immune():
		return
	var to := point - global_position
	to.y = 0.0
	var dist := to.length()
	var travel := minf(metres, maxf(0.0, dist - 0.9))
	if travel <= 0.01:
		return
	_knock += to.normalized() * sqrt(2.0 * 22.0 * travel)


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
	discard_primed()
	_clear_shield()
	freeze_time = 0.0
	stun_time = 0.0
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
			# Only the multiplier changes: the emission shader variant is always
			# compiled in, so a hit never triggers a program rebuild.
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
	var direction := d.normalized()
	if primed_slot >= 0:
		var spell := get_primed_spell()
		if spell != null and spell.form in ["bolt", "orb", "beam"]:
			for rival in get_tree().get_nodes_in_group("wizards"):
				if rival == self or not rival is Wizard or not rival.alive:
					continue
				var to_rival: Vector3 = rival.global_position - origin
				to_rival.y = 0.0
				if to_rival.length() <= float(_primed_check.get("stats", {}).get("range", 15.0)) and direction.angle_to(to_rival.normalized()) <= deg_to_rad(10.0):
					return to_rival.normalized()
	return direction


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


func _set_primed_tint(spell: SpellDef, active: bool) -> void:
	var color: Color = wand.get("color", Color("ffd166"))
	if active and spell != null:
		color = SpellData.ELEMENTS.get(spell.element, {}).get("color", color)
	if _chant_ring != null:
		_chant_ring.material_override = Fx.glow_material(color if active else Color("ffd166"), 3.0)
	if _staff_light != null:
		_staff_light.light_color = color
		if not active:
			_staff_light.light_energy = 0.9


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
