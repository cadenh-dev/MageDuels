class_name FlowTest
extends Node

## Arena 2.0 end-to-end: round 1 -> draft -> round 2 -> draft -> round 3 -> results -> rematch.
## Run with: godot --headless -- --flow

var _checks := 0
var _failures: Array[String] = []
var main: Node


func run(p_main: Node) -> int:
	main = p_main
	print("FLOW: start Arena 2.0")
	Game.player_wand = "apprentice"
	Game.enemy_wand = "apprentice"

	main.start_match()
	if not await _until(func() -> bool: return main.duel_active, 10.0, "round 1 starts"):
		return _finish()
	_check("round index starts at 0", Game.round_index == 0, "index=%d" % Game.round_index)
	_check("score starts 0-0", Game.player_score == 0 and Game.enemy_score == 0)
	_check("apprentice wand for both", Game.player_wand == "apprentice" and Game.enemy_wand == "apprentice")
	_check("loadouts initialized", Game.player_loadout.get("cards", []).is_empty() and Game.enemy_loadout.get("cards", []).is_empty())

	for round_index in 3:
		_check("round %d active" % (round_index + 1), main.duel_active)
		main.enemy.take_damage(9999.0, "void", main.player.global_position, 0.0)

		if round_index < 2:
			if not await _until(func() -> bool: return main.current_screen is DraftScreen, 12.0, "draft after round %d" % (round_index + 1)):
				return _finish()
			var draft := main.current_screen as DraftScreen
			draft.auto_pick()
			if not await _until(func() -> bool: return main.duel_active, 14.0, "round %d starts" % (round_index + 2)):
				return _finish()
			var expected := round_index + 1
			_check("player drafted a card", Game.player_loadout.get("cards", []).size() == expected, "cards=%d" % Game.player_loadout.get("cards", []).size())
			_check("rival drafted a card", Game.enemy_loadout.get("cards", []).size() == expected, "cards=%d" % Game.enemy_loadout.get("cards", []).size())
		else:
			if not await _until(func() -> bool: return main.current_screen is ResultsScreen, 12.0, "results screen"):
				return _finish()

	_check("match score 3-0", Game.player_score == 3 and Game.enemy_score == 0, "%d-%d" % [Game.player_score, Game.enemy_score])
	_check("player won match", Game.player_won_match())
	_check("duel torn down", main.player == null and main.enemy == null)

	main.start_match()
	if not await _until(func() -> bool: return main.duel_active, 10.0, "rematch starts"):
		return _finish()
	_check("rematch resets score", Game.player_score == 0 and Game.enemy_score == 0, "%d-%d" % [Game.player_score, Game.enemy_score])
	_check("rematch resets round", Game.round_index == 0, "index=%d" % Game.round_index)
	_check("rematch resets boons", Game.player_loadout.get("cards", []).is_empty())

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
