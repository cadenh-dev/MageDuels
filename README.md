<img src="assets/icon.svg" width="72" height="72" alt="">

# SHIFTCAST

**Craft the rune. Shift the duel.**

A 2.5D wizard duel for [Game Off 2026](https://itch.io/jam/game-off-2026) (theme: **SHIFT**).
Build two pages of spells from elemental runes, then fight a named archmage in a
best-of-three. Quickcast with the number keys, or plant your feet and **type the
incantation** to overcast.

Made with Godot 4.7.2. Browser-first, procedural art, no external gameplay assets.

---

## Play

> Web build: _link TBD_

### Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Aim |
| `1`–`4` | Quickcast the spell in that slot |
| `Space` | Begin chanting the selected spell |
| Type + `Enter` | Complete the incantation → **Overcast** |
| `Shift` | Swap spell page (A ↔ B) |
| `Esc` | Pause / cancel a chant |

A chant roots you for at least **0.9 seconds**, costs full mana, deals **+80%**
damage, and is **broken by any direct hit**. The rival follows the same rules.

### The runes

- **Elements:** Fire, Frost, Storm, Earth, Arcane, Void
- **Forms:** Bolt, Orb, Beam, Nova, Ward
- **Modifiers:** Split, Heavy, Quick, Pierce

An incantation is the element word plus the form word (plus an optional modifier
word), e.g. `IGNA MITT` or `GLACIA RUPTA GRAVIS`. The arena's element changes each
round and adds +15% damage to matching spells.

---

## Develop

Requires **Godot 4.7.2** (GL Compatibility renderer).

```powershell
# Run the game
godot --path .

# Headless checks
godot --headless --path . -- --test      # spell math, wall/beam/nova, interrupts
godot --headless --path . -- --flow      # round 1 -> round 2 -> match end -> rematch
godot --headless --path . -- --lifetime  # 10 duel rebuilds, orphan check
godot --headless --path . -- --ai        # rival telegraph, completion, interrupt
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
scripts/ui/       title, wand select, crafting, HUD, results
scripts/debug/    headless combat / flow / lifetime / AI tests
design/           game design and jam plan
```

## Credits

- Fonts: [Cinzel](https://fonts.google.com/specimen/Cinzel) and
  [Rajdhani](https://fonts.google.com/specimen/Rajdhani), SIL Open Font License
  (see `assets/fonts/OFL-*.txt`).
- Everything else is procedural or generated in-engine.
