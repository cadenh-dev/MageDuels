class_name SpellWarmup
extends Node

## Renders one arena, two wizards, and every spell form/effect once in the REAL
## viewport, behind the boot loading screen. This compiles the same depth,
## transparent, MSAA, light, and particle pipelines the first duel will use.


func run(parent: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return

	var arena := Arena.new()
	parent.add_child(arena)
	arena.build("fire")

	var kit := Game.wizard_kit("apprentice")
	var pages := SpellData.apprentice_pages()
	var p := Wizard.new()
	p.setup("WARMUP", kit, pages, true)
	arena.add_wizard(p)
	p.global_position = arena.spawn_position(0)
	var e := Wizard.new()
	e.setup("WARMUP RIVAL", kit, pages, false)
	arena.add_wizard(e)
	e.global_position = arena.spawn_position(1)

	var wand := SpellData.wand("apprentice")
	var forms: Array[String] = ["bolt", "orb", "beam", "nova", "wall", "aegis"]
	var elements: Array[String] = ["fire", "frost", "storm", "earth", "arcane", "void"]
	# Every color/form material used by the real spellbook, not just a diagonal.
	for element in elements:
		for form in forms:
			var spell := SpellDef.new(element, form)
			var stats := spell.resolved_stats(wand, false)
			arena.spawn_spell(p, spell, stats, p.get_muzzle_position(), Vector3.RIGHT)

	# Ground hazards of every shape, so zone/flame pipelines compile too.
	for element in ["fire", "frost", "void"]:
		arena.spawn_zone({"owner": p, "element": element, "shape": "circle", "position": Vector3(-2, 0, 2), "radius": 1.2, "duration": 0.5})
		arena.spawn_zone({"owner": p, "element": element, "shape": "band", "position": Vector3.ZERO, "inner": 4.0, "radius": 4.8, "duration": 0.5})
		arena.spawn_zone({"owner": p, "element": element, "shape": "strip", "a": Vector3(-3, 0, -2), "b": Vector3(3, 0, -2), "half_width": 0.5, "duration": 0.5})

	# Impact/UI variants that are not part of a projectile.
	Fx.burst(arena.effects, Vector3.ZERO, Color.WHITE, 8, 3.0, 0.06, 0.3)
	Fx.damage_number(arena.effects, Vector3.ZERO, 12.0, Color.WHITE)
	# Damage numbers are Label3D at size 52 with their own glyph atlas. Warm
	# every digit so the first real hit does not rasterize a new glyph mid-duel.
	var glyphs := Label3D.new()
	glyphs.text = "0123456789"
	glyphs.font_size = 52
	glyphs.outline_size = 14
	glyphs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glyphs.no_depth_test = true
	glyphs.pixel_size = 0.005
	glyphs.position = Vector3(0, 2.2, 0)
	arena.add_child(glyphs)
	Fx.beam(arena.effects, Vector3(-2.0, 1.0, 0.0), Vector3(2.0, 1.0, 0.0), Color.WHITE)
	Fx.shockwave(arena.effects, Vector3.ZERO, Color.WHITE, 3.0)

	# Keep one tiny rendered instance of each per-cast VFX material alive after
	# this warmup arena is freed. WebGL drops the compiled program when the last
	# material using it is destroyed; wall/beam/shockwave are allocated per cast.
	_build_keepalive(parent)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	arena.queue_free()
	await get_tree().process_frame


## A handful of microscopic meshes under the floor. They are rendered during
## the warmup, then stay in the scene so the renderer keeps the compiled
## programs for materials that real spells allocate per cast.
func _build_keepalive(parent: Node3D) -> void:
	if parent == null:
		return
	var keep := Node3D.new()
	keep.name = "WarmKeepalive"
	parent.add_child(keep)

	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, 0.02)
	wall.mesh = box
	var wall_mat := Fx.glow_material(Color.WHITE, 1.6)
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall.material_override = wall_mat
	wall.position = Vector3(-0.35, -0.6, 0.0)
	keep.add_child(wall)

	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.01
	cyl.bottom_radius = 0.005
	cyl.height = 0.02
	cyl.radial_segments = 8
	beam.mesh = cyl
	var glow := Fx.glow_material(Color.WHITE, 4.0)
	beam.material_override = glow
	beam.position = Vector3(0.0, -0.6, 0.0)
	keep.add_child(beam)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.01
	torus.outer_radius = 0.02
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = glow
	ring.position = Vector3(0.35, -0.6, 0.0)
	keep.add_child(ring)

	# Ward materials (opaque stone, additive flame, glassy ice, mirror, rift)
	# and ground-zone materials are duplicated per cast; keep each program.
	var x := -0.6
	for element in ["earth", "frost", "fire", "arcane", "void", "storm"]:
		var ward := MeshInstance3D.new()
		ward.mesh = box
		ward.material_override = SpellWall._wall_material(element)
		ward.position = Vector3(x, -0.7, 0.0)
		keep.add_child(ward)
		var trim := MeshInstance3D.new()
		trim.mesh = box
		trim.material_override = SpellWall._trim_material(element, SpellData.ELEMENTS[element]["color"])
		trim.position = Vector3(x, -0.75, 0.05)
		keep.add_child(trim)
		var ground := MeshInstance3D.new()
		ground.mesh = box
		ground.material_override = SpellZone.zone_material(element)
		ground.position = Vector3(x, -0.8, 0.1)
		keep.add_child(ground)
		x += 0.2
	for element in ["earth", "void", "frost"]:
		var core := MeshInstance3D.new()
		core.mesh = box
		core.material_override = SpellProjectile._material_core(element, Color.WHITE)
		core.position = Vector3(x, -0.7, 0.2)
		keep.add_child(core)
		x += 0.2
	var flame := MeshInstance3D.new()
	flame.mesh = box
	flame.material_override = SpellZone.flame_particle_material()
	flame.position = Vector3(0.6, -0.7, 0.0)
	keep.add_child(flame)

	var label := Label3D.new()
	label.text = "0123456789"
	label.font_size = 52
	label.outline_size = 14
	label.no_depth_test = true
	label.pixel_size = 0.005
	label.modulate = Color(1, 1, 1, 0.0)
	label.position = Vector3(0.0, -0.6, 0.2)
	keep.add_child(label)
