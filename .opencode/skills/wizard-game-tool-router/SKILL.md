---
name: wizard-game-november-game-jam-tool-router
description: Route tasks in wizard-game-november-game-jam to its detected languages, frameworks, tools, and commands. Generated from repository evidence; use when choosing between competing languages, engines, build systems, test runners, or package managers.
---

# wizard-game-november-game-jam Tool Router

Generated from repository evidence on 2026-11-02T03:18:41+00:00.
This is a **project-local** router. It describes what this repository uses; it does not
prove a tool is installed. Check the runtime column before relying on a command.

## What this project uses

| Language | Files | Manifests | Frameworks | Confidence | Runtime |
| --- | ---: | --- | --- | --- | --- |
| gdscript | 29 | project.godot | — | high | NOT ON PATH |
| python | 3 | — | — | medium | available |

## Route tasks

| If the task is about... | Use | Evidence |
| --- | --- | --- |
| Files under the gdscript toolchain, or extensions .gd | `gdscript` toolchain | scripts/main.gd, scripts/ai/ai_wizard.gd, scripts/audio/synth.gd |
| Files under the python toolchain, or extensions .ipynb, .py, .pyi | `python` toolchain | .opencode/skills/project-classifier/scripts/build_project_classifier.py, .opencode/skills/subagent-orchestrator/scripts/select_target.py, .opencode/skills/subagent-orchestrator/scripts/validate_plan.py |
| git work | `git` | .git |
| godot work | `godot` | project.godot, scenes/Main.tscn, scripts/ai/ai_wizard.gd |

### Routing tie-breakers

- **Multiple toolchains:** route by the task's path or requested artifact. If two options remain plausible, ask; do not choose from the repository root.
- **Evidence over defaults:** a detected tool being present does not mean every task should use it. Use the path and manifest above.

## Commands

- No standard commands detected. Ask before inventing one.

## Guardrails

- Do not introduce a new language, engine, package manager, or build system without approval.
- Prefer the project's existing path/manifest evidence over a global default.
- If the runtime column says `NOT ON PATH`, do not claim the tool is available; report the gap.
- Keep generated evidence intact. Edit the builder or re-run it rather than hand-editing counts.
- For a delegated task, pass the selected toolchain and command in the brief; do not make the child re-detect the stack.

## Delegation handoff

When using `subagent-orchestrator`, include:

- the task's path/module,
- the selected language and engine,
- the exact test/build command from this page,
- the relevant manifest and runtime availability.

The subagent should not choose a different stack because its model has a preference.

## Evidence

- Machine-readable profile: [`data/project-profile.json`](data/project-profile.json)
- Detailed evidence: [`references/evidence.md`](references/evidence.md)
- Scan: 216 files; truncated=false

## Warnings

- gdscript is used by the project but its runtime is not on PATH

## Refresh

Re-run the project-classifier builder after a stack change:

```bash
python3 <path-to-project-classifier>/scripts/build_project_classifier.py --root . --out C:/Users/minisforum-zach/.t3/projects/wizard-game-november-game-jam/.opencode/skills/wizard-game-tool-router --force
```
