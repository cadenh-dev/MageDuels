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
- **Stable light count** — per-projectile and per-wall `OmniLight3D` nodes were
  removed. The arena now owns two pooled spell lights created at build time, so
  casting never changes the scene's light list or forces pipeline rebuilds.
- **Material reuse** — projectile core/halo/trail and impact-burst materials are
  cached per color instead of allocated on every cast.
- **No shadow passes for VFX** — projectile trails, bursts, and walls no longer
  cast shadows.
- **Real-wizard shield warm-up** — the actual round wizards briefly show their
  shield bubble at build time, compiling the per-wizard Aegis material before a
  player can cast it.
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
AUDIO: baked in 878 ms (voice 162 ms)
PROFILE build_ms=25.6
PROFILE page=0 slot=0 max_frame=22.4ms
PROFILE page=0 slot=1 max_frame=20.0ms
PROFILE page=0 slot=2 max_frame=20.1ms
PROFILE page=0 slot=3 max_frame=19.1ms
PROFILE page=1 slot=0 max_frame=20.8ms
PROFILE page=1 slot=1 max_frame=19.6ms
PROFILE page=1 slot=2 max_frame=19.1ms
PROFILE page=1 slot=3 max_frame=23.4ms
PROFILE worst_frame=23.4ms
```

The previous Aegis first-cast spike measured **123.4ms**; after the real-wizard
shield warm-up it is **19–20ms**. Without the warm-up, the first cast/battle
frame was the visible hitch.

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
