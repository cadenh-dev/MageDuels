extends NetTransport

## Real ENet with deterministic 10% unreliable loss and 80ms one-way delay.
var inner := ENetTransport.new()
var delay_ms := 80
var dropped := 0
var _count := 0
var _queue: Array = []

func _ready() -> void:
	add_child(inner)
	inner.connected.connect(func() -> void:
		room_code = inner.room_code
		connected.emit()
	)
	inner.peer_joined.connect(func() -> void: peer_joined.emit())
	inner.peer_left.connect(func() -> void: peer_left.emit())
	inner.failed.connect(func(reason: String) -> void: failed.emit(reason))
	inner.message_received.connect(func(msg: Dictionary) -> void: message_received.emit(msg))

func host(options: Dictionary) -> void:
	inner.host(options)
	room_code = inner.room_code

func join(code: String) -> void:
	inner.join(code)
	room_code = inner.room_code

func leave() -> void:
	_queue.clear()
	inner.leave()
	room_code = ""

func is_host() -> bool:
	return inner.is_host()

func list_public_lobbies() -> Array:
	var result := await inner.list_public_lobbies()
	lobby_list_updated.emit(result)
	return result

func send_reliable(msg: Dictionary) -> void:
	_queue.append({"at": Time.get_ticks_msec() + delay_ms, "msg": msg.duplicate(true), "reliable": true})

func send_unreliable(msg: Dictionary) -> void:
	_count += 1
	if _count % 10 == 0:
		dropped += 1
		return
	_queue.append({"at": Time.get_ticks_msec() + delay_ms, "msg": msg.duplicate(true), "reliable": false})

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while not _queue.is_empty() and int(_queue[0]["at"]) <= now:
		var item: Dictionary = _queue.pop_front()
		if item["reliable"]:
			inner.send_reliable(item["msg"])
		else:
			inner.send_unreliable(item["msg"])
