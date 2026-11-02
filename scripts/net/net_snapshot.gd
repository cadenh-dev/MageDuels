class_name NetSnapshot
extends RefCounted

## Versioned authoritative state snapshot. The spike uses Godot's Variant
## serialization for speed of iteration; a production build should swap the
## codec for explicit packed fields after the schema stabilizes.

const VERSION := 1

var version := VERSION
var tick := 0
var phase := "duel"
var round_index := 0
var player_score := 0
var enemy_score := 0
var wizards: Dictionary = {}
var events: Array = []


func to_dict() -> Dictionary:
	return {
		"v": version,
		"tick": tick,
		"phase": phase,
		"round": round_index,
		"ps": player_score,
		"es": enemy_score,
		"w": wizards,
		"e": events,
	}


func encode() -> PackedByteArray:
	return var_to_bytes(to_dict())


static func decode(bytes: PackedByteArray) -> NetSnapshot:
	if bytes.is_empty():
		return null
	var data: Variant = bytes_to_var(bytes)
	if not (data is Dictionary):
		return null
	var snap := NetSnapshot.new()
	snap.version = int(data.get("v", 0))
	if snap.version != VERSION:
		return null
	snap.tick = int(data.get("tick", 0))
	snap.phase = str(data.get("phase", "duel"))
	snap.round_index = int(data.get("round", 0))
	snap.player_score = int(data.get("ps", 0))
	snap.enemy_score = int(data.get("es", 0))
	var w: Variant = data.get("w", {})
	snap.wizards = w if w is Dictionary else {}
	var e: Variant = data.get("e", [])
	snap.events = e if e is Array else []
	return snap


func byte_size() -> int:
	return encode().size()
