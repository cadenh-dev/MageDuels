class_name Coach
extends PanelContainer

## Four-beat first-run coach. Advances when the player actually performs the action.

var player: Wizard
var step := 0
var done := false

var _title: Label
var _body: Label
var _count: Label
var _move_time := 0.0
var _last_page := 0
var _did_cast := false
var _did_swap := false
var _did_overcast := false

const STEPS := [
	["MOVE", "WASD slips you around incoming spells."],
	["QUICKCAST", "Press 1–4 to fire the highlighted spell instantly."],
	["SHIFT", "Tap SHIFT to swap between your two spell pages."],
	["CHANT", "SPACE, then type the gold runes and press ENTER. The 1.6s hold and direct hits make it a real risk. Half-typed still fizzles at ×0.5. Hold RMB / LT for assisted overcast."],
]


func _ready() -> void:
	custom_minimum_size = Vector2(348, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.04, 0.09, 0.92), Color(0.65, 0.51, 0.25, 0.5), 10))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var badge := UIKit.bold_label("TUTORIAL", 11, UIKit.GOLD)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	_title = UIKit.bold_label("", 14, UIKit.INK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title)

	_body = UIKit.label("", 13, UIKit.MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(230, 0)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_body)

	_count = UIKit.label("1/4", 11, UIKit.DIM)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_count)

	if player != null:
		player.cast_fired.connect(_on_cast)
		_last_page = player.page
	_render()


func update(delta: float) -> void:
	if done or player == null or not is_instance_valid(player):
		return
	if player.page != _last_page:
		_last_page = player.page
		_did_swap = true

	match step:
		0:
			if player.input_enabled and player.velocity.length() > 0.5:
				_move_time += delta
				if _move_time > 0.35:
					_advance()
		1:
			if _did_cast:
				_advance()
		2:
			if _did_swap:
				_advance()
		3:
			if _did_overcast:
				_advance()


func _on_cast(_wiz: Wizard, _spell: SpellDef, stats: Dictionary, _origin: Vector3, _direction: Vector3) -> void:
	_did_cast = true
	if bool(stats.get("overcast", false)):
		_did_overcast = true


func _advance() -> void:
	step += 1
	while step < STEPS.size() and _already_done(step):
		step += 1
	if step >= STEPS.size():
		_finish()
	else:
		_render()


func _already_done(index: int) -> bool:
	match index:
		1:
			return _did_cast
		2:
			return _did_swap
		3:
			return _did_overcast
	return false


func _render() -> void:
	if _title == null:
		return
	var data: Array = STEPS[step]
	_title.text = str(data[0])
	_body.text = str(data[1])
	_count.text = "%d/%d" % [step + 1, STEPS.size()]


func _finish() -> void:
	done = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
