# NEXT SESSION - Full art, material, and UI redesign

Bootstrap file for a `/sonnet-opus` session.
Read this fully before doing anything else, then read `handoffs/HANDOFF.md` for the standing project constraints.

**Run this session after `handoffs/NEXT-SESSION-weapons-and-loadouts.md` is done and merged, not before or in parallel with it - see "Sequencing" below.**

## Suggested prompt to paste after `/sonnet-opus`

> Implement the full art, material, and UI redesign recorded in `handoffs/NEXT-SESSION-art-ui-redesign.md`.
> Move the game off its current placeholder look (the user's words: "roblox lookin", and the UI reads as "AI slop") toward a realistic register in the style of Halo and Destiny, with light sci-fi accents on weapons, environment, and UI.
> This covers weapon models (the five weapons from the prior weapons session), character materials (`duelist.gd` is still on the old `pulp_lit` shader while the level geometry moved to `nuclear_pbr`), and the entire HUD/UI.
> Zero imported art and Mobile renderer are hard constraints - see `handoffs/HANDOFF.md`. Take your time, use MCP editor screenshots to self-review, and feel free to iterate more than once before calling it done - the user explicitly said quality over speed here.

## Why this exists

The user was explicit: the current look is unacceptable ("roblox lookin", UI is "AI slop") and they want a deliberate redesign, not incremental polish, in the register of Halo/Destiny with sci-fi touches.
They also said to take real time on this and iterate - it is scoped as its own session on purpose, not a tack-on to the weapons work.

## Resolved constraints (do not re-litigate these)

- **Zero imported art.** Everything is procedural: shaders, `NuclearMaterials` (`scripts/nuclear_materials.gd`), procedural mesh construction. This has held since project start and is a hard line, not a preference - see `handoffs/HANDOFF.md`.
- **Mobile renderer only.** No Forward+-only features (SSAO, SSIL, SDFGI, SSR, volumetric fog) - not affordable at 120 Hz on a phone. `handoffs/HANDOFF.md` has the reasoning.
- **Realistic-but-sci-fi**, Halo/Destiny as the named reference points, not photoreal military sim and not cartoon/stylized.
- **Level geometry already made this jump.** `shaders/nuclear_pbr.gdshader` + `NuclearMaterials` (metal-roughness PBR, procedural relief, grime/dust, sky ambient/reflection, ACES tonemapping) is the target quality bar and the toolkit to extend, not replace. `shaders/pulp_lit.gdshader` is the old look being retired - `duelist.gd` (character + weapon meshes) is the biggest thing still on it.
- **The UI is a separate, equally real complaint**, not just "make it look nicer" - the user specifically called out the settings screen's layout as unprofessional (fixed earlier this session, see `devlogs/2026-08-07.md` for the before/after) and the broader HUD/UI aesthetic as "AI slop". This session should treat the whole `duel_hud.gd` visual language (colors, typography, iconography, panel treatment) as in scope, not just the settings panel that already got a structural cleanup.

## Open questions this session must resolve

- Whether the sci-fi visual language leans toward Halo's UNSC-industrial read or Destiny's more ornate Guardian read, or a deliberate blend - this is a real aesthetic choice, not a detail; consider using `frontend-design`-style direction-setting (mood, palette, one or two reference silhouettes) before touching code, even though this is a Godot project, not a web one - the same "commit to a direction before implementing" discipline applies.
- How much of the existing procedural-noise material system (`nuclear_materials.gd`) is reusable for character/weapon materials vs. needs new material presets (skin/fabric/composite-armor style responses are a different problem than concrete/metal level geometry).
- Palette: `handoffs/HANDOFF.md`'s existing backlog already flags the current palette as over-saturated (team colors on whole walls, blown-out emissive). Decide whether this redesign session absorbs that fix or treats it as still-separate backlog - absorbing it is probably more efficient since you'll be touching the same material code anyway.
- Whether team color-coding (RED/BLUE) stays as strong accent-only per the existing backlog note, or gets reconsidered as part of the broader palette decision.

## Files you will almost certainly touch

`scripts/duelist.gd` (character + weapon meshes/materials - the biggest single gap), `scripts/nuclear_materials.gd` (new presets for character/weapon surfaces), `shaders/nuclear_pbr.gdshader` (possibly new variants), `scripts/duel_hud.gd` (full visual pass, not just layout), `scripts/riftline_arena.gd` (environment dressing, tracer/impact effect colors and shapes if the new direction wants to revisit them), `scripts/rift_link_panel.gd` (connection/lobby screen shares the UI language), `scripts/riftline_roster.gd`/related HUD consumers if roster display gets a visual pass.

## Sequencing - read this before starting

This session and `handoffs/NEXT-SESSION-weapons-and-loadouts.md` both touch `scripts/duelist.gd`, `scripts/riftline_arena.gd`, and `scripts/duel_hud.gd` heavily.
Running them as two Claude Code sessions **at the same time against the same working copy will produce colliding edits** in those files.
Run them **sequentially**: finish and commit the weapons/loadouts session first, then start this one against the updated tree, so weapon shapes and slot rules are settled before you build final art and UI around them.

If you genuinely want two sessions running concurrently, each session needs its own `git worktree` (see the `EnterWorktree`/`isolation: "worktree"` mechanism) and a real manual merge afterward - do not just open two terminals against the same checkout.

## Validation

There is no automated test for "does this look good" - use `editor_screenshot`/the `--capture=` headless PNG convention in `handoffs/HANDOFF.md` liberally and actually look at the output before calling something done, per this project's own stated standard for engineering rigor. Confirm the full exercise suite still passes (visual changes should not break logic exercises, but character material changes have broken things before by accident - check for regressions).
