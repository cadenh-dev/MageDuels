class_name SpellWall
extends StaticBody3D

## Temporary elemental barrier. Blocks projectiles and beams.

static var _materials: Dictionary = {}

var duration: float = 7.0
var color: Color = Color.WHITE
var _max_duration: float = 7.0
var _mat: StandardMaterial3D
var _fading := false


func setup(p_color: Color, p_duration: float = 7.0, p_size: Vector3 = Vector3(2.4, 2.6, 0.45)) -> void:
	color = p_color
	duration = p_duration
	_max_duration = p_duration

	collision_layer = 1
	collision_mask = 0
	if not p_size.is_equal_approx(Vector3(2.4, 2.6, 0.45)):
		scale = Vector3(p_size.x / 2.4, p_size.y / 2.6, p_size.z / 0.45)

	var mesh_node := get_node_or_null("Mesh") as MeshInstance3D
	_mat = _wall_material(color)
	if mesh_node != null:
		mesh_node.material_override = _mat
	for path in ["TrimLeft", "TrimRight"]:
		var trim := get_node_or_null(path) as MeshInstance3D
		if trim != null:
			trim.material_override = Fx.glow_material(color, 4.0)


func _process(delta: float) -> void:
	duration -= delta
	if duration <= 0.0:
		Fx.burst(get_parent(), global_position + Vector3.UP * 1.0, color, 14, 4.0, 0.08, 0.4)
		queue_free()
		return
	if duration < 1.4 and not _fading:
		_fading = true
		var tween := create_tween()
		tween.tween_property(_mat, "albedo_color:a", 0.0, 1.4)


## Keep one template per color so the transparent/cull-disabled shader program
## survives between walls; duplicate per wall so each fades independently.
static func _wall_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _materials.has(key):
		var mat := Fx.glow_material(Color(c.r, c.g, c.b, 0.36), 1.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = mat
	var out: StandardMaterial3D = _materials[key].duplicate()
	return out
