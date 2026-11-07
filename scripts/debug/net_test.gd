extends Node

## End-to-end real sockets + real Wizard/Arena in independent World3Ds.
const Impaired := preload("res://scripts/debug/impaired_transport.gd")
var checks := 0
var failures: Array[String] = []
var host_session: OnlineSession
var client_session: OnlineSession
var host_match: OnlineMatch
var client_match: OnlineMatch
var _roots: Array[SubViewport] = []
var _port := 0
var _ui := false

func _ready() -> void:
	_port = 27000 + OS.get_process_id() % 12000
	Game.cast_mode = Game.CAST_CHANT
	await _mismatch()
	await _scenario(false)
	await _scenario(true)
	print("NET: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("  FAIL %s" % failure)
	print("NET: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func _sessions(impaired: bool) -> void:
	host_session = OnlineSession.new()
	client_session = OnlineSession.new()
	add_child(host_session)
	add_child(client_session)
	host_session.use_transport(Impaired.new() if impaired else ENetTransport.new())
	client_session.use_transport(Impaired.new() if impaired else ENetTransport.new())
	_port += 1

func _connect_pair() -> void:
	host_session.host({"port": _port, "host_name": "Host", "cast_mode": "chant", "public": true})
	client_session.join("127.0.0.1:%d" % _port, "Guest")

func _mismatch() -> void:
	_sessions(false)
	client_session.protocol_version = 999
	_connect_pair()
	await _until(func() -> bool: return client_session.state == OnlineSession.State.DISCONNECTED, "protocol mismatch rejects guest")
	_check("mismatch reason is explicit", "version mismatch" in client_session.status)
	await _until(func() -> bool: return host_session.state == OnlineSession.State.DISCONNECTED, "mismatch closes host lobby")
	await _cleanup()

func _make_match(value: OnlineSession) -> OnlineMatch:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	_roots.append(viewport)
	var duel := OnlineMatch.new()
	duel.controls = false
	duel.show_ui = _ui
	viewport.add_child(duel)
	duel.setup(value)
	return duel

func _scenario(impaired: bool) -> void:
	print("NET: real ENet scenario impaired=%s" % impaired)
	_ui = not impaired
	_sessions(impaired)
	host_session.lobby_ready.connect(func() -> void: host_match = _make_match(host_session))
	client_session.lobby_ready.connect(func() -> void: client_match = _make_match(client_session))
	_connect_pair()
	if not await _until(func() -> bool: return is_instance_valid(host_match) and is_instance_valid(client_match) and host_match.phase == "duel" and client_match.phase == "duel", "handshake and ready start real duel"):
		await _cleanup()
		return
	var host_wire := _wire_transport(host_session.transport)
	var client_wire := _wire_transport(client_session.transport)
	var host_bytes_at_start := host_wire.bytes_sent
	var client_bytes_at_start := client_wire.bytes_sent
	var started_at := Time.get_ticks_msec()
	_check("names and host cast mode negotiated", host_session.remote_name == "Guest" and client_session.remote_name == "Host" and client_session.cast_mode == "chant")
	_check("online has no AI nodes", host_match.drivers.size() == 2 and client_match.drivers.is_empty())
	if _ui:
		_check("both HUDs show their own wizard as YOU", host_match.hud.player == host_match.wizards[0] and client_match.hud.player == client_match.wizards[1] and client_match.hud.player.wizard_name == "YOU")
		_check("coach is off online", host_match.hud._coach == null and client_match.hud._coach == null)
	var lobbies := await host_session.transport.list_public_lobbies()
	_check("public listing carries lobby metadata", lobbies.size() == 1 and lobbies[0]["players"] == 2 and lobbies[0]["cast_mode"] == "chant")
	await _until(func() -> bool: return client_session.rtt_ms > 0, "RTT measured")
	var start := host_match.wizards[1].position
	client_match.set_input(Vector2(0, 1), Vector3(-6, 0, 0))
	await _wait(0.5)
	client_match.set_input(Vector2.ZERO, Vector3(-6, 0, 0))
	await _wait(0.7)
	_check("client movement reaches real host wizard", host_match.wizards[1].position.distance_to(start) > 1.0)
	_check("client prediction converges to host", host_match.wizards[1].position.distance_to(client_match.wizards[1].position) < 0.3)
	host_match.set_input(Vector2(0, -1), host_match.wizards[1].position)
	await _wait(0.5)
	host_match.set_input(Vector2.ZERO, host_match.wizards[1].position)
	await _wait(0.6)
	_check("snapshots interpolate host wizard on client", host_match.wizards[0].position.distance_to(client_match.wizards[0].position) < 0.15 and client_match.wizards[0].position.z < -1.0)
	host_match.wizards[0].position = Vector3(-3, 0, 0)
	host_match.wizards[1].position = Vector3(3, 0, 0)
	client_match.set_input(Vector2.ZERO, Vector3(-3, 0, 0))
	await _wait(0.6)
	var before := host_match.wizards[0].hp
	client_match.command("prepare", {"slot": 0})
	_check("prepare echoes immediately", client_match.wizards[1].chanting)
	var word := client_match.wizards[1].current_spell(0).incantation_compact()
	for c in word:
		client_match.command("chant_char", {"c": c})
	_check("typing echoes before a round trip", client_match.wizards[1].chant_text == word)
	await _wait(1.8)
	client_match.command("unleash")
	await _until(func() -> bool: return host_match.wizards[0].hp < before, "remote chant produces host-side damaging cast")
	await _wait(3.2) # Let the authoritative burn finish before comparing exact HP.
	_check("cast outcome reliably reaches guest", client_match.received_casts == host_match.received_casts and client_match.received_casts > 0)
	_check("authoritative HP agrees", is_equal_approx(host_match.wizards[0].hp, client_match.wizards[0].hp))
	var accepted := host_match.drivers[1].last_frame
	host_match.drivers[1].frame({"seq": accepted + 1, "move": Vector2(INF, 0), "aim": Vector3.ZERO})
	_check("non-finite movement rejected", host_match.drivers[1].last_frame == accepted)
	host_match._toggle_pause()
	var tick := host_match.server_tick
	await _wait(0.15)
	_check("online pause leaves simulation running", not get_tree().paused and host_match.server_tick > tick)
	host_match._toggle_pause()
	var winners: Array = [0, 1, 0, 1, 0]
	for round_no in winners.size():
		var winner: int = winners[round_no]
		if host_match.phase != "duel":
			if not await _until(func() -> bool: return host_match.phase == "duel" and client_match.phase == "duel", "round %d starts" % (round_no + 1)):
				break
		var loser := host_match.wizards[1 - winner]
		loser.take_damage(99999.0, "arcane", Vector3.ZERO, 0.0, false)
		if round_no == 4:
			break
		if not await _until(func() -> bool: return host_match.phase == "draft" and client_match.phase == "draft", "round %d enters draft" % (round_no + 1)):
			break
		_check("loser drafts first", host_match.pick_turn == 1 - winner and client_match.pick_turn == host_match.pick_turn)
		for pick in 2:
			var turn := host_match.pick_turn
			var id := str(host_match.offer[0]["id"])
			var chooser := host_match if turn == 0 else client_match
			chooser.command("boon_pick", {"id": id})
			if pick == 0:
				await _until(func() -> bool: return host_match.pick_turn == 1 - turn and client_match.pick_turn == 1 - turn, "first pick reaches both peers")
			else:
				await _until(func() -> bool: return host_match.phase == "duel" and client_match.phase == "duel", "both picks start next round")
		_check("boon histories agree", host_match.loadouts[0]["cards"] == client_match.loadouts[0]["cards"] and host_match.loadouts[1]["cards"] == client_match.loadouts[1]["cards"])
	await _until(func() -> bool: return host_match.phase == "results" and client_match.phase == "results", "full best-of-five reaches results")
	_check("identical final score 3-2", host_match.scores == [3, 2] and client_match.scores == host_match.scores)
	client_match.command("rematch_vote")
	await _wait(0.4)
	_check("one vote cannot rematch", host_match.phase == "results")
	host_match.command("rematch_vote")
	await _until(func() -> bool: return host_match.phase == "duel" and client_match.phase == "duel", "two votes start rematch")
	_check("rematch resets scores and boons", host_match.scores == [0, 0] and client_match.scores == [0, 0] and host_match.loadouts[0]["cards"].is_empty())
	var elapsed := maxi(1, Time.get_ticks_msec() - started_at)
	var host_sent := host_wire.bytes_sent - host_bytes_at_start
	var client_sent := client_wire.bytes_sent - client_bytes_at_start
	print("NET: bandwidth impaired=%s host_to_client=%d B/s client_to_host=%d B/s combined=%.1f KB/s (wire packet bytes; %.1f s)" % [impaired, host_sent * 1000 / elapsed, client_sent * 1000 / elapsed, float(host_sent + client_sent) * 1000.0 / elapsed / 1024.0, float(elapsed) / 1000.0])
	if impaired:
		_check("loss simulation dropped real unreliable packets", host_session.transport.dropped > 0 and client_session.transport.dropped > 0)
	client_match.leave()
	await _until(func() -> bool: return host_match.phase == "menu", "disconnect mid-round returns host to menu")
	await _wait(0.15)
	_check("disconnect leaves no arena or driver nodes", host_match.arena == null and host_match.drivers.is_empty() and host_match.wizards.is_empty() and get_tree().get_nodes_in_group("wizards").is_empty())
	await _cleanup()

func _wire_transport(transport: NetTransport) -> ENetTransport:
	if transport is Impaired:
		return transport.inner
	return transport as ENetTransport


func _cleanup() -> void:
	if is_instance_valid(host_session): host_session.leave()
	if is_instance_valid(client_session): client_session.leave()
	for root in _roots:
		root.queue_free()
	_roots.clear()
	host_match = null
	client_match = null
	await get_tree().process_frame
	host_session.queue_free()
	client_session.queue_free()
	await get_tree().process_frame

func _until(condition: Callable, label: String, timeout: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var passed := bool(condition.call())
	_check(label, passed)
	return passed

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _check(label: String, condition: bool) -> void:
	checks += 1
	print("  %s %s" % ["ok  " if condition else "FAIL", label])
	if not condition:
		failures.append(label)
