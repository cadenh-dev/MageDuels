class_name Arena
extends Node3D

## The 2.5D duelling stage. Owns the camera, lighting, and spell resolution.

var wizards: Array[Wizard] = []
signal beam_fx(from: Vector3, to: Vector3, color: Color, width: float)
var networked := false
var projectiles: Node3D
var effects: Node3D
var walls: Node3D
var zones: Node3D
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
	zones = _container("Zones")

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
	cyl.height = 0.9
	shape.shape = cyl
	shape.position = Vector3(0, -0.45, 0)
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
	# Online physics and transport cadence must use real time on both peers.
	if networked:
		return
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


func enemies_of(w: Wizard) -> Array[Wizard]:
	var out: Array[Wizard] = []
	for other_w in wizards:
		if other_w != w and is_instance_valid(other_w) and other_w.alive:
			out.append(other_w)
	return out


func active_walls() -> Array[SpellWall]:
	var out: Array[SpellWall] = []
	if walls == null:
		return out
	for child in walls.get_children():
		if child is SpellWall and not child.broken and not child.is_queued_for_deletion():
			out.append(child)
	return out


func active_zones() -> Array[SpellZone]:
	var out: Array[SpellZone] = []
	if zones == null:
		return out
	for child in zones.get_children():
		if child is SpellZone and not child.is_queued_for_deletion():
			out.append(child)
	return out


func spawn_spell(caster: Wizard, spell: SpellDef, stats: Dictionary, origin: Vector3, direction: Vector3) -> void:
	if not is_inside_tree():
		return
	var s := stats.duplicate(true)
	if spell.element == arena_element:
		s["damage"] = float(s["damage"]) + float(s.get("base_damage", s["damage"])) * 0.15
		s["power"] = float(s.get("power", 1.0)) + float(s.get("mod_damage", 1.0)) * 0.15

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
			_spawn_shield(caster, spell, s)


func _spawn_projectiles(caster: Wizard, spell: SpellDef, s: Dictionary, origin: Vector3, direction: Vector3) -> void:
	var count := int(s.get("count", 1))
	var spread := float(s.get("spread", 0.0))
	var target := other(caster)
	var c := spell.cell()
	if bool(c.get("low", false)):
		origin = Vector3(origin.x, 0.45, origin.z)
		direction = Vector3(direction.x, 0.0, direction.z).normalized()
	var radius := float(s.get("radius", 0.32))
	if spell.element == "earth" and spell.form == "orb":
		radius = 0.55

	for i in count:
		var dir := direction
		if count > 1 and spread > 0.0:
			var t := float(i) / float(count - 1) - 0.5
			dir = direction.rotated(Vector3.UP, deg_to_rad(spread * t))
		launch_projectile(caster, target, spell, s, origin, dir, radius)


func launch_projectile(caster: Wizard, target: Wizard, spell: SpellDef, s: Dictionary, origin: Vector3, dir: Vector3, radius: float, extra: Dictionary = {}) -> SpellProjectile:
	var proj := SpellProjectile.new()
	var params := {
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
		"homing_strength": s.get("homing_strength", 3.2),
		"overcast": s.get("overcast", false),
		"spell": spell,
		"radius": radius,
		"stats": s,
		"lifetime": s.get("lifetime", 5.0),
	}
	params.merge(extra, true)
	proj.setup(params)
	projectiles.add_child(proj)
	proj.global_position = origin
	return proj


# ---- Cross-material rules ---------------------------------------------------

## Resolve every ward the step from->to crosses, in order along the path, with
## the cross-material order from SPELLCRAFT.md. Returns {} to keep flying,
## {"stop": true, "point"} to end at a wall, {"redirect": true, "point"} after
## a reflection. May mutate the projectile (speed, damage, owner, ignition).
func projectile_walls(proj: SpellProjectile, from: Vector3, to: Vector3) -> Dictionary:
	var hits: Array = []
	for wall in active_walls():
		if proj.walls_done.has(wall.get_instance_id()):
			continue
		var t := wall.crossing_t(from, to, proj.radius)
		if t >= 0.0:
			hits.append([t, wall])
	if hits.is_empty():
		return {}
	hits.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var c: Dictionary = proj.spell.cell() if proj.spell != null else {}
	for entry in hits:
		var wall: SpellWall = entry[1]
		if wall.broken:
			continue
		proj.walls_done[wall.get_instance_id()] = true
		var point := from.lerp(to, float(entry[0]))
		var enemy_wall := wall.owner_wizard != proj.caster
		# 1. Rift consumes enemy projectiles; its caster heals 25%.
		if wall.element == "void" and enemy_wall:
			if wall.owner_wizard != null and is_instance_valid(wall.owner_wizard):
				wall.owner_wizard.heal(proj.damage * float(SpellData.cell("void", "wall").get("heal", 0.25)))
			Fx.burst(effects, point, wall.color, 16, 2.0, 0.08, 0.4)
			proj.destroy(point)
			return {"stop": false}
		# 2. Mirror Ward reflects enemy projectiles and flips ownership.
		if wall.element == "arcane" and enemy_wall:
			var old_owner := proj.caster
			proj.redirect(wall.owner_wizard, proj.direction.bounce(wall.normal()), old_owner)
			proj.walls_done.erase(wall.get_instance_id())
			proj.walls_done[wall.get_instance_id()] = true
			wall.use_reflection()
			Fx.burst(effects, point, wall.color, 12, 3.0, 0.07, 0.3)
			return {"redirect": true, "point": point + proj.direction * 0.05}
		# 3. Arcane force phases through solid matter.
		if bool(c.get("phase", false)) and wall.is_solid():
			continue
		# 4. A Boulder smashes an Ice Wall and keeps rolling.
		if bool(c.get("smash_ice", false)) and wall.element == "frost":
			wall.shatter()
			continue
		# 5. Frost melts in a Flame Sheet.
		if proj.element == "frost" and wall.element == "fire":
			Fx.burst(effects, point, Color("bff6ff"), 10, 2.0, 0.06, 0.3)
			proj.destroy(point)
			return {"stop": false}
		# 6. Stone stops the projectile and takes its damage.
		if wall.element == "earth" or wall.element == "":
			# 10. Pierce may pass one wall it would otherwise stop at.
			if proj.pierce > 0:
				proj.pierce -= 1
				continue
			wall.damage_wall(proj.damage, proj.element)
			return {"stop": true, "point": point, "wall": wall}
		# 7. Ice lets it through slowed, weaker, and takes its damage.
		if wall.element == "frost":
			var ice := SpellData.cell("frost", "wall")
			wall.damage_wall(proj.damage, proj.element)
			proj.speed *= 1.0 - float(ice.get("proj_slow", 0.5))
			proj.damage *= 1.0 - float(ice.get("proj_damage_loss", 0.25))
			continue
		# 8. Flame Sheet ignites what passes.
		if wall.element == "fire":
			if proj.element != "fire":
				proj.ignited = true
			continue
		# 9. Tesla Fence, own Mirror/Rift: pass.
	return {}


## Per-frame hazards a projectile flies into. Returns true if it was destroyed.
func projectile_hazards(proj: SpellProjectile) -> bool:
	if proj.element != "frost":
		return false
	for w in wizards:
		if w == proj.caster or not is_instance_valid(w) or not w.alive or not w.has_shield("fire"):
			continue
		var r := float(SpellData.cell("fire", "aegis").get("aura_radius", 2.2))
		var d := Vector2(proj.global_position.x - w.global_position.x, proj.global_position.z - w.global_position.z).length()
		if d <= r:
			Fx.burst(effects, proj.global_position, Color("bff6ff"), 10, 2.0, 0.06, 0.3)
			proj.destroy(proj.global_position)
			return true
	return false


## True when a straight line crosses something that stops projectiles.
func line_blocked(from: Vector3, to: Vector3) -> bool:
	for wall in active_walls():
		if wall.element in ["earth", ""] and wall.crossing_t(from, to) >= 0.0:
			return true
	return false


## The first enemy Mirror Ward or Rift (relative to ``caster``) on a line.
func hostile_ward_on_line(caster: Wizard, from: Vector3, to: Vector3) -> SpellWall:
	for wall in active_walls():
		if wall.owner_wizard != caster and wall.element in ["arcane", "void"] and wall.crossing_t(from, to) >= 0.0:
			return wall
	return null


func hostile_zone_at(w: Wizard, pos: Vector3) -> bool:
	for zone in active_zones():
		if zone.is_hostile_to(w) and zone.contains(pos):
			return true
	for wall in active_walls():
		if wall.owner_wizard != w and wall.element in ["fire", "storm"] and wall.distance_to_point(pos) <= 0.9:
			return true
	return false


# ---- Projectile payloads ------------------------------------------------------

func projectile_end(proj: SpellProjectile, at: Vector3, reason: String, victim: Wizard) -> void:
	if proj.spell == null:
		return
	var c := proj.spell.cell()
	var s := proj.stats
	var ground := Vector3(at.x, 0.0, at.z)
	if c.has("patch_radius") and reason in ["hit", "wall", "expire"]:
		if c.has("explode_radius"):
			_fireball_explode(proj, at, victim)
		spawn_zone({"owner": proj.caster, "element": "fire", "shape": "circle", "position": ground,
			"radius": float(c["patch_radius"]), "duration": float(c["patch_duration"]) * float(s.get("dur_mult", 1.0)),
			"dps": float(c["patch_dps"]) * float(s.get("zone_mult", 1.0)), "burn": _rider_burn(s)})
	if c.has("fragments") and reason == "wall" and not bool(s.get("fragment", false)):
		_ice_fragments(proj, at)
	if c.has("collapse_radius"):
		_collapse(proj, at)


func _fireball_explode(proj: SpellProjectile, at: Vector3, victim: Wizard) -> void:
	var c := proj.spell.cell()
	var r := float(c.get("explode_radius", 2.2))
	Fx.shockwave(effects, Vector3(at.x, 0.05, at.z), proj.color, r, 0.35)
	for w in enemies_of(proj.caster):
		if w == victim:
			continue
		if Vector2(w.global_position.x - at.x, w.global_position.z - at.z).length() <= r + 0.4:
			w.take_damage(float(c.get("splash", 8.0)) * float(proj.stats.get("power", 1.0)), "fire", at, 1.0,
				not bool(proj.stats.get("fizzle", false)), {"attacker": proj.caster, "direct": true})


func _ice_fragments(proj: SpellProjectile, at: Vector3) -> void:
	var c := proj.spell.cell()
	var n := int(c.get("fragments", 3))
	var cone := float(c.get("fragment_cone", 40.0))
	var back := -proj.direction
	back.y = 0.0
	back = back.normalized()
	var s := proj.stats.duplicate()
	s["damage"] = float(c.get("fragment_damage", 4.0)) * float(proj.stats.get("power", 1.0))
	s["fragment"] = true
	s["knockback"] = 0.5
	s["homing"] = false
	s["pierce"] = 0
	s["count"] = 1
	var speed := float(c.get("speed", 17.0))
	s["speed"] = speed
	s["lifetime"] = float(c.get("fragment_range", 6.0)) / speed
	for i in n:
		var t := (float(i) / float(maxi(1, n - 1)) - 0.5) if n > 1 else 0.0
		var dir := back.rotated(Vector3.UP, deg_to_rad(cone * t))
		var frag := launch_projectile(proj.caster, proj.target, proj.spell, s, at + dir * 0.15, dir, 0.16)
		frag.walls_done = proj.walls_done.duplicate()


func _collapse(proj: SpellProjectile, at: Vector3) -> void:
	var c := proj.spell.cell()
	var r := float(c.get("collapse_radius", 1.5))
	var damage := (float(c.get("damage", 12.0)) + float(c.get("absorb_bonus", 3.0)) * proj.absorbed) * float(proj.stats.get("power", 1.0))
	Fx.shockwave(effects, Vector3(at.x, 0.05, at.z), proj.color, r + 0.3, 0.35)
	for w in enemies_of(proj.caster):
		if Vector2(w.global_position.x - at.x, w.global_position.z - at.z).length() <= r + 0.46:
			var s := proj.stats.duplicate()
			s["damage"] = damage
			s["knockback"] = 0.0
			_resolve_on(proj.caster, w, proj.spell, s, at, {"projectile": true})


## Ball Lightning: zap the nearest enemy within range, no line of sight needed.
func orb_zap(proj: SpellProjectile) -> void:
	var c := proj.spell.cell()
	var best: Wizard = null
	var best_d := float(c.get("zap_range", 3.5))
	for w in enemies_of(proj.caster):
		var d := proj.global_position.distance_to(w.global_position + Vector3.UP * 0.9)
		if d <= best_d:
			best_d = d
			best = w
	if best == null:
		return
	var dmg := float(c.get("zap_dps", 8.0)) * float(c.get("zap_interval", 0.5)) * float(proj.stats.get("zone_mult", 1.0))
	best.take_damage(dmg, "storm", proj.global_position, 0.0, not bool(proj.stats.get("fizzle", false)),
		{"attacker": proj.caster, "direct": false, "jolt": 0.0})
	Fx.beam(effects, proj.global_position, best.global_position + Vector3.UP * 1.0, proj.color, 0.04, 0.12)


## Mana Sphere: siphon mana from a nearby enemy to the caster.
func orb_leech(proj: SpellProjectile) -> void:
	var c := proj.spell.cell()
	for w in enemies_of(proj.caster):
		if proj.global_position.distance_to(w.global_position + Vector3.UP * 0.9) <= float(c.get("leech_range", 3.0)):
			var amount := minf(w.mana, float(c.get("leech_mana", 4.0)))
			w.mana -= amount
			w.mana_changed.emit(w, w.mana, w.max_mana)
			if proj.caster != null and is_instance_valid(proj.caster):
				proj.caster.mana = minf(proj.caster.max_mana, proj.caster.mana + amount)
				proj.caster.mana_changed.emit(proj.caster, proj.caster.mana, proj.caster.max_mana)
			Fx.beam(effects, w.global_position + Vector3.UP * 1.0, proj.global_position, proj.color, 0.03, 0.1)
			return


## Singularity: drag enemies toward it.
func orb_pull(proj: SpellProjectile, delta: float) -> void:
	var c := proj.spell.cell()
	for w in enemies_of(proj.caster):
		if w.is_cc_immune():
			continue
		var to := proj.global_position - w.global_position
		to.y = 0.0
		var d := to.length()
		if d <= float(c.get("pull_radius", 3.5)) and d > 0.3:
			w.add_drift(to.normalized() * float(c.get("pull_speed", 3.0)))


## Singularity: swallow enemy projectiles it touches (+3 payload each).
func orb_absorb(proj: SpellProjectile) -> void:
	for child in projectiles.get_children():
		if child == proj or not child is SpellProjectile:
			continue
		var other_p := child as SpellProjectile
		if other_p._dead or other_p.caster == proj.caster:
			continue
		if other_p.global_position.distance_to(proj.global_position) <= proj.radius + other_p.radius + 0.35:
			proj.absorbed += 1
			other_p.destroy(other_p.global_position)


## Frost Globe trail: a short ice strip behind the orb.
func spawn_trail(proj: SpellProjectile, from: Vector3, to: Vector3) -> void:
	var c := proj.spell.cell()
	spawn_zone({"owner": proj.caster, "element": "frost", "shape": "strip", "a": from, "b": to,
		"half_width": float(c.get("trail_width", 1.2)) * 0.5,
		"duration": float(c.get("trail_duration", 3.0)) * float(proj.stats.get("dur_mult", 1.0)), "chill": true})


## Fizzles skip status riders, including the burn their hazards would apply.
func _rider_burn(s: Dictionary) -> float:
	return 0.0 if bool(s.get("fizzle", false)) else Wizard.BURN_TOTAL


func spawn_zone(p: Dictionary) -> SpellZone:
	var zone := SpellZone.new()
	p["arena"] = self
	zone.setup(p)
	zones.add_child(zone)
	if zone.shape != "strip":
		var pos: Vector3 = p.get("position", Vector3.ZERO)
		zone.global_position = Vector3(pos.x, 0.0, pos.z)
	return zone


# ---- Beams --------------------------------------------------------------------

func _spawn_beam(caster: Wizard, spell: SpellDef, s: Dictionary, origin: Vector3, direction: Vector3) -> void:
	var c := spell.cell()
	var color: Color = s.get("color", Color.WHITE)
	var width := 0.12 if s.get("overcast", false) else 0.085
	if c.has("beam_width"):
		width *= 2.4
	var owner_w := caster
	var pos := origin
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	var remaining := float(s.get("range", 15.0))
	var damage := float(s.get("damage", 0.0))
	var pierce := int(s.get("pierce", 0))
	var bounces := int(c.get("bounces", 0))
	var hit_r := float(c.get("beam_width", 0.0)) + 0.2 if c.has("beam_width") else 0.6
	var done_walls: Dictionary = {}
	var done_wizards: Array[Wizard] = []
	var segments: Array = []
	for _iter in 8:
		if remaining <= 0.05:
			break
		var end := pos + dir * remaining
		var best_t := 2.0
		var best_wall: SpellWall = null
		var best_wiz: Wizard = null
		for wall in active_walls():
			if done_walls.has(wall.get_instance_id()):
				continue
			var t := wall.crossing_t(pos, end)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_wall = wall
		for w in wizards:
			if w == owner_w or not is_instance_valid(w) or not w.alive or w in done_wizards:
				continue
			var t := _segment_param(pos, end, w.global_position, hit_r)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_wall = null
				best_wiz = w
		if best_t > 1.0:
			segments.append([pos, end])
			break
		var point := pos.lerp(end, best_t)
		segments.append([pos, point])
		remaining -= pos.distance_to(point)
		pos = point
		if best_wiz != null:
			var s2 := s.duplicate()
			s2["damage"] = damage
			_resolve_on(owner_w, best_wiz, spell, s2, origin, {"beam": true})
			shake(0.18, 0.16)
			done_wizards.append(best_wiz)
			if pierce > 0:
				pierce -= 1
				continue
			break
		var wall := best_wall
		done_walls[wall.get_instance_id()] = true
		var enemy_wall := wall.owner_wizard != owner_w
		if wall.element == "void" and enemy_wall:
			break
		if wall.element == "arcane" and enemy_wall:
			dir = dir.bounce(wall.normal())
			owner_w = wall.owner_wizard
			done_wizards.clear()
			wall.use_reflection()
			continue
		if c.has("wall_loss"):
			damage *= 1.0 - float(c["wall_loss"])
			continue
		if not wall.is_solid():
			continue
		if pierce > 0:
			pierce -= 1
			continue
		if bounces > 0:
			bounces -= 1
			dir = dir.bounce(wall.normal())
			done_walls.erase(wall.get_instance_id())
			pos += dir * 0.05
			done_walls[wall.get_instance_id()] = true
			continue
		wall.damage_wall(damage, spell.element)
		break

	var y_off := Vector3.ZERO
	if spell.element == "earth":
		y_off = Vector3(0, -(origin.y - 0.25), 0)
	for seg in segments:
		var a: Vector3 = seg[0] + y_off
		var b: Vector3 = seg[1] + y_off
		Fx.beam(effects, a, b, color, width)
		beam_fx.emit(a, b, color, width)
	if not segments.is_empty():
		Fx.burst(effects, segments[-1][1] + y_off, color, 12, 4.0, 0.07, 0.35)
	if c.has("strip_width"):
		for seg in segments:
			spawn_zone({"owner": caster, "element": "frost", "shape": "strip", "a": seg[0], "b": seg[1],
				"half_width": float(c["strip_width"]) * 0.5,
				"duration": float(c.get("strip_duration", 3.0)) * float(s.get("dur_mult", 1.0)), "chill": true})


## Param t in [0, 1] of the closest approach of ``point`` to from->to in the
## ground plane if within ``radius``, else -1.
func _segment_param(from: Vector3, to: Vector3, point: Vector3, radius: float) -> float:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var p := Vector2(point.x, point.z)
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return -1.0
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	if (a + ab * t).distance_to(p) > radius:
		return -1.0
	return t


# ---- Novas, wards, aegis ------------------------------------------------------

func _spawn_nova(caster: Wizard, spell: SpellDef, s: Dictionary) -> void:
	var c := spell.cell()
	var radius := float(s.get("radius", 4.8))
	var color: Color = s.get("color", Color.WHITE)
	var center := caster.global_position
	Fx.shockwave(effects, center, color, radius, 0.5)
	Fx.burst(effects, center + Vector3.UP * 0.8, color, 28, 10.0, 0.1, 0.55)
	shake(0.2, 0.2)
	for w in enemies_of(caster):
		var d := center.distance_to(w.global_position)
		if d <= radius:
			var falloff := clampf(1.0 - (d / radius) * 0.45, 0.55, 1.0)
			var s2 := s.duplicate(true)
			s2["damage"] = float(s["damage"]) * falloff
			_resolve_on(caster, w, spell, s2, center, {"nova": true})
	var dur_mult := float(s.get("dur_mult", 1.0))
	var zone_mult := float(s.get("zone_mult", 1.0))
	if c.has("band_inner"):
		spawn_zone({"owner": caster, "element": "fire", "shape": "band", "position": center,
			"inner": float(c["band_inner"]) * radius / 4.8, "radius": radius,
			"duration": float(c.get("band_duration", 3.0)) * dur_mult,
			"dps": float(c.get("band_dps", 5.0)) * zone_mult, "burn": _rider_burn(s)})
	if c.has("floor_duration"):
		spawn_zone({"owner": caster, "element": "frost", "shape": "circle", "position": center,
			"radius": radius, "duration": float(c["floor_duration"]) * dur_mult, "chill": true})
	if c.has("wall_damage"):
		for wall in active_walls():
			if wall.distance_to_point(center) <= radius:
				wall.damage_wall(float(c["wall_damage"]), "earth", true)
	if bool(c.get("reflect", false)):
		for child in projectiles.get_children():
			if not child is SpellProjectile:
				continue
			var p := child as SpellProjectile
			if p._dead or p.caster == caster:
				continue
			if Vector2(p.global_position.x - center.x, p.global_position.z - center.z).length() <= radius:
				var old_owner := p.caster
				var back := Vector3.ZERO
				if old_owner != null and is_instance_valid(old_owner):
					back = old_owner.global_position + Vector3.UP * 0.9 - p.global_position
				if back.length() < 0.01:
					back = -p.direction
				p.redirect(caster, back.normalized(), old_owner)


func _spawn_wall(caster: Wizard, spell: SpellDef, s: Dictionary, direction: Vector3) -> void:
	var wall := SpellWall.new()
	var color: Color = s.get("color", Color.WHITE)
	wall.setup_ward({"arena": self, "owner": caster, "element": spell.element, "stats": s, "color": color})
	walls.add_child(wall)
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	var pos := caster.global_position + flat * 2.3
	wall.global_position = Vector3(pos.x, 0.0, pos.z)
	wall.rotation.y = atan2(flat.x, flat.z)
	Fx.burst(effects, wall.global_position + Vector3.UP * 1.0, color, 18, 5.0, 0.08, 0.45)


func _spawn_shield(caster: Wizard, spell: SpellDef, s: Dictionary) -> void:
	var color: Color = s.get("color", Color("8fe7ff"))
	var c := spell.cell()
	caster.add_shield(float(s.get("shield", 0.0)), float(s.get("duration", 4.0)), color, spell.element, s)
	if c.has("aura_radius"):
		spawn_zone({"owner": caster, "attach": caster, "element": "fire", "shape": "circle",
			"position": caster.global_position, "radius": float(c["aura_radius"]),
			"duration": float(s.get("duration", 4.0)) + 0.1,
			"dps": float(c.get("aura_dps", 6.0)) * float(s.get("zone_mult", 1.0)), "burn": _rider_burn(s)})
	Fx.shockwave(effects, caster.global_position, color, 1.7, 0.35)
	Fx.burst(effects, caster.global_position + Vector3.UP * 1.0, color, 16, 4.0, 0.07, 0.4)
	shake(0.06, 0.1)


## Static Shell: arc back at a direct attacker.
func static_arc(defender: Wizard, attacker: Wizard) -> void:
	if attacker == null or not is_instance_valid(attacker) or not attacker.alive:
		return
	var c := SpellData.cell("storm", "aegis")
	var power := float(defender.shield_stats.get("power", 1.0))
	Fx.beam(effects, defender.global_position + Vector3.UP * 1.2, attacker.global_position + Vector3.UP * 1.0, Color("ffe066"), 0.05, 0.16)
	attacker.take_damage(float(c.get("arc_damage", 8.0)) * power, "storm", defender.global_position, 0.0, true,
		{"attacker": defender, "direct": false, "jolt": Wizard.JOLT_TIME})


## Ice Armor shatters on whoever is near when it breaks.
func on_shield_broken(w: Wizard, element: String, stats: Dictionary) -> void:
	if element != "frost":
		return
	_ice_shatter(w, w.global_position, float(stats.get("power", 1.0)), SpellData.cell("frost", "aegis"))


func on_wall_broken(wall: SpellWall) -> void:
	if wall.element == "frost":
		_ice_shatter(wall.owner_wizard, wall.global_position, float(wall.stats.get("power", 1.0)), SpellData.cell("frost", "wall"))


func _ice_shatter(owner_w: Wizard, at: Vector3, power: float, c: Dictionary) -> void:
	var r := float(c.get("shatter_radius", 2.5))
	Fx.shockwave(effects, Vector3(at.x, 0.05, at.z), Color("bff6ff"), r, 0.35)
	Fx.burst(effects, at + Vector3.UP * 1.0, Color("e8fbff"), 26, 6.0, 0.08, 0.5)
	for w in wizards:
		if w == owner_w or not is_instance_valid(w) or not w.alive:
			continue
		if Vector2(w.global_position.x - at.x, w.global_position.z - at.z).length() <= r:
			w.take_damage(float(c.get("shatter_damage", 8.0)) * power, "frost", at, 1.0, true, {"attacker": owner_w, "direct": false})


func resolve_hit(proj: SpellProjectile, victim: Wizard) -> void:
	if proj.spell == null:
		return
	var s := proj.stats.duplicate()
	s["damage"] = proj.damage
	s["knockback"] = proj.knockback
	_resolve_on(proj.caster, victim, proj.spell, s, proj.global_position, {"projectile": true, "ignite": proj.ignited})


func _resolve_on(caster: Wizard, victim: Wizard, spell: SpellDef, s: Dictionary, from_pos: Vector3, extra: Dictionary = {}) -> void:
	if victim == null or not victim.is_alive():
		return
	var c := spell.cell()
	var damage := float(s.get("damage", 0.0))
	var knockback := float(s.get("knockback", 0.0))
	var hit := {"attacker": caster, "projectile": bool(extra.get("projectile", false)), "ignite": bool(extra.get("ignite", false))}
	if c.has("chill"):
		hit["chill"] = float(c["chill"])
		hit["chill_time"] = float(c.get("chill_time", Wizard.CHILL_TIME))
	if c.has("jolt"):
		hit["jolt"] = float(c["jolt"])
	if c.has("mana_burn"):
		hit["mana_burn"] = float(c["mana_burn"])
	if c.has("pull") and caster != null and is_instance_valid(caster):
		hit["pull_to"] = caster.global_position
		hit["pull"] = float(c["pull"])
		knockback = 0.0
	if damage > 0.0:
		victim.take_damage(damage, spell.element, from_pos, knockback, not bool(s.get("fizzle", false)), hit)
		impact(victim.global_position + Vector3.UP * 1.0, s.get("color", Color.WHITE), 0.7 if damage < 20.0 else 1.0)

	# Element riders credited to the current owner.
	match spell.element:
		"void":
			if caster != null and is_instance_valid(caster):
				caster.heal(damage * float(c.get("drain", 0.25)))
		"storm":
			if not c.has("chain"):
				return
			var chain := float(c["chain"])
			var chained := false
			for w in wizards:
				if w == caster or w == victim or not w.is_alive():
					continue
				if victim.global_position.distance_to(w.global_position) <= 6.0:
					Fx.beam(effects, victim.global_position + Vector3.UP * 1.0, w.global_position + Vector3.UP * 1.0, s.get("color", Color.WHITE), 0.05, 0.2)
					w.take_damage(damage * chain, spell.element, victim.global_position, 1.0, false, {"direct": false})
					chained = true
					break
			if not chained and victim.is_alive():
				# In a 1v1 there is no second foe: the bolt arcs back through the victim.
				Fx.beam(effects, victim.global_position + Vector3.UP * 2.1, victim.global_position + Vector3.UP * 0.3, s.get("color", Color.WHITE), 0.05, 0.18)
				victim.take_damage(damage * chain, spell.element, victim.global_position, 0.0, false, {"direct": false})
			shake(0.08, 0.12)


func spawn_position(index: int) -> Vector3:
	return Vector3(-6.0 if index == 0 else 6.0, 0.0, 0.0)


func dispose() -> void:
	queue_free()
