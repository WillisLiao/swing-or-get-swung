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

This repo is protected on `main` - land changes by branch + PR, not a direct push (`gh pr merge --admin` works for the owner). See `WORKFLOW.md` for the two-developer plus AI-assistant flow.

**As of 2026-08-07, `IOSapp` is a direct clone of this repo, at its root - there is no longer a separate `IOSapp/Riftline/` working copy.** That two-tree setup (this repo plus a working copy on a different remote, manually kept "identical" - which it in fact was not; see the sessions below for exactly how they'd diverged) was retired at the user's request specifically because of that silent drift. If you're reading this from `IOSapp` and it still looks like it has a `Riftline/` subfolder or an `X-in-a-bottle` remote, something regressed - it shouldn't.

## Current state (2026-08-08)

**Agent tooling hard gate:** every implementation, debugging, review, test, or verification task that touches game behavior must prove a live `godot-ai` MCP editor-plugin connection with an actual successful tool call before substantive investigation or any repository write.
Godot CLI and headless checks remain complementary validation and are never a fallback for missing MCP.
Any Blender or 3D-model task likewise requires an actual successful Blender MCP call, and a Blender-authored game asset requires both Blender MCP for source work and Godot MCP for import and live-game verification.
Planning, documentation-only edits, and Git or PR administration that do not assess game behavior are exempt.
See `AGENTS.md` section 0 for the blocking rules.

**Same day, second performance round - sniper scope rebuilt as FOV zoom, not picture-in-picture (`/sonnet-opus`, Opus-advised):** after the first round's throttle/MSAA fixes, the user reported the scope was still laggy on-device *and* now looked "chunky, lower resolution" while scoped - a real regression from disabling AA on the picture-in-picture SubViewport. `opus-advisor` (Medium) found the actual root cause was architectural, not tunable: the scope picture was drawn at up to 86% of screen height from a 512px source (a ~2.75-4.4x upscale), so no AA setting could have made it look sharp, and a second full-scene render at close to main-view resolution was never going to be cheap regardless of throttling. The picture-in-picture camera/SubViewport is removed entirely; the sniper now zooms the *main* camera's own FOV, exactly like every other weapon's ADS already does (`RiftWeapons.ads_horizontal_fov()`) - zero extra render passes, full native resolution, existing MSAA intact. The HUD's tube/vignette 2D art is unchanged in look but now masks the whole screen (not just its own footprint) since the zoomed view is the real main view, visible everywhere until masked. Also found and fixed a real bug from the first round: the HUD's redraw-gate rewrite (below) was itself defeated by an unconditional per-tick scope-texture push, meaning the "only redraw on change" fix never actually took effect during any match. Added magnification-aware ADS look-sensitivity scaling (only for the sniper - other weapons' already-tuned feel is untouched), since a flat sensitivity multiplier at the sniper's 3x/6x zoom would have felt wildly twitchy now that player look input actually reaches the zoomed camera (it never did under picture-in-picture). Verified live via MCP: both zoom stages render crisply full-mask-to-edges, at correct FOV, with no runtime errors. **Still not on-device verified** - same open item as below.
**Sixteenth session, mobile ADS button drag-look fixed (Robert):** mobile players can now hold the ADS button with the right thumb and drag that same touch to steer the camera while the left thumb keeps moving. The path already existed behind `ads_button_look`, but its default was OFF and previously saved device configs kept it OFF indefinitely. `DuelHud` now defaults it ON and carries a versioned one-time controls migration; a later explicit OFF choice remains respected. `riftline_mobile_touch_exercise.gd` now covers the full simultaneous two-thumb contract plus legacy/current config behavior. Clean import, all 18 exercises pass, and MCP live-game evaluation confirmed a same-touch ADS drag produced scaled look input with clean current-run game logs. The build was signed with Robert's Personal Team, installed, launched, and process-verified on both the connected iPhone and iPad. Human on-device feel/aim verification remains the next check; this input-event-only change adds no per-frame or physics-tick work.

**L2 session, Nuclear Rush respawn timing and carrier risk:** the frozen decision is a flat 6.0-second minimum in LIVE and SUDDEN_DEATH, independent of score, team, installed objective, carrier status, or dead-teammate count. Humans remain manual after the gate, bots auto-request at the same boundary, and `respawn_started` remains the authoritative spawn event. Non-vest carriers now take authoritative `RiftlineMatch.CORE_CARRY_DAMAGE_PER_SECOND` = 2.5 HP/s through `Duelist.take_damage()`, while the Runner's nuclear vest is immune; the existing 0.82x movement multiplier and independent 15-second dropped-core timer remain unchanged. `RiftlineNetwork.PROTOCOL_VERSION` is 13 with no wire-field changes. The design note predates source implementation in commit `803f109`; full implementation and validation evidence is appended to `devlogs/2026-08-08.md`.

**Fifteenth session, performance regression diagnosed and fixed (`/sonnet-opus`):** the fourteenth-session "super laggy" iPad report is addressed, not just filed. Measured with the existing `_arena_perf_sample` headless harness plus live MCP `game_eval` inspection (see `devlogs/2026-08-08.md` for the full numbers and method). The sniper scope's second full-scene render pass is throttled from `UPDATE_ALWAYS` (up to 120Hz) to `UPDATE_ONCE` on a 30Hz cadence (`scripts/duelist.gd`, `SCOPE_REFRESH_SECONDS`) - camera transform/recoil still update every frame, only the re-render itself is throttled. The bots' `route_toward()` pathfinding call, previously unconditional every physics tick for all seven bots, is now cached and recomputed on a jittered ~0.2s interval (`scripts/bot_duelist.gd`, `ROUTE_RECOMPUTE_SECONDS`) with an early-recompute trigger if the objective goal jumps more than 3m. High Alert's raycast was confirmed already correctly gated behind cheap early-outs and left unchanged. All three systems are kept, per the user's explicit instruction - nothing was reverted. **Not yet done: on-device (iPad) re-verification** - everything above was verified in-editor/headless, which is the same gap that let the original regression ship unmeasured. See "Performance discipline" below for the standing rule this added.

**Fourteenth-session context (superseded above):** three suspects were recorded with concrete file:line pointers and a bisection methodology in `handoffs/NEXT-SESSION-performance-regression.md`, now historical - its diagnosis was accurate and its fixes are in, but on-device confirmation is still open.

**Latest - fourteenth session, High Alert threat warning chip (Robert, PR #8):**
A universal local passive (no chip-selection UI yet, everyone gets it) that warns the local player when an enemy is aiming at them: alive, opposing team, 55%+ into ADS, within 95m, inside a 5.5-degree aim cone, outside the player's own view, and unobstructed - a pulsing edge arc/chevron plus a `HIGH ALERT` plate. Restyled onto the twelfth session's HUD token/plate system on merge (`HUD_ALERT`, `draw_plate`, `draw_tracked_centered`), same trigger logic and public contract. Full detail: "Fourteenth session" in `devlogs/2026-08-07.md`.

**Thirteenth session, objective-aware autonomous bots (Robert, PR #9):**
Offline teammates and enemies now understand Nuclear Rush instead of acting as combat-only targets. Each squad assigns deterministic Runner, Escort, Defender, and Raider roles; bots dynamically claim the core, escort a friendly carrier, intercept an enemy carrier, deliver and install at their own pad, defend a launch, or invade and cancel an enemy launch. They reuse the map's route planner, keep fighting opportunistically while moving toward the objective, recover from obstructions, and drive the same authoritative `interact` input used by players. A new end-to-end exercise covers decisions plus real pickup/install/cancel rules. Headless import is clean, all 17 exercises pass, and MCP runtime inspection confirmed the live 4v4 bots moving without game-log errors. Full detail: "Thirteenth session" in `devlogs/2026-08-07.md`.

**Twelfth session - full art/UI redesign via `/sonnet-opus`: Blender MCP weapons, HUD/UI visual pass, sniper scope picture-in-picture rework:**
The "zero imported art" constraint was explicitly retired this session (Blender-authored assets are now a normal part of the pipeline; Mobile renderer stays hard, unchanged). All five weapons plus the Shield-class revolver were rebuilt as Blender-authored `.glb` models in a Halo/Destiny register, replacing procedural geometry, materialized through `NuclearMaterials`/`nuclear_pbr` by the same mesh-name-prefix convention the character import already used. `duel_hud.gd`, `rift_link_panel.gd`, `riftline_main_menu.gd`, and `riftline_class_panel.gd` got a full consistent visual redesign, replacing the old placeholder look, with every public signature and touch hit-test region preserved (a real latent settings-panel hit-test bug found and fixed along the way). The sniper scope was reworked from a flat full-screen mask to a genuine picture-in-picture second camera, fixing both the "solid color outside the scope" and "no recoil while scoped" reports at once. Full detail: "Twelfth session" in `devlogs/2026-08-07.md`.

**Eleventh session - all seven bugs from `handoffs/NEXT-SESSION-weapon-visual-bugs.md` fixed, via `/sonnet-opus`:**
The reticle now tracks recoil (a new `Duelist.recoil_presentation()` pushed into `DuelHud` each frame, same pattern as `ads_progress`), the confirmed respawn-with-same-weapon bug is fixed (`set_weapon_presentation(force: bool)`), the sniper scope reticle kicks under recoil instead of reading as dead, the sniper reticle is a dot with ranging marks instead of a cross, the pistol is one-handed at hip and two-handed on ADS with a genuinely mirrored (not just relocated) support hand, the shield's default carry reads as in front of the character with a squared-up ADS parapet and a visible reload pose, and the shader's periodic sine-wave surface relief - the actual cause of the moving stripe artifact - is replaced with an analytic-derivative noise field. Full detail, including each fix's known remaining limitations (pistol sleeve occlusion, shield forearm-cuff ring, unverified long-range shader aliasing): "Eleventh session" in `devlogs/2026-08-07.md`. `handoffs/NEXT-SESSION-weapon-visual-bugs.md` is now historical - its diagnosis was accurate, but every bug it describes is fixed; nothing there is still open work.

**Ninth session - recoil, muzzle flash, ballistic shield rework, first-person hands (ported from the old `IOSapp/Riftline` working copy, now retired):**
Ported as a clean patch from that working copy's own sixth session - see "Ninth session" in `devlogs/2026-08-07.md` for full detail, and its "Known, pre-existing three-way divergence" note for exactly how the two trees had drifted apart before this port (this repo's own sixth-eighth sessions - Blender character, death-presentation cleanup, core-carry damage removal - were not reflected in the old working copy; conversely this session's work didn't exist here until ported). Recoil now moves the weapon rig's position, not just its rotation. Muzzle flash is a real crossed-blade star plus a brief point light. The Shield class has a reworked ADS (plate pitches into a low parapet, sidearm rises to a normal centered sight), a shield-bump melee, a reload pose tucked behind the vertical shield, a much larger vision port, and a new revolver model. First-person hands exist on this render path for the first time, team-neutral by design.

**Fifth session - weapon models, sights, sniper scope, and shield visibility redesign (via `/sonnet-opus`):**
All five weapon models rebuilt with distinct silhouettes; sights redesigned from a single occluding lens disc to real hollow sight housings (reflex sights, a ghost-ring shotgun sight, three-dot pistol notch-and-post) with matching HUD reticles that are now actually visible during ADS (previously none were, for any weapon). The sniper finally has a real scope: a vignette + mil-dot HUD overlay with two visibly distinct zoom stages, since a physically modeled scope tube can't be looked *through* in a raster render. Shield-class players can now see their own shield in first person - previously it only rendered for everyone else. Found and fixed a real bug along the way: 4 of 5 weapons' `optic_tip_local`/`ads_anchor` didn't actually satisfy the alignment invariant, so their sights sat visibly off the crosshair. Full detail, including a follow-up fix pass on the shotgun/pistol sights: "Fifth session" in `devlogs/2026-08-07.md`.

Robert's circular arena is in as the **only** map, ported forward from PR #1 rather than merged.
Nuclear Rush is the **only** mode, built to the final rules below.
The session layer is 4v4 on protocol 13 with no map or mode negotiation left in the wire format.
Art moved to real PBR via `shaders/nuclear_pbr.gdshader` + `NuclearMaterials`. The shipping character and the standalone Cover V2 review are now explicit user-requested Blender-import exceptions; neither uses textures.
The settings-panel touch-capture bug (a sliding finger activating other controls) is fixed with a regression test.
Headless import is clean and all 17 exercises pass.
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
- Four classes (frontline/sniper/runner/shield) resolve into 1-2 loadout slots via `Duelist.configure_loadout()`; `RiftlineRoster` carries `player_class`/`primary_weapon` (defaults to Frontline/Rifle - no selection screen yet, see below). Runner wears the nuclear vest as visual class equipment and is immune to the restored authoritative 2.5 HP/s carry damage; non-vest carriers take that damage, and the shield still blocks frontal damage.
- All five weapons rebuilt on `NuclearMaterials` instead of the old flat `pulp_lit` boxes (mid-session user feedback: the old carbine read "Roblox/TF2-like," not the Halo/Destiny register the rest of the game already commits to) - still "lightly on the model side" per the handoff, not final art.
- `PROTOCOL_VERSION` bumped 10 -> 11 (new `melee` input field, renamed `melee_strike` wire event, new snapshot fields).
- All 16 exercises still pass, several extended for the new weapon/accuracy/loadout surface. Full detail: the "Third session" entry in `devlogs/2026-08-07.md`.
- **Not done:** shotgun reload is one bulk animation not shell-by-shell, no headshot hitboxes (none exist anywhere in the codebase yet, so the sniper's one-shot fantasy is only half-delivered), numbers are a first tuning pass. (Class selection UI landed the same day - see below.)

**Same day, fourth session - main menu, class picker, manual respawn, two bug fixes:**
- **Class picker** (new `scripts/riftline_class_panel.gd`), reused pre-game and on a new death screen.
- **Manual respawn.** `RiftlineMatch` no longer auto-respawns humans on a timer - `RESPAWN_MIN_SECONDS := 6.0` only unlocks `request_respawn()`, which the death screen's Respawn button calls explicitly. Bots request through the same authoritative gate. Non-host clients ride `respawn`/`class_id`/`primary_weapon` on the existing per-tick input frame. **Protocol bumped 12 -> 13 with no wire-field changes.**
- **Real main menu** (new `scripts/riftline_main_menu.gd`): CREATE GAME / JOIN GAME / ENTER DRILL, each into the class picker first. This is now the actual destination of the settings panel's MAIN MENU action, which previously went nowhere (`_on_rift_link_cancelled()` either did nothing or silently started a new offline match instead of showing any menu).
- **Health display bug fixed.** The offline path never synced `duel_hud.gd`'s `health` field outside the `damaged` signal, so a respawn (health silently reset to 100) left the HUD showing the stale 0 from the killing blow until the next hit. Now synced every tick, matching what the LAN path already did.
- **Optic visuals fixed.** ADS still read as iron sights because no weapon had anything resembling glass to look through. `Duelist._add_optic_lens()` places a glowing lens disc at each weapon's exact ADS calibration point.
- Found and fixed along the way: `_continuous_input()` in `riftline_arena.gd` never forwarded the `melee` field, so remote players' melee never worked over LAN (local-only). `project.godot` never registered a `melee` InputMap action despite it being read every tick - was throwing an engine error every physics frame.
- All 16 exercises still pass, plus a new respawn-gate block in `riftline_modes_exercise.gd`. Full detail: the "Fourth session" entry in `devlogs/2026-08-07.md`.
- **Not done:** drill squad-size selection (solo/wing/full) isn't reachable from the new main menu (ENTER DRILL goes straight to the real 4v4). No further main-menu/class-panel visual polish - still plain rects/text.

**Same day, fifth session - death cleanup and bot respawn:**
- Eliminated character visuals now keep the existing powered-down fall for 1.8 seconds, fade over 0.7 seconds, and then hide instead of remaining in the arena indefinitely. Respawning resets visibility, transparency, and the body pose.
- Bots now automatically call the existing authoritative respawn request when their same 6-second minimum death timer expires. Human players still use the death-screen button and can change class before respawning; that manual flow is unchanged.
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

**Same day, eighth session - core carry health drain removed, later superseded by L2:**
- The earlier direct playtest decision removed the 2.5 HP/s non-Runner drain from client movement simulation, and that damage remains absent from `Duelist._simulate_motion()`.
- L2 restores the damage in the authoritative match tick only: non-vest carriers lose 2.5 HP/s, the Runner's nuclear vest is immune, and the 0.82x carrier movement multiplier remains.
- `riftline_modes_exercise.gd` now distinguishes client prediction from authoritative carry damage and covers both vest immunity and the normal death/drop/respawn chain.

**Same day, ninth session - High Alert chip v1:**
- Every local player currently has the High Alert chip equipped by default; there is no chip-selection screen yet. This is a presentation-only passive and does not change authority, damage, snapshots, or protocol 13.
- An enemy must be alive, on the opposing team, at least 55% into ADS, within 95m, aiming within a 5.5-degree cone, outside the local camera frustum, and have an unobstructed layer-1 sightline for 0.5 seconds. Cover blocks the warning; the chip never supplies through-wall information.
- A qualifying threat produces a pulsing amber screen-edge direction arc, `HIGH ALERT` plate, and a short procedural local warning tone. Each attacker must reacquire after losing the target, and its audio cue has a 5-second rearm window.
- New `scripts/riftline_high_alert.gd` owns the local evaluator. `tools/riftline_high_alert_exercise.gd` covers timing, aim cone/range, behind-camera direction, cover suppression, and HUD state. Headless import is clean, all 17 exercises pass, the visual preview was inspected at 1280x588, and an MCP live main-scene run has no runtime errors.

**Deferred by explicit user decision to their own sessions - do not start these inline, use the bootstrap files:**
- `handoffs/NEXT-SESSION-weapon-visual-bugs.md` - **done, see the eleventh session above.** Kept as a record of the diagnosis, not as open work. If a fresh visual pass on the same surfaces is wanted (the pistol-sleeve occlusion, the shield forearm-cuff ring, or long-range shader aliasing noted as remaining), file a new bootstrap rather than reopening this one.
- `handoffs/NEXT-SESSION-art-ui-redesign.md` - its character-material premise is now partly stale because the live character is a Blender import on `NuclearMaterials`; use it for further character polish and the still-unfinished full UI pass. Visual polish for the main menu/class panel belongs here too.
- `handoffs/NEXT-SESSION-respawn-logic.md` - respawn *timing* is now resolved (6s minimum + manual human respawn and automatic bot respawn). What's left there, if anything, is historical framing, not open base-mechanic work.

These touch `scripts/duelist.gd`, `scripts/riftline_arena.gd`, and `scripts/duel_hud.gd` in overlapping ways.
**Run them sequentially, one at a time, not as concurrently-running sessions against the same checkout** - see the "Sequencing" note in `NEXT-SESSION-art-ui-redesign.md` for what happens if you don't and how to do it safely with worktrees if you really want two running at once.

**Older backlog, still real but lower priority than the above:**
1. **Surface relief bands on large flat areas.** Drive albedo from the isotropic value noise and leave the sine sum for the normal only.
2. **Palette is over-saturated.** Team accents are on whole base walls; the pad emissive ring blows out. Large surfaces should be concrete/steel with team colour as accent only. (Likely absorbed into the art/UI redesign session rather than done separately - see that bootstrap file.)
3. **On-device touch playtest** of install/cancel, which PR #1's review asked for.

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
- Carrying the core costs **0.82x movement speed**, and non-vest carriers take **2.5 HP/s** authoritative core damage. The Runner's nuclear vest is immune, and every carrier keeps their full loadout.
- Respawn delay is a flat **6.0 seconds**. Humans must explicitly request after the gate; bots request automatically.

Roles (Shield Operator, Core Carrier, Support Operator, Observer/Marksman) are playstyle labels only.
No loadout or perk restrictions are enforced.
High Alert is currently a universal v1 passive, not a selectable or class-restricted perk.

## The one map

There is exactly one map, the circular Concourse, and no map selection exists in the game.
It is Robert's layout from PR #1 on the Nuclear-Rush repo, ported forward onto current `main`: a 60m-radius circular floor, RED base north (+Z) and BLUE base south (-Z) with four spawn slots each, a central open core room, a symmetric oval of cover, raised midfield decks with ramps, and roofed flank underpasses.

## Art direction

Realistic, in the register of Halo Infinite (and, as of the twelfth session below, Destiny). **The "zero imported art" rule is retired as of 2026-08-07, by explicit user decision - Blender-authored assets are now a normal, ongoing part of the pipeline, not a one-off exception.** The Blender character and Cover V2 review were the first two cases of this; they are no longer exceptions to a rule, just the first examples of the rule.
Realism still comes from `shaders/nuclear_pbr.gdshader` plus the `NuclearMaterials` factory in `scripts/nuclear_materials.gd` for procedural surfaces: true metal-roughness response, procedural relief with an analytic normal gradient, grime in recesses, dust on upward faces, material-supplied AO, sky ambient and reflection, ACES tonemapping, soft shadows, bloom. Imported Blender meshes/materials sit alongside that toolkit wherever they serve the art direction better, and should still target the same PBR/mobile-lit look (bake down to `nuclear_pbr`-compatible materials or vertex data, not baked lightmaps or techniques the Mobile renderer can't afford).

**The renderer stays Mobile - this constraint is unchanged and still hard.**
SSAO, SSIL, SDFGI, SSR, and volumetric fog are Forward+ only and are not affordable at 120 Hz on a phone.
Do not reach for them.

## Performance discipline

**See `AGENTS.md` at the repo root for the full, current standing rules on this (performance measurement, clean-code discipline, and the `project.godot` editor bug) - it's the canonical reference for any agent working on this repo, kept in sync with what's below.**

The fourteenth session shipped a real regression (see the fifteenth-session note above and `devlogs/2026-08-08.md`) because four sessions in a row verified correctness only, never speed, despite the Mobile-renderer-at-120Hz constraint above already being a hard limit.
The user's standing instruction, as of the fifteenth session: **any session that adds or changes a system that runs every frame or every physics tick (a new camera/viewport, a per-actor loop, a physics query, a shader pass) must sample frame time before calling itself done, not just confirm it renders correctly.**
Use `_arena_perf_sample`/`--arena-perf-sample` (`scripts/riftline_arena.gd`) headlessly for a fast CPU-only relative check, and note in the session's devlog entry that headless mode never exercises the GPU - anything render/shader-cost-shaped (a second camera pass, a new material, more draw calls) needs either a windowed MCP run with `monitors_get`, or better, an actual on-device sample, since this project's own regression surfaced on-device and not in the editor. "It compiles and the exercises pass" is necessary but is no longer sufficient for anything with a per-frame or per-tick cost - say so explicitly in the devlog if a session skips this, don't let it go unstated the way the twelfth-fourteenth sessions did.

The older `shaders/pulp_lit.gdshader` is the previous illustrative look and is being retired in favour of `nuclear_pbr`.

Cover V2 is still preview-only (`scenes/cover_v2_preview.tscn`) and should not be treated as approval to replace the procedural shipping map without a separate decision - that's a gameplay/collision change, not an art one.

## Also decided, do not undo

- The **lean mechanic is gone** entirely: input, HUD controls, camera/gun/body tilt, network field. Do not re-add it.
- Teams are **RED / BLUE**, not SUN / VOID, including the rendered team colours.

## Tooling

- Godot binary on Robert's Mac: `/Users/robertwu/Downloads/Godot.app/Contents/MacOS/Godot` (Godot 4.7.1). Always export `GODOT_BIN=/Users/robertwu/Downloads/Godot.app/Contents/MacOS/Godot` on this machine. The older `/opt/homebrew/bin/godot` path no longer exists.
- Headless compile check: `GODOT_BIN='/Users/robertwu/Downloads/Godot.app/Contents/MacOS/Godot' GODOT_WATCHDOG_SECONDS=45 ./tools/run_godot_serial.sh --path . --headless --import`. An empty grep for `SCRIPT ERROR|Parse Error|Failed to load` means clean.
- Run one exercise: same runner with `--headless --script tools/<name>.gd`.
- Capture a PNG: same runner with `--resolution 2622x1206 -- --capture=/tmp/x.png --after=4`, then read the PNG to inspect it. **As of 2026-08-08, this fails in this environment** (`ERROR: Parameter "t" is null` / `Cannot call method 'save_png' on a null value` from `riftline_arena.gd`'s `_capture_after_delay()`) - confirmed pre-existing via `git stash` on an unmodified checkout, not caused by any session's changes. Headless mode's dummy rendering driver can't produce a real viewport texture to save here; use the windowed MCP `editor_screenshot(source="game")` path instead for visual verification, which does work.
- Deploy: `GODOT_BIN=/opt/homebrew/bin/godot bash deploy.sh <DEVICE_UUID>`. iPhone 15 Pro `47ED6F31-01BC-5659-832A-E0512FAF1031`, iPad Pro 12.9 `78C9B3A4-2E79-5827-A287-5F09C7E29ACA`.
- GDScript here is strict: untyped inference from a Variant is a compile error. Annotate when reading out of a Dictionary (`var d: Dictionary = ...`, `var f: float = ...`, `(x as Duelist)`).
- **`project.godot` text edits are unreliable in this environment - worse than "stale in-memory copy."** Confirmed 2026-08-08: opening or relaunching the Godot editor (including via the MCP session) after a direct text edit to `project.godot` can silently **drop an entire new section/key outright**, not just revert one value to something stale - reproduced repeatedly, independent of comment placement or formatting. Never leave the Godot editor open while working from the command line, and don't trust a `project.godot` text edit survived until you've verified it with a fully independent headless process (`ProjectSettings.get_setting(...)` via `--script`) taken *after* the editor has been closed and reopened at least once. **For anything performance- or behavior-critical, set it in script instead** (`Engine.physics_ticks_per_second`, `Viewport.scaling_3d_scale`/`scaling_3d_mode`, `SceneTree.physics_interpolation`, etc. are all real runtime properties - see `RiftlineArena._ready()` for the pattern) rather than fighting this. This is not a one-off fluke; treat every `project.godot` text edit as unverified until independently re-checked.

## Conventions

- `devlogs/YYYY-MM-DD.md` - one entry per session, append-only, dated.
- `handoffs/HANDOFF.md` (this file) - update the top with what changed and what is next.
- `handoffs/NEXT-SESSION-*.md` - a bootstrap file for a specific chunk of unstarted work.
