class_name VoiceSynth
extends RefCounted

## Original synthetic chant voice for SHIFTCAST.
##
## This is *not* a licensed voicebank and it ships no samples: every stream is
## rendered offline from a glottal pulse, three parallel formant resonators,
## vibrato, consonant noise and a soft waveshaper. Two profiles exist:
##
##   VOICE_PLAYER - brighter formants, A2-ish base, lighter drive
##   VOICE_RIVAL  - 15% lower formants/pitch, darker and a little rougher
##
## The bank is baked exactly once by Audio._ready(). Playback only changes
## pitch_scale/volume on finished AudioStreamWAVs, so no synthesis happens
## after startup. Encoding goes through SynthLib._finalize() so the shared
## Synth.baked_count counter also covers the voice bank.
##
## Output contract matches scripts/audio/synth.gd: 22 050 Hz, mono, 16-bit PCM.

const SynthLib := preload("res://scripts/audio/synth.gd")

const RATE := 22050
## Rungs baked per profile. Past this the ladder holds its top note; the
## longest incantation is ~20 characters, so 12 rungs already cover a full
## element + form + modifier phrase without repeating a vowel too often.
const LADDER_STEPS := 12
const MAX_LADDER_INDEX := LADDER_STEPS - 1

const VOICE_PLAYER := 0
const VOICE_RIVAL := 1

const VOWELS: Array[String] = ["A", "E", "I", "O", "U"]
const PENTATONIC: Array[int] = [0, 3, 5, 7, 10]

## F1/F2/F3 centres in Hz for a neutral adult voice.
const VOWEL_FORMANTS := {
	"A": [730.0, 1090.0, 2440.0],
	"E": [530.0, 1840.0, 2480.0],
	"I": [270.0, 2290.0, 3010.0],
	"O": [570.0, 840.0, 2410.0],
	"U": [300.0, 870.0, 2240.0],
}
const FORMANT_BW: Array[float] = [90.0, 110.0, 140.0]
const FORMANT_GAIN: Array[float] = [1.0, 0.55, 0.30]

const PROFILE_PLAYER := {
	"f0": 110.0,
	"formant_scale": 1.0,
	"breath": 0.42,
	"drive": 1.70,
	"vibrato_hz": 5.1,
	"vibrato": 0.013,
	"consonant": 0.55,
}

const PROFILE_RIVAL := {
	"f0": 82.5,
	"formant_scale": 0.86,
	"breath": 0.34,
	"drive": 2.10,
	"vibrato_hz": 4.4,
	"vibrato": 0.011,
	"consonant": 0.70,
}


# ---------------------------------------------------------------------------
# Public bake
# ---------------------------------------------------------------------------

## Bake one complete voice. Returns:
##   { onset, ladder: Array[AudioStreamWAV], resolve, fail, cut }
## Callers bake each profile once during startup and never again.
static func bake_voice(voice_id: int) -> Dictionary:
	var profile: Dictionary = PROFILE_PLAYER if voice_id == VOICE_PLAYER else PROFILE_RIVAL
	var ladder: Array[AudioStreamWAV] = []
	for step in LADDER_STEPS:
		ladder.append(_ladder_syllable(profile, step))
	return {
		"onset": _onset(profile, voice_id),
		"ladder": ladder,
		"resolve": _resolve(profile, voice_id),
		"fail": _fail(profile, voice_id, false),
		"cut": _fail(profile, voice_id, true),
	}


## Bake one short spoken callout per rune word (element / form / modifier).
## Only the player profile is needed: the rival reuses these streams at a lower
## pitch_scale, which keeps the extra startup bake small.
static func bake_callouts(words: Array) -> Dictionary:
	var out := {}
	for word in words:
		var key := str(word).to_upper()
		if key.is_empty() or out.has(key):
			continue
		out[key] = _speak_word(PROFILE_PLAYER, key)
	return out


## Render a rune word as a short, chant-like utterance. It is not English
## speech: each vowel group becomes a formant-shaped syllable, and consonant
## clusters become the existing noise onset. Enough to voice "IGNA MITT" as a
## recognisable cast callout without shipping samples.
static func _speak_word(profile: Dictionary, word: String) -> AudioStreamWAV:
	var chunks := _syllables(word)
	if chunks.is_empty():
		chunks = [word]
	var seg := 0.19 if chunks.size() <= 2 else 0.165
	var gap := 0.012
	var total := 0.06 + float(chunks.size()) * (seg + gap)
	var buf := _buffer(total)
	var base := float(profile["f0"]) * 1.55
	for i in chunks.size():
		var chunk := str(chunks[i])
		var vowel := _first_vowel(chunk)
		var onset := not _is_vowel(chunk.substr(0, 1))
		var pitch := base * pow(0.90, float(i))
		_render_voice(
			buf, int((0.02 + float(i) * (seg + gap)) * RATE), seg,
			pitch, pitch * 0.965, vowel, profile,
			0.95, 1.35 if onset else 0.45
		)
	return SynthLib._finalize(buf, 0.60, false, 0.012)


## Rough syllabification: consonant cluster + vowel group (+ one coda consonant).
static func _syllables(word: String) -> Array[String]:
	var out: Array[String] = []
	var current := ""
	var i := 0
	var n := word.length()
	while i < n:
		var ch := word.substr(i, 1)
		current += ch
		if _is_vowel(ch):
			var j := i + 1
			while j < n and _is_vowel(word.substr(j, 1)):
				current += word.substr(j, 1)
				j += 1
			# Absorb up to two coda consonants so a word like MITT stays one
			# syllable instead of ending on a bare, vowel-less fragment.
			var k := j
			var coda := 0
			while k < n and coda < 2 and not _is_vowel(word.substr(k, 1)):
				current += word.substr(k, 1)
				k += 1
				coda += 1
			out.append(current)
			current = ""
			i = k
		else:
			i += 1
	if not current.is_empty():
		out.append(current)
	return out


static func _first_vowel(text: String) -> String:
	for i in text.length():
		var ch := text.substr(i, 1).to_upper()
		if _is_vowel(ch):
			return ch
	return "A"


static func _is_vowel(ch: String) -> bool:
	return ch in VOWELS


## Player ladder is a 12-rung A minor pentatonic run from A2 to A4. The rival
## uses the same contour 15% lower (see PROFILE_RIVAL.f0).
static func ladder_frequency(step: int) -> float:
	return _step_frequency(PROFILE_PLAYER, step)


## Vowel sung on a ladder rung. Typing a letter advances both pitch and mouth
## shape, which is what keeps a long incantation from sounding like a siren.
static func step_vowel(step: int) -> String:
	return VOWELS[posmod(step, VOWELS.size())]


# ---------------------------------------------------------------------------
# Individual streams
# ---------------------------------------------------------------------------

static func _ladder_syllable(profile: Dictionary, step: int) -> AudioStreamWAV:
	var dur := 0.21
	var buf := _buffer(dur)
	var f0 := _step_frequency(profile, step)
	var vowel := step_vowel(step)
	# Tiny downward glide at the tail gives each typed letter a sung shape.
	_render_voice(buf, 0, dur - 0.012, f0, f0 * 0.982, vowel, profile, 1.0, 0.55)
	return SynthLib._finalize(buf, 0.62, false, 0.012)


## A breathy inhale/onset: filtered noise swell with a quiet rising hum. It
## covers the gap between pressing chant and the first typed letter.
static func _onset(profile: Dictionary, voice_id: int) -> AudioStreamWAV:
	var dur := 0.30
	var buf := _buffer(dur)
	var rng := _rng(700 + voice_id)
	var prev := 0.0
	var lp := 0.0
	var phase := 0.0
	var hum_f := float(profile["f0"]) * 0.5
	for i in buf.size():
		var t := float(i) / RATE
		var u := clampf(t / dur, 0.0, 1.0)
		var env := sin(PI * u)
		var n := _noise(rng)
		var hp := n - prev
		prev = n
		lp += (n - lp) * 0.10
		phase += TAU * hum_f * (1.0 + 0.06 * u) / RATE
		var hum := sin(phase) * 0.22 * (0.35 + 0.65 * u)
		buf[i] = hp * 0.34 * env + lp * 0.85 * env + hum * env
	return SynthLib._finalize(buf, 0.55, false, 0.02)


## The "cast resolved" stab: root + fifth + octave sung on a rolled chord,
## with just enough breath noise to read as a voice rather than an organ.
static func _resolve(profile: Dictionary, voice_id: int) -> AudioStreamWAV:
	var dur := 0.74
	var buf := _buffer(dur)
	var root := float(profile["f0"]) * 2.0
	var notes: Array[float] = [root, root * 1.5, root * 2.0]
	var vocals: Array[String] = ["A", "O", "E"]
	var onsets: Array[float] = [0.0, 0.04, 0.08]
	var amps: Array[float] = [0.9, 0.56, 0.4]
	for i in notes.size():
		_render_voice(
			buf, int(onsets[i] * RATE), 0.56,
			notes[i], notes[i] * 0.994, vocals[i], profile,
			amps[i], 0.35
		)
	var rng := _rng(810 + voice_id)
	var prev := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var n := _noise(rng)
		var hp := n - prev
		prev = n
		buf[i] += hp * exp(-t * 7.0) * 0.045
	return SynthLib._finalize(buf, 0.68, false, 0.03)


## Typo = a descending buzz; interruption = a shorter,noisier glottal choke.
static func _fail(profile: Dictionary, voice_id: int, choked: bool) -> AudioStreamWAV:
	var dur := 0.20 if choked else 0.32
	var buf := _buffer(dur)
	var base := float(profile["f0"]) * (2.3 if choked else 2.0)
	var tail := base * (0.55 if choked else 0.62)
	var vowel := "U" if choked else "A"
	_render_voice(buf, 0, dur - 0.01, base, tail, vowel, profile, 1.0, 0.9)
	if choked:
		var rng := _rng(910 + voice_id)
		var prev := 0.0
		for i in buf.size():
			var t := float(i) / RATE
			var n := _noise(rng)
			var hp := n - prev
			prev = n
			buf[i] += hp * exp(-t * 42.0) * 0.55
	return SynthLib._finalize(buf, 0.60 if choked else 0.58, false, 0.01)


# ---------------------------------------------------------------------------
# Core voice renderer
# ---------------------------------------------------------------------------

## Render one sung note into buf at start_sample.
##
## Signal path: Rosenberg glottal pulse -> differentiated source -> three
## parallel two-pole formant resonators -> breath/consonant noise -> soft
## waveshaper -> envelope. f0 glides from f0_start to f0_end over the note.
static func _render_voice(
	buf: PackedFloat32Array,
	start: int,
	dur: float,
	f0_start: float,
	f0_end: float,
	vowel: String,
	profile: Dictionary,
	amp: float,
	consonant_amount: float
) -> void:
	var n := int(dur * RATE)
	if n <= 0:
		return

	var formants: Array = VOWEL_FORMANTS.get(vowel, VOWEL_FORMANTS["A"])
	var scale := float(profile["formant_scale"])
	# Coefficients are fetched once per note. Keeping the three resonators in
	# scalars (rather than arrays) makes the per-sample loop roughly twice as
	# fast in GDScript, which matters for startup bake time.
	var c1 := _resonator(float(formants[0]) * scale, FORMANT_BW[0])
	var c2 := _resonator(float(formants[1]) * scale, FORMANT_BW[1])
	var c3 := _resonator(float(formants[2]) * scale, FORMANT_BW[2])
	var a01: float = c1[0]
	var b11: float = c1[1]
	var b21: float = c1[2]
	var a02: float = c2[0]
	var b12: float = c2[1]
	var b22: float = c2[2]
	var a03: float = c3[0]
	var b13: float = c3[1]
	var b23: float = c3[2]
	var y11 := 0.0
	var y21 := 0.0
	var y12 := 0.0
	var y22 := 0.0
	var y13 := 0.0
	var y23 := 0.0

	var rng := _rng(int(f0_start * 100.0) + start + vowel.hash() + int(dur * 1000.0))
	var phase := 0.0
	var prev_g := 0.0
	var prev_noise := 0.0
	var vib_rate := float(profile["vibrato_hz"])
	var vib_depth := float(profile["vibrato"])
	var breath := float(profile["breath"])
	var drive := float(profile["drive"])
	var gain1 := FORMANT_GAIN[0]
	var gain2 := FORMANT_GAIN[1]
	var gain3 := FORMANT_GAIN[2]

	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		var u := t / dur
		var f0 := lerpf(f0_start, f0_end, u)

		# Delayed vibrato: a straight onset, then the pitch blooms.
		var vib := 1.0 + vib_depth * sin(TAU * vib_rate * t + 0.6) * minf(1.0, t / 0.07)
		phase += f0 * vib / RATE
		phase -= floorf(phase)

		# Rosenberg glottal pulse, inlined: open phase rises smoothly, closing
		# phase falls fast, then a closed (silent) remainder. Differentiating
		# sample-to-sample supplies the bright glottal buzz.
		var g := 0.0
		if phase < 0.40:
			var px := phase / 0.40
			g = 3.0 * px * px - 2.0 * px * px * px
		elif phase < 0.56:
			var py := (phase - 0.40) / 0.16
			g = 1.0 - py * py
		var src := (g - prev_g) * 6.0 * (110.0 / maxf(f0, 40.0))
		prev_g = g

		var noise := rng.randf() * 2.0 - 1.0
		var hp := noise - prev_noise
		prev_noise = noise
		var cons_env := exp(-t * 26.0) * consonant_amount
		var exc := src + hp * (cons_env * 1.35 + 0.05) + noise * breath * 0.05

		var y1 := a01 * exc + b11 * y11 + b21 * y21
		y21 = y11
		y11 = y1
		var y2 := a02 * exc + b12 * y12 + b22 * y22
		y22 = y12
		y12 = y2
		var y3 := a03 * exc + b13 * y13 + b23 * y23
		y23 = y13
		y13 = y3
		var sum := y1 * gain1 + y2 * gain2 + y3 * gain3

		var env := minf(1.0, t / 0.010) * exp(-t * 2.4) * (1.0 - smoothstep(0.82, 1.0, u))
		var x := sum * amp
		buf[idx] += (x / (1.0 + absf(x)) * drive) * env


## Two-pole resonator: y[n] = a0*x[n] + b1*y[n-1] + b2*y[n-2].
static func _resonator(freq: float, bandwidth: float) -> Array:
	var r := exp(-PI * bandwidth / RATE)
	var theta := TAU * clampf(freq, 40.0, RATE * 0.45) / RATE
	return [1.0 - r, 2.0 * r * cos(theta), -r * r]


static func _step_frequency(profile: Dictionary, step: int) -> float:
	var idx := clampi(step, 0, MAX_LADDER_INDEX)
	var octave := idx / PENTATONIC.size()
	var semis := PENTATONIC[idx % PENTATONIC.size()] + octave * 12
	return float(profile["f0"]) * pow(2.0, float(semis) / 12.0)


# ---------------------------------------------------------------------------
# Buffer plumbing (kept local so the voice bank is self-contained)
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
