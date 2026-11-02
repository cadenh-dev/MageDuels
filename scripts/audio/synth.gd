class_name Synth
extends RefCounted

## Procedural audio bakery for SHIFTCAST.
##
## Everything here is deterministic, offline synthesis: callers get a finished
## AudioStreamWAV back. Nothing in this file runs during gameplay after the
## Audio autoload's _ready() has baked the bank once.
##
## Output format is locked: 22050 Hz, mono, 16-bit PCM. That keeps the browser
## build small and makes every bake reproducible across platforms.

const RATE := 22050
## Music is synthesised at half rate then band-limited back up to 22 050 Hz.
## The bed lives below 3 kHz, so this halves startup bake time with no audible
## loss while every delivered stream still meets the required format.
const HALF_RATE := RATE / 2
## Pad and pulse sit below 1.5 kHz, so they bake at a third of the rate and are
## sample-doubled on the way out. The lead keeps the higher half-rate source.
const MUSIC_LOW_RATE := RATE / 3
const MUSIC_BPM := 112.0
const MUSIC_BARS := 8
const MUSIC_BEATS_PER_BAR := 4
const BEAT_SECONDS := 60.0 / MUSIC_BPM
const BAR_SECONDS := BEAT_SECONDS * MUSIC_BEATS_PER_BAR
const MUSIC_SECONDS := BAR_SECONDS * MUSIC_BARS
const MUSIC_LAYERS := 3

## A minor pentatonic, the chant ladder. Index 0 is A3.
const PENTATONIC: Array[int] = [0, 3, 5, 7, 10]
const MAX_NOTE_INDEX := 11

# How many streams have been encoded since launch. The Audio autoload uses this
# to prove nothing is synthesised after startup.
static var baked_count := 0

const _BAR_ROOTS: Array[float] = [110.0, 87.31, 130.81, 98.0, 110.0, 87.31, 146.83, 82.41]
const _BAR_CHORDS: Array = [
	[0, 3, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7],
	[0, 3, 7], [0, 4, 7], [0, 3, 7], [0, 4, 7],
]
const _LEAD_LINE: Array = [
	[0, 3, 7, 5],
	[3, 0, -2, 0],
	[7, 10, 7, 3],
	[5, 7, 5, 2],
	[0, 3, 7, 12],
	[10, 7, 3, 5],
	[8, 7, 5, 3],
	[2, 5, 7, 10],
]


# ---------------------------------------------------------------------------
# Public bakes
# ---------------------------------------------------------------------------

static func cast_fire() -> AudioStreamWAV:
	var buf := _buffer(0.46)
	var rng := _rng(11)
	var phase := 0.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := 70.0 + 250.0 * exp(-t * 6.0)
		phase += TAU * f / RATE
		var body := (sin(phase) + 0.45 * sin(phase * 2.01)) * exp(-t * 5.0) * 0.62
		var n := _noise(rng)
		lp += (n - lp) * 0.35
		var burst := n * exp(-t * 17.0) * 0.45 + lp * exp(-t * 7.0) * 0.55
		var crackle := 0.0
		if rng.randf() < 0.016:
			crackle = n * 0.8
		buf[i] = body + burst + crackle
	return _finalize(buf, 0.86, false, 0.006)


static func cast_frost() -> AudioStreamWAV:
	var buf := _buffer(0.58)
	var rng := _rng(23)
	var p1 := 0.0
	var p2 := 0.0
	var prev := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f1 := 620.0 + 1450.0 * exp(-t * 5.2)
		p1 += TAU * f1 / RATE
		p2 += TAU * f1 * 2.51 / RATE
		var env := minf(1.0, t / 0.004) * exp(-t * 5.4)
		var shimmer := sin(p1) * 0.46 + sin(p2) * 0.24 * exp(-t * 2.4)
		var n := _noise(rng)
		var high := n - prev
		prev = n
		var chorus := 1.0 + 0.16 * sin(TAU * 7.0 * t)
		buf[i] = (shimmer + high * 0.16) * env * chorus
	return _finalize(buf, 0.84, false, 0.008)


static func cast_storm() -> AudioStreamWAV:
	var buf := _buffer(0.4)
	var rng := _rng(37)
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var gate := 1.0 if sin(TAU * 58.0 * t) > 0.0 else 0.28
		var f := 140.0 + 980.0 * exp(-t * 10.0)
		phase += TAU * f / RATE
		var zap := (sin(phase) + 0.5 * sin(phase * 3.0)) * gate * exp(-t * 6.5)
		var n := _noise(rng)
		var crack := n * exp(-t * 24.0) * 0.42
		if t < 0.035:
			crack += n * 0.55
		buf[i] = zap * 0.66 + crack
	return _finalize(buf, 0.86, false, 0.006)


static func cast_earth() -> AudioStreamWAV:
	var buf := _buffer(0.58)
	var rng := _rng(41)
	var phase := 0.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := 42.0 + 110.0 * exp(-t * 8.0)
		phase += TAU * f / RATE
		var n := _noise(rng)
		lp += (n - lp) * 0.055
		var thud := (sin(phase) + 0.35 * sin(phase * 0.5)) * exp(-t * 4.2) * 0.85
		var rumble := lp * exp(-t * 3.6) * 1.5
		var click := n * exp(-t * 90.0) * 0.5
		buf[i] = thud + rumble + click
	return _finalize(buf, 0.88, false, 0.008)


static func cast_arcane() -> AudioStreamWAV:
	var buf := _buffer(0.64)
	var notes := [440.0, 554.37, 659.25, 880.0]
	var onset := [0.0, 0.075, 0.15, 0.225]
	for i in notes.size():
		_add_bell(buf, int(onset[i] * RATE), 0.56, notes[i], 0.42, 3.1)
	var rng := _rng(43)
	var n := 0.0
	var hi := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var x := _noise(rng)
		var hp := x - n
		n = x
		hi += (hp - hi) * 0.2
		buf[i] += hi * sin(PI * clampf(t / 0.64, 0.0, 1.0)) * 0.12
	return _finalize(buf, 0.84, false, 0.01)


static func cast_void() -> AudioStreamWAV:
	var buf := _buffer(0.68)
	var rng := _rng(53)
	var p1 := 0.0
	var p2 := 0.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := 62.0 + 58.0 * exp(-t * 3.0)
		p1 += TAU * f / RATE
		p2 += TAU * f * 1.06 / RATE
		var swell := pow(clampf(t / 0.68, 0.0, 1.0), 2.2)
		var tone := (sin(p1) + 0.5 * sin(p2)) * swell * 0.72
		var n := _noise(rng)
		lp += (n - lp) * 0.04
		var air := lp * swell * 1.3
		buf[i] = tone + air
	return _finalize(buf, 0.82, false, 0.02)


static func impact() -> AudioStreamWAV:
	var buf := _buffer(0.24)
	var rng := _rng(61)
	var phase := 0.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := 55.0 + 170.0 * exp(-t * 30.0)
		phase += TAU * f / RATE
		var n := _noise(rng)
		lp += (n - lp) * 0.22
		var thud := sin(phase) * exp(-t * 17.0) * 0.9
		var crack := n * exp(-t * 40.0) * 0.55
		buf[i] = thud + crack + lp * exp(-t * 12.0) * 0.4
	return _finalize(buf, 0.85, false, 0.005)


static func page_shift() -> AudioStreamWAV:
	var buf := _buffer(0.3)
	var rng := _rng(71)
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var n := _noise(rng)
		var sweep := 500.0 + 2600.0 * sin(PI * clampf(t / 0.3, 0.0, 1.0))
		var a := clampf(TAU * sweep / RATE, 0.002, 0.92)
		lp += (n - lp) * a
		var env := pow(sin(PI * clampf(t / 0.3, 0.0, 1.0)), 2.0)
		buf[i] = lp * env * 1.7 + n * env * 0.06
	return _finalize(buf, 0.72, false, 0.01)


## One rising note of the chant ladder. pitch_index is a position, not a
## frequency: 0 is A3 and each step walks the minor pentatonic scale.
static func chant_pluck(pitch_index: int) -> AudioStreamWAV:
	var buf := _buffer(0.5)
	var rng := _rng(100 + pitch_index)
	var freq := note_frequency(pitch_index)
	var phase := 0.0
	var pick := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := freq * (1.0 + 0.012 * exp(-t * 40.0))
		phase += TAU * f / RATE
		var env := minf(1.0, t / 0.003) * exp(-t * 8.2)
		var body := sin(phase) \
			+ 0.34 * sin(phase * 2.0) * exp(-t * 3.0) \
			+ 0.15 * sin(phase * 3.01) * exp(-t * 5.0) \
			+ 0.07 * sin(phase * 4.2) * exp(-t * 7.0)
		if t < 0.012:
			pick = _noise(rng) * (1.0 - t / 0.012) * 0.2
		buf[i] = body * env * 0.62 + pick
	return _finalize(buf, 0.8, false, 0.02)


static func chant_resolve() -> AudioStreamWAV:
	var buf := _buffer(1.05)
	var notes := [440.0, 554.37, 659.25, 987.77, 220.0]
	var onset := [0.0, 0.045, 0.09, 0.15, 0.0]
	var amp := [0.4, 0.34, 0.34, 0.22, 0.34]
	for i in notes.size():
		_add_bell(buf, int(onset[i] * RATE), 1.0, notes[i], amp[i], 2.3)
	var rng := _rng(211)
	var shimmer := 0.0
	var prev := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var n := _noise(rng)
		var hp := n - prev
		prev = n
		shimmer += (hp - shimmer) * 0.35
		buf[i] += shimmer * exp(-t * 3.0) * 0.05
	return _finalize(buf, 0.86, false, 0.02)


static func chant_fail() -> AudioStreamWAV:
	var buf := _buffer(0.5)
	var rng := _rng(223)
	var p1 := 0.0
	var p2 := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := 120.0 + 110.0 * exp(-t * 2.4)
		p1 += TAU * f / RATE
		p2 += TAU * f * 1.414 / RATE
		var saw := sin(p1) + 0.5 * sin(p1 * 2.0) + 0.33 * sin(p1 * 3.0) + 0.25 * sin(p1 * 4.0)
		var saw2 := sin(p2) + 0.5 * sin(p2 * 2.0) + 0.33 * sin(p2 * 3.0)
		var drive := (saw + saw2 * 0.7) * 0.42
		drive = drive / (1.0 + absf(drive)) * 1.9
		var env := minf(1.0, t / 0.006) * exp(-t * 4.2)
		var n := _noise(rng) * exp(-t * 11.0) * 0.22
		buf[i] = drive * env + n
	return _finalize(buf, 0.82, false, 0.01)


static func round_win() -> AudioStreamWAV:
	var buf := _buffer(1.35)
	var notes := [440.0, 554.37, 659.25, 880.0, 110.0]
	var onset := [0.0, 0.1, 0.2, 0.34, 0.0]
	var amp := [0.36, 0.34, 0.32, 0.3, 0.3]
	for i in notes.size():
		_add_bell(buf, int(onset[i] * RATE), 1.25, notes[i], amp[i], 2.0)
	var rng := _rng(307)
	for i in buf.size():
		var t := float(i) / RATE
		if t > 0.3:
			buf[i] += _noise(rng) * exp(-(t - 0.3) * 5.0) * 0.035
	return _finalize(buf, 0.88, false, 0.03)


static func round_lose() -> AudioStreamWAV:
	var buf := _buffer(1.5)
	var notes := [220.0, 174.61, 146.83, 110.0]
	var onset := [0.0, 0.2, 0.42, 0.66]
	for i in notes.size():
		_add_dark_note(buf, int(onset[i] * RATE), 0.95, notes[i], 0.4, 1.5)
	var rng := _rng(311)
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		if t > 0.66:
			var u := t - 0.66
			var f := 34.0 + 50.0 * exp(-u * 6.0)
			phase += TAU * f / RATE
			buf[i] += sin(phase) * exp(-u * 3.0) * 0.4
	var lp := 0.0
	for i in buf.size():
		lp += (buf[i] - lp) * 0.35
		buf[i] += lp * 0.2
	return _finalize(buf, 0.8, false, 0.04)


static func ui_click() -> AudioStreamWAV:
	var buf := _buffer(0.08)
	var rng := _rng(401)
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := 1400.0 + 700.0 * exp(-t * 70.0)
		phase += TAU * f / RATE
		var env := minf(1.0, t / 0.0015) * exp(-t * 48.0)
		buf[i] = sin(phase) * env * 0.55 + _noise(rng) * exp(-t * 220.0) * 0.12
	return _finalize(buf, 0.62, false, 0.004)


static func death() -> AudioStreamWAV:
	var buf := _buffer(1.7)
	var rng := _rng(409)
	var phase := 0.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var f := 42.0 + 270.0 * exp(-t * 2.2)
		phase += TAU * f / RATE
		var tone := sin(phase) + 0.4 * sin(phase * 2.0) + 0.2 * sin(phase * 3.0)
		tone *= (1.0 + 0.3 * sin(TAU * 9.0 * t)) * exp(-t * 1.7) * 0.55
		var n := _noise(rng)
		lp += (n - lp) * 0.04
		buf[i] = tone + lp * exp(-t * 1.2) * 1.4
	return _finalize(buf, 0.86, false, 0.05)


## Eight bars, one stem. Callers play all stems together so they stay locked.
static func music_layer(layer: int) -> AudioStreamWAV:
	var rate := MUSIC_LOW_RATE if layer < 2 else HALF_RATE
	var src := PackedFloat32Array()
	src.resize(int(MUSIC_SECONDS * rate))
	var rng := _rng(900 + layer)
	match layer:
		0:
			_render_pad(src, rate)
		1:
			_render_pulse(src, rate)
		2:
			_render_lead(src, rng, rate)
		_:
			_render_pad(src, rate)
	return _finalize_music(src, RATE / rate)


static func note_frequency(pitch_index: int) -> float:
	var idx := clampi(pitch_index, 0, MAX_NOTE_INDEX)
	var octave := idx / PENTATONIC.size()
	var semis := PENTATONIC[idx % PENTATONIC.size()] + octave * 12
	return 220.0 * pow(2.0, float(semis) / 12.0)


# ---------------------------------------------------------------------------
# Music stems
# ---------------------------------------------------------------------------

static func _render_pad(buf: PackedFloat32Array, rate: int) -> void:
	var p0 := 0.0
	var p1 := 0.0
	var p2 := 0.0
	var detune0 := 1.0
	var detune1 := 1.0035
	var detune2 := 0.9965
	var table: Array = []
	for b in MUSIC_BARS:
		var row: Array[float] = []
		for v in 3:
			row.append(_BAR_ROOTS[b] * pow(2.0, float(_BAR_CHORDS[b][v]) / 12.0))
		table.append(row)
	var bar_samples := int(BAR_SECONDS * rate)
	var breath_phase := 0.0
	var breath_inc := TAU * 0.075 / rate

	for i in buf.size():
		var bar := mini(i / bar_samples, MUSIC_BARS - 1)
		var local := float(i - bar * bar_samples) / rate
		var blend := clampf(local / 0.12, 0.0, 1.0)
		var prev := (bar - 1) if bar > 0 else (MUSIC_BARS - 1)
		breath_phase += breath_inc
		var breath := 0.82 + 0.18 * sin(breath_phase + 0.4)
		var a: Array[float] = table[prev]
		var b: Array[float] = table[bar]
		p0 += TAU * lerpf(a[0], b[0], blend) * detune0 / rate
		p1 += TAU * lerpf(a[1], b[1], blend) * detune1 / rate
		p2 += TAU * lerpf(a[2], b[2], blend) * detune2 / rate
		var sum := sin(p0) * 0.36 + sin(p1) * 0.18 + sin(p2) * 0.12
		buf[i] = sum * breath * 0.42


static func _render_pulse(buf: PackedFloat32Array, rate: int) -> void:
	var beat_samples := int(BEAT_SECONDS * rate)
	for bar in MUSIC_BARS:
		var root: float = _BAR_ROOTS[bar] * 0.5
		for beat in MUSIC_BEATS_PER_BAR:
			var start := bar * MUSIC_BEATS_PER_BAR * beat_samples + beat * beat_samples
			_add_kick(buf, start, 0.45, rate)
			_add_bass(buf, start, 0.44, root, 0.32, 4.0, rate)
			_add_hat(buf, start + int(beat_samples * 0.5), 0.1, rate)
			if beat == 3:
				_add_bass(buf, start + int(beat_samples * 0.5), 0.2, root * 2.0, 0.14, 7.0, rate)


static func _render_lead(buf: PackedFloat32Array, rng: RandomNumberGenerator, rate: int) -> void:
	var bar_samples := int(BAR_SECONDS * rate)
	var step_samples := int(BEAT_SECONDS * rate)
	for bar in MUSIC_BARS:
		for step in MUSIC_BEATS_PER_BAR:
			var semis: int = _LEAD_LINE[bar][step]
			var freq := 440.0 * pow(2.0, float(semis) / 12.0)
			var amp := 0.3 if step == 0 else 0.22
			_add_bell(buf, bar * bar_samples + step * step_samples, 0.8, freq, amp, 2.6, rate, 3)
	# Single-tap feedback echo: cheap, phase-locked, and it keeps the line airy.
	var delay := int(BEAT_SECONDS * 0.5 * rate)
	for i in range(delay, buf.size()):
		buf[i] += buf[i - delay] * 0.24
	# A whisper of air, deterministic.
	for i in buf.size():
		buf[i] += (rng.randf() * 2.0 - 1.0) * 0.008


## Music-specific finish: normalise at the reduced source rate, fade the loop
## seam, then repeat each sample factor times. The delivered WAV is still
## 22 050 Hz / 16-bit mono, but we pay for far fewer synthesis and encode calls.
static func _finalize_music(src: PackedFloat32Array, factor: int) -> AudioStreamWAV:
	var n := src.size()
	var maxv := 0.00001
	for i in n:
		maxv = maxf(maxv, absf(src[i]))
	var gain := 0.9 / maxv
	var lf := mini(int(0.025 * (RATE / factor)), n / 4)
	var bytes := PackedByteArray()
	bytes.resize(n * factor * 2)
	var pair := PackedByteArray()
	pair.resize(2)
	for i in n:
		var v: float = src[i] * gain
		if i < lf:
			v *= float(i) / float(lf)
		elif i >= n - lf:
			v *= float(n - 1 - i) / float(lf)
		pair.encode_s16(0, int(clampf(v, -1.0, 1.0) * 32767.0))
		var lo := pair[0]
		var hi := pair[1]
		var o := i * factor * 2
		for k in factor:
			bytes[o + k * 2] = lo
			bytes[o + k * 2 + 1] = hi
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n * factor
	baked_count += 1
	return wav


# ---------------------------------------------------------------------------
# Small additive voices (used by one-shots and the music stems)
# ---------------------------------------------------------------------------

static func _add_bell(buf: PackedFloat32Array, start: int, dur: float, freq: float, amp: float, decay: float, rate: int = RATE, partials: int = 4) -> void:
	var n := int(dur * rate)
	var p := 0.0
	for i in n:
		var idx := start + i
		if idx < 0:
			continue
		if idx >= buf.size():
			break
		var t := float(i) / rate
		p += TAU * freq / rate
		var env := minf(1.0, t / 0.004) * exp(-t * decay)
		var v := sin(p) + 0.32 * sin(p * 2.0) * exp(-t * 2.5)
		if partials >= 3:
			v += 0.14 * sin(p * 3.01) * exp(-t * 4.0)
		if partials >= 4:
			v += 0.07 * sin(p * 4.2) * exp(-t * 6.0)
		buf[idx] += v * env * amp


static func _add_dark_note(buf: PackedFloat32Array, start: int, dur: float, freq: float, amp: float, decay: float) -> void:
	var n := int(dur * RATE)
	var p := 0.0
	var lp := 0.0
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		p += TAU * freq / RATE
		var v := sin(p) + 0.45 * sin(p * 2.0) + 0.25 * sin(p * 3.0)
		lp += (v - lp) * 0.18
		buf[idx] += lp * minf(1.0, t / 0.02) * exp(-t * decay) * amp


static func _add_bass(buf: PackedFloat32Array, start: int, dur: float, freq: float, amp: float, decay: float, rate: int = RATE) -> void:
	var n := int(dur * rate)
	var p := 0.0
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / rate
		p += TAU * freq / rate
		var env := minf(1.0, t / 0.008) * exp(-t * decay)
		buf[idx] += (sin(p) + 0.35 * sin(p * 2.0)) * env * amp


static func _add_kick(buf: PackedFloat32Array, start: int, amp: float, rate: int = RATE) -> void:
	var n := int(0.24 * rate)
	var p := 0.0
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / rate
		var f := 46.0 + 78.0 * exp(-t * 28.0)
		p += TAU * f / rate
		buf[idx] += sin(p) * exp(-t * 17.0) * amp


static func _add_hat(buf: PackedFloat32Array, start: int, amp: float, rate: int = RATE) -> void:
	var rng := _rng(start)
	var n := int(0.05 * rate)
	var prev := 0.0
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / rate
		var x := _noise(rng)
		var hp := x - prev
		prev = x
		buf[idx] += hp * exp(-t * 72.0) * amp


# ---------------------------------------------------------------------------
# Buffer plumbing
# ---------------------------------------------------------------------------

static func _buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(maxi(1, int(seconds * RATE)))
	return buf


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _noise(rng: RandomNumberGenerator) -> float:
	return rng.randf() * 2.0 - 1.0


static func _finalize(buf: PackedFloat32Array, peak: float, loop: bool, fade_seconds: float) -> AudioStreamWAV:
	var maxv := 0.00001
	for i in buf.size():
		maxv = maxf(maxv, absf(buf[i]))
	var gain := peak / maxv
	var n := buf.size()
	for i in n:
		buf[i] *= gain
	if loop:
		# Crossfade the loop seam so the 8-bar wrap is silent-click free.
		var lf := mini(int(0.025 * RATE), n / 4)
		for i in lf:
			var k := float(i) / float(lf)
			buf[i] *= k
			buf[n - 1 - i] *= k
	elif fade_seconds > 0.0:
		var fade := mini(int(fade_seconds * RATE), n / 3)
		for i in fade:
			buf[n - 1 - i] *= float(i) / float(fade)
	return _encode(buf, loop)


static func _encode(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	baked_count += 1
	return wav
