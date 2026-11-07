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
| `1`–`4` | Chant mode: start chanting that slot. Classic mode: quickcast it (×1.0) |
| `Space` | Classic mode: start chanting the selected slot |
| Type the rune words | Chant. When the words are typed **and** the charge is done, the spell **primes** on its own (no confirm key) |
| `Left Click` / `Space` / `RT` | **Release** the primed spell at your aim (`Enter` still works as a silent alias) |
| `F` / Right Mouse / `LT` (hold) | **Assisted overcast**: hold to charge (rooted), fires on release, no typing |
| Mouse wheel | Cycle the selected spell slot |
| `Shift` / `RB` | Swap spell page (A ↔ B), also while primed |
| `C` / `R3` | Toggle follow camera ↔ arena camera |
| `Esc` / `Start` | Cancel a chant, discard a primed spell, or pause |

**Gamepad:** left stick moves, right stick aims. In chant mode hold `LB`, pick a
slot with the stick and let go, then press `A`, `B`, `X` for words 1–3; the spell
primes when the last word lands and the charge completes, and `RT` releases it.
`Back` cancels. `RB` swaps pages, `LT` holds an assisted overcast, `Start`
pauses. Menus are navigable with the D-pad or left stick and `A`.

**Chanting** roots you (mouse aim still turns you) and halves mana regen. Every
rune word uses only left-hand letters (`QWERT ASDFG ZXCVB`), so the right hand
stays on the mouse. A typo resets the typed text; `Backspace` deletes a letter.
Charge time is letters ÷ 8 seconds (× the wand's cast speed). A hit of 5+
damage, an Earth stagger or a Storm jolt breaks the chant; nothing is paid yet.

**Primed:** mana is paid when the spell primes. You then move at full speed and
aim freely for up to **6 seconds** (mana regen paused) while your wand glows and a
rune ring floats over you, so the rival can see it coming. Hits do not remove a
primed spell. After 6 s it fizzles out and the mana is lost. Release with
`Left Click` / `Space` / `RT` for **×2.4** damage; projectile and beam spells
**soft-lock** onto the rival if your aim is within 10° and they are in range.

**Early release:** clicking while still chanting fires a **fizzle** right away if
at least half the letters are typed and the charge is done (×0.5 power, half
durations, full mana). Under half, nothing happens ("Keep chanting"); only `Esc`
cancels. The **assisted hold** charges for 2.3 s and fires at ×1.9; releasing in
the **gold window (1.6–1.95 s)** is a **PERFECT** overcast (+15%). Every cast is
named in the HUD and the rune words are spoken by the synthetic voice. The rival
follows the same rules.

### The runes

Both duelists start with the same Apprentice spellbook (page A: Ember Dart, Ice
Shard, Stone Wall, Arcane Ray; page B: Ball Lightning, Inferno Ring, Ice Armor,
Hasty Void Dart). After each round, the loser picks a boon first; boons add
runes, switch wands, or boost stats, and last for the whole match. First to
**three** rounds wins.

An incantation is the element word plus the form word (plus an optional
modifier word), e.g. `ARDE WARD`, `TERRA CETRA` or `FREZA BREXA GRAVE`.

| Element | Word | Form | Word | Modifier | Word |
|---|---|---|---|---|---|
| Fire | `ARDE` | Bolt | `DARDE` | Split | `TRES` |
| Frost | `FREZA` | Orb | `ASTRA` | Heavy | `GRAVE` |
| Storm | `ZAGRA` | Beam | `RAZE` | Quick | `DEXT` |
| Earth | `TERRA` | Nova | `BREXA` | Pierce | `WEDGE` |
| Arcane | `SACRA` | Ward | `WARD` | Track | `SEQA` |
| Void | `VASTA` | Aegis | `CETRA` | | |

**The form is only a shape** (fast bolt, slow orb, line beam, burst nova, placed
ward, attached aegis). **The element is the material**, and the material decides
what is solid, what it leaves behind and how it reacts to other materials:

- **Fire** (flame) is never solid. It burns, leaves burning ground and ignites
  what passes through it. A Flame Sheet blocks nothing but scorches whoever
  crosses it, and melts frost.
- **Frost** (ice) is brittle. It chills (a second chill while chilled freezes
  you in place for 0.6 s), slows projectiles and shatters into shards. An Ice
  Wall stops wizards but lets spells through, slowed and weakened.
- **Storm** (lightning) is instant. Hits jolt (a short stun that breaks chants),
  arc to nearby targets and bounce off walls.
- **Earth** (stone) is solid and heavy. It staggers, knocks back hard, smashes
  ice, and a Stone Wall blocks wizards, projectiles and beams until its HP runs
  out.
- **Arcane** (force) is weightless. It burns mana, phases through solid walls
  and reflects: a Mirror Ward sends enemy spells back at their caster.
- **Void** (gravity) pulls instead of pushing, drains health and swallows
  projectiles: a Rift eats enemy spells and heals you.

| | Bolt | Orb | Beam | Nova | Ward | Aegis |
|---|---|---|---|---|---|---|
| **Fire** | Ember Dart | Fireball | Flame Jet | Inferno Ring | Flame Sheet | Heat Aura |
| **Frost** | Ice Shard | Frost Globe | Freeze Ray | Rime Burst | Ice Wall | Ice Armor |
| **Storm** | Spark | Ball Lightning | Chain Lance | Thunderclap | Tesla Fence | Static Shell |
| **Earth** | Stone Bolt | Boulder | Fault Line | Quake | Stone Wall | Stoneskin |
| **Arcane** | Arcane Missile | Mana Sphere | Arcane Ray | Repulse | Mirror Ward | Mana Shield |
| **Void** | Void Dart | Singularity | Siphon | Implosion | Rift | Void Shroud |

A modifier adds its prefix to the name ("Heavy Inferno Ring", "Seeking Ember
Dart"). `SEQA` (Track) makes projectiles home in, Boulder and Ball Lightning
included; `WEDGE` (Pierce) passes one target or one wall. The arena's element
changes each round and adds +15% damage to matching spells. The full rules for
every cell are in [`design/SPELLCRAFT.md`](design/SPELLCRAFT.md).

---

## Develop

Requires **Godot 4.7.2** (GL Compatibility renderer).

```powershell
# Run the game
godot --path .

# Headless checks
godot --headless --path . -- --spellcraft  # all 36 cells, ward order, statuses, scaling
godot --headless --path . -- --test      # spell math, wall/beam/nova, interrupts
godot --headless --path . -- --flow      # 3 rounds + drafts -> match end -> rematch
godot --headless --path . -- --lifetime  # 10 duel rebuilds, orphan check
godot --headless --path . -- --ai        # rival telegraph, completion, interrupt
godot --headless --path . -- --input     # unicode typing, assist/perfect, controller maps
godot --headless --path . -- --balance   # all wand x rune combinations + cell value outliers
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
