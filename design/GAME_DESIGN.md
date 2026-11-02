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

1. **Choose a wand** — each wand has an elemental affinity and a stat identity.
2. **Craft two pages of four spells** — combine Element + Form + Modifier runes.
3. **Duel** — dodge, quickcast, and find windows to plant your feet and chant.
4. **Win 2 of 3 rounds** — the arena's shifting element changes each round.

## Combat

### Resources

| Resource | Value | Notes |
|---|---|---|
| Health | 100 | No regeneration during a round |
| Mana | 100 (wand-modified) | Regenerates ~12/s |
| Overcast | +80% power, full mana | Requires a 0.9s hold and a completed incantation; direct damage breaks it |

### Controls

| Input | Action |
|---|---|
| WASD | Move (arcade, camera-relative) |
| Mouse | Aim |
| 1–4 | Quickcast spell in that slot (weak, full cost) |
| Space | Begin chanting the last-selected spell |
| Type + Enter | Complete the incantation → Overcast |
| F / RMB / LT (hold) | Assisted overcast — 1.4s, no typing |
| Mouse wheel | Cycle selected spell slot |
| Shift / RB | Swap spell page |
| Esc / Start | Pause |

**Gamepad:** left stick move, right stick aim, face buttons cast, `LT` assisted
overcast, `RB` swap, `Start` pause. Menus navigate with D-pad/stick + `A`.
Releasing `LT` in the 0.9–1.2s gold window is a PERFECT overcast.

While chanting you are **rooted**. Movement and quickcast are locked until the
incantation completes or is cancelled. A chant needs 0.9s of hold time and is
**interrupted by direct damage**, so it is a wager, not a discount. The 1.4s
assisted hold is the accessible alternative to typing.

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

**Forms** (5)

| Form | Word | Behaviour |
|---|---|---|
| Bolt | MITT | Fast projectile |
| Orb | QUAERO | Slow homing projectile |
| Beam | RADIA | Instant ray |
| Nova | RUPTA | Point-blank area burst |
| Wall | MURUS | Temporary barrier |

**Modifiers** (4)

| Modifier | Word | Effect |
|---|---|---|
| Split | TRIA | Three projectiles, 62% damage each |
| Heavy | GRAVIS | +45% damage, slower, more knockback |
| Quick | CITUS | Faster, cheaper cooldown, -18% damage |
| Pierce | PUNGO | Passes through one target |

Incantation = element word + form word + optional modifier word, e.g.
`IGNA MITT`, `GLACIA RUPTA`, `TERRA MITT GRAVIS`.

## 2.5D presentation

- Full 3D low-poly arena viewed from a raised side camera.
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
