**Historical - done, see the fifteenth session in `devlogs/2026-08-08.md` and `handoffs/HANDOFF.md`'s "Current state" and "Performance discipline" sections.**
Every suspect below was checked with real numbers, not guessed. The scope viewport and bot pathfinding were confirmed as real costs and made cheaper (throttled render, cached routing) without reverting either system; High Alert was confirmed already well-gated and left unchanged.
**Still open: on-device (iPad) re-verification** - this file's own methodology's step 4 has not run yet.
Kept below as the original diagnosis record, not as open work.

# NEXT SESSION - Diagnose and fix the post-redesign performance regression

Bootstrap file for a fresh session (does not need to be `/sonnet-opus` - this is diagnosis-first, not visual work, though a real fix might route through it once the cause is known).
Read this fully before doing anything else, then read `handoffs/HANDOFF.md` for the standing project constraints (art direction, renderer, tooling commands).

## Suggested prompt to paste

> The game is "super laggy" on a real device after the twelfth-fourteenth session redesign (art/UI, sniper scope rework, bots, High Alert chip) - see `handoffs/NEXT-SESSION-performance-regression.md`.
> Find the actual cause before changing anything - profile and bisect, don't guess.
> The three suspects (Blender weapon art / new sniper scope viewport, autonomous bots, High Alert chip) are recorded with concrete file:line pointers and a suggested measurement method. Confirm which one(s) are real with numbers from the device or a live MCP profiling pass, then fix the real cause - which may mean re-implementing a system more cheaply rather than reverting it, since the user wants all of this functionality kept.

## Why this exists

The user deployed the build from the twelfth-fourteenth sessions (art/UI redesign, sniper scope rework, Robert's autonomous bots, Robert's High Alert chip - all merged the same session, see `devlogs/2026-08-07.md`) to their iPad and reported it as "super laggy."
None of the four MCP-verified sessions that produced this build measured frame time or GPU/CPU cost - every verification pass was "does it render correctly," never "is it still fast."
This is a real gap in that verification, not just bad luck - `handoffs/HANDOFF.md`'s art direction section has said "Mobile renderer... not affordable at 120 Hz on a phone" since the project's very first PBR pass, and this session broke that discipline by never actually measuring against it.

The user explicitly does not want a blind revert - they want to know *which* system is responsible (or how much each contributes) so it can be **fixed/re-implemented correctly**, not thrown away.
All three candidate systems are wanted long-term.

## Suspects, ranked by plausibility, with concrete pointers

### 1. Sniper scope picture-in-picture (`Duelist._scope_viewport`/`_scope_camera`) - strongest single suspect

`scripts/duelist.gd` (search `SCOPE_VIEWPORT_SIZE`, `_scope_viewport`, `_scope_camera`): while a player is aiming the sniper past `ads_progress > 0.02`, a second `Camera3D` inside a 512x512 `SubViewport` renders the **entire same `World3D` a second time**, every frame (`render_target_update_mode = SubViewport.UPDATE_ALWAYS`), on top of the main camera's own render.
This is a real doubled draw-call/fragment-shading cost, not a cheap effect - full scene geometry, full `nuclear_pbr` shading, full lighting, twice, simultaneously, for as long as a player is scoped in.
On a 120 Hz mobile target this is the single most expensive thing added this session by construction, not by accident.

**Not yet measured:** whether this is the actual cause, how bad it is (512x512 is small, but the *shading* cost of a second full scene pass is the concern, not the resolution), or whether it's the cause of *general* lag (the user's report doesn't say "only while scoped," which would seem to rule this out - but if they were testing with a Sniper-class loadout for a while, or if `render_target_update_mode` is somehow not actually resetting to `UPDATE_DISABLED` when not scoped, it could be running continuously - check that first, it would be a real bug, not just a cost tradeoff).

**How to check:** `mcp__godot-ai__editor_manage(op="monitors_get")` for GPU/frame-time monitors, sampled with a sniper equipped but not aiming vs. aiming vs. any other weapon, on a live MCP run. If the device itself is available, Xcode's GPU frame capture or a simple on-screen FPS counter comparing sniper-scoped vs. everything else would be more conclusive than the editor, since mobile GPU behavior does not always match the desktop editor's.

### 2. Autonomous bots (`BotDuelist`, Robert's PR #9) - plausible, continuous cost

`scripts/bot_duelist.gd:157` (`_physics_process`) and `:273` (`route_toward()`, called every physics tick per bot): seven bots each recompute a navigation route toward their current objective goal every physics frame, unconditionally, for the entire match - not once per objective change, not on a timer.
`scripts/riftline_arena.gd`'s `_tick_high_alert`/`_populate_bot_opponents`/`_sync_*` functions also now do additional per-bot work every `_physics_process` tick (search for what was added in the "Thirteenth session" - see `devlogs/2026-08-07.md`).
Pathfinding recomputation every tick for seven actors simultaneously is a classic CPU-side cost that would read as general, constant lag rather than a spike tied to one weapon - which matches "super laggy" better than suspect #1 does, if the report was general and not specifically about aiming.

**How to check:** compare frame time/tick time with `RiftlineArena._populate_bot_opponents()`'s bot count temporarily forced to 0 (offline solo, no bots) vs. the normal 7-bot 4v4, everything else identical. If `route_toward()` is expensive, consider recomputing it on an interval (e.g. every 0.2-0.5s, or only when the goal actually changes) rather than every physics tick - that is very likely a "re-implement more cheaply" fix, not a "remove the feature" one.

### 3. High Alert chip (`RiftlineHighAlert`, Robert's PR #8) - real but probably smallest

`scripts/riftline_high_alert.gd:87-89` (`evaluate()`): does a `PhysicsRayQueryParameters3D` raycast against world collision **per opponent, every physics tick**, for every player who has an opponent roughly aiming their way (worst case: up to 7 raycasts/tick).
This is real physics-server cost but is gated behind several cheap early-outs (team check, ADS-progress threshold, range, aim-cone dot product) before the raycast runs, so it's unlikely to be the dominant cost unless those gates are being satisfied constantly (e.g. bots aim at the player a lot, which - combined with suspect #2 - could compound).

**How to check:** same interval/gating idea as #2 - if this turns out to matter, cache/skip the raycast when the cheap checks already ruled out most candidates (they should already be doing this - confirm the early-outs actually short-circuit before the raycast, not after).

## What was NOT measured and should not be assumed

- The Blender weapon `.glb` models themselves (polycounts: rifle 4476, smg 3348, shotgun ~4400, pistol 2240, sniper 5112, revolver 2256 - see the twelfth-session devlog entry) are not high by any normal mobile standard and are an unlikely primary cause on their own. Don't spend time re-optimizing geometry before ruling out #1-#3 above.
- The HUD redesign's tracked/letter-spaced text draws per character (the implementing agent's own report flagged roughly 40-70 `draw_char` calls per HUD frame as "not measured against the 120 Hz mobile budget, worth a perf sample if frame time regresses" - see the twelfth-session devlog entry) is a real, self-flagged unknown, worth checking but a lower prior than #1/#2 since it's `_draw()` overhead, not a full render pass or per-frame physics query.
- Nothing about `shaders/nuclear_pbr.gdshader` changed this session (the material system was already the Mobile-renderer baseline going in) - it is not a new suspect, though it's still worth a sanity FPS spot-check the way the eleventh session already did once (see that devlog entry for the exact method: fixed camera pose, uncapped FPS, old vs. new).

## Methodology - bisect with numbers, not guesses

1. Get a real baseline number first: `mcp__godot-ai__editor_manage(op="monitors_get")` or the device's own FPS overlay, on the actual iPad if possible (the editor's numbers do not necessarily match on-device mobile GPU/CPU behavior - this whole regression only surfaced on-device, not in editor verification, which is itself a clue that whatever it is may be worse on real mobile hardware than the desktop editor suggested).
2. Toggle one suspect at a time (force bot count to 0; force the scope viewport permanently `UPDATE_DISABLED` and compare with/without aiming sniper; stub `RiftlineHighAlert.evaluate()` to return inactive immediately) and re-measure. Do not toggle more than one at once - you need to know which one(s) actually move the number, not just confirm the combination is slow.
3. Once the real cause (or causes, could be more than one) is confirmed with numbers, fix it properly - the user wants all three systems kept, so the fix is almost always "make the same feature cheaper" (interval-based recomputation, smaller/lower-frequency scope viewport, gated raycasts) not "delete it."
4. Re-verify on-device after the fix, not just in the editor - that's the gap that let this regression ship in the first place.
