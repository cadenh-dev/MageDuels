# SHIFTCAST Spellcraft v3

Status: design approved for implementation (2026-11-07). Base branch: `feature/online`.
This replaces the rune and casting sections of `design/GAME_DESIGN.md` and the
README "Controls" / "The runes" sections.

Three changes:

1. **Constructive spellcraft.** A form is only a shape. The element is the
   material, and the material decides collision, hazards and tactics.
2. **Ergonomic casting.** Type to *prime* the wand, then move and aim freely and
   release with Left Click or Space. Rune words use only left-hand letters.
   No Enter.
3. **Emberwood fix.** Fire spells get a clean +25% (15% affinity + 10% wand).

---

## 1. Rune words (left-hand alphabet)

Every rune word uses only `Q W E R T A S D F G Z X C V B`, so the left hand types
the whole incantation from home position while the right hand stays on the
mouse. Words are 3–5 letters. Within each group the first letters differ.

| Element | Word | | Form | Word | | Modifier | Word |
|---|---|---|---|---|---|---|---|
| Fire | `ARDE` | | Bolt | `DARDE` | | Split | `TRES` |
| Frost | `FREZA` | | Orb | `ASTRA` | | Heavy | `GRAVE` |
| Storm | `ZAGRA` | | Beam | `RAZE` | | Quick | `DEXT` |
| Earth | `TERRA` | | Nova | `BREXA` | | Pierce | `WEDGE` |
| Arcane | `SACRA` | | Ward (wall) | `WARD` | | Track | `SEQA` |
| Void | `VASTA` | | Aegis | `CETRA` | | | |

Incantation = element + form (+ modifier): `ARDE WARD`, `TERRA CETRA`,
`FREZA BREXA GRAVE`. Spaces are never typed.

Notes:
- The procedural voice speaks any word, so callouts keep working. With only A and
  E as vowels the chants sound more alike; acceptable for now.
- Old words (`IGNA`, `MURUS`, …) are removed everywhere: data, docs, README,
  tests, `tools/voice/README.md` kana table (mark that table as outdated if
  re-deriving kana is out of scope).

---

## 2. Casting rules

### States

```
idle ──(start chant)──▶ CHANTING ──(complete + charged)──▶ PRIMED ──(release)──▶ cast
                         │  rooted, typing                 │ free to move/aim
                         │                                 │ 6 s max, then fizzles out
                         └─(early release ≥50%)─▶ fizzle cast (×0.5)
```

**Chanting**
- Start: `1`–`4` (chant mode) or `Space` on the selected slot (classic mode).
  Left Click on the selected slot also starts a chant in chant mode.
- You are rooted. Mouse aim still turns you. Mana regen is halved (as today).
- Type the incantation letters. A wrong letter is a typo and resets typed text
  (best progress is remembered, as today). `Backspace` deletes one letter;
  `Esc` cancels. While chanting, every letter key goes to the chant (WASD, Q, C,
  F included), exactly as today.
- Charge time: letters ÷ 8 seconds × wand `cast_time_mult` (chant mode, as
  today). Classic mode Space-chant keeps the 1.6 s minimum.
- **Auto-prime:** once the full incantation is typed *and* the charge time has
  passed, the spell primes on its own. There is no confirm key. If the typing
  finishes first, it primes the moment the charge completes.
- A hit of 5+ damage, a stagger (Earth) or a jolt (Storm) breaks the chant, as
  today. Nothing has been paid yet.

**Primed**
- Mana is paid at the moment of priming. If mana is short then, the chant
  collapses with "Not enough mana."
- You move at full speed and aim freely. Mana regen is paused.
- The wand glows in the element colour and a rune ring floats over your head, so
  the rival can see a loaded spell and react.
- HUD: "PRIMED · Ember Dart ×2.4" with a 6 s draining bar.
- Hits do not remove the primed spell. Stagger/jolt only stop movement.
- After 6 s it fizzles out with a puff. Mana is lost.
- While primed you cannot start another chant ("Release your primed spell
  first"). Page swap is allowed. `Esc` discards it.

**Release**
- `Left Click` or `Space` (keyboard), `RT` (controller). `Enter` stays as a
  silent alias so old habits still work, but nothing requires it.
- Fires at the current aim with **soft-lock**: for projectile and beam forms, if
  the rival is within 10° of the aim line and within the spell's range, the aim
  snaps to the rival. Walls, novas and aegis ignore soft-lock.
- Damage multiplier: ×2.4 typed (unchanged).

**Early release (fizzle)**
- `Left Click` / `Space` while still chanting: if ≥50% of the letters are typed
  and the charge time has passed, a fizzle fires immediately at aim (×0.5 power,
  half durations, full mana, as today).
- Under 50%: nothing happens and the HUD says "Keep chanting". (It does **not**
  collapse; only `Esc` cancels.) This prevents a double click from wasting a chant.

**Assisted hold** (`F` / Right Mouse / `LT`): unchanged. Hold to charge (rooted),
release in the gold window for Perfect, fires on release at current aim (it does
not prime). ×1.9 / Perfect +15%.

**Classic mode**: `1`–`4` quickcast instantly at ×1.0, unchanged. Left Click
quickcasts the selected slot unless a spell is primed, in which case it releases.
Space starts a chant on the selected slot (primes, then release as above).

**Controller (chant mode)**: hold `LB`, pick a slot with the stick, let go; press
`A`, `B`, `X` for words 1–3 (unchanged). The spell primes when the last word
lands and the charge completes. Move with the left stick, aim with the right,
release with `RT` (new binding). `Back` cancels.

**AI rival**: same pipeline. It chants (rooted), primes, then moves and releases
when its aim is within 10° of the player, after a 0.3–0.8 s reaction, and always
before the 6 s limit.

**Online**: host-authoritative as today. New command `release` (carries aim);
`unleash` from Enter maps to it. The wizard snapshot carries primed slot
(−1 for none) and primed time remaining so the client HUD, glow and rune ring
render on both screens. The early-unleash queue (`_queue_early_unleash`) becomes
the auto-prime path.

---

## 3. Constructive spellcraft

### Principle

- **Form = shape and delivery only.** Bolt (fast small projectile), Orb (slow
  large projectile), Beam (line), Nova (burst around caster), Ward (placed
  barrier segment), Aegis (attached to caster).
- **Element = material.** It decides whether the shape is solid, what it does to
  things that touch or cross it, what it leaves behind, and how it reacts to
  other materials.

### Materials

| Element | Material | Solid? | Core rider | Signature |
|---|---|---|---|---|
| Fire | flame | never | **Burn** 6 dmg / 3 s | leaves burning ground, ignites things passing through, melts ice |
| Frost | ice | brittle (HP) | **Chill** 40% slow / 2 s; a second chill while chilled = **Freeze** (rooted 0.6 s, 3 s immunity after) | slows projectiles, ice ground, shatters into shards |
| Storm | lightning | never | **Jolt** 0.25 s stun, breaks chants | instant, arcs to nearby targets, bounces off walls |
| Earth | stone | solid (HP) | **Stagger** 0.35 s + heavy knockback | physical collision, smashes ice, highest absorb |
| Arcane | force | never | **Mana burn** 12 | phases through solid matter, reflects |
| Void | gravity | never | **Drain** heals caster 25% of damage | pulls instead of pushes, absorbs projectiles |

Freeze roots movement only. It does not break a chant.

### The 6 × 6 matrix (names)

| | Bolt | Orb | Beam | Nova | Ward | Aegis |
|---|---|---|---|---|---|---|
| **Fire** | Ember Dart | Fireball | Flame Jet | Inferno Ring | Flame Sheet | Heat Aura |
| **Frost** | Ice Shard | Frost Globe | Freeze Ray | Rime Burst | Ice Wall | Ice Armor |
| **Storm** | Spark | Ball Lightning | Chain Lance | Thunderclap | Tesla Fence | Static Shell |
| **Earth** | Stone Bolt | Boulder | Fault Line | Quake | Stone Wall | Stoneskin |
| **Arcane** | Arcane Missile | Mana Sphere | Arcane Ray | Repulse | Mirror Ward | Mana Shield |
| **Void** | Void Dart | Singularity | Siphon | Implosion | Rift | Void Shroud |

Display name = modifier prefix + cell name ("Heavy Inferno Ring", "Seeking Ember
Dart").

### Cell behaviour

Numbers are base values: before wand, arena element, boons, overcast and
modifiers. Mana is the form's current cost × element `cost_mult` (unchanged).
"dps" means damage per second while inside; zones tick every 0.25 s.

#### Fire (flame: never solid, burns, leaves fire)

| Form | Behaviour | Collision |
|---|---|---|
| **Ember Dart** | 17 m/s, 9 dmg + Burn. Wherever it ends (wizard, wall, or 15 m range) it leaves a **fire patch**, radius 1.2 m, 2.5 s, 4 dps + Burn to enemies. | Stopped by solid walls (patch spawns there). Passes Flame Sheet. |
| **Fireball** | 8 m/s homing, 12 dmg direct. On impact explodes: radius 2.2 m, 8 splash to anyone else in range (the direct target takes only the direct hit), leaves a fire patch r 2 m, 3 s. | Explodes on solid walls. |
| **Flame Jet** | Short (8 m) but wide: hits anything within 0.9 m of the line. 14 dmg + Burn. | Passes non-solid walls. Stopped by Stone Wall. Hits an Ice Wall for ×2 and stops. |
| **Inferno Ring** | Radius 4.8 m, 13 dmg + Burn, low knockback (3). Leaves a **burning band** (r 4.0–4.8 m) for 3 s, 5 dps + Burn to anyone crossing it: a ring of fire that traps or fences. | — |
| **Flame Sheet** | 2.4 m wide, 5 s. **Blocks nothing**: players, projectiles and beams pass. Enemies inside take 10 dps + heavy Burn (12 / 3 s). Any non-fire projectile crossing it gains Burn on hit (ignition, both teams). Frost projectiles crossing it melt (destroyed). | No collision. Caster immune. |
| **Heat Aura** | No absorb. 4 s, radius 2.2 m around the caster: enemies take 6 dps + Burn. Frost projectiles entering it melt. Caster is immune to Chill/Freeze while active. | — |

#### Frost (ice: brittle solid, slows, shatters)

| Form | Behaviour | Collision |
|---|---|---|
| **Ice Shard** | 17 m/s, 9.5 dmg + Chill. If it hits a wall it shatters into 3 fragments (40° cone back out of the impact, 4 dmg + Chill each, 6 m). | Normal projectile. |
| **Frost Globe** | 7 m/s homing, 12 dmg + Chill. Leaves an **ice trail** (1.2 m wide, 3 s) that Chills enemies walking on it. Direct hit on a chilled target Freezes. | Normal projectile. |
| **Freeze Ray** | 15 m, 15 dmg, deep Chill (60% / 2.5 s). Coats the ground along the ray in ice for 3 s (1 m wide chill strip). | Stopped by solid walls. |
| **Rime Burst** | Radius 4.8 m, 13 dmg + Chill, knockback 2. Freezes the floor inside the radius for 3 s (chill zone). Targets already chilled Freeze. | — |
| **Ice Wall** | **Solid to players.** 30 HP, 7 s. **Projectiles pass through** but are slowed 50%, lose 25% damage, and deal their damage to the wall. Beams are stopped and damage it. Wizards within 0.4 m are Chilled. Fire damage ×2 against it. When broken: **shatters**, 8 dmg + Chill in r 2.5 m. | Blocks wizards; projectiles pass slowed. |
| **Ice Armor** | Absorbs 30 for 4 s. Immune to Chill/slow while up. Fire damage ×2 against it. If broken by damage it shatters: 8 dmg + Chill in r 2.5 m. | — |

#### Storm (lightning: instant, arcs, jolts)

| Form | Behaviour | Collision |
|---|---|---|
| **Spark** | Fastest bolt, 26 m/s, 9 dmg + Jolt; chains 50% (existing chain / arc-back rule). | Normal projectile. |
| **Ball Lightning** | 6 m/s, no homing, lives 4 s. Every 0.5 s it zaps the nearest enemy within 3.5 m for 4 dmg (no line of sight needed). On contact pops for 10 dmg + Jolt. | Stopped by solid walls. |
| **Chain Lance** | 15 m, 15 dmg + Jolt. **Bounces once** off a solid wall (reflect about the wall normal, remaining range). | Bounces off solid walls. |
| **Thunderclap** | Small radius 3.5 m, 14 dmg, Jolt 0.5 s (breaks chants), knockback 1. | — |
| **Tesla Fence** | 6 s. **Blocks nothing.** An enemy crossing it takes 8 dmg + Jolt (at most once per second). Every 1 s it zaps the nearest enemy within 3 m for 4 dmg. | No collision. |
| **Static Shell** | Absorbs 20 for 4 s, +15% move speed. When hit by a direct attack it arcs 8 dmg + Jolt back to the attacker (at most every 0.5 s). | — |

#### Earth (stone: solid, heavy, HP)

| Form | Behaviour | Collision |
|---|---|---|
| **Stone Bolt** | 13 m/s, 11.5 dmg, knockback 3, Stagger. ×1.5 damage to walls. | Normal projectile. |
| **Boulder** | 9 m/s, no homing, rolls low along the ground, 15 dmg, knockback 6. **Smashes Ice Walls** (destroys, keeps rolling), ×1.5 to Stone Walls. Rolls through non-solid walls. | Ground-level. |
| **Fault Line** | 15 m ground ray of erupting spikes, 19.5 dmg + Stagger. Ignores non-solid walls; stopped by solid walls (and damages them). | Solid walls only. |
| **Quake** | Radius 4.8 m, 17 dmg, knockback 9, Stagger. Deals 20 to every wall in radius (×2 to ice). | — |
| **Stone Wall** | **Solid to players, projectiles and beams.** 60 HP, 8 s. | Blocks everything except Arcane phasing. |
| **Stoneskin** | Absorbs 45 for 4 s. Immune to knockback, Stagger and Jolt. −25% move speed while up. | — |

#### Arcane (force: weightless, phases, reflects, burns mana)

| Form | Behaviour | Collision |
|---|---|---|
| **Arcane Missile** | 17 m/s, 9 dmg + Mana burn. **Phases through solid walls** (Stone, Ice). | Phases. |
| **Mana Sphere** | 8 m/s homing, 11 dmg, phases through solid walls. Every 0.5 s drains 4 mana from an enemy within 3 m and gives it to the caster. On hit burns 15 mana. | Phases. |
| **Arcane Ray** | 15 m, 17 dmg + Mana burn. Passes through walls, losing 30% damage per wall crossed. | Passes walls. |
| **Repulse** | Radius 4.8 m, 8 dmg, knockback 9. **Reflects every enemy projectile** in the radius back toward its caster (ownership flips). | — |
| **Mirror Ward** | 5 s. **Players pass.** Enemy projectiles and beams that hit it are **reflected** (mirrored about the wall normal, ownership flips). Own projectiles pass. Breaks after 4 reflections. | No player collision. |
| **Mana Shield** | 4 s. Incoming damage is paid from mana instead of health, 1 mana per 1 damage, until mana runs out. Mana regen paused while up. | — |

#### Void (gravity: pulls, absorbs, drains)

| Form | Behaviour | Collision |
|---|---|---|
| **Void Dart** | 17 m/s, 9 dmg + Drain. **Pulls** the target 1.5 m toward the caster instead of pushing. | Normal projectile. |
| **Singularity** | 5 m/s, no homing, lives 4 s. Pulls enemies within 3.5 m toward it at 3 m/s. **Absorbs enemy projectiles** it touches (+3 to its payload each). Collapses on contact or at end of life: 12 dmg (+3 per absorbed) in r 1.5 m, Drain. | Stopped by solid walls (collapses). |
| **Siphon** | 12 m ray, 16 dmg, Drain **50%**, pulls the target 2 m toward the caster. | Stopped by solid walls. |
| **Implosion** | Radius 4.8 m, 13 dmg + Drain, pulls everything 2.5 m **inward** toward the caster. | — |
| **Rift** | 5 s. **Players pass** (enemies inside are slowed 25%). **Consumes enemy projectiles** that enter; the caster heals 25% of each one's damage. Stops enemy beams. Own projectiles pass. | No player collision. |
| **Void Shroud** | 4 s. Swallows the **next 2 projectile hits** completely, whatever their damage, healing 25% of each. Beams and novas still hit. | — |

### Cross-material rules

When a projectile meets a ward, check in this order:

1. **Rift** (enemy projectile) → consumed.
2. **Mirror Ward** (enemy projectile) → reflected.
3. **Arcane** projectile and a **solid** wall (Stone, Ice) → phases through.
4. **Boulder** and **Ice Wall** → wall destroyed, boulder continues.
5. **Frost** projectile and **Flame Sheet** → melts (destroyed).
6. **Stone Wall** → projectile stops, wall takes damage.
7. **Ice Wall** → projectile passes, slowed 50%, −25% damage, wall takes damage.
8. **Flame Sheet** → passes, gains Burn.
9. **Tesla Fence** → passes.
10. **Pierce** modifier: may pass one wall it would otherwise stop at (consumes the pierce).

Solid = Stone Wall and Ice Wall (only these block wizards). Walls are hit by
both teams' projectiles; only Mirror and Rift care about ownership. Own walls
still block their owner's movement if solid.

Wall damage multipliers: Fire ×2 vs ice; Earth ×1.5 vs any HP wall; Quake 20
flat to every wall (×2 to ice). Projectiles and beams damage HP walls by their
own damage value.

### Overcast, fizzle and modifiers on the new behaviours

Let *m* be the cast multiplier (typed 2.4, assisted 1.9, perfect ×1.15 on top,
fizzle 0.5).

- Direct damage × *m* (unchanged).
- Zone / aura / fence dps × (1 + (*m* − 1) × 0.5). Durations unchanged.
- Wall HP and shield absorb × (1 + (*m* − 1) × 0.6) (shield rule exists today).
- Mirror Ward reflections +2 when *m* ≥ 1.9.
- Void Shroud swallows 3 hits when *m* ≥ 1.9.
- Fizzle: damage, dps, HP and durations × 0.5.
- Status durations (Burn, Chill, Jolt, Stagger, Freeze) never scale.

Modifiers keep today's numbers and apply where they make sense:
- **Split**: projectile forms only (unchanged).
- **Heavy**: also +45% wall HP, shield absorb and zone dps.
- **Quick**: unchanged (speed, cost, damage).
- **Pierce**: passes one target *or* one wall (rule 10).
- **Track**: adds homing, including to Boulder, Ball Lightning and Singularity.

### Updated starter book and boons

- Page A: Ember Dart, Ice Shard, Stone Wall, Arcane Ray.
- Page B: Ball Lightning, Inferno Ring, Ice Armor, Hasty Void Dart.
- Boon cards: "Ember Nova" → **Heavy Inferno Ring**; "Glacial Aegis" → **Ice
  Armor**; "Void Lance" → **Piercing Siphon**; "Seeker Bolt" → **Seeking Ember
  Dart**. Rewrite their descriptions to describe the material behaviour.

---

## 4. Wands

Emberwood: `damage_mult` 1.05 → **1.10**, `affinity_bonus` stays 0.15, so fire
spells deal base × (1.10 + 0.15) = **+25%** and other spells +10%.

- Wand blurb: "Aggressive. All spells +10%; fire spells +25%."
- Boon card `wand_ember`: "Switch wand: fire affinity, +25% fire damage".
- Fix any doc or README line that says 30%.

---

## 5. Implementation notes

- **Data first.** `SpellData` gets the new words and a `SPELLS` table keyed
  `"element:form"` holding the cell name and its behaviour parameters.
  `SpellDef.display_name()` and `base_stats()` read from it. Keep all numbers in
  data so `--balance` can sweep them.
- **Zones.** One new entity, `SpellZone` (circle, band, or strip), simulated on
  the host with plain distance checks every 0.25 s rather than physics areas.
  Used for fire patches, burning band, ice trail/strip/floor, auras.
- **Wards.** `SpellWall` gets an element profile: `solid_to_wizards`,
  `solid_to_projectiles`, `hp`, and an `on_projectile_enter` hook implementing
  the cross-material order. Non-solid wards must not sit on the collision layer
  wizards and projectiles collide with; detect crossings by distance to the
  segment.
- **Aegis.** `Wizard` shields become typed: absorb (Ice/Earth/Storm), aura
  (Fire), mana (Arcane), swallow-count (Void), with the side effects above.
- **Statuses.** Add Freeze (with immunity window), Jolt, pull (negative
  knockback) and immunity flags (Stoneskin, Heat Aura, Ice Armor).
- **Online.** `MatchState.entity` gains kinds `zone` plus wall element and HP;
  wizard snapshot gains shield type and primed state. Client-side these stay
  presentation only; the host resolves everything. Keep payloads compact
  (fixed-point, short keys): GD-Sync's free tier is capped per day.
- **AI.** It should at least: prefer Stone Wall / Ice Wall when the player is
  primed, avoid standing in fire/ice zones, and not shoot into a Mirror Ward or
  Rift.
- **Tests.** Every cell gets a headless check of its defining behaviour (e.g.
  Flame Sheet lets a wizard and a bolt through and burns; Stone Wall blocks
  both; Ice Wall blocks the wizard and slows the bolt; Mirror reflects ownership).
