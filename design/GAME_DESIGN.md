# SHIFTCAST — Design Doc

> Game Off 2026 · Theme: **SHIFT** · Godot 4.7 · Browser-first 2.5D

## Pitch

**SHIFTCAST** is a 2.5D online wizard duel where you build your own spells from runes,
then cast them by typing incantations under pressure.

Shift your spellbook. Shift your feet. Shift the duel.

## Why it fits the theme

- The **Shift** key swaps between two prepared spell pages mid-duel.
- Casting **shifts** you between mobile quickcasting and rooted, high-power chanting.
- The arena itself shifts element every round, empowering one affinity.

## Core loop

1. **Enter the arena** with the Apprentice Wand and a shared starting spellbook.
2. **Duel** — first to three rounds; the arena element shifts each round.
3. **Draft a boon** after each round — the loser picks first, then the winner.
   Boons add runes, switch wands, or boost stats, and persist for the match.
4. **Win three rounds** to take the match.

## Combat

### Resources

| Resource | Value | Notes |
|---|---|---|
| Health | 100 | No regeneration during a round |
| Mana | 100 (wand-modified) | Regenerates ~12/s |
| Overcast | Typed ×2.4 damage, assisted ×1.9, full mana | Requires a 1.6s typed hold (2.3s assisted) and a completed incantation; direct damage breaks it |
| Fizzle | ×0.5 damage, full mana and cooldown | A failed typed incantation that reached at least 50% of the runes |

### Controls

| Input | Action |
|---|---|
| WASD | Move (arcade, camera-relative) |
| Mouse | Aim |
| 1–4 | Quickcast spell in that slot (weak, full cost) |
| Space | Begin chanting the last-selected spell |
| Type + Enter | Complete the incantation → Overcast |
| F / RMB / LT (hold) | Assisted overcast — 2.3s, no typing, ×1.9 damage |
| Mouse wheel | Cycle selected spell slot |
| Shift / RB | Swap spell page |
| C / R3 | Toggle camera |
| Esc / Start | Pause |

**Gamepad:** left stick move, right stick aim, face buttons cast, `LT` assisted
overcast, `RB` swap, `Start` pause. Menus navigate with D-pad/stick + `A`.
Releasing `LT` in the 1.6–1.95s gold window is a PERFECT overcast (+15% damage).

While chanting you are **rooted**. Movement and quickcast are locked until the
incantation completes or is cancelled. A typed chant needs 1.6s of hold time and
is **interrupted by direct damage**, so it is a wager, not a discount. Typing is
the stronger path (×2.4); the 2.3s assisted hold is the accessible ×1.9
alternative. A failed typed incantation still fires a **fizzle** at ×0.5 damage
if at least half of the runes were typed (full mana and cooldown); below half it
cancels. Every cast also announces its spell name in the HUD and speaks its
rune words through the synthetic voice.

### Runes

**Elements** (6)

| Rune | Word | Effect |
|---|---|---|
| Fire | IGNA | Burn: 6 damage over 3s |
| Frost | GLACIA | Chill: 40% slow for 2s |
| Storm | VOLTA | Chain: 50% damage to a nearby second target |
| Earth | TERRA | Knockback and a brief stagger |
| Arcane | ARCANA | Mana burn: steals 12 mana |
| Void | VANA | Lifedrain: heals 25% of damage dealt |

**Forms** (6)

| Form | Word | Behaviour |
|---|---|---|
| Bolt | MITT | Fast projectile |
| Orb | QUAERO | Slow homing projectile |
| Beam | RADIA | Instant ray |
| Nova | RUPTA | Point-blank area burst |
| Wall | MURUS | Temporary barrier |
| Aegis | TUTELA | Personal shield: 35 damage / 3s |

**Modifiers** (5)

| Modifier | Word | Effect |
|---|---|---|
| Split | TRIA | Three projectiles, 62% damage each |
| Heavy | GRAVIS | +45% damage, slower, more knockback |
| Quick | CITUS | Faster, cheaper cooldown, -18% damage |
| Pierce | PUNGO | Passes through one target |
| Track | SEQUI | Every projectile homes toward the rival |

Incantation = element word + form word + optional modifier word, e.g.
`IGNA MITT`, `GLACIA RUPTA`, `TERRA MITT GRAVIS`, `IGNA MITT SEQUI`
(Fire + Track: seeking bolts).

### Wands

Both duelists start with the balanced **Apprentice Wand** (no affinity). The draft
can switch either duelist to Emberwood, Frostglass, Stormbone, or Voidheart. Each
wand has its own affinity and stat identity; boons stack on top.

### Boon draft

After every round, the loser picks first from a three-card offer, then the winner
picks from the remainder. Cards are stat boons (+HP, +mana, +damage, +cast speed,
+move speed, +starting shield), wand switches, or rune replacements for page B
slot 4. Boons persist for the match.

## 2.5D presentation

- Full 3D low-poly arena viewed from a raised side camera.
- `C` / right-stick click toggles a follow camera centered on the player.
- Gameplay happens on the XZ plane; depth is readable but shallow.
- Emissive materials, floating runes, cosmic backdrop, simple light rigs.
- All meshes generated procedurally so the jam build has no art-asset dependencies.

## Online

Planned architecture: authoritative Godot headless server over WebSocket, with the
browser client connecting to a `wss://` endpoint.

- **Milestone 1 (jam build):** vs AI, plus local two-player on one keyboard.
- **Milestone 2:** dedicated server + matchmaking room codes.

The combat simulation is kept in plain GDScript with deterministic spell math so
it can be moved server-side without a rewrite.

## Scope guardrails

- One arena, one mode, three rounds.
- Ship the duel before the meta.
- Audio: a small set of procedural or CC0 sounds.
- Browser build is the submission target; desktop export is a bonus.
