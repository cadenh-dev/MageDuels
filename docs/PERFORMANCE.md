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
