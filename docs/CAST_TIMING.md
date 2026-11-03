# Cast timing harness

`--cast-timing` measures every slot in the live Arena spellbook. `--cast-timing-all`
measures all 36 element x form combinations. Both use the real `quickcast` path,
the real arena, and the real HUD, but aim away from the rival so impact hitstop
does not contaminate the cast timings.

```powershell
# Rendered frame timings
& $godot --path . -- --cast-timing
& $godot --path . -- --cast-timing-all

# CPU/tick timings without a window
& $godot --headless --path . -- --cast-timing
```

Each row reports:

| Column | Meaning |
|---|---|
| `pre` | the last full process frame before the cast |
| `cast` | wall time inside `quickcast()` (input validation, stats, audio, spawn) |
| `f1` | time from the end of the cast to the next process frame |
| `f2` | time from that process frame to the next |
| `t1` | time from the end of the cast to the next physics tick |
| `t2` | time from that physics tick to the next |

## Arena spellbook

Windowed run, 1280x720, GL Compatibility. Values in milliseconds.

| Page | Slot | Spell | pre | cast | f1 | f2 | t1 | t2 |
|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 0 | 0 | Ember Bolt | 17.43 | 1.71 | 15.22 | 17.00 | 14.81 | 16.96 |
| 0 | 1 | Frost Bolt | 15.32 | 1.39 | 15.53 | 17.08 | 15.15 | 17.05 |
| 0 | 2 | Stone Ward | 17.55 | 1.76 | 14.76 | 16.87 | 14.27 | 16.74 |
| 0 | 3 | Arcane Beam | 16.96 | 2.22 | 14.57 | 16.38 | 14.22 | 16.43 |
| 1 | 0 | Storm Orb | 15.52 | 1.19 | 15.84 | 16.84 | 15.39 | 16.90 |
| 1 | 1 | Ember Nova | 16.22 | 2.21 | 15.21 | 15.87 | 14.84 | 15.92 |
| 1 | 2 | Frost Aegis | 16.41 | 2.29 | 14.51 | 16.70 | 14.09 | 16.67 |
| 1 | 3 | Hasty Void Bolt | 18.01 | 1.17 | 15.33 | 17.21 | 14.95 | 16.97 |

Worst cast setup: **2.29 ms** (Frost Aegis). Worst post-cast frame/tick:
**17.21 ms** (Hasty Void Bolt).

## All 36 element x form spells

Windowed run. Per-form maxima across all six elements:

| Form | Worst cast | Worst post-cast |
|---|---:|---:|
| bolt | 2.84 ms | 20.16 ms |
| orb | 2.79 ms | 18.31 ms |
| beam | 4.90 ms | 17.39 ms |
| nova | 3.93 ms | 18.09 ms |
| wall | 3.84 ms | 17.44 ms |
| aegis | 4.24 ms | 17.06 ms |

Worst overall: **4.90 ms** cast setup (arcane beam), **20.16 ms** post-cast
frame (arcane bolt). That is one 60 Hz frame, not a multi-frame stall.

## Notes

- The boot warmup still runs first; these numbers are the first real use of each
  spell in the round, after the loader has compiled the shared render state.
- The harness clears projectiles, walls, effects, shields, and status timers
  between casts, and resets mana/cooldowns so every cast actually fires.
- The `--cast-timing-all` pass runs in its own process because running the Arena
  pages first would warm some of the matrix combos.
