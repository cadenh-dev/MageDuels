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
| Fizzle | ×0.5 damage, full mana | A failed typed incantation that reached at least 50% of the runes |

### Controls

Casting follows `design/SPELLCRAFT.md` section 2 (type to prime, release to
fire). Rune words use only left-hand letters.

| Input | Action |
|---|---|
| WASD | Move (arcade, camera-relative) |
| Mouse | Aim |
| 1–4 | Chant mode: start chanting that slot. Classic: quickcast (×1.0) |
| Space | Classic: start chanting the selected slot |
| Type the rune words | Chant; the spell **auto-primes** once typed and charged (no confirm key) |
| Left Click / Space / RT | Release the primed spell (Enter is a silent alias) |
| F / RMB / LT (hold) | Assisted overcast: hold to charge, fires on release, ×1.9 |
| Mouse wheel | Cycle selected spell slot |
| Shift / RB | Swap spell page (allowed while primed) |
| C / R3 | Toggle camera |
| Esc / Start | Cancel chant, discard primed spell, or pause |

**Gamepad (chant mode):** hold `LB`, pick a slot with the stick, let go; `A`,
`B`, `X` enter words 1–3. The spell primes when the last word lands and the
charge completes; move with the left stick, aim with the right, release with
`RT`. `Back` cancels. Releasing `LT` in the 1.6–1.95 s gold window is a PERFECT
assisted overcast (+15%).

**Chanting** roots you (mouse aim still turns you) and halves mana regen. Charge
time is letters ÷ 8 s × the wand's cast speed (classic Space-chant keeps the
1.6 s minimum). A hit of 5+ damage, a stagger or a jolt breaks the chant;
nothing has been paid.

**Primed:** mana is paid at priming ("Not enough mana" collapses the chant).
You move at full speed and aim freely for at most 6 s, regen paused, with a
visible wand glow and rune ring. Hits do not remove it. Release fires at ×2.4
with a 10° **soft-lock** for bolts, orbs and beams. At 6 s it fizzles out and
the mana is lost. While primed you cannot start another chant.

**Early release:** Left Click / Space while still chanting fires a **fizzle**
(×0.5 power, half durations, full mana) if at least half the letters are typed
and the charge is done; below half nothing happens ("Keep chanting") and only
Esc cancels.

### Runes

**Elements** (6)

| Rune | Word | Effect |
|---|---|---|
| Fire | ARDE | Burn 6 over 3s; never solid; leaves burning ground |
| Frost | FREZA | Chill: 40% slow for 2s; a second chill freezes (0.6 s root) |
| Storm | ZAGRA | Jolt: 0.25 s stun that breaks chants; arcs and bounces |
| Earth | TERRA | Stagger 0.35 s and heavy knockback; solid, smashes ice |
| Arcane | SACRA | Mana burn 12; phases through solid walls; reflects |
| Void | VASTA | Drain 25%; pulls instead of pushing; absorbs projectiles |

**Forms** (6)

| Form | Word | Behaviour |
|---|---|---|
| Bolt | DARDE | Fast projectile |
| Orb | ASTRA | Slow homing projectile |
| Beam | RAZE | Instant ray |
| Nova | BREXA | Point-blank area burst |
| Ward | WARD | Placed barrier segment; the element decides what it blocks |
| Aegis | CETRA | Attached to the caster; the element decides what it does |

**Modifiers** (5)

| Modifier | Word | Effect |
|---|---|---|
| Split | TRES | Three projectiles, 62% damage each |
| Heavy | GRAVE | +45% damage, wall HP, shield absorb and zone dps; slower, more knockback |
| Quick | DEXT | Faster, cheaper mana, -18% damage |
| Pierce | WEDGE | Passes one target or one wall |
| Track | SEQA | Projectiles home toward the rival (Boulder, Ball Lightning, Singularity too) |

The form is only a shape; the element is the material. Each of the 36
element x form cells (Ember Dart, Flame Sheet, Stone Wall, Mirror Ward, Void
Shroud, ...) is specified in `design/SPELLCRAFT.md` section 3, including the
cross-material order for projectiles meeting wards.

Incantation = element word + form word + optional modifier word, e.g.
`ARDE DARDE`, `FREZA BREXA`, `TERRA DARDE GRAVE`, `ARDE DARDE SEQA`
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
