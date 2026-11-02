extends Node

## SHIFTCAST audio director (autoload: Audio).
##
## Owns the runtime side of the procedural soundtrack:
##   * one bank of AudioStreamWAVs, baked exactly once in _ready()
##   * a 12-voice SFX pool with per-shot pitch humanisation
##   * a baked synthetic chant voice bank (player + rival profiles)
##   * a 3-layer, phase-locked music bed driven by Game.round_index
##   * chant arpeggio, voice syllables + music ducking
##   * Music / SFX / UI / Voice buses and a hard limiter on Master
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
const VoiceSynthLib := preload("res://scripts/audio/voice_synth.gd")

const POOL_SIZE := 12
const VOICE_POOL_SIZE := 8
const MUSIC_LAYERS := 3
const CONFIG_PATH := "user://audio.cfg"
const VOICE_CUES: Array[String] = ["onset", "resolve", "fail", "cut"]
## Extra trim applied to every rival voice shot on top of the Voice bus gain.
const RIVAL_VOICE_TRIM_DB := -3.5

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

## VoiceSynth.VOICE_PLAYER / VOICE_RIVAL -> baked bank dictionary.
var _voices: Dictionary = {}
var _voice_pool: Array[AudioStreamPlayer] = []
var _voice_cursor := 0
var _voice_bytes := 0
var _voice_bake_ms := 0
var _rival_chanting := false

## Baked per-word callouts ("IGNA", "MITT") played in sequence on cast.
var _callouts: Dictionary = {}
var _callout_player: AudioStreamPlayer
var _callout_queue: Array[AudioStreamWAV] = []
var _callout_volume_db := 0.0
var _callout_pitch := 1.0
var _last_player_callout_ms := -1000

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
var _prepared := false
var _last_impact_ms := -1000
var _last_round_index := -999
var _last_player_score := -1
var _last_enemy_score := -1
var _game_node: Node
var _warm_started := false
var _save_queued := false

## instance_id -> tracking dictionary. Weak refs keep freed wizards cheap.
var _wizards: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	_load_master_volume()
	_build_pool()
	_build_voice_pool()
	_build_callout_player()
	_wire_ui()
	_last_round_index = _game_int("round_index", 0)
	_last_player_score = _game_int("player_score", 0)
	_last_enemy_score = _game_int("enemy_score", 0)


## Bakes the bank and starts the music. Called from the boot loading screen so
## the expensive synthesis is covered instead of freezing an interactive menu.
func prepare() -> void:
	if _prepared:
		return
	_prepared = true
	_bake_bank()
	_build_music_players()
	_start_music()
	print("AUDIO: %d streams ready (%d chant notes, %d music stems, %d voice streams, %d callouts)" % [
		_streams.size() + _notes.size() + _music_streams.size() + _voice_stream_count() + _callouts.size(),
		_notes.size(), _music_streams.size(), _voice_stream_count(), _callouts.size()
	])


func is_prepared() -> bool:
	return _prepared


func run_selftest() -> void:
	await _run_selftest()


func _process(_delta: float) -> void:
	_poll_wizards()
	_poll_game()


func _exit_tree() -> void:
	# Flush a pending volume change before the debounce timer dies with the tree.
	if _save_queued:
		_save_queued = false
		_save_master_volume()
	# Stop the dummy/driver playbacks and drop references so a quick quit (the
	# headless test path) does not report leaked audio objects.
	for p in _pool:
		p.stop()
		p.stream = null
	for p in _voice_pool:
		p.stop()
		p.stream = null
	if _callout_player != null:
		_callout_player.stop()
		_callout_player.stream = null
	for p in _music_players:
		p.stop()
		p.stream = null
	_streams.clear()
	_notes.clear()
	_music_streams.clear()
	_voices.clear()
	_callouts.clear()
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
	if _streams.is_empty():
		return
	var stream: AudioStreamWAV = _streams.get(sound_id, null)
	if stream == null:
		push_warning("AUDIO: unknown sound '%s'" % sound_id)
		return
	_play_stream(stream, bus, randf_range(0.94, 1.06), volume_db)


## Play one rung of the chant ladder. pitch_index rises with typed progress.
## The synthetic voice sings the rung; the original pluck doubles it quietly so
## the pitch skeleton still reads under the noise of a duel.
func play_note(pitch_index: int, is_player: bool = true) -> void:
	if _notes.is_empty():
		return
	var idx := clampi(pitch_index, 0, _notes.size() - 1)
	# The ladder is musical: only micro-humanise, never enough to blur the rise.
	_play_stream(_notes[idx], "SFX", randf_range(0.995, 1.005), -9.0)
	_play_voice_cue("ladder", is_player, pitch_index, 0.0)


## Fire a voice cue: "onset", "resolve", "fail" or "cut".
## is_player selects the profile; the rival is baked darker and mixed quieter.
func play_voice(cue: String, is_player: bool = true, volume_db: float = 0.0) -> void:
	_play_voice_cue(cue, is_player, 0, volume_db)


## Speak the spell's rune name as it is cast: element word, form word, then the
## modifier word. Streams are baked at startup; this only queues playback.
## The newest cast wins, so a fast duel never builds a backlog of names.
func play_spell_name(spell: SpellDef, is_player: bool = true, volume_db: float = 0.0) -> void:
	if spell == null or _callouts.is_empty() or _callout_player == null:
		return
	var words: Array[String] = [
		str(spell.element_data().get("word", "")),
		str(spell.form_data().get("word", "")),
	]
	if spell.modifier != "":
		words.append(str(spell.modifier_data().get("word", "")))
	var streams: Array[AudioStreamWAV] = []
	for word in words:
		var stream: AudioStreamWAV = _callouts.get(word.to_upper(), null)
		if stream != null:
			streams.append(stream)
	if streams.is_empty():
		return
	_callout_queue = streams
	_callout_volume_db = volume_db + (0.0 if is_player else RIVAL_VOICE_TRIM_DB)
	_callout_pitch = 1.0 if is_player else 0.80
	if is_player:
		_last_player_callout_ms = Time.get_ticks_msec()
	_callout_player.stop()
	_pump_callout()


func _pump_callout() -> void:
	if _callout_queue.is_empty() or _callout_player == null:
		return
	var stream: AudioStreamWAV = _callout_queue.pop_front()
	_callout_player.stream = stream
	_callout_player.pitch_scale = _callout_pitch * randf_range(0.995, 1.005)
	_callout_player.volume_db = _callout_volume_db
	_callout_player.play()


func _on_callout_finished() -> void:
	if _callout_queue.is_empty():
		return
	_pump_callout()


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
	_refresh_duck()


## The rival's chant only leans on the music (-3 dB); the player's own chant
## still gets the deeper -7 dB duck so typed letters stay legible.
func _set_rival_chanting(active: bool) -> void:
	if active == _rival_chanting:
		return
	_rival_chanting = active
	_refresh_duck()


func _refresh_duck() -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	var target_db := 0.0
	var cutoff := 20000.0
	var t := 0.4
	if _chanting:
		target_db = -7.0
		cutoff = 700.0
		t = 0.1
	elif _rival_chanting:
		target_db = -3.0
		cutoff = 1400.0
		t = 0.15
	_duck_tween.tween_method(_set_duck_db, _duck_db, target_db, t).set_trans(Tween.TRANS_SINE)
	if _music_lowpass != null:
		_duck_tween.parallel().tween_method(_set_lowpass_cutoff, _music_lowpass.cutoff_hz, cutoff, t + 0.05)


func play_cast(element: String) -> void:
	var id: String = CAST_IDS.get(element, "cast_arcane")
	play(id, "SFX")


func set_master_volume_db(db: float) -> void:
	_apply_master_db(db)
	# The pause-menu slider emits on every step. Debounce the config write so
	# dragging it does not hit the disk dozens of times per second.
	if _save_queued:
		return
	_save_queued = true
	await get_tree().create_timer(0.25).timeout
	_save_queued = false
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

	# Voice bank: two profiles, baked once. Everything below is playback only.
	var voice_t0 := Time.get_ticks_msec()
	_voices.clear()
	_voices[VoiceSynthLib.VOICE_PLAYER] = VoiceSynthLib.bake_voice(VoiceSynthLib.VOICE_PLAYER)
	_voices[VoiceSynthLib.VOICE_RIVAL] = VoiceSynthLib.bake_voice(VoiceSynthLib.VOICE_RIVAL)

	# Cast callouts: one short utterance per rune word. The rival reuses these
	# streams at a lower pitch, so only one set is baked.
	_callouts = VoiceSynthLib.bake_callouts(_callout_words())
	_voice_bake_ms = Time.get_ticks_msec() - voice_t0
	_voice_bytes = _voice_memory_bytes()

	var total_ms := Time.get_ticks_msec() - t0
	print("AUDIO: baked in %d ms (voice %d ms)" % [total_ms, _voice_bake_ms])
	print("AUDIO: voice bank %d streams + %d callouts, %d KiB" % [
		_voice_stream_count(), _callouts.size(), _voice_bytes / 1024
	])


func _callout_words() -> Array:
	var words: Array = []
	for id in SpellData.element_ids():
		words.append(str(SpellData.ELEMENTS[id].get("word", "")))
	for id in SpellData.form_ids():
		words.append(str(SpellData.FORMS[id].get("word", "")))
	for id in SpellData.modifier_ids():
		words.append(str(SpellData.MODIFIERS[id].get("word", "")))
	return words


func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%02d" % i
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)


func _build_voice_pool() -> void:
	# A separate pool keeps long vowel/stab streams from stealing impact and UI
	# one-shots, and gives the voice bank its own bus and gain staging.
	for i in VOICE_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "ChantVoice%02d" % i
		p.bus = "Voice"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_voice_pool.append(p)


func _build_callout_player() -> void:
	# One dedicated player: spell names are queued word-by-word and the newest
	# cast replaces the previous name instead of stacking with it.
	_callout_player = AudioStreamPlayer.new()
	_callout_player.name = "SpellCallout"
	_callout_player.bus = "Voice"
	_callout_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_callout_player.finished.connect(_on_callout_finished)
	add_child(_callout_player)


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
	for bus_name in ["Music", "SFX", "UI", "Voice"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -2.5)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), -3.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), -4.5)

	if not _bus_has_effect(0, "AudioEffectHardLimiter"):
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.6
		limiter.release = 0.12
		AudioServer.add_bus_effect(0, limiter)

	# Voice colour: soft overdrive for the "synthetic throat", then a gentle
	# lowpass to shave the buzz above the formant range. Both are runtime-only.
	var voice_idx := AudioServer.get_bus_index("Voice")
	if not _bus_has_effect(voice_idx, "AudioEffectDistortion"):
		var dist := AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		dist.pre_gain = -2.0
		dist.post_gain = -1.0
		dist.drive = 0.28
		AudioServer.add_bus_effect(voice_idx, dist)
	if not _bus_has_effect(voice_idx, "AudioEffectLowPassFilter"):
		var voice_lp := AudioEffectLowPassFilter.new()
		voice_lp.cutoff_hz = 7600.0
		voice_lp.resonance = 0.22
		AudioServer.add_bus_effect(voice_idx, voice_lp)

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
	if String(p.bus) != bus:
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


func _next_voice_player() -> AudioStreamPlayer:
	for p in _voice_pool:
		if not p.playing:
			return p
	var p := _voice_pool[_voice_cursor % _voice_pool.size()]
	_voice_cursor = (_voice_cursor + 1) % _voice_pool.size()
	return p


## internal cue player. "ladder" indexes the baked rung streams; the other
## cues are looked up by name. No stream is ever built here.
func _play_voice_cue(cue: String, is_player: bool, ladder_index: int, volume_db: float) -> void:
	var key := VoiceSynthLib.VOICE_PLAYER if is_player else VoiceSynthLib.VOICE_RIVAL
	var bank: Dictionary = _voices.get(key, {})
	if bank.is_empty():
		return
	var stream: AudioStreamWAV
	if cue == "ladder":
		var ladder: Array = bank.get("ladder", [])
		if ladder.is_empty():
			return
		var idx := clampi(ladder_index, 0, ladder.size() - 1)
		stream = ladder[idx]
	else:
		stream = bank.get(cue, null)
	if stream == null:
		push_warning("AUDIO: unknown voice cue '%s'" % cue)
		return
	if _voice_pool.is_empty():
		return
	var p := _next_voice_player()
	p.stream = stream
	p.pitch_scale = randf_range(0.997, 1.003)
	p.volume_db = volume_db + (0.0 if is_player else RIVAL_VOICE_TRIM_DB)
	p.play()


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

func register_wizard(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _wizards.has(id):
		return
	_wire_wizard(node, id)


func unregister_wizard(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if not _wizards.has(id):
		return
	var st: Dictionary = _wizards[id]
	if not bool(st.get("is_player", true)) and bool(st.get("was_chanting", false)):
		_set_rival_chanting(false)
	_wizards.erase(id)


## Poll only the wizards that registered themselves. The previous version
## rebuilt a group array and a seen-set every frame, even in menus.
func _poll_wizards() -> void:
	for id in _wizards.keys():
		var st: Dictionary = _wizards[id]
		var node: Node = st["ref"].get_ref()
		if node == null or not is_instance_valid(node):
			if not bool(st.get("is_player", true)) and bool(st.get("was_chanting", false)):
				_set_rival_chanting(false)
			_wizards.erase(id)
			continue
		_poll_wizard(node, st)


func _wire_wizard(node: Node, id: int) -> void:
	_connect_signal(node, "cast_fired", _on_cast_fired)
	_connect_signal(node, "damaged", _on_damaged)
	_connect_signal(node, "died", _on_died)
	_connect_signal(node, "chant_changed", _on_chant_changed)
	_connect_signal(node, "chant_interrupted", _on_chant_interrupted)
	_wizards[id] = {
		"ref": weakref(node),
		"is_player": bool(node.is_player),
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

	if not bool(node.chanting):
		st["chant_len"] = 0
		return

	var is_player := bool(node.is_player)
	var typos := int(node.chant_typos)
	if typos > int(st["typos"]):
		st["typos"] = typos
		st["chant_len"] = 0
		play("chant_fail", "SFX", -3.0 if is_player else -6.0)
		play_voice("fail", is_player, 0.0 if is_player else -3.0)
		return

	# Both duelists type real characters, so both climb the same ladder. The
	# rival's bank is transposed/formant-shifted at bake time, not in playback.
	var typed := String(node.chant_text).length()
	var known := int(st["chant_len"])
	if typed > known:
		# One note per frame. If the text jumps (AI catch-up or a lagged frame)
		# starting several voice+pluck streams at once reads as a stutter.
		play_note(typed - 1, is_player)
		st["chant_len"] = typed
	elif typed < known:
		st["chant_len"] = typed


func _on_cast_fired(caster: Node, spell: Variant, stats: Dictionary, _origin: Vector3, _direction: Vector3) -> void:
	var element := "arcane"
	var spell_def: SpellDef = null
	if spell is SpellDef:
		spell_def = spell
		element = spell_def.element
	var id := caster.get_instance_id()
	var resolved := false
	if _wizards.has(id):
		var st: Dictionary = _wizards[id]
		resolved = Time.get_ticks_msec() - int(st.get("ended_ms", -9999)) < 250
	if resolved:
		play("chant_resolve", "SFX", -4.0)
		play_voice("resolve", bool(caster.is_player), 0.0 if bool(caster.is_player) else -3.0)
	play_cast(element)
	if spell_def == null:
		return
	var is_player := bool(caster.is_player)
	if is_player:
		play_spell_name(spell_def, true, -1.0 if bool(stats.get("overcast", false)) else -3.0)
	elif Time.get_ticks_msec() - _last_player_callout_ms > 700:
		# Keep the rival's name audible but never talk over the player's cast.
		play_spell_name(spell_def, false, -3.0)


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
	var is_player := bool(wizard.is_player)
	if is_player:
		set_chanting(active)
	else:
		_set_rival_chanting(active)
	var id := wizard.get_instance_id()
	if not _wizards.has(id):
		return
	var st: Dictionary = _wizards[id]
	if active:
		# chant_changed(true) also fires when a typo resets the text, so only
		# the real 0 -> 1 transition gets the breath/onset.
		if not bool(st.get("was_chanting", false)):
			play_voice("onset", is_player, 0.0 if is_player else -2.5)
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
	var is_player := bool(wizard.is_player)
	play("chant_fail", "SFX", -3.0 if is_player else -6.0)
	play_voice("cut", is_player, 0.0 if is_player else -3.0)
	var id := wizard.get_instance_id()
	if _wizards.has(id):
		var st: Dictionary = _wizards[id]
		# Never let the following _on_chant_changed(false) read as a completed cast.
		st["ended_ms"] = -9999
		st["was_chanting"] = false
		st["chant_len"] = 0
	if is_player:
		set_chanting(false)
	else:
		_set_rival_chanting(false)


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
	if _game_node == null or not is_instance_valid(_game_node):
		_game_node = get_node_or_null("/root/Game")
	return _game_node


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

	# Warm the Voice bus graph too, so the first typed letter is not the
	# gesture that resumes a suspended WebAudio context on the voice path.
	var bank: Dictionary = _voices.get(VoiceSynthLib.VOICE_PLAYER, {})
	var onset: AudioStreamWAV = bank.get("onset", null)
	if onset != null:
		var v := AudioStreamPlayer.new()
		v.name = "UnlockVoice"
		v.stream = onset
		v.bus = "Voice"
		v.volume_db = -80.0
		add_child(v)
		v.finished.connect(v.queue_free)
		v.play()
	# Streams are baked, but some backends still initialize per-stream state on
	# first play. Push every spell/impact/voice stream through silently now.
	_warm_streams()


## One silent frame per baked stream. Front-load the sounds a first cast,
## impact, and callout need, then warm the long tail. This is the first-use
## cost the player would otherwise pay on their first element.
func _warm_streams() -> void:
	if _warm_started:
		return
	_warm_started = true
	var sfx := AudioStreamPlayer.new()
	sfx.name = "WarmSfx"
	sfx.bus = "SFX"
	sfx.volume_db = -80.0
	add_child(sfx)
	var vox := AudioStreamPlayer.new()
	vox.name = "WarmVoice"
	vox.bus = "Voice"
	vox.volume_db = -80.0
	add_child(vox)

	var warmed: Dictionary = {}
	for id in [
		"cast_fire", "cast_frost", "cast_storm", "cast_earth", "cast_arcane", "cast_void",
		"impact", "chant_resolve", "chant_fail",
	]:
		var stream: AudioStreamWAV = _streams.get(id, null)
		if stream == null:
			continue
		warmed[id] = true
		await _warm_stream(sfx, stream)

	for is_player in [true, false]:
		var key := VoiceSynthLib.VOICE_PLAYER if is_player else VoiceSynthLib.VOICE_RIVAL
		var bank: Dictionary = _voices.get(key, {})
		var onset: AudioStreamWAV = bank.get("onset", null)
		await _warm_stream(vox, onset)

	for word in _callouts:
		await _warm_stream(vox, _callouts[word])
	for note in _notes:
		await _warm_stream(sfx, note)
	for key in _voices:
		var bank: Dictionary = _voices[key]
		var ladder: Array = bank.get("ladder", [])
		for stream in ladder:
			if stream is AudioStreamWAV:
				await _warm_stream(vox, stream)

	for id in SOUND_IDS:
		if warmed.has(id):
			continue
		await _warm_stream(sfx, _streams.get(id, null))
	for key in _voices:
		var bank: Dictionary = _voices[key]
		for cue in VOICE_CUES:
			await _warm_stream(vox, bank.get(cue, null))

	sfx.stop()
	sfx.stream = null
	sfx.queue_free()
	vox.stop()
	vox.stream = null
	vox.queue_free()


func _warm_stream(player: AudioStreamPlayer, stream: AudioStreamWAV) -> void:
	if stream == null or not is_instance_valid(player):
		return
	player.stream = stream
	player.play()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Debug: godot --headless --path . -- --audio-selftest
# ---------------------------------------------------------------------------

func _run_selftest() -> void:
	await get_tree().process_frame
	var failures := 0
	var baked_before := SynthLib.baked_count

	print("AUDIO TEST: %d streams, %d chant notes, %d music stems, %d voice streams" % [
		_streams.size(), _notes.size(), _music_streams.size(), _voice_stream_count()
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

	# Voice bank: format, nonzero RMS, sane/never-clipped peaks, rising ladder.
	var voice_streams := _voice_streams()
	var voice_rms_min := 1.0
	var voice_rms_max := 0.0
	var voice_rms_sum := 0.0
	var voice_peak_max := 0.0
	var voice_bytes := 0
	var voice_bad := 0
	for stream in voice_streams:
		var ok := _validate(stream, false)
		var rms := _stream_rms(stream)
		var peak := _stream_peak(stream)
		voice_rms_min = minf(voice_rms_min, rms)
		voice_rms_max = maxf(voice_rms_max, rms)
		voice_rms_sum += rms
		voice_peak_max = maxf(voice_peak_max, peak)
		if stream != null:
			voice_bytes += stream.data.size()
		if not ok or rms < 0.02 or peak < 0.20 or peak > 0.995:
			print("  BAD voice stream len=%5.2fs rms=%5.3f peak=%4.2f" % [_stream_len(stream), rms, peak])
			voice_bad += 1
			failures += 1
	var voice_avg := voice_rms_sum / maxf(1.0, float(voice_streams.size()))
	var voice_status := "ok" if voice_bad == 0 else "BAD"
	print("  voice bank+callouts %d streams %4.1f KiB bake=%d ms rms=%4.3f..%4.3f avg=%4.3f peak=%4.2f %s" % [
		voice_streams.size(), float(voice_bytes) / 1024.0, _voice_bake_ms,
		voice_rms_min, voice_rms_max, voice_avg, voice_peak_max, voice_status,
	])
	var expected_voice := (VoiceSynthLib.LADDER_STEPS + 4) * 2 + _callouts.size()
	if voice_streams.size() != expected_voice:
		print("  BAD voice stream count %d (expected %d)" % [voice_streams.size(), expected_voice])
		failures += 1
	print("  callout bank   %d rune words baked" % _callouts.size())
	for i in range(1, VoiceSynthLib.LADDER_STEPS):
		if VoiceSynthLib.ladder_frequency(i) <= VoiceSynthLib.ladder_frequency(i - 1):
			print("  BAD voice ladder is not rising at %d" % i)
			failures += 1
	print("  voice ladder  %4.1f Hz -> %4.1f Hz (%d rungs, vowels A-E-I-O-U)" % [
		VoiceSynthLib.ladder_frequency(0),
		VoiceSynthLib.ladder_frequency(VoiceSynthLib.MAX_LADDER_INDEX),
		VoiceSynthLib.LADDER_STEPS,
	])
	var voice_bus := AudioServer.get_bus_index("Voice")
	if voice_bus == -1:
		print("  BAD Voice bus is missing")
		failures += 1
	elif not _bus_has_effect(voice_bus, "AudioEffectDistortion"):
		print("  BAD Voice bus has no distortion")
		failures += 1
	else:
		print("  voice bus      %.1f dB, %d effects (distortion + lowpass) ok" % [
			AudioServer.get_bus_volume_db(voice_bus), AudioServer.get_bus_effect_count(voice_bus)
		])

	# Exercise the runtime path through the real pool and bus graph.
	for id in SOUND_IDS:
		play(id)
	for i in _notes.size():
		play_note(i)
	for i in VoiceSynthLib.LADDER_STEPS:
		play_note(i, true)
		play_note(i, false)
	for cue in VOICE_CUES:
		play_voice(cue, true)
		play_voice(cue, false)
	play_spell_name(SpellDef.new("fire", "bolt", "track"), true)
	play_spell_name(SpellDef.new("fire", "bolt", "track"), false)
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
	for p in _voice_pool:
		p.stop()
		p.stream = null
	if _callout_player != null:
		_callout_player.stop()
		_callout_player.stream = null
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


func _voice_streams() -> Array[AudioStreamWAV]:
	var out: Array[AudioStreamWAV] = []
	for key in _voices.keys():
		var bank: Dictionary = _voices[key]
		var onset: AudioStreamWAV = bank.get("onset", null)
		out.append(onset)
		var ladder: Array = bank.get("ladder", [])
		for item in ladder:
			var stream: AudioStreamWAV = item
			out.append(stream)
		var resolve: AudioStreamWAV = bank.get("resolve", null)
		var fail: AudioStreamWAV = bank.get("fail", null)
		var cut: AudioStreamWAV = bank.get("cut", null)
		out.append(resolve)
		out.append(fail)
		out.append(cut)
	for word in _callouts:
		out.append(_callouts[word])
	return out


func _voice_stream_count() -> int:
	var count := 0
	for key in _voices.keys():
		var bank: Dictionary = _voices[key]
		var ladder: Array = bank.get("ladder", [])
		count += 4 + ladder.size()
	return count


func _voice_memory_bytes() -> int:
	var total := 0
	for stream in _voice_streams():
		if stream != null:
			total += stream.data.size()
	return total


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


func _stream_rms(stream: AudioStreamWAV) -> float:
	if stream == null:
		return 0.0
	var sum := 0.0
	var count := 0
	var data := stream.data
	var i := 0
	while i + 1 < data.size():
		var v := float(data.decode_s16(i)) / 32767.0
		sum += v * v
		count += 1
		i += 2
	if count == 0:
		return 0.0
	return sqrt(sum / float(count))
