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
		"slow": w.slow_time, "slow_amount": w.slow_amount, "stun": w.stun_time}

## Compact snapshot row. Coordinates and timers are fixed point, while flags
## share one integer. The decoder restores the stable dictionary used by the
## presentation code; this keeps the backend seam independent of the codec.
static func wizard_wire(w: Wizard) -> Array:
	var flags := 0
	flags |= 1 if w.alive else 0
	flags |= 2 if w.chanting else 0
	flags |= 4 if w.chanting or w.stun_time > 0.0 else 0
	flags |= 8 if w.assisted_chant else 0
	return [roundi(w.global_position.x * 100.0), roundi(w.global_position.z * 100.0),
		roundi(w.velocity.x * 100.0), roundi(w.velocity.z * 100.0),
		roundi(w.aim_point.x * 100.0), roundi(w.aim_point.y * 100.0), roundi(w.aim_point.z * 100.0),
		roundi(w.hp * 10.0), roundi(w.mana * 10.0), flags, w.page, w.selected_slot,
		w.chant_slot, roundi(w.chant_elapsed * 100.0), w.chant_best, w.chant_typos,
		roundi(w.chant_progress() * 1000.0), roundi(w.shield_hp * 10.0), roundi(w.shield_max * 10.0),
		roundi(w.slow_time * 100.0), roundi(w.slow_amount * 1000.0), roundi(w.stun_time * 100.0),
		w.chant_text]

static func wizard_unwire(row: Array) -> Dictionary:
	if row.size() != 23:
		return {}
	var flags := int(row[9])
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
		"text": str(row[22])}

static func apply(w: Wizard, data: Dictionary, preserve_echo: bool = false) -> void:
	var chant_changed := w.chanting != bool(data["chant"]) or w.chant_text != str(data["text"])
	w.hp = float(data["hp"])
	w.mana = float(data["mana"])
	if w.alive and not bool(data["alive"]):
		w._die() # Presentation/signals only; no damage is simulated on the guest.
	w.alive = bool(data["alive"])
	w.velocity = data["vel"]
	w.shield_hp = float(data["shield"])
	w.shield_max = float(data["shield_max"])
	w._shield_mesh.visible = w.shield_hp > 0.0
	w.slow_time = float(data["slow"])
	w.slow_amount = float(data["slow_amount"])
	w.stun_time = float(data["stun"])
	if not preserve_echo or not w.alive:
		w.page = int(data["page"])
		w.selected_slot = int(data["slot"])
		w.chanting = bool(data["chant"])
		w.chant_slot = int(data["cs"])
		w.chant_text = str(data["text"])
		w.chant_elapsed = float(data["elapsed"])
		w.chant_best = int(data["best"])
		w.chant_typos = int(data["typos"])
		w.assisted_chant = bool(data["assist"])
		w._set_chant_fx(w.chanting)
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
	elif node is SpellWall:
		data.merge({"kind": "wall", "color": node.color, "duration": node.duration})
	return data
