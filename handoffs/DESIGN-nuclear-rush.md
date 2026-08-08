# DESIGN - Nuclear Rush (final game decision)

Status: FINAL, as of 2026-08-06.
This supersedes every earlier mode concept: deathmatch, bomb defuse, and the enemy-base-delivery "Nuke Rush" originally implemented on the `circular-nuke-arena` branch (PR #1, opened when the repo was still named `Nuclear-Rush`).
**Nuclear Rush is the name of the game mode, and it is the only mode.**
Do not add deathmatch, bomb defuse, or any other mode back in without an explicit new decision recorded here.

Naming, decided 2026-08-06: the **game** is **Swing or Get Swung**, the **home-screen label** under the app icon is **SOGS** (`application/config/name`), and the GitHub repo is `WillisLiao/swing-or-get-swung`.
The bundle id stays `com.lull.riftline` on purpose, because changing it breaks code signing and orphans existing installs.

## Overview

Nuclear Rush is a continuous 4v4 objective FPS mode.
There are no round resets during normal play: the match is one continuous 10-minute session, not a series of rounds like bomb-defuse modes.

A single nuclear core spawns in the center of the map.
Both teams fight to capture it and carry it back to their **own** launch base, not the enemy's.
The fiction is a nuclear weapon launch rather than a bomb plant, so "bring it home to launch it" makes more narrative and mechanical sense than "smuggle it into the enemy base".

Once the core is installed at a team's base, a launch countdown begins.
The delivering team must then defend their own base, and the opposing team must push in and cancel the launch before it completes.

## Final rules

- Match format: 4v4.
- Match duration: 10 minutes.
- No round resets during normal gameplay, one continuous match clock.
- One nuclear core spawns in the center of the map.
- Teams carry the core back to their **own** base, not the enemy's.
- Installing the core at a base begins a launch countdown.
- The opposing team can enter that base and cancel the launch.
- A successful launch earns 1 point.
- First team to reach 3 points wins.
- If neither team reaches 3 points before the 10-minute clock expires, the team with more points wins.
- If the score is tied at time expiry, the match enters sudden death and the next successful launch wins.
- After a successful launch or a cancelled launch, the core respawns in the center after a short delay.
- If the carrier dies, the core drops and can be picked up by either team.
- If a dropped core is untouched for 15 seconds, it returns to the center.

### Explicitly rejected: the two-tier scoring system

An earlier draft used "failed launch = 1 point, successful launch = 2 points".
We decided against this because it made scoring and the win condition unnecessarily complicated for a mode that should read clearly at a glance.
Only a **successful** launch scores, and it is always worth exactly 1 point.

## Team roles

Each 4-player team has four informal responsibilities.
These are playstyle roles, not hard class locks.

- **Shield Operator** protects the carrier from frontal gunfire.
- **Core Carrier** carries the core and moves more efficiently while doing so than an off-role player would.
- **Support Operator** protects the group's sides and rear.
- **Observer / Marksman** scouts enemy positions and watches likely interception routes.

## Resolved implementation decisions

These were the open questions in the original decision record.
They are now decided, and the numbers below are the ones the code implements.

**Carrier penalty: movement slowdown and authoritative core damage, no weapon restriction.**
A carrier moves at `Duelist.CORE_CARRY_SPEED_MULTIPLIER` = 0.82 of normal speed and keeps their full loadout.
Non-vest carriers lose `RiftlineMatch.CORE_CARRY_DAMAGE_PER_SECOND` = 2.5 health per second while carrying, while the Runner's nuclear vest makes that class immune to the carry damage.
The damage is applied by the authoritative match simulation through `Duelist.take_damage()`, so client prediction cannot create duplicate or divergent self-damage.
Sidearm-only was rejected: it requires surgery on the weapon and loadout system for a mode whose tension already comes from being slow and visible, and taking a player's gun away on a touchscreen reads as a bug rather than a tradeoff.

**Roles are playstyle labels, not enforced loadouts.**
No perk or loadout restriction system is implemented.
The four roles exist in the design language, comms, and documentation only.
Revisit only if a loadout system is added for other reasons.

**Launch countdown: 25 seconds, visible to both teams.**
Hiding the countdown from attackers was rejected because it makes the mode unreadable.
Both teams see the same countdown and the same installed-base marker, so the siege is legible to everyone in it.

**Install point: one fixed launch pad per base.**
`RiftlineMap.launch_pad_positions()` returns exactly one point per team.
Positional flexibility was rejected because a fixed pad is what makes the defense learnable and gives the level art something to build around.

**Cancel: hold to cancel for 3 seconds, matching the existing interact pattern.**
Install is a 2.5-second hold on the same `interact` input.
Instant-on-entry cancel was rejected as too cheap against a coordinated defense.

**Sudden death is unbounded.**
There is no sudden-death timer, and the next successful launch wins outright.
This is also the deliberate fix for the stalemate tie-break raised in review on PR #1.
In the old code a 0-0 timeout fell through to `winner = nuke_carrier_team`, which resolved to whichever team the variable happened to be initialized with when nobody had ever carried the core.
An unbounded sudden death removes the accidental default entirely rather than papering over it with a coin flip.

**Respawn delay is a flat 6.0 seconds.**
Human actors remain eliminated after the minimum until an explicit respawn request succeeds, while bots request respawn at the same authoritative boundary.
The same timer applies in normal play and sudden death, regardless of score deficit, objective ownership, carrier status, or the number of dead teammates.
The dead carrier's timer is independent of the dropped core's 15-second return timer.
The older 3.0-second framing value and the current main branch's 5.0-second implementation were both rejected because the six-second rule gives the launch and cancel loop a legible, shared absence window without hidden team-specific assistance.

## Why this shape

The mode is a neutral-object capture mode combined with a launch and base-defense phase.
It is easy for players to understand at a glance, but has more identity than a plain capture-the-flag mode because of the install-and-defend beat.
The fight does not end when the core changes hands, it shifts to a siege at the delivering team's own base.

## The map

Nuclear Rush has exactly one map, the circular Concourse, and no map selection exists anywhere in the game.
It came from Robert's PR #1 (`robertwu072792`, branch `circular-nuke-arena`) and is preserved in layout: a 60-metre-radius circular floor inside a segmented perimeter wall, opposing RED and BLUE bases at the north and south rim with four spawn slots each, a central open pickup room with equal north and south entrances, a symmetric oval cover pattern of side columns and shoulder blocks, raised midfield decks reached by ramps, and roofed flank underpasses.

RED holds the north base at +Z, BLUE holds the south base at -Z.
The original branch predated the SUN/VOID to RED/BLUE rename and the lean removal, so the layout was ported forward onto current `main` rather than merged.

## Art direction

Realistic, in the register of Halo Infinite: real metal-roughness surface response, sky-sourced ambient and reflection, ACES tonemapping, high-resolution soft shadows, and bloom.

**The "zero imported art" rule is retired as of 2026-08-07** (explicit user decision - see `handoffs/HANDOFF.md`). Blender-authored assets are now a normal part of the pipeline, not a one-off exception.
Realism still leans on `shaders/nuclear_pbr.gdshader` and the `NuclearMaterials` factory - physically based diffuse and specular, procedural surface relief with an analytic normal gradient, grime that pools in recesses, dust on upward faces, and material-supplied ambient occlusion - but imported meshes/textures authored in Blender are equally valid where they serve the art direction better.

The renderer stays **Mobile**, not Forward+.
Forward+ would unlock SSAO, SSIL, SDFGI, SSR, and volumetric fog, and none of them are affordable at 120 Hz on a phone.
Do not reach for those effects, and do not assume they work if you set them.
