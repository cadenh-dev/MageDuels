<img src="assets/icon.svg" width="72" height="72" alt="">

# SHIFTCAST

**Draft the boon. Shift the duel.**

A 2.5D wizard duel for [Game Off 2026](https://itch.io/jam/game-off-2026) (theme: **SHIFT**).
Start with the **Apprentice Wand**, win three rounds, and draft a boon after each
round — the loser picks first. Quickcast with the number keys, or plant your feet
and **type the incantation** to overcast. Boons change your wand, your spellbook,
and your stats for the rest of the match.

Made with Godot 4.7.2. Browser-first, procedural art, no external gameplay assets.

---

## Play

> Web build: **TODO** — upload `dist/shiftcast-web.zip` to itch.io (see `docs/ITCH.md`).

**Media:** cover, GIF, and screenshots live in [`docs/media/`](docs/media/).

### Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Aim |
| `1`–`4` | Quickcast the spell in that slot |
| `Space` | Begin chanting the selected spell |
| Type + `Enter` | Complete the incantation → **Overcast** |
| `F` / Right Mouse / `LT` (hold) | **Assisted overcast** — auto-casts after 2.3s, no typing |
| Mouse wheel | Cycle the selected spell slot |
| `Shift` / `RB` | Swap spell page (A ↔ B) |
| `C` / `R3` | Toggle follow camera ↔ arena camera |
| `Esc` / `Start` | Pause / cancel a chant |

**Gamepad:** left stick moves, right stick aims, `A/B/X/Y` cast slots 1–4, `RB`
swaps pages, `LT` holds an assisted overcast, `Start` pauses. Menus are navigable
with the D-pad or left stick and `A`.

A chant roots you for at least **1.6 seconds**, costs full mana, deals **×2.4**
damage, and is **broken by any direct hit**. Typing is the strong, high-skill
route; the 2.3s assisted hold is the accessible **×1.9** route. Releasing the
hold in the **gold window (1.6–1.95s)** is a **PERFECT overcast** (+15% damage),
so the pad has a hard mode as well. If you fumble the incantation but typed at
least **half** of it, ENTER still fires a **fizzle** at **×0.5** power — full
mana, so it is a consolation rather than a plan. Every cast is named in the HUD
and the rune words are spoken by the synthetic voice. The rival follows the same
rules. **Ward** blocks projectiles; **Aegis** is a personal shield that absorbs
35 damage for 3s.

### The runes

Both duelists start with the same Apprentice spellbook. After each round, the
loser picks a boon first; boons add runes, switch wands, or boost stats, and last
for the whole match. First to **three** rounds wins.

- **Elements:** Fire, Frost, Storm, Earth, Arcane, Void
- **Forms:** Bolt, Orb, Beam, Nova, Ward, Aegis
- **Modifiers:** Split, Heavy, Quick, Pierce, Track

An incantation is the element word plus the form word (plus an optional modifier
word), e.g. `ARDE DARDE` or `FREZA BREXA GRAVE`. `TRACK` makes every projectile
curve toward the rival, so `ARDE DARDE SEQA` is a seeking fire bolt. The arena's
element changes each round and adds +15% damage to matching spells.

---

## Develop

Requires **Godot 4.7.2** (GL Compatibility renderer).

```powershell
# Run the game
godot --path .

# Headless checks
godot --headless --path . -- --test      # spell math, wall/beam/nova, interrupts
godot --headless --path . -- --flow      # 3 rounds + drafts -> match end -> rematch
godot --headless --path . -- --lifetime  # 10 duel rebuilds, orphan check
godot --headless --path . -- --ai        # rival telegraph, completion, interrupt
godot --headless --path . -- --input     # unicode typing, assist/perfect, controller maps
godot --headless --path . -- --balance   # all wand x rune stat combinations
godot --headless --path . -- --audio-selftest
godot --path . -- --fps                  # rendered FPS benchmark (720p/1080p/vsync)
godot --headless --path . res://scenes/NetTest.tscn  # 2-client sync spike
```

### Web export

```powershell
godot --headless --path . --export-release "Web" build/web/index.html
python -m http.server 8060 --directory build/web
```

Threads are **off** so the build runs on itch.io without COOP/COEP headers.

---

## Structure

```
scripts/core/     rune data, spell math, global game state
scripts/world/    procedural arena, wizard, projectiles, walls, VFX
scripts/ai/       rival state machine and wand archetypes
scripts/ui/       title, boon draft, HUD, results
scripts/debug/    headless combat / flow / lifetime / AI tests
design/           game design and jam plan
```

## Voice pipeline

The runtime uses the baked procedural voices in `scripts/audio/voice_synth.gd`
(player + rival profiles, no external samples). A rendered singing-voice pipeline
(OpenUTAU + the Tsukuyomi-chan UTAU voicebank) and a starter chant project live in
`tools/voice/`; see that README for licensing and render steps. The voicebank is
not committed and must not be redistributed.

## Credits

- Fonts: [Cinzel](https://fonts.google.com/specimen/Cinzel) and
  [Rajdhani](https://fonts.google.com/specimen/Rajdhani), SIL Open Font License
  (see `assets/fonts/OFL-*.txt`).
- Audio: synthesized procedurally at startup (SFX, chant ladder, adaptive music
  bed) into `AudioStreamWAV` banks — no third-party samples.
- Everything else is procedural or generated in-engine.
