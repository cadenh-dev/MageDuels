# SHIFTCAST — Mode Roadmap (V2)

> The duel loop is shipping. This doc scopes the requested expansions so we build
> them in an order that protects the jam submission.

## Current baseline

Title → wand select → craft → best-of-three duel → results → rematch.
Four wands, two pages of four spells, quickcast + typed overcast + assisted
overcast + perfect release, AI archetypes, audio, controller support, web export.

## Just added

- **Camera modes.** `C` / right-stick click toggles `ARENA` (fixed duel camera)
  and `FOLLOW` (centered on the player). Arena duels default to fixed.
- **Aegis** (`TUTELA`) — a personal shield form. Absorbs 35 damage for 3s,
  overcast raises it to 52.5. The existing **Ward** (`MURUS`) still blocks
  projectiles and beams.

## Requested modes

### A. Arena 2.0 — Rounds-like (jam-sized rework)

- Both duelists start with the same **Apprentice Wand** (balanced, no affinity).
- **First to 3** (best of 5) instead of first to 2.
- After every round, a **card draft**:
  - Loser picks first, then the winner, from a shared 3-card offer.
  - Cards are rune unlocks, wand upgrades, or passive boons (+HP, +mana,
    +damage, +cast speed, shield, extra projectile).
- The full craft screen moves out of the arena path (or becomes the pre-match
  loadout) so the draft is the progression.
- Touches: `Game`, `main.gd`, new `DraftScreen`, HUD card strip, `spell_data`.
- Effort: 2–3 focused days. **Recommended jam scope.**

### B. Spell Sprint — casting-speed mode (self-contained)

- 60-second typing gauntlet. Random incantations appear; type them for score,
  combo, and accuracy.
- Shows WPM / perfect-cast rate; local best saved.
- Uses the same rune words and cinematic backdrop. No AI, no arena.
- Touches: new `SpellSprintScreen`, `Game` best score.
- Effort: ~1 day. Low risk, good second mode.

### C. Battle Royale — PVE + PVP (post-jam flagship)

- Large map (floating islands), 6–8 wizards, shrinking ring, last standing.
- **Chests** contain wands, rune pages, potions, shields, and gold.
- **PVE:** wandering constructs/guardians guarding loot; neutral until aggroed.
- **PVP:** AI wizards loot and fight each other; player can third-party.
- **Camera:** follow mode (already built) with a wide overview toggle.
- **Online:** later. Start with AI opponents + local hotseat/ghost replays.
- Reuses: `Wizard`, `Arena` spell resolution, `SpellData`, VFX, audio.
- New: map generator, loot tables, interactables, ring, multi-wizard AI,
  inventory/HUD, spectate, match manager.
- Milestones:
  - BR-1: one map, player + 3 AI, chests, ring, win screen.
  - BR-2: PVE guardians, consumables, wand swaps.
  - BR-3: online rooms (WebSocket server or WebRTC + signaling).
- Effort: 2–3 weeks for BR-1/2; online is separate.

### D. Counterspell — the "reiterate + cancel" defense

- When the rival commits a spell, the player can type the **same incantation +
  `FRANGO`** in a reaction window to nullify the projectile/beam and break the
  rival's chant.
- Needs a counter input mode, a prompt with the rival's incantation, and a
  success/fail window. High skill, high spectacle.
- Effort: 2–3 days. Aegis + Ward cover defense until then.

### E. Casting-speed variants (optional)

- **Duel tempo:** a modifier that halves all cooldowns and chant windows.
- **Sudden death:** first clean hit wins; no regen.
- **Spell Sprint** is the clean standalone version of this idea.

## Recommended order

1. **Arena 2.0** (normal wand + draft + first to 3) — directly addresses the
   Rounds direction and keeps the existing duel as the foundation.
2. **Spell Sprint** — one-day second mode; gives the jam page variety.
3. **Aegis/defense polish + counterspell** — if the draft lands early.
4. **Battle Royale BR-1** — after the jam, as the next major milestone.

Do not replace the working duel with a half-built BR before submission. A
polished 5-minute duel plus a 60-second typing mode is a stronger jam entry than
a broken 8-player mode.

## Open decisions

- Keep the craft screen in Arena 2.0, or replace it with the draft and move
  crafting to BR/sandbox?
- Best-of-5 with loser-first draft, or best-of-3 with one draft?
- BR roster: 4 AI wizards first, or 8?
- Online: dedicated Godot WebSocket server (reliable, needs hosting) or WebRTC
  P2P (cheap, needs signaling and NAT handling)?
