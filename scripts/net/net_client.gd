class_name NetClient
extends RefCounted

## Client-side snapshot buffer, interpolation, and event dedupe.

const MAX_SNAPSHOTS := 32

var id := 1
var link: LoopbackLink
var input_seq := 0
var snapshots: Array[NetSnapshot] = []
var last_snapshot_tick := -1
var events_seen: Dictionary = {}
var received_events: Array = []


func setup(client_id: int, p_link: LoopbackLink) -> void:
	id = client_id
	link = p_link


func send_input(move: Vector2, aim: Vector3, tick: int) -> void:
	input_seq += 1
	link.send(id, 0, {
		"type": "input",
		"seq": input_seq,
		"move": move,
		"aim": aim,
	}, tick)


func receive(packet: Dictionary) -> bool:
	if str(packet.get("type", "")) != "snapshot":
		return false
	var bytes: PackedByteArray = packet.get("bytes", PackedByteArray())
	var snap := NetSnapshot.decode(bytes)
	if snap == null:
		return false
	if snap.tick <= last_snapshot_tick:
		return false

	snapshots.append(snap)
	last_snapshot_tick = snap.tick
	while snapshots.size() > MAX_SNAPSHOTS:
		snapshots.pop_front()

	for event in snap.events:
		var event_id := int(event.get("id", 0))
		if event_id <= 0 or events_seen.has(event_id):
			continue
		events_seen[event_id] = true
		received_events.append(event)
	return true


func latest_state(wizard_id: int) -> Dictionary:
	if snapshots.is_empty():
		return {}
	var state: Dictionary = snapshots[-1].wizards.get(wizard_id, {})
	return state.duplicate(true)


## Interpolates position/aim at (latest tick - delay), with the latest state
## providing discrete values such as hp, mana, and chant progress.
func interpolated_state(wizard_id: int, delay_ticks: float = 4.0) -> Dictionary:
	if snapshots.is_empty():
		return {}
	var latest := snapshots[-1]
	var latest_state: Dictionary = latest.wizards.get(wizard_id, {})
	if latest_state.is_empty():
		return {}
	var target := float(last_snapshot_tick) - delay_ticks

	var before_snap: NetSnapshot = null
	var after_snap: NetSnapshot = null
	for snap in snapshots:
		if float(snap.tick) <= target:
			before_snap = snap
		if float(snap.tick) >= target and after_snap == null:
			after_snap = snap

	if before_snap == null or after_snap == null or before_snap.tick == after_snap.tick:
		return latest_state.duplicate(true)

	var a: Dictionary = before_snap.wizards.get(wizard_id, latest_state)
	var b: Dictionary = after_snap.wizards.get(wizard_id, latest_state)
	var span := float(after_snap.tick - before_snap.tick)
	var t := clampf((target - float(before_snap.tick)) / maxf(span, 0.001), 0.0, 1.0)

	var out := b.duplicate(true)
	var a_pos: Vector3 = a.get("pos", b.get("pos", Vector3.ZERO))
	var b_pos: Vector3 = b.get("pos", a_pos)
	var a_aim: Vector3 = a.get("aim", b.get("aim", Vector3.RIGHT))
	var b_aim: Vector3 = b.get("aim", a_aim)
	out["pos"] = a_pos.lerp(b_pos, t)
	out["aim"] = a_aim.lerp(b_aim, t)
	return out
