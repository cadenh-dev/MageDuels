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
var homing_strength: float = 3.2
var overcast: bool = false
var spell: SpellDef
var radius: float = 0.32
var lifetime: float = 5.0
var stats: Dictionary = {}

var _dead := false
var _hit: Array[Wizard] = []
var _spin := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _trail: CPUParticles3D
var _near_missed := false

## Shared by every projectile of the same color: no material churn per cast.
static var _core_materials: Dictionary = {}
static var _halo_materials: Dictionary = {}
static var _trail_materials: Dictionary = {}


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
	homing_strength = float(p.get("homing_strength", 3.2))
	overcast = bool(p.get("overcast", false))
	spell = p.get("spell")
	radius = float(p.get("radius", 0.32))
	stats = p.get("stats", {})
	lifetime = float(p.get("lifetime", 5.0))

	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false

	_cache_scene()
	_apply_visuals()


func _cache_scene() -> void:
	_core = get_node_or_null("Core") as MeshInstance3D
	_halo = get_node_or_null("Halo") as MeshInstance3D
	_trail = get_node_or_null("Trail") as CPUParticles3D


func _apply_visuals() -> void:
	var scale_factor := radius / 0.32
	if _core != null:
		_core.scale = Vector3.ONE * scale_factor
		_core.material_override = _core_material(color)
	if _halo != null:
		_halo.scale = Vector3.ONE * scale_factor
		_halo.material_override = _halo_material(color)
	if _trail != null:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(color.r, color.g, color.b, 0.7))
		ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
		_trail.color_ramp = ramp
		_trail.material_override = _trail_material(color)


func _ready() -> void:
	if _trail != null:
		_trail.emitting = true


static func _core_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _core_materials.has(key):
		_core_materials[key] = Fx.glow_material(c, 4.0)
	return _core_materials[key]


static func _halo_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _halo_materials.has(key):
		var mat := Fx.glow_material(Color(c.r, c.g, c.b, 0.14), 2.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_materials[key] = mat
	return _halo_materials[key]


static func _trail_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _trail_materials.has(key):
		var mat := Fx.glow_material(c, 2.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		_trail_materials[key] = mat
	return _trail_materials[key]


func _physics_process(delta: float) -> void:
	if _dead:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_dissipate()
		return

	if homing and is_instance_valid(target) and target.is_alive():
		var desired := (target.global_position + Vector3.UP * 0.9 - global_position).normalized()
		var turn := clampf(homing_strength * delta, 0.0, 1.0)
		direction = direction.slerp(desired, turn).normalized()

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

	if target != null and is_instance_valid(target) and not _near_missed:
		var d := global_position.distance_to(target.global_position + Vector3.UP * 1.0)
		if d < 1.55:
			_near_missed = true
			if arena != null and is_instance_valid(arena):
				arena.near_miss.emit(target, global_position)


func _impact(at: Vector3) -> void:
	if _dead:
		return
	_dead = true
	if arena != null and is_instance_valid(arena):
		Fx.burst(arena.effects, at, color, 20, 7.0, 0.1, 0.5)
		arena.impact(at, color, 0.55)
	queue_free()


func _dissipate() -> void:
	if _dead:
		return
	_dead = true
	if arena != null and is_instance_valid(arena):
		Fx.burst(arena.effects, global_position, color, 6, 2.0, 0.06, 0.3)
	queue_free()
