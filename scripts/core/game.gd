extends Node

## Global game state + runtime input map.
## Screens live in main.gd; this node only owns durable data.

const TITLE := "SHIFTCAST"
const VERSION := "0.1.0"
const ROUNDS_TO_WIN := 2

var mode: String = "ai" ## "ai" | "local" | "online"
var player_wand: String = "emberwood"
var enemy_wand: String = "stormbone"
var player_pages: Array = []
var enemy_pages: Array = []
var player_score: int = 0
var enemy_score: int = 0
var round_index: int = 0
var arena_element: String = "fire"
var last_result: String = ""

var ui_scale: float = 1.0
var master_volume_db: float = 0.0
var input_mode := "kb" ## "kb" | "pad"


func _ready() -> void:
	randomize()
	_install_input_map()
	player_pages = SpellData.default_pages(player_wand)
	enemy_pages = SpellData.default_pages(enemy_wand)


func reset_match(p_mode: String = "ai") -> void:
	mode = p_mode
	player_score = 0
	enemy_score = 0
	round_index = 0
	arena_element = _pick_arena_element()
	last_result = ""


func next_round() -> void:
	round_index += 1
	arena_element = _pick_arena_element()


func record_round(player_won: bool) -> void:
	if player_won:
		player_score += 1
	else:
		enemy_score += 1


func match_over() -> bool:
	return player_score >= ROUNDS_TO_WIN or enemy_score >= ROUNDS_TO_WIN


func player_won_match() -> bool:
	return player_score >= ROUNDS_TO_WIN


func _pick_arena_element() -> String:
	var options: Array = ["fire", "frost", "storm", "earth", "arcane", "void"]
	return str(options[randi() % options.size()])


func wizard_kit(wand_id: String) -> Dictionary:
	var w: Dictionary = SpellData.wand(wand_id)
	return {
		"wand_id": wand_id,
		"max_hp": float(w.get("hp", 100.0)),
		"max_mana": float(w.get("mana_max", 100.0)),
		"mana_regen": float(w.get("mana_regen", 10.0)),
		"move_speed": float(w.get("move_speed", 5.5)),
		"color": w.get("color", Color.WHITE),
		"affinity": str(w.get("affinity", "")),
	}


func _install_input_map() -> void:
	_add_keys("move_left", [KEY_A])
	_add_keys("move_right", [KEY_D])
	_add_keys("move_forward", [KEY_W])
	_add_keys("move_back", [KEY_S])
	_add_keys("swap_page", [KEY_SHIFT])
	_add_keys("chant", [KEY_SPACE])
	_add_keys("confirm", [KEY_ENTER, KEY_KP_ENTER])
	_add_keys("pause", [KEY_ESCAPE])
	_add_keys("cast_1", [KEY_1])
	_add_keys("cast_2", [KEY_2])
	_add_keys("cast_3", [KEY_3])
	_add_keys("cast_4", [KEY_4])
	_add_keys("quick_swap", [KEY_Q])
	_add_keys("toggle_camera", [KEY_C])
	_add_mouse("cast_mouse", MOUSE_BUTTON_LEFT)

	# Assisted overcast: hold RMB / F / left trigger for 1.4s.
	_add_keys("assist_chant", [KEY_F])
	_add_mouse("assist_chant", MOUSE_BUTTON_RIGHT)
	_add_joy_axis("assist_chant", JOY_AXIS_TRIGGER_LEFT, 1.0)

	# Mouse wheel cycles the selected spell slot.
	_add_mouse("cycle_next", MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse("cycle_prev", MOUSE_BUTTON_WHEEL_UP)

	# Controller duel bindings: face buttons cast, right bumper swaps pages,
	# Start pauses. Left stick moves; right stick aims (read as raw axes).
	_add_joy_buttons("cast_1", [JOY_BUTTON_A])
	_add_joy_buttons("cast_2", [JOY_BUTTON_B])
	_add_joy_buttons("cast_3", [JOY_BUTTON_X])
	_add_joy_buttons("cast_4", [JOY_BUTTON_Y])
	_add_joy_buttons("swap_page", [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_LEFT])
	_add_joy_buttons("toggle_camera", [JOY_BUTTON_RIGHT_STICK])
	_add_joy_buttons("pause", [JOY_BUTTON_START])


func _add_keys(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for code in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		InputMap.action_add_event(action, ev)


func _add_mouse(action: StringName, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _add_joy_buttons(action: StringName, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for button in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)


func _add_joy_axis(action: StringName, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
