# NEXT SESSION - Weapons, accuracy model, and class loadouts

Bootstrap file for a `/sonnet-opus` session.
Read this fully before doing anything else, then read `handoffs/HANDOFF.md` for the standing project constraints (art direction, renderer, tooling commands).

## Suggested prompt to paste after `/sonnet-opus`

> Implement the weapon and loadout redesign recorded in `handoffs/NEXT-SESSION-weapons-and-loadouts.md`.
> Remove iron sights and the knife entirely - melee becomes swinging whatever weapon is currently equipped.
> Rebuild ADS/hipfire accuracy for stationary, moving, jumping, and crouching, with and without ADS.
> Replace the current single generic M4 with five real weapons: an assault rifle, an MP7-style SMG, an S1897-style shotgun, a 9mm-or-.45-class pistol (not a revolver or Desert Eagle), and a sniper rifle with Halo-Infinite-style scope magnification and ADS time and no ADS drift.
> Rebuild the 2-slot loadout system into four classes: frontline (AR/SMG/shotgun + pistol), sniper (sniper + pistol), runner (pistol only, wears the nuclear vest), shield (pistol only, carries the ballistic shield).
> Read the handoff doc fully first - it has the resolved constraints and the open questions you need to settle before writing code. This is a large, long-lived gameplay contract (accuracy model, weapon data shape, loadout rules); consult `opus-advisor` before finalizing the accuracy-state design and the weapon data schema, per the sonnet-opus skill's own criteria.

## Why this exists

The user wants weapons "next" after multiplayer hardening and the three bug fixes (reconnect grace period, continuous health bar, damage falloff/range, bullet visuals - all done in the session that wrote this file, see `devlogs/2026-08-07.md`).
This is a large enough body of work - a new accuracy model, five new weapons, and a loadout/class rebuild - that it did not fit in the same session and was deliberately deferred rather than rushed.

## Resolved constraints (do not re-litigate these)

- **Iron sights are gone.** Every weapon ADS's through some form of optic/scope presentation, not a mechanical iron sight. (`ads_iron_sight_tip_head_offset()` and related iron-sight-tip code in `duelist.gd` need to go or be renamed/repurposed - check every caller.)
- **The knife is gone.** There is no dedicated melee weapon. Melee is always "swing whatever is in your current slot" - the currently equipped AR/SMG/shotgun/pistol/sniper is the melee weapon, presumably with per-weapon-class melee range/damage/animation rather than one universal knife swing. `KNIFE_DAMAGE`, `KNIFE_COOLDOWN`, `Weapon.KNIFE`, and the `knife_strike`/`knife_struck` signal chain (`duelist.gd`, `rift_ballistics.gd`, `riftline_combat_feedback.gd`, `riftline_arena.gd`) all need to be reworked around this, not just renamed.
- **Five weapons, real-world archetypes, not fantasy names for the model/visual reference only** (the actual in-game names can stay Riftline-flavored if that fits the sci-fi direction the art session will set - that naming decision belongs to this session or the art session, not predetermined here):
  - Assault rifle (replaces the current generic M4/PULSE weapon)
  - SMG, MP7-reference
  - Shotgun, S1897-reference
  - Pistol, 9mm-or-.45-reference - explicitly not a revolver or Desert Eagle/hand-cannon
  - Sniper rifle, Halo Infinite sniper reference for scope magnification and ADS time specifically
- **Sniper has no ADS drift/sway.** Several competitive shooters add a slight reticle drift while scoped; this game explicitly should not.
- **Four classes, two slots, both slots always drawn from {AR, SMG, shotgun, pistol, sniper, nuclear core if carrying}:**
  - **Frontline**: slot 1 = AR or SMG or shotgun (player choice), slot 2 = pistol
  - **Sniper**: slot 1 = sniper, slot 2 = pistol
  - **Runner**: one slot only = pistol. Wears the nuclear vest. Carrying the core costs a slight speed reduction either way (see Nuclear Rush rules in `handoffs/HANDOFF.md`), but the vest means the runner does not also take the constant carrier damage that everyone else takes while carrying the core.
  - **Shield**: one slot only = pistol. Carries a ballistic shield (Rainbow Six Siege Montagne reference - a moveable frontal shield, not a deployable).
- **Carrying the nuclear core without the vest costs constant damage over time**, in addition to the existing 0.82x speed penalty recorded in `handoffs/HANDOFF.md`. The vest (runner-only) removes the damage, not the speed penalty. This is new - the current `carrying_core` implementation in `duelist.gd` only applies the speed multiplier; find it and confirm before adding the damage-over-time.
- **Accuracy varies by stance, movement, and ADS**, at minimum for: hipfire stationary, hipfire moving, hipfire jumping, hipfire crouching, ADS stationary, ADS moving, ADS jumping, ADS crouching. Exact numbers are this session's job to design (a per-weapon spread/cone-angle table is the likely shape, informed by the existing hip-burst dispersion system in `duelist.gd` - `HIP_BURST_MAX_INDEX`, `HIP_BURST_RESET_SECONDS`, `_accept_shot_plan()` - which already has some of this machinery for the one existing weapon).

## Open questions this session must resolve (ask the user, or make and record a defensible call)

- Exact damage, fire rate, magazine size, reload time, and range-falloff curve per weapon (the falloff *pattern* fixed this session - linear near/far damage with a floor, see `rift_ballistics.gd` - is a reasonable template to extend per-weapon, not a fixed law).
- Whether melee-with-current-weapon has one universal damage/range/speed regardless of held weapon, or varies per weapon class (a shotgun butt-stroke vs. a pistol pistol-whip vs. a sniper's long melee reach are all plausible design choices with real gameplay consequences).
- Whether the shield blocks all frontal damage, partial damage, or damage above some caliber, and whether it degrades/breaks.
- Exact scope magnification steps and ADS time for the sniper (Halo Infinite is the named reference - look up its actual numbers rather than guessing, or ask the user for their felt preference if precision matters more than the exact citation).
- Whether switching between the two loadout slots keeps the old per-weapon reload/ammo state (almost certainly yes, matching how `magazine_rounds`/`reserve_ammo` already work per-duelist rather than per-weapon-instance today - check whether that needs to become per-weapon-slot).

## Files you will almost certainly touch

`scripts/duelist.gd` (weapon enum, ADS/iron-sight code, melee, loadout slots, carrying-core damage), `scripts/rift_ballistics.gd` (currently single-weapon; needs to become data-driven across five weapons), `scripts/riftline_arena.gd` (weapon presentation, HUD wiring, ballistics preview harness), `scripts/duel_hud.gd` (ammo/weapon HUD), `scripts/riftline_combat_feedback.gd` (per-weapon fire/impact/melee feedback), `scripts/riftline_roster.gd`/`riftline_lobby.gd` if class selection needs to be part of admission, and probably a new `scripts/rift_weapons.gd` or similar data table rather than cramming five weapons' worth of constants into `rift_ballistics.gd`.

Also touches (lightly, per the user's explicit ask - "lightly on the model side") whatever placeholder mesh-building code stands in for weapon visuals today (`_box`/`_box_mesh` calls in `duelist.gd`/`riftline_arena.gd`) - keep this to shape/silhouette differentiation between the five weapons, not final art. Full weapon art is the art/UI redesign session's job (`handoffs/NEXT-SESSION-art-ui-redesign.md`), which should run **after** this one - see the sequencing note in `handoffs/HANDOFF.md`.

## Validation

Extend `tools/rift_ballistics_exercise.gd` (or split per-weapon) and `tools/riftline_weapon_mobility_exercise.gd` to cover all five weapons and every accuracy state combination you add. Every existing exercise must keep passing - run the full suite (`handoffs/HANDOFF.md` has the exact headless commands) before calling this done.
