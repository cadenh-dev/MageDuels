class_name SpellWall
extends StaticBody3D

## A placed ward segment. The element is the material:
## - Stone Wall: solid to wizards, projectiles and beams; 60 HP.
## - Ice Wall: solid to wizards only; projectiles pass slowed; 30 HP; shatters.
## - Flame Sheet, Tesla Fence, Mirror Ward, Rift: never collide. Crossings are
##   found by distance to the segment, so they sit on no physics layer at all.
## The arena applies the cross-material order (see Arena.projectile_walls).

signal hp_changed(wall: SpellWall, hp: float)

const HALF_LEN := 1.2
const HALF_THICK := 0.225
const HEIGHT := 2.6
const TICK := 0.25

static var _materials: Dictionary = {}
static var _trim_materials: Dictionary = {}

var arena: Node
var owner_wizard: Wizard
var element := "earth"
var stats: Dictionary = {}
var duration: float = 7.0
var color: Color = Color.WHITE
var max_hp := 0.0
var hp := 0.0
var reflections_left := 0
var solid_wizards := true
var solid_projectiles := true
var authority := true
var broken := false

var _max_duration: float = 7.0
var _mat: StandardMaterial3D
var _fading := false
var _tick := 0.0
var _age := 0.0
var _sides: Dictionary = {}
var _cross_cd: Dictionary = {}
var _zap_timer := 0.0
var _arcs: Array[MeshInstance3D] = []
var _swirl: MeshInstance3D


## Legacy plain barrier (solid, no HP). Kept for callers that only know a color.
func setup(p_color: Color, p_duration: float = 7.0, _p_size: Vector3 = Vector3(2.4, 2.6, 0.45)) -> void:
	setup_ward({"element": "", "color": p_color, "duration": p_duration})


func setup_ward(p: Dictionary) -> void:
	arena = p.get("arena")
	owner_wizard = p.get("owner")
	element = str(p.get("element", ""))
	stats = p.get("stats", {})
	authority = bool(p.get("authority", true))
	var c := SpellData.cell(element, "wall")
	color = p.get("color", SpellData.ELEMENTS.get(element, {}).get("color", Color.WHITE))
	duration = float(p.get("duration", stats.get("duration", c.get("duration", 7.0))))
	_max_duration = duration
	if element == "":
		solid_wizards = true
		solid_projectiles = true
	else:
		solid_wizards = bool(c.get("solid_wizards", false))
		solid_projectiles = bool(c.get("solid_projectiles", false))
	max_hp = float(p.get("max_hp", stats.get("wall_hp", c.get("hp", 0.0))))
	hp = float(p.get("hp", max_hp))
	reflections_left = int(stats.get("reflections", c.get("reflections", 0)))

	collision_mask = 0
	collision_layer = Wizard.WALL_LAYER if solid_wizards else 0
	if solid_wizards:
		var box := BoxShape3D.new()
		box.size = Vector3(HALF_LEN * 2.0, HEIGHT, HALF_THICK * 2.0)
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = Vector3(0, HEIGHT * 0.5, 0)
		add_child(shape)
	_build_visual()


func is_solid() -> bool:
	return solid_wizards


func has_hp() -> bool:
	return max_hp > 0.0


## Unit vector along the segment.
func axis() -> Vector3:
	var x := global_transform.basis.x
	x.y = 0.0
	return x.normalized()


## Unit vector the ward faces (the caster's aim when placed).
func normal() -> Vector3:
	var z := global_transform.basis.z
	z.y = 0.0
	return z.normalized()


func endpoints() -> Array[Vector3]:
	var c := Vector3(global_position.x, 0.0, global_position.z)
	return [c - axis() * HALF_LEN, c + axis() * HALF_LEN]


func distance_to_point(pos: Vector3) -> float:
	var e := endpoints()
	var p := Vector2(pos.x, pos.z)
	return Geometry2D.get_closest_point_to_segment(p, Vector2(e[0].x, e[0].z), Vector2(e[1].x, e[1].z)).distance_to(p)


## Signed distance from the ward's centre line.
func side_of(pos: Vector3) -> float:
	var d := pos - global_position
	d.y = 0.0
	return d.dot(normal())


## Parametric t in [0, 1] where the segment from->to crosses this ward (with
## ``pad`` extra half-length for a fat projectile), or -1.
func crossing_t(from: Vector3, to: Vector3, pad: float = 0.0) -> float:
	if broken:
		return -1.0
	var d0 := side_of(from)
	var d1 := side_of(to)
	if (d0 > 0.0 and d1 > 0.0) or (d0 < 0.0 and d1 < 0.0):
		return -1.0
	if is_equal_approx(d0, d1):
		return -1.0 if absf(d0) > 0.001 else 0.0
	var t := d0 / (d0 - d1)
	var point := from.lerp(to, t)
	var lateral := (point - global_position)
	lateral.y = 0.0
	if absf(lateral.dot(axis())) > HALF_LEN + pad:
		return -1.0
	return clampf(t, 0.0, 1.0)


## Projectiles and beams damage HP walls: fire x2 vs ice, earth x1.5.
func damage_wall(amount: float, by_element: String, flat: bool = false) -> void:
	if broken or not has_hp() or amount <= 0.0:
		return
	var dmg := amount
	if element == "frost" and by_element in ["fire", "earth"]:
		dmg *= 2.0 if (by_element == "fire" or flat) else 1.5
	elif by_element == "earth" and not flat:
		dmg *= 1.5
	hp = maxf(0.0, hp - dmg)
	if _mat != null and max_hp > 0.0:
		var t := clampf(hp / max_hp, 0.0, 1.0)
		var base := _wall_material(element).albedo_color
		_mat.albedo_color = Color(base.r * (0.55 + 0.45 * t), base.g * (0.55 + 0.45 * t), base.b * (0.55 + 0.45 * t), base.a)
	if arena != null and is_instance_valid(arena):
		Fx.burst(arena.effects, global_position + Vector3.UP * 1.2, color, 8, 3.0, 0.07, 0.3)
	hp_changed.emit(self, hp)
	if hp <= 0.0:
		shatter()


## Broken by damage or smashed by a Boulder. Ice shatters into shards.
func shatter() -> void:
	if broken:
		return
	broken = true
	hp = 0.0
	hp_changed.emit(self, hp)
	if authority and arena != null and is_instance_valid(arena):
		arena.on_wall_broken(self)
	_vanish(22)


func use_reflection() -> void:
	reflections_left -= 1
	if reflections_left <= 0:
		broken = true
		_vanish(18)


func _vanish(amount: int) -> void:
	var parent := get_parent()
	if parent != null:
		Fx.burst(parent, global_position + Vector3.UP * 1.0, color, amount, 5.0, 0.09, 0.45)
	collision_layer = 0
	set_physics_process(false)
	set_process(false)
	queue_free()


func _physics_process(delta: float) -> void:
	if broken:
		return
	duration -= delta
	if duration <= 0.0:
		broken = true
		_vanish(14)
		return
	if not authority or arena == null or not is_instance_valid(arena):
		return
	if element == "storm":
		_tesla(delta)
	_tick += delta
	while _tick >= TICK:
		_tick -= TICK
		_area_tick()


func _enemies() -> Array[Wizard]:
	var out: Array[Wizard] = []
	for w: Wizard in arena.wizards:
		if is_instance_valid(w) and w.alive and w != owner_wizard:
			out.append(w)
	return out


func _area_tick() -> void:
	var c := SpellData.cell(element, "wall")
	var zone_mult := float(stats.get("zone_mult", 1.0))
	for w in _enemies():
		var d := distance_to_point(w.global_position)
		match element:
			"fire":
				if d <= float(c.get("zone_depth", 0.75)):
					w.take_damage(float(c.get("zone_dps", 10.0)) * zone_mult * TICK, "fire", global_position, 0.0, true, {
						"attacker": owner_wizard, "direct": false, "quiet": true, "burn": float(c.get("burn", 12.0))})
			"void":
				if d <= float(c.get("zone_depth", 0.75)):
					w.apply_slow(float(c.get("slow", 0.25)), TICK + 0.1)
			"frost":
				if d <= float(c.get("chill_radius", 0.4)) + 0.5:
					w.apply_chill(Wizard.CHILL_SLOW, Wizard.CHILL_TIME, false)


## Tesla Fence: crossing it jolts (at most once a second per wizard); every
## second it also zaps the nearest enemy within 3 m.
func _tesla(delta: float) -> void:
	var c := SpellData.cell("storm", "wall")
	var zone_mult := float(stats.get("zone_mult", 1.0))
	for w in _enemies():
		var id := w.get_instance_id()
		var side := side_of(w.global_position)
		var cd := float(_cross_cd.get(id, 0.0)) - delta
		_cross_cd[id] = cd
		var lateral := absf((w.global_position - global_position).dot(axis()))
		if _sides.has(id) and signf(side) != signf(float(_sides[id])) and lateral <= HALF_LEN + 0.4 and cd <= 0.0:
			_cross_cd[id] = float(c.get("cross_cooldown", 1.0))
			w.take_damage(float(c.get("cross_damage", 8.0)) * zone_mult, "storm", global_position, 0.0, true, {
				"attacker": owner_wizard, "direct": false, "jolt": Wizard.JOLT_TIME})
			Fx.beam(arena.effects, global_position + Vector3.UP * 1.3, w.global_position + Vector3.UP * 1.0, color, 0.05, 0.16)
		_sides[id] = side
	_zap_timer += delta
	if _zap_timer >= float(c.get("zap_interval", 1.0)):
		_zap_timer = 0.0
		var best: Wizard = null
		var best_d := float(c.get("zap_range", 3.0))
		for w in _enemies():
			var d := distance_to_point(w.global_position)
			if d <= best_d:
				best_d = d
				best = w
		if best != null:
			best.take_damage(float(c.get("zap_dps", 4.0)) * float(c.get("zap_interval", 1.0)) * zone_mult, "storm", global_position, 0.0, true, {
				"attacker": owner_wizard, "direct": false, "jolt": 0.0})
			Fx.beam(arena.effects, global_position + Vector3.UP * 2.0, best.global_position + Vector3.UP * 1.0, color, 0.04, 0.14)


func _process(delta: float) -> void:
	_age += delta
	if duration < 1.4 and not _fading and _mat != null and _mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		_fading = true
		var tween := create_tween()
		tween.tween_property(_mat, "albedo_color:a", 0.0, 1.4)
	if _mat == null:
		return
	match element:
		"fire":
			_mat.emission_energy_multiplier = 2.2 + sin(_age * 23.0) * 0.6 + sin(_age * 9.0) * 0.4
		"arcane":
			_mat.emission_energy_multiplier = 1.6 + sin(_age * 6.0) * 0.5
		"storm":
			for i in _arcs.size():
				var arc := _arcs[i]
				arc.position.y = 0.5 + float(i) * 0.7 + randf_range(-0.18, 0.18)
				arc.visible = randf() > 0.2
		"void":
			if _swirl != null:
				_swirl.rotation.z += delta * 3.5


# ---- Visuals ---------------------------------------------------------------

func _build_visual() -> void:
	var size := Vector3(HALF_LEN * 2.0, HEIGHT, HALF_THICK * 2.0)
	match element:
		"storm":
			_build_tesla()
			return
		"fire":
			size.z = 0.12
		"arcane", "void":
			size.z = 0.1
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, size.y * 0.5, 0)
	_mat = _wall_material(element).duplicate()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	if element in ["", "frost", "earth", "arcane"]:
		for x in [-1.0, 1.0]:
			var trim := MeshInstance3D.new()
			var trim_mesh := BoxMesh.new()
			trim_mesh.size = Vector3(0.12, size.y, size.z + 0.08)
			trim.mesh = trim_mesh
			trim.material_override = _trim_material(element, color)
			trim.position = Vector3(x * size.x * 0.5, size.y * 0.5, 0)
			trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(trim)
	if element == "fire":
		var flames := CPUParticles3D.new()
		flames.amount = 40
		flames.lifetime = 0.6
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		flames.emission_box_extents = Vector3(HALF_LEN, 0.1, 0.1)
		flames.direction = Vector3.UP
		flames.spread = 12.0
		flames.gravity = Vector3(0, 3.0, 0)
		flames.initial_velocity_min = 1.2
		flames.initial_velocity_max = 2.6
		flames.scale_amount_min = 0.7
		flames.scale_amount_max = 1.6
		var pm := SphereMesh.new()
		pm.radius = 0.1
		pm.height = 0.2
		pm.radial_segments = 6
		pm.rings = 3
		flames.mesh = pm
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.8, 0.35, 0.9))
		ramp.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
		flames.color_ramp = ramp
		flames.material_override = SpellZone.flame_particle_material()
		flames.position = Vector3(0, 0.1, 0)
		add_child(flames)
	if element == "void":
		_swirl = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.85
		torus.rings = 24
		torus.ring_segments = 6
		_swirl.mesh = torus
		_swirl.rotation = Vector3(PI * 0.5, 0, 0)
		_swirl.position = Vector3(0, 1.3, 0)
		_swirl.material_override = _trim_material("void", color)
		_swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_swirl)


func _build_tesla() -> void:
	var post_mat := Fx.standard_material(Color("3a3346"))
	for x in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.11
		cyl.height = HEIGHT
		cyl.radial_segments = 8
		post.mesh = cyl
		post.material_override = post_mat
		post.position = Vector3(x * HALF_LEN, HEIGHT * 0.5, 0)
		add_child(post)
		var tip := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.14
		sphere.height = 0.28
		sphere.radial_segments = 8
		sphere.rings = 4
		tip.mesh = sphere
		tip.material_override = _trim_material("storm", color)
		tip.position = Vector3(x * HALF_LEN, HEIGHT, 0)
		add_child(tip)
	for i in 3:
		var arc := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(HALF_LEN * 2.0, 0.035, 0.035)
		arc.mesh = box
		arc.material_override = _trim_material("storm", color)
		arc.position = Vector3(0, 0.5 + float(i) * 0.7, 0)
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arc)
		_arcs.append(arc)


## One shared trim/glow material per element.
static func _trim_material(p_element: String, c: Color) -> StandardMaterial3D:
	var key := p_element + c.to_html()
	if not _trim_materials.has(key):
		var glow := c
		if p_element == "earth":
			glow = Color("e0b07a")
		elif p_element == "frost":
			glow = Color("e8fbff")
		_trim_materials[key] = Fx.glow_material(glow, 4.0 if p_element != "earth" else 1.2)
	return _trim_materials[key]


## Keep one template per material so its shader program survives between
## walls; each wall duplicates it so it can fade and crack independently.
static func _wall_material(p_element: String) -> StandardMaterial3D:
	if not _materials.has(p_element):
		var mat: StandardMaterial3D
		var c: Color = SpellData.ELEMENTS.get(p_element, {}).get("color", Color("cfd6ff"))
		match p_element:
			"earth":
				# Opaque stone: reads as physical, blocks sight.
				mat = Fx.standard_material(Color("7a5a3a"))
				mat.roughness = 1.0
			"frost":
				mat = Fx.glow_material(Color(0.8, 0.95, 1.0, 0.78), 0.9)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.metallic = 0.3
				mat.roughness = 0.15
			"fire":
				mat = Fx.glow_material(Color(1.0, 0.45, 0.12, 0.32), 2.4)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			"arcane":
				mat = Fx.glow_material(Color(c.r, c.g, c.b, 0.42), 1.6)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.metallic = 0.8
				mat.roughness = 0.05
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			"void":
				mat = Fx.glow_material(Color(0.22, 0.02, 0.16, 0.82), 1.2)
				mat.emission = Color("ff4d9d")
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_:
				mat = Fx.glow_material(Color(c.r, c.g, c.b, 0.36), 1.6)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[p_element] = mat
	return _materials[p_element]
