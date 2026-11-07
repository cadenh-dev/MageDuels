class_name SpellDef
extends RefCounted

## A single crafted spell: one element rune, one form rune, and an optional modifier.
## All balance math lives here so the server can reuse it verbatim later.

## Typed chants are the committed, high-risk cast: they pay full mana and hit far
## harder than a quickcast. Assisted holds are still overcast, but deliberately
## weaker so that actually typing the incantation stays the stronger option.
const OVERCAST_MULT := 2.4
const ASSIST_OVERCAST_MULT := 1.9
## Releasing an assisted hold inside the gold window is a perfect cast.
const PERFECT_DAMAGE_BONUS := 0.15
## Overcast scales zone/aura/fence dps and wall HP / shield absorb more gently
## than direct damage: value x (1 + (m - 1) x k).
const ZONE_SCALE := 0.5
const HP_SCALE := 0.6
const HEAVY_STRUCTURE := 1.45
const FIZZLE_MULT := 0.5

var element: String = "fire"
var form: String = "bolt"
var modifier: String = ""


func _init(p_element: String = "fire", p_form: String = "bolt", p_modifier: String = "") -> void:
	element = p_element
	form = p_form
	modifier = p_modifier


func element_data() -> Dictionary:
	return SpellData.ELEMENTS.get(element, SpellData.ELEMENTS["fire"])


func form_data() -> Dictionary:
	return SpellData.FORMS.get(form, SpellData.FORMS["bolt"])


func modifier_data() -> Dictionary:
	return SpellData.MODIFIERS.get(modifier, {})


func cell() -> Dictionary:
	return SpellData.cell(element, form)


func cell_name() -> String:
	var c := cell()
	if c.has("name"):
		return str(c["name"])
	return "%s %s" % [element_data()["adj"], form_data()["name"]]


func display_name() -> String:
	var prefix: String = str(modifier_data().get("prefix", ""))
	if prefix != "":
		return prefix + " " + cell_name()
	return cell_name()


func incantation() -> String:
	var parts: Array[String] = [str(element_data()["word"]), str(form_data()["word"])]
	if modifier != "":
		parts.append(str(modifier_data()["word"]))
	return " ".join(parts)


func incantation_compact() -> String:
	return incantation().replace(" ", "")


func base_stats() -> Dictionary:
	var f: Dictionary = form_data()
	var e: Dictionary = element_data()
	var m: Dictionary = modifier_data()
	var c: Dictionary = cell()

	var damage: float = float(c["damage"]) if c.has("damage") else float(f["damage"]) * float(e["damage_mult"])
	var mana: float = float(f["mana"]) * float(e["cost_mult"])
	var speed: float = float(c.get("speed", f.get("speed", 0.0)))
	var count: int = int(f.get("count", 1))
	var knockback: float = float(c.get("knockback", f.get("knockback", 0.0)))
	var pierce: int = 0
	var kind := str(f.get("kind", "projectile"))

	var mod_damage := float(m.get("damage_mult", 1.0))
	damage *= mod_damage
	mana *= float(m.get("cost_mult", 1.0))
	speed *= float(m.get("speed_mult", 1.0))
	if kind == "projectile":
		count = int(m.get("count", count))
	knockback *= float(m.get("knockback_mult", 1.0))
	pierce += int(m.get("pierce", 0))

	var range_m := float(c.get("range", f.get("range", 15.0)))
	var lifetime := 5.0
	if c.has("lifetime"):
		lifetime = float(c["lifetime"])
	elif form == "bolt" and speed > 0.0:
		lifetime = range_m / speed

	var status := str(c.get("desc", e.get("desc", "")))
	var note := str(m.get("note", ""))
	if note != "":
		status += "  ·  " + note

	var radius := float(c.get("radius", f.get("radius", 0.3)))
	if kind == "projectile":
		radius = float(f.get("radius", 0.32))

	return {
		"base_damage": damage,
		"damage": damage,
		"mana": mana,
		"speed": speed,
		"count": count,
		"knockback": knockback,
		"pierce": pierce,
		"spread": float(m.get("spread", 0.0)),
		"radius": radius,
		"range": range_m,
		"lifetime": lifetime,
		"duration": float(c.get("duration", f.get("duration", 0.0))),
		"shield": float(c.get("shield", f.get("shield", 0.0))),
		"wall_hp": float(c.get("hp", 0.0)),
		"homing": bool(c.get("homing", f.get("homing", false))) or bool(m.get("homing", false)),
		"homing_strength": float(m.get("homing_strength", 3.2)),
		"kind": kind,
		"form": form,
		"element": element,
		"modifier": modifier,
		"status": status,
		"color": e["color"],
		# Multipliers for the cell's secondary numbers. ``power`` scales hit
		# damage, ``zone_mult`` periodic damage, ``dur_mult`` hazard durations.
		"power": mod_damage,
		"mod_damage": mod_damage,
		"zone_mult": mod_damage,
		"dur_mult": 1.0,
		"cast_mult": 1.0,
		"reflections": int(c.get("reflections", 0)),
		"swallows": int(c.get("swallows", 0)),
	}


## Stats after the caster's wand affinity and the overcast bonus are applied.
## ``overcast_mult`` lets typed chants and assisted holds use different payoffs.
func resolved_stats(wand: Dictionary, overcast: bool = false, overcast_mult: float = OVERCAST_MULT) -> Dictionary:
	var s := base_stats()
	var affinity: String = str(wand.get("affinity", ""))
	var wand_scale: float = float(wand.get("damage_mult", 1.0))
	if element == affinity:
		wand_scale += float(wand.get("affinity_bonus", 0.0))

	s["damage"] = float(s["base_damage"]) * wand_scale
	s["power"] = float(s["power"]) * wand_scale
	s["zone_mult"] = float(s["zone_mult"]) * wand_scale
	s["speed"] = float(s["speed"]) * float(wand.get("speed_mult", 1.0))

	var mult := 1.0
	if overcast:
		mult = maxf(1.0, overcast_mult)
		s["damage"] = float(s["damage"]) * mult
		s["power"] = float(s["power"]) * mult
		s["overcast"] = true
		s["overcast_mult"] = mult
	_apply_structure(s, mult)

	s["damage"] = snappedf(float(s["damage"]), 0.1)
	s["mana"] = snappedf(float(s["mana"]), 0.1)
	return s


## Zone dps, wall HP, shield absorb and overcast-only counts for cast mult m.
func _apply_structure(s: Dictionary, mult: float) -> void:
	var c := cell()
	var heavy := HEAVY_STRUCTURE if modifier == "heavy" else 1.0
	s["cast_mult"] = mult
	s["zone_mult"] = float(s["zone_mult"]) * (1.0 + (mult - 1.0) * ZONE_SCALE)
	var hp_mult := (1.0 + (mult - 1.0) * HP_SCALE) * heavy
	s["shield"] = snappedf(float(c.get("shield", s["shield"])) * hp_mult, 0.1)
	s["wall_hp"] = snappedf(float(c.get("hp", 0.0)) * hp_mult, 0.1)
	var strong := mult >= SpellData.STRONG_CAST
	s["reflections"] = int(c.get("reflections", 0)) + (int(c.get("strong_reflections", 0)) if strong else 0)
	s["swallows"] = int(c.get("swallows", 0)) + (int(c.get("strong_swallows", 0)) if strong else 0)


## Early release: damage, dps, HP and durations x0.5. Status durations never
## scale, and the fizzle still pays full mana.
static func apply_fizzle(stats: Dictionary) -> void:
	for key in ["damage", "power", "zone_mult", "shield", "wall_hp", "duration", "knockback"]:
		stats[key] = float(stats.get(key, 0.0)) * FIZZLE_MULT
	stats["damage"] = snappedf(float(stats["damage"]), 0.1)
	stats["shield"] = snappedf(float(stats["shield"]), 0.1)
	stats["dur_mult"] = float(stats.get("dur_mult", 1.0)) * FIZZLE_MULT
	stats["cast_mult"] = FIZZLE_MULT
	stats["fizzle"] = true
	stats["fizzle_mult"] = FIZZLE_MULT


## Perfect assisted release: the cast multiplier grows by 15%; every
## structure value follows its own rule for the new multiplier.
static func apply_perfect(stats: Dictionary) -> void:
	var bonus := 1.0 + PERFECT_DAMAGE_BONUS
	var old_m := float(stats.get("cast_mult", 1.0))
	var new_m := old_m * bonus
	stats["damage"] = snappedf(float(stats["damage"]) * bonus, 0.1)
	stats["power"] = float(stats.get("power", 1.0)) * bonus
	stats["zone_mult"] = float(stats.get("zone_mult", 1.0)) * (1.0 + (new_m - 1.0) * ZONE_SCALE) / (1.0 + (old_m - 1.0) * ZONE_SCALE)
	var hp_ratio := (1.0 + (new_m - 1.0) * HP_SCALE) / (1.0 + (old_m - 1.0) * HP_SCALE)
	stats["shield"] = snappedf(float(stats["shield"]) * hp_ratio, 0.1)
	stats["wall_hp"] = snappedf(float(stats.get("wall_hp", 0.0)) * hp_ratio, 0.1)
	stats["cast_mult"] = new_m


func duplicate_spell() -> SpellDef:
	return SpellDef.new(element, form, modifier)


func equals(other: SpellDef) -> bool:
	return other != null and element == other.element and form == other.form and modifier == other.modifier
