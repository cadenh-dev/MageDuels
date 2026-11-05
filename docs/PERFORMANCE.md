# Performance — first cast, battle entry, and editor first-open

## Symptoms

- A hitch on the first spell cast.
- A hitch when entering the first battle.
- The Godot editor crashed on the first open of the project.
- Slow startup while the audio bank baked.

## Causes

1. **Shader/material compilation on first use.** The first projectile, beam,
   nova, wall, shield, damage number, and arena materials each compile their
   GL Compatibility shader variants the first time they are drawn.
2. **Audio synthesis at startup.** The procedural SFX/music/voice bank was baked
   synchronously in `Audio._ready`, before the menu existed.
3. **Generated folders inside `res://`.** `build/`, `dist/`, `screenshots/`,
   `docs/`, `design/`, `tools/`, `.opencode/`, and `graphify-out/` were scanned
   and imported by the editor on first open. The web export (`index.wasm`,
   `index.pck`) and screenshot PNGs were the likely first-open crash trigger.

## Fixes

- **`Audio.prepare()`** — audio baking moved out of `_ready` and behind the boot
  loading screen. The menu appears only after the bank and music are ready.
- **`SpellWarmup`** — the real arena, two wizards, every spell form, and **every
  element × form color combination** render once in the **real viewport**
  (behind the loading screen). This compiles the same depth, transparent, MSAA,
  light, and particle pipelines the first duel uses.
- **Stable light count** — per-projectile, per-wall, and pooled dynamic spell
  lights were removed entirely. Spells are emissive-only, so casting never
  changes the scene's light list or forces pipeline rebuilds.
- **MSAA off and real-time shadows off** — the 4× MSAA depth buffer and the
  directional shadow depth pass were the remaining depth bandwidth. The arena
  keeps its emissive rim, rings, and ambient light; the low-poly look was
  verified without shadows.
- **Depth prepass disabled** — `rendering/driver/depth_prepass/enable=false`.
  The arena is a small opaque stage plus transparent VFX, so the prepass was
  costing more than the overdraw it saved. Verified on desktop GL and in the
  web build; the scene renders correctly.
- **Material reuse** — projectile core/halo/trail, impact-burst, beam, shockwave,
  and wall materials are cached per color instead of allocated on every cast.
  Beam/shockwave/wall keep a static template and get a per-instance duplicate so
  each effect can fade independently without recompiling the variant.
- **Persistent VFX keepalive** — a few microscopic meshes under the floor hold
  the wall/beam/shockwave programs and a size-52 Label3D holds the damage-number
  glyph atlas. They stay resident after the boot warmup so the first real cast
  or hit does not rebuild a program that the warmup already compiled.
- **All damage-number digits warmed** — a `0123456789` Label3D at the real
  damage-number size/raster settings renders during the warmup, so the first
  hit does not rasterize a new glyph into the atlas.
- **Silent audio-stream warmup** — on the first user gesture (when WebAudio is
  allowed to start), every baked cast/impact/chant/voice stream is played once
  at −80 dB on its real bus. This moves first-play backend initialization out of
  the first spell cast while staying inaudible.
- **No shadow passes for VFX** — projectile trails, bursts, and walls no longer
  cast shadows.
- **Real-wizard shield + hit-flash warm-up** — the actual round wizards briefly
  show their shield bubble and white hit flash at build time, compiling the
  per-wizard Aegis and damage-flash materials before a player can trigger them.
- **`LoadingScreen`** — covers the audio bake and warm-up with a deliberate
  boot screen instead of a frozen menu.
- **`.gdignore` files** in every generated/tooling folder. Godot no longer scans
  or imports build output, screenshots, docs images, or tool caches.
- **Web export** now excludes those trees: bundle dropped from ~43.2 MB to
  **38.9 MB** (pck).
- **Fresh-editor check**: deleted `.godot`, opened the GUI editor with
  `--editor --quit`; exit 0, no crash.

## Measured

Machine under normal load, Godot 4.7.2 GL Compatibility, 1280×720:

```
AUDIO: baked in 1036 ms (voice 191 ms)
PROFILE build_ms=23.0
PROFILE page=0 slot=0 Ember Bolt max_frame=20.8ms
PROFILE page=0 slot=1 Frost Bolt max_frame=19.3ms
PROFILE page=0 slot=2 Stone Ward max_frame=19.6ms
PROFILE page=0 slot=3 Arcane Beam max_frame=20.3ms
PROFILE page=1 slot=0 Storm Orb max_frame=22.1ms
PROFILE page=1 slot=1 Ember Nova max_frame=20.2ms
PROFILE page=1 slot=2 Frost Aegis max_frame=22.3ms
PROFILE page=1 slot=3 Hasty Void Bolt max_frame=19.6ms
PROFILE worst_frame=22.3ms
```

`--profile` now casts the **real Arena 2.0 spellbook** (both pages, all eight
slots in order) rather than a synthetic list. The previous list did not match
the shipped pages, so it could not reproduce a slot-specific first-use report.

The previous Aegis first-cast spike measured **123.4ms**; after the real-wizard
shield warm-up it is **19–20ms**. Web boot measured **4.67s** engine-ready with
audio at **1.04s**, zero console errors.

## Audio runtime audit

- **No per-frame group scan.** `Audio._process` used to rebuild the `wizards`
  group array and a seen dictionary every frame, even in menus. Wizards now
  register/unregister with the audio director, so only live wizards are polled.
  The `/root/Game` lookup is cached instead of resolving a node path three times
  per frame.
- **One chant note per frame.** A lagged frame or AI catch-up could previously
  enter the `typed > known` loop with several characters and start several
  voice + pluck pairs in one frame. It now plays only the newest rung and
  advances the counter; intended typing still gets one note per key.
- **Prioritised silent stream warmup.** On the first user gesture, the first
  six cast sounds, impact, chant resolve/fail, onsets, callouts, then the chant
  ladder are played once at −80 dB. The streams a first cast needs are
  initialised before the round intro ends; the long tail follows.
- **Debounced volume save.** The pause-menu slider emits on every step. The
  config write is now debounced by 250ms (and flushed on exit) instead of
  writing `audio.cfg` on every slider tick.
- **Bus changes only when needed.** The SFX pool no longer reassigns the bus
  while a player is already on it.

The remaining per-cast allocations (`play_spell_name` builds a small word/stream
array) are three elements long and are not frame-budget risks.

## Render pass detail

The spikes the profiler labels **Render 3D Depth** and **Render 3D Transparent**
were first-use pipeline compilation plus scene churn:

- The offscreen SubViewport warm-up did not share all main-viewport pipeline
  state (notably MSAA), so the real pass still compiled on first use.
- Adding an `OmniLight3D` per projectile changed the light list and forced extra
  depth/transparent work.
- Each cast allocated new transparent materials and particle materials.

Now the warm-up uses the real viewport and the scene's light/material set is
stable, so those passes compile during the boot screen and stay warm.

## Reproduce

```powershell
& "C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --path . -- --profile
```

The `--profile` mode boots, builds the arena, and casts all eight test slots;
it prints per-cast max frame time and the arena build time.

## Rendered FPS benchmark

`--fps` builds the shipped arena, keeps both wizards alive, warms the spellbook,
and drives continuous combat at 720p, 1080p, and 720p with vsync. Each row
reports average / 1% low / 0.1% low FPS, p95/p99/worst frame time, draw calls,
and every frame over 100ms. It is silent by default; add `--fps-audio` to hear
it.

```powershell
godot --path . -- --fps
godot --path . -- --fps --fps-only=720p --fps-seconds=20
godot --path . -- --fps --fps-cold          # no warm-up, first-use hitches
```

Run it on AC power, or at a healthy battery charge. At 9% on the Balanced plan
we measured ~600ms stalls every few seconds that looked like engine hitches;
the same build at 65% on battery ran stall-free. Windows throttles hard near
empty.

## Beam material regression

`Fx.beam` allocated a duplicate material per cast. A beam only lives 0.085s, so
the duplicate was freed before the next cast and the GL Compatibility driver
dropped its program: every beam paid a fresh shader compile. On the Radeon 840M
at 25% battery / Balanced that measured **~580ms per beam cast**.

`_beam_material` now returns one persistent material per color and resets its
alpha on each cast. The beam-only benchmark went from **16fps with a 580ms
stall every cast** to **434fps with a 7ms worst frame**. The trade-off is that
two same-color beams overlapping inside the 0.085s window share one fade; at the
0.32s cast interval that is not visible.

## Hit flash regression

`Wizard._flash()` set `emission_enabled = true` on the four body materials, then
`_clear_flash()` set it back to `false` 70ms later. In Godot 4 that flag is part
of the material's shader key, so each flip rebuilt the GL program.

Measured on the Radeon 840M with `--fps-hits`, which lands one real hit on the
player every 0.32s and does nothing else:

| hit path | avg | worst frame |
|---|---|---|
| full `take_damage` | 2.0 fps | 2312 ms |
| damage number only | 400.8 fps | 5 ms |
| **flash only** | **3.8 fps** | **2082 ms** |
| impact burst only | 414.6 fps | 8 ms |
| HUD damage flash only | 430.2 fps | 7 ms |

The material now comes from `Fx.flash_material()`, which compiles emission in
from the start with `emission_energy_multiplier = 0`. A hit only changes the
multiplier — a uniform, not a shader variant. Full hit path went from 2.0 to
**392 fps / 18ms worst frame** on battery, and to **533 fps / 6ms worst frame**
on AC with current drivers.

## Reference numbers (AC, Radeon 840M)

| pass | avg | 1% low | 0.1% low | worst |
|---|---|---|---|---|
| 720p, 25s sustained combat (AC) | 542.8 | 266.3 | 139.1 | 8.7 ms |
| 720p, 20s sustained combat (battery 65%) | 422.2 | 184.2 | 104.5 | 11.7 ms |
| 1080p, 12s (AC) | 255.0 | 162.3 | 99.7 | 11.6 ms |
| 720p + vsync (AC) | 59.9 | 54.4 | 52.9 | 18.9 ms |

The 1080p pass renders at 2880x1620 on this laptop because of Windows DPI
scaling, so treat it as a ~3K number.

## Is the boot warm-up still needed?

`--profile` reports `boot_ms`, and `--no-warmup` skips `SpellWarmup` for
comparison. Measured by deleting `user://shader_cache` between runs:

| shader cache | warm-up | boot | worst first cast |
|---|---|---|---|
| warm | yes | 1578 ms | 18.8 ms |
| warm | no | 1384 ms | 19.5 ms |
| cold | no | 1386 ms | **102.4 ms** (Stone Ward) |
| cold | yes | 2368 ms | 30.1 ms |

On a warm cache the warm-up costs ~0.2s and buys nothing measurable. On a cold
cache (new driver, first install, cleared cache) it costs ~1s and removes a
one-time 40-100ms hitch on wall, nova, and beam.

### Why Stone Ward's first cast is the worst

The first Stone Ward is a one-time GPU pipeline compile for the wall's
transparent, emissive box; it is not cast logic. Three things pin it down:

- The cast itself costs ~4ms of script. The rest of the frame is the draw.
- Making the wall mesh invisible at spawn drops the same first-cast frame from
  ~130ms to the 19ms baseline, with nothing else changed.
- On a cold cache the wall is **112ms**; on a warm cache it is **17.5ms**, and
  every later wall in the same run stays at ~18ms.

The wall is the only large transparent body created at cast time. Its body and
trim materials are new instances every cast, so the first draw is the first time
the driver builds that pipeline. The boot warm-up already spawns and renders
every element x form, walls included, in the real viewport, which is why the
first real Stone Ward is cheap after it.

A partial pre-render is not enough: rendering one real `SpellWall` at boot in a
SubViewport, or in the main viewport before the arena environment exists, only
brings the cold cost down to ~45-55ms. The remaining cost needs the real arena
viewport, which is what `SpellWarmup` uses.

The `LoadingScreen` is still required either way: `Audio.prepare()` bakes the
procedural bank synchronously and takes 1.2-2s. Only the shader half is
optional. It is kept because the Web export is a shipping target — browsers
have no persistent shader cache, so the first cast there is the worst case the
warm-up exists for.


