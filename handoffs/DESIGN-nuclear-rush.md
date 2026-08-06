# DESIGN - Nuclear Rush (final game decision)

Status: FINAL, as of 2026-08-06.
This supersedes every earlier mode concept (deathmatch, bomb defuse, the
enemy-base-delivery "Nuke Rush" implemented on the `circular-nuke-arena`
branch / PR #1).
The game is now officially called **Nuclear Rush**, and this is the only
game mode.
Do not add deathmatch, bomb defuse, or any other mode back in without an
explicit new decision recorded here.

## Important: conflicts with the in-flight PR

PR #1 ("Add circular 4v4 Nuke Rush mode") delivers the core to the
**enemy's** base.
That is now wrong.
Per this decision, the core is carried back to the carrying team's **own**
base, and installing it there starts a launch countdown that the *other*
team must interrupt.
The circular Concourse map layout, the neutral center pickup, and the
carry/drop/steal mechanics in that PR are still directionally useful, but
the win condition and base-relationship need to be reworked before merge.

## Overview

Nuclear Rush is a continuous 4v4 objective FPS mode.
There are no round resets during normal play - the match is one
continuous 10-minute session, not a series of rounds like bomb-defuse
modes.

A single nuclear core spawns in the center of the map.
Both teams fight to capture it and carry it back to their **own** launch
base - not the enemy's.
The fiction is a nuclear weapon launch, not a bomb plant, so "bring it
home to launch it" makes more narrative and mechanical sense than
"smuggle it into the enemy base."

Once the core is installed at a team's base, a launch countdown begins.
The delivering team must now defend their base; the opposing team must
push in and cancel the launch before it completes.

## Final rules

- Match format: 4v4.
- Match duration: 10 minutes.
- No round resets during normal gameplay - continuous match clock.
- One nuclear core spawns in the center of the map.
- Teams must carry the core back to their **own** base (not the enemy's).
- Installing the core at a base begins a launch countdown.
- The opposing team can enter that base and cancel the launch.
- A successful launch earns 1 point.
- First team to reach 3 points wins.
- If neither team reaches 3 points before the 10-minute clock expires,
  the team with more points wins.
- If the score is tied at time expiry, the match enters sudden death -
  the next successful launch wins.
- After a successful launch, or a cancelled launch, the core respawns in
  the center after a short delay.
- If the carrier dies, the core drops and can be picked up by either
  team.
- If a dropped core is untouched for 15 seconds, it returns to the
  center.

### Explicitly rejected: the two-tier scoring system

An earlier draft used "failed launch = 1 point, successful launch = 2
points."
We decided against this - it made scoring and the win condition
unnecessarily complicated for a mode that should read clearly at a
glance.
Only a **successful** launch scores, and it is always worth exactly 1
point.

## Team roles

Each 4-player team has four informal responsibilities.
These are playstyle roles, not hard class locks (no confirmed loadout
restriction system yet - see open questions below).

- **Shield Operator** - protects the carrier from frontal gunfire.
- **Core Carrier** - carries the core; wears a protective suit and takes
  a smaller movement penalty while carrying than an off-role player
  would.
- **Support Operator** - protects the group's sides and rear.
- **Observer / Marksman** - scouts enemy positions and watches likely
  interception routes.

The carrier may be limited to a sidearm (pistol-only) while holding the
core, or take a slight movement penalty instead - exact tradeoff still
open (see below).
A player specialized as Core Carrier should still carry the core more
efficiently (less penalty) than a player in one of the other three
roles.

## Why this shape

The mode is a neutral-object capture mode combined with a launch and
base-defense phase.
It's easy for players to understand at a glance, but has more identity
than a plain capture-the-flag mode because of the install-and-defend
beat: the fight doesn't end when the core changes hands, it shifts to a
siege at the delivering team's own base.

## Open questions for implementation (not yet decided)

- Exact carrier penalty: sidearm-only vs. movement-speed penalty vs.
  both, and the specific numbers.
- Whether roles (Shield / Carrier / Support / Observer) are just
  playstyle labels the HUD/comms can reference, or whether they come
  with actual loadout/perk restrictions enforced by the game.
- Launch countdown duration and whether it's visible/audible to both
  teams or only the defending team.
- Whether the base install point is a fixed spot per base or has some
  positional flexibility.
- Cancel mechanic: instant on entering a zone, a hold-to-cancel
  interaction (matching the existing bomb-defuse hold-to-interact
  pattern), or something else.
