# NEXT SESSION - Respawn timing and game-mode-rule reasoning

Bootstrap file for a `/sonnet-opus` session.
Read this fully before doing anything else, then read `handoffs/HANDOFF.md` and `handoffs/DESIGN-nuclear-rush.md` for the full current rule set and its reasoning.

**This file is deliberately framing only.** No respawn design has been decided yet - that is next session's job, not this one's. This session (2026-08-07) only wrote down the problem and the constraints it must respect.

## Suggested prompt to paste after `/sonnet-opus`

> Design and implement respawn timing for Nuclear Rush, using deep logical reasoning about how the game mode's rules should interact with respawn - read `handoffs/NEXT-SESSION-respawn-logic.md` first, it has the constraints and open questions, not a design.
> Respawn time is one link in a longer chain of game-mode-rule consequences, not an isolated number - reason about the whole chain before picking a value or formula.
> This is exactly the kind of decision the sonnet-opus skill flags for an `opus-advisor` consult (or `opus-adjudicator` if the reasoning gets genuinely gnarly): it is a long-lived gameplay rule with second-order effects on pacing, comeback potential, and the core-carry loop. Consult before finalizing.

## Why this exists

The user asked for this explicitly, separately from the weapons/loadouts and art/UI work, and asked that it get a dedicated session with real reasoning rather than a quick guess - possibly with an Opus subagent, in their words.

## What is already decided (from `handoffs/HANDOFF.md` - do not re-derive, just respect)

- Nuclear Rush is 4v4, one continuous 10-minute match, no round resets.
- Respawn delay is currently a flat **3.0 seconds** - this is the number in question, not necessarily wrong, but not derived from anything documented either.
- One core, center spawn, carried to your **own** base, not the enemy's.
- Install is a 2.5s hold; launch countdown is 25s, visible to both teams; cancel is a 3s hold.
- A launch scores 1 point; first to 3 wins; tied-at-expiry goes to sudden death (next successful launch wins, unbounded).
- If the carrier dies, the core drops; untouched for 15s, it returns to center. Core respawns at center after a short delay following a launch or cancel.
- Carrying the core costs 0.82x speed. (The weapons/loadouts session may add carrier damage-over-time without the nuclear vest - check whether that landed before this session starts, since it changes the calculus of how costly dying-while-carrying already is before respawn even enters the picture.)
- Roles (Shield Operator, Core Carrier, Support Operator, Observer/Marksman - soon to be formalized as actual classes with real loadout restrictions, see `handoffs/NEXT-SESSION-weapons-and-loadouts.md`) are playstyle labels, not loadout restrictions, as of this writing - check whether that has changed.

## The actual open question

Whether a flat 3.0s respawn delay is the right model at all, given:

- A 25-second launch countdown that the opposing team can push to cancel - does respawn timing need to account for whether a teammate died defending or attacking a countdown, so a team is not structurally unable to contest it?
- Sudden death being unbounded - does respawn pacing change in sudden death, where a single life arguably matters more?
- Whether respawn time should scale with anything (score deficit, match time remaining, how many teammates are already dead) the way some competitive shooters do for comeback pacing, or whether a flat number is the more honest, more competitively legible choice - this is a real design tradeoff, not a solved problem, and deserves the "deep logical reasoning" the user asked for rather than a copied convention from another game.
- How respawn interacts with the core carrier's death specifically - the core drops and sits contestable for up to 15 seconds; does the dead carrier's own respawn timer need to relate to that 15-second window at all, or are they cleanly independent systems?

## Where the current implementation lives

`scripts/riftline_match.gd` (482 lines - the game-mode rules/phase state machine) is the most likely home for whatever the new model becomes; `scripts/riftline_arena.gd` currently drives the respawn timer and consumes `respawn_started`-style signals (search for `respawn` across both files before starting - the mechanism was touched at least once before, see the `devlogs/2026-08-07.md` entry about a wrongly-deleted `respawn_started` signal being restored).

## Non-goals for this specific session

Do not redesign the core/launch/scoring rules themselves - those are marked "do not undo without a new recorded decision" in `handoffs/HANDOFF.md`. Respawn timing is the scope; if reasoning about it surfaces a real problem with the core/launch rules, write that up as its own decision rather than silently changing them here.
