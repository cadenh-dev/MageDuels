extends Node

## SHIFTCAST audio director (autoload: Audio).
##
## Owns the runtime side of the procedural soundtrack:
##   * one bank of AudioStreamWAVs, baked exactly once in _ready()
##   * a 12-voice SFX pool with per-shot pitch humanisation
##   * a 3-layer, phase-locked music bed driven by Game.round_index
##   * chant arpeggio + music ducking
##   * Music / SFX / UI buses and a hard limiter on Master
##   * master volume persisted to user://audio.cfg
##
## Gameplay code never has to call this: the autoload watches the "wizards"
## group and wires itself to the signals that already exist (cast_fired,
## damaged, died, chant_changed), plus polls chant text / pages / scores.
## Public API is still available for explicit calls: play(), play_note(),
## set_intensity(), set_chanting(), set_master_volume_db().
##
## Headless runs bake normally and play through the dummy audio driver, so the
## test harness stays silent and error-free.

const SynthLib := preload("res://scripts/audio/synth.gd")

const POOL_SIZE := 12
const MUSIC_LAYERS := 3
const CONFIG_PATH := "user://audio.cfg"
const WIZARD_GROUP := "wizards"

const SOUND_IDS: Array[String] = [
	"cast_fire", "cast_frost", "cast_storm", "cast_earth", "cast_arcane", "cast_void",
	"impact", "page_shift", "chant_fail", "chant_resolve",
	"round_win", "round_lose", "ui_click", "death",
]

const CAST_IDS := {
	"fire": "cast_fire",
	"frost": "cast_frost",
	"storm": "cast_storm",
	"earth": "cast_earth",
	"arcane": "cast_arcane",
	"void": "cast_void",
}

## Per-intensity (0..3) target gain for [pad, pulse, lead].
const MUSIC_LEVEL_DB: Array = [
	[-6.0, -80.0, -80.0],
	[-4.5, -9.0, -80.0],
	[-3.5, -7.0, -8.0],
	[-3.0, -6.0, -5.0],
]

var _streams: Dictionary = {}
var _notes: Array[AudioStreamWAV] = []
var _music_streams: Array[AudioStreamWAV] = []

var _pool: Array[AudioStreamPlayer] = []
var _pool_cursor := 0
var _music_players: Array[AudioStreamPlayer] = []
var _music_started := false
var _layer_db: Array[float] = [-80.0, -80.0, -80.0]
var _layer_tweens: Array = [null, null, null]
var _duck_db := 0.0
var _duck_tween: Tween
var _music_lowpass: AudioEffectLowPassFilter
var _intensity := -1
var _chanting := false

var _master_db := 0.0
var _unlocked := false
var _last_impact_ms := -1000
var _last_round_index := -999
var _last_player_score := -1
var _last_enemy_score := -1

## instance_id -> tracking dictionary. Weak refs keep freed wizards cheap.
var _wizards: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	_load_master_volume()
	_bake_bank()
	_build_pool()
	_build_music_players()
	_wire_ui()
	_start_music()
	_last_round_index = _game_int("round_index", 0)
	_last_player_score = _game_int("player_score", 0)
	_last_enemy_score = _game_int("enemy_score", 0)
	print("AUDIO: %d streams ready (%d chant notes, %d music stems)" % [
		_streams.size() + _notes.size() + _music_streams.size(), _notes.size(), _music_streams.size()
	])
	if "--audio-selftest" in OS.get_cmdline_user_args():
		_run_selftest.call_deferred()


func _process(_delta: float) -> void:
	_scan_wizards()
	_poll_game()


func _exit_tree() -> void:
	# Stop the dummy/driver playbacks and drop references so a quick quit (the
	# headless test path) does not report leaked audio objects.
	for p in _pool:
		p.stop()
		p.stream = null
	for p in _music_players:
		p.stop()
		p.stream = null
	_streams.clear()
	_notes.clear()
	_music_streams.clear()
	# AudioServer releases a stopped playback on the audio thread. Without a
	# short drain the last few sounds are still referenced when ObjectDB is
	# checked at shutdown, which prints a spurious "instances were leaked"
	# warning from the headless test run.
	OS.delay_msec(100)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Fire a one-shot from the baked bank. Unknown ids are ignored with a warning.
func play(sound_id: String, bus: String = "SFX", volume_db: float = 0.0) -> void:
	var stream: AudioStreamWAV = _streams.get(sound_id, null)
	if stream == null:
		push_warning("AUDIO: unknown sound '%s'" % sound_id)
		return
	_play_stream(stream, bus, randf_range(0.94, 1.06), volume_db)


## Play one rung of the chant ladder. pitch_index rises with typed progress.
func play_note(pitch_index: int) -> void:
	if _notes.is_empty():
		return
	var idx := clampi(pitch_index, 0, _notes.size() - 1)
	# The ladder is musical: only micro-humanise, never enough to blur the rise.
	_play_stream(_notes[idx], "SFX", randf_range(0.995, 1.005), 0.0)


## Choose a music tier. 0 = pad, 1 = +pulse, 2 = +lead, 3 = all-out.
func set_intensity(level: int) -> void:
	var lvl := clampi(level, 0, 3)
	if lvl == _intensity:
		return
	_intensity = lvl
	for layer in MUSIC_LAYERS:
		_tween_layer(layer, float(MUSIC_LEVEL_DB[lvl][layer]), 0.8)


## Duck the music while the player chants. Safe to call repeatedly.
func set_chanting(active: bool) -> void:
	if active == _chanting:
		return
	_chanting = active
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	var target_db := -7.0 if active else 0.0
	var t := 0.1 if active else 0.4
	_duck_tween.tween_method(_set_duck_db, _duck_db, target_db, t).set_trans(Tween.TRANS_SINE)
	if _music_lowpass != null:
		var cutoff := 700.0 if active else 20000.0
		_duck_tween.parallel().tween_method(_set_lowpass_cutoff, _music_lowpass.cutoff_hz, cutoff, t + 0.05)


func play_cast(element: String) -> void:
	var id: String = CAST_IDS.get(element, "cast_arcane")
	play(id, "SFX")


func set_master_volume_db(db: float) -> void:
	_apply_master_db(db)
	_save_master_volume()


func get_master_volume_db() -> float:
	return _master_db


func start_music() -> void:
	_start_music()


# ---------------------------------------------------------------------------
# Bank bake (the only place synthesis happens)
# ---------------------------------------------------------------------------

func _bake_bank() -> void:
	var t0 := Time.get_ticks_msec()
	_streams = {
		"cast_fire": SynthLib.cast_fire(),
		"cast_frost": SynthLib.cast_frost(),
		"cast_storm": SynthLib.cast_storm(),
		"cast_earth": SynthLib.cast_earth(),
		"cast_arcane": SynthLib.cast_arcane(),
		"cast_void": SynthLib.cast_void(),
		"impact": SynthLib.impact(),
		"page_shift": SynthLib.page_shift(),
		"chant_fail": SynthLib.chant_fail(),
		"chant_resolve": SynthLib.chant_resolve(),
		"round_win": SynthLib.round_win(),
		"round_lose": SynthLib.round_lose(),
		"ui_click": SynthLib.ui_click(),
		"death": SynthLib.death(),
	}
	_notes.clear()
	for i in SynthLib.MAX_NOTE_INDEX + 1:
		_notes.append(SynthLib.chant_pluck(i))
	_music_streams.clear()
	for layer in MUSIC_LAYERS:
		_music_streams.append(SynthLib.music_layer(layer))
	print("AUDIO: baked in %d ms" % (Time.get_ticks_msec() - t0))


func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%02d" % i
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)


func _build_music_players() -> void:
	for i in MUSIC_LAYERS:
		var p := AudioStreamPlayer.new()
		p.name = "MusicStem%d" % i
		p.stream = _music_streams[i]
		p.bus = "Music"
		p.volume_db = -80.0
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_music_players.append(p)


# ---------------------------------------------------------------------------
# Buses and volume
# ---------------------------------------------------------------------------

func _build_buses() -> void:
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -2.5)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), -3.0)

	if not _bus_has_effect(0, "AudioEffectHardLimiter"):
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.6
		limiter.release = 0.12
		AudioServer.add_bus_effect(0, limiter)

	var music_idx := AudioServer.get_bus_index("Music")
	for i in AudioServer.get_bus_effect_count(music_idx):
		var effect: AudioEffect = AudioServer.get_bus_effect(music_idx, i)
		if effect is AudioEffectLowPassFilter:
			_music_lowpass = effect
			break
	if _music_lowpass == null:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		lp.resonance = 0.3
		AudioServer.add_bus_effect(music_idx, lp)
		_music_lowpass = lp


func _bus_has_effect(bus_idx: int, class_name_str: String) -> bool:
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i).get_class() == class_name_str:
			return true
	return false


func _load_master_volume() -> void:
	var cfg := ConfigFile.new()
	var db := 0.0
	if cfg.load(CONFIG_PATH) == OK:
		db = float(cfg.get_value("audio", "master_db", 0.0))
	else:
		var game := _game()
		if game != null:
			db = float(game.master_volume_db)
	_apply_master_db(db)


func _apply_master_db(db: float) -> void:
	_master_db = clampf(db, -40.0, 6.0)
	AudioServer.set_bus_volume_db(0, _master_db)
	var game := _game()
	if game != null:
		game.master_volume_db = _master_db


func _save_master_volume() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_db", _master_db)
	cfg.save(CONFIG_PATH)


# ---------------------------------------------------------------------------
# Voices and music mixing
# ---------------------------------------------------------------------------

func _play_stream(stream: AudioStreamWAV, bus: String, pitch: float, volume_db: float) -> void:
	var p := _next_player()
	p.stream = stream
	p.bus = bus
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func _next_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	var p := _pool[_pool_cursor % _pool.size()]
	_pool_cursor = (_pool_cursor + 1) % _pool.size()
	return p


func _start_music() -> void:
	if _music_started or _music_players.is_empty():
		return
	_music_started = true
	if _intensity < 0:
		_intensity = clampi(_game_int("round_index", 0), 0, 3)
	for layer in MUSIC_LAYERS:
		_layer_db[layer] = float(MUSIC_LEVEL_DB[_intensity][layer])
	_push_music_volumes()
	# Every stem starts on the same call so they remain sample-locked forever.
	for p in _music_players:
		p.play(0.0)


func _tween_layer(layer: int, target_db: float, duration: float) -> void:
	var old: Tween = _layer_tweens[layer]
	if old != null and old.is_valid():
		old.kill()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_method(_set_layer_db.bind(layer), _layer_db[layer], target_db, duration)
	_layer_tweens[layer] = tw


func _set_layer_db(value: float, layer: int) -> void:
	_layer_db[layer] = value
	_push_music_volumes()


func _set_duck_db(value: float) -> void:
	_duck_db = value
	_push_music_volumes()


func _push_music_volumes() -> void:
	for i in _music_players.size():
		_music_players[i].volume_db = _layer_db[i] + _duck_db


func _set_lowpass_cutoff(value: float) -> void:
	if _music_lowpass != null:
		_music_lowpass.cutoff_hz = clampf(value, 40.0, 20000.0)


# ---------------------------------------------------------------------------
# Existing-signal integration
# ---------------------------------------------------------------------------

func _scan_wizards() -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group(WIZARD_GROUP):
		var id := node.get_instance_id()
		seen[id] = true
		if not _wizards.has(id):
			_wire_wizard(node, id)
		var st: Dictionary = _wizards[id]
		_poll_wizard(node, st)
	for id in _wizards.keys():
		if not seen.has(id):
			_wizards.erase(id)


func _wire_wizard(node: Node, id: int) -> void:
	_connect_signal(node, "cast_fired", _on_cast_fired)
	_connect_signal(node, "damaged", _on_damaged)
	_connect_signal(node, "died", _on_died)
	_connect_signal(node, "chant_changed", _on_chant_changed)
	_connect_signal(node, "chant_interrupted", _on_chant_interrupted)
	_wizards[id] = {
		"ref": weakref(node),
		"page": int(node.page),
		"page_ready": false,
		"chant_len": 0,
		"typos": int(node.chant_typos),
		"was_chanting": false,
		"ended_ms": -9999,
	}


func _connect_signal(node: Node, signal_name: String, handler: Callable) -> void:
	if node.has_signal(signal_name) and not node.is_connected(signal_name, handler):
		node.connect(signal_name, handler)


func _poll_wizard(node: Node, st: Dictionary) -> void:
	if not is_instance_valid(node):
		return
	var page := int(node.page)
	if page != int(st["page"]):
		st["page"] = page
		if bool(st["page_ready"]):
			play("page_shift", "SFX", -3.0)
	else:
		st["page_ready"] = true

	if not bool(node.is_player):
		return

	if not bool(node.chanting):
		st["chant_len"] = 0
		return

	var typos := int(node.chant_typos)
	if typos > int(st["typos"]):
		st["typos"] = typos
		st["chant_len"] = 0
		play("chant_fail")
		return

	var typed := String(node.chant_text).length()
	var known := int(st["chant_len"])
	if typed > known:
		for i in range(known, typed):
			play_note(i)
		st["chant_len"] = typed
	elif typed < known:
		st["chant_len"] = typed


func _on_cast_fired(caster: Node, spell: Variant, _stats: Dictionary, _origin: Vector3, _direction: Vector3) -> void:
	var element := "arcane"
	if spell != null:
		element = str(spell.element)
	var id := caster.get_instance_id()
	var resolved := false
	if _wizards.has(id):
		var st: Dictionary = _wizards[id]
		resolved = Time.get_ticks_msec() - int(st.get("ended_ms", -9999)) < 250
	if resolved:
		play("chant_resolve", "SFX", -4.0)
	play_cast(element)


func _on_damaged(_wizard: Node, amount: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_impact_ms < 40:
		return
	_last_impact_ms = now
	var vol := clampf(linear_to_db(maxf(amount, 1.0) / 10.0), -14.0, 2.0)
	play("impact", "SFX", vol)


func _on_died(_wizard: Node) -> void:
	play("death")


func _on_chant_changed(wizard: Node, active: bool) -> void:
	if not is_instance_valid(wizard):
		return
	if bool(wizard.is_player):
		set_chanting(active)
	var id := wizard.get_instance_id()
	if not _wizards.has(id):
		return
	var st: Dictionary = _wizards[id]
	if active:
		st["was_chanting"] = true
		st["chant_len"] = 0
		st["typos"] = int(wizard.chant_typos)
	else:
		# A successful chant clears its text before cast_fired arrives. Mark the
		# time; _on_cast_fired turns it into the resolution chord.
		if bool(st.get("was_chanting", false)) and String(wizard.chant_text).is_empty():
			st["ended_ms"] = Time.get_ticks_msec()
		st["was_chanting"] = false
		st["chant_len"] = 0


func _on_chant_interrupted(wizard: Node) -> void:
	if not is_instance_valid(wizard):
		return
	play("chant_fail", "SFX", -3.0)
	var id := wizard.get_instance_id()
	if _wizards.has(id):
		var st: Dictionary = _wizards[id]
		# Never let the following _on_chant_changed(false) read as a completed cast.
		st["ended_ms"] = -9999
		st["was_chanting"] = false
		st["chant_len"] = 0
	if bool(wizard.is_player):
		set_chanting(false)


func _poll_game() -> void:
	var round_index := _game_int("round_index", 0)
	if round_index != _last_round_index:
		_last_round_index = round_index
		set_intensity(round_index)

	var player_score := _game_int("player_score", 0)
	var enemy_score := _game_int("enemy_score", 0)
	if _last_player_score >= 0:
		if player_score > _last_player_score:
			play("round_win")
		elif enemy_score > _last_enemy_score:
			play("round_lose")
	_last_player_score = player_score
	_last_enemy_score = enemy_score


func _game() -> Node:
	return get_node_or_null("/root/Game")


func _game_int(property: String, fallback: int) -> int:
	var game := _game()
	if game == null:
		return fallback
	return int(game.get(property))


# ---------------------------------------------------------------------------
# UI clicks and browser audio unlock
# ---------------------------------------------------------------------------

func _wire_ui() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if not button.pressed.is_connected(_on_ui_pressed):
			button.pressed.connect(_on_ui_pressed)


func _on_ui_pressed() -> void:
	play("ui_click", "UI")


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	var gesture := false
	if event is InputEventKey:
		var key := event as InputEventKey
		gesture = key.pressed and not key.echo
	elif event is InputEventMouseButton:
		gesture = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		gesture = (event as InputEventScreenTouch).pressed
	if gesture:
		_unlock_audio()


## Web exports only allow audio after a user gesture. Playing a silent voice on
## the first key/click warms the WebAudio graph; other platforms no-op quietly.
func _unlock_audio() -> void:
	_unlocked = true
	var p := AudioStreamPlayer.new()
	p.name = "Unlock"
	p.stream = _streams.get("ui_click", null)
	p.bus = "SFX"
	p.volume_db = -80.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------------------
# Debug: godot --headless --path . -- --audio-selftest
# ---------------------------------------------------------------------------

func _run_selftest() -> void:
	await get_tree().process_frame
	var failures := 0
	var baked_before := SynthLib.baked_count

	print("AUDIO TEST: %d streams, %d chant notes, %d music stems" % [
		_streams.size(), _notes.size(), _music_streams.size()
	])

	for id in SOUND_IDS:
		var stream: AudioStreamWAV = _streams.get(id, null)
		var ok := _validate(stream, false)
		if not ok:
			failures += 1
		var peak := _stream_peak(stream)
		print("  %-14s len=%5.2fs peak=%4.2f %s" % [id, _stream_len(stream), peak, "ok" if ok else "BAD"])

	for i in _notes.size():
		var stream: AudioStreamWAV = _notes[i]
		var ok := _validate(stream, false)
		if not ok:
			failures += 1
	for i in range(1, _notes.size()):
		if SynthLib.note_frequency(i) <= SynthLib.note_frequency(i - 1):
			print("  BAD chant ladder is not rising at %d" % i)
			failures += 1
	print("  chant ladder %4.1f Hz -> %4.1f Hz (%d notes)" % [
		SynthLib.note_frequency(0), SynthLib.note_frequency(_notes.size() - 1), _notes.size()
	])

	for layer in _music_streams.size():
		var stream: AudioStreamWAV = _music_streams[layer]
		var ok := _validate(stream, true)
		if not ok:
			failures += 1
		var seam := maxf(absf(_stream_sample(stream, 0)), absf(_stream_sample(stream, stream.data.size() / 2 - 1)))
		print("  music[%d]       len=%5.2fs peak=%4.2f loop=%s seam=%4.3f %s" % [
			layer, _stream_len(stream), _stream_peak(stream),
			"forward" if stream.loop_mode == AudioStreamWAV.LOOP_FORWARD else "none",
			seam, "ok" if ok else "BAD",
		])
		if absf(_stream_len(stream) - SynthLib.MUSIC_SECONDS) > 0.01:
			print("  BAD music[%d] length mismatch" % layer)
			failures += 1
		if seam > 0.05:
			print("  BAD music[%d] loop seam clicks (%.3f)" % [layer, seam])
			failures += 1
		if layer > 0 and stream.data.size() != _music_streams[0].data.size():
			print("  BAD music[%d] is not phase-locked (stem length differs)" % layer)
			failures += 1

	# Exercise the runtime path through the real pool and bus graph.
	for id in SOUND_IDS:
		play(id)
	for i in _notes.size():
		play_note(i)
	set_intensity(3)
	set_chanting(true)
	await get_tree().create_timer(0.2).timeout
	set_chanting(false)

	if SynthLib.baked_count != baked_before:
		print("  BAD synthesis happened after _ready (%d -> %d)" % [baked_before, SynthLib.baked_count])
		failures += 1
	else:
		print("  no synthesis after _ready (%d baked streams)" % baked_before)

	# Release active playbacks before quitting so the engine does not report
	# leak warnings from the dummy audio driver.
	for p in _pool:
		p.stop()
		p.stream = null
	for p in _music_players:
		p.stop()
		p.stream = null
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	for tw in _layer_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	# Give the audio server thread a few mixes to release the playbacks that
	# stopped above; quitting mid-mix otherwise reports them as leaked.
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout

	print("AUDIO TEST: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _validate(stream: AudioStreamWAV, loop: bool) -> bool:
	if stream == null:
		return false
	if stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return false
	if stream.mix_rate != SynthLib.RATE:
		return false
	if stream.stereo:
		return false
	if stream.data.size() < 32 or stream.data.size() % 2 != 0:
		return false
	if loop and stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		return false
	if loop and stream.loop_end <= 0:
		return false
	return true


func _stream_len(stream: AudioStreamWAV) -> float:
	if stream == null:
		return 0.0
	return float(stream.data.size()) / 2.0 / float(SynthLib.RATE)


func _stream_sample(stream: AudioStreamWAV, sample_index: int) -> float:
	if stream == null:
		return 0.0
	var byte_index := sample_index * 2
	if byte_index < 0 or byte_index + 1 >= stream.data.size():
		return 0.0
	return float(stream.data.decode_s16(byte_index)) / 32767.0


func _stream_peak(stream: AudioStreamWAV) -> float:
	if stream == null:
		return 0.0
	var peak := 0
	var i := 0
	var data := stream.data
	while i + 1 < data.size():
		peak = maxi(peak, absi(int(data.decode_s16(i))))
		i += 2
	return float(peak) / 32767.0
