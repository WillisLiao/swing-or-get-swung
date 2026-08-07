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
Art moved to real PBR via `shaders/nuclear_pbr.gdshader` + `NuclearMaterials`. The shipping character and the standalone Cover V2 review are now explicit user-requested Blender-import exceptions; neither uses textures.
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

**Same day, fifth session - death cleanup and bot respawn:**
- Eliminated character visuals now keep the existing powered-down fall for 1.8 seconds, fade over 0.7 seconds, and then hide instead of remaining in the arena indefinitely. Respawning resets visibility, transparency, and the body pose.
- Bots now automatically call the existing authoritative respawn request when their same 5-second minimum death timer expires. Human players still use the death-screen button and can change class before respawning; that manual flow is unchanged.
- `tools/riftline_modes_exercise.gd` now covers both bot auto-respawn and death-visual cleanup/reset. Headless import is clean, all 16 exercises pass, and an MCP main-scene launch reports no runtime errors (existing GDScript warnings remain).

**Same day, sixth session - Blender Cover V2 preview (explicit imported-art exception):**
- User explicitly requested a Blender-authored map pass with more cover and varied interior-wall heights. The original uniform outer wall is unchanged; 32 new pieces span 1.10-2.55m and remain 180-degree symmetric for RED/BLUE fairness.
- The Blender source is `/Users/robertwu/Documents/New project/art/exports/RiftlineMap_Concourse_CoverV2.blend`. A visual-only 205-mesh export lives at `assets/maps/riftline_map_concourse_cover_v2.glb`, wrapped by `scenes/cover_v2_preview.tscn` with an orbit camera.
- This is a standalone review scene only: it has no gameplay collisions and does not replace the procedural shipping map. Press F6 while the preview scene is open; hold Space to pause its orbit.
- Godot 4.7.1 imported the GLB cleanly, the preview scene ran through MCP with no runtime errors, and the editor is left open on `cover_v2_preview.tscn`.

**Same day, seventh session - Blender character integrated into live play (explicit imported-art exception):**
- The old GDScript-built box/cylinder body silhouette is replaced by `assets/characters/riftline_duelist_lowpoly.glb`, a Blender-authored modular low-poly armored character: 31 meshes under seven named pivots (`Torso`, `Head`, left/right arms, left/right legs, root). The source is `/Users/robertwu/Documents/New project/art/exports/RiftlineDuelist_LowPoly.blend`; no textures are used.
- One shared model serves both teams. `Duelist` assigns RED/BLUE `NuclearMaterials` at runtime by exported mesh-name roles (`TEAM_`, `DARK_`, `ARMOR_`, `METAL_`, `VISOR_`, `ACCENT_`), so there are no SUN/VOID variants or duplicated team assets.
- Existing procedural gait, stance scaling, head pitch, strafe lean, class equipment, world weapon, carrier signal, collision capsule, and networking remain attached to the same `Duelist`. The 1.8s death hold + 0.7s fade now traverses all imported `MeshInstance3D` descendants; respawn restores visibility and zero transparency exactly as before.
- `riftline_modes_exercise.gd` now locks the imported model/pivot contract, minimum mesh count, both team albedos, death disappearance, and respawn restoration. Headless import is clean, all 16 exercises pass, and MCP live-game inspection confirmed 31 meshes and `nuclear_pbr` materials for both teams.

**Deferred by explicit user decision to their own sessions - do not start these inline, use the bootstrap files:**
- `handoffs/NEXT-SESSION-art-ui-redesign.md` - its character-material premise is now partly stale because the live character is a Blender import on `NuclearMaterials`; use it for further character polish and the still-unfinished full UI pass. Visual polish for the main menu/class panel belongs here too.
- `handoffs/NEXT-SESSION-respawn-logic.md` - respawn *timing* is now resolved (5s minimum + manual respawn). What's left there, if anything, is deeper game-mode-rule interaction, not the base mechanic.

These touch `scripts/duelist.gd`, `scripts/riftline_arena.gd`, and `scripts/duel_hud.gd` in overlapping ways.
**Run them sequentially, one at a time, not as concurrently-running sessions against the same checkout** - see the "Sequencing" note in `NEXT-SESSION-art-ui-redesign.md` for what happens if you don't and how to do it safely with worktrees if you really want two running at once.

**Older backlog, still real but lower priority than the above:**
1. **Objective-aware bots.** `bot_duelist.gd` is combat-only. `set_objective_context()` exists and the arena feeds it, but nothing consumes it, so bots ignore the core entirely. This is the biggest gap for offline and bot-filled 4v4.
2. **Surface relief bands on large flat areas.** Drive albedo from the isotropic value noise and leave the sine sum for the normal only.
3. **Palette is over-saturated.** Team accents are on whole base walls; the pad emissive ring blows out. Large surfaces should be concrete/steel with team colour as accent only. (Likely absorbed into the art/UI redesign session rather than done separately - see that bootstrap file.)
4. **On-device touch playtest** of install/cancel, which PR #1's review asked for.

The old character `pulp_lit` gap is resolved by the Blender character integration above. UI polish and any later higher-detail character pass remain in the art/UI redesign bootstrap.

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

Realistic, in the register of Halo Infinite. Procedural geometry remains the default, with only the user-approved Blender character and Cover V2 review as imported-art exceptions.
Realism comes from `shaders/nuclear_pbr.gdshader` plus the `NuclearMaterials` factory in `scripts/nuclear_materials.gd`: true metal-roughness response, procedural relief with an analytic normal gradient, grime in recesses, dust on upward faces, material-supplied AO, sky ambient and reflection, ACES tonemapping, soft shadows, bloom.

The renderer stays **Mobile**.
SSAO, SSIL, SDFGI, SSR, and volumetric fog are Forward+ only and are not affordable at 120 Hz on a phone.
Do not reach for them.

The older `shaders/pulp_lit.gdshader` is the previous illustrative look and is being retired in favour of `nuclear_pbr`.

The current exceptions are the Blender Cover V2 **review scene** and the Blender character described above. The character is wired into live play; Cover V2 is still preview-only and should not be treated as approval to replace the procedural shipping map.

## Also decided, do not undo

- The **lean mechanic is gone** entirely: input, HUD controls, camera/gun/body tilt, network field. Do not re-add it.
- Teams are **RED / BLUE**, not SUN / VOID, including the rendered team colours.

## Tooling

- Godot binary on Robert's Mac: `/Users/robertwu/Downloads/Godot.app/Contents/MacOS/Godot` (Godot 4.7.1). Always export `GODOT_BIN=/Users/robertwu/Downloads/Godot.app/Contents/MacOS/Godot` on this machine. The older `/opt/homebrew/bin/godot` path no longer exists.
- Headless compile check: `GODOT_BIN='/Users/robertwu/Downloads/Godot.app/Contents/MacOS/Godot' GODOT_WATCHDOG_SECONDS=45 ./tools/run_godot_serial.sh --path . --headless --import`. An empty grep for `SCRIPT ERROR|Parse Error|Failed to load` means clean.
- Run one exercise: same runner with `--headless --script tools/<name>.gd`.
- Capture a PNG: same runner with `--resolution 2622x1206 -- --capture=/tmp/x.png --after=4`, then read the PNG to inspect it.
- Deploy: `GODOT_BIN=/opt/homebrew/bin/godot bash deploy.sh <DEVICE_UUID>`. iPhone 15 Pro `47ED6F31-01BC-5659-832A-E0512FAF1031`, iPad Pro 12.9 `78C9B3A4-2E79-5827-A287-5F09C7E29ACA`.
- GDScript here is strict: untyped inference from a Variant is a compile error. Annotate when reading out of a Dictionary (`var d: Dictionary = ...`, `var f: float = ...`, `(x as Duelist)`).
- Never leave the Godot editor open while working from the command line. It rewrites `project.godot` from its stale in-memory copy.

## Conventions

- `devlogs/YYYY-MM-DD.md` - one entry per session, append-only, dated.
- `handoffs/HANDOFF.md` (this file) - update the top with what changed and what is next.
- `handoffs/NEXT-SESSION-*.md` - a bootstrap file for a specific chunk of unstarted work.
