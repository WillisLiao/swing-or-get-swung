# Standards for AI agents working on this repo

This file is for any AI coding agent working on Nuclear Rush / SOGS - Claude Code, Codex, or anything else.
Read it before making changes, not after something ships broken or slow.
It exists because a real regression shipped on 2026-08-07 (see `devlogs/2026-08-07.md` and `devlogs/2026-08-08.md`) from four sessions in a row that verified correctness and never once measured speed, on a project whose own Mobile-renderer-at-120Hz constraint had been documented since the very first PBR pass.
Don't repeat that.

Also read `handoffs/HANDOFF.md` first for current project state, and `WORKFLOW.md` for the git/branch/PR process.
This file is standards, not status - it doesn't change from session to session the way HANDOFF.md does.

## 1. Performance discipline

**Any change to a system that runs every frame or every physics tick needs its cost reasoned about before you call it done, not just its correctness.**
That means a new camera or viewport, a per-actor loop over multiple entities, a physics or raycast query, a shader or material change, anything added to `_process()`/`_physics_process()`, or anything that runs on every HUD redraw.
"It compiles, it renders correctly, the exercises pass" is necessary but not sufficient for any of those.
Say explicitly in your summary/devlog whether you measured the cost, and what you found - don't let "I didn't check speed" go unstated the way it did before.

**How to measure, in order of how much it tells you:**

1. `scripts/riftline_arena.gd`'s `_arena_perf_sample` (`--offline-squad=<n> --arena-perf-sample` on the headless runner) prints avg/min/max frame time over 120 frames.
   Fast, cheap, CPU-only.
   It will not show you anything about GPU/render cost - headless mode uses a dummy rendering driver with no real GPU work at all.
2. For anything render/shader/material-shaped, use a windowed MCP session (`project_run` + `editor_manage(op="monitors_get")`, or `editor_screenshot(source="game")` for a visual check) instead.
3. For a real answer, get it on an actual device.
   This project's own regression only showed up on an iPad, not in the editor - desktop GPUs and mobile tile-based GPUs behave differently enough that an editor-only pass can miss a real cost entirely.

**Frame time being smooth is not the same as the work being cheap.**
A GPU that finishes a frame early on a capped frame rate still runs its clock high and draws power - "it hits 120fps" tells you the frame fit the budget, not that the total work per frame is small.
If a device runs hot despite smooth frame times, that is a real, separate signal - go looking for always-on cost (resolution, shader complexity, shadow/lighting settings, anything unconditional), not just per-action spikes.

**Prefer cutting absolute work over tuning a parameter, when the two are actually different problems.**
The sniper scope spent two rounds getting throttled and having its anti-aliasing disabled before anyone noticed the real problem was architectural - a second full-scene camera render, drawn at a several-times upscale from a small source texture, is expensive and blurry by construction, and no amount of frame-rate throttling or AA tuning was ever going to fix either complaint.
When a fix round doesn't resolve the actual complaint, don't reach for a third parameter tweak - re-examine whether the technique itself is right for the budget. See `devlogs/2026-08-08.md`'s second session entry for the full example.

**Default to interval-based recomputation for per-entity, per-tick work**, not unconditional every-frame work, unless there's a specific reason it must be exact every tick.
Stagger/jitter per-entity timers (`+ randf_range(...)`) so N entities don't all do expensive work on the same tick.
See `scripts/bot_duelist.gd`'s route-caching for the pattern.

**A `queue_redraw()`/state-push call inside something invoked every tick needs a change guard**, or it silently defeats every other redraw-gating optimization in the file - this actually happened here: a setter pushed unconditionally every physics tick made an entire HUD redraw-gate rewrite a no-op for a whole session before it was caught.
Compare the new value before assigning and returning early, the way `set_ads_state()`/`set_recoil_state()`/`show_damage()` do in `scripts/duel_hud.gd`.

## 2. Clean code discipline

**Don't leave dead state.**
A field that gets written to but never read anywhere in the draw/behavior path is not harmless - `duel_hud.gd`'s `damage_flash` field was set unconditionally every physics tick, forcing a redraw every tick, while having zero actual visual effect anywhere in the file.
If you find dead state like this, remove it or wire it up - don't leave it for the next session to rediscover as a mystery performance bug.

**Verify with the real thing, not just a green build.**
Run `tools/*_exercise.gd` (all of them, not a subset) and the headless import check before calling anything done.
For visual or interactive changes, actually run the game via MCP (`project_run`, `game_eval` to force the relevant state, `editor_screenshot`) and look at the render - a passing exercise suite proves logic, not appearance or feel.

**Spot-check anything an advisor, reviewer, or subagent tells you before acting on it.**
Cite file:line and re-read the actual lines yourself.
A review that just restates what the code already says is worthless.

**Match the codebase's own conventions instead of inventing new ones.**
This project already has a consistent voice in its comments (full sentences explaining *why*, not just *what*) and consistent patterns (the `NuclearMaterials` factory for all procedural surfaces, change-guarded setters with `queue_redraw()`, timer fields decremented by `delta` rather than counted in ticks).
New code should read like it was written by the same person who wrote the surrounding code.

**GDScript here is strict** - untyped inference from a `Variant` is a compile error.
Annotate when reading out of a `Dictionary` (`var d: Dictionary = ...`, `var f: float = ...`, `(x as Duelist)`).

## 3. `project.godot` is unreliable - don't hand-edit it for anything that matters

Confirmed 2026-08-08: opening or relaunching the Godot editor after a direct text edit to `project.godot` can silently **drop an entire new section outright**, not just revert one value to something stale.
This is worse than "the editor has a stale in-memory copy" - a `key=value` line can vanish completely, independent of comment placement or formatting, reproduced repeatedly, unrelated to any specific setting.

**For anything performance- or behavior-critical, set it in script instead.**
`Engine.physics_ticks_per_second`, `Viewport.scaling_3d_scale`/`scaling_3d_mode`, `SceneTree.physics_interpolation`, and similar are all real runtime properties - see `RiftlineArena._ready()` for the pattern.
Setting them there is immune to this bug, since it isn't `project.godot` text.

If you do need a genuine project-setting change (something with no runtime-property equivalent), verify it survived by re-reading `ProjectSettings.get_setting(...)` from a **freshly launched, independent headless process**, taken *after* the editor has been closed and reopened at least once - not just by reading the file back with a text tool, which will show your edit sitting there correctly even when the editor is about to clobber it.

## 4. When to get a second opinion

This project uses Claude Code's `/sonnet-opus` workflow, which routes visual/design work to Opus and consults Opus for architectural decisions when a fix has already been tried and failed, or when a decision crosses multiple systems (rendering + shader + lighting + project config, for example).
If you're a different agent without that routing: the same judgment call applies.
Don't guess a third time at the same problem - step back and reconsider whether the *approach* is right, not just the parameters, especially for anything rendering- or architecture-shaped.

## 5. Recording what you did

Follow the existing convention (see `WORKFLOW.md` section 4): update `handoffs/HANDOFF.md`'s top section with what changed and what's next, append a dated entry to `devlogs/`, and write a `handoffs/NEXT-SESSION-<topic>.md` bootstrap file for any well-scoped chunk of work you're leaving unstarted.
State plainly what you verified and what you didn't - on-device confirmation from an actual human, in particular, is not something an agent session can substitute for, and every performance fix in this project's history has needed it as the real final check.
