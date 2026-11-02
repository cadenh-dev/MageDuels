class_name Fx
extends RefCounted

## Small procedural VFX helpers. No external assets required.

static var _burst_materials: Dictionary = {}


static func standard_material(color: Color, emission_strength: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission_strength > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_strength
	return mat


static func glow_material(color: Color, strength: float = 2.5) -> StandardMaterial3D:
	var mat := standard_material(color, strength, true)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 18, speed: float = 6.0, size: float = 0.09, lifetime: float = 0.55) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.9
	p.color = Color.WHITE
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sphere := SphereMesh.new()
	sphere.radius = maxf(0.03, size * 0.7)
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	p.mesh = sphere

	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp

	var mat := _burst_material(color)
	p.material_override = mat

	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _burst_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _burst_materials.has(key):
		var mat := glow_material(color, 3.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		_burst_materials[key] = mat
	return _burst_materials[key]


static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, width: float = 0.09, duration: float = 0.18) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var length := from.distance_to(to)
	if length < 0.01:
		return

	var mesh := CylinderMesh.new()
	mesh.top_radius = width
	mesh.bottom_radius = width * 0.45
	mesh.height = length
	mesh.radial_segments = 8
	mesh.rings = 1

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = glow_material(color, 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

	var mid := (from + to) * 0.5
	mi.global_position = mid
	var dir := (to - from).normalized()
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	mi.look_at(mid + dir, up)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.scale = Vector3(1.0, 1.0, 1.0)

	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(0.05, 1.0, 0.05), duration)
	tween.tween_property(mi.material_override, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(mi.queue_free)


static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float, duration: float = 0.45) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 8

	var mi := MeshInstance3D.new()
	mi.mesh = ring
	var mat := glow_material(color, 4.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.12, pos.z)
	mi.scale = Vector3(0.4, 0.4, 0.4)

	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(mi.queue_free)


static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.font_size = 52
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color(0.02, 0.01, 0.05, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.005
	parent.add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 2.0, 0)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.2, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.8).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
