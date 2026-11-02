class_name FlowTest
extends Node

## End-to-end match flow: round 1 -> forced kill -> round 2 -> match end -> rematch.
## Run with: godot --headless -- --flow

var _checks := 0
var _failures: Array[String] = []
var main: Node


func run(p_main: Node) -> int:
	main = p_main
	print("FLOW: start")
	Game.player_wand = "emberwood"
	Game.enemy_wand = "stormbone"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)

	main.start_match()
	if not await _until(func() -> bool: return main.duel_active, 10.0, "round 1 starts"):
		return _finish()
	_check("round index starts at 0", Game.round_index == 0, "index=%d" % Game.round_index)
	_check("score starts 0-0", Game.player_score == 0 and Game.enemy_score == 0)

	main.enemy.take_damage(9999.0, "void", main.player.global_position, 0.0)
	if not await _until(func() -> bool:
		return Game.player_score == 1 and Game.round_index == 1 and main.duel_active, 15.0, "round 2 starts"):
		return _finish()
	_check("round win recorded", Game.player_score == 1, "score=%d" % Game.player_score)
	_check("round advanced", Game.round_index == 1, "index=%d" % Game.round_index)
	_check("wizard rebuilt for round 2", main.enemy.is_alive() and main.player.is_alive())

	main.enemy.take_damage(9999.0, "void", main.player.global_position, 0.0)
	if not await _until(func() -> bool: return main.current_screen is ResultsScreen, 12.0, "results screen"):
		return _finish()
	_check("match score 2-0", Game.player_score == 2 and Game.enemy_score == 0, "%d-%d" % [Game.player_score, Game.enemy_score])
	_check("player won match", Game.player_won_match())
	_check("duel torn down", main.player == null and main.enemy == null)

	main.start_match()
	if not await _until(func() -> bool: return main.duel_active, 10.0, "rematch starts"):
		return _finish()
	_check("rematch resets score", Game.player_score == 0 and Game.enemy_score == 0, "%d-%d" % [Game.player_score, Game.enemy_score])
	_check("rematch resets round", Game.round_index == 0, "index=%d" % Game.round_index)

	return _finish()


func _until(condition: Callable, timeout: float, label: String) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if condition.call():
			return true
		await get_tree().create_timer(0.1, false).timeout
		elapsed += 0.1
	_check(label, false)
	return false


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _finish() -> int:
	print("FLOW: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("FLOW: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1
