# SHIFTCAST — itch.io submission kit

## Pitch

SHIFTCAST is a 2.5D wizard duel where you craft spells from runes and cast them by
typing. Build two pages of eight spells, then outplay a named archmage across a
best-of-three. Quickcasts are instant; planting your feet and typing an incantation
unleashes an **overcast** at +80% damage, full mana, and a 0.9s hold — any direct hit
breaks it. The arena's element shifts every round and empowers matching spells.

Built for **Game Off 2026** (theme: **SHIFT**) in Godot 4.7.2 with a GL Compatibility,
single-threaded web build that runs in the browser.

## Tags

wizard, duel, typing, spell-crafting, runes, 2.5d, web, godot, fantasy, strategy, pvp

## Cover image

- Size: 630 x 500 px (itch cover)
- Format: PNG/JPEG, under 1 MB recommended
- Source: title screen with the SHIFTCAST logo; keep the rune ring visible.

## Animated GIF

- Size: 640 x 360 px
- Length: 5–10 seconds, looping
- File size: under 6 MB
- Content: a fire bolt hit → page shift → typed overcast → victory. The chant
  panel and `SHIFT` page flip are the signature shots.

## Screenshots (3)

1. Title screen (1280 x 720)
2. Mid-duel with HUD, chant panel, and the rival's `CHANTING` telegraph (1280 x 720)
3. Victory / results screen (1280 x 720)

## Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Aim |
| `1`–`4` | Quickcast the spell in that slot |
| `Space` | Begin chanting the selected spell |
| Type + `Enter` | Complete the incantation → Overcast |
| `Shift` | Swap spell page (A ↔ B) |
| `Esc` | Pause; cancel a chant while chanting |

## Credits

- Design, code, and procedural art: SHIFTCAST team.
- Fonts: Cinzel and Rajdhani, SIL Open Font License. See
  `assets/fonts/OFL-Cinzel.txt` and `assets/fonts/OFL-Rajdhani.txt`.
- Engine: Godot 4.7.2 (GL Compatibility).
- Audio: fully procedural, synthesized at startup into `AudioStreamWAV` banks.
  No third-party samples.

## Pre-flight checklist

- [ ] Boots under 10 seconds on itch.io (measured ~6.3 s locally with audio)
- [ ] Audio unlocks on first click/tap
- [ ] Full best-of-three duel completes without errors
- [ ] No console errors in browser devtools
- [ ] Threads disabled (single-threaded build) for the itch iframe
- [ ] VRAM texture compression for desktop enabled
- [ ] PWA **disabled** (no stale service worker / cache)
- [ ] `export_presets.cfg` committed; `build/` not committed
- [ ] Zip the contents of `build/web/` (index.html at the zip root), not the folder
- [ ] Test the uploaded build in the itch iframe, not just locally
