extends Node

## Static game data: runes, wands, and starter loadouts.
## Kept as plain dictionaries so a future server can share the same numbers.

var ELEMENTS: Dictionary = {
	"fire": {
		"name": "Fire",
		"word": "ARDE",
		"adj": "Ember",
		"color": Color("ff6b35"),
		"damage_mult": 1.0,
		"cost_mult": 1.0,
		"desc": "Burn 6 damage over 3s",
	},
	"frost": {
		"name": "Frost",
		"word": "FREZA",
		"adj": "Frost",
		"color": Color("74dcff"),
		"damage_mult": 0.95,
		"cost_mult": 1.0,
		"desc": "Chill: 40% slow for 2s",
	},
	"storm": {
		"name": "Storm",
		"word": "ZAGRA",
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
		"word": "SACRA",
		"adj": "Arcane",
		"color": Color("c084fc"),
		"damage_mult": 1.0,
		"cost_mult": 1.0,
		"desc": "Burns 12 mana from the target",
	},
	"void": {
		"name": "Void",
		"word": "VASTA",
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
		"word": "DARDE",
		"kind": "projectile",
		"damage": 10.0,
		"mana": 11.0,
		"speed": 17.0,
		"count": 1,
		"radius": 0.32,
		"knockback": 1.5,
	},
	"orb": {
		"name": "Orb",
		"word": "ASTRA",
		"kind": "projectile",
		"damage": 13.0,
		"mana": 16.0,
		"speed": 8.0,
		"count": 1,
		"radius": 0.46,
		"knockback": 2.5,
		"homing": true,
	},
	"beam": {
		"name": "Beam",
		"word": "RAZE",
		"kind": "beam",
		"damage": 17.0,
		"mana": 22.0,
		"speed": 0.0,
		"count": 1,
		"range": 15.0,
		"knockback": 2.0,
	},
	"nova": {
		"name": "Nova",
		"word": "BREXA",
		"kind": "nova",
		"damage": 15.0,
		"mana": 26.0,
		"speed": 0.0,
		"count": 1,
		"radius": 4.8,
		"knockback": 7.0,
	},
	"wall": {
		"name": "Ward",
		"word": "WARD",
		"kind": "wall",
		"damage": 0.0,
		"mana": 20.0,
		"speed": 0.0,
		"count": 1,
		"duration": 7.0,
	},
	"aegis": {
		"name": "Aegis",
		"word": "CETRA",
		"kind": "shield",
		"damage": 0.0,
		"mana": 24.0,
		"speed": 0.0,
		"count": 1,
		"duration": 3.0,
		"shield": 35.0,
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
		"word": "TRES",
		"prefix": "Triple",
		"damage_mult": 0.62,
		"cost_mult": 1.35,
		"count": 3,
		"spread": 16.0,
		"desc": "Three projectiles at 62% damage",
	},
	"heavy": {
		"name": "Heavy",
		"word": "GRAVE",
		"prefix": "Heavy",
		"damage_mult": 1.45,
		"speed_mult": 0.7,
		"cost_mult": 1.2,
		"knockback_mult": 1.8,
		"desc": "+45% damage, slower, huge knockback",
	},
	"quick": {
		"name": "Quick",
		"word": "DEXT",
		"prefix": "Hasty",
		"damage_mult": 0.82,
		"speed_mult": 1.5,
		"cost_mult": 0.85,
		"desc": "Faster, cheaper mana, -18% damage",
	},
	"pierce": {
		"name": "Pierce",
		"word": "WEDGE",
		"prefix": "Piercing",
		"damage_mult": 0.9,
		"cost_mult": 1.1,
		"pierce": 1,
		"desc": "Passes through one target",
	},
	"track": {
		"name": "Track",
		"word": "SEQA",
		"prefix": "Seeking",
		"damage_mult": 0.9,
		"cost_mult": 1.15,
		"homing": true,
		"homing_strength": 4.8,
		"desc": "Every shot curves toward the rival",
		"note": "All projectiles home in",
	},
}

var WANDS: Dictionary = {
	"emberwood": {
		"name": "Emberwood",
		"affinity": "fire",
		"affinity_bonus": 0.15,
		"damage_mult": 1.10,
		"cast_time_mult": 1.0,
		"speed_mult": 1.0,
		"mana_max": 95.0,
		"mana_regen": 10.0,
		"hp": 100.0,
		"move_speed": 5.6,
		"color": Color("ff7a45"),
		"blurb": "Aggressive. All spells +10%; fire spells +25%.",
	},
	"frostglass": {
		"name": "Frostglass",
		"affinity": "frost",
		"affinity_bonus": 0.15,
		"damage_mult": 1.0,
		"cast_time_mult": 1.0,
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
		"cast_time_mult": 0.78,
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
		"cast_time_mult": 0.95,
		"speed_mult": 1.0,
		"mana_max": 100.0,
		"mana_regen": 10.0,
		"hp": 85.0,
		"move_speed": 5.8,
		"color": Color("ff4d9d"),
		"blurb": "Void spells drain life. Low health, high risk.",
	},
	"apprentice": {
		"name": "Apprentice",
		"affinity": "",
		"affinity_bonus": 0.0,
		"damage_mult": 1.0,
		"cast_time_mult": 1.0,
		"speed_mult": 1.0,
		"mana_max": 100.0,
		"mana_regen": 11.0,
		"hp": 100.0,
		"move_speed": 5.5,
		"color": Color("cfd6ff"),
		"blurb": "A balanced training wand. No affinity, no tricks.",
	},
}

const WAND_ORDER: Array[String] = ["emberwood", "frostglass", "stormbone", "voidheart"]

## Draft boons for Arena 2.0. The loser picks first after each round.
var CARDS: Array = [
	{"id": "vitality", "name": "Vitality", "desc": "+20 max health", "kind": "hp", "amount": 20.0, "color": Color("66f2a5")},
	{"id": "wellspring", "name": "Wellspring", "desc": "+20 max mana", "kind": "mana", "amount": 20.0, "color": Color("5bd1ff")},
	{"id": "focus", "name": "Focus", "desc": "+10% spell damage", "kind": "damage", "amount": 0.10, "color": Color("ff8a5c")},
	{"id": "haste", "name": "Haste", "desc": "+10% cast speed", "kind": "cast", "amount": 0.10, "color": Color("ffe066")},
	{"id": "swiftness", "name": "Swiftness", "desc": "+8% move speed", "kind": "speed", "amount": 0.08, "color": Color("a78bfa")},
	{"id": "barrier", "name": "Barrier", "desc": "Start each round with 20 shield", "kind": "shield", "amount": 20.0, "color": Color("8fe7ff")},
	{"id": "wand_ember", "name": "Emberwood", "desc": "Switch wand: fire affinity, +25% fire damage", "kind": "wand", "wand_id": "emberwood", "color": Color("ff6b35")},
	{"id": "wand_frost", "name": "Frostglass", "desc": "Switch wand: frost affinity, +35 max mana", "kind": "wand", "wand_id": "frostglass", "color": Color("74dcff")},
	{"id": "wand_storm", "name": "Stormbone", "desc": "Switch wand: storm affinity, 22% faster casts", "kind": "wand", "wand_id": "stormbone", "color": Color("ffe066")},
	{"id": "wand_void", "name": "Voidheart", "desc": "Switch wand: void affinity, lifedrain spells", "kind": "wand", "wand_id": "voidheart", "color": Color("ff4d9d")},
	{"id": "rune_nova", "name": "Ember Nova", "desc": "Page B slot 4 becomes a heavy fire nova", "kind": "spell", "element": "fire", "form": "nova", "modifier": "heavy", "color": Color("ff6b35")},
	{"id": "rune_aegis", "name": "Glacial Aegis", "desc": "Page B slot 4 becomes a frost Aegis", "kind": "spell", "element": "frost", "form": "aegis", "modifier": "", "color": Color("74dcff")},
	{"id": "rune_lance", "name": "Void Lance", "desc": "Page B slot 4 becomes a piercing void beam", "kind": "spell", "element": "void", "form": "beam", "modifier": "pierce", "color": Color("ff4d9d")},
	{"id": "rune_seeker", "name": "Seeker Bolt", "desc": "Page B slot 4 becomes a tracking fire bolt", "kind": "spell", "element": "fire", "form": "bolt", "modifier": "track", "color": Color("ff9e5c")},
]


func apprentice_pages() -> Array:
	var page_a: Array[SpellDef] = [
		make("fire", "bolt"),
		make("frost", "bolt"),
		make("earth", "wall"),
		make("arcane", "beam"),
	]
	var page_b: Array[SpellDef] = [
		make("storm", "orb"),
		make("fire", "nova"),
		make("frost", "aegis"),
		make("void", "bolt", "quick"),
	]
	return [page_a, page_b]


func element_ids() -> Array[String]:
	return ["fire", "frost", "storm", "earth", "arcane", "void"]


func form_ids() -> Array[String]:
	return ["bolt", "orb", "beam", "nova", "wall", "aegis"]


func modifier_ids() -> Array[String]:
	return ["", "split", "heavy", "quick", "pierce", "track"]


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
		make("frost", "aegis"),
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
