class_name LoopbackLink
extends RefCounted

## In-process transport harness for the net test. Packets are queued with a
## tick delay; the later WebSocket transport implements the same send/poll shape.

var latency_ticks := 0
var loss_chance := 0.0
var _queue: Array = []


func send(from_id: int, to_id: int, payload: Dictionary, tick: int) -> void:
	if randf() < loss_chance:
		return
	_queue.append({
		"from": from_id,
		"to": to_id,
		"data": payload,
		"at": tick + latency_ticks,
	})


func broadcast(from_id: int, targets: Array, payload: Dictionary, tick: int) -> void:
	for to_id in targets:
		send(from_id, int(to_id), payload, tick)


func poll(tick: int) -> Array:
	var out: Array = []
	var keep: Array = []
	for packet in _queue:
		if int(packet["at"]) <= tick:
			out.append(packet)
		else:
			keep.append(packet)
	_queue = keep
	return out


func pending() -> int:
	return _queue.size()
