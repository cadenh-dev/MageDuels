class_name SpellZone
extends Node3D

## A ground hazard: fire patch, burning band, ice trail/strip/floor, or an aura
## attached to a wizard. The host ticks it every 0.25 s with plain distance
## checks (no physics areas); clients only render it.

const TICK := 0.25
const SHAPES: Array[String] = ["circle", "band", "strip"]

static var _materials: Dictionary = {}

var arena: Node
var owner_wizard: Wizard
var attach: Wizard
var element := "fire"
var shape := "circle"
var radius := 1.2
var inner := 0.0
var half_width := 0.5
## Strip endpoints in world space (y ignored).
var a := Vector3.ZERO
var b := Vector3.ZERO
var duration := 3.0
var dps := 0.0
var burn := 0.0
var chill := false
var slow := 0.0
var authority := true
var color := Color.WHITE

var _tick := 0.0
var _age := 0.0
var _mesh: MeshInstance3D
var _particles: CPUParticles3D


func setup(p: Dictionary) -> void:
	arena = p.get("arena")
	owner_wizard = p.get("owner")
	attach = p.get("attach")
	element = str(p.get("element", "fire"))
	shape = str(p.get("shape", "circle"))
	radius = float(p.get("radius", 1.2))
	inner = float(p.get("inner", 0.0))
	half_width = float(p.get("half_width", 0.5))
	a = p.get("a", Vector3.ZERO)
	b = p.get("b", Vector3.ZERO)
	duration = float(p.get("duration", 3.0))
	dps = float(p.get("dps", 0.0))
	burn = float(p.get("burn", 0.0))
	chill = bool(p.get("chill", false))
	slow = float(p.get("slow", 0.0))
	authority = bool(p.get("authority", true))
	color = SpellData.ELEMENTS.get(element, {}).get("color", Color.WHITE)
	_build_visual()


func _ready() -> void:
	if shape == "strip":
		var mid := (a + b) * 0.5
		global_position = Vector3(mid.x, 0.0, mid.z)
		var d := b - a
		d.y = 0.0
		if d.length() > 0.001:
			global_rotation = Vector3(0.0, atan2(d.x, d.z), 0.0)
	if _particles != null:
		_particles.emitting = true


func _build_visual() -> void:
	var mesh: Mesh
	match shape:
		"band":
			var torus := TorusMesh.new()
			torus.inner_radius = inner
			torus.outer_radius = radius
			torus.rings = 48
			torus.ring_segments = 6
			mesh = torus
		"strip":
			var box := BoxMesh.new()
			box.size = Vector3(half_width * 2.0, 0.04, maxf(0.1, Vector2(b.x - a.x, b.z - a.z).length()))
			mesh = box
		_:
			var disc := CylinderMesh.new()
			disc.top_radius = radius
			disc.bottom_radius = radius
			disc.height = 0.04
			disc.radial_segments = 24
			disc.rings = 1
			mesh = disc
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = zone_material(element)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.position = Vector3(0, 0.03, 0)
	if shape == "band":
		_mesh.scale = Vector3(1.0, 0.06, 1.0)
	add_child(_mesh)

	if element == "fire" and shape != "strip":
		_particles = CPUParticles3D.new()
		_particles.amount = 28 if shape == "band" else 14
		_particles.lifetime = 0.5
		_particles.emitting = false
		_particles.local_coords = false
		_particles.direction = Vector3.UP
		_particles.spread = 15.0
		_particles.gravity = Vector3(0, 2.0, 0)
		_particles.initial_velocity_min = 0.6
		_particles.initial_velocity_max = 1.6
		_particles.scale_amount_min = 0.6
		_particles.scale_amount_max = 1.4
		if shape == "band":
			_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			_particles.emission_ring_axis = Vector3.UP
			_particles.emission_ring_radius = radius - 0.2
			_particles.emission_ring_inner_radius = inner + 0.1
			_particles.emission_ring_height = 0.05
		else:
			_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			_particles.emission_sphere_radius = radius * 0.8
		var pm := SphereMesh.new()
		pm.radius = 0.08
		pm.height = 0.16
		pm.radial_segments = 6
		pm.rings = 3
		_particles.mesh = pm
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
		ramp.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
		_particles.color_ramp = ramp
		_particles.material_override = flame_particle_material()
		add_child(_particles)


static func zone_material(p_element: String) -> StandardMaterial3D:
	if not _materials.has(p_element):
		var c: Color = SpellData.ELEMENTS.get(p_element, {}).get("color", Color.WHITE)
		var mat: StandardMaterial3D
		if p_element == "frost":
			mat = Fx.glow_material(Color(0.82, 0.95, 1.0, 0.42), 0.8)
		elif p_element == "fire":
			mat = Fx.glow_material(Color(c.r, c.g * 0.8, c.b * 0.5, 0.42), 2.6)
		else:
			mat = Fx.glow_material(Color(c.r, c.g, c.b, 0.3), 1.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[p_element] = mat
	return _materials[p_element]


static func flame_particle_material() -> StandardMaterial3D:
	if not _materials.has("_flame_particle"):
		var mat := Fx.glow_material(Color(1.0, 0.6, 0.2), 3.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
		_materials["_flame_particle"] = mat
	return _materials["_flame_particle"]


func center() -> Vector3:
	if shape == "strip":
		return (a + b) * 0.5
	return global_position


func contains(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	match shape:
		"band":
			var d := p.distance_to(Vector2(global_position.x, global_position.z))
			return d >= inner and d <= radius
		"strip":
			return Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(p) <= half_width
		_:
			return p.distance_to(Vector2(global_position.x, global_position.z)) <= radius


func is_hostile_to(w: Wizard) -> bool:
	return w != owner_wizard and (dps > 0.0 or chill or slow > 0.0)


func _physics_process(delta: float) -> void:
	_age += delta
	if attach != null:
		if not is_instance_valid(attach) or not attach.alive or (authority and not attach.has_shield(element)):
			_expire()
			return
		global_position = Vector3(attach.global_position.x, 0.0, attach.global_position.z)
	duration -= delta
	if duration <= 0.0:
		_expire()
		return
	if _mesh != null and element == "fire":
		_mesh.scale.x = (1.0 if shape != "band" else 1.0) + sin(_age * 17.0) * 0.02
	if not authority or arena == null or not is_instance_valid(arena):
		return
	_tick += delta
	while _tick >= TICK:
		_tick -= TICK
		_apply_tick()


func _apply_tick() -> void:
	for w: Wizard in arena.wizards:
		if not is_instance_valid(w) or not w.alive or not is_hostile_to(w):
			continue
		if not contains(w.global_position):
			continue
		if dps > 0.0:
			w.take_damage(dps * TICK, element, center(), 0.0, true, {
				"attacker": owner_wizard, "direct": false, "quiet": true, "burn": burn,
				"chill_time": 0.0, "can_freeze": false, "jolt": 0.0, "stagger": 0.0, "mana_burn": 0.0})
		if chill:
			w.apply_chill(Wizard.CHILL_SLOW, Wizard.CHILL_TIME, false)
		if slow > 0.0:
			w.apply_slow(slow, TICK + 0.1)


func _expire() -> void:
	set_physics_process(false)
	queue_free()
