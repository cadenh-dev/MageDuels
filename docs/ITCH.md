# SHIFTCAST — itch.io submission kit

## Pitch

SHIFTCAST is a 2.5D wizard duel where you start with the Apprentice Wand, win
three rounds, and draft a boon after each one — the loser picks first. Boons add
runes, switch wands, or boost stats. Plant your feet and **type the incantation**
to overcast (default **Chant-only** cast mode; **Classic** quickcast is selectable
on the main menu). Built for **Game Off 2026** (theme: **SHIFT**) in Godot
4.7.2 with a GL Compatibility, single-threaded web build.

## Tags

wizard, duel, typing, spell-crafting, runes, 2.5d, web, godot, fantasy, strategy, pvp

## Cover image

- Size: 630 x 500 px (itch cover)
- Format: PNG/JPEG, under 1 MB recommended
- Source: `docs/media/cover.png` (title screen — rune ring visible)

## Animated GIF

- Size: 640 px wide (`docs/media/preview.gif`, ~596 KB)
- Length: 5 seconds, looping
- Content: live duel — quickcasts, arena shift, spell VFX

## Screenshots (3)

1. Mid-duel with spells (`docs/media/screenshot-1.png`, 1280 × 720)
2. Typed overcast / incantation HUD (`docs/media/screenshot-2.png`, 1280 × 720)
3. Boon draft after a round (`docs/media/screenshot-3.png`, 1280 × 720)

## Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Aim |
| `1`–`4` | Quickcast the spell in that slot |
| `Space` | Begin chanting the selected spell |
| Type + `Enter` | Complete the incantation → Overcast |
| `F` / Right Mouse / `LT` (hold) | Assisted overcast — auto-casts after 2.3s |
| Mouse wheel | Cycle the selected spell slot |
| `Shift` / `RB` | Swap spell page (A ↔ B) |
| `C` / `R3` | Toggle follow camera ↔ arena camera |
| `Esc` / `Start` | Pause; cancel a chant while chanting |

**Gamepad:** left stick move, right stick aim, `A/B/X/Y` cast slots 1–4, `RB`
swap page, `LT` assisted overcast, `Start` pause. Release `LT` in the 1.6–1.95s
gold window for a PERFECT overcast, or hold to 2.3s to auto-cast. Menus navigate
with the D-pad or left stick and `A`. **ENTER THE ARENA** starts the match
directly.

## Credits

- Design, code, and procedural art: SHIFTCAST team.
- Fonts: Cinzel and Rajdhani, SIL Open Font License. See
  `assets/fonts/OFL-Cinzel.txt` and `assets/fonts/OFL-Rajdhani.txt`.
- Engine: Godot 4.7.2 (GL Compatibility).
- Audio: fully procedural, synthesized at startup into `AudioStreamWAV` banks.
  No third-party samples.

## Upload settings (itch.io)

| Setting | Value |
|---|---|
| Kind of project | **HTML** |
| Upload file | `dist/shiftcast-web.zip` |
| Play in browser | **Yes** — tick “This file will be played in the browser” |
| Embed size | **1280 × 720** (matches `project.godot` viewport) |
| Fullscreen button | **On** |
| SharedArrayBuffer / threads | **Off** (single-threaded export) |
| PWA / cross-origin isolation headers | **Off** (preset: PWA disabled) |

**After upload:** test in a **private/incognito** window (itch caches builds
aggressively). **Click inside the game iframe** before keyboard input. Audio
unlocks on the first click or keypress.

## Butler (CLI upload)

```powershell
$env:BUTLER_API_KEY="..."
butler push build/web <your-itch-user>/<game-slug>:html5
```

Mark the `html5` channel as **browser-playable** once in the itch dashboard
(butler does not set that flag).

## Pre-flight checklist

- [x] Web export built (`build/web/index.html`, `.js`, `.wasm`, `.pck`)
- [x] Release zip at zip root (`dist/shiftcast-web.zip`, index.html not in a subfolder)
- [x] Threads disabled (`variant/thread_support=false`) for the itch iframe
- [x] VRAM texture compression for desktop enabled
- [x] PWA **disabled** (no stale service worker / cache)
- [x] `export_presets.cfg` committed; `build/` not committed
- [x] Store media in `docs/media/` (cover, GIF, three screenshots)
- [ ] Boots under 10 seconds on itch.io (measured ~6.3 s locally with audio)
- [ ] Audio unlocks on first click/tap (verify in itch iframe)
- [ ] Full first-to-three duel with drafts completes without errors (browser test)
- [ ] No console errors in browser devtools (browser test)
- [ ] Test the uploaded build in the itch iframe, not just locally
