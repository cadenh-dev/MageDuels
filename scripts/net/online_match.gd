class_name OnlineMatch
extends Node

signal finished(reason: String)
signal phase_changed
const HISTORY := 256
const INTERPOLATION_MS := 100
var session: OnlineSession
var arena: Arena
var wizards: Array[Wizard] = [] # Canonical order: host, guest. Never mirrored.
var drivers: Array[RemoteInputDriver] = []
var hud: DuelHUD
var screen: Control
var screens: CanvasLayer
var loadouts: Array = []
var scores: Array = [0, 0]
var round_index := 0
var epoch := 0
var phase := "waiting"
var element := "fire"
var offer: Array = []
var pick_turn := -1
var picks_left := 0
var votes: Array = [false, false]
var local_index := 0
var controls := true
var show_ui := true
var paused := false
var server_tick := 0
var snapshot_tick := -1
var last_event_ack := 0
var received_casts := 0
var last_cast: Dictionary = {}
var _event_seq := 0
var _remote_event_seq := 0
var _frame_seq := 0
var _timer := 0.0
var _stall := 0.0
var _local_move := Vector2.ZERO
var _local_aim := Vector3.ZERO
var _input_batch: Array = [{}, {}]
var _batch_count := 0
var _displacements := PackedVector3Array()
var _correction := Vector3.ZERO
var _snapshots: Array = []
var _entities: Dictionary = {}
var _known_entities: Dictionary = {}
var _beam_seq := 0
var _closed := false

func _ready() -> void:
	# Snapshot ACKs describe inputs already consumed by Wizard physics.
	process_physics_priority = 10

func setup(value: OnlineSession) -> void:
	session = value
	local_index = 0 if session.is_host() else 1
	session.message_received.connect(_receive)
	session.disconnected.connect(_disconnected)
	_displacements.resize(HISTORY)
	if show_ui:
		screens = CanvasLayer.new()
		screens.layer = 3
		add_child(screens)
	if not session.is_host():
		command("ready")

func _new_match() -> void:
	scores = [0, 0]
	round_index = 0
	votes = [false, false]
	loadouts = [Game.new_loadout(Game.ARENA_WAND, SpellData.apprentice_pages()), Game.new_loadout(Game.ARENA_WAND, SpellData.apprentice_pages())]
	session.begin_match()
	_start_round()

func _start_round() -> void:
	epoch += 1
	element = Game._pick_arena_element()
	phase = "loading"
	_build_round()
	_broadcast({"type": "round_start", "loadouts": [MatchState.loadout(loadouts[0]), MatchState.loadout(loadouts[1])], "scores": scores, "round": round_index, "element": element})
	phase_changed.emit()

func _build_round() -> void:
	_clear_round()
	_clear_screen()
	paused = false
	_frame_seq = 0
	_local_move = Vector2.ZERO
	_batch_count = 0
	_displacements.fill(Vector3.ZERO)
	_correction = Vector3.ZERO
	snapshot_tick = -1
	arena = Arena.new()
	arena.networked = true
	add_child(arena)
	arena.build(element)
	for i in 2:
		var w := Wizard.new()
		w.external_input = true
		w.setup("YOU" if i == local_index else session.remote_name, Game.loadout_kit(loadouts[i]), loadouts[i]["pages"], i == local_index)
		arena.add_wizard(w)
		w.global_position = arena.spawn_position(i)
		w.input_enabled = false
		wizards.append(w)
		if session.is_host():
			var driver := RemoteInputDriver.new()
			driver.wizard = w
			driver.last_event = _event_seq if i == 0 else _remote_event_seq
			add_child(driver)
			drivers.append(driver)
			w.cast_fired.connect(_cast)
			w.died.connect(_death)
			w.damaged.connect(_damaged)
		else:
			w.set_physics_process(false)
	wizards[0].set_aim_world(wizards[1].global_position)
	wizards[1].set_aim_world(wizards[0].global_position)
	_local_aim = wizards[1 - local_index].global_position
	if session.is_host():
		arena.beam_fx.connect(_beam)
	if show_ui:
		hud = DuelHUD.new()
		hud.online = true
		hud.online_round = round_index
		hud.online_scores = [scores[local_index], scores[1 - local_index]]
		hud.setup(wizards[local_index], wizards[1 - local_index], arena)
		add_child(hud)
		hud.pause_resume.connect(_toggle_pause)
		hud.pause_quit.connect(leave)

func _physics_process(delta: float) -> void:
	if _closed:
		return
	server_tick += 1
	if phase == "countdown" and session.is_host():
		_timer -= delta
		if _timer <= 0.0:
			_set_duel()
			_broadcast({"type": "fight"})
	if phase == "round_end" and session.is_host():
		_timer -= delta
		if _timer <= 0.0:
			if scores[0] >= Game.ROUNDS_TO_WIN or scores[1] >= Game.ROUNDS_TO_WIN:
				phase = "results"
				_clear_round()
				_broadcast({"type": "results", "scores": scores})
				_show_results()
			else:
				_begin_draft()
			phase_changed.emit()
	if phase == "countdown":
		_sample_frame(delta) # Prime the unreliable lane before movement is enabled.
	if phase == "duel":
		if controls:
			_sample_controls()
		_sample_frame(delta)
		if session.is_host():
			_stall += delta
			if _stall > 20.0:
				var victim := wizards[0] if wizards[0].hp / wizards[0].max_hp <= wizards[1].hp / wizards[1].max_hp else wizards[1]
				victim.take_damage(9999.0, "arcane", Vector3.ZERO, 0.0)
	if session.is_host() and not wizards.is_empty() and server_tick % 3 == 0:
		_send_snapshot()
	if not session.is_host() and not wizards.is_empty():
		_present(delta)

func _set_duel() -> void:
	phase = "duel"
	_stall = 0.0
	for w in wizards:
		w.input_enabled = true
	for driver in drivers:
		driver.active = true
	if hud != null:
		hud.announce("SHIFT!", "First to three wins", UIKit.GOLD, 0.6)
	phase_changed.emit()

func _sample_controls() -> void:
	_local_move = Vector2.ZERO
	if not paused:
		_local_move = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).limit_length()
		var mouse := get_viewport().get_mouse_position()
		var hit: Variant = Plane(Vector3.UP, 0.9).intersects_ray(arena.camera.project_ray_origin(mouse), arena.camera.project_ray_normal(mouse))
		if hit is Vector3:
			_local_aim = hit
	arena.set_reticle(_local_aim, wizards[local_index].wand.get("color", UIKit.ACCENT), not paused)

## Also used by the headless harness, through exactly the live input pipeline.
func set_input(move: Vector2, aim: Vector3) -> void:
	_local_move = move.limit_length()
	_local_aim = aim

func _sample_frame(delta: float) -> void:
	_frame_seq += 1
	var frame: Dictionary = _input_batch[_batch_count]
	frame["seq"] = _frame_seq
	frame["move"] = _local_move
	frame["aim"] = _local_aim
	frame["hold"] = controls and not paused and (Input.is_physical_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if session.is_host():
		drivers[0].frame(frame)
	else:
		var w := wizards[1]
		var displacement := Vector3.ZERO
		if not w.chanting and w.stun_time <= 0.0 and w.alive:
			displacement = Vector3(_local_move.x, 0.0, _local_move.y) * w.move_speed * (1.0 - w.slow_amount if w.slow_time > 0.0 else 1.0) * delta
		_displacements[_frame_seq % HISTORY] = displacement
		w.velocity = displacement / delta
		w.move_and_collide(displacement)
		_clamp_position(w)
		w.set_aim_world(_local_aim)
	_batch_count += 1
	if _batch_count == 2:
		if not session.is_host():
			session.send_unreliable({"type": "input", "epoch": epoch, "frames": _input_batch})
		_batch_count = 0

func command(action: String, fields: Dictionary = {}) -> void:
	_event_seq += 1
	var msg := fields.duplicate()
	msg.merge({"type": "action", "action": action, "seq": _event_seq, "epoch": epoch}, true)
	if session.is_host():
		_action(0, msg)
	else:
		if phase == "duel" and not wizards.is_empty():
			RemoteInputDriver.apply(wizards[1], msg, true)
		session.send_reliable(msg)

func _action(index: int, msg: Dictionary) -> void:
	var action := str(msg.get("action", ""))
	if action == "ready":
		if phase == "waiting" and index == 1:
			_new_match()
		elif phase == "loading" and int(msg.get("epoch", -1)) == epoch and index == 1:
			phase = "countdown"
			_timer = 1.0
			_broadcast({"type": "countdown"})
		return
	if int(msg.get("epoch", -1)) != epoch:
		return
	match action:
		"boon_pick": _pick(index, str(msg.get("id", "")))
		"rematch_vote":
			if phase == "results":
				votes[index] = true
				_broadcast({"type": "rematch", "votes": votes})
				_show_results()
				if votes[0] and votes[1]:
					_new_match()
		_:
			if phase == "duel":
				drivers[index].event(msg)

func _receive(msg: Dictionary) -> void:
	if _closed:
		return
	var kind := str(msg.get("type", ""))
	if session.is_host():
		if kind == "action":
			var seq := int(msg.get("seq", 0))
			if seq <= _remote_event_seq or seq > _remote_event_seq + 256:
				return
			_remote_event_seq = seq
			_action(1, msg)
		elif kind == "input" and phase in ["duel", "countdown"] and int(msg.get("epoch", -1)) == epoch:
			var frames: Variant = msg.get("frames")
			if frames is Array and frames.size() <= 4:
				for frame in frames:
					if frame is Dictionary:
						drivers[1].frame(frame)
		return
	if kind == "round_start":
		if int(msg.get("epoch", -1)) <= epoch:
			return
		epoch = int(msg["epoch"])
		loadouts = [MatchState.decode_loadout(msg["loadouts"][0]), MatchState.decode_loadout(msg["loadouts"][1])]
		scores = msg["scores"]
		round_index = int(msg["round"])
		element = str(msg["element"])
		phase = "loading"
		session.begin_match()
		_build_round()
		command("ready")
		phase_changed.emit()
		return
	if int(msg.get("epoch", -1)) != epoch:
		return
	match kind:
		"countdown":
			phase = "countdown"
		"fight": _set_duel()
		"snapshot": _snapshot(msg)
		"spawn": _spawn_entity(msg["entity"])
		"despawn":
			if _entities.has(msg["id"]):
				_entities[msg["id"]].queue_free()
				_entities.erase(msg["id"])
		"cast":
			received_casts += 1
			last_cast = msg
			if not wizards.is_empty():
				var w := wizards[int(msg["caster"])]
				var s: Array = msg["spell"]
				var spell := SpellDef.new(s[0], s[1], s[2])
				w.cast_fired.emit(w, spell, msg["stats"], msg["origin"], msg["dir"])
				var stats: Dictionary = msg["stats"]
				if stats.get("kind") == "nova":
					Fx.shockwave(arena.effects, w.global_position, stats["color"], float(stats["radius"]), 0.5)
		"beam":
			if arena != null:
				Fx.beam(arena.effects, msg["from"], msg["to"], msg["color"], float(msg["width"]))
		"hit":
			if not wizards.is_empty():
				var w := wizards[int(msg["wizard"])]
				w.damaged.emit(w, float(msg["amount"]))
				w._flash()
				Fx.damage_number(arena.effects, w.global_position + Vector3.UP * 1.9, float(msg["amount"]), UIKit.DANGER)
		"round_end":
			scores = msg["scores"]
			phase = "round_end"
			for w in wizards:
				w.input_enabled = false
				w.cancel_chant()
			if hud != null:
				hud.online_scores = [scores[1], scores[0]]
		"draft":
			phase = "draft"
			offer = msg["offer"]
			pick_turn = int(msg["turn"])
			_clear_round()
			_show_draft()
		"pick":
			Game.apply_card(loadouts[int(msg["player"])], msg["card"])
		"results":
			phase = "results"
			scores = msg["scores"]
			votes = [false, false]
			_clear_round()
			_show_results()
		"rematch":
			votes = msg["votes"]
			_show_results()
	phase_changed.emit()

func _broadcast(msg: Dictionary) -> void:
	msg["epoch"] = epoch
	session.send_reliable(msg)

func _cast(w: Wizard, spell: SpellDef, stats: Dictionary, origin: Vector3, direction: Vector3) -> void:
	if phase != "duel":
		return
	_stall = 0.0
	received_casts += 1
	last_cast = {"type": "cast", "caster": wizards.find(w), "spell": [spell.element, spell.form, spell.modifier], "stats": stats, "origin": origin, "dir": direction}
	_broadcast(last_cast)
	arena.spawn_spell(w, spell, stats, origin, direction)
	_collect_entities() # Reliable births also cover projectiles shorter than a snapshot interval.

func _beam(from: Vector3, to: Vector3, color: Color, width: float) -> void:
	_beam_seq += 1
	_broadcast({"type": "beam", "id": _beam_seq, "from": from, "to": to, "color": color, "width": width})

func _damaged(w: Wizard, amount: float) -> void:
	_stall = 0.0
	_broadcast({"type": "hit", "wizard": wizards.find(w), "amount": amount, "hp": w.hp})

func _death(w: Wizard) -> void:
	if phase != "duel":
		return
	phase = "round_end"
	_timer = 1.5
	var loser := wizards.find(w)
	scores[1 - loser] += 1
	pick_turn = loser
	for driver in drivers:
		driver.active = false
	for wizard in wizards:
		wizard.input_enabled = false
		wizard.cancel_chant()
	if hud != null:
		hud.online_scores = [scores[0], scores[1]]
		hud.announce("ROUND WON" if loser != local_index else "ROUND LOST", "", UIKit.GOLD, 1.0)
	_send_snapshot()
	_broadcast({"type": "round_end", "scores": scores, "loser": loser})
	phase_changed.emit()

func _begin_draft() -> void:
	phase = "draft"
	_clear_round()
	picks_left = 2
	offer = Game.draw_offer(3, loadouts[pick_turn])
	_publish_draft()

func _publish_draft() -> void:
	_broadcast({"type": "draft", "offer": offer, "turn": pick_turn})
	_show_draft()

func _pick(index: int, id: String) -> void:
	if phase != "draft" or index != pick_turn:
		return
	for card in offer:
		if str(card["id"]) != id:
			continue
		Game.apply_card(loadouts[index], card)
		_broadcast({"type": "pick", "player": index, "card": card})
		offer.erase(card)
		picks_left -= 1
		if picks_left == 0:
			round_index += 1
			_start_round()
		else:
			pick_turn = 1 - pick_turn
			_publish_draft()
		return

func _collect_entities() -> Array:
	var result: Array = []
	var live: Dictionary = {}
	for container in [arena.projectiles, arena.walls]:
		for i in container.get_child_count():
			var node := container.get_child(i) as Node3D
			if node.is_queued_for_deletion():
				continue
			var data := MatchState.entity(node)
			result.append(data)
			live[data["id"]] = true
			if not _known_entities.has(data["id"]):
				_known_entities[data["id"]] = true
				_broadcast({"type": "spawn", "entity": data})
	for id in _known_entities.keys():
		if not live.has(id):
			_known_entities.erase(id)
			_broadcast({"type": "despawn", "id": id})
	return result

func _send_snapshot() -> void:
	session.send_unreliable({"type": "snapshot", "epoch": epoch, "tick": server_tick,
		"ack": drivers[1].last_frame, "event_ack": _remote_event_seq,
		"w": [MatchState.wizard(wizards[0]), MatchState.wizard(wizards[1])], "entities": _collect_entities()})

func _snapshot(msg: Dictionary) -> void:
	if wizards.is_empty() or int(msg["tick"]) <= snapshot_tick:
		return
	snapshot_tick = int(msg["tick"])
	last_event_ack = int(msg["event_ack"])
	msg["received"] = Time.get_ticks_msec()
	_snapshots.append(msg)
	if _snapshots.size() > 16:
		_snapshots.pop_front()
	for i in 2:
		MatchState.apply(wizards[i], msg["w"][i], i == 1 and last_event_ack < _event_seq)
	var target: Vector3 = msg["w"][1]["pos"]
	var ack := int(msg["ack"])
	if _frame_seq - ack < HISTORY:
		for seq in range(ack + 1, _frame_seq + 1):
			target += _displacements[seq % HISTORY]
	var error := target - wizards[1].global_position
	if error.length() > 2.5:
		wizards[1].global_position = target
		_correction = Vector3.ZERO
	else:
		_correction = error
	var live: Dictionary = {}
	for data in msg["entities"]:
		live[data["id"]] = true
		_spawn_entity(data)
	for id in _entities.keys():
		if not live.has(id):
			var node: Node = _entities[id]
			node.queue_free()
			_entities.erase(id)

func _spawn_entity(data: Dictionary) -> void:
	if arena == null or _entities.has(data["id"]):
		return
	var node: Node3D
	if data["kind"] == "projectile":
		var p := SpellProjectile.new()
		p.setup({"color": data["color"], "radius": data["radius"], "direction": data["dir"], "speed": data["speed"]})
		node = p
		arena.projectiles.add_child(node)
		p.set_physics_process(false)
	else:
		var wall := SpellWall.new()
		wall.setup(data["color"], float(data["duration"]))
		node = wall
		arena.walls.add_child(node)
		wall.set_process(false)
	node.global_position = data["pos"]
	node.rotation = data["rot"]
	_entities[data["id"]] = node

func _present(delta: float) -> void:
	var local := wizards[1]
	var correction := _correction * minf(delta * 10.0, 1.0)
	local.move_and_collide(correction)
	_correction -= correction
	_clamp_position(local)
	if local.chanting:
		local.chant_elapsed += delta
	if not _snapshots.is_empty():
		var target := Time.get_ticks_msec() - INTERPOLATION_MS
		var a: Dictionary = _snapshots[0]
		var b: Dictionary = _snapshots[-1]
		for snap: Dictionary in _snapshots:
			if int(snap["received"]) <= target:
				a = snap
			if int(snap["received"]) >= target:
				b = snap
				break
		var t := clampf(float(target - int(a["received"])) / maxf(1.0, float(int(b["received"]) - int(a["received"]))), 0.0, 1.0)
		wizards[0].global_position = (a["w"][0]["pos"] as Vector3).lerp(b["w"][0]["pos"], t)
		wizards[0].aim_point = b["w"][0]["aim"]
		for data: Dictionary in b["entities"]:
			if not _entities.has(data["id"]):
				continue
			var node: Node3D = _entities[data["id"]]
			var from: Vector3 = data["pos"]
			for previous: Dictionary in a["entities"]:
				if previous["id"] == data["id"]:
					from = previous["pos"]
					break
			node.global_position = from.lerp(data["pos"], t)
	for w in wizards:
		w._time += delta
		if w.alive:
			w._animate(delta, w.velocity.length() > 0.01)
			w._update_facing()
		w._update_bars()

func _clamp_position(w: Wizard) -> void:
	var flat := Vector2(w.position.x, w.position.z).limit_length(Wizard.ARENA_RADIUS)
	w.position = Vector3(flat.x, 0.0, flat.y)

func _unhandled_input(event: InputEvent) -> void:
	if not controls or phase != "duel" or wizards.is_empty():
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return
	var w := wizards[local_index]
	if event is InputEventKey and (event.echo or event.ctrl_pressed or event.meta_pressed):
		return
	if event.is_action_released("assist_chant") and w.assisted_chant:
		command("unleash")
	elif event.is_action_pressed("pause") and (not w.chanting or paused):
		_toggle_pause()
	elif paused:
		return
	elif w.chanting and event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER: command("unleash")
			KEY_ESCAPE: command("chant_cancel")
			KEY_BACKSPACE: command("chant_backspace")
			_:
				var c := String.chr(event.unicode).to_upper()
				if c.length() == 1 and c >= "A" and c <= "Z":
					command("chant_char", {"c": c})
	elif not w.chanting:
		if event.is_action_pressed("cast_1"): command("prepare", {"slot": 0})
		elif event.is_action_pressed("cast_2"): command("prepare", {"slot": 1})
		elif event.is_action_pressed("cast_3"): command("prepare", {"slot": 2})
		elif event.is_action_pressed("cast_4"): command("prepare", {"slot": 3})
		elif event.is_action_pressed("cast_mouse"): command("prepare", {"slot": w.selected_slot})
		elif event.is_action_pressed("chant"): command("prepare", {"slot": w.selected_slot, "chant": true})
		elif event.is_action_pressed("assist_chant"): command("prepare", {"slot": w.selected_slot, "assist": true})
		elif event.is_action_pressed("swap_page"): command("page_swap")
		elif event.is_action_pressed("cycle_next"): w.selected_slot = (w.selected_slot + 1) % 4
		elif event.is_action_pressed("cycle_prev"): w.selected_slot = (w.selected_slot + 3) % 4
	get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	paused = not paused
	_local_move = Vector2.ZERO
	if hud != null:
		hud.set_paused(paused)

func _panel(title: String) -> VBoxContainer:
	_clear_screen()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens.add_child(screen)
	screen.add_child(Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	box.add_child(UIKit.heading(title, 44))
	return box

func _show_draft() -> void:
	if not show_ui:
		return
	var box := _panel("CHOOSE A BOON" if pick_turn == local_index else "RIVAL IS CHOOSING")
	box.add_child(UIKit.label("Loser picks first. Boons persist for the match.", 18))
	var row := HBoxContainer.new()
	box.add_child(row)
	for data in offer:
		var card := BoonCard.new()
		row.add_child(card)
		card.setup(data)
		card.disabled = pick_turn != local_index
		card.pressed.connect(func(chosen: BoonCard) -> void: command("boon_pick", {"id": chosen.data["id"]}))
	var leave_button := UIKit.ghost_button("LEAVE MATCH")
	leave_button.pressed.connect(leave)
	box.add_child(leave_button)

func _show_results() -> void:
	if not show_ui:
		return
	var box := _panel("VICTORY" if scores[local_index] >= Game.ROUNDS_TO_WIN else "DEFEAT")
	box.add_child(UIKit.heading("%d  —  %d" % [scores[local_index], scores[1 - local_index]], 40))
	var vote := UIKit.button("WAITING FOR RIVAL" if votes[local_index] else "REMATCH")
	vote.disabled = votes[local_index]
	vote.pressed.connect(func() -> void: command("rematch_vote"))
	box.add_child(vote)
	var leave_button := UIKit.ghost_button("MAIN MENU")
	leave_button.pressed.connect(leave)
	box.add_child(leave_button)

func _clear_screen() -> void:
	if is_instance_valid(screen):
		screens.remove_child(screen)
		screen.queue_free()
	screen = null

func _clear_round() -> void:
	if is_instance_valid(hud):
		remove_child(hud)
		hud.queue_free()
	hud = null
	for driver in drivers:
		remove_child(driver)
		driver.queue_free()
	drivers.clear()
	wizards.clear()
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	arena = null
	_entities.clear()
	_known_entities.clear()
	_snapshots.clear()

func leave() -> void:
	session.leave()
	_disconnected("You left the match.")

func _disconnected(reason: String) -> void:
	if _closed:
		return
	_closed = true
	phase = "menu"
	_clear_round()
	_clear_screen()
	finished.emit(reason)

func _exit_tree() -> void:
	if is_instance_valid(session):
		if session.message_received.is_connected(_receive):
			session.message_received.disconnect(_receive)
		if session.disconnected.is_connected(_disconnected):
			session.disconnected.disconnect(_disconnected)
