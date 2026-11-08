class_name RemoteInputDriver
extends Node

## Uses the same Wizard entry points as AIWizard, with no simulated authority
## on the client. Sequence windows, finite vectors, slot/character limits and
## an event budget bound untrusted input before it reaches the simulation.
var wizard: Wizard
var last_frame := 0
var last_event := 0
var active := false
var held := false
var _move := Vector2.ZERO
var _aim := Vector3.ZERO
var _received_at := 0
var _budget := 120.0

func _ready() -> void:
	process_physics_priority = -10

func frame(msg: Dictionary) -> void:
	var seq := int(msg.get("seq", 0))
	var move: Variant = msg.get("move")
	var aim: Variant = msg.get("aim")
	if seq <= last_frame or seq > last_frame + 600 or not move is Vector2 or not aim is Vector3:
		return
	if not move.is_finite() or not aim.is_finite() or aim.length() > 1000.0:
		return
	last_frame = seq
	_move = move.limit_length(1.0)
	_aim = aim
	held = bool(msg.get("hold", false))
	_received_at = Time.get_ticks_msec()

func event(msg: Dictionary) -> bool:
	var seq := int(msg.get("seq", 0))
	if seq <= last_event or seq > last_event + 256 or _budget < 1.0:
		return false
	last_event = seq
	_budget -= 1.0
	if not active or not is_instance_valid(wizard) or not wizard.alive:
		return false
	apply(wizard, msg)
	return true

static func apply(w: Wizard, msg: Dictionary, echo: bool = false) -> void:
	var slot := int(msg.get("slot", 0))
	match str(msg.get("action", "")):
		"prepare":
			if slot >= 0 and slot < 4:
				if Game.cast_mode == Game.CAST_CHANT or bool(msg.get("chant", false)) or bool(msg.get("assist", false)):
					w.begin_chant(slot, bool(msg.get("assist", false)), bool(msg.get("controller", false)))
				elif not echo:
					w.quickcast(slot)
		"chant_char":
			var c := str(msg.get("c", ""))
			if c.length() == 1 and c >= "A" and c <= "Z":
				w.chant_key(c)
		"chant_word": w.controller_chant_button(int(msg.get("word_index", -1)))
		"chant_backspace": w.chant_backspace()
		"chant_cancel":
			if w.primed_slot >= 0:
				w.discard_primed()
			else:
				w.cancel_chant()
		"unleash":
			if not echo:
				if w.assisted_chant:
					w.assist_release()
				elif w.chanting:
					w.chant_finish()
				elif w.primed_slot >= 0:
					# The guest clicked while its last snapshot still showed the
					# chant, but the host had already auto-primed: that click is
					# a release, not a lost input.
					var unleash_aim: Variant = msg.get("aim", null)
					if unleash_aim is Vector3 and unleash_aim.is_finite():
						w.set_aim_world(unleash_aim)
					w.release_primed()
		"release":
			var aim: Variant = msg.get("aim", null)
			if aim is Vector3 and aim.is_finite():
				w.set_aim_world(aim)
			if not echo:
				w.release_primed()
		"page_swap": w.swap_page()

func _physics_process(delta: float) -> void:
	_budget = minf(120.0, _budget + delta * 60.0)
	if not is_instance_valid(wizard):
		return
	if not active or Time.get_ticks_msec() - _received_at > 250:
		wizard.set_ai_move(Vector3.ZERO)
		return
	wizard.set_ai_move(Vector3(_move.x, 0.0, _move.y))
	wizard.set_aim_world(_aim)
