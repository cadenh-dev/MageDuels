class_name NetTransport
extends Node

## Gameplay sees one connected opponent. Backends own addressing/lobbies.
## All callbacks run on the main thread; payloads contain values, never Objects.
signal connected
signal peer_joined
signal peer_left
signal message_received(msg: Dictionary)
signal lobby_list_updated(lobbies: Array)
signal failed(reason: String)

var room_code := ""

func host(_options: Dictionary) -> void:
	failed.emit("Hosting is unavailable on this transport.")

func join(_code: String) -> void:
	failed.emit("Joining is unavailable on this transport.")

func leave() -> void:
	pass

func list_public_lobbies() -> Array:
	# Awaitable even when the backend has a synchronous cached result.
	await get_tree().process_frame
	lobby_list_updated.emit([])
	return []

func send_reliable(_msg: Dictionary) -> void:
	pass

func send_unreliable(_msg: Dictionary) -> void:
	pass

func is_host() -> bool:
	return false
