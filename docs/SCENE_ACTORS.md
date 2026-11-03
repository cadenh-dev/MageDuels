# Scene-authored actors (test fork)

Local branch: `test/scene-actors` in
`C:\Users\minisforum-zach\.local\share\opencode\worktree\316789\scene-actors`.

This fork replaces the code-built 3D actors with `.tscn` scenes. The arena stage
and HUD/menus are unchanged; the scope is the actors and their effects.

## Scene map

| Scene | Root | Script |
|---|---|---|
| `scenes/actors/Wizard.tscn` | `CharacterBody3D` | `wizard.gd` |
| `scenes/actors/SpellProjectile.tscn` | `Area3D` | `spell_projectile.gd` |
| `scenes/actors/SpellWall.tscn` | `StaticBody3D` | `spell_wall.gd` |
| `scenes/fx/FxBeam.tscn` | `MeshInstance3D` | none |
| `scenes/fx/FxShockwave.tscn` | `MeshInstance3D` | none |
| `scenes/fx/FxBurst.tscn` | `CPUParticles3D` | none |
| `scenes/fx/FxDamageNumber.tscn` | `Label3D` | none |

`scripts/core/actors.gd` owns the lazy scene cache. Lazy loading avoids a
preload cycle between the actor scripts and `Fx`.

## Script changes

- **Wizard** — removed `_build_model`, `_build_bars`, `_build_shield`, and the
  code-created collision shape. `setup()` caches scene nodes and applies the
  wand-colored materials. The node hierarchy and transforms are in the scene.
- **SpellProjectile** — removed `_build_visual`; `setup()` caches `Core`,
  `Halo`, and `Trail`, scales the core/halo by `radius / 0.32`, and assigns the
  cached color materials.
- **SpellWall** — removed code-created mesh, trim, and collision shape; `setup()`
  applies the wall material and trim colors to the scene nodes.
- **Fx** — beam, shockwave, burst, and damage-number nodes are instantiated from
  their scenes. Only transforms, colors, particle counts, and lifetimes are set
  in code.
- **Main / tests / warmup** — construct Wizards from `ActorScenes.wizard()`.

## Verification

```text
TEST 27/27        FLOW 17/17        LIFETIME 33/33
AI 8/8            INPUT 16/16       BALANCE 7380/7380
AUDIO PASS
```

Rendered profile:

```text
PROFILE build_ms=24.4
PROFILE worst_frame=18.9ms
```

Cast timing:

```text
Arena spellbook: 8/8, worst cast 2.46ms, worst post-cast 17.52ms
All 36:          36/36, worst cast 4.80ms, worst post-cast 30.50ms
```

The actor renders the same in the scene fork as in the code-built master.

Web export succeeds at **38.94 MB**.

## Run

```powershell
$godot = "C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path . -- --test
& $godot --path . -- --cast-timing
& $godot --path . -- --cast-timing-all
& $godot --path . -- --shot-duel
```
