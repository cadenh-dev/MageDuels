extends Node

## Root controller: menus, match flow, and duel input.

var world: Node3D
var screens: CanvasLayer
var arena: Arena
var player: Wizard
var enemy: Wizard
var hud: DuelHUD
var ai: AIWizard
var current_screen: Control

var duel_active := false
var round_running := false
var is_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	screens = CanvasLayer.new()
	screens.name = "Screens"
	screens.layer = 2
	add_child(screens)

	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		await _smoke_test()
		return
	if "--test" in args:
		var tester := CombatTest.new()
		add_child(tester)
		var code: int = await tester.run()
		get_tree().quit(code)
		return
	for mode in ["--shot-menu", "--shot-wand", "--shot-craft", "--shot-duel", "--shot-result"]:
		if mode in args:
			await _debug_shot(mode)
			return

	show_menu()


# --------------------------------------------------------------------------
# Screens
# --------------------------------------------------------------------------

func _swap_screen(screen: Control) -> void:
	if current_screen != null and is_instance_valid(current_screen):
		screens.remove_child(current_screen)
		current_screen.queue_free()
	current_screen = screen
	screens.add_child(screen)


func show_menu() -> void:
	_reset_pause()
	_clear_duel()
	var menu := MenuScreen.new()
	menu.play_pressed.connect(_on_play_pressed)
	menu.how_pressed.connect(menu.show_how)
	menu.quit_pressed.connect(func() -> void: get_tree().quit())
	_swap_screen(menu)


func _on_play_pressed() -> void:
	show_wand()


func show_wand() -> void:
	_reset_pause()
	_clear_duel()
	var screen := WandScreen.new()
	screen.back_pressed.connect(show_menu)
	screen.continue_pressed.connect(func() -> void: _on_wand_chosen(screen))
	_swap_screen(screen)


func _on_wand_chosen(screen: WandScreen) -> void:
	Game.player_wand = screen.selected_wand()
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_wand = _pick_enemy_wand()
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)
	show_craft()


func show_craft() -> void:
	_reset_pause()
	_clear_duel()
	var screen := CraftScreen.new()
	screen.back_pressed.connect(show_wand)
	screen.begin_pressed.connect(start_match)
	_swap_screen(screen)


func start_match() -> void:
	_reset_pause()
	_clear_duel()
	Game.reset_match("ai")
	if Game.enemy_pages.is_empty():
		Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)
	start_round()


func start_round() -> void:
	_clear_duel()
	_build_duel()
	_run_round_flow()


func show_results() -> void:
	_reset_pause()
	_clear_duel()
	var screen := ResultsScreen.new()
	screen.setup(Game.player_won_match(), Game.player_score, Game.enemy_score)
	screen.rematch_pressed.connect(start_match)
	screen.menu_pressed.connect(show_menu)
	_swap_screen(screen)


func _pick_enemy_wand() -> String:
	var options: Array[String] = []
	for wand_id in SpellData.WAND_ORDER:
		if wand_id != Game.player_wand:
			options.append(wand_id)
	return str(options[randi() % options.size()])


# --------------------------------------------------------------------------
# Duel construction
# --------------------------------------------------------------------------

func _build_duel() -> void:
	arena = Arena.new()
	world.add_child(arena)
	arena.build(Game.arena_element)

	player = Wizard.new()
	player.setup("YOU", Game.wizard_kit(Game.player_wand), Game.player_pages, true)
	arena.add_wizard(player)
	player.global_position = arena.spawn_position(0)

	enemy = Wizard.new()
	enemy.setup("RIVAL", Game.wizard_kit(Game.enemy_wand), Game.enemy_pages, false)
	arena.add_wizard(enemy)
	enemy.global_position = arena.spawn_position(1)

	player.cast_fired.connect(_on_cast)
	enemy.cast_fired.connect(_on_cast)
	player.died.connect(_on_death)
	enemy.died.connect(_on_death)

	hud = DuelHUD.new()
	hud.setup(player, enemy, arena)
	add_child(hud)
	hud.pause_resume.connect(_toggle_pause)
	hud.pause_quit.connect(_quit_from_pause)

	ai = AIWizard.new()
	add_child(ai)
	ai.setup(enemy, player, arena)
	ai.active = false

	player.set_aim_world(enemy.global_position)
	enemy.set_aim_world(player.global_position)
	player.input_enabled = false
	round_running = true
	duel_active = false


func _run_round_flow() -> void:
	await _wait(0.35)
	if not round_running:
		return
	var e: Dictionary = SpellData.ELEMENTS.get(Game.arena_element, {})
	var color: Color = e.get("color", UIKit.ACCENT)
	var element_name := str(e.get("name", ""))
	hud.announce("ROUND %d" % (Game.round_index + 1), "%s SURGE  ·  %s spells deal +15%%" % [element_name.to_upper(), element_name], color, 1.1)
	await _wait(1.5)
	if not round_running:
		return
	hud.announce("SHIFT!", "Quickcast with 1–4.  Chant to overcast.", UIKit.GOLD, 0.55)
	await _wait(0.8)
	if not round_running:
		return
	player.input_enabled = true
	ai.active = true
	duel_active = true


func _clear_duel() -> void:
	if ai != null and is_instance_valid(ai):
		ai.stop()
		ai.queue_free()
	ai = null
	duel_active = false
	round_running = false
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
	hud = null
	if arena != null and is_instance_valid(arena):
		arena.queue_free()
	arena = null
	player = null
	enemy = null


func _on_cast(caster: Wizard, spell: SpellDef, stats: Dictionary, origin: Vector3, direction: Vector3) -> void:
	if arena != null and is_instance_valid(arena):
		arena.spawn_spell(caster, spell, stats, origin, direction)


func _on_death(wiz: Wizard) -> void:
	if not round_running:
		return
	round_running = false
	duel_active = false
	if player != null and is_instance_valid(player):
		player.input_enabled = false
		player.cancel_chant()
	if ai != null and is_instance_valid(ai):
		ai.stop()

	var player_won := wiz == enemy
	Game.record_round(player_won)
	var title := "ROUND WON" if player_won else "ROUND LOST"
	var sub := "The rival falls." if player_won else "You are undone."
	hud.announce(title, sub, UIKit.GOLD if player_won else UIKit.DANGER, 1.0)

	await _wait(2.2)
	if Game.match_over():
		show_results()
	else:
		Game.next_round()
		start_round()


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not duel_active or player == null or not is_instance_valid(player) or not player.is_alive() or is_paused:
		if arena != null and is_instance_valid(arena):
			arena.set_reticle(Vector3.ZERO, Color.WHITE, false)
		return
	if arena == null or not is_instance_valid(arena) or arena.camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := arena.camera.project_ray_origin(mouse)
	var dir := arena.camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, 0.9)
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit is Vector3:
		var point: Vector3 = hit
		player.set_aim_world(point)
		var color: Color = player.wand.get("color", UIKit.ACCENT)
		arena.set_reticle(point, color, true)


func _unhandled_input(event: InputEvent) -> void:
	if player != null and is_instance_valid(player) and player.chanting and duel_active and not is_paused:
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo:
				match key.keycode:
					KEY_ENTER, KEY_KP_ENTER:
						player.chant_finish()
					KEY_ESCAPE:
						player.cancel_chant()
					KEY_BACKSPACE:
						player.chant_backspace()
					_:
						var code := key.unicode
						if code >= 65 and code <= 122:
							var ch := String.chr(code).to_upper()
							if ch >= "A" and ch <= "Z":
								player.chant_key(ch)
				get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause"):
		if duel_active:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		return

	if is_paused or not duel_active:
		return
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return

	if event.is_action_pressed("cast_1"):
		player.quickcast(0)
	elif event.is_action_pressed("cast_2"):
		player.quickcast(1)
	elif event.is_action_pressed("cast_3"):
		player.quickcast(2)
	elif event.is_action_pressed("cast_4"):
		player.quickcast(3)
	elif event.is_action_pressed("cast_mouse"):
		player.quickcast(player.selected_slot)
	elif event.is_action_pressed("chant"):
		if not player.chanting:
			player.begin_chant(player.selected_slot)
	elif event.is_action_pressed("swap_page"):
		player.swap_page()


func _toggle_pause() -> void:
	if not duel_active:
		return
	is_paused = not is_paused
	get_tree().paused = is_paused
	if hud != null and is_instance_valid(hud):
		hud.set_paused(is_paused)


func _reset_pause() -> void:
	is_paused = false
	get_tree().paused = false


func _quit_from_pause() -> void:
	_reset_pause()
	show_menu()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


# --------------------------------------------------------------------------
# Debug harness
# --------------------------------------------------------------------------

func _smoke_test() -> void:
	print("SMOKE: building duel")
	Game.player_wand = "emberwood"
	Game.enemy_wand = "stormbone"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)
	Game.reset_match("ai")
	_build_duel()
	player.input_enabled = true
	await _wait(0.4)
	var before := enemy.hp
	var ok := player.quickcast(0)
	print("SMOKE: cast ok=%s" % ok)
	await _wait(1.2)
	print("SMOKE: enemy hp before=%s after=%s" % [before, enemy.hp])
	print("SMOKE: arena element=%s projectiles=%s" % [Game.arena_element, arena.projectiles.get_child_count()])
	var passed := enemy.hp < before
	print("SMOKE: %s" % ("PASS" if passed else "FAIL"))
	get_tree().quit(0 if passed else 1)


func _debug_shot(mode: String) -> void:
	Game.player_wand = "emberwood"
	Game.enemy_wand = "frostglass"
	Game.player_pages = SpellData.default_pages(Game.player_wand)
	Game.enemy_pages = SpellData.default_pages(Game.enemy_wand)

	match mode:
		"--shot-menu":
			show_menu()
		"--shot-wand":
			show_wand()
		"--shot-craft":
			show_craft()
		"--shot-duel":
			Game.reset_match("ai")
			_build_duel()
			player.input_enabled = true
			ai.active = false
		"--shot-result":
			Game.player_score = 2
			Game.enemy_score = 1
			show_results()

	await _wait(0.55)
	if mode == "--shot-duel" and player != null:
		player.set_aim_world(enemy.global_position)
		player.quickcast(0)
		await _wait(0.22)
	await _capture(mode.replace("--shot-", ""))


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("%s.png" % label))
	print("SHOT: %s" % label)
	get_tree().quit()
