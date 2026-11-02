# SHIFTCAST audio

SHIFTCAST ships **no audio files**. Every sound in the game is synthesised from
scratch at startup, so the repository stays tiny and the browser build loads
with zero network audio requests.

- `scripts/audio/synth.gd` — the bakery. Pure static functions that return a
  finished `AudioStreamWAV`.
- `scripts/core/audio.gd` — the `Audio` autoload. Bakes the bank once, mixes,
  wires itself to gameplay, persists volume.
- `project.godot` — one autoload line (`Audio`) is the only project change.

Nothing in this folder is a sample; this document is the only file in it.

---

## Format contract

Every stream is:

| Property | Value |
| --- | --- |
| Class | `AudioStreamWAV` |
| Mix rate | `22 050` Hz |
| Channels | mono (`stereo = false`) |
| Format | `FORMAT_16_BITS` |
| Encoding | `PackedByteArray.resize(samples * 2)` + `encode_s16(i * 2, sample)` |

`AudioStreamGenerator` is never used, so nothing is synthesised per frame — the
whole bank is built inside `Audio._ready()` and the frame loop only calls
`play()` on pre-baked streams. Bake time is ~1.0–1.2 s on a desktop CPU
(~2.4 s on a cold headless run with shader/import work in front of it).

The three music stems are *rendered* at a lower internal rate (7 350 Hz for pad
and pulse, 11 025 Hz for the lead) and **sample-doubled/tripled on encode**.
Delivered streams still measure 22 050 Hz, 16-bit mono; the trick just cuts the
startup bake by roughly half.

---

## Sound recipes

Envelope shorthand: `a` attack, `d` decay rate, `lp` one-pole lowpass with
coefficient `k`. All noise is deterministic (`RandomNumberGenerator` with a
fixed seed), so every bake is bit-identical across platforms.

### Casts — one per element, deliberately different in spectrum and gesture

| Id | Length | Recipe |
| --- | --- | --- |
| `cast_fire` | 0.46 s | Pitch-falling body `70 + 250·e^(−6t)` Hz with a detuned 2.01× partial, over a noise burst (`d = 17`) plus lowpassed rumble (`d = 7`). Sparse random crackle grains (`p = 1.6%` per sample). Sounds like a fireball igniting and guttering out. |
| `cast_frost` | 0.58 s | Two sines at `f` and `2.51f` with `f = 620 + 1450·e^(−5.2t)`; the upper partial decays faster. Added differentiated noise (high-pass "air") and a 7 Hz chorus on the amplitude. Glassy, crystalline, cold. |
| `cast_storm` | 0.40 s | A saw-ish `sin + 0.5·sin(3×)` zap sweeping `140 → 1120` Hz, amplitude-gated at 58 Hz (the electric buzz), plus a very fast noise crack (`d = 24`) with a hard transient for the first 35 ms. Short and bright. |
| `cast_earth` | 0.58 s | Sub thud `42 + 110·e^(−8t)` Hz plus a 0.5× sub-octave, heavy lowpassed rumble (`k = 0.055`, `d = 3.6`) and a 90 Hz-decay click. Slow, heavy, felt more than heard. |
| `cast_arcane` | 0.64 s | Four additive bells (A4, C♯5, E5, A5) staggered 0–225 ms with `d = 3.1`, then a high-passed shimmer swelled by `sin(π·t/T)`. Arpeggiated and magical. |
| `cast_void` | 0.68 s | Near-unison pair `f`/`1.06f` with `f = 62 + 58·e^(−3t)` under a `t^2.2` swell (sound grows instead of decaying), plus a heavily lowpassed air layer. Inhales rather than explodes. |

### Feedback

| Id | Length | Recipe |
| --- | --- | --- |
| `impact` | 0.24 s | `55 + 170·e^(−30t)` Hz thud (`d = 17`), noise crack (`d = 40`) and a lowpassed tail. Gain is scaled from the damage amount in the autoload. |
| `page_shift` | 0.30 s | Pure filtered noise whose lowpass sweep rides `500 + 2600·sin(π·t/T)`, shaped by `sin²(π·t/T)`: a paper whoosh that fades in and out. |
| `chant_fail` | 0.50 s | Two detuned (`×1.414`, a tritone) harmonic stacks (`sin + ½sin2 + ⅓sin3 + ¼sin4`), soft-clipped via `x/(1+|x|)`, `f = 120 + 110·e^(−2.4t)`. Harsh and clearly wrong. |
| `ui_click` | 0.08 s | One 1.4–2.1 kHz blip, 1.5 ms attack, `d = 48`, plus 220 Hz-decay noise tick. Quiet and dry. |
| `death` | 1.70 s | Falling `42 + 270·e^(−2.2t)` Hz tone with 2nd/3rd harmonics, 9 Hz tremolo, `d = 1.7`, over a deep lowpassed rumble. Long, collapsing, final. |

### Chant ladder and cadences

`chant_pluck(i)` — 12 notes, A minor pentatonic starting at A3:
`220, 261.6, 293.7, 329.6, 392, 440, 523.3, 587.3, 659.3, 784, 880, 1046.5` Hz.
Each pluck is 0.5 s: a small pitch drop (`+1.2%` that decays in 25 ms) for a
plucked feel, four additive partials decaying at different rates, and a 12 ms
noise pick transient.

| Id | Length | Recipe |
| --- | --- | --- |
| `chant_resolve` | 1.05 s | A-major-ish bell chord (A4, C♯5, E5, B5) rolled over 150 ms on top of a low A3, plus high-passed shimmer. The "you cast it" payoff. |
| `round_win` | 1.35 s | Rising bell arpeggio A4 → C♯5 → E5 → A5 over 340 ms with a low A2 bed and a noise sparkle swelling after 0.3 s. |
| `round_lose` | 1.50 s | Descending dark notes A3 → F3 → D3 → A2 (0.95 s each, lowpass-swept), then a 34–84 Hz sub drop from 0.66 s and a final lowpass pass over everything. |

### Music bed — one looping 8-bar cue, three stems

- Tempo **112 BPM**, 4/4, **8 bars = 17.14 s**.
- `loop_mode = LOOP_FORWARD`, `loop_begin = 0`, `loop_end = 378 000` samples.
  The first and last 25 ms are fade-shaped on encode, so the wrap is
  click-free (measured seam ≈ 0.000 in the self-test).
- Harmony (A minor): `Am · F · C · G · Am · F · F · Em`, roots at
  `110, 87.31, 130.81, 98, 110, 87.31, 146.83, 82.41` Hz.

| Stem | Content |
| --- | --- |
| `music_layer(0)` — pad | Three detuned sines (`±0.35%`) per chord tone, chord changes crossfaded over 120 ms, 0.075 Hz "breath" amplitude LFO. Continuous, no transients. |
| `music_layer(1)` — pulse | Per beat: kick (`46 + 78·e^(−28t)` Hz), root-fifth bass pluck, off-beat hi-hat (differentiated noise). Adds motion and a heartbeat. |
| `music_layer(2)` — lead | One bell per beat from a written 8×4 line (0.8 s, `d = 2.6`), a half-beat feedback echo at 24 %, and a deterministic noise whisper at −42 dB. |

All three stems are the exact same length and are started by the same
`play()` loop, so they are **phase-locked** forever — the layers can be faded
in and out without ever drifting.

---

## Buses and mixing

Created at runtime by `Audio._ready()` if they are missing:

```
Master  ← AudioEffectHardLimiter (ceiling −0.6 dB, release 0.12 s)
 ├── Music  (−2.5 dB) ← AudioEffectLowPassFilter (20 kHz idle → 700 Hz when ducking)
 ├── SFX    (−1.0 dB)
 └── UI     (−3.0 dB)
```

- **Ducking:** while the player chants, the Music bus fades −7 dB and its
  lowpass sweeps to 700 Hz (0.10 s in, 0.40 s out). Released the instant the
  incantation ends or fails.
- **Intensity** (`Music` stem gains in dB; a `−80 dB` layer is inaudible):

| `set_intensity` | pad | pulse | lead | When |
| --- | --- | --- | --- | --- |
| 0 | −6.0 | −80 | −80 | round 1 — pad only |
| 1 | −4.5 | −9.0 | −80 | round 2 |
| 2 | −3.5 | −7.0 | −8.0 | round 3 |
| 3 | −3.0 | −6.0 | −5.0 | round 4+ — all-out |

- **Voices:** a fixed pool of 12 `AudioStreamPlayer`s on `SFX`. `play()` picks a
  free voice, otherwise steals round-robin, and humanises with
  `pitch_scale = randf_range(0.94, 1.06)`. `play_note()` only uses
  `0.995–1.005` so the rising chant ladder never smears.
- **Master volume** is clamped to `[−40, +6]` dB and saved to
  `user://audio.cfg` (`[audio] master_db`). It mirrors `Game.master_volume_db`
  when the file is absent, and writes back to it.

---

## Integration — what is connected, and what is polled

`scripts/main.gd`, `scripts/world/*`, `scripts/ui/*` and `scenes/*` are **not
modified**. The autoload finds the wizard nodes through the existing
`"wizards"` group and wires itself up at runtime.

Signal-driven (real signals on `scripts/world/wizard.gd`):

| Signal | Effect |
| --- | --- |
| `cast_fired(wizard, spell, stats, origin, direction)` | `play_cast(spell.element)`; if the caster's chant ended < 250 ms ago, also `chant_resolve`. |
| `damaged(wizard, amount)` | `impact`, volume scaled by damage, 40 ms de-dupe so one explosion is one hit. |
| `died(wizard)` | `death`. |
| `chant_changed(wizard, active)` | Player only: ducks/unducks music; a chant that ends with empty `chant_text` is flagged as a successful cast. |

Polled each frame (there is no signal for these — `wizard.gd` emits none):

| Property | Effect |
| --- | --- |
| `wizard.page` | `page_shift` whoosh whenever the page index changes. |
| `wizard.chant_text.length()` | One rising `chant_pluck(i)` per newly typed correct character. |
| `wizard.chant_typos` | `chant_fail` on an increase, and the ladder resets. |
| `Game.round_index` | `set_intensity(round_index)`. |
| `Game.player_score` / `Game.enemy_score` | `round_win` / `round_lose` on an increase. |
| `BaseButton.pressed` (via `SceneTree.node_added`) | `ui_click` on `UI` for every button in the game. |

Because `chant_key(character)` and `swap_page()` were listed in the brief but do
not exist in `wizard.gd`, the arpeggio and page whoosh are implemented by
polling the state those signals would have carried. Adding the real signals
later only requires swapping `_poll_wizard()` for two handlers.

Browser builds block audio until a user gesture. `_input()` catches the first
key / mouse / touch and plays a silent (−80 dB) voice to warm the WebAudio
graph; on desktop it is a harmless no-op.

---

## API

`Audio` (autoload, `scripts/core/audio.gd`):

```gdscript
Audio.play("impact")                # one-shot from the baked bank
Audio.play("ui_click", "UI", -4.0)  # explicit bus + gain
Audio.play_cast("frost")            # element name -> cast_frost
Audio.play_note(5)                  # rung 5 of the 12-note ladder
Audio.set_intensity(2)              # 0..3 music tier
Audio.set_chanting(true)            # duck music (also happens automatically)
Audio.set_master_volume_db(-6.0)    # persisted to user://audio.cfg
Audio.start_music()                 # idempotent, already called at startup
```

Unknown sound ids warn once and are ignored.

---

## Verification

```powershell
# fresh worktree: build the class cache first
godot --headless --path . --import

# audio-only report: formats, lengths, loop seams, rising ladder,
# phase-locked stems, and "no synthesis after _ready"
godot --headless --path . -- --audio-selftest

# the acceptance harness
godot --headless --path . -- --test
```

`--audio-selftest` is a debug path handled inside the autoload; it never runs
in a normal session. It asserts 14 one-shots, 12 chant notes, 3 music stems,
`FORMAT_16_BITS` / 22 050 Hz / mono on all 29 streams, 17.14 s forward loops
with a silent seam, monotonic chant pitches (220.0 → 1046.5 Hz), identical stem
lengths, and `Synth.baked_count` unchanged after `_ready()`.

Latest run: 29 streams, all checks `ok`, no synthesis after `_ready`, `PASS`.
