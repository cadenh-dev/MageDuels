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
