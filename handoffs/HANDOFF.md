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
The session layer is 4v4 on protocol 12 with no map or mode negotiation left in the wire format.
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

**Same day, third session - weapons, accuracy model, and class loadouts (`handoffs/NEXT-SESSION-weapons-and-loadouts.md`, now done):**
- Iron sights and the knife are gone. Every weapon ADS's through an optic; melee (`Duelist.melee_attack()`) swings whatever weapon is currently equipped, with per-weapon range/damage/cooldown.
- Five real weapons replace the single generic M4/PULSE: assault rifle, MP7-reference SMG, S1897-reference pump shotgun (9-pellet rosette), 9mm-class pistol, Halo-Infinite-referenced sniper (two zoom steps, zero ADS drift). New `scripts/rift_weapons.gd` data table backs all of it; `rift_ballistics.gd` is now fully data-driven.
- New accuracy model: `RiftWeapons.cone_for()` composes hipfire/ADS x stationary/moving/jumping/crouching from one formula per weapon, driven by new networked `Duelist` state (`bloom`, `shot_counter`, `ads_progress`) that is symmetric across `authoritative_state()`/`apply_presentation_state()`.
- Four classes (frontline/sniper/runner/shield) resolve into 1-2 loadout slots via `Duelist.configure_loadout()`; `RiftlineRoster` carries `player_class`/`primary_weapon` (defaults to Frontline/Rifle - no selection screen yet, see below). Runner wears the nuclear vest (removes the new carry damage-over-time); shield blocks frontal damage.
- All five weapons rebuilt on `NuclearMaterials` instead of the old flat `pulp_lit` boxes (mid-session user feedback: the old carbine read "Roblox/TF2-like," not the Halo/Destiny register the rest of the game already commits to) - still "lightly on the model side" per the handoff, not final art.
- `PROTOCOL_VERSION` bumped 10 -> 11 (new `melee` input field, renamed `melee_strike` wire event, new snapshot fields).
- All 16 exercises still pass, several extended for the new weapon/accuracy/loadout surface. Full detail: the "Third session" entry in `devlogs/2026-08-07.md`.
- **Not done:** shotgun reload is one bulk animation not shell-by-shell, no headshot hitboxes (none exist anywhere in the codebase yet, so the sniper's one-shot fantasy is only half-delivered), numbers are a first tuning pass. (Class selection UI landed the same day - see below.)

**Same day, fourth session - main menu, class picker, manual respawn, two bug fixes:**
- **Class picker** (new `scripts/riftline_class_panel.gd`), reused pre-game and on a new death screen.
- **Manual respawn.** `RiftlineMatch` no longer auto-respawns on a timer - `RESPAWN_MIN_SECONDS := 5.0` only unlocks `request_respawn()`, which the death screen's Respawn button calls explicitly. Non-host clients ride `respawn`/`class_id`/`primary_weapon` on the existing per-tick input frame. **Protocol bumped 11 -> 12.**
- **Real main menu** (new `scripts/riftline_main_menu.gd`): CREATE GAME / JOIN GAME / ENTER DRILL, each into the class picker first. This is now the actual destination of the settings panel's MAIN MENU action, which previously went nowhere (`_on_rift_link_cancelled()` either did nothing or silently started a new offline match instead of showing any menu).
- **Health display bug fixed.** The offline path never synced `duel_hud.gd`'s `health` field outside the `damaged` signal, so a respawn (health silently reset to 100) left the HUD showing the stale 0 from the killing blow until the next hit. Now synced every tick, matching what the LAN path already did.
- **Optic visuals fixed.** ADS still read as iron sights because no weapon had anything resembling glass to look through. `Duelist._add_optic_lens()` places a glowing lens disc at each weapon's exact ADS calibration point.
- Found and fixed along the way: `_continuous_input()` in `riftline_arena.gd` never forwarded the `melee` field, so remote players' melee never worked over LAN (local-only). `project.godot` never registered a `melee` InputMap action despite it being read every tick - was throwing an engine error every physics frame.
- All 16 exercises still pass, plus a new respawn-gate block in `riftline_modes_exercise.gd`. Full detail: the "Fourth session" entry in `devlogs/2026-08-07.md`.
- **Not done:** drill squad-size selection (solo/wing/full) isn't reachable from the new main menu (ENTER DRILL goes straight to the real 4v4). No further main-menu/class-panel visual polish - still plain rects/text.

**Deferred by explicit user decision to their own sessions - do not start these inline, use the bootstrap files:**
- `handoffs/NEXT-SESSION-art-ui-redesign.md` - full Halo/Destiny-register art, character/weapon materials off `pulp_lit`, and a full UI pass (not just the settings-panel layout fix already done). **Run after** the weapons/loadouts session (now done) - they touch the same files. Visual polish for the new main menu/class panel belongs here too.
- `handoffs/NEXT-SESSION-respawn-logic.md` - respawn *timing* is now resolved (5s minimum + manual respawn). What's left there, if anything, is deeper game-mode-rule interaction, not the base mechanic.

These touch `scripts/duelist.gd`, `scripts/riftline_arena.gd`, and `scripts/duel_hud.gd` in overlapping ways.
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
