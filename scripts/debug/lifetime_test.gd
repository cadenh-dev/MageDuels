class_name LifetimeTest
extends Node

## Rebuilds the duel ten times and checks that the world and orphan counts stay flat.
## Run with: godot --headless -- --lifetime

var _checks := 0
var _failures: Array[String] = []
var main: Node


func run(p_main: Node) -> int:
	main = p_main
	print("LIFETIME: start")
	Game.player_wand = "emberwood"
	Game.enemy_wand = "stormbone"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)
	Game.reset_match("ai")

	var base_orphans: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var base_nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	for i in 10:
		main._clear_duel()
		await _frames(2)
		_check("cycle %d: world empty" % i, main.world.get_child_count() == 0, "children=%d" % main.world.get_child_count())

		main._build_duel()
		await _frames(2)
		_check("cycle %d: one arena" % i, main.world.get_child_count() == 1, "children=%d" % main.world.get_child_count())
		_check("cycle %d: duel wired" % i, main.player != null and main.enemy != null and main.hud != null and main.ai != null)

	main._clear_duel()
	await _frames(4)
	_check("final world empty", main.world.get_child_count() == 0, "children=%d" % main.world.get_child_count())
	_check("main sheds duel nodes", main.get_child_count() <= 3, "children=%d (world, screens, test)" % main.get_child_count())

	var orphans: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("LIFETIME: orphans %.0f -> %.0f, nodes %.0f -> %.0f" % [base_orphans, orphans, base_nodes, nodes])
	_check("orphan count stays flat", orphans <= base_orphans + 12.0, "orphans=%.0f" % orphans)

	print("LIFETIME: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("LIFETIME: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)
