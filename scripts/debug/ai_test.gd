class_name AITest
extends Node

## Verifies the rival's telegraph: it chants visibly, completes honestly, and can be interrupted.
## Run with: godot --headless -- --ai

var _checks := 0
var _failures: Array[String] = []
var main: Node


func run(p_main: Node) -> int:
	main = p_main
	print("AI: start")
	Game.player_wand = "emberwood"
	Game.enemy_wand = "frostglass"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)
	Game.reset_match("ai")
	main._build_duel()
	main.ai.active = true
	main.ai._chant_cooldown = 0.0
	main.player.max_hp = 9999.0
	main.player.hp = 9999.0
	main.round_running = true
	main.duel_active = true

	_check("archetype title", main.ai.rival_title == "EVERFROST ZONER", main.ai.rival_title)

	if not await _until(func() -> bool: return main.enemy.chanting, 12.0, "rival starts a chant"):
		return _finish()
	_check("chant roots the rival", main.enemy.velocity.length() < 0.5, "vel=%.2f" % main.enemy.velocity.length())

	var completed := await _until(func() -> bool: return not main.enemy.chanting, 7.0, "rival completes or drops chant")
	_check("chant resolves", completed)
	_check("recovery window opens", main.ai.state == AIWizard.State.RECOVER or main.ai.state == AIWizard.State.MOVE, "state=%d" % main.ai.state)

	# Force a second chant and break it with direct damage.
	main.ai._chant_cooldown = 0.0
	main.ai.state = AIWizard.State.MOVE
	if not await _until(func() -> bool: return main.enemy.chanting, 10.0, "rival starts a second chant"):
		return _finish()
	await get_tree().create_timer(0.25, false).timeout
	main.enemy.take_damage(1.0, "void", main.player.global_position, 0.0)
	_check("chip damage does not break chant", main.enemy.chanting)
	main.enemy.take_damage(12.0, "void", main.player.global_position, 0.0)
	_check("direct hit interrupts rival", not main.enemy.chanting)
	await get_tree().create_timer(0.15, false).timeout
	_check("rival leaves the chant state", main.ai.state != AIWizard.State.WINDUP and main.ai.state != AIWizard.State.TYPING, "state=%d" % main.ai.state)

	# Let it move again and land at least one spell on the stationary caster.
	main.ai._chant_cooldown = 4.0
	var hurt := await _until(func() -> bool: return main.player.hp < main.player.max_hp, 14.0, "rival lands a spell")
	_check("rival can still deal damage", hurt)

	print("AI: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("AI: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1


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
	print("AI: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("AI: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1
