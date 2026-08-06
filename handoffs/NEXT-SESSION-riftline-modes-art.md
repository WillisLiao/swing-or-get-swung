# HANDOFF — Riftline (WhoYouPeekin): finish mode swap + art pass

Target model: a fast, cheap executor (e.g. Qwen 3.6 flash). Follow steps IN ORDER, verify after each, and stop to report if a step fails twice. Do not improvise beyond the listed edits. Work ONLY in `/Users/willis/Documents/IOSapp/Riftline`. The game is a Godot 4.7 mobile FPS. There is NO imported art — everything is procedural geometry + the `pulp_lit` shader; keep that convention for the art pass.

## Tooling you must use (do not invent alternatives)
- Godot binary: `/opt/homebrew/bin/godot` (there is NO `/Applications/Godot.app`). Always export `GODOT_BIN=/opt/homebrew/bin/godot`.
- Run any exercise: `GODOT_BIN=/opt/homebrew/bin/godot GODOT_WATCHDOG_SECONDS=45 ./Riftline/tools/run_godot_serial.sh --path Riftline --headless --script tools/<name>.gd`
- Headless compile check: `... run_godot_serial.sh --path Riftline --headless --import` (empty grep for `SCRIPT ERROR|Parse Error|Failed to load` = clean).
- Capture a PNG: `... run_godot_serial.sh --path Riftline --resolution 2622x1206 -- --motion-preview=<case> --capture=/tmp/x.png --after=4` then READ the PNG to inspect it.
- Deploy to device: `cd Riftline && GODOT_BIN=/opt/homebrew/bin/godot bash deploy.sh <DEVICE_UUID>`. iPhone 15 Pro = `47ED6F31-01BC-5659-832A-E0512FAF1031`; iPad Pro 12.9 = `78C9B3A4-2E79-5827-A287-5F09C7E29ACA`.
- GDScript is STRICT: untyped inference from a Variant is a compile ERROR. When reading a Dictionary value into a var, annotate the type (`var d: Dictionary = ...`, `var f: float = ...`, cast `(x as Duelist)`).

## What is ALREADY DONE (do not redo)
1. True FPS lean: gun tilts around front-sight tip, character silhouette tilts, camera horizon stays level, lean works from prone, `LEAN ADS` (auto-aim) + `ADS LOOK`/`LEAN LOOK` drag-look settings. Protocol 7 for lean.
2. 120 Hz targets in `project.godot` (`run/max_fps=120`, `display/window/ios/enable_high_refresh_rate`, `physics/common/physics_ticks_per_second=120`).
3. New authoritative controller `scripts/riftline_match.gd` (class `RiftlineMatch`) with `GameMode { DEATHMATCH, BOMB }`, kill scoring + enemy-aware safe respawn (`_pick_safe_spawn`), and bomb plant/defuse/fuse/round-win/side-swap. Verified by `tools/riftline_modes_exercise.gd` (PASSES).
4. Arena (`scripts/riftline_arena.gd`) rewired to `RiftlineMatch` (var `director`, `_game_mode`); seed removed from the live flow; LAN/dedicated paths send a continuous `interact` bool (protocol 8) used for plant/defuse via `director.set_interact(...)`.
5. HUD (`scripts/duel_hud.gd`) objective strip is mode-aware (numeric scores + bomb glyph), phase typed to `RiftlineMatch.Phase`, carrier chevron removed.
6. Mode selector added to `scripts/riftline_practice_panel.gd` (DEATHMATCH / BOMB buttons, `mode_requested` signal) and `--mode=bomb|deathmatch` CLI in the arena. Arena handles `mode_requested` by rebuilding the offline match.
7. Everything COMPILES clean and offline deathmatch + bomb run headless without runtime errors.

## REMAINING WORK, in order

### Step 1 — delete obsolete seed code + exercises
Delete these files (they are unused now): `scripts/rift_seed.gd`, `scripts/linebreak_match.gd`, `scripts/riftline_squad_tactics.gd`, `scripts/match_director.gd`, and exercises `tools/linebreak_rules_exercise.gd`, `tools/riftline_seed_relay_exercise.gd`, `tools/riftline_bot_relay_exercise.gd`, `tools/riftline_squad_tactics_exercise.gd`. ALSO delete their `.uid` sidecar files if present.
Before deleting, you MUST clean these live references or the build breaks:
- `scripts/riftline_first_match_coach.gd:44` uses `RiftSeed.State.CARRIED` — replace the seed-cue logic with a no-op or a mode-neutral cue (the coach's `observe_objective`/`observe_delivery` are no longer called by the arena; you may delete those methods and `Step.SEED`).
- `scripts/bot_duelist.gd` lines ~68,74 (`RiftlineSquadTactics.INTENT_RELAY_SUPPORT`, `RiftSeed.RELAY_RANGE`), ~186,202 (`_linebreak_seed_state`, `RiftSeed.State`): remove seed-driven movement/targeting so bots simply fight (keep the combat AI). Delete `set_linebreak_context`/`set_squad_context`/`seed_relay_aim_direction` if unreferenced after.
- `scripts/riftline_map.gd`: keep spawn/gate geometry; `seed_position()`, `pulse_objective()`, and seed anchors in `tactical_facts()` may stay (arena still calls `seed_position()` as a fallback in `_bomb_site_points`) OR be trimmed carefully.
- `scripts/duel_hud.gd`: `_draw_seed_glyph` is now unused — delete it. Keep `set_seed_relay_available` (arena uses it as the plant/defuse use-button gate).
After cleanup run the compile check; it must be clean.

### Step 2 — propagate mode over LAN (host -> clients)
Add a `mode` field end to end so a joining client matches the host:
- `scripts/riftline_network.gd`: parse `--mode=` like `--team-size` (see `_read_command_line_options`), expose `var mode`, include `mode` in the session descriptor + `public_state`/`_validated_lobby_state` whitelist.
- `scripts/riftline_arena.gd`: on `_on_session_descriptor`/lobby state, set `_game_mode` before `_replace_match_for_lan`. Bump `PROTOCOL_VERSION` if you change the wire shape.
Verify with a host+join LAN smoke (below).

### Step 3 — full verification of modes
- Run ALL exercises in `tools/` (loop over `*_exercise.gd`) — every one must PASS. Remove any that now fail only because they test deleted seed behavior.
- LAN smoke: run host `-- --lan-host --team-size=3 --lobby-auto-ready` and a joiner `-- --lan-join=127.0.0.1 --lobby-auto-ready` for ~13s; only the pre-existing ENet MTU warning is acceptable.
- Capture deathmatch + bomb HUD (`--mode=` + a capture) and READ the PNGs to confirm the objective strip shows scores / bomb glyph.

### Step 4 — broad model / texture / animation pass (procedural only)
Stay in the procedural style. Concrete, bounded tasks:
- Character silhouette: add articulated arms/legs and a head that visibly leans/strafes (drive from `lean` + lateral velocity already present in `duelist.gd` `_process`).
- First-person gun: add a reload animation (magazine dip/rotate) and a plant/defuse hand animation keyed to the `interact` hold progress.
- Textures: enrich `shaders/pulp_lit.gdshader` with 1-2 more procedural layers (e.g. edge wear / noise breakup) via new uniforms; do NOT import image textures.
- Bomb: give the planted bomb a visible model + blinking light at `bomb_position` (arena presentation), and site markers (A/B) so players find sites.
Verify each with a capture and READ the PNG.

### Step 5 — devlog + deploy
- Append a section to `Riftline/devlogs/` (use the current date file, e.g. `2026-08-05.md`) in the existing terse style describing: mode swap (deathmatch+bomb), seed removal, LAN mode propagation, and the art pass.
- Deploy to BOTH devices with the deploy commands above; confirm `iPhone OK` / `iPad OK`.

## Definition of done
- Compile check clean; all exercises PASS; LAN smoke clean; deathmatch + bomb playable offline and over LAN; captures inspected; devlog updated; both devices deployed.
