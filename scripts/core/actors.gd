class_name Actors
extends RefCounted

## Scene entry points for the 3D actors. Scenes are loaded lazily so actor
## scripts can reference Fx without creating a preload cycle.

const WIZARD_PATH := "res://scenes/actors/Wizard.tscn"
const PROJECTILE_PATH := "res://scenes/actors/SpellProjectile.tscn"
const WALL_PATH := "res://scenes/actors/SpellWall.tscn"
const BEAM_PATH := "res://scenes/fx/FxBeam.tscn"
const SHOCKWAVE_PATH := "res://scenes/fx/FxShockwave.tscn"
const BURST_PATH := "res://scenes/fx/FxBurst.tscn"
const DAMAGE_NUMBER_PATH := "res://scenes/fx/FxDamageNumber.tscn"

static var _wizard: PackedScene
static var _projectile: PackedScene
static var _wall: PackedScene
static var _beam: PackedScene
static var _shockwave: PackedScene
static var _burst: PackedScene
static var _damage_number: PackedScene


static func wizard() -> PackedScene:
	if _wizard == null:
		_wizard = load(WIZARD_PATH) as PackedScene
	return _wizard


static func projectile() -> PackedScene:
	if _projectile == null:
		_projectile = load(PROJECTILE_PATH) as PackedScene
	return _projectile


static func wall() -> PackedScene:
	if _wall == null:
		_wall = load(WALL_PATH) as PackedScene
	return _wall


static func beam() -> PackedScene:
	if _beam == null:
		_beam = load(BEAM_PATH) as PackedScene
	return _beam


static func shockwave() -> PackedScene:
	if _shockwave == null:
		_shockwave = load(SHOCKWAVE_PATH) as PackedScene
	return _shockwave


static func burst() -> PackedScene:
	if _burst == null:
		_burst = load(BURST_PATH) as PackedScene
	return _burst


static func damage_number() -> PackedScene:
	if _damage_number == null:
		_damage_number = load(DAMAGE_NUMBER_PATH) as PackedScene
	return _damage_number
