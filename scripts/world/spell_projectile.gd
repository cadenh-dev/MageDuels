class_name SpellProjectile
extends Area3D

## A single travelling spell. Arena owns the balance resolution.

var arena: Node
var caster: Wizard
var target: Wizard
var direction: Vector3 = Vector3.FORWARD
var speed: float = 16.0
var damage: float = 10.0
var mana_cost: float = 0.0
var element: String = "fire"
var color: Color = Color.WHITE
var knockback: float = 1.5
var pierce: int = 0
var homing: bool = false
var overcast: bool = false
var spell: SpellDef
var radius: float = 0.32
var lifetime: float = 5.0
var stats: Dictionary = {}

var _dead := false
var _hit: Array[Wizard] = []
var _spin := 0.0
var _trail: CPUParticles3D


func setup(p: Dictionary) -> void:
	arena = p.get("arena")
	caster = p.get("caster")
	target = p.get("target")
	direction = (p.get("direction", Vector3.FORWARD) as Vector3).normalized()
	speed = float(p.get("speed", 16.0))
	damage = float(p.get("damage", 10.0))
	element = str(p.get("element", "fire"))
	color = p.get("color", Color.WHITE)
	knockback = float(p.get("knockback", 1.5))
	pierce = int(p.get("pierce", 0))
	homing = bool(p.get("homing", false))
	overcast = bool(p.get("overcast", false))
	spell = p.get("spell")
	radius = float(p.get("radius", 0.32))
	stats = p.get("stats", {})
	lifetime = float(p.get("lifetime", 5.0))

	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false

	_build_visual()


func _build_visual() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6

	var core := MeshInstance3D.new()
	core.mesh = sphere
	core.material_override = Fx.glow_material(color, 4.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = radius * 1.5
	halo_mesh.height = radius * 3.0
	halo_mesh.radial_segments = 10
	halo_mesh.rings = 5
	halo.mesh = halo_mesh
	var halo_mat := Fx.glow_material(Color(color.r, color.g, color.b, 0.18), 2.0)
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.4
	light.omni_range = 3.6
	light.shadow_enabled = false
	add_child(light)

	var trail := CPUParticles3D.new()
	trail.amount = 30
	trail.lifetime = 0.28
	trail.local_coords = false
	trail.emitting = false
	trail.direction = Vector3.ZERO
	trail.spread = 180.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.4
	trail.scale_amount_min = 0.8
	trail.scale_amount_max = 1.8
	trail.color = Color.WHITE

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.09
	particle_mesh.height = 0.18
	particle_mesh.radial_segments = 6
	particle_mesh.rings = 3
	trail.mesh = particle_mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 0.7))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	trail.color_ramp = ramp
	var mat := Fx.glow_material(color, 2.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	trail.material_override = mat
	add_child(trail)
	_trail = trail


func _ready() -> void:
	if _trail != null:
		_trail.emitting = true


func _physics_process(delta: float) -> void:
	if _dead:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_dissipate()
		return

	if homing and is_instance_valid(target) and target.is_alive():
		var desired := (target.global_position + Vector3.UP * 0.9 - global_position).normalized()
		direction = direction.slerp(desired, clampf(3.2 * delta, 0.0, 1.0)).normalized()

	var from := global_position
	var to := from + direction * speed * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2
	var exclude: Array[RID] = []
	if caster != null and is_instance_valid(caster):
		exclude.append(caster.get_rid())
	for w in _hit:
		if is_instance_valid(w):
			exclude.append(w.get_rid())
	query.exclude = exclude
	var hit := space.intersect_ray(query)

	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var point: Vector3 = hit["position"]
		if collider is Wizard and collider != caster:
			var wiz := collider as Wizard
			arena.resolve_hit(self, wiz)
			_hit.append(wiz)
			if pierce > 0:
				pierce -= 1
				Fx.burst(arena.effects, point, color, 8, 3.0, 0.06, 0.3)
			else:
				_impact(point)
				return
		else:
			_impact(point)
			return

	global_position = to
	_spin += delta * 9.0
	rotate_y(_spin * 0.15)


func _impact(at: Vector3) -> void:
	if _dead:
		return
	_dead = true
	if arena != null and is_instance_valid(arena):
		Fx.burst(arena.effects, at, color, 20, 7.0, 0.1, 0.5)
		if arena.has_method("shake"):
			arena.shake(0.12, 0.12)
	queue_free()


func _dissipate() -> void:
	if _dead:
		return
	_dead = true
	if arena != null and is_instance_valid(arena):
		Fx.burst(arena.effects, global_position, color, 6, 2.0, 0.06, 0.3)
	queue_free()
