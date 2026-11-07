class_name ENetTransport
extends NetTransport

## Raw ENet packets keep independent endpoints usable in ONE SceneTree without
## installing a global multiplayer peer or depending on matching scene paths.
const DEFAULT_PORT := 24567
const MAX_PACKET := 49152
var peer: ENetMultiplayerPeer
var _hosting := false
var _remote := 0
const CHUNK_BYTES := 1100
var _packet_seq := 0
var _parts: Dictionary = {}
static var _local_lobbies: Dictionary = {}

func host(options: Dictionary) -> void:
	leave()
	if OS.has_feature("web"):
		failed.emit("ENet needs the desktop build. A web relay backend is not installed.")
		return
	peer = ENetMultiplayerPeer.new()
	var port := int(options.get("port", DEFAULT_PORT))
	if port < 1 or port > 65535:
		peer = null
		failed.emit("Port must be between 1 and 65535.")
		return
	var error := peer.create_server(port, 1, 2)
	if error != OK:
		peer = null
		failed.emit("Cannot host on port %d (%s)." % [port, error_string(error)])
		return
	_hosting = true
	room_code = "127.0.0.1:%d" % port
	peer.peer_connected.connect(_peer_connected)
	peer.peer_disconnected.connect(_peer_disconnected)
	if bool(options.get("public", false)):
		_local_lobbies[room_code] = {"code": room_code, "host_name": options.get("host_name", "Wizard"), "players": 1, "cast_mode": options.get("cast_mode", "chant")}
	connected.emit()

func join(code: String) -> void:
	leave()
	if OS.has_feature("web"):
		failed.emit("ENet needs the desktop build. A web relay backend is not installed.")
		return
	var address := code.strip_edges().split(":")
	if address.size() != 2 or not address[1].is_valid_int() or int(address[1]) < 1 or int(address[1]) > 65535:
		failed.emit("Use an address such as 127.0.0.1:24567.")
		return
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address[0], int(address[1]), 2)
	if error != OK:
		peer = null
		failed.emit("Cannot connect (%s)." % error_string(error))
		return
	room_code = code.strip_edges()
	peer.peer_connected.connect(_peer_connected)
	peer.peer_disconnected.connect(_peer_disconnected)

func _peer_connected(id: int) -> void:
	_remote = id
	# Recover promptly after arena construction temporarily raises handshake RTT.
	# The default slow ramp can starve the first movement stream on localhost.
	peer.get_peer(id).throttle_configure(1000, 32, 2)
	peer.get_peer(id).ping_interval(250)
	if _hosting:
		if _local_lobbies.has(room_code):
			_local_lobbies[room_code]["players"] = 2
	else:
		connected.emit()
	peer_joined.emit()

func _peer_disconnected(id: int) -> void:
	if id == _remote:
		_remote = 0
		peer_left.emit()

func _process(_delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	# Signal handlers may leave and release the peer while polling.
	if peer == null:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		failed.emit("Unable to connect to the host.")
		return
	var budget := 256
	while peer != null and peer.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var sender := peer.get_packet_peer()
		var lane := int(peer.get_packet_mode())
		var bytes := peer.get_packet()
		if sender != _remote or bytes.size() > MAX_PACKET:
			continue
		bytes = _decode_packet(bytes, lane)
		if bytes.is_empty():
			continue
		var value: Variant = bytes_to_var(bytes)
		if value is Dictionary and value.get("type") is String:
			message_received.emit(value)

func _send(msg: Dictionary, reliable: bool) -> void:
	if peer == null or _remote == 0 or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var bytes := var_to_bytes(msg)
	if bytes.size() > MAX_PACKET:
		failed.emit("Network payload exceeded the transport limit.")
		return
	# A compressed, bounded envelope keeps ordinary snapshots below the MTU.
	# Large volleys use explicit independently bounded unreliable chunks.
	bytes = bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	peer.set_target_peer(_remote)
	# Channel zero separates reliable and unreliable traffic internally.
	peer.transfer_channel = 0
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	_packet_seq += 1
	var count := ceili(float(bytes.size()) / CHUNK_BYTES)
	for part in count:
		var packet := PackedByteArray()
		packet.resize(12)
		packet.encode_u32(0, _packet_seq)
		packet.encode_u16(4, part)
		packet.encode_u16(6, count)
		packet.encode_u32(8, bytes.size())
		packet.append_array(bytes.slice(part * CHUNK_BYTES, mini((part + 1) * CHUNK_BYTES, bytes.size())))
		peer.put_packet(packet)

func _decode_packet(packet: PackedByteArray, lane: int) -> PackedByteArray:
	if packet.size() < 13 or packet.size() > CHUNK_BYTES + 12:
		return PackedByteArray()
	var seq := packet.decode_u32(0)
	var part := packet.decode_u16(4)
	var count := packet.decode_u16(6)
	var size := packet.decode_u32(8)
	if size < 1 or size > MAX_PACKET or count != ceili(float(size) / CHUNK_BYTES) or part >= count:
		return PackedByteArray()
	var chunk := packet.slice(12)
	if chunk.size() != mini(CHUNK_BYTES, size - part * CHUNK_BYTES):
		return PackedByteArray()
	if count == 1:
		return chunk.decompress_dynamic(MAX_PACKET, FileAccess.COMPRESSION_DEFLATE)
	# Multi-chunk messages need separate assemblies for reliable and unreliable
	# lanes. Reliable cast bursts can interleave with a large snapshot.
	var key := Vector2i(lane, seq)
	if not _parts.has(key):
		# Bounded to the most recent partial message per lane.
		for old in _parts.keys():
			if old.x == lane:
				if old.y > seq:
					return PackedByteArray()
				_parts.erase(old)
		_parts[key] = {"chunks": {}, "size": size, "count": count}
	var assembly: Dictionary = _parts[key]
	if assembly["size"] != size or assembly["count"] != count:
		return PackedByteArray()
	assembly["chunks"][part] = chunk
	if assembly["chunks"].size() != count:
		return PackedByteArray()
	var compressed := PackedByteArray()
	for i in count:
		compressed.append_array(assembly["chunks"][i])
	_parts.erase(key)
	return compressed.decompress_dynamic(MAX_PACKET, FileAccess.COMPRESSION_DEFLATE)

func send_reliable(msg: Dictionary) -> void:
	_send(msg, true)

func send_unreliable(msg: Dictionary) -> void:
	_send(msg, false)

func leave() -> void:
	_local_lobbies.erase(room_code)
	if peer != null:
		peer.close()
	peer = null
	_remote = 0
	_hosting = false
	_parts.clear()
	room_code = ""

func is_host() -> bool:
	return _hosting

func list_public_lobbies() -> Array:
	await get_tree().process_frame
	var result := _local_lobbies.values()
	lobby_list_updated.emit(result)
	return result

func _exit_tree() -> void:
	leave()
