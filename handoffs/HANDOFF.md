# HANDOFF - Swing or Get Swung

Living snapshot, read first, update at end of session.

## What this is

**The game is called Swing or Get Swung.**
The home-screen label under the app icon is the short form **SOGS**, because iOS truncates a long name there.
**Nuclear Rush is the name of the game mode**, not the game. Do not conflate the two.

It is a Godot 4.7 mobile 4v4 objective FPS, landscape only, built for iOS.
Earlier names for the same project: Riftline, WhoYouPeekin, Nuclear Rush.

The bundle id is still `com.lull.riftline` and is deliberately unchanged, because changing it breaks code signing and orphans existing installs.
That is a separate decision from the display name.

This source tree lives in two places that are kept identical: `IOSapp/Riftline/` (day-to-day working copy) and the standalone `WillisLiao/swing-or-get-swung` GitHub repo (collaboration home, protected `main`, PRs required).
That repo was previously named `Nuclear-Rush`; GitHub redirects the old URL, but new clones should use the current name.
See `WORKFLOW.md` in that repo for the two-developer plus AI-assistant flow.

## Current state (2026-08-07)

Robert's circular arena is in as the **only** map, ported forward from PR #1 rather than merged.
Nuclear Rush is the **only** mode, built to the final rules below.
The session layer is 4v4 on protocol 10 with no map or mode negotiation left in the wire format.
Art moved to real PBR via `shaders/nuclear_pbr.gdshader` + `NuclearMaterials`, still with zero imported art.
The settings-panel touch-capture bug (a sliding finger activating other controls) is fixed with a regression test.
Headless import is clean and all 16 exercises pass.
Full detail: `devlogs/2026-08-07.md`.

**Same day, second session - multiplayer hardening and three bug fixes:**
- **Reconnect grace period.** A human actor's connection dropping during a LIVE/ARMING match no longer instantly abandons the match. The dropped slot is reserved under a rejoin token for `RiftlineLobby.RECONNECT_GRACE_MS` (20s); the same client reconnecting within that window is restored to its original actor/team identity. Only a grace-window timeout (or a non-live-phase disconnect, unchanged) abandons the match. New: `RiftlineRoster.disconnect_peer/reclaim/disconnected_records`, `RiftlineLobby.disconnect_peer/reclaim_peer/sweep_grace`, network-level rejoin handshake in `riftline_network.gd`. This is foundation work for eventual internet play (still LAN/ENet only today, by explicit user decision - see `devlogs/2026-08-07.md`), not internet play itself.
- **Health bar fixed.** `duel_hud.gd`'s vitality strip was rendering `ceili(health/20)` as 5 discrete plates (a "5 hits and you're dead" display) even though the underlying model was already a real 100 HP value. It is now a continuous 0-100 bar with a numeric readout.
- **Damage falloff/range bug fixed.** `rift_ballistics.gd`'s `M4_MAX_RANGE` was 48m on a 60m-radius (120m diameter) map - long-sightline shots were vanishing with zero damage and no feedback, which read as "shots not registering." Range raised to 95m with a real linear damage falloff (23 near, floors at 14 far) instead of a hard cutoff.
- **Bullet/impact visuals fixed.** The in-flight tracer was a thin box streak and the wall/duelist impact effect was a literal `+`-shaped cross (two crossed boxes). Tracer is now a small stretched sphere; impact is a circular scorch mark + ring, not a cross.
- **Settings panel redesigned + Main Menu added.** There was previously no way back to the connection/staging screen from inside a match short of restarting the app. `duel_hud.gd` settings now has a MAIN MENU action (reuses the existing `_on_rift_link_cancelled()` leave/severed path) and the whole panel moved from hand-placed pixel offsets to a real 2-column grid with section headers; the dead inert "QUICK SWAP" chip was removed.
- All 16 exercises still pass, including a new reconnect-grace block in `tools/riftline_lobby_exercise.gd`.

**Deferred by explicit user decision to their own sessions - do not start these inline, use the bootstrap files:**
- `handoffs/NEXT-SESSION-weapons-and-loadouts.md` - remove iron sights and the knife, real per-stance/movement/ADS accuracy model, five real weapons (AR/SMG/shotgun/pistol/sniper) replacing the one generic M4, four-class 2-slot loadout rebuild (frontline/sniper/runner/shield), nuclear vest mechanic.
- `handoffs/NEXT-SESSION-art-ui-redesign.md` - full Halo/Destiny-register art, character/weapon materials off `pulp_lit`, and a full UI pass (not just the settings-panel layout fix already done). **Run after** the weapons/loadouts session - they touch the same files.
- `handoffs/NEXT-SESSION-respawn-logic.md` - respawn timing considered as part of the whole game-mode-rule chain, not an isolated number. Framing only so far, no design.

These three touch `scripts/duelist.gd`, `scripts/riftline_arena.gd`, and `scripts/duel_hud.gd` in overlapping ways.
**Run them sequentially, one at a time, not as concurrently-running sessions against the same checkout** - see the "Sequencing" note in `NEXT-SESSION-art-ui-redesign.md` for what happens if you don't and how to do it safely with worktrees if you really want two running at once.

**Older backlog, still real but lower priority than the above:**
1. **Objective-aware bots.** `bot_duelist.gd` is combat-only. `set_objective_context()` exists and the arena feeds it, but nothing consumes it, so bots ignore the core entirely. This is the biggest gap for offline and bot-filled 4v4.
2. **Surface relief bands on large flat areas.** Drive albedo from the isotropic value noise and leave the sine sum for the normal only.
3. **Palette is over-saturated.** Team accents are on whole base walls; the pad emissive ring blows out. Large surfaces should be concrete/steel with team colour as accent only. (Likely absorbed into the art/UI redesign session rather than done separately - see that bootstrap file.)
4. **On-device touch playtest** of install/cancel, which PR #1's review asked for.

Character/weapon materials being on `pulp_lit` moved from this list into the art/UI redesign bootstrap file - it is the same underlying gap, just now scoped with the rest of the visual redesign instead of as a standalone item.

## THE GAME MODE - FINAL RULES

Nuclear Rush is the **only** mode.
Deathmatch and bomb defuse were removed and must not come back without a new recorded decision.
Full reasoning, plus every resolved implementation question, is in `handoffs/DESIGN-nuclear-rush.md`.
The rules themselves:

- **4v4.** One continuous 10-minute match. No round resets.
- **One nuclear core** spawns in the center of the map.
- Both teams fight for it and carry it back to their **own** launch base, not the enemy's.
- **Installing** the core at your own base pad begins a **launch countdown**. Install is a 2.5-second hold on `interact`.
- The **countdown is 25 seconds** and is visible to both teams.
- The opposing team can push into that base and **cancel** the launch with a 3-second hold on `interact`.
- A **successful launch scores exactly 1 point**. A cancelled launch scores nothing.
- **First to 3 points wins.**
- If nobody reaches 3 before the clock expires, the higher score wins.
- If the score is **tied** at expiry, the match enters **sudden death** and the **next successful launch wins**. Sudden death is unbounded, so there is no default winner and no coin flip.
- If the **carrier dies the core drops**, and either team can pick it up.
- A dropped core **untouched for 15 seconds returns to center**.
- After a launch or a cancel, the core **respawns at center after a short delay**.
- Carrying the core costs **movement speed only** (0.82x). The carrier keeps their full loadout.
- Respawn delay is **3.0 seconds**.

Roles (Shield Operator, Core Carrier, Support Operator, Observer/Marksman) are playstyle labels only.
No loadout or perk restrictions are enforced.

## The one map

There is exactly one map, the circular Concourse, and no map selection exists in the game.
It is Robert's layout from PR #1 on the Nuclear-Rush repo, ported forward onto current `main`: a 60m-radius circular floor, RED base north (+Z) and BLUE base south (-Z) with four spawn slots each, a central open core room, a symmetric oval of cover, raised midfield decks with ramps, and roofed flank underpasses.

## Art direction

Realistic, in the register of Halo Infinite, but with **no imported art** - that convention still holds.
Realism comes from `shaders/nuclear_pbr.gdshader` plus the `NuclearMaterials` factory in `scripts/nuclear_materials.gd`: true metal-roughness response, procedural relief with an analytic normal gradient, grime in recesses, dust on upward faces, material-supplied AO, sky ambient and reflection, ACES tonemapping, soft shadows, bloom.

The renderer stays **Mobile**.
SSAO, SSIL, SDFGI, SSR, and volumetric fog are Forward+ only and are not affordable at 120 Hz on a phone.
Do not reach for them.

The older `shaders/pulp_lit.gdshader` is the previous illustrative look and is being retired in favour of `nuclear_pbr`.

## Also decided, do not undo

- The **lean mechanic is gone** entirely: input, HUD controls, camera/gun/body tilt, network field. Do not re-add it.
- Teams are **RED / BLUE**, not SUN / VOID, including the rendered team colours.

## Tooling

- Godot binary: `/opt/homebrew/bin/godot` (Godot 4.7.1). Always export `GODOT_BIN=/opt/homebrew/bin/godot`.
- Headless compile check: `GODOT_BIN=/opt/homebrew/bin/godot GODOT_WATCHDOG_SECONDS=45 ./tools/run_godot_serial.sh --path . --headless --import`. An empty grep for `SCRIPT ERROR|Parse Error|Failed to load` means clean.
- Run one exercise: same runner with `--headless --script tools/<name>.gd`.
- Capture a PNG: same runner with `--resolution 2622x1206 -- --capture=/tmp/x.png --after=4`, then read the PNG to inspect it.
- Deploy: `GODOT_BIN=/opt/homebrew/bin/godot bash deploy.sh <DEVICE_UUID>`. iPhone 15 Pro `47ED6F31-01BC-5659-832A-E0512FAF1031`, iPad Pro 12.9 `78C9B3A4-2E79-5827-A287-5F09C7E29ACA`.
- GDScript here is strict: untyped inference from a Variant is a compile error. Annotate when reading out of a Dictionary (`var d: Dictionary = ...`, `var f: float = ...`, `(x as Duelist)`).
- Never leave the Godot editor open while working from the command line. It rewrites `project.godot` from its stale in-memory copy.

## Conventions

- `devlogs/YYYY-MM-DD.md` - one entry per session, append-only, dated.
- `handoffs/HANDOFF.md` (this file) - update the top with what changed and what is next.
- `handoffs/NEXT-SESSION-*.md` - a bootstrap file for a specific chunk of unstarted work.
