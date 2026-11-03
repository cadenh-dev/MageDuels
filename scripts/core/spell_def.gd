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


func display_name() -> String:
	var prefix: String = str(modifier_data().get("prefix", ""))
	var part := "%s %s" % [element_data()["adj"], form_data()["name"]]
	if prefix != "":
		return prefix + " " + part
	return part


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

	var damage: float = float(f["damage"]) * float(e["damage_mult"])
	var mana: float = float(f["mana"]) * float(e["cost_mult"])
	var speed: float = float(f.get("speed", 0.0))
	var count: int = int(f.get("count", 1))
	var knockback: float = float(f.get("knockback", 0.0))
	var pierce: int = 0

	damage *= float(m.get("damage_mult", 1.0))
	mana *= float(m.get("cost_mult", 1.0))
	speed *= float(m.get("speed_mult", 1.0))
	count = int(m.get("count", count))
	knockback *= float(m.get("knockback_mult", 1.0))
	pierce += int(m.get("pierce", 0))

	var kind := str(f.get("kind", "projectile"))
	var status := str(e.get("desc", ""))
	if kind == "shield":
		status = "Shield %d for %.1fs" % [roundi(float(f.get("shield", 0.0))), float(f.get("duration", 0.0))]
	elif kind == "wall":
		status = "Barrier for %.1fs" % float(f.get("duration", 0.0))
	var note := str(m.get("note", ""))
	if note != "":
		status += "  ·  " + note

	return {
		"base_damage": damage,
		"damage": damage,
		"mana": mana,
		"speed": speed,
		"count": count,
		"knockback": knockback,
		"pierce": pierce,
		"spread": float(m.get("spread", 0.0)),
		"radius": float(f.get("radius", 0.3)),
		"range": float(f.get("range", 15.0)),
		"duration": float(f.get("duration", 0.0)),
		"shield": float(f.get("shield", 0.0)),
		"homing": bool(f.get("homing", false)) or bool(m.get("homing", false)),
		"homing_strength": float(m.get("homing_strength", 3.2)),
		"kind": kind,
		"element": element,
		"status": status,
		"color": e["color"],
	}


## Stats after the caster's wand affinity and the overcast bonus are applied.
## ``overcast_mult`` lets typed chants and assisted holds use different payoffs.
func resolved_stats(wand: Dictionary, overcast: bool = false, overcast_mult: float = OVERCAST_MULT) -> Dictionary:
	var s := base_stats()
	var affinity: String = str(wand.get("affinity", ""))
	var affinity_bonus: float = float(wand.get("affinity_bonus", 0.0))
	var wand_damage: float = float(wand.get("damage_mult", 1.0))
	var base_damage: float = float(s["base_damage"])

	var final_damage: float = base_damage * wand_damage
	if element == affinity:
		final_damage += base_damage * affinity_bonus

	s["damage"] = final_damage
	s["speed"] = float(s["speed"]) * float(wand.get("speed_mult", 1.0))

	if overcast:
		var mult := maxf(1.0, overcast_mult)
		s["damage"] = float(s["damage"]) * mult
		s["shield"] = float(s["shield"]) * (1.0 + (mult - 1.0) * 0.6)
		s["overcast"] = true
		s["overcast_mult"] = mult

	s["damage"] = snappedf(float(s["damage"]), 0.1)
	s["mana"] = snappedf(float(s["mana"]), 0.1)
	return s


func duplicate_spell() -> SpellDef:
	return SpellDef.new(element, form, modifier)


func equals(other: SpellDef) -> bool:
	return other != null and element == other.element and form == other.form and modifier == other.modifier
