# Synthetic chant voice

SHIFTCAST's chant voice is an **original synthetic vocal emulation**. It is not a
licensed voicebank, contains no Vocaloid assets, and ships no samples. Every
stream is rendered from oscillators, noise and filters during `Audio._ready()`
and then played back as ordinary `AudioStreamWAV` data.

Files:

| File | Role |
| --- | --- |
| `scripts/audio/voice_synth.gd` | Offline voice bakery. Two profiles (16 streams each) plus 17 shared rune-word callouts. |
| `scripts/core/audio.gd` | Bakes the bank once, owns the Voice bus/pool, maps gameplay events to cues. |
| `scripts/audio/synth.gd` | Existing SFX/music bakery; also supplies the shared 16-bit encoder and `baked_count`. |

---

## Baked vs generated

**Chosen: bake once at startup.** The autoload calls
`VoiceSynth.bake_voice()` exactly twice in `_bake_bank()` — once for the player
profile and once for the rival — and `VoiceSynth.bake_callouts()` once for the
shared rune-word bank. After `_ready()` the voice path only changes
`pitch_scale`, `volume_db` and which finished stream a player holds. There is no
`AudioStreamGenerator` anywhere in the project and no synthesis in `_process()`.

Why not generate on demand:

- A per-frame vocal synth competes with physics, AI and rendering on the browser
  main thread and can underrun the WebAudio callback.
- A stereo/24-bit on-demand voice would be far more CPU and memory than the
  entire baked bank.
- The bank is tiny enough that startup cost is the only trade-off, and it is
  paid once before the menu is interactive.
- `Synth.baked_count` gives a hard proof (used by `--audio-selftest`) that no
  stream is encoded after startup.

Measured in this worktree on the latest headless run (warm file cache, includes
existing SFX and music baking in the total):

| Run | Total bake | Voice portion | Bank |
| --- | --- | --- | --- |
| `--audio-selftest` | 974 ms | 262 ms | 49 streams / 684.6 KiB |

Timings vary by a few hundred milliseconds between cold and warm runs. The
callout bank adds ~333 KiB and roughly 0.25–0.5 s to the voice bake.

The voice bank is ~180 KiB per profile: 12 ladder rungs (~0.21 s each), a 0.30 s
breath onset, a 0.74 s resolve stab, a 0.32 s typo fail and a 0.20 s interruption
cut. A third shared bank holds one ~0.4 s callout per rune word (6 elements, 6
forms, 5 modifiers), ~333 KiB in total. All streams are 22 050 Hz, mono, 16-bit
PCM, peak-normalised to 0.55–0.68 so the bus has headroom before the Master
limiter.

---

## Synthesis model

Each note is rendered by `VoiceSynth._render_voice()`:

1. **Glottal pulse** — a Rosenberg-shaped open/close cycle (`_glottal`), then
   differentiated sample-to-sample to emulate lip radiation. This is the buzzy
   source, not a sample loop.
2. **Formants** — the source is fed in parallel to three two-pole resonators at
   F1/F2/F3. The vowel table is:

   | Vowel | F1 | F2 | F3 |
   | --- | --- | --- | --- |
   | A | 730 | 1090 | 2440 |
   | E | 530 | 1840 | 2480 |
   | I | 270 | 2290 | 3010 |
   | O | 570 | 840 | 2410 |
   | U | 300 | 870 | 2240 |

   Ladder rung `i` sings `VOWELS[i % 5]`, so typing advances both pitch and
   mouth shape instead of producing a siren.
3. **Vibrato** — ±1.1–1.3% at 4.4–5.1 Hz, faded in over the first 70 ms so the
   attack starts straight.
4. **Consonant/breath noise** — a high-passed noise burst for the first ~100 ms
   of each syllable, plus a quiet breath bed. The onset stream is a pure breath
   swell with a low hum.
5. **Waveshaping** — `x / (1 + |x|)` with 1.7–2.1 drive per profile, giving the
   synthetic throat a little rasp before the bus effect.

Ladder contour: A minor pentatonic over 12 rungs. Player A2 → A4
(110.0 → 523.3 Hz); rival is transposed and formant-scaled 15% down
(82.5 → ~392 Hz, formant scale 0.86). The rival also gets 0.34 vs 0.42 breath,
4.4 vs 5.1 Hz vibrato, and more drive.

### Spell-name callouts

`VoiceSynth._speak_word()` renders each rune word as 1–3 short formant syllables
using a rough syllabifier: each vowel group takes its F1/F2/F3 shape, the
preceding consonant cluster becomes the existing noise onset, and pitch steps
down 10% per syllable. This is deliberately a **sung rune-language callout**, not
English text-to-speech; it is there so a cast audibly announces `IGNA MITT` or
`GLACIA RUPTA` instead of sounding like every other bolt. Only the player profile
is baked; the rival replays the same streams at `pitch_scale = 0.8`.

---

## Integration

The autoload discovers wizards through the existing `"wizards"` group and uses
the same signal + polling pattern as the rest of the audio director. No gameplay
script was changed.

| Gameplay event | Voice cue |
| --- | --- |
| `chant_changed(wizard, true)` (real start, not a typo reset) | `onset` breath |
| Each newly typed correct character (`wizard.chant_text.length()`) | Next baked ladder rung, both duelists |
| Successful cast (`cast_fired` within 250 ms of a chant ending) | `resolve` stab (plus the existing `chant_resolve` bell) |
| Every cast (`cast_fired`) | Spell-name callout: element word + form word + optional modifier word on a dedicated Voice player. The rival's copy is pitch-shifted down and skipped if the player just cast. |
| Fizzled partial cast (`stats.fizzle`) | The cast SFX plus `chant_fail` at −5 dB; no resolve stab and no triumphant chord. |
| Typo (`wizard.chant_typos` increases) | `fail` descending buzz |
| `chant_interrupted(wizard)` | `cut` glottal choke |

The old plucked ladder still plays under the voice at −9 dB on the SFX bus, so
the pitch skeleton survives in a noisy fight without fighting the formants.

---

## Mix

```
Master  -> AudioEffectHardLimiter (ceiling -0.6 dB, release 0.12 s, unchanged)
  Music (-2.5 dB)  -> lowpass 20 kHz idle, 700/1400 Hz while ducking
  SFX   (-1.0 dB)
  UI    (-3.0 dB)
  Voice (-4.5 dB)  -> AudioEffectDistortion (overdrive, drive 0.28)
                   -> AudioEffectLowPassFilter (7.6 kHz, resonance 0.22)
```

- The Voice bus and its effects are created at runtime, like the existing buses.
- Player voice plays at 0 dB on the Voice bus; the rival plays at an extra
  −3.5 dB per shot and uses the darker/lower profile, so both can chant at once
  without the rival poking through the mix.
- Music ducking is now tiered: player chant −7 dB / 700 Hz lowpass, rival chant
  −3 dB / 1400 Hz lowpass, both released over 0.4 s. The player keeps the deeper
  duck so typed letters stay readable.
- Eight dedicated Voice players are separate from the 12 SFX players, so a
  resolve stab cannot steal an impact, and SFX cannot mute a ladder rung. A
  ninth `SpellCallout` player queues the name words one at a time; a new cast
  replaces the queue so fast quickcasts do not pile up.
- Baked peaks are 0.55–0.68; the Master limiter is the final safety net. In the
  self-test the bank measured RMS 0.121–0.337 (average 0.219), peak 0.68, so no
  stream is silent or clipped before it reaches the bus.

### Mix concerns to listen for

- **Rival intelligibility** — the −3.5 dB offset and 15% formant drop are
  deliberate, but the rival can disappear under a loud fire fight. Raise the
  rival per-shot gain before raising the whole Voice bus.
- **Sibilance** — consonant noise is high-passed; the 7.6 kHz bus lowpass is
  there to stop `S`-like energy from turning into hiss on laptop speakers.
- **Two simultaneous chants** — they are separated by pitch and formant profile
  rather than stereo placement. On mono/browser speakers check that the rival
  still reads as a second singer.
- **Ducking** — the rival only ducks music by 3 dB. If the music bed masks the
  rival, extend the duck rather than pushing the voice bus up.

---

## Listening / verification

```powershell
# Bakes the bank, checks formats, RMS, peaks, ladder, Voice bus, and that
# Synth.baked_count does not change after _ready.
godot --headless --path . -- --audio-selftest

# Alias: same checks with a voice-specific flag.
godot --headless --path . -- --voice-selftest
```

Expected voice section (cold headless worktree):

```
voice bank+callouts 49 streams 684.6 KiB bake=262 ms rms=0.121..0.337 avg=0.203 peak=0.68 ok
callout bank   17 rune words baked
voice ladder  110.0 Hz -> 523.3 Hz (12 rungs, vowels A-E-I-O-U)
voice bus      -4.5 dB, 2 effects (distortion + lowpass) ok
no synthesis after _ready (78 baked streams)
```

Listening notes:

- The intent is a **choir of one**, not a pop vocal: formants carry the vowel,
  the glottal derivative carries the buzz, and the bus overdrive adds grit.
- A single ladder rung should read as one sung syllable. A fast typed phrase
  should read as a rising, vowel-shifting chant; if it turns into a buzz, lower
  the bus distortion drive before changing the formants.
- The resolve stab is a root/fifth/octave chord and should feel like the payoff
  after the last letter, not a separate instrument.
- A spell callout should sound like two or three clipped syllables of the same
  voice, pitched above the resolve stab. If it reads as speech, that is fine; if
  it reads as a second melody, shorten the syllables or raise the gap.
- The typo `fail` is deliberately ugly (descending, choked) and the interruption
  `cut` is shorter and noisier so the player can tell "wrong letter" from
  "I got hit".
