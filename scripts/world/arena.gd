class_name Arena
extends Node3D

## The 2.5D duelling stage. Owns the camera, lighting, and spell resolution.

var wizards: Array[Wizard] = []
var projectiles: Node3D
var effects: Node3D
var walls: Node3D
var camera: Camera3D
var arena_element := "fire"
var follow_camera := false
var follow_target: Wizard

signal impact_fx(at: Vector3, color: Color, strength: float)
signal near_miss(wizard: Wizard, at: Vector3)

var _cam_base := Vector3(0, 9.6, 13.2)
var _shake_time := 0.0
var _shake_amount := 0.0
var _time := 0.0
var _rocks: Array[Node3D] = []
var _braziers: Array[MeshInstance3D] = []
var _element_light: OmniLight3D
var _rim_mat: StandardMaterial3D
var _env: Environment
var _reticle: MeshInstance3D
var _hitstop_until := 0
var _flash_rect: ColorRect
var _flash_until := 0
var _flash_start := 0
var _flash_duration := 60
var _flash_alpha := 0.0


func build(p_element: String) -> void:
	arena_element = p_element
	projectiles = _container("Projectiles")
	effects = _container("Effects")
	walls = _container("Walls")

	_build_environment()
	_build_stage()
	_build_decor()
	_build_camera()
	_build_stars()
	_build_flash()


func _container(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	return n


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("0d0820")
	sky_mat.sky_horizon_color = Color("2b1547")
	sky_mat.sky_curve = 0.22
	sky_mat.ground_bottom_color = Color("05030b")
	sky_mat.ground_horizon_color = Color("1a0d2e")
	sky_mat.ground_curve = 0.1
	sky_mat.sun_angle_max = 18.0

	var sky := Sky.new()
	sky.sky_material = sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.7
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	_env.fog_enabled = true
	_env.fog_light_color = Color("1a1030")
	_env.fog_density = 0.014
	_env.fog_sky_affect = 0.4
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.12

	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_color = Color("cfd6ff")
	key.light_energy = 0.55
	key.rotation_degrees = Vector3(-52, -28, 0)
	key.shadow_enabled = false
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color("ffb38a")
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-18, 150, 0)
	add_child(fill)

	_element_light = OmniLight3D.new()
	_element_light.light_color = _element_color()
	_element_light.light_energy = 1.8
	_element_light.omni_range = 18.0
	_element_light.position = Vector3(0, 5.0, 0)
	_element_light.shadow_enabled = false
	add_child(_element_light)


func _build_stage() -> void:
	var stone := Fx.standard_material(Color("171126"))
	stone.roughness = 0.92
	stone.metallic = 0.15

	var disc := CylinderMesh.new()
	disc.top_radius = 9.0
	disc.bottom_radius = 8.2
	disc.height = 0.9
	disc.radial_segments = 48
	disc.rings = 2

	var stage := MeshInstance3D.new()
	stage.mesh = disc
	stage.position = Vector3(0, -0.45, 0)
	stage.material_override = stone
	add_child(stage)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 9.0
	cyl.height = 1.2
	shape.shape = cyl
	shape.position = Vector3(0, -0.3, 0)
	body.add_child(shape)
	add_child(body)

	# Glowing rim
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 8.72
	rim_mesh.outer_radius = 9.02
	rim_mesh.rings = 64
	rim_mesh.ring_segments = 6
	rim.mesh = rim_mesh
	_rim_mat = Fx.glow_material(_element_color(), 1.9)
	rim.material_override = _rim_mat
	rim.position = Vector3(0, 0.02, 0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)

	# Inner inscribed circle
	var inner := MeshInstance3D.new()
	var inner_mesh := TorusMesh.new()
	inner_mesh.inner_radius = 3.05
	inner_mesh.outer_radius = 3.11
	inner_mesh.rings = 48
	inner_mesh.ring_segments = 4
	inner.mesh = inner_mesh
	var inner_mat := Fx.glow_material(Color(_element_color().r, _element_color().g, _element_color().b, 0.35), 1.2)
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner.material_override = inner_mat
	inner.position = Vector3(0, 0.015, 0)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inner)

	# Rune ticks around the rim
	var rune_mat := Fx.glow_material(_element_color(), 2.0)
	for i in 24:
		var tick := MeshInstance3D.new()
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.08, 0.03, 0.42 if i % 3 == 0 else 0.24)
		tick.mesh = tick_mesh
		tick.material_override = rune_mat
		var angle := TAU * float(i) / 24.0
		tick.position = Vector3(cos(angle) * 8.35, 0.02, sin(angle) * 8.35)
		tick.rotation.y = -angle
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tick)


func _build_decor() -> void:
	for i in 6:
		var angle := TAU * float(i) / 6.0
		var radius := 10.6
		var pillar := Node3D.new()
		pillar.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		add_child(pillar)

		var shaft := MeshInstance3D.new()
		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.32
		shaft_mesh.bottom_radius = 0.5
		shaft_mesh.height = 4.2
		shaft_mesh.radial_segments = 8
		shaft.mesh = shaft_mesh
		shaft.position = Vector3(0, 2.1, 0)
		shaft.material_override = Fx.standard_material(Color("130e21"))
		pillar.add_child(shaft)

		var crystal := MeshInstance3D.new()
		var crystal_mesh := SphereMesh.new()
		crystal_mesh.radius = 0.34
		crystal_mesh.height = 0.68
		crystal_mesh.radial_segments = 6
		crystal_mesh.rings = 3
		crystal.mesh = crystal_mesh
		crystal.position = Vector3(0, 4.45, 0)
		crystal.material_override = Fx.glow_material(_element_color(), 3.0)
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar.add_child(crystal)
		_braziers.append(crystal)

		if i % 2 == 0:
			var light := OmniLight3D.new()
			light.light_color = _element_color()
			light.light_energy = 1.2
			light.omni_range = 7.0
			light.position = Vector3(0, 4.45, 0)
			light.shadow_enabled = false
			pillar.add_child(light)

	# Floating debris
	for i in 12:
		var angle := TAU * float(i) / 12.0 + randf_range(-0.2, 0.2)
		var radius := randf_range(15.0, 20.0)
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := randf_range(0.45, 1.5)
		box.size = Vector3(s, s * randf_range(0.6, 1.3), s * randf_range(0.6, 1.2))
		rock.mesh = box
		rock.position = Vector3(cos(angle) * radius, randf_range(3.0, 10.0), sin(angle) * radius)
		rock.rotation_degrees = Vector3(randf_range(0, 360), randf_range(0, 360), randf_range(0, 360))
		rock.material_override = Fx.standard_material(Color("1d1530"))
		add_child(rock)
		_rocks.append(rock)

	# Aim reticle
	_reticle = MeshInstance3D.new()
	var reticle_mesh := TorusMesh.new()
	reticle_mesh.inner_radius = 0.34
	reticle_mesh.outer_radius = 0.42
	reticle_mesh.rings = 20
	reticle_mesh.ring_segments = 4
	_reticle.mesh = reticle_mesh
	_reticle.material_override = Fx.glow_material(UIKit.ACCENT, 2.2)
	_reticle.position = Vector3(0, 0.06, 0)
	_reticle.visible = false
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_reticle)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 47.0
	camera.position = _cam_base
	camera.rotation_degrees = Vector3(-36.2, 0, 0)
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.current = true


func _build_stars() -> void:
	var stars := CPUParticles3D.new()
	stars.amount = 220
	stars.lifetime = 60.0
	stars.preprocess = 30.0
	stars.emitting = true
	stars.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	stars.emission_box_extents = Vector3(40, 18, 40)
	stars.direction = Vector3.ZERO
	stars.spread = 180.0
	stars.gravity = Vector3.ZERO
	stars.initial_velocity_min = 0.0
	stars.initial_velocity_max = 0.05
	stars.scale_amount_min = 0.4
	stars.scale_amount_max = 1.4
	stars.color = Color("cfd6ff")
	stars.position = Vector3(0, 8, 0)

	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.radial_segments = 4
	sphere.rings = 2
	stars.mesh = sphere
	var mat := Fx.glow_material(Color.WHITE, 2.0)
	mat.vertex_color_use_as_albedo = true
	stars.material_override = mat
	add_child(stars)


func _build_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash_rect)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _hitstop_until > 0 and now >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0

	if _flash_until > 0:
		var left := _flash_until - now
		if left <= 0:
			_flash_until = 0
			if _flash_rect != null:
				_flash_rect.color.a = 0.0
		elif _flash_rect != null:
			_flash_rect.color.a = _flash_alpha * (float(left) / float(maxi(1, _flash_duration)))

	_time += delta
	for i in _rocks.size():
		var rock := _rocks[i]
		rock.rotation.y += delta * (0.04 + 0.01 * i)
		rock.position.y += sin(_time * 0.4 + i) * delta * 0.08

	for crystal in _braziers:
		var s := 1.0 + sin(_time * 2.0 + crystal.position.x) * 0.06
		crystal.scale = Vector3(s, s, s)

	if _shake_time > 0.0:
		_shake_time -= delta
		var falloff := clampf(_shake_time / 0.25, 0.0, 1.0)
		camera.position = _camera_base() + Vector3(
			randf_range(-1.0, 1.0) * _shake_amount * falloff,
			randf_range(-1.0, 1.0) * _shake_amount * falloff,
			0.0
		)
	else:
		camera.position = camera.position.lerp(_camera_base(), minf(1.0, delta * 8.0))


func _camera_base() -> Vector3:
	if follow_camera and follow_target != null and is_instance_valid(follow_target):
		return follow_target.global_position + Vector3(0.0, 9.6, 13.2)
	return _cam_base


func set_follow(enabled: bool, target: Wizard = null) -> void:
	follow_camera = enabled
	follow_target = target


func toggle_follow(target: Wizard = null) -> bool:
	follow_target = target
	follow_camera = not follow_camera
	return follow_camera


func shake(amount: float, duration: float = 0.2) -> void:
	_shake_amount = maxf(_shake_amount, amount)
	_shake_time = maxf(_shake_time, duration)


func hitstop(duration_ms: int = 25, scale: float = 0.06) -> void:
	Engine.time_scale = minf(Engine.time_scale, scale)
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + duration_ms)


func flash(color: Color, alpha: float = 0.2, duration: float = 0.06) -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = Color(color.r, color.g, color.b, alpha)
	_flash_alpha = alpha
	_flash_duration = maxi(1, int(duration * 1000.0))
	_flash_start = Time.get_ticks_msec()
	_flash_until = _flash_start + _flash_duration


func impact(at: Vector3, color: Color, strength: float = 1.0) -> void:
	hitstop(25)
	flash(color.lightened(0.55), 0.18 + 0.10 * clampf(strength, 0.0, 1.0))
	shake(0.12 * strength, 0.14)
	impact_fx.emit(at, color, strength)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func set_reticle(pos: Vector3, color: Color, show_reticle: bool = true) -> void:
	if _reticle == null:
		return
	_reticle.visible = show_reticle
	_reticle.global_position = Vector3(pos.x, 0.06, pos.z)
	var mat := _reticle.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
		mat.emission = color
		mat.emission_energy_multiplier = 2.2


func _element_color() -> Color:
	var e: Dictionary = SpellData.ELEMENTS.get(arena_element, {})
	return e.get("color", Color("a78bfa"))


func add_wizard(wiz: Wizard) -> void:
	wizards.append(wiz)
	add_child(wiz)


func other(wiz: Wizard) -> Wizard:
	for w in wizards:
		if w != wiz:
			return w
	return null


func living_wizards() -> Array[Wizard]:
	var out: Array[Wizard] = []
	for w in wizards:
		if w.is_alive():
			out.append(w)
	return out


func spawn_spell(caster: Wizard, spell: SpellDef, stats: Dictionary, origin: Vector3, direction: Vector3) -> void:
	if not is_inside_tree():
		return
	var s := stats.duplicate(true)
	if spell.element == arena_element:
		s["damage"] = float(s["damage"]) + float(s.get("base_damage", s["damage"])) * 0.15

	var kind := str(s.get("kind", "projectile"))
	match kind:
		"projectile":
			_spawn_projectiles(caster, spell, s, origin, direction)
		"beam":
			_spawn_beam(caster, spell, s, origin, direction)
		"nova":
			_spawn_nova(caster, spell, s)
		"wall":
			_spawn_wall(caster, spell, s, direction)
		"shield":
			_spawn_shield(caster, s)


func _spawn_projectiles(caster: Wizard, spell: SpellDef, s: Dictionary, origin: Vector3, direction: Vector3) -> void:
	var count := int(s.get("count", 1))
	var spread := float(s.get("spread", 0.0))
	var target := other(caster)

	for i in count:
		var dir := direction
		if count > 1 and spread > 0.0:
			var t := float(i) / float(count - 1) - 0.5
			dir = direction.rotated(Vector3.UP, deg_to_rad(spread * t))
		var proj := SpellProjectile.new()
		proj.setup({
			"arena": self,
			"caster": caster,
			"target": target,
			"direction": dir,
			"speed": s.get("speed", 16.0),
			"damage": s.get("damage", 10.0),
			"element": spell.element,
			"color": s.get("color", Color.WHITE),
			"knockback": s.get("knockback", 1.5),
			"pierce": s.get("pierce", 0),
			"homing": s.get("homing", false),
			"overcast": s.get("overcast", false),
			"spell": spell,
			"radius": s.get("radius", 0.32),
			"stats": s,
		})
		projectiles.add_child(proj)
		proj.global_position = origin


func _spawn_beam(caster: Wizard, spell: SpellDef, s: Dictionary, origin: Vector3, direction: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * float(s.get("range", 15.0)))
	query.collision_mask = 1 | 2
	query.exclude = [caster.get_rid()]
	var hit := space.intersect_ray(query)
	var end := origin + direction * float(s.get("range", 15.0))
	var victim: Wizard = null
	if not hit.is_empty():
		end = hit["position"]
		if hit["collider"] is Wizard:
			victim = hit["collider"]

	Fx.beam(effects, origin, end, s.get("color", Color.WHITE), 0.12 if s.get("overcast", false) else 0.085)
	Fx.burst(effects, end, s.get("color", Color.WHITE), 12, 4.0, 0.07, 0.35)
	if victim != null:
		_resolve_on(caster, victim, spell, s, origin)
		shake(0.18, 0.16)


func _spawn_nova(caster: Wizard, spell: SpellDef, s: Dictionary) -> void:
	var radius := float(s.get("radius", 4.8))
	var color: Color = s.get("color", Color.WHITE)
	Fx.shockwave(effects, caster.global_position, color, radius, 0.5)
	Fx.burst(effects, caster.global_position + Vector3.UP * 0.8, color, 28, 10.0, 0.1, 0.55)
	shake(0.2, 0.2)
	for w in wizards:
		if w == caster or not w.is_alive():
			continue
		var d := caster.global_position.distance_to(w.global_position)
		if d <= radius:
			var falloff := clampf(1.0 - (d / radius) * 0.45, 0.55, 1.0)
			var s2 := s.duplicate(true)
			s2["damage"] = float(s["damage"]) * falloff
			_resolve_on(caster, w, spell, s2, caster.global_position)


func _spawn_wall(caster: Wizard, spell: SpellDef, s: Dictionary, direction: Vector3) -> void:
	var wall := SpellWall.new()
	var color: Color = s.get("color", Color.WHITE)
	wall.setup(color, float(s.get("duration", 7.0)))
	walls.add_child(wall)
	var pos := caster.global_position + direction.normalized() * 2.3
	wall.global_position = Vector3(pos.x, 0.0, pos.z)
	wall.rotation.y = atan2(direction.x, direction.z)
	Fx.burst(effects, wall.global_position + Vector3.UP * 1.0, color, 18, 5.0, 0.08, 0.45)


func _spawn_shield(caster: Wizard, s: Dictionary) -> void:
	var color: Color = s.get("color", Color("8fe7ff"))
	caster.add_shield(float(s.get("shield", 30.0)), float(s.get("duration", 3.0)), color)
	Fx.shockwave(effects, caster.global_position, color, 1.7, 0.35)
	Fx.burst(effects, caster.global_position + Vector3.UP * 1.0, color, 16, 4.0, 0.07, 0.4)
	shake(0.06, 0.1)


func resolve_hit(proj: SpellProjectile, victim: Wizard) -> void:
	if proj.spell == null:
		return
	_resolve_on(proj.caster, victim, proj.spell, proj.stats, proj.global_position)


func _resolve_on(caster: Wizard, victim: Wizard, spell: SpellDef, s: Dictionary, from_pos: Vector3) -> void:
	if victim == null or not victim.is_alive():
		return
	var damage := float(s.get("damage", 0.0))
	if damage > 0.0:
		victim.take_damage(damage, spell.element, from_pos, float(s.get("knockback", 0.0)))
		impact(victim.global_position + Vector3.UP * 1.0, s.get("color", Color.WHITE), 0.7 if damage < 20.0 else 1.0)

	# Element riders
	match spell.element:
		"void":
			if caster != null:
				caster.heal(damage * 0.25)
		"storm":
			var chained := false
			for w in wizards:
				if w == caster or w == victim or not w.is_alive():
					continue
				if victim.global_position.distance_to(w.global_position) <= 6.0:
					Fx.beam(effects, victim.global_position + Vector3.UP * 1.0, w.global_position + Vector3.UP * 1.0, s.get("color", Color.WHITE), 0.05, 0.2)
					w.take_damage(damage * 0.5, spell.element, victim.global_position, 1.0, false)
					chained = true
					break
			if not chained:
				# In a 1v1 there is no second foe: the bolt arcs back through the victim.
				Fx.beam(effects, victim.global_position + Vector3.UP * 2.1, victim.global_position + Vector3.UP * 0.3, s.get("color", Color.WHITE), 0.05, 0.18)
				victim.take_damage(damage * 0.5, spell.element, victim.global_position, 0.0, false)
			shake(0.08, 0.12)


func spawn_position(index: int) -> Vector3:
	return Vector3(-6.0 if index == 0 else 6.0, 0.0, 0.0)


func dispose() -> void:
	queue_free()
