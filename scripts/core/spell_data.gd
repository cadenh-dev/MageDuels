extends Node

## Static game data: runes, wands, and starter loadouts.
## Kept as plain dictionaries so a future server can share the same numbers.

## Constructive spellcraft: one cell per element x form. The element is the
## material and decides collision, hazards and riders; the form is the shape.
## Numbers are base values before wand, arena, boons, overcast and modifiers.
## Cell ``damage`` already includes the element's damage_mult. Secondary hit
## damage (splash, zaps, shatter, arcs) scales with the cast's direct power;
## ``*_dps`` values scale with the zone rule; ``hp`` and ``shield`` with the
## wall/shield rule (see SpellDef.resolved_stats).
var SPELLS: Dictionary = {
	"fire:bolt": {"name": "Ember Dart", "speed": 17.0, "damage": 9.0, "range": 15.0,
		"patch_radius": 1.2, "patch_duration": 2.5, "patch_dps": 4.0,
		"desc": "Burn; leaves a fire patch where it lands"},
	"fire:orb": {"name": "Fireball", "speed": 8.0, "damage": 12.0, "homing": true,
		"explode_radius": 2.2, "splash": 8.0, "patch_radius": 2.0, "patch_duration": 3.0, "patch_dps": 4.0,
		"desc": "Explodes for splash and leaves burning ground"},
	"fire:beam": {"name": "Flame Jet", "range": 8.0, "damage": 14.0, "beam_width": 0.9,
		"desc": "Short, wide jet of flame; burns"},
	"fire:nova": {"name": "Inferno Ring", "radius": 4.8, "damage": 13.0, "knockback": 3.0,
		"band_inner": 4.0, "band_duration": 3.0, "band_dps": 5.0,
		"desc": "Burst that leaves a ring of fire"},
	"fire:wall": {"name": "Flame Sheet", "duration": 5.0, "zone_dps": 10.0, "burn": 12.0, "zone_depth": 0.75,
		"desc": "Blocks nothing; burns and ignites what crosses"},
	"fire:aegis": {"name": "Heat Aura", "duration": 4.0, "shield": 0.0, "aura_radius": 2.2, "aura_dps": 6.0,
		"desc": "Burning aura; melts frost; immune to chill"},
	"frost:bolt": {"name": "Ice Shard", "speed": 17.0, "damage": 9.5, "range": 15.0,
		"fragments": 3, "fragment_damage": 4.0, "fragment_range": 6.0, "fragment_cone": 40.0,
		"desc": "Chill; shatters into shards on walls"},
	"frost:orb": {"name": "Frost Globe", "speed": 7.0, "damage": 12.0, "homing": true, "freeze_chilled": true,
		"trail_width": 1.2, "trail_duration": 3.0, "trail_step": 1.4,
		"desc": "Leaves an ice trail; freezes chilled targets"},
	"frost:beam": {"name": "Freeze Ray", "range": 15.0, "damage": 15.0, "chill": 0.6, "chill_time": 2.5,
		"strip_width": 1.0, "strip_duration": 3.0,
		"desc": "Deep chill; coats the ground in ice"},
	"frost:nova": {"name": "Rime Burst", "radius": 4.8, "damage": 13.0, "knockback": 2.0, "freeze_chilled": true,
		"floor_duration": 3.0,
		"desc": "Freezes the floor; freezes chilled targets"},
	"frost:wall": {"name": "Ice Wall", "duration": 7.0, "hp": 30.0, "solid_wizards": true,
		"proj_slow": 0.5, "proj_damage_loss": 0.25, "chill_radius": 0.4,
		"shatter_damage": 8.0, "shatter_radius": 2.5,
		"desc": "Blocks wizards; slows projectiles; shatters"},
	"frost:aegis": {"name": "Ice Armor", "duration": 4.0, "shield": 30.0,
		"shatter_damage": 8.0, "shatter_radius": 2.5,
		"desc": "Absorbs; immune to chill; shatters when broken"},
	"storm:bolt": {"name": "Spark", "speed": 26.0, "damage": 9.0, "range": 15.0, "chain": 0.5,
		"desc": "Fastest bolt; jolts and chains"},
	"storm:orb": {"name": "Ball Lightning", "speed": 6.0, "damage": 10.0, "homing": false, "lifetime": 4.0,
		"zap_interval": 0.5, "zap_range": 3.5, "zap_dps": 8.0,
		"desc": "Drifting orb that zaps anyone nearby"},
	"storm:beam": {"name": "Chain Lance", "range": 15.0, "damage": 15.0, "bounces": 1,
		"desc": "Jolts; bounces once off solid walls"},
	"storm:nova": {"name": "Thunderclap", "radius": 3.5, "damage": 14.0, "jolt": 0.5, "knockback": 1.0,
		"desc": "Small burst; long jolt breaks chants"},
	"storm:wall": {"name": "Tesla Fence", "duration": 6.0, "cross_damage": 8.0, "cross_cooldown": 1.0,
		"zap_interval": 1.0, "zap_range": 3.0, "zap_dps": 4.0,
		"desc": "Blocks nothing; jolts whoever crosses"},
	"storm:aegis": {"name": "Static Shell", "duration": 4.0, "shield": 20.0, "move_mult": 1.15,
		"arc_damage": 8.0, "arc_cooldown": 0.5,
		"desc": "Absorbs; faster; arcs back at attackers"},
	"earth:bolt": {"name": "Stone Bolt", "speed": 13.0, "damage": 11.5, "range": 15.0, "knockback": 3.0,
		"desc": "Heavy bolt; stagger; x1.5 to walls"},
	"earth:orb": {"name": "Boulder", "speed": 9.0, "damage": 15.0, "knockback": 6.0, "homing": false,
		"low": true, "smash_ice": true,
		"desc": "Rolls low; smashes ice walls"},
	"earth:beam": {"name": "Fault Line", "range": 15.0, "damage": 19.5,
		"desc": "Ground spikes; ignores non-solid walls"},
	"earth:nova": {"name": "Quake", "radius": 4.8, "damage": 17.0, "knockback": 9.0, "wall_damage": 20.0,
		"desc": "Huge knockback; cracks every wall nearby"},
	"earth:wall": {"name": "Stone Wall", "duration": 8.0, "hp": 60.0, "solid_wizards": true, "solid_projectiles": true,
		"desc": "Blocks wizards, projectiles and beams"},
	"earth:aegis": {"name": "Stoneskin", "duration": 4.0, "shield": 45.0, "move_mult": 0.75,
		"desc": "Big absorb; immune to knockback, stagger, jolt"},
	"arcane:bolt": {"name": "Arcane Missile", "speed": 17.0, "damage": 9.0, "range": 15.0, "phase": true,
		"desc": "Burns mana; phases through solid walls"},
	"arcane:orb": {"name": "Mana Sphere", "speed": 8.0, "damage": 11.0, "homing": true, "phase": true,
		"mana_burn": 15.0, "leech_interval": 0.5, "leech_range": 3.0, "leech_mana": 4.0,
		"desc": "Phases; leeches mana from nearby foes"},
	"arcane:beam": {"name": "Arcane Ray", "range": 15.0, "damage": 17.0, "wall_loss": 0.3,
		"desc": "Burns mana; passes walls at -30% each"},
	"arcane:nova": {"name": "Repulse", "radius": 4.8, "damage": 8.0, "knockback": 9.0, "reflect": true,
		"desc": "Pushes back and reflects enemy projectiles"},
	"arcane:wall": {"name": "Mirror Ward", "duration": 5.0, "reflections": 4, "strong_reflections": 2,
		"desc": "Players pass; reflects enemy spells"},
	"arcane:aegis": {"name": "Mana Shield", "duration": 4.0, "shield": 0.0,
		"desc": "Damage is paid from mana instead of health"},
	"void:bolt": {"name": "Void Dart", "speed": 17.0, "damage": 9.0, "range": 15.0, "pull": 1.5,
		"desc": "Drains; pulls the target toward you"},
	"void:orb": {"name": "Singularity", "speed": 5.0, "damage": 12.0, "homing": false, "lifetime": 4.0,
		"pull_radius": 3.5, "pull_speed": 3.0, "absorb_bonus": 3.0, "collapse_radius": 1.5,
		"desc": "Pulls foes in; eats projectiles; collapses"},
	"void:beam": {"name": "Siphon", "range": 12.0, "damage": 16.0, "drain": 0.5, "pull": 2.0,
		"desc": "Drains 50%; pulls the target in"},
	"void:nova": {"name": "Implosion", "radius": 4.8, "damage": 13.0, "pull": 2.5, "knockback": 0.0,
		"desc": "Drains; pulls everyone inward"},
	"void:wall": {"name": "Rift", "duration": 5.0, "slow": 0.25, "heal": 0.25, "zone_depth": 0.75,
		"desc": "Players pass; consumes enemy projectiles"},
	"void:aegis": {"name": "Void Shroud", "duration": 4.0, "shield": 0.0, "swallows": 2, "strong_swallows": 1,
		"heal": 0.25,
		"desc": "Swallows the next projectile hits"},
}

## Cast multiplier at which overcast-only bonuses (Mirror, Shroud) apply.
const STRONG_CAST := 1.9


func cell(element: String, form: String) -> Dictionary:
	return SPELLS.get(element + ":" + form, {})


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
	{"id": "rune_nova", "name": "Heavy Inferno Ring", "desc": "Page B slot 4: a fire burst that leaves a hotter ring of flame to fence the rival in", "kind": "spell", "element": "fire", "form": "nova", "modifier": "heavy", "color": Color("ff6b35")},
	{"id": "rune_aegis", "name": "Ice Armor", "desc": "Page B slot 4: ice that absorbs 30, stops chill and shatters on whoever breaks it", "kind": "spell", "element": "frost", "form": "aegis", "modifier": "", "color": Color("74dcff")},
	{"id": "rune_lance", "name": "Piercing Siphon", "desc": "Page B slot 4: a gravity ray that drains half its damage, pulls the rival in and slips past one wall", "kind": "spell", "element": "void", "form": "beam", "modifier": "pierce", "color": Color("ff4d9d")},
	{"id": "rune_seeker", "name": "Seeking Ember Dart", "desc": "Page B slot 4: a homing flame dart that burns and leaves fire where it lands", "kind": "spell", "element": "fire", "form": "bolt", "modifier": "track", "color": Color("ff9e5c")},
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
