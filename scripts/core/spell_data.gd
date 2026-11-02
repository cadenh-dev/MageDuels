extends Node

## Static game data: runes, wands, and starter loadouts.
## Kept as plain dictionaries so a future server can share the same numbers.

var ELEMENTS: Dictionary = {
	"fire": {
		"name": "Fire",
		"word": "IGNA",
		"adj": "Ember",
		"color": Color("ff6b35"),
		"damage_mult": 1.0,
		"cost_mult": 1.0,
		"desc": "Burn 6 damage over 3s",
	},
	"frost": {
		"name": "Frost",
		"word": "GLACIA",
		"adj": "Frost",
		"color": Color("74dcff"),
		"damage_mult": 0.95,
		"cost_mult": 1.0,
		"desc": "Chill: 40% slow for 2s",
	},
	"storm": {
		"name": "Storm",
		"word": "VOLTA",
		"adj": "Storm",
		"color": Color("ffe066"),
		"damage_mult": 0.9,
		"cost_mult": 1.0,
		"desc": "Chains 50% damage to a nearby foe",
	},
	"earth": {
		"name": "Earth",
		"word": "TERRA",
		"adj": "Stone",
		"color": Color("c69763"),
		"damage_mult": 1.15,
		"cost_mult": 1.1,
		"desc": "Heavy knockback and stagger",
	},
	"arcane": {
		"name": "Arcane",
		"word": "ARCANA",
		"adj": "Arcane",
		"color": Color("c084fc"),
		"damage_mult": 1.0,
		"cost_mult": 1.0,
		"desc": "Burns 12 mana from the target",
	},
	"void": {
		"name": "Void",
		"word": "VANA",
		"adj": "Void",
		"color": Color("ff4d9d"),
		"damage_mult": 0.9,
		"cost_mult": 0.95,
		"desc": "Drains 25% of damage as health",
	},
}

var FORMS: Dictionary = {
	"bolt": {
		"name": "Bolt",
		"word": "MITT",
		"kind": "projectile",
		"damage": 10.0,
		"mana": 11.0,
		"cooldown": 0.42,
		"speed": 17.0,
		"count": 1,
		"radius": 0.32,
		"knockback": 1.5,
	},
	"orb": {
		"name": "Orb",
		"word": "QUAERO",
		"kind": "projectile",
		"damage": 13.0,
		"mana": 16.0,
		"cooldown": 0.95,
		"speed": 8.0,
		"count": 1,
		"radius": 0.46,
		"knockback": 2.5,
		"homing": true,
	},
	"beam": {
		"name": "Beam",
		"word": "RADIA",
		"kind": "beam",
		"damage": 17.0,
		"mana": 22.0,
		"cooldown": 0.95,
		"speed": 0.0,
		"count": 1,
		"range": 15.0,
		"knockback": 2.0,
	},
	"nova": {
		"name": "Nova",
		"word": "RUPTA",
		"kind": "nova",
		"damage": 15.0,
		"mana": 26.0,
		"cooldown": 1.7,
		"speed": 0.0,
		"count": 1,
		"radius": 4.8,
		"knockback": 7.0,
	},
	"wall": {
		"name": "Ward",
		"word": "MURUS",
		"kind": "wall",
		"damage": 0.0,
		"mana": 20.0,
		"cooldown": 4.5,
		"speed": 0.0,
		"count": 1,
		"duration": 7.0,
	},
}

var MODIFIERS: Dictionary = {
	"": {
		"name": "Plain",
		"word": "",
		"prefix": "",
		"desc": "No modifier",
	},
	"split": {
		"name": "Split",
		"word": "TRIA",
		"prefix": "Triple",
		"damage_mult": 0.62,
		"cost_mult": 1.35,
		"count": 3,
		"spread": 16.0,
		"desc": "Three projectiles at 62% damage",
	},
	"heavy": {
		"name": "Heavy",
		"word": "GRAVIS",
		"prefix": "Heavy",
		"damage_mult": 1.45,
		"speed_mult": 0.7,
		"cost_mult": 1.2,
		"cooldown_mult": 1.15,
		"knockback_mult": 1.8,
		"desc": "+45% damage, slower, huge knockback",
	},
	"quick": {
		"name": "Quick",
		"word": "CITUS",
		"prefix": "Hasty",
		"damage_mult": 0.82,
		"speed_mult": 1.5,
		"cost_mult": 0.9,
		"cooldown_mult": 0.75,
		"desc": "Faster, cheaper cooldown, -18% damage",
	},
	"pierce": {
		"name": "Pierce",
		"word": "PUNGO",
		"prefix": "Piercing",
		"damage_mult": 0.9,
		"cost_mult": 1.1,
		"pierce": 1,
		"desc": "Passes through one target",
	},
}

var WANDS: Dictionary = {
	"emberwood": {
		"name": "Emberwood",
		"affinity": "fire",
		"affinity_bonus": 0.15,
		"damage_mult": 1.05,
		"cooldown_mult": 1.0,
		"speed_mult": 1.0,
		"mana_max": 95.0,
		"mana_regen": 10.0,
		"hp": 100.0,
		"move_speed": 5.6,
		"color": Color("ff7a45"),
		"blurb": "Aggressive. Fire spells hit 30% harder.",
	},
	"frostglass": {
		"name": "Frostglass",
		"affinity": "frost",
		"affinity_bonus": 0.15,
		"damage_mult": 1.0,
		"cooldown_mult": 1.0,
		"speed_mult": 1.0,
		"mana_max": 135.0,
		"mana_regen": 14.0,
		"hp": 90.0,
		"move_speed": 5.2,
		"color": Color("74dcff"),
		"blurb": "Deep mana and fast recovery. Fragile.",
	},
	"stormbone": {
		"name": "Stormbone",
		"affinity": "storm",
		"affinity_bonus": 0.15,
		"damage_mult": 0.95,
		"cooldown_mult": 0.78,
		"speed_mult": 1.15,
		"mana_max": 100.0,
		"mana_regen": 11.0,
		"hp": 95.0,
		"move_speed": 6.1,
		"color": Color("ffe066"),
		"blurb": "Casts 22% faster. Storm spells are empowered.",
	},
	"voidheart": {
		"name": "Voidheart",
		"affinity": "void",
		"affinity_bonus": 0.15,
		"damage_mult": 1.0,
		"cooldown_mult": 0.95,
		"speed_mult": 1.0,
		"mana_max": 100.0,
		"mana_regen": 10.0,
		"hp": 85.0,
		"move_speed": 5.8,
		"color": Color("ff4d9d"),
		"blurb": "Void spells drain life. Low health, high risk.",
	},
}

const WAND_ORDER: Array[String] = ["emberwood", "frostglass", "stormbone", "voidheart"]


func element_ids() -> Array[String]:
	return ["fire", "frost", "storm", "earth", "arcane", "void"]


func form_ids() -> Array[String]:
	return ["bolt", "orb", "beam", "nova", "wall"]


func modifier_ids() -> Array[String]:
	return ["", "split", "heavy", "quick", "pierce"]


func wand(wand_id: String) -> Dictionary:
	return WANDS.get(wand_id, WANDS["emberwood"])


func make(element: String, form: String, modifier: String = "") -> SpellDef:
	return SpellDef.new(element, form, modifier)


## Two pages of four spells tuned around a wand's affinity.
func default_pages(wand_id: String) -> Array:
	var affinity: String = str(wand(wand_id)["affinity"])
	var secondary := _secondary_element(affinity)

	var page_a: Array[SpellDef] = [
		make(affinity, "bolt"),
		make(affinity, "beam", "quick"),
		make(secondary, "orb"),
		make("earth", "wall"),
	]
	var page_b: Array[SpellDef] = [
		make(affinity, "nova", "heavy"),
		make(secondary, "bolt", "split"),
		make("arcane", "orb", "pierce"),
		make("frost", "nova"),
	]

	return [page_a, page_b]


func _secondary_element(affinity: String) -> String:
	match affinity:
		"fire":
			return "storm"
		"frost":
			return "void"
		"storm":
			return "frost"
		"void":
			return "arcane"
		_:
			return "fire"


func random_spell(wand_id: String, allow_wall: bool = true) -> SpellDef:
	var element: String = _random_from(element_ids())
	var form: String = _random_from(form_ids())
	if not allow_wall and form == "wall":
		form = "bolt"
	return make(element, form, _random_from(modifier_ids()))


func random_pages(wand_id: String) -> Array:
	var a: Array[SpellDef] = []
	var b: Array[SpellDef] = []
	for i in 4:
		a.append(random_spell(wand_id))
		b.append(random_spell(wand_id))
	return [a, b]


func _random_from(options: Array) -> String:
	return str(options[randi() % options.size()])
