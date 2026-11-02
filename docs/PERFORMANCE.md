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
- **`SpellWarmup`** — one offscreen `SubViewport` builds an arena, two wizards,
  and every spell form/effect once. All shader variants compile there instead of
  during the first duel.
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
AUDIO: baked in 873 ms (voice 159 ms)
PROFILE build_ms=23.4
PROFILE page=0 slot=0 max_frame=19.7ms
PROFILE page=0 slot=1 max_frame=20.9ms
PROFILE page=0 slot=2 max_frame=18.4ms
PROFILE page=0 slot=3 max_frame=19.2ms
PROFILE page=1 slot=0 max_frame=18.7ms
PROFILE page=1 slot=1 max_frame=19.7ms
PROFILE page=1 slot=2 max_frame=20.3ms
PROFILE page=1 slot=3 max_frame=21.3ms
PROFILE worst_frame=21.3ms
```

Without the warm-up, the first cast and first battle frame were the visible
hitches. With it, no cast exceeded ~21ms.

## Reproduce

```powershell
& "C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --path . -- --profile
```

The `--profile` mode boots, builds the arena, and casts all eight test slots;
it prints per-cast max frame time and the arena build time.
