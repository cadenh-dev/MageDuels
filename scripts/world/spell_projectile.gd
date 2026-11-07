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

## Rolls along the ground (Boulder).
var low := false
## Crossed a Flame Sheet: the hit also burns.
var ignited := false
var reflected := false
## Singularity payload growth.
var absorbed := 0
## Wards already resolved for this projectile (instance ids).
var walls_done: Dictionary = {}

var _cell: Dictionary = {}
var _timer := 0.0
var _travel := 0.0
var _trail_from := Vector3.INF
var _dead := false
var _hit: Array[Wizard] = []
var _spin := 0.0
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
	lifetime = float(p.get("lifetime", stats.get("lifetime", 5.0)))
	if spell != null:
		_cell = spell.cell()
	low = bool(_cell.get("low", false))
	if p.has("cell"):
		_cell = p["cell"]

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
	core.material_override = _core_material(color)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = radius * 1.5
	halo_mesh.height = radius * 3.0
	halo_mesh.radial_segments = 10
	halo_mesh.rings = 5
	halo.mesh = halo_mesh
	halo.material_override = _halo_material(color)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	var trail := CPUParticles3D.new()
	trail.amount = 22
	trail.lifetime = 0.22
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
	trail.material_override = _trail_material(color)
	add_child(trail)
	_trail = trail


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
		_end(global_position, "expire")
		return
	if arena == null or not is_instance_valid(arena):
		return

	if homing and is_instance_valid(target) and target.is_alive():
		var desired := (target.global_position + Vector3.UP * _aim_height() - global_position)
		if low:
			desired.y = 0.0
		desired = desired.normalized()
		var turn := clampf(homing_strength * delta, 0.0, 1.0)
		direction = direction.slerp(desired, turn).normalized()

	_cell_tick(delta)
	if _dead:
		return
	if arena.projectile_hazards(self):
		return

	var from := global_position
	var to := from + direction * speed * delta
	var result: Dictionary = arena.projectile_walls(self, from, to)
	if _dead:
		return
	if bool(result.get("stop", false)):
		_end(result.get("point", from), "wall")
		return
	if bool(result.get("redirect", false)):
		global_position = result.get("point", from)
		return

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
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
			if _cell.has("collapse_radius"):
				_end(point, "hit")
				return
			arena.resolve_hit(self, wiz)
			_hit.append(wiz)
			if pierce > 0:
				pierce -= 1
				Fx.burst(arena.effects, point, color, 8, 3.0, 0.06, 0.3)
			else:
				_end(point, "hit", wiz)
				return

	global_position = to
	_travel += speed * delta
	_spin += delta * 9.0
	rotate_y(_spin * 0.15)

	if target != null and is_instance_valid(target) and not _near_missed:
		var d := global_position.distance_to(target.global_position + Vector3.UP * 1.0)
		if d < 1.55:
			_near_missed = true
			arena.near_miss.emit(target, global_position)


func _aim_height() -> float:
	return 0.45 if low else 0.9


## Per-cell behaviour while flying (host only: clients never run physics here).
func _cell_tick(delta: float) -> void:
	if _cell.has("zap_interval") and spell != null and spell.form == "orb":
		_timer += delta
		if _timer >= float(_cell["zap_interval"]):
			_timer = 0.0
			arena.orb_zap(self)
	if _cell.has("leech_interval"):
		_timer += delta
		if _timer >= float(_cell["leech_interval"]):
			_timer = 0.0
			arena.orb_leech(self)
	if _cell.has("pull_radius"):
		arena.orb_pull(self, delta)
		arena.orb_absorb(self)
	if _cell.has("trail_step"):
		var flat := Vector3(global_position.x, 0.0, global_position.z)
		if _trail_from == Vector3.INF:
			_trail_from = flat
		elif flat.distance_to(_trail_from) >= float(_cell["trail_step"]):
			arena.spawn_trail(self, _trail_from, flat)
			_trail_from = flat


## Ownership flip for Mirror Ward, Repulse: damage, drain and chain credit
## now belong to ``new_owner``.
func redirect(new_owner: Wizard, new_dir: Vector3, new_target: Wizard) -> void:
	caster = new_owner
	target = new_target
	direction = new_dir.normalized()
	_hit.clear()
	_near_missed = false
	reflected = true


func _end(at: Vector3, reason: String, victim: Wizard = null) -> void:
	if _dead:
		return
	_dead = true
	if arena != null and is_instance_valid(arena):
		if reason in ["hit", "wall", "expire"]:
			arena.projectile_end(self, at, reason, victim)
		if reason == "expire":
			Fx.burst(arena.effects, at, color, 6, 2.0, 0.06, 0.3)
		else:
			Fx.burst(arena.effects, at, color, 20, 7.0, 0.1, 0.5)
			if reason in ["hit", "wall"]:
				arena.impact(at, color, 0.55)
	queue_free()


## Destroyed without a payload (melted, consumed, absorbed).
func destroy(at: Vector3) -> void:
	_end(at, "destroyed")
