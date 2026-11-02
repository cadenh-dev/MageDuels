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

	# Impact/UI variants that are not part of a projectile.
	Fx.burst(arena.effects, Vector3.ZERO, Color.WHITE, 8, 3.0, 0.06, 0.3)
	Fx.damage_number(arena.effects, Vector3.ZERO, 12.0, Color.WHITE)
	Fx.beam(arena.effects, Vector3(-2.0, 1.0, 0.0), Vector3(2.0, 1.0, 0.0), Color.WHITE)
	Fx.shockwave(arena.effects, Vector3.ZERO, Color.WHITE, 3.0)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	arena.queue_free()
	await get_tree().process_frame
