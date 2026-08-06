# HANDOFF - Riftline (WhoYouPeekin)

Living snapshot, read first, update at end of session.

## What this is
Riftline (product name WhoYouPeekin) is a Godot 4.7 mobile FPS.
No imported art - everything is procedural geometry plus the `pulp_lit` shader.
Keep that convention.

## Current state
The circular Nuke Rush arena is implemented on branch
`circular-nuke-arena` and is ready for review through the contributor-fork
pull-request workflow. Concourse is now a symmetric circular 4v4 arena with
SUN and VOID bases on opposite sides and a central nuke pickup room. Nuke Rush
runs for three minutes: either team can take, drop, or steal the nuke; delivery
to the opposing base wins immediately; otherwise the furthest recorded push
toward the enemy base wins, with a 30-second overtime for an exact tie.

The mode is integrated with the HUD, practice-mode picker, LAN descriptors,
replicated match state, and procedural `pulp_lit` visuals. Protocol version is
10. `nuke_rush_arena.tscn` is the canonical Concourse scene used at runtime
and builds the procedural map directly in the Godot editor viewport. Headless
import and every `tools/*_exercise.gd` test pass. A concurrent
4v4 LAN host/join smoke test also passed; the existing documented ENet MTU
warning can still appear. Desktop overview, center-room, and live 4v4 captures
were visually checked. Device deployment and touch playtesting remain for a
future session.

See `handoffs/NEXT-SESSION-riftline-modes-art.md` for the earlier mode/art
backlog and the exact Godot runner and device deployment commands.

## Conventions
- `devlogs/YYYY-MM-DD.md` - one entry per session, append-only, dated.
- `handoffs/HANDOFF.md` (this file) - update the top section at the end of
  a session with what changed and what's next.
- `handoffs/NEXT-SESSION-*.md` - a fresh bootstrap file for a specific
  chunk of unstarted work, written when there's meaningful work a future
  session (human or AI) should pick up.
- See `WORKFLOW.md` for how this repo is used by two developers plus
  AI coding assistants (Claude Code / Codex).
