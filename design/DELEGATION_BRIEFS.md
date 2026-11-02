# SHIFTCAST — Ready-to-launch delegation briefs

These are self-contained. Do not launch until `master` has a commit; worktree isolation
forks from a commit and does not copy uncommitted edits.

**Toolchain handoff (from the generated project router):**

```
Toolchain: gdscript / Godot 4.7.2, GL Compatibility renderer
Manifest:  project.godot
Runtime:   NOT ON PATH — use the absolute binary
Command:   C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --test
Screens:   same binary without --headless, -- --shot-duel
Rules:     do not add an engine, language, package manager, or build system
```

---

## U4 — Rival AI: wind-up, archetypes, optional Echo

ROLE: implementation
TARGET: `codex:gpt-6-astra#reasoningEffort=xhigh`
ISOLATION: worktree
WRITE SCOPE: `scripts/ai/ai_wizard.gd`, `scripts/core/spell_data.gd`
DO NOT TOUCH: `scripts/main.gd`, `scripts/ui/**`, `scripts/world/**`

OBJECTIVE
Replace the rival's instant chant and random-slot casting with a readable, interruptible
opponent whose personality follows its wand.

CONTEXT
- `ai_wizard.gd` currently "chants" by setting `chant_text` and calling `chant_finish()`
  on a timer. That invalidates the rooted-chant bargain; the player never gets to punish it.
- `Wizard` already exposes everything needed: `set_ai_move`, `set_aim_world`, `quickcast`,
  `begin_chant`, `chant_key`, `chant_finish`, `cancel_chant`, `swap_page`, `page_spells`.
- `main.gd` assigns `Game.enemy_wand` via `_pick_enemy_wand()` before building the duel.

REQUIRED BEHAVIOUR
1. **Telegraph.** Before any quickcast or chant, the AI enters a wind-up state with a
   visible tell (staff light spike / ground-ring pulse via existing `Fx` helpers) lasting
   0.35–0.6s. During wind-up the player can interrupt by landing a direct hit.
2. **Chant honestly.** Chanting must take real time and be interruptible. Feed characters
   through `chant_key()` at a human-ish rate, or expose a `chant_progress` the UI can read.
   Never set `chant_text` directly.
3. **Recovery window.** After a committed cast, 0.4–0.9s where the AI cannot cast and
   moves sluggishly. This is the player's punish window.
4. **Archetypes** derived from `Game.enemy_wand`:
   - `emberwood` → Cinder Vanguard: closes distance, heavy/split bolts at close range.
   - `frostglass` → Everfrost: holds range, frost nova + ward walls to deny approach.
   - `stormbone` → Tempest Trickster: erratic strafing, split volleys, feint chants.
   - `voidheart` → Hollow Duelist: lifedrain trades, retreats when low.
   Cap each archetype at three signature behaviours; everything else uses weighted scoring.
5. **Optional (only if 1–4 pass):** on match point, the rival mirrors the player's own
   `Game.player_wand` and `Game.player_pages` as a "Rival Echo".

ACCEPTANCE
- A player can see a cast coming and interrupt a chant with a direct hit.
- The AI never completes a chant instantly.
- Each archetype is distinguishable in a 30-second observation.
- `--test` still passes; add one check asserting a chant in progress can be interrupted.

DELIVERABLE
Commit on your branch. Report changed files, the exact test output, and any balance risks.
Last line: `PR <full URL>, head <SHA>, checks and reviews <state>` — or, if no PR,
`branch <name>, head <SHA>, tests <state>`.

---

## U5 — Audio: baked SFX, chant arpeggio, one adaptive bed

ROLE: implementation
TARGET: `opencode:opencode/big-pickle`
ISOLATION: worktree
WRITE SCOPE: `scripts/core/audio.gd`, `scripts/audio/**`, `project.godot` (autoload + audio
buses only), `assets/audio/**`
DO NOT TOUCH: `scripts/main.gd`, `scripts/ui/**`, `scripts/world/**`, `scripts/ai/**`

OBJECTIVE
Make SHIFTCAST audible with zero external assets.

CONTEXT
- The repo has **no audio at all**: no files, no buses, no players.
- Godot 4.7.2, GL Compatibility, browser target. Audio must unlock on first user gesture.
- Hooks already exist: `Wizard.cast_fired`, `Wizard.damaged`, `Wizard.died`,
  `Wizard.chant_changed`, `Wizard.chant_key`, `Wizard.swap_page`, `Arena.spawn_spell`,
  `DuelHUD.announce`.

REQUIRED
1. `scripts/audio/synth.gd`: pure static functions returning `AudioStreamWAV` baked at
   startup — 22 050 Hz, mono, `FORMAT_16_BITS`, encoded with `PackedByteArray.encode_s16`.
   **Do not run `AudioStreamGenerator` in the frame loop.**
2. Sounds: cast (per element family), impact, page-shift whoosh, chant key tick (rising
   pentatonic), chant fail, round win, round lose, UI click, death.
3. **Chant arpeggio is the priority.** One pluck per correct character, pitch rising with
   progress, resolving on completion. Duck the music while chanting.
4. One looping music bed (8 bars, loop-forward) with 3 intensity layers driven by
   `Game.round_index`; stems started together to stay phase-locked.
5. Buses: `Music`, `SFX`, `UI`, plus a limiter on Master. Master volume persisted.
6. Polyphony: pool ~12 `AudioStreamPlayer`s; `pitch_scale = randf_range(0.94, 1.06)`.

ACCEPTANCE
- Every element is identifiable with eyes closed.
- Chant ticks rise and resolve; a typo is audibly distinct.
- No runtime synthesis on the main thread after `_ready`.
- `--test` still passes and produces no audio errors in headless mode.

DELIVERABLE
Commit on your branch. Report files, the synthesis recipe per sound, and test output.

---

## U8 — Web export + itch submission kit

ROLE: implementation
TARGET: `opencode:opencode-go/beam-free#variant=high`
ISOLATION: worktree
WRITE SCOPE: `export_presets.cfg`, `.gitignore`, `docs/ITCH.md`, `tools/export_web.ps1`,
`assets/icon.svg` (only if a 630x500 cover must be generated)
DO NOT TOUCH: `scripts/**`, `project.godot`, `scenes/**`

OBJECTIVE
Produce a reproducible browser build and the itch.io submission kit.

CONTEXT
- No `export_presets.cfg` exists. `.gitignore` line 4 currently ignores it — remove that.
- itch.io cannot send COOP/COEP headers, so **thread support must be OFF**; a
  SharedArrayBuffer build fails inside the itch iframe.
- Renderer is GL Compatibility. Export templates for 4.7.2 are installed at
  `%APPDATA%\Godot\export_templates\4.7.2.stable`.

REQUIRED
1. `export_presets.cfg` with a `Web` preset: threads off, VRAM compression on for desktop,
   canvas resize policy, PWA on, custom HTML shell if needed for context-menu suppression
   and pointer focus.
2. `tools/export_web.ps1` using the absolute Godot binary; fails loudly on a missing template.
3. `docs/ITCH.md`: store copy (3-sentence pitch), tags, cover 630x500, GIF 640x360 ≤6 MB,
   three screenshots, controls block, credits (Cinzel + Rajdhani, OFL), and a pre-flight
   checklist (boots <10s, audio unlocks on click, full match, no console errors).
4. Report the exported bundle size and the load time you measured.

ACCEPTANCE
- `godot --headless --export-release "Web" build/index.html` succeeds from a clean checkout.
- `build/` is gitignored; `export_presets.cfg` is committed.
- Opening `build/index.html` over a local static server boots the menu.

DELIVERABLE
Commit on your branch. Report bundle size, measured load time, and browser versions tested.
