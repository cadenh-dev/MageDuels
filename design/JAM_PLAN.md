# SHIFTCAST — Jam Plan (orchestrator synthesis)

> Written after consulting 11 independent advisors (one per available model), then
> routing through the project classifier. This file is a plan, not a spec of what is
> already built. Source memos are summarized; the reasoning that survived is kept.

---

## 1. Verdict

The hard part is already done, and the frame landed while this plan was being written.
Combat math, rune grammar, typed chanting, statuses, procedural arena, AI, menus, wand
select, crafting, results, HUD, pause, reticle, round flow, and a headless combat test
all exist.

**What is actually missing now: audio, a web export, a readable AI, and verification of
the loop end-to-end.** Those four are the jam.

The build should be: **one arena, one named rival, best-of-three, optional typing,
audio, browser export.** Everything else is post-jam.

> **Live status (checked after the main thread's latest pass):**
> `main.gd` now implements `TITLE → WAND → CRAFT → ROUND_INTRO → DUEL → ROUND_END →
> MATCH_END → rematch`, instantiates `DuelHUD`, owns input with unicode chant matching,
> and pauses/resumes. `scripts/debug/combat_test.gd` covers projectile, beam, wall,
> nova, overcast, page swap, and death. Still absent: `export_presets.cfg`, any audio,
> any AI wind-up, `--flow`/`--lifetime` tests. A `CraftScreen` also exists now, which
> overrides the "curated loadouts only" advice — keep it, but add a fast path (see §3).

---

## 2. What the advisors agreed on (and I am adopting)

| Decision | Agreed by | Why |
|---|---|---|
| Close the match loop before any more content | architecture, scope, QA, references | **Done** — `main.gd` now runs round → result → rematch |
| Curated loadouts / between-round draft instead of a crafting screen | creative, scope, UX, references, systems | The 150-spell grid is a jam-killer; `default_pages()` already gives themed pages |
| Typing stays optional; quickcast must be fully viable | creative, UX, systems, references | Typing as a gate loses browser players and gamepad users |
| The AI must chant visibly and be interruptible | creative (#1 pick), systems, QA | Current instant AI chant invalidates the core risk/reward bargain |
| Ship a first-run coach, not a tutorial level | UX, scope, QA | 90-second judge patience |
| Validate the web export early, threads **off** for itch | browser, QA, scope | itch.io cannot send COOP/COEP; `SharedArrayBuffer` builds fail |
| Audio is missing and is the cheapest perceived-polish win | audio, scope, references | Silence reads as "unfinished" |
| Cut online multiplayer from the required slice | scope, QA, references, creative | Costs days, judged by nobody if the loop is weak |

### Where they disagreed, and my ruling

| Disagreement | Positions | Ruling |
|---|---|---|
| **Arena element cadence** | Creative: shift every ~12s mid-round with telegraph. Architecture/references/scope: shift per round. | **Per round** for launch. It is already implemented (`Game.next_round()`), it is readable, and it supports loadout planning. Mid-round shifting is a stretch goal behind a flag. |
| **Overcast economy** | Current: ×1.6 damage, ×0.7 mana. Systems: ×2.2 damage, ×1.2 mana + windup. | **Middle:** ×1.8 damage, ×1.0 mana, minimum 0.9s windup, interrupted by direct damage. Chanting must be a *risk*, not a discount. |
| **Rune count** | Systems: cut to 19 recipes, remove orb/beam/split/pierce from launch. | **Keep the code, gate the UI.** Removing working content saves no time. Expose 8 curated spells per wand; leave the full grammar as a post-jam toy. |
| **Wand / arena bonuses** | Systems: zero mechanical affinity, remove arena +15%. References: keep both. | **Reduce, don't remove.** Wand affinity `0.30–0.40 → 0.15`, and make wand + arena bonuses **additive** instead of multiplicative. Two one-line changes, still legible. |
| **Shift semantics** | Creative/references: Shift should read as a *stance*, not a page. | **Do both cheaply.** Shift flips page **and** the HUD stance label (`MOBILE`/`ROOTED`), the ground ring color, and a sound. Chant entry stays on Space. |
| **Netcode** | Architecture round 1: host-authoritative WebSocket after a 2–3 day refactor. Round 2: P2P WebRTC listen-server, and "ghost duels" are the highest-ROI fake-online. Others: cut it. | **Cut real-time online for jam; keep the seam.** Adopt the controller boundary (see §7, U2), which local 2P, ghosts, and online all need later. Ship **shadow duels / daily seed** as the post-jam social feature — no server, no latency, same snapshot format as real netcode. |

---

## 3. Ranked backlog

Effort is rough agent-hours, not calendar time.

### Already landed (no action; verify only)

Match flow · menus · wand select · craft screen · results · HUD wiring · pause · reticle ·
round intro · death beat · unicode chant routing · combat test (`--test`).

### P0 — ship blockers

| # | Item | Effort | Notes |
|---|---|---:|---|
| 1 | **Web export + browser smoke run** | 2 | No `export_presets.cfg` exists. Threads OFF, GL Compatibility. Prove boot, keys, and a full match in Chrome and Firefox. |
| 2 | **Audio** | 4 | Zero audio in the repo. Baked SFX + chant arpeggio + one looping bed. Highest perceived-polish per hour. |
| 3 | **AI wind-up + interruptible chant** | 3 | `ai_wizard.gd` has no telegraph and still completes chants instantly. Converts "random spitter" into "committed villain". |
| 4 | **Flow verification** | 2 | `--test` covers combat only. Add `--flow` (forced kill → round 2 → match end) and `--lifetime` (10 rebuilds, no orphans). |
| 5 | **Craft-screen fast path** | 1 | A full `CraftScreen` exists. Add `DUEL NOW` that accepts defaults, so judges never have to craft before their first cast. |

### P1 — the difference between "works" and "wins"

| # | Item | Effort | Notes |
|---|---|---:|---|
| 5 | **AI chant windup**: visible, interruptible, named rival | 3 | Creative's #1 and systems' #1 overlap. Highest design payoff. |
| 6 | **Chant as wager**: hold-to-chant fallback, glyph progress, interrupt on direct hit, no free mana discount | 3 | Accessibility + tension at once. |
| 7 | **Shift moment**: page flip + stance label + ring recolor + whoosh + 0.18s slow | 2 | The GIF moment. |
| 8 | **Audio pass**: 8 baked SFX + chant arpeggio + 1 looping bed with 3 intensity layers | 4 | Bake to `AudioStreamWAV` at startup; do **not** run `AudioStreamGenerator` live. |
| 9 | **Impact package**: 25ms hitstop, 50ms white flash, shake, near-miss whoosh | 2 | One function in `arena.gd` covers every spell. |
| 10 | **Round intro card**: "THE ARENA SHIFTS — VOID" + element tint reveal | 1 | Free theme payoff; `Game.next_round()` already rerolls. |
| 11 | **First-run coach**: 4 beats (move, quickcast, Shift, optional chant), dismiss-on-success | 2 | No separate tutorial scene. |
| 12 | **Between-round draft**: 3 random spells, replace one slot | 2 | Cheap build agency; uses `SpellData.random_spell`. |

### P2 — depth and polish, only if the gates pass

| # | Item | Effort | Notes |
|---|---|---:|---|
| 13 | **One status conversion**: Frost → Earth *Shatter* (+8 dmg, consumes chill); Frost → Fire (+4, no burn) | 2 | One mechanic, real depth. Do not build a reaction table. |
| 14 | **Shared cooldowns** across modifier variants of the same element+form | 1 | Stops "eight cooldown batteries" gameplay. |
| 15 | **Result receipt**: casts, typos, page swaps, biggest hit, arena history | 1 | Doubles as a playtest survey. |
| 16 | **Seeded daily duel + share code** | 3 | Uses `RandomNumberGenerator`; no server. |
| 17 | **Local hotseat 2P** | 3 | Only after the controller boundary exists. |
| 18 | **Shadow duels** ("beat my ghost"): record move/cast/swap commands + 5 Hz keyframes, share as a clipboard code | 4 | Zero infrastructure, works on itch, and the snapshot serializer is the same one future netcode needs. The strongest post-jam differentiator. |

### Explicitly cut

Online multiplayer · matchmaking · full crafting editor · meta progression/unlocks ·
extra arenas · multiple game modes · trailer · settings beyond volume/fullscreen.

---

## 4. The vertical slice (definition of done)

> A judge clicks Play, understands the game in 15 seconds, finishes a best-of-three
> against a named rival in under 5 minutes, hears it, and can immediately rematch.

- Title screen over a live or slow-panning arena, one primary action.
- Wand select: 4 cards, one screen, no confirmation dialog.
- Two curated pages of four spells, per wand.
- HUD: HP/mana both sides, 4 slot cards with cooldown arcs + mana cost, page tabs, `SHIFT` hint, chant panel with typed progress, arena element badge, round + score.
- Round intro ("ROUND 2 — THE ARENA SHIFTS"), death beat, match result, rematch.
- Pause: resume, volume, fullscreen, quit.
- Audio: cast, impact, page shift, chant tick, round win/lose, one music bed.
- Web build loads < 10s, holds 55+ fps at 720p with ≤4 projectiles, and runs a full match without a console error.

---

## 5. Match flow contract

```
BOOT
 └─ TITLE ──(play)──> WAND ──(confirm)──> ROUND_INTRO
                                   ↑            │
                                   │        (3..1)
                                   │            ↓
                              ROUND_END <──── DUEL ──(esc)──> PAUSE ──> DUEL
                                   │
                     (match not over) └──> DRAFT ──> ROUND_INTRO
                                   │
                            (match over) └──> MATCH_END ──(rematch)──> ROUND_INTRO
                                                        └─(menu)──> TITLE
```

Rules that prevent the classic soft-lock:

- `_end_round()` may only fire once per round; guard with a `_resolving` flag.
- Death animation gets 1.2s before the result transition; the result screen waits for it.
- `_clear_world()` must `await get_tree().process_frame` after `queue_free()` before rebuilding (see §7 QA note).
- A watchdog force-resolves a round after 20s with no damage and no cast.
- Rematch calls `Game.reset_match()` + `start_round()`, never reuses wizard nodes.

---

## 6. Input contract (fixes the three collisions)

| Context | Input | Action |
|---|---|---|
| DUEL | `1-4` | quickcast slot |
| DUEL | `Shift` | swap page + stance FX (never cancels a chant) |
| DUEL | `Space` | begin chant on selected slot |
| DUEL | `LMB` | begin chant on hovered/selected slot (alias) |
| CHANT | `a-z` via `event.unicode` | feed `chant_key` |
| CHANT | `Backspace` | `chant_backspace` |
| CHANT | `Enter` | `chant_finish` |
| CHANT | `Esc` | cancel chant (does **not** open pause) |
| DUEL | `Esc` | pause |
| anywhere | `Ctrl/Meta` chords | ignored (never eat browser shortcuts) |

Changes required:

- Remove `KEY_SPACE` from the `confirm` action (`game.gd:88`).
- Match chant characters on `event.unicode.to_lower()`, not `physical_keycode` (AZERTY/Dvorak).
- Ignore IME composition events.
- One `scripts/core/input_router.gd`; no other node reads raw input during a duel.
- Show "click to focus" if the canvas loses focus (browser).

---

## 7. Work breakdown and delegation

### Toolchain handoff (from the generated router)

```
Toolchain: gdscript / Godot 4.7.2 (GL Compatibility)
Manifest:  project.godot
Runtime:   NOT ON PATH — use absolute binary
Command:   C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --smoke
Screens:   same binary, no --headless, -- --shot
Rules:     do not introduce a new engine, language, or build system
```

### ⚠ Blocker for parallel writes

`git log` shows **zero commits** on `master` (46 changed entries, no `HEAD`). T3's
`isolation: "worktree"` forks from the parent commit and **does not copy uncommitted
edits**, so a worktree child would start with none of this game.

**Order of operations:** the main thread must make an initial commit before any
parallel implementation delegate is launched. Until then, writes must be sequential in
the shared checkout.

Also: `.gitignore` currently ignores `export_presets.cfg`. Un-ignore it — the web export
preset is part of the submission and must be reproducible.

### Units

| Unit | Scope | Depends on | Target (route) | Verify |
|---|---|---|---|---|
| U1 flow | `scripts/main.gd` | — | `codex:gpt-6.1-sol#reasoningEffort=high` | `--smoke --flow` completes a match |
| U2 input | `scripts/core/input_router.gd`, `game.gd` | — | `codex:gpt-6-astra#reasoningEffort=xhigh` | `--smoke --input` |
| U3 hud | `scripts/ui/hud.gd`, `main.gd` (one line) | U1, U2 | `opencode:opencode-go/claude-haiku-5-5#variant=high` | visual + `--shot` |
| U4 rival | `scripts/ai/ai_wizard.gd`, `spell_data.gd` | U1 | `codex:gpt-6-astra#reasoningEffort=xhigh` | wind-up states + punish windows; archetype derived from `Game.enemy_wand` (Cinder Vanguard / Everfrost / Tempest Trickster); optional Rival Echo on match point (mirror `Game.player_wand` + `player_pages`) |
| U5 audio | `scripts/core/audio.gd`, `scripts/audio/synth.gd`, `project.godot` | — | `opencode:opencode/big-pickle` | every element audible; no runtime synth |
| U6 juice | `arena.gd`, `fx.gd`, `spell_projectile.gd` | U1 | `codex:gpt-6.1-terra#reasoningEffort=max` | 3-round soak, no tween leaks |
| U7 balance | `spell_data.gd`, `spell_def.gd` | U4 | `codex:gpt-6-astra#reasoningEffort=high` | `--smoke --balance` no NaN |
| U8 export | `export_presets.cfg`, `.gitignore`, `docs/ITCH.md` | — | `opencode:opencode-go/beam-free#variant=high` | Chrome + Firefox, threads off |
| U9 coach | `scripts/ui/coach.gd`, `hud.gd` | U1, U3 | `codex:gpt-6-luna#reasoningEffort=xhigh` | new player casts + shifts < 40s |

### Sequencing

```
U1 ─┬─> U3 ──> U9
U2 ─┘
U1 ──> U4 ──> U7
U5  (parallel, no deps)
U6  (parallel after U1 lands)
U8  (parallel, day 1)
```

**U1 (flow), U2 (input), and U3 (HUD) are already implemented in the live checkout.**
Start the delegation plan at U4, U5, and U8.

No two units may write the same file. `main.gd` is touched by U1, U3, and U9 — sequence
them, or have U3/U9 hand back a patch instead of editing.

**Rival note:** `main.gd` now has `_pick_enemy_wand()` (line 124), and
`scripts/debug/combat_test.gd` now exists, so the AI memo's two integration points are
real rather than proposed. Use them.

### Verification harness (from the QA memo)

Add to the existing `--smoke` pattern in `main.gd:23`:

| Flag | Asserts |
|---|---|
| `--smoke` | existing: cast lands, enemy HP drops |
| `--flow` | forced kill → score 1 → next round → match end |
| `--input` | synthetic keys: mana spent, rooted while chanting |
| `--lifetime` | 10 duel cycles leave no orphans, `world` has 1 child |
| `--balance` | all wand × element × form × modifier stats are finite and > 0 |

All must `quit(1)` on failure so `--headless` is meaningful.

---

## 8. Known defects to fix on the way

| Defect | Where | Fix |
|---|---|---|
| `Fx.burst(arena.effects, ...)` dereferences `arena` before the null check | `spell_projectile.gd:174` and `:184` | guard `arena` first |
| Debug print left in shipping path | `spell_projectile.gd:166` | remove or gate behind `OS.is_debug_build()` |
| `Space` is both chant and confirm | `game.gd:86` | remove from `confirm` (low risk: no focused buttons) |
| Chant matching uses `physical_keycode` | `game.gd:98` | match `event.unicode` |
| Per-projectile `OmniLight3D` + new material | `spell_projectile.gd:72,89` | cache per element; drop light on web |
| Uncapped particle emitters | `fx.gd:26` | global FX budget (~600 live particles) |
| AI chants instantly | `ai_wizard.gd:52` | visible windup, interruptible |
| `.gitignore` excludes export presets | `.gitignore:4` | remove that line |

---

## 9. Gates

| Gate | Check | If it fails |
|---|---|---|
| **G0 (day 1)** | Web export boots and casts in Chrome | Cut effects/audio, export desktop-only, say so on the page |
| **G1** | Title → best-of-three → result → rematch, no soft-lock | Stop all cosmetics until it passes |
| **G2** | HUD, chant, pause, draft; 3 outsider playtests | Cut the draft, then the coach |
| **G3** | Audio + juice + balance; feature freeze | Ship what passes G2 |
| **G4** | itch page, 3 screenshots + 1 GIF, cross-browser check | Upload with 4h buffer |

**Feature freeze after G3.** New ideas go to `design/POST_JAM.md`, not into the build.

---

## 10. Open decisions for the user

1. **Delegation mode** — sequence the nine units through the main thread, or commit first and run 3–4 worktree children in parallel? (Parallel is faster but needs the initial commit.)
2. **Rival identity** — one named archmage, or three rivals (Frost controller / Fire rusher / Storm trickster) with one round each? Three is better value for a best-of-three, at ~2 extra hours.
3. **Typing fallback** — hold-to-chant at reduced speed, or make chanting a pure skill check? Hold-to-chant is the safer jam choice.
4. **ip/theme** — keep the name **SHIFTCAST** and subtitle *The Arena Turns a Page*, or drop the subtitle to reduce text on the title screen.
