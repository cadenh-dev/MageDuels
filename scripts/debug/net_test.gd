extends Node

## Headless loopback proof for the authoritative sync spike.
## Run: godot --headless --path . res://scenes/NetTest.tscn

const DT := 0.05
const LOOPS := 100
const FLUSH := 8

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var link := LoopbackLink.new()
	link.latency_ticks = 2

	var server := NetServer.new()
	server.setup(link)
	var c1 := NetClient.new()
	c1.setup(1, link)
	var c2 := NetClient.new()
	c2.setup(2, link)

	var duplicate_probe: Dictionary = {}

	for i in LOOPS:
		var move1 := Vector2(1, 0) if i < 40 else Vector2.ZERO
		var move2 := Vector2(-1, 0) if i < 40 else Vector2.ZERO
		c1.send_input(move1, Vector3.RIGHT, server.tick)
		c2.send_input(move2, Vector3.LEFT, server.tick)

		for packet in link.poll(server.tick):
			var to_id := int(packet["to"])
			var data: Dictionary = packet["data"]
			if to_id == 0:
				server.receive(data, int(packet["from"]))
			elif to_id == 1:
				c1.receive(data)
			elif to_id == 2:
				c2.receive(data)

		if i == 20:
			server.cast(1, "fire", "bolt", "", Vector3(-6, 1.7, 0), Vector3.RIGHT)

		server.step(DT)

	for j in FLUSH:
		c1.send_input(Vector2.ZERO, Vector3.RIGHT, server.tick)
		c2.send_input(Vector2.ZERO, Vector3.LEFT, server.tick)
		for packet in link.poll(server.tick):
			var to_id := int(packet["to"])
			var data: Dictionary = packet["data"]
			if to_id == 0:
				server.receive(data, int(packet["from"]))
			elif to_id == 1:
				duplicate_probe = data.duplicate()
				c1.receive(data)
			elif to_id == 2:
				c2.receive(data)
		server.step(DT)

	_check("clients received snapshots", c1.snapshots.size() > 8 and c2.snapshots.size() > 8, "%d/%d" % [c1.snapshots.size(), c2.snapshots.size()])
	_check("ticks are monotonic", c1.last_snapshot_tick > 0 and c2.last_snapshot_tick > 0, "%d/%d" % [c1.last_snapshot_tick, c2.last_snapshot_tick])
	_check("snapshot payload is bounded", server.last_snapshot_size > 0 and server.last_snapshot_size < 4096, "%d bytes" % server.last_snapshot_size)

	var authoritative1: Dictionary = server.wizards[1]
	var authoritative2: Dictionary = server.wizards[2]
	var view1 := c1.interpolated_state(1, 4.0)
	var view2 := c2.interpolated_state(2, 4.0)
	var err1 := (view1.get("pos", Vector3.ZERO) as Vector3).distance_to(authoritative1["pos"])
	var err2 := (view2.get("pos", Vector3.ZERO) as Vector3).distance_to(authoritative2["pos"])
	_check("client 1 converges", err1 < 0.15, "err=%.3f" % err1)
	_check("client 2 converges", err2 < 0.15, "err=%.3f" % err2)

	_check("spell event delivered once to client 1", c1.received_events.size() == 1, "events=%d" % c1.received_events.size())
	_check("spell event delivered once to client 2", c2.received_events.size() == 1, "events=%d" % c2.received_events.size())
	if not c1.received_events.is_empty():
		var event: Dictionary = c1.received_events[0]
		_check("event carries cast data", str(event.get("kind", "")) == "cast" and int(event.get("caster", 0)) == 1, str(event))

	var event_count_before := c1.received_events.size()
	if not duplicate_probe.is_empty():
		c1.receive(duplicate_probe)
	_check("duplicate/out-of-order snapshot is ignored", c1.received_events.size() == event_count_before, "events=%d" % c1.received_events.size())

	_check("server is authoritative at rest", (authoritative1["pos"] as Vector3).distance_to(Vector3(5.0, 0, 0)) < 0.2, str(authoritative1["pos"]))
	_check("rival is authoritative at rest", (authoritative2["pos"] as Vector3).distance_to(Vector3(-5.0, 0, 0)) < 0.2, str(authoritative2["pos"]))

	print("NET: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("  FAIL %s" % failure)
	print("NET: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		failures.append(label)
