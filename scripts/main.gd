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

const STALL_MS := 20000
const CastTimingScript := preload("res://scripts/debug/cast_timing.gd")
const FpsTestScript := preload("res://scripts/debug/fps_test.gd")
var _last_action_ms := 0
var _pad_aim := Vector2.RIGHT
var _chant_wheel_open := false
var _chant_wheel_slot := 0
var online_match: OnlineMatch
var menu_notice := ""


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
	NetSession.lobby_ready.connect(_online_ready)
	NetSession.disconnected.connect(_online_disconnected)
	for arg_i in args.size():
		if args[arg_i] == "--cast-mode" and arg_i + 1 < args.size():
			Game.cast_mode = Game.CAST_CLASSIC if str(args[arg_i + 1]).to_lower() == Game.CAST_CLASSIC else Game.CAST_CHANT
	if "--net-test" in args:
		var net_test: Node = load("res://scripts/debug/net_test.gd").new()
		add_child(net_test)
		return
	if "--gdsync-probe" in args:
		await _run_gdsync_probe()
		return
	if "--gdsync-duel-host" in args or "--gdsync-duel-join" in args:
		await _run_gdsync_duel("--gdsync-duel-host" in args)
		return
	if "--net-host" in args or "--net-join" in args:
		await _boot()
		show_online()
		if "--net-host" in args:
			var idx := args.find("--net-host")
			var port := ENetTransport.DEFAULT_PORT
			if idx + 1 < args.size() and args[idx + 1].is_valid_int():
				port = int(args[idx + 1])
			NetSession.host({"port": port, "host_name": Game.player_name, "cast_mode": Game.cast_mode})
		else:
			var idx := args.find("--net-join")
			if idx + 1 < args.size():
				NetSession.join(args[idx + 1])
		return
	if "--audio-selftest" in args or "--voice-selftest" in args:
		Audio.prepare()
		await Audio.run_selftest()
		return
	if "--profile" in args:
		await _profile()
		return
	if "--smoke" in args:
		await _smoke_test()
		return
	if "--flow" in args:
		var flow := FlowTest.new()
		add_child(flow)
		var flow_code: int = await flow.run(self)
		get_tree().quit(flow_code)
		return
	if "--lifetime" in args:
		var life := LifetimeTest.new()
		add_child(life)
		var life_code: int = await life.run(self)
		get_tree().quit(life_code)
		return
	if "--ai" in args:
		var ai_test := AITest.new()
		add_child(ai_test)
		var ai_code: int = await ai_test.run(self)
		get_tree().quit(ai_code)
		return
	if "--balance" in args:
		var balance := BalanceTest.new()
		add_child(balance)
		get_tree().quit(balance.run())
		return
	if "--input" in args:
		var input_test := InputTest.new()
		add_child(input_test)
		var input_code: int = await input_test.run(self)
		get_tree().quit(input_code)
		return
	if "--cast-timing" in args or "--cast-timing-all" in args:
		var timing := CastTimingScript.new()
		add_child(timing)
		var timing_code: int = await timing.run(self, "--cast-timing-all" in args)
		get_tree().quit(timing_code)
		return
	if "--fps" in args:
		var fps_test := FpsTestScript.new()
		add_child(fps_test)
		var fps_code: int = await fps_test.run(self)
		get_tree().quit(fps_code)
		return
	if "--test" in args:
		var tester := CombatTest.new()
		add_child(tester)
		var code: int = await tester.run()
		get_tree().quit(code)
		return
	for mode in ["--shot-menu", "--shot-wand", "--shot-craft", "--shot-duel", "--shot-chant", "--shot-assist", "--shot-shield", "--shot-draft", "--shot-boot", "--shot-result", "--shot-preview"]:
		if mode in args:
			await _debug_shot(mode)
			return

	await _boot()
	show_menu()


func _boot(skip_warmup: bool = false) -> void:
	var loading := LoadingScreen.new()
	screens.add_child(loading)
	# Let the loading screen reach the screen before the blocking audio bake.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

	Audio.prepare()

	if not skip_warmup:
		var warm := SpellWarmup.new()
		add_child(warm)
		await warm.run(world)
		warm.queue_free()

	loading.queue_free()
	await get_tree().process_frame


func _profile() -> void:
	Game.cast_mode = Game.CAST_CLASSIC
	var boot_t0 := Time.get_ticks_usec()
	await _boot("--no-warmup" in OS.get_cmdline_user_args())
	print("PROFILE boot_ms=%.1f" % (float(Time.get_ticks_usec() - boot_t0) / 1000.0))
	Game.start_arena()
	var t0 := Time.get_ticks_usec()
	_build_duel()
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	player.input_enabled = true
	ai.active = false
	duel_active = true
	round_running = true

	# Measure the real Arena spellbook, not a synthetic list: a stale mix here
	# previously missed the two slots players reported as first-use hitches.
	player.page = 0
	player.selected_slot = 0
	player.input_enabled = true
	await _wait(0.5)

	print("PROFILE build_ms=%.1f" % build_ms)
	var worst := 0.0
	for page in 2:
		player.page = page
		for slot in 4:
			player.mana = player.max_mana
			var last := Time.get_ticks_usec()
			player.quickcast(slot)
			var page_worst := 0.0
			for i in 24:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				page_worst = maxf(page_worst, float(now - last) / 1000.0)
				last = now
			var spell: SpellDef = player.pages[page][slot]
			var label := spell.display_name() if spell != null else "?"
			worst = maxf(worst, page_worst)
			print("PROFILE page=%d slot=%d %s max_frame=%.1fms" % [page, slot, label, page_worst])
	print("PROFILE worst_frame=%.1fms" % worst)
	get_tree().quit(0)


# --------------------------------------------------------------------------
# Screens
# --------------------------------------------------------------------------

func _swap_screen(screen: Control) -> void:
	_clear_screen()
	current_screen = screen
	screens.add_child(screen)


func _clear_screen() -> void:
	if current_screen != null and is_instance_valid(current_screen):
		screens.remove_child(current_screen)
		current_screen.queue_free()
	current_screen = null


func show_menu() -> void:
	_reset_pause()
	_clear_duel()
	var menu := MenuScreen.new()
	menu.notice = menu_notice
	menu_notice = ""
	menu.online_pressed.connect(show_online)
	menu.play_pressed.connect(_on_play_pressed)
	menu.how_pressed.connect(menu.show_how)
	menu.quit_pressed.connect(func() -> void: get_tree().quit())
	_swap_screen(menu)


func show_online() -> void:
	_reset_pause()
	_clear_duel()
	var screen := OnlineScreen.new()
	screen.cancel_pressed.connect(show_menu)
	_swap_screen(screen)


func _online_ready() -> void:
	_clear_screen()
	_clear_duel()
	Game.mode = "online"
	Game.input_mode = "kb"
	online_match = OnlineMatch.new()
	add_child(online_match)
	online_match.finished.connect(_online_finished)
	online_match.setup(NetSession)


func _online_finished(reason: String) -> void:
	if is_instance_valid(online_match):
		online_match.queue_free()
	online_match = null
	Game.mode = "ai"
	menu_notice = reason
	show_menu()


func _online_disconnected(reason: String) -> void:
	# A match handles its own teardown; pre-match failures return here directly.
	if not is_instance_valid(online_match):
		menu_notice = reason
		show_menu()

func _run_gdsync_probe() -> void:
	var started := Time.get_ticks_msec()
	var stage := "connect"
	var outcome := {"value": ""}
	GDSync.connected.connect(func() -> void: outcome["value"] = "connected", CONNECT_ONE_SHOT)
	GDSync.connection_failed.connect(func(error: int) -> void: outcome["value"] = "connection_failed:%d" % error, CONNECT_ONE_SHOT)
	GDSync.start_multiplayer()
	if not await _wait_probe(func() -> bool: return not str(outcome["value"]).is_empty(), 20000):
		GDSync.stop_multiplayer()
		print("GDSYNC PROBE FAIL: connection timed out")
		get_tree().quit(1)
		return
	if outcome["value"] != "connected":
		GDSync.stop_multiplayer()
		print("GDSYNC PROBE FAIL: %s" % outcome)
		get_tree().quit(1)
		return
	var code := "SC" + str(Time.get_ticks_msec() % 100000).pad_zeros(5)
	outcome["value"] = ""
	stage = "private lobby create/join"
	GDSync.lobby_created.connect(func(name: String) -> void:
		if name == code:
			GDSync.lobby_join(name)
	, CONNECT_ONE_SHOT)
	GDSync.lobby_creation_failed.connect(func(_name: String, error: int) -> void: outcome["value"] = "create_failed:%d" % error, CONNECT_ONE_SHOT)
	GDSync.lobby_joined.connect(func(name: String) -> void:
		if name == code:
			outcome["value"] = "joined"
	, CONNECT_ONE_SHOT)
	GDSync.lobby_join_failed.connect(func(_name: String, error: int) -> void: outcome["value"] = "join_failed:%d" % error, CONNECT_ONE_SHOT)
	GDSync.lobby_create(code, "", false, 2, {"protocol": OnlineSession.PROTOCOL, "state": "waiting"})
	if not await _wait_probe(func() -> bool: return not str(outcome["value"]).is_empty(), 15000) or outcome["value"] != "joined":
		GDSync.stop_multiplayer()
		print("GDSYNC PROBE FAIL: %s (%s)" % [stage, outcome["value"] if not str(outcome["value"]).is_empty() else "timed out"])
		get_tree().quit(1)
		return
	stage = "public lobby listing"
	outcome["value"] = ""
	GDSync.lobbies_received.connect(func(_lobbies: Array) -> void: outcome["value"] = "listed", CONNECT_ONE_SHOT)
	GDSync.get_public_lobbies()
	if not await _wait_probe(func() -> bool: return outcome["value"] == "listed", 10000):
		GDSync.lobby_leave()
		GDSync.stop_multiplayer()
		print("GDSYNC PROBE FAIL: %s timed out" % stage)
		get_tree().quit(1)
		return
	GDSync.lobby_leave()
	GDSync.stop_multiplayer()
	print("GDSYNC PROBE PASS: connected, private lobby create/join, public listing, leave/disconnect; %d ms" % (Time.get_ticks_msec() - started))
	get_tree().quit(0)

func _run_gdsync_duel(hosting: bool) -> void:
	await _boot()
	NetSession.prepare_online()
	var code_path := "user://gdsync_duel_code.txt"
	if hosting:
		NetSession.host({"public": false, "host_name": Game.player_name, "cast_mode": Game.cast_mode})
		var deadline := Time.get_ticks_msec() + 20000
		while NetSession.room_code.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if NetSession.room_code.is_empty():
			print("GDSYNC DUEL FAIL: host did not create a lobby")
			get_tree().quit(1)
			return
		var code_file := FileAccess.open(code_path, FileAccess.WRITE)
		if code_file == null:
			print("GDSYNC DUEL FAIL: could not publish the local lobby code")
			get_tree().quit(1)
			return
		code_file.store_string(NetSession.room_code)
		code_file.close()
	else:
		var deadline := Time.get_ticks_msec() + 20000
		var code := ""
		while code.is_empty() and Time.get_ticks_msec() < deadline:
			if FileAccess.file_exists(code_path):
				var code_file := FileAccess.open(code_path, FileAccess.READ)
				if code_file != null:
					code = code_file.get_as_text().strip_edges()
			await get_tree().create_timer(0.25).timeout
		if code.is_empty():
			print("GDSYNC DUEL FAIL: no host lobby code arrived")
			get_tree().quit(1)
			return
		NetSession.join(code, Game.player_name)
	var connected := await _wait_probe(func() -> bool: return is_instance_valid(online_match) and online_match.phase == "duel", 30000)
	if not connected:
		var failed_transport := NetSession.transport as GDSyncTransport
		print("GDSYNC DUEL FAIL: match did not start; state=%d host=%s lobby=%s peers=%d sent=%d received=%d" % [NetSession.state, NetSession.is_host(), failed_transport._in_lobby, failed_transport.peer_join_events, failed_transport.bytes_sent, failed_transport.bytes_received])
		NetSession.leave()
		get_tree().quit(1)
		return
	online_match.controls = false
	var transport := NetSession.transport as GDSyncTransport
	var sent_start := transport.bytes_sent
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 6000 and is_instance_valid(online_match):
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		var move := Vector2(0.4 if elapsed < 3.0 else -0.4, 0.0)
		var opponent := online_match.wizards[1 - online_match.local_index].global_position
		online_match.set_input(move, opponent)
		await get_tree().create_timer(0.033).timeout
	if hosting and is_instance_valid(online_match) and online_match.phase == "duel":
		online_match.wizards[1].take_damage(99999.0, "arcane", Vector3.ZERO, 0.0, false)
	await get_tree().create_timer(1.0).timeout
	var elapsed_ms := maxi(1, Time.get_ticks_msec() - started)
	var sent := transport.bytes_sent - sent_start
	print("GDSYNC DUEL %s: sent=%d B (%.1f B/s), received=%d B, RTT=%d ms, phase=%s, duration=%.1f s" % ["HOST" if hosting else "JOIN", sent, float(sent) * 1000.0 / elapsed_ms, transport.bytes_received, NetSession.rtt_ms, online_match.phase if is_instance_valid(online_match) else "ended", float(elapsed_ms) / 1000.0])
	NetSession.leave()
	if FileAccess.file_exists(code_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(code_path))
	get_tree().quit(0)

func _wait_probe(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(condition.call())


func _on_play_pressed() -> void:
	start_match()


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
	_clear_screen()
	_clear_duel()
	Game.start_arena()
	start_round()


func start_round() -> void:
	_clear_screen()
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
	Game.ensure_loadouts()
	var player_pages_now: Array = Game.player_loadout.get("pages", [])
	var enemy_pages_now: Array = Game.enemy_loadout.get("pages", [])
	Game.player_pages = player_pages_now
	Game.enemy_pages = enemy_pages_now

	arena = Arena.new()
	world.add_child(arena)
	arena.build(Game.arena_element)

	player = Wizard.new()
	player.setup("YOU", Game.loadout_kit(Game.player_loadout), player_pages_now, true)
	arena.add_wizard(player)
	player.global_position = arena.spawn_position(0)

	enemy = Wizard.new()
	enemy.setup("RIVAL", Game.loadout_kit(Game.enemy_loadout), enemy_pages_now, false)
	arena.add_wizard(enemy)
	enemy.global_position = arena.spawn_position(1)

	# The shield bubble is hidden until the first Aegis. Show it for a few frames
	# on the real round wizards so its per-wizard material/pipeline is compiled
	# before a player can cast it.
	player.add_shield(1.0, 0.08, player.wand.get("color", Color("8fe7ff")))
	enemy.add_shield(1.0, 0.08, enemy.wand.get("color", Color("8fe7ff")))
	player._flash()
	enemy._flash()

	player.cast_fired.connect(_on_cast)
	enemy.cast_fired.connect(_on_cast)
	player.died.connect(_on_death)
	enemy.died.connect(_on_death)
	player.damaged.connect(func(_w: Wizard, _a: float) -> void: _mark_action())
	enemy.damaged.connect(func(_w: Wizard, _a: float) -> void: _mark_action())

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
	_last_action_ms = Time.get_ticks_msec()


func _clear_duel() -> void:
	_clear_chant_wheel()
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
	_mark_action()
	if arena != null and is_instance_valid(arena):
		arena.spawn_spell(caster, spell, stats, origin, direction)


func _mark_action() -> void:
	_last_action_ms = Time.get_ticks_msec()


func _resolve_stall() -> void:
	if not duel_active or not round_running or player == null or enemy == null:
		return
	if not player.is_alive() or not enemy.is_alive():
		return
	_mark_action()
	if hud != null and is_instance_valid(hud):
		hud.announce("THE ARENA STIRS", "A stall is broken.", UIKit.GOLD, 0.8)
	var victim := player
	if player.hp / player.max_hp > enemy.hp / enemy.max_hp:
		victim = enemy
	victim.take_damage(9999.0, "arcane", Vector3.ZERO, 0.0)


func _on_death(wiz: Wizard) -> void:
	if not round_running:
		return
	round_running = false
	duel_active = false
	_clear_chant_wheel()
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
		show_draft(not player_won)


func show_draft(player_lost: bool) -> void:
	_clear_duel()
	var screen := DraftScreen.new()
	screen.setup(player_lost, Game.player_loadout, Game.enemy_loadout, Game.round_index + 1)
	screen.draft_complete.connect(func() -> void:
		Game.next_round()
		start_round()
	)
	_swap_screen(screen)


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if duel_active and not is_paused and _last_action_ms > 0:
		if Time.get_ticks_msec() - _last_action_ms > STALL_MS:
			_resolve_stall()

	if not duel_active or player == null or not is_instance_valid(player) or not player.is_alive() or is_paused:
		if arena != null and is_instance_valid(arena):
			arena.set_reticle(Vector3.ZERO, Color.WHITE, false)
		return
	if arena == null or not is_instance_valid(arena) or arena.camera == null:
		return

	var color: Color = player.wand.get("color", UIKit.ACCENT)
	if Game.input_mode == "pad":
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var v := Vector2(
				Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X),
				Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y)
			)
			if v.length() > 0.25 and not _chant_wheel_open:
				_pad_aim = v.normalized()
			var point := player.global_position + Vector3(_pad_aim.x, 0.0, _pad_aim.y) * 9.0
			player.set_aim_world(point)
			arena.set_reticle(point, color, true)
			return

	var mouse := get_viewport().get_mouse_position()
	var from := arena.camera.project_ray_origin(mouse)
	var dir := arena.camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, 0.9)
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit is Vector3:
		var point: Vector3 = hit
		player.set_aim_world(point)
		arena.set_reticle(point, color, true)


func _input(event: InputEvent) -> void:
	if is_instance_valid(online_match):
		return
	if event is InputEventJoypadMotion and _chant_wheel_open:
		var motion := event as InputEventJoypadMotion
		if motion.axis == JOY_AXIS_RIGHT_X or motion.axis == JOY_AXIS_RIGHT_Y:
			var x := Input.get_joy_axis(motion.device, JOY_AXIS_RIGHT_X)
			var y := Input.get_joy_axis(motion.device, JOY_AXIS_RIGHT_Y)
			if Vector2(x, y).length() > 0.45:
				_chant_wheel_slot = (roundi(atan2(y, x) / (PI * 0.5)) + 1) % 4
				_chant_wheel_slot = posmod(_chant_wheel_slot, 4)
				if hud != null:
					hud.set_spell_wheel(true, _chant_wheel_slot)
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		Game.input_mode = "pad"
	elif event is InputEventKey or event is InputEventMouseMotion or event is InputEventMouseButton:
		Game.input_mode = "kb"


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(online_match):
		return
	if event.is_action_pressed("chant_wheel") and duel_active and not is_paused and Game.cast_mode == Game.CAST_CHANT:
		_chant_wheel_open = true
		_chant_wheel_slot = player.selected_slot if player != null else 0
		if hud != null:
			hud.set_spell_wheel(true, _chant_wheel_slot)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("chant_wheel") and _chant_wheel_open:
		var can_prepare := duel_active and round_running and not is_paused and player != null and is_instance_valid(player) and player.is_alive() and player.input_enabled
		_clear_chant_wheel()
		if can_prepare:
			player.begin_chant(_chant_wheel_slot, false, true)
		get_viewport().set_input_as_handled()
		return
	# Start remains available during CHANT_ONLY controller chants. Back is a
	# dedicated cancel button so all four face buttons remain for word entry.
	var chant_pad_pause := Game.cast_mode == Game.CAST_CHANT and event is InputEventJoypadButton
	if event.is_action_pressed("pause") and (player == null or not is_instance_valid(player) or not player.chanting or chant_pad_pause):
		if duel_active:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		return
	# Assisted overcast is hold-and-release, so catch the release before the chant
	# keyboard block below swallows it.
	if player != null and is_instance_valid(player) and player.assisted_chant and duel_active and not is_paused:
		if event.is_action_released("assist_chant"):
			player.assist_release()
			get_viewport().set_input_as_handled()
			return
	if _chant_wheel_open and event is InputEventJoypadButton and event.is_pressed() and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var any_key := event as InputEventKey
		if any_key.ctrl_pressed or any_key.meta_pressed:
			return

	if player != null and is_instance_valid(player) and player.chanting and duel_active and not is_paused:
		if event is InputEventJoypadButton and event.is_pressed():
			var face := event as InputEventJoypadButton
			if face.button_index == JOY_BUTTON_BACK and player.controller_chant:
				player.cancel_chant()
				get_viewport().set_input_as_handled()
				return
			var word_index := -1
			match face.button_index:
				JOY_BUTTON_A: word_index = 0
				JOY_BUTTON_B: word_index = 1
				JOY_BUTTON_X: word_index = 2
				JOY_BUTTON_Y: word_index = 3
			var spell := player.current_spell(player.chant_slot)
			if spell != null and word_index >= 0:
				player.controller_chant_button(word_index)
			get_viewport().set_input_as_handled()
			return
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
	if event is InputEventJoypadButton and Game.cast_mode == Game.CAST_CHANT:
		if event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
			get_viewport().set_input_as_handled()
			return

	if is_paused or not duel_active:
		return
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return

	if event.is_action_pressed("cast_1"):
		_cast_input(0)
	elif event.is_action_pressed("cast_2"):
		_cast_input(1)
	elif event.is_action_pressed("cast_3"):
		_cast_input(2)
	elif event.is_action_pressed("cast_4"):
		_cast_input(3)
	elif event.is_action_pressed("cast_mouse"):
		_cast_input(player.selected_slot)
	elif event.is_action_pressed("chant"):
		if not player.chanting:
			player.begin_chant(player.selected_slot)
	elif event.is_action_pressed("assist_chant"):
		if not player.chanting:
			player.begin_chant(player.selected_slot, true)
	elif event.is_action_pressed("cycle_next"):
		player.selected_slot = (player.selected_slot + 1) % 4
	elif event.is_action_pressed("cycle_prev"):
		player.selected_slot = (player.selected_slot + 3) % 4
	elif event.is_action_pressed("swap_page"):
		player.swap_page()
	elif event.is_action_pressed("toggle_camera"):
		if arena != null and is_instance_valid(arena):
			var following := arena.toggle_follow(player)
			if hud != null and is_instance_valid(hud):
				hud.show_message("CAMERA  ·  %s" % ("FOLLOW" if following else "ARENA"), UIKit.MUTED, 0.7)


func _cast_input(slot: int) -> void:
	if Game.cast_mode == Game.CAST_CHANT:
		player.begin_chant(slot)
	else:
		player.quickcast(slot)


func _toggle_pause() -> void:
	if not duel_active:
		return
	_clear_chant_wheel()
	is_paused = not is_paused
	get_tree().paused = is_paused
	if hud != null and is_instance_valid(hud):
		hud.set_paused(is_paused)


func _reset_pause() -> void:
	_clear_chant_wheel()
	is_paused = false
	get_tree().paused = false


func _clear_chant_wheel() -> void:
	_chant_wheel_open = false
	if hud != null and is_instance_valid(hud):
		hud.set_spell_wheel(false)


func _quit_from_pause() -> void:
	_reset_pause()
	show_menu()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


# --------------------------------------------------------------------------
# Debug harness
# --------------------------------------------------------------------------

func _smoke_test() -> void:
	Game.cast_mode = Game.CAST_CLASSIC
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
	Game.cast_mode = Game.CAST_CHANT
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
		"--shot-duel", "--shot-chant", "--shot-assist", "--shot-shield", "--shot-preview":
			_debug_shot_setup_duel()
			if mode == "--shot-chant" or mode == "--shot-preview":
				ai.active = true
				ai._chant_cooldown = 0.0
			elif mode == "--shot-assist":
				ai.active = true
				ai._chant_cooldown = 0.0
				player.begin_chant(0, false)
				var shot_spell: SpellDef = player.current_spell(0)
				if shot_spell != null:
					var compact := shot_spell.incantation_compact()
					var type_len := mini(compact.length() - 1, maxi(1, compact.length() * 2 / 3))
					for ci in type_len:
						player.chant_key(compact.substr(ci, 1))
						await _wait(0.07)
			else:
				ai.active = false
			if mode == "--shot-shield":
				player.add_shield(35.0, 3.0, Color("8fe7ff"))
		"--shot-draft":
			Game.start_arena()
			Game.player_score = 1
			Game.round_index = 1
			show_draft(true)
		"--shot-boot":
			await _boot()
			show_menu()
		"--shot-result":
			Game.player_score = 2
			Game.enemy_score = 1
			show_results()

	if mode == "--shot-preview":
		await _wait(0.45)
		await _capture_preview_animation()
		return

	await _wait(0.55)
	if mode == "--shot-duel":
		_debug_force_quickcast(enemy, 0)
		await _wait(0.1)
		_debug_force_quickcast(player, 1)
		await _wait(0.35)
	if mode == "--shot-chant":
		enemy.begin_chant(2, false)
		await _wait(1.0)
	if mode == "--shot-assist":
		await _wait(0.35)
	await _capture(mode.replace("--shot-", ""))


func _debug_shot_setup_duel() -> void:
	Game.reset_match("ai")
	Game.round_index = 1
	_build_duel()
	duel_active = true
	round_running = true
	player.input_enabled = true
	player.set_aim_world(enemy.global_position)
	enemy.set_aim_world(player.global_position)


func _debug_force_quickcast(wiz: Wizard, slot: int) -> void:
	if wiz == null or not is_instance_valid(wiz):
		return
	var check: Dictionary = wiz.can_cast(slot, false)
	if bool(check.get("ok", false)):
		wiz._do_cast(slot, false, check)


func _capture_preview_animation() -> void:
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	const FPS := 15.0
	const DURATION := 5.0
	var frame_count := int(DURATION * FPS)
	for frame_i in frame_count:
		if frame_i == 12:
			_debug_force_quickcast(enemy, 0)
		elif frame_i == 28:
			_debug_force_quickcast(player, 2)
		elif frame_i == 45 and player != null and not player.chanting:
			player.begin_chant(0, false)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("preview_%04d.png" % frame_i))
		await _wait(1.0 / FPS)
	print("SHOT: preview %d frames" % frame_count)
	get_tree().quit()


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("%s.png" % label))
	print("SHOT: %s" % label)
	get_tree().quit()
