class_name BalanceTest
extends Node

## Exhaustive stat sanity check across wands, elements, forms, and modifiers.
## Run with: godot --headless -- --balance

var _checks := 0
var _failures: Array[String] = []


func run() -> int:
	print("BALANCE: start")
	for wand_id in SpellData.WAND_ORDER + ["apprentice"]:
		var wand: Dictionary = SpellData.wand(wand_id)
		for element in SpellData.element_ids():
			for form in SpellData.form_ids():
				for modifier in SpellData.modifier_ids():
					_check_spell(wand_id, wand, element, form, modifier)

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

	_check(label + " finite", _finite(plain), str(plain))
	_check(label + " mana > 0", float(plain["mana"]) > 0.0, "%.2f" % float(plain["mana"]))
	if form != "wall" and form != "aegis":
		_check(label + " damage > 0", float(plain["damage"]) > 0.0, "%.2f" % float(plain["damage"]))
		_check(label + " overcast > plain", float(over["damage"]) > float(plain["damage"]), "%.2f -> %.2f" % [float(plain["damage"]), float(over["damage"])])
	if form == "aegis":
		_check(label + " shield > 0", float(plain["shield"]) > 0.0, "%.2f" % float(plain["shield"]))
		_check(label + " overcast shield > plain", float(over["shield"]) > float(plain["shield"]), "%.2f -> %.2f" % [float(plain["shield"]), float(over["shield"])])
	_check(label + " overcast full mana", is_equal_approx(float(over["mana"]), float(plain["mana"])), "%.2f vs %.2f" % [float(over["mana"]), float(plain["mana"])])
	_check(label + " finite overcast", _finite(over), str(over))
	if modifier == "track":
		_check(label + " tracking homes", bool(plain.get("homing", false)), str(plain.get("homing", false)))


func _finite(stats: Dictionary) -> bool:
	for key in ["damage", "mana", "speed", "knockback", "radius", "shield", "homing_strength"]:
		if not is_finite(float(stats.get(key, 0.0))):
			return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures.append("%s %s" % [label, detail])
