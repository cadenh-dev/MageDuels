class_name SpellWall
extends StaticBody3D

## Temporary elemental barrier. Blocks projectiles and beams.

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

	var box := BoxShape3D.new()
	box.size = p_size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0, p_size.y * 0.5, 0)
	add_child(shape)

	var mesh := BoxMesh.new()
	mesh.size = p_size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, p_size.y * 0.5, 0)

	_mat = Fx.glow_material(Color(color.r, color.g, color.b, 0.36), 1.6)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# Edge trim makes the barrier readable from the arena camera.
	for x in [-1.0, 1.0]:
		var trim := MeshInstance3D.new()
		var trim_mesh := BoxMesh.new()
		trim_mesh.size = Vector3(0.12, p_size.y, p_size.z + 0.08)
		trim.mesh = trim_mesh
		trim.material_override = Fx.glow_material(color, 4.0)
		trim.position = Vector3(x * p_size.x * 0.5, p_size.y * 0.5, 0)
		trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(trim)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.1
	light.omni_range = 4.0
	light.position = Vector3(0, 1.2, 0)
	add_child(light)


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
