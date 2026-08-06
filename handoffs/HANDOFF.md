# HANDOFF - Nuclear Rush

Living snapshot, read first, update at end of session.

## What this is
Nuclear Rush (formerly Riftline / WhoYouPeekin) is a Godot 4.7 mobile FPS.
No imported art - everything is procedural geometry plus the `pulp_lit` shader.
Keep that convention.

## Current state
**The game design is now final and single-mode: read
`handoffs/DESIGN-nuclear-rush.md` first.**
It is the one and only game mode going forward and supersedes every
earlier mode concept, including the enemy-base-delivery "Nuke Rush" in
open PR #1 - that PR's win condition (deliver to the enemy base) now
conflicts with the final design (deliver to your own base, then defend
the launch) and needs rework before merge.

Also removed this session: the lean mechanic (input, HUD controls,
camera/gun/body tilt, network field) is gone entirely - don't re-add it.
Teams were renamed from SUN/VOID to RED/BLUE across the whole codebase,
including the rendered team colors (RED now actually renders red).

See `handoffs/NEXT-SESSION-riftline-modes-art.md` for older in-flight
tooling notes (Godot binary path, headless exercise runner, deploy
script, device UUIDs) - still accurate for how to run things, just not
for which mode to build.

## Conventions
- `devlogs/YYYY-MM-DD.md` - one entry per session, append-only, dated.
- `handoffs/HANDOFF.md` (this file) - update the top section at the end of
  a session with what changed and what's next.
- `handoffs/NEXT-SESSION-*.md` - a fresh bootstrap file for a specific
  chunk of unstarted work, written when there's meaningful work a future
  session (human or AI) should pick up.
- See `WORKFLOW.md` for how this repo is used by two developers plus
  AI coding assistants (Claude Code / Codex).
