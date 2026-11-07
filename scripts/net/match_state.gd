class_name MatchState
extends RefCounted

## Wire codecs contain no Resources/Objects. Dictionaries are built only at
## snapshot cadence or on transitions, never in the render interpolation loop.
static func loadout(value: Dictionary) -> Dictionary:
	var result := value.duplicate()
	var pages: Array = []
	for row in value["pages"]:
		var spells: Array = []
		for s: SpellDef in row:
			spells.append([s.element, s.form, s.modifier])
		pages.append(spells)
	result["pages"] = pages
	return result

static func decode_loadout(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	var pages: Array = []
	for row in value["pages"]:
		var spells: Array[SpellDef] = []
		for s in row:
			spells.append(SpellDef.new(str(s[0]), str(s[1]), str(s[2])))
		pages.append(spells)
	result["pages"] = pages
	return result

static func wizard(w: Wizard) -> Dictionary:
	return {"pos": w.global_position, "vel": w.velocity, "aim": w.aim_point,
		"hp": w.hp, "mana": w.mana, "alive": w.alive, "page": w.page,
		"slot": w.selected_slot, "rooted": w.chanting or w.stun_time > 0.0,
		"chant": w.chanting, "cs": w.chant_slot, "text": w.chant_text,
		"elapsed": w.chant_elapsed, "best": w.chant_best, "typos": w.chant_typos,
		"assist": w.assisted_chant, "progress": w.chant_progress(),
		"shield": w.shield_hp, "shield_max": w.shield_max,
		"primed": w.primed_slot, "primed_page": w.primed_page, "prime_time": w.primed_remaining,
		"slow": w.slow_time, "slow_amount": w.slow_amount, "stun": w.stun_time,
		"shield_el": w.shield_element, "swallows": w.shield_swallows, "freeze": w.freeze_time,
		"shield_time": w.shield_time}

## Element <-> small int for compact rows ("" = none / plain).
const ELEMENT_CODES: Array[String] = ["", "fire", "frost", "storm", "earth", "arcane", "void"]

static func element_code(element: String) -> int:
	return maxi(0, ELEMENT_CODES.find(element))

static func element_from(code: int) -> String:
	return ELEMENT_CODES[code] if code >= 0 and code < ELEMENT_CODES.size() else ""

## Compact snapshot row. Coordinates and timers are fixed point, while flags
## share one integer. The decoder restores the stable dictionary used by the
## presentation code; this keeps the backend seam independent of the codec.
static func wizard_wire(w: Wizard) -> Array:
	var flags := 0
	flags |= 1 if w.alive else 0
	flags |= 2 if w.chanting else 0
	flags |= 4 if w.chanting or w.stun_time > 0.0 else 0
	flags |= 8 if w.assisted_chant else 0
	flags |= 16 if w.freeze_time > 0.0 else 0
	if w.freeze_time > 0.0:
		flags |= 4
	# Primed slot and its page share one int: slot + page * 4, -1 for none.
	var primed := w.primed_slot + maxi(0, w.primed_page) * 4 if w.primed_slot >= 0 else -1
	return [roundi(w.global_position.x * 100.0), roundi(w.global_position.z * 100.0),
		roundi(w.velocity.x * 100.0), roundi(w.velocity.z * 100.0),
		roundi(w.aim_point.x * 100.0), roundi(w.aim_point.y * 100.0), roundi(w.aim_point.z * 100.0),
		roundi(w.hp * 10.0), roundi(w.mana * 10.0), flags, w.page, w.selected_slot,
		w.chant_slot, roundi(w.chant_elapsed * 100.0), w.chant_best, w.chant_typos,
		roundi(w.chant_progress() * 1000.0), roundi(w.shield_hp * 10.0), roundi(w.shield_max * 10.0),
		roundi(w.slow_time * 100.0), roundi(w.slow_amount * 1000.0), roundi(w.stun_time * 100.0),
		w.chant_text, primed, roundi(w.primed_remaining * 100.0),
		element_code(w.shield_element), w.shield_swallows, roundi(w.freeze_time * 100.0), roundi(w.shield_time * 10.0)]

static func wizard_unwire(row: Array) -> Dictionary:
	if row.size() != 29:
		return {}
	var flags := int(row[9])
	var primed := int(row[23])
	return {"pos": Vector3(float(row[0]) / 100.0, 0.0, float(row[1]) / 100.0),
		"vel": Vector3(float(row[2]) / 100.0, 0.0, float(row[3]) / 100.0),
		"aim": Vector3(float(row[4]) / 100.0, float(row[5]) / 100.0, float(row[6]) / 100.0),
		"hp": float(row[7]) / 10.0, "mana": float(row[8]) / 10.0, "alive": flags & 1 != 0,
		"page": int(row[10]), "slot": int(row[11]), "rooted": flags & 4 != 0,
		"chant": flags & 2 != 0, "cs": int(row[12]), "elapsed": float(row[13]) / 100.0,
		"best": int(row[14]), "typos": int(row[15]), "assist": flags & 8 != 0,
		"progress": float(row[16]) / 1000.0, "shield": float(row[17]) / 10.0,
		"shield_max": float(row[18]) / 10.0, "slow": float(row[19]) / 100.0,
		"slow_amount": float(row[20]) / 1000.0, "stun": float(row[21]) / 100.0,
		"text": str(row[22]), "primed": primed % 4 if primed >= 0 else -1,
		"primed_page": primed / 4 if primed >= 0 else -1, "prime_time": float(row[24]) / 100.0,
		"shield_el": element_from(int(row[25])), "swallows": int(row[26]),
		"freeze": float(row[27]) / 100.0, "shield_time": float(row[28]) / 10.0}

static func apply(w: Wizard, data: Dictionary, preserve_echo: bool = false, preserve_selection: bool = false) -> void:
	var chant_changed := w.chanting != bool(data["chant"]) or w.chant_text != str(data["text"])
	w.hp = float(data["hp"])
	w.mana = float(data["mana"])
	if w.alive and not bool(data["alive"]):
		w._die() # Presentation/signals only; no damage is simulated on the guest.
	w.alive = bool(data["alive"])
	w.velocity = data["vel"]
	w.shield_hp = float(data["shield"])
	w.shield_max = float(data["shield_max"])
	var shield_el := str(data.get("shield_el", ""))
	w.shield_time = float(data.get("shield_time", 0.0))
	w.shield_swallows = int(data.get("swallows", 0))
	if shield_el != w.shield_element:
		w.shield_element = shield_el
		w.shield_stats = {}
		if w.shield_time > 0.0:
			w._show_shield(SpellData.ELEMENTS.get(shield_el, {}).get("color", Color("8fe7ff")))
	w._shield_mesh.visible = w.shield_time > 0.0 and (w.shield_hp > 0.0 or w.shield_element != "")
	w.freeze_time = float(data.get("freeze", 0.0))
	w.slow_time = float(data["slow"])
	w.slow_amount = float(data["slow_amount"])
	w.stun_time = float(data["stun"])
	w.primed_slot = int(data.get("primed", -1))
	w.primed_page = int(data.get("primed_page", -1))
	# Clients resolve the primed spell from page/slot; never from a stale def.
	w.primed_spell = null
	w.primed_remaining = float(data.get("prime_time", 0.0))
	w.chant_elapsed = float(data["elapsed"])
	if not preserve_echo or not w.alive:
		w.page = int(data["page"])
		if not preserve_selection:
			w.selected_slot = int(data["slot"])
		w.chanting = bool(data["chant"])
		w.chant_slot = int(data["cs"])
		w.chant_text = str(data["text"])
		w.chant_best = int(data["best"])
		w.chant_typos = int(data["typos"])
		w.assisted_chant = bool(data["assist"])
		w._set_chant_fx(w.chanting)
		if w.primed_slot >= 0:
			w._set_chant_fx(true)
			w._set_primed_tint(w.get_primed_spell(), true)
		else:
			w._set_primed_tint(null, false)
		var spell := w.current_spell(w.chant_slot)
		if w.chanting and spell != null:
			w._chant_label.text = spell.display_name().to_upper()
		if chant_changed:
			w.chant_changed.emit(w, w.chanting)
	w._update_bars()

static func entity(node: Node3D) -> Dictionary:
	var data := {"id": node.get_instance_id(), "pos": node.global_position, "rot": node.rotation}
	if node is SpellProjectile:
		var p := node as SpellProjectile
		data.merge({"kind": "projectile", "dir": p.direction, "speed": p.speed,
			"color": p.color, "radius": p.radius, "element": p.element})
	return data

## Wards and zones are static: sent once on the reliable lane with short keys
## and fixed-point numbers, then only HP changes (``whp``) and despawn follow.
## ``owners`` maps wizard -> canonical index.
static func static_entity(node: Node3D, owners: Array) -> Dictionary:
	var pos := Vector2i(roundi(node.global_position.x * 100.0), roundi(node.global_position.z * 100.0))
	if node is SpellWall:
		var w := node as SpellWall
		return {"id": w.get_instance_id(), "kind": "wall", "p": pos, "y": roundi(w.rotation.y * 1000.0),
			"e": element_code(w.element), "d": roundi(w.duration * 10.0), "h": roundi(w.hp * 10.0),
			"m": roundi(w.max_hp * 10.0), "o": owners.find(w.owner_wizard)}
	var z := node as SpellZone
	return {"id": z.get_instance_id(), "kind": "zone", "s": SpellZone.SHAPES.find(z.shape),
		"e": element_code(z.element), "p": pos, "r": roundi(z.radius * 100.0), "i": roundi(z.inner * 100.0),
		"a": Vector2i(roundi(z.a.x * 100.0), roundi(z.a.z * 100.0)), "b": Vector2i(roundi(z.b.x * 100.0), roundi(z.b.z * 100.0)),
		"w": roundi(z.half_width * 100.0), "d": roundi(z.duration * 10.0), "t": owners.find(z.attach)}

static func _v3(v: Variant) -> Vector3:
	if v is Vector2i:
		return Vector3(float(v.x) / 100.0, 0.0, float(v.y) / 100.0)
	return Vector3.ZERO

## Client-side presentation node for a static entity row.
static func build_static(data: Dictionary, wizards: Array) -> Node3D:
	var owner_index := int(data.get("o", data.get("t", -1)))
	var owner: Wizard = wizards[owner_index] if owner_index >= 0 and owner_index < wizards.size() else null
	if data["kind"] == "wall":
		var wall := SpellWall.new()
		wall.setup_ward({"element": element_from(int(data["e"])), "owner": owner, "authority": false,
			"duration": float(data["d"]) / 10.0, "max_hp": float(data["m"]) / 10.0, "hp": float(data["h"]) / 10.0})
		wall.position = _v3(data["p"])
		wall.rotation.y = float(data["y"]) / 1000.0
		return wall
	var zone := SpellZone.new()
	var shape_index := int(data["s"])
	zone.setup({"element": element_from(int(data["e"])), "shape": SpellZone.SHAPES[clampi(shape_index, 0, 2)],
		"radius": float(data["r"]) / 100.0, "inner": float(data["i"]) / 100.0,
		"a": _v3(data["a"]), "b": _v3(data["b"]), "half_width": float(data["w"]) / 100.0,
		"duration": float(data["d"]) / 10.0, "attach": wizards[int(data["t"])] if int(data["t"]) >= 0 and int(data["t"]) < wizards.size() else null,
		"authority": false})
	zone.position = _v3(data["p"])
	return zone
