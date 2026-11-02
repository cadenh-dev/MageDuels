class_name NetServer
extends RefCounted

## Authoritative simulation stub for the sync spike. It owns wizard state,
## applies sequenced inputs, emits spell events, and broadcasts snapshots.

const TICK_RATE := 20
const SNAPSHOT_EVERY := 2
const EVENT_WINDOW_TICKS := 60
const ARENA_RADIUS := 8.1

var link: LoopbackLink
var tick := 0
var clients: Array[int] = []
var wizards: Dictionary = {}
var phase := "duel"
var round_index := 0
var player_score := 0
var enemy_score := 0
var last_snapshot_size := 0

var _inputs: Dictionary = {}
var _events: Array = []
var _event_seq := 0


func setup(p_link: LoopbackLink) -> void:
	link = p_link
	clients = [1, 2]
	add_wizard(1, Vector3(-6.0, 0.0, 0.0))
	add_wizard(2, Vector3(6.0, 0.0, 0.0))


func add_wizard(id: int, pos: Vector3) -> void:
	wizards[id] = {
		"id": id,
		"pos": pos,
		"vel": Vector3.ZERO,
		"aim": Vector3.RIGHT,
		"hp": 100.0,
		"max_hp": 100.0,
		"mana": 100.0,
		"max_mana": 100.0,
		"shield": 0.0,
		"page": 0,
		"slot": 0,
		"cooldowns": [0.0, 0.0, 0.0, 0.0],
		"chant": false,
		"chant_progress": 0.0,
		"chant_text_len": 0,
		"alive": true,
		"burn": 0.0,
		"slow": 0.0,
		"stun": 0.0,
	}


func apply_input(client_id: int, input: Dictionary) -> void:
	var previous: Dictionary = _inputs.get(client_id, {})
	if int(input.get("seq", 0)) <= int(previous.get("seq", -1)):
		return
	_inputs[client_id] = input


func step(dt: float) -> void:
	tick += 1
	for id in wizards:
		var w: Dictionary = wizards[id]
		var input: Dictionary = _inputs.get(id, {})
		var move: Vector2 = input.get("move", Vector2.ZERO)
		var speed := 5.5
		if float(w.get("slow", 0.0)) > 0.0:
			speed *= 0.6
		if bool(w.get("chant", false)) or float(w.get("stun", 0.0)) > 0.0:
			move = Vector2.ZERO
		w["vel"] = Vector3(move.x, 0.0, move.y) * speed
		w["pos"] = (w["pos"] as Vector3) + (w["vel"] as Vector3) * dt
		var flat := Vector2((w["pos"] as Vector3).x, (w["pos"] as Vector3).z)
		if flat.length() > ARENA_RADIUS:
			flat = flat.normalized() * ARENA_RADIUS
			w["pos"] = Vector3(flat.x, 0.0, flat.y)
		w["aim"] = input.get("aim", w.get("aim", Vector3.RIGHT))
		var cds: Array = w["cooldowns"]
		for i in cds.size():
			cds[i] = maxf(0.0, float(cds[i]) - dt)

	if tick % SNAPSHOT_EVERY == 0:
		broadcast_snapshot()


func cast(caster_id: int, element: String, form: String, modifier: String, origin: Vector3, direction: Vector3) -> int:
	_event_seq += 1
	_events.append({
		"id": _event_seq,
		"tick": tick,
		"kind": "cast",
		"caster": caster_id,
		"spell": {"element": element, "form": form, "modifier": modifier},
		"origin": origin,
		"direction": direction,
	})
	return _event_seq


func receive(packet: Dictionary, from_id: int) -> void:
	if str(packet.get("type", "")) == "input":
		apply_input(from_id, packet)


func broadcast_snapshot() -> void:
	var snap := NetSnapshot.new()
	snap.tick = tick
	snap.phase = phase
	snap.round_index = round_index
	snap.player_score = player_score
	snap.enemy_score = enemy_score
	snap.wizards = wizards.duplicate(true)

	var cutoff := tick - EVENT_WINDOW_TICKS
	var keep: Array = []
	for event in _events:
		if int(event.get("tick", 0)) >= cutoff:
			snap.events.append(event)
			keep.append(event)
	_events = keep

	var bytes := snap.encode()
	last_snapshot_size = bytes.size()
	link.broadcast(0, clients, {"type": "snapshot", "bytes": bytes}, tick)
