class_name BalanceTest
extends Node

## Exhaustive stat sanity check across wands, elements, forms, and modifiers,
## plus an expected-value sweep of all 36 spellcraft cells.
## Run with: godot --headless -- --balance

const ABSORB_AEGIS: Array[String] = ["frost", "storm", "earth"]
const HP_WARDS: Array[String] = ["frost", "earth"]
## Rough exposure assumptions for the value model (seconds a rival spends in a
## hazard, hits a shield or ward actually soaks).
const ZONE_EXPOSURE := 0.8
const WARD_EXPOSURE := 1.0

var _checks := 0
var _failures: Array[String] = []
var _values: Dictionary = {}


func run() -> int:
	print("BALANCE: start")
	for wand_id in SpellData.WAND_ORDER + ["apprentice"]:
		var wand: Dictionary = SpellData.wand(wand_id)
		for element in SpellData.element_ids():
			for form in SpellData.form_ids():
				for modifier in SpellData.modifier_ids():
					_check_spell(wand_id, wand, element, form, modifier)
	_check(SpellData.SPELLS.size() == 36, "36 spellcraft cells", str(SpellData.SPELLS.size()))
	_report_outliers()

	print("BALANCE: %d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: %s" % f)
	print("BALANCE: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	return 0 if _failures.is_empty() else 1


func _check_spell(wand_id: String, wand: Dictionary, element: String, form: String, modifier: String) -> void:
	var label := "%s/%s/%s/%s" % [wand_id, element, form, "plain" if modifier == "" else modifier]
	var spell := SpellDef.new(element, form, modifier)
	var plain := spell.resolved_stats(wand, false)
	var over := spell.resolved_stats(wand, true)
	var fizzle := spell.resolved_stats(wand, false)
	SpellDef.apply_fizzle(fizzle)

	_check(_finite(plain), label + " finite", str(plain))
	_check(float(plain["mana"]) > 0.0, label + " mana > 0", "%.2f" % float(plain["mana"]))
	_check(spell.cell_name() != "", label + " has a cell name")
	if form != "wall" and form != "aegis":
		_check(float(plain["damage"]) > 0.0, label + " damage > 0", "%.2f" % float(plain["damage"]))
		_check(float(over["damage"]) > float(plain["damage"]), label + " overcast > plain", "%.2f -> %.2f" % [float(plain["damage"]), float(over["damage"])])
		_check(float(fizzle["damage"]) < float(plain["damage"]), label + " fizzle < plain")
	if form == "aegis" and element in ABSORB_AEGIS:
		_check(float(plain["shield"]) > 0.0, label + " shield > 0", "%.2f" % float(plain["shield"]))
		_check(float(over["shield"]) > float(plain["shield"]), label + " overcast shield > plain", "%.2f -> %.2f" % [float(plain["shield"]), float(over["shield"])])
		_check(absf(float(fizzle["shield"]) - float(plain["shield"]) * 0.5) < 0.1, label + " fizzle shield x0.5")
	if form == "wall" and element in HP_WARDS:
		_check(float(over["wall_hp"]) > float(plain["wall_hp"]), label + " overcast wall HP > plain")
		_check(absf(float(fizzle["wall_hp"]) - float(plain["wall_hp"]) * 0.5) < 0.1, label + " fizzle wall HP x0.5")
	_check(float(over["zone_mult"]) > float(plain["zone_mult"]), label + " overcast zone dps > plain")
	_check(is_equal_approx(float(fizzle["duration"]), float(plain["duration"]) * 0.5), label + " fizzle duration x0.5")
	_check(is_equal_approx(float(over["mana"]), float(plain["mana"])), label + " overcast full mana", "%.2f vs %.2f" % [float(over["mana"]), float(plain["mana"])])
	_check(_finite(over), label + " finite overcast", str(over))
	if modifier == "track":
		_check(bool(plain.get("homing", false)), label + " tracking homes", str(plain.get("homing", false)))
	if modifier == "" and wand_id == "apprentice":
		_values[element + ":" + form] = value(spell, plain) / maxf(1.0, float(plain["mana"]))
	if modifier != "" and form in ["bolt", "orb", "beam", "nova"]:
		_values_mod(wand_id, spell, plain)


var _mod_values: Dictionary = {}


func _values_mod(wand_id: String, spell: SpellDef, s: Dictionary) -> void:
	var key := "%s:%s:%s" % [spell.element, spell.form, spell.modifier]
	# Only where the modifier applies: Split on projectiles, Pierce on
	# projectiles and beams, Track on projectiles.
	if spell.modifier == "split" and spell.form not in ["bolt", "orb"]:
		return
	if spell.modifier in ["pierce", "track"] and spell.form == "nova":
		return
	if spell.modifier == "track" and spell.form == "beam":
		return
	if wand_id == "apprentice":
		_mod_values[key] = value(spell, s) / maxf(1.0, float(s["mana"]))


## Expected value of one plain cast in damage-equivalent points (damage dealt,
## or damage prevented for wards and aegis). A coarse model for spotting cells
## that are far off the curve, not a simulator.
static func value(spell: SpellDef, s: Dictionary) -> float:
	var c := spell.cell()
	var dmg := float(s["damage"])
	var power := float(s.get("power", 1.0))
	var zone := float(s.get("zone_mult", 1.0))
	var v := 0.0
	match spell.form:
		"bolt", "orb":
			v = dmg * int(s.get("count", 1))
			if c.has("patch_dps"):
				v += float(c["patch_dps"]) * zone * minf(float(c["patch_duration"]), ZONE_EXPOSURE * 2.0)
			if c.has("chain"):
				v += dmg * float(c["chain"])
			if c.has("zap_dps"):
				v += float(c["zap_dps"]) * zone * 1.0
			if c.has("leech_mana"):
				v += float(c["leech_mana"]) * 2.0 * 0.5
		"beam":
			v = dmg
		"nova":
			v = dmg * 0.8
			if c.has("band_dps"):
				v += float(c["band_dps"]) * zone * ZONE_EXPOSURE
		"wall":
			match spell.element:
				"earth", "frost":
					v = float(s["wall_hp"]) * 0.6
				"fire":
					v = float(c.get("zone_dps", 0.0)) * zone * WARD_EXPOSURE + float(c.get("burn", 0.0)) * 0.5
				"storm":
					v = float(c.get("cross_damage", 0.0)) * zone + float(c.get("zap_dps", 0.0)) * zone * 2.0
				"arcane":
					v = float(s.get("reflections", 0)) * 10.0 * 0.4
				"void":
					v = 10.0 * 1.25
		"aegis":
			match spell.element:
				"fire":
					v = float(c.get("aura_dps", 0.0)) * zone * float(s["duration"]) * 0.35
				"arcane":
					v = 20.0
				"void":
					v = float(s.get("swallows", 0)) * 10.0
				_:
					v = float(s["shield"]) * 0.6
	# Element riders, roughly in damage points.
	if spell.form in ["bolt", "orb", "beam", "nova"]:
		match spell.element:
			"fire": v += 3.0
			"void": v += dmg * float(c.get("drain", 0.25))
			"arcane": v += float(c.get("mana_burn", 12.0)) * 0.25
			"storm", "earth", "frost": v += 2.0
	return v * (1.0 if power > 0.0 else 0.0)


func _report_outliers() -> void:
	var list: Array = _values.values()
	list.sort()
	var median: float = list[list.size() / 2]
	print("BALANCE: value per mana, apprentice wand, plain cast (median %.2f)" % median)
	var keys := _values.keys()
	keys.sort()
	var outliers := 0
	for key in keys:
		var v := float(_values[key])
		var tag := ""
		if v > median * 2.0:
			tag = "  << HIGH (>2x median)"
		elif v < median * 0.5:
			tag = "  << LOW (<0.5x median)"
		if tag != "":
			outliers += 1
		print("  %-14s %-16s %.2f%s" % [key, SpellData.cell(key.split(":")[0], key.split(":")[1]).get("name", ""), v, tag])
	print("BALANCE: %d cell outliers" % outliers)
	var mod_outliers := 0
	for key in _mod_values.keys():
		var v := float(_mod_values[key])
		if v > median * 2.0 or v < median * 0.5:
			mod_outliers += 1
			print("  modifier outlier %s %.2f" % [key, v])
	print("BALANCE: %d modifier outliers" % mod_outliers)


func _finite(stats: Dictionary) -> bool:
	for key in ["damage", "mana", "speed", "knockback", "radius", "shield", "homing_strength", "wall_hp", "zone_mult", "power", "lifetime"]:
		if not is_finite(float(stats.get(key, 0.0))):
			return false
	return true


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures.append("%s %s" % [label, detail])
