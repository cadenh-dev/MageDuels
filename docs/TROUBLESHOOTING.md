# Editor / Import Troubleshooting

## The editor crashes on a fresh pull

The repository now has `.gdignore` in every generated/tooling folder
(`build/`, `dist/`, `screenshots/`, `docs/`, `design/`, `tools/`, `.opencode/`,
`graphify-out/`). Godot should not scan or import those.

A `git pull` does **not** delete your local `.godot/` import cache. If that cache
was built before those folders were ignored, it can reference missing/corrupt
imports and crash the editor on boot.

Fix once:

```powershell
powershell -ExecutionPolicy Bypass -File tools/clean_godot_cache.ps1
```

Then reopen the project. Godot rebuilds `.godot/` and reimports the fonts,
shaders, and scripts.

A genuinely fresh clone was tested: import + a 20-second editor session stayed
up with no crash on Godot 4.7.2 (GL Compatibility).

## Are the fonts imported correctly?

Yes.

- `assets/fonts/Cinzel.ttf` (variable, weight axis) and the three Rajdhani
  weights are present, valid, and have committed `.import` sidecars.
- Deleting the `.import` files and reopening the editor regenerates them
  successfully.
- The title/menu/UI screenshots use Cinzel and Rajdhani; the fonts are rendering,
  not falling back.

Do not delete the `.import` files to "fix" the editor — remove `.godot` instead.

## If it still crashes

1. Close the editor before `git pull`; a file watcher running during a pull can
   produce transient import errors.
2. Run the editor from a terminal and capture the tail:

```powershell
& "C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --path . --editor --verbose
```

3. Check `%APPDATA%\Godot\app_userdata\SHIFTCAST\logs\` and the Windows
   Application event log for a faulting module.
4. Report the last 40 lines and whether the crash is at import, opening a scene,
   or switching to the 3D tab. A GPU/editor crash needs the stack, not a font
   guess.

## Why the editor-only crash is hard to reproduce

The game runtime is GL Compatibility and starts with the console binary; the
editor uses its own OpenGL window and restores per-user layout/import state. A
project that runs perfectly can still crash an editor with a stale `.godot`
cache or a broken GPU driver. The clean-cache step separates those cases.
