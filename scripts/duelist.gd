class_name Duelist
extends CharacterBody3D

const PULP_LIT := preload("res://shaders/pulp_lit.gdshader")
const BALLISTICS := preload("res://scripts/rift_ballistics.gd")
const CHARACTER_MODEL: PackedScene = preload("res://assets/characters/riftline_duelist_lowpoly.glb")

signal defeated(victim: Duelist, killer: Duelist)
signal fire_requested(shooter: Duelist, weapon: Weapon, origin: Vector3, direction: Vector3)
signal melee_strike(shooter_id: String, weapon: Weapon, origin: Vector3, end: Vector3, team: Team, hit_target: bool, target_id: String)
signal damaged(amount: float, remaining: float, attacker_id: String, source_position: Vector3, enemy_team: int)

enum Team { RED, BLUE }
enum Stance { STAND, CROUCH, PRONE }
## Five real-world archetypes. Ordinals line up 1:1 with RiftWeapons' RIFLE/
## SMG/SHOTGUN/PISTOL/SNIPER int constants - do not reorder one without the
## other. There is no dedicated melee weapon: melee always swings whichever
## of these is currently equipped.
enum Weapon { RIFLE, SMG, SHOTGUN, PISTOL, SNIPER }
## Four classes, two loadout slots at most. Both slots are always drawn from
## {RIFLE, SMG, SHOTGUN, PISTOL, SNIPER}; the nuclear vest and ballistic
## shield are class equipment, not weapons, and never occupy a slot.
enum PlayerClass { FRONTLINE, SNIPER, RUNNER, SHIELD }

const HEALTH := 100.0
const WALK_SPEED := 7.2
const DEFAULT_HORIZONTAL_FOV := 80.0
const MIN_HORIZONTAL_FOV := 70.0
const MAX_HORIZONTAL_FOV := 90.0
const FIRST_PERSON_WEAPON_SCALE := 0.38
# Where the view model rests when not aiming. The old value sat the weapon so
# low that only a black sliver of it was ever on screen; this puts roughly the
# top third of the receiver in frame, bottom-right, the way a first-person
# shooter actually reads. `physical_muzzle_position()` deliberately keeps its
# own gameplay-side offset - it is an obstruction probe, not a render position.
const FIRST_PERSON_HIP_ANCHOR := Vector3(0.33, -0.20, -0.95)
# Resting cant/yaw of the weapon at the hip, carried by `_weapon_rig` rather
# than `_weapon_root` so the recoil/obstruction/melee rotations that already
# drive the root are not fighting it. It resolves to zero at full ADS, which is
# what keeps the optic exactly on the camera's aim ray.
const FIRST_PERSON_HIP_RIG_ROTATION := Vector3(-0.030, 0.075, 0.055)
# Recoil used to be rotation-only (`_weapon_root.rotation.x/y`), which reads as
# the camera nodding rather than the weapon itself kicking. This is the linear
# throw added on top of that rotation, carried by `_weapon_rig.position` -
# which nothing else ever writes to - so it is a pure decay with no other
# consumer to fight, exactly like the existing rotation.x recoil term below.
const RECOIL_POSITION_UP := 0.048
const RECOIL_POSITION_BACK := 0.190
# Shield class only. Reference (Siege-style shield operator) shows the aimed
# revolver in a completely ordinary, centered sight picture - the "gun above
# the shield" read comes from the shield dropping out of the way underneath
# it, not from the gun being pushed out to one side. So this is simply the
# PISTOL row's own anchor: `ads_anchor.y + optic_tip_local.y * SCALE == 0` is
# what puts a sight on the aim ray, and the revolver's notch sights are built
# on the same `optic_tip_local` the Sidearm 9 uses. Keeping the value here
# rather than falling through to the generic branch leaves the shield class a
# single obvious place to retune its framing.
const SHIELD_ADS_WEAPON_ANCHOR := Vector3(0.0, -0.06460, -0.62)
# The shield's default carry: a tall plate held out in front, slightly to the
# left and turned just enough to show its face rather than its edge, with the
# vision port near the middle of the view. This is also the forced pose during
# a reload.
const SHIELD_VERTICAL_POSITION := Vector3(-0.22, -0.28, -0.66)
const SHIELD_VERTICAL_ROTATION := Vector3(0.05, 0.62, -0.09)
# ADS pose. The plate does not spin in the picture plane - it *pitches*, the
# way a visor or a car hood tips open: the carrier twists the wrist forward,
# the top edge falls away from him, and the wall of steel becomes a low
# horizontal parapet lying along the bottom of the screen that he shoots over.
# So the ADS transform is a rotation about the camera's own right axis,
# pre-multiplied onto the vertical basis so the parapet stays level on screen
# regardless of the yaw already baked into the carry pose, plus a drop in
# position to park it at the bottom edge of the frame. Lerping the raw Euler
# triple doesn't compose correctly once X/Y are already non-zero, which is why
# this isn't a second Vector3.
const SHIELD_HORIZONTAL_POSITION := Vector3(0.01, -0.225, -0.66)
const SHIELD_ADS_PITCH_ANGLE := -PI * 0.5
# Weapon-root pose while a Shield-class reload plays: tucked in close and low
# so it sits visually behind/below the vertical shield plate rather than out
# at the usual hip or ADS anchor.
const SHIELD_RELOAD_WEAPON_POSITION := Vector3(-0.02, -0.34, -0.30)
# The view model lives alone on render layer 2, so it can carry its own key and
# fill lights without touching a single watt of the arena's lighting. Without
# them the weapon is lit only by a world-space sun and goes to pure black
# whenever the player faces away from it.
const VIEW_MODEL_LAYER_MASK := 2
# `ads_progress` at which the sniper hands the view over from the 3D rifle to
# the HUD's scope picture. `DuelHud` closes its vignette to full opacity on the
# same value - the two must stay in step or the swap becomes visible.
const SNIPER_SCOPE_HANDOVER := 0.42
# One universal swap lockout keeps slot-swapping from becoming a free
# fire-rate exploit (e.g. swapping away from a sniper mid-cycle to reset it).
const WEAPON_SWAP_LOCKOUT := 0.35
const GRAVITY := 26.0
const JUMP_SPEED := 9.3
# Carrying the nuclear core is the mode's central risk: slow enough that a
# carrier needs escorts, not so slow that reaching your own base is hopeless.
const CORE_CARRY_SPEED_MULTIPLIER := 0.82
# A shot is airborne when the restored (snapshotted) vertical velocity is
# clearly off the ground plate. Grounded velocity.y is pinned to -0.1 by
# _simulate_motion, so this threshold is unambiguous and - unlike
# is_on_floor() - is derived purely from state that reconcile restores.
const AIRBORNE_VELOCITY_Y := 0.75

const CLASS_LOADOUTS := {
	PlayerClass.FRONTLINE: {"slot_count": 2, "primary_choices": [Weapon.RIFLE, Weapon.SMG, Weapon.SHOTGUN], "vest": false, "shield": false},
	PlayerClass.SNIPER: {"slot_count": 2, "primary_choices": [Weapon.SNIPER], "vest": false, "shield": false},
	PlayerClass.RUNNER: {"slot_count": 1, "primary_choices": [Weapon.PISTOL], "vest": true, "shield": false},
	PlayerClass.SHIELD: {"slot_count": 1, "primary_choices": [Weapon.PISTOL], "vest": false, "shield": true},
}

## Grip and support-hand poses in `_weapon_rig` space, tuned per weapon
## silhouette against the existing part positions in each `_build_*_model()`
## so the gloves land on the actual grip/foregrip rather than floating beside
## the model. Not used by the Shield class - see `_rebuild_first_person_shield()`,
## whose left hand grips the shield handle instead, and its right hand still
## reads this table for the revolver.
##
## Both rotations are dictated by `_build_glove_hand()`'s origin convention
## (grip axis along the glove's local X, forearm out its +Z) and so reduce to
## one meaningful number each rather than three tuned-by-eye Euler terms:
##
##   grip_rot    = Vector3(<the grip column's own rotation.x>, 0, -PI/2)
##                 - the quarter turn stands the glove's wrap axis up along a
##                   pistol grip, the first term matches that grip's rake, so
##                   the fist tracks the grip if the grip is ever re-raked.
##   support_rot = Vector3(<roll around the barrel>, -PI/2, 0)
##                 - the quarter turn lays the wrap axis down the handguard,
##                   the first term is purely how far round the tube the hand
##                   is rotated, which is the only free choice there is.
##
## The shotgun has no pistol grip, so its trigger hand wraps the small of the
## stock instead and takes a positive (rearward) rake; that is the one entry
## whose first term is not copied from a grip block.
##
## The pistol is the one weapon whose support hand is a second *pistol-grip*
## hand rather than a handguard hand, so it is the only entry that does not
## follow the `support_rot` rule above. It takes the trigger hand's own quarter
## turn with the opposite sign - a genuinely mirrored glove (see
## `PISTOL_SUPPORT_MIRRORED` and `_mirror_node_x()`) has its thumb on the
## opposite side, so +PI/2 is what puts that thumb back up at the top of the
## grip and lays the back of the hand out to the left. The middle term is a
## pure rotation *around* the vertical grip axis - Y survives an Euler-Y
## rotation untouched - so it is the free choice here: how far round the grip
## the off hand sits, and therefore how far to the left its forearm exits.
const HAND_GRIP_POSE := {
	Weapon.RIFLE:   {"grip": Vector3(0.0, -0.118, 0.122), "grip_rot": Vector3(-0.36, 0.0, -PI * 0.5), "support": Vector3(0.0, 0.052, -0.700), "support_rot": Vector3(1.05, -PI * 0.5, 0.0)},
	Weapon.SMG:     {"grip": Vector3(0.0, -0.096, 0.052), "grip_rot": Vector3(-0.19, 0.0, -PI * 0.5), "support": Vector3(0.0, 0.026, -0.545), "support_rot": Vector3(1.05, -PI * 0.5, 0.0)},
	Weapon.SHOTGUN: {"grip": Vector3(0.0, -0.046, 0.170), "grip_rot": Vector3(0.42, 0.0, -PI * 0.5), "support": Vector3(0.0, -0.014, -0.460), "support_rot": Vector3(1.05, -PI * 0.5, 0.0)},
	Weapon.PISTOL:  {"grip": Vector3(0.0, -0.104, 0.096), "grip_rot": Vector3(-0.28, 0.0, -PI * 0.5), "support": Vector3(-0.060, -0.108, 0.028), "support_rot": Vector3(-0.28, -0.78, PI * 0.5)},
	Weapon.SNIPER:  {"grip": Vector3(0.0, -0.134, 0.284), "grip_rot": Vector3(-0.32, 0.0, -PI * 0.5), "support": Vector3(0.0, 0.038, -0.680), "support_rot": Vector3(1.05, -PI * 0.5, 0.0)},
}

## Which weapons get a genuinely mirrored (left) support glove.
##
## Only the pistol. Chirality is not free to change per weapon: the glove's
## thumb sits on its local -X, which for the four long guns' `support_rot`
## resolves to the muzzle direction - i.e. the unmirrored glove already has its
## thumb pointing forward down the handguard, which is what a left hand does
## there. Mirroring those would swing the thumb *rearward* and make four
## currently-correct hands wrong. The pistol's support hand wraps a vertical
## grip instead, where the thumb sits at the top of the grip on either hand, so
## the mirror is both free and necessary: there the two gloves are inches apart
## and unobstructed, and two identical right hands read immediately as a bug.
const PISTOL_SUPPORT_MIRRORED := true

## `ads_progress` below which the pistol's support hand is not on the gun at
## all, and the offset it waits at while it is away.
##
## A pistol is a one-handed weapon at the hip and a two-handed weapon on the
## sights, so the off hand is not merely parked out of frame - it is gone, and
## it comes back on the aim. The offset takes it down and out to the lower left
## so the return reads as a hand travelling to the gun rather than a hand
## fading up on top of it; the dead zone keeps a twitch of the aim button from
## flickering a whole arm across the bottom of the frame.
const PISTOL_SUPPORT_JOIN_START := 0.16
const PISTOL_SUPPORT_APPROACH := Vector3(-0.26, -0.34, 0.16)
## Folded-away scale for that hand. Small enough to be nothing behind an
## already-cleared `visible`, but never exactly zero: a zero-determinant basis
## is what makes Godot start logging degenerate-transform errors every frame.
const PISTOL_SUPPORT_FOLDED_SCALE := 0.001

var team: Team = Team.RED
var actor_id := ""
var health := HEALTH
var eliminated := false
var carrying_core := false
var stance: Stance = Stance.STAND
var player_class: PlayerClass = PlayerClass.FRONTLINE
var loadout_slots: Array = [Weapon.RIFLE, Weapon.PISTOL]
var active_slot := 0
var has_nuclear_vest := false
var has_ballistic_shield := false
var weapon: Weapon = Weapon.RIFLE
var horizontal_fov := DEFAULT_HORIZONTAL_FOV
var _last_camera_aspect := -1.0
var magazine_rounds := 0
var reserve_ammo := 0
var _slot_magazine: Array = []
var _slot_reserve: Array = []
var reload_remaining := 0.0
var interact_progress := 0.0
var match_active := false
var _fire_remaining := 0.0
var _melee_remaining := 0.0
var _melee_swing_remaining := 0.0
# Accuracy-state trio. All three are pure functions of replayed state and are
# part of authoritative_state()/apply_presentation_state() - if either side
# forgets one, client-predicted shots silently disagree with the server about
# where they went. See RiftWeapons.cone_for().
var bloom := 0.0
var shot_counter := 0
var ads_progress := 0.0
var zoom_index := 0
var _pending_authoritative_shot_plan: Dictionary = {}
var last_shot_was_hip_followup := false
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _torso: Node3D
var _band: MeshInstance3D
var _body_visual_root: Node3D
var _body_visual_target_scale_y := 1.0
var _torso_rest_position := Vector3.ZERO
var _torso_rest_rotation := Vector3.ZERO
var _model_head: Node3D
var _model_head_rest_rotation := Vector3.ZERO
var _left_leg_rest_rotation := Vector3.ZERO
var _right_leg_rest_rotation := Vector3.ZERO
var _left_arm_rest_rotation := Vector3.ZERO
var _right_arm_rest_rotation := Vector3.ZERO
var _weapon_root: Node3D
## Static resting pose of the weapon inside `_weapon_root`. The root itself is
## already animated every frame (ADS anchor, recoil, obstruction, melee, swap),
## so the hip cant needs its own node or the two overwrite each other.
var _weapon_rig: Node3D
var _fp_shield_root: Node3D
var _weapon_mesh: MeshInstance3D
var _weapon_core: MeshInstance3D
var _muzzle_flare: MeshInstance3D
var _rail_slots: Array[MeshInstance3D] = []
var _signal_spine: MeshInstance3D
var _survey_frame: MeshInstance3D
var _friendly_pennant: MeshInstance3D
var _shield_plate: MeshInstance3D
## Blended 0..1: 0 is the shield carried vertically (default, and forced
## during reload), 1 is rolled flat horizontal for the Shield class's ADS.
## See `SHIELD_VERTICAL_*`/`SHIELD_HORIZONTAL_*` and `_process()`.
var _shield_horizontal_t := 0.0
var _muzzle_light: OmniLight3D
var _left_hand_root: Node3D
var _right_hand_root: Node3D
## Rest pose of the support hand before reload's mag-out/mag-in hump is added
## on top of it. Recorded at build time so `_process` doesn't need to look the
## per-weapon pose table up every frame.
var _hand_support_rest := Vector3.ZERO
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _pose_distance := 0.0
var _aiming := false
var _recoil_remaining := 0.0
var _fire_flash_remaining := 0.0
var _damage_flash_remaining := 0.0
var _flinch_remaining := 0.0
var _obstruction_remaining := 0.0
var _swap_motion := 0.0
var _recoil_kick := 0.0
var _recoil_lateral := 0.0
var _magazine_mesh: MeshInstance3D
var _carrier_signal_root: Node3D
var _local_camera := false
var _render_visuals := true
var _authoritative_collision := true
var _pending_jump := false
var _death_visual_elapsed := 0.0
var _death_visual_hidden := false

const DEATH_VISUAL_HOLD_SECONDS := 1.8
const DEATH_VISUAL_FADE_SECONDS := 0.7

var head: Node3D
var camera: Camera3D

func build(assigned_team: Team, local_camera: bool, render_visuals: bool = true, authoritative_collision: bool = true) -> void:
	team = assigned_team
	add_to_group("riftline_duelists")
	_local_camera = local_camera
	_render_visuals = render_visuals
	_authoritative_collision = authoritative_collision
	collision_layer = 2 if authoritative_collision else 0
	collision_mask = 1 | 2

	_collision = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.48
	_capsule.height = 1.8
	_collision.shape = _capsule
	_collision.position.y = 0.9
	add_child(_collision)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.46, 0.0)
	add_child(head)

	if local_camera and _render_visuals:
		camera = Camera3D.new()
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_last_camera_aspect = _viewport_aspect()
		camera.fov = _vertical_fov_for_horizontal(horizontal_fov, _last_camera_aspect)
		# World silhouettes live on layer 1; the local view model gets its own layer so it never leaks to another client.
		camera.cull_mask = 1 | 2
		camera.current = true
		head.add_child(camera)

	configure_loadout(player_class, loadout_slots[0] as Weapon)

	if _render_visuals:
		if local_camera:
			_build_first_person_weapon()
		else:
			_build_character_silhouette()
			_build_world_weapon()
		_rebuild_weapon_models()

func set_horizontal_fov(value: float) -> void:
	var next := clampf(value, MIN_HORIZONTAL_FOV, MAX_HORIZONTAL_FOV) if is_finite(value) else DEFAULT_HORIZONTAL_FOV
	horizontal_fov = next
	_update_camera_projection()

func _viewport_aspect() -> float:
	if get_viewport() == null or get_viewport().size.x <= 0 or get_viewport().size.y <= 0:
		return 1280.0 / 588.0
	return float(get_viewport().size.x) / float(get_viewport().size.y)

static func vertical_fov_for_horizontal(horizontal_degrees: float, aspect: float) -> float:
	var safe_horizontal := horizontal_degrees if is_finite(horizontal_degrees) else DEFAULT_HORIZONTAL_FOV
	var safe_aspect := aspect if is_finite(aspect) and aspect > 0.01 else 1280.0 / 588.0
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(safe_horizontal) * 0.5) / safe_aspect))

## Resolves a player's class into concrete loadout slots. `primary_choice` is
## only meaningful for Frontline (AR/SMG/shotgun); every other class has
## exactly one legal primary and ignores an out-of-set request.
func configure_loadout(next_class: PlayerClass, primary_choice: Weapon = Weapon.RIFLE) -> void:
	player_class = next_class
	var facts: Dictionary = CLASS_LOADOUTS[int(player_class)]
	var choices: Array = facts.primary_choices
	var primary: int = int(primary_choice) if choices.has(int(primary_choice)) else int(choices[0])
	loadout_slots = [primary] if int(facts.slot_count) == 1 else [primary, int(Weapon.PISTOL)]
	has_nuclear_vest = bool(facts.vest)
	has_ballistic_shield = bool(facts.shield)
	active_slot = 0
	zoom_index = 0
	_resolve_loadout_ammo()
	weapon = RiftWeapons.clamp_weapon(loadout_slots[0]) as Weapon
	if _render_visuals:
		_rebuild_weapon_models()

func _resolve_loadout_ammo() -> void:
	_slot_magazine.resize(loadout_slots.size())
	_slot_reserve.resize(loadout_slots.size())
	for i in loadout_slots.size():
		var row := RiftWeapons.row(int(loadout_slots[i]))
		_slot_magazine[i] = int(row.magazine_size)
		_slot_reserve[i] = int(row.reserve_ammo)
	magazine_rounds = int(_slot_magazine[active_slot])
	reserve_ammo = int(_slot_reserve[active_slot])

static func mobility_facts(value: Weapon) -> Dictionary:
	return RiftWeapons.row(RiftWeapons.clamp_weapon(int(value)))

static func standing_speed_profile(value: Weapon, aiming: bool = false) -> Dictionary:
	var facts := mobility_facts(value)
	var forward := WALK_SPEED * float(facts.get("hip_forward", 1.0))
	var lateral := forward * float(facts.get("hip_strafe", 0.76))
	if aiming:
		var scale := float(facts.get("ads_move_scale", 0.82))
		forward *= scale
		lateral *= scale
	return {"forward": forward, "lateral": lateral}

func _vertical_fov_for_horizontal(horizontal_degrees: float, aspect: float) -> float:
	return vertical_fov_for_horizontal(horizontal_degrees, aspect)

func _update_camera_projection() -> void:
	if camera == null:
		return
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var target_horizontal := RiftWeapons.ads_horizontal_fov(horizontal_fov, int(weapon), zoom_index) if _aiming else horizontal_fov
	camera.fov = _vertical_fov_for_horizontal(target_horizontal, _viewport_aspect())

func set_actor_id(next_actor_id: String) -> void:
	actor_id = next_actor_id

func set_friendly_presenter(friendly: bool) -> void:
	if not _render_visuals or _local_camera or not friendly or _friendly_pennant != null:
		return
	_friendly_pennant = MeshInstance3D.new()
	var pennant_mesh := BoxMesh.new()
	pennant_mesh.size = Vector3(0.22, 0.12, 0.035)
	_friendly_pennant.mesh = pennant_mesh
	_friendly_pennant.position = Vector3(-0.4, 1.42, 0.05)
	_friendly_pennant.material_override = _material(_team_glow(), 0.42)
	_friendly_pennant.layers = 1
	add_child(_friendly_pennant)

func set_carrying_core(carrying: bool) -> void:
	carrying_core = carrying and not eliminated

func is_carrying_core() -> bool:
	return carrying_core and not eliminated

func is_shield_class() -> bool:
	return player_class == PlayerClass.SHIELD

func movement_speed_multiplier() -> float:
	return CORE_CARRY_SPEED_MULTIPLIER if is_carrying_core() else 1.0

func _process(delta: float) -> void:
	if not _render_visuals:
		return
	_tick_death_presentation(delta)
	if _death_visual_hidden:
		return
	if _local_camera and camera != null:
		var current_aspect := _viewport_aspect()
		if _last_camera_aspect < 0.0 or absf(current_aspect - _last_camera_aspect) > 0.001:
			_last_camera_aspect = current_aspect
			_update_camera_projection()
	_pose_distance += Vector2(velocity.x, velocity.z).length() * delta
	_recoil_remaining = maxf(0.0, _recoil_remaining - delta)
	_fire_flash_remaining = maxf(0.0, _fire_flash_remaining - delta)
	_damage_flash_remaining = maxf(0.0, _damage_flash_remaining - delta)
	_flinch_remaining = maxf(0.0, _flinch_remaining - delta)
	_obstruction_remaining = maxf(0.0, _obstruction_remaining - delta)
	_swap_motion = maxf(0.0, _swap_motion - delta * 5.5)
	_melee_swing_remaining = maxf(0.0, _melee_swing_remaining - delta * 4.6)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.35
	var gait := sin(_pose_distance * 1.35) if moving else 0.0
	var gait_lag := cos(_pose_distance * 1.35) if moving else 0.0
	var airborne := clampf(velocity.y / JUMP_SPEED, -1.0, 1.0)
	var firing_pose := clampf(_recoil_remaining / 0.22, 0.0, 1.0)
	var flinch_pose := clampf(_flinch_remaining / 0.18, 0.0, 1.0)
	if _torso != null:
		_torso.position = _torso_rest_position + Vector3.UP * (absf(gait) * (0.018 if moving else 0.0))
		_torso.rotation = _torso_rest_rotation + Vector3(flinch_pose * -0.1, 0.0, gait_lag * (0.035 if moving else 0.0) + flinch_pose * 0.12)
	if _band != null:
		_band.scale = Vector3.ONE * (1.0 + (_damage_flash_remaining / 0.16) * 0.08)
	if _left_leg != null:
		_left_leg.rotation = _left_leg_rest_rotation + Vector3(gait * (0.17 if stance == Stance.STAND else 0.07), 0.0, 0.0)
	if _right_leg != null:
		_right_leg.rotation = _right_leg_rest_rotation + Vector3(-gait * (0.17 if stance == Stance.STAND else 0.07), 0.0, 0.0)
	if _left_arm != null:
		_left_arm.rotation = _left_arm_rest_rotation + Vector3(-gait * 0.09, 0.0, airborne * 0.08 - firing_pose * 0.05)
	if _right_arm != null:
		_right_arm.rotation = _right_arm_rest_rotation + Vector3(gait * 0.09, 0.0, -airborne * 0.08 + firing_pose * 0.05)
	if _model_head != null and head != null:
		_model_head.rotation = _model_head_rest_rotation + Vector3(head.rotation.x, 0.0, 0.0)
	if _survey_frame != null:
		_survey_frame.rotation.z = -gait_lag * 0.025
	if _weapon_root != null:
		var hip := FIRST_PERSON_HIP_ANCHOR
		var target := _ads_weapon_anchor() if _aiming and _local_camera else hip
		if _weapon_rig != null and _local_camera:
			# The resting cant has to unwind exactly as the weapon comes up, or
			# the optic no longer sits on the camera's aim ray at full ADS.
			_weapon_rig.rotation = FIRST_PERSON_HIP_RIG_ROTATION * (1.0 - clampf(ads_progress, 0.0, 1.0))
			# A telescopic sight cannot be looked *through* in a raster render:
			# the eye sits well behind the ocular, so the tube's far end always
			# projects as a small aperture ring parked over the crosshair. Every
			# shooter solves this the same way - once the scope picture has
			# taken over, the view model stops being drawn, and the HUD's tube
			# is the scope. The handover is timed to the moment the vignette
			# reaches full closure so there is nothing left to see it happen.
			_weapon_rig.visible = weapon != Weapon.SNIPER or ads_progress < SNIPER_SCOPE_HANDOVER
		if _local_camera:
			var breathing := sin(Time.get_ticks_msec() * 0.0017) * (0.004 if _aiming else 0.009)
			var walking := sin(_pose_distance * 1.35) if moving else 0.0
			target += Vector3(0.0, breathing + walking * (0.012 if not _aiming else 0.004), 0.0)
			if _obstruction_remaining > 0.0 or _local_muzzle_obstructed():
				target += Vector3(-0.12, 0.07, 0.22)
			var obstruction_tilt := 0.08 if _obstruction_remaining > 0.0 or _local_muzzle_obstructed() else 0.0
			_weapon_root.rotation.z = lerpf(_weapon_root.rotation.z, obstruction_tilt, clampf(delta * 18.0, 0.0, 1.0))
			if _swap_motion > 0.0:
				target += Vector3(0.0, -0.16 * sin(_swap_motion * PI), 0.18 * sin(_swap_motion * PI))
			if _melee_swing_remaining > 0.0:
				var swing := sin(_melee_swing_remaining * PI)
				target += Vector3(-0.16 * swing, -0.08 * swing, -0.34 * swing)
				_weapon_root.rotation.y = lerpf(_weapon_root.rotation.y, -0.6 * swing, clampf(delta * 26.0, 0.0, 1.0))
		var active_reload_seconds := maxf(0.05, float(RiftWeapons.row(int(weapon)).reload_seconds))
		var reload_phase := 0.0
		if reload_remaining > 0.0 and _local_camera:
			reload_phase = clampf(1.0 - reload_remaining / active_reload_seconds, 0.0, 1.0)
			if is_shield_class():
				# Reloads happen tucked in close behind the vertical shield rather
				# than out at the hip/ADS anchor - see `_fp_shield_root` below,
				# which is forced back to vertical for the same duration.
				target = SHIELD_RELOAD_WEAPON_POSITION
			else:
				target += Vector3(-0.04, -0.12 + sin(reload_phase * PI) * 0.06, 0.08)
		if interact_progress > 0.0 and _local_camera:
			var interact_arc := sin(interact_progress * PI)
			target += Vector3(-0.06, -0.18 * interact_arc, 0.22 * interact_arc)
			_weapon_root.rotation.x = lerpf(_weapon_root.rotation.x, -0.25 * interact_arc, clampf(delta * 12.0, 0.0, 1.0))
		_weapon_root.position = _weapon_root.position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))
		_recoil_kick = move_toward(_recoil_kick, 0.0, delta * 5.4)
		_recoil_lateral = move_toward(_recoil_lateral, 0.0, delta * 7.0)
		_weapon_root.rotation.x = lerpf(_weapon_root.rotation.x, -_recoil_kick, clampf(delta * 24.0, 0.0, 1.0))
		if _melee_swing_remaining <= 0.0:
			_weapon_root.rotation.y = lerpf(_weapon_root.rotation.y, _recoil_lateral, clampf(delta * 20.0, 0.0, 1.0))
		if _weapon_rig != null:
			# Linear recoil throw. `_weapon_rig.position` has no other writer, so
			# it can decay straight toward the kick amount every frame without
			# fighting the ADS/hip/sway/reload targets already driving
			# `_weapon_root.position` above - and because every weapon part, the
			# sight and the hands all hang off `_weapon_rig`, the whole assembly
			# (sight included) rides the kick together, hip or ADS alike.
			var recoil_offset := Vector3(0.0, RECOIL_POSITION_UP, RECOIL_POSITION_BACK) * _recoil_kick
			_weapon_rig.position = _weapon_rig.position.lerp(recoil_offset, clampf(delta * 22.0, 0.0, 1.0))
		if _magazine_mesh != null and reload_remaining > 0.0:
			_magazine_mesh.visible = reload_phase < 0.16 or reload_phase > 0.68
		# The Shield class's left glove is not a support hand at all - it is
		# welded to the shield's handle bar inside `_fp_shield_root` and rides
		# the plate's own motion. `_hand_support_rest` is a *weapon-rig* pose
		# and means nothing in shield space, so letting the branch below reach
		# it dragged the fist off the handle and out into the middle of the
		# frame, taking its whole forearm across the screen with it.
		if _left_hand_root != null and _local_camera and not is_shield_class():
			var support_rest := _hand_support_rest
			if weapon == Weapon.PISTOL:
				# A pistol is a one-handed weapon until the shooter actually aims
				# it, so its off hand is not merely parked out of frame the way the
				# long guns' never-moving support hand is - it is folded away
				# entirely and brought back on `ads_progress`. Scaling rather than
				# rebuilding is what makes that affordable: the aim button is tapped
				# constantly, and `_build_glove_hand()` is around a hundred mesh
				# parts to throw away and re-make every time it is.
				var join := clampf((clampf(ads_progress, 0.0, 1.0) - PISTOL_SUPPORT_JOIN_START) / maxf(0.01, 1.0 - PISTOL_SUPPORT_JOIN_START), 0.0, 1.0)
				join = join * join * (3.0 - 2.0 * join)
				# A reload is the other time the off hand is genuinely on the
				# weapon, aimed or not - somebody has to bring the magazine. It
				# rides the same sine hump the swing below and the magazine mesh
				# already share, steepened so the hand is fully there for the body
				# of the reload and only folds away at its two ends.
				join = maxf(join, clampf(sin(reload_phase * PI) * 2.4, 0.0, 1.0))
				# The mass arrives ahead of the travel - full size is reached at
				# roughly half the join - so what the eye reads is a hand moving
				# onto the gun rather than a hand inflating on top of it.
				_left_hand_root.visible = join > 0.004
				_left_hand_root.scale = Vector3.ONE * maxf(PISTOL_SUPPORT_FOLDED_SCALE, minf(1.0, join * 1.9))
				support_rest += PISTOL_SUPPORT_APPROACH * (1.0 - join)
			elif not _left_hand_root.visible:
				_left_hand_root.visible = true
			if reload_remaining > 0.0:
				# Support hand sweeps down to the magazine well and back up on a
				# single sine hump timed to the same reload_phase the magazine
				# mesh hides/shows on, rather than a second, unsynchronized clock.
				var mag_hump := sin(reload_phase * PI)
				_left_hand_root.position = support_rest + Vector3(-0.025, -0.20, 0.10) * mag_hump
			else:
				_left_hand_root.position = _left_hand_root.position.lerp(support_rest, clampf(delta * 12.0, 0.0, 1.0))
	if _fp_shield_root != null:
		# Vertical is the resting/reload pose; ADS pitches the plate forward and
		# down about the camera's right axis until it lies flat as a low
		# parapet across the bottom of the frame, and the revolver comes up to
		# an ordinary centered sight picture over it - see
		# SHIELD_ADS_PITCH_ANGLE and `_ads_weapon_anchor()` above.
		var shield_target_t := 0.0 if reload_remaining > 0.0 else clampf(ads_progress, 0.0, 1.0)
		_shield_horizontal_t = lerpf(_shield_horizontal_t, shield_target_t, clampf(delta * 9.0, 0.0, 1.0))
		var shield_pos := SHIELD_VERTICAL_POSITION.lerp(SHIELD_HORIZONTAL_POSITION, _shield_horizontal_t)
		# Pre-multiplying the pitch onto the vertical basis (rather than
		# lerping the Euler triple) rotates about the camera's own right axis,
		# so the top edge falls straight away from the viewer and the parapet
		# lands level on screen no matter how the carry pose has the plate
		# yawed to show its face instead of its edge.
		var shield_pitch := Basis(Vector3(1.0, 0.0, 0.0), SHIELD_ADS_PITCH_ANGLE * _shield_horizontal_t)
		var shield_basis := shield_pitch * Basis.from_euler(SHIELD_VERTICAL_ROTATION)
		if _melee_swing_remaining > 0.0:
			# Shield-bump melee: the plate itself lunges forward - the
			# Montagne-reference "hit them with the shield", not a weapon swing.
			var bump := sin(_melee_swing_remaining * PI)
			shield_pos += Vector3(0.0, -0.02 * bump, -0.46 * bump)
		_fp_shield_root.position = _fp_shield_root.position.lerp(shield_pos, clampf(delta * 12.0, 0.0, 1.0))
		_fp_shield_root.quaternion = _fp_shield_root.quaternion.slerp(shield_basis.get_rotation_quaternion(), clampf(delta * 12.0, 0.0, 1.0))
		if _left_hand_root != null:
			# The plate is tipped by the wrist, not by the whole arm. Left as a
			# rigid child of the shield the glove rotates bodily with it and
			# swings its forearm up and across the right of the screen, which
			# is the one thing that gives away that this is a prop bolted to
			# the camera. Rolling the glove back about its own X - the handle
			# bar's axis, so the fist stays wrapped around the bar and only
			# changes where round it the knuckles sit - holds the forearm
			# roughly still while the plate turns under it. Slightly less than
			# a full counter-roll, so some of the turn still carries into the
			# arm and it does not read as a detached hand.
			_left_hand_root.rotation.x = -SHIELD_ADS_PITCH_ANGLE * _shield_horizontal_t * 0.85
	if _muzzle_flare != null:
		var flare := clampf(_fire_flash_remaining / 0.075, 0.0, 1.0)
		_muzzle_flare.scale = Vector3.ONE * flare
	if _muzzle_light != null:
		_muzzle_light.light_energy = clampf(_fire_flash_remaining / 0.05, 0.0, 1.0) * 7.0
	if not _rail_slots.is_empty():
		var sequence := clampf((0.12 - _fire_flash_remaining) / 0.12 * 6.0, 0.0, 6.0)
		for index in _rail_slots.size():
			_set_material_glow(_rail_slots[index], 0.45 if index >= sequence else 1.2)
		_set_material_glow(_band, 1.35 if _damage_flash_remaining > 0.0 else 0.6)
	if _body_visual_root != null:
		_body_visual_root.scale.y = lerpf(_body_visual_root.scale.y, _body_visual_target_scale_y, clampf(delta * 10.0, 0.0, 1.0))
	if camera != null:
		var camera_stance_offset := -0.14 if stance == Stance.CROUCH else -0.28 if stance == Stance.PRONE else 0.0
		camera.position.y = lerpf(camera.position.y, camera_stance_offset, clampf(delta * 9.0, 0.0, 1.0))
		# The horizon always stays parallel to the ground; the camera never rolls.
		camera.rotation.z = 0.0
	if _body_visual_root != null:
		var powered_down := eliminated
		var strafe := 0.0
		if not powered_down:
			var local_velocity := global_transform.basis.orthonormalized().inverse() * velocity
			strafe = clampf(local_velocity.x / 6.0, -1.0, 1.0)
		var strafe_roll := 0.0 if powered_down else -strafe * 0.07
		_body_visual_root.rotation.z = lerpf(_body_visual_root.rotation.z, -0.92 if powered_down else strafe_roll, clampf(delta * (7.0 if powered_down else 9.0), 0.0, 1.0))
		_body_visual_root.position.x = lerpf(_body_visual_root.position.x, 0.0 if powered_down else strafe * 0.084, clampf(delta * 9.0, 0.0, 1.0))
		_body_visual_root.position.y = lerpf(_body_visual_root.position.y, -0.24 if powered_down else 0.0, clampf(delta * (7.0 if powered_down else 9.0), 0.0, 1.0))
	if _carrier_signal_root != null:
		_carrier_signal_root.visible = is_carrying_core()
		_carrier_signal_root.rotation.y += delta * 1.8
		_carrier_signal_root.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.06)

## `force` skips the "same weapon, don't bother" optimization. Presentation
## resets - respawn chief among them - need every view-model node rebuilt
## fresh even when the incoming weapon matches what was already equipped,
## because the fire/recoil/muzzle-flash state above (`_weapon_mesh`,
## `_muzzle_flare`, `_muzzle_light`, `_rail_slots`, ...) is exactly what a
## death cycle can leave in an inconsistent mid-effect state (see the
## respawn caller below).
func set_weapon_presentation(next_weapon: Weapon, force: bool = false) -> void:
	var clamped := RiftWeapons.clamp_weapon(int(next_weapon)) as Weapon
	if not force and weapon == clamped and _weapon_mesh != null:
		return
	weapon = clamped
	_recoil_remaining = 0.0
	_recoil_kick = 0.0
	_recoil_lateral = 0.0
	_fire_flash_remaining = 0.0
	_swap_motion = 1.0
	_rebuild_weapon_models()

func play_local_weapon_fire(fired_weapon: Weapon) -> void:
	_play_weapon_fire(fired_weapon)

func play_remote_weapon_fire(fired_weapon: Weapon) -> void:
	_play_weapon_fire(fired_weapon)

func _play_weapon_fire(fired_weapon: Weapon) -> void:
	if not _render_visuals:
		return
	if weapon != fired_weapon:
		set_weapon_presentation(fired_weapon)
	var row := RiftWeapons.row(int(fired_weapon))
	var punch := clampf(float(row.damage_near) / 45.0, 0.35, 1.35)
	_recoil_remaining = 0.12 + punch * 0.06
	_recoil_kick = 0.12 + punch * 0.10
	_recoil_lateral = (-0.035 if int(fired_weapon) % 2 == 0 else 0.04) * punch
	_fire_flash_remaining = 0.075 + punch * 0.03
	if _weapon_core != null:
		_set_material_glow(_weapon_core, 2.6 + punch * 2.6)
	if _muzzle_flare != null:
		_set_material_glow(_muzzle_flare, 4.0 + punch * 4.0)

func play_local_melee_swing() -> void:
	_melee_swing_remaining = 1.0

func apply_damage_presentation(_amount: float, _remaining: float) -> void:
	if not _render_visuals:
		return
	_damage_flash_remaining = 0.16
	_flinch_remaining = 0.18
	_set_material_glow(_band, 1.35)

func apply_look(delta: Vector2) -> void:
	if eliminated:
		return
	rotate_y(-delta.x * 0.006)
	head.rotation.x = clampf(head.rotation.x - delta.y * 0.006, -1.05, 0.9)

func set_match_active(active: bool) -> void:
	match_active = active
	if not active:
		velocity.x = 0.0
		velocity.z = 0.0
		_fire_remaining = 0.0
		_melee_remaining = 0.0
		reload_remaining = 0.0
		interact_progress = 0.0
		_pending_jump = false
		_pending_authoritative_shot_plan.clear()
		_obstruction_remaining = 0.0
		_swap_motion = 0.0
		_recoil_kick = 0.0
		_recoil_lateral = 0.0
		if _magazine_mesh != null:
			_magazine_mesh.visible = true

func set_interact_progress(value: float) -> void:
	interact_progress = clampf(value, 0.0, 1.0)

func make_input_frame(sequence: int, move_input: Vector2, aiming: bool, firing: bool, wants_jump: bool, crouch_edge: bool, prone_edge: bool, weapon_switch_edge: bool, reload_edge: bool, pass_seed_edge: bool = false, interact_held_value: bool = false, melee_edge: bool = false) -> Dictionary:
	return {
		"sequence": sequence,
		"move_x": clampf(move_input.x, -1.0, 1.0),
		"move_y": clampf(move_input.y, -1.0, 1.0),
		"yaw": rotation.y,
		"pitch": head.rotation.x if head != null else 0.0,
		"aim": aiming,
		"fire": firing,
		"jump": wants_jump,
		"crouch": crouch_edge,
		"prone": prone_edge,
		"weapon_switch": weapon_switch_edge,
		"reload": reload_edge,
		"pass_seed": pass_seed_edge,
		"interact": interact_held_value,
		"melee": melee_edge,
	}

func aim_direction() -> Vector3:
	return -head.global_transform.basis.z if head != null else -global_transform.basis.z

func authoritative_state(server_tick: int, last_input_sequence: int) -> Dictionary:
	return {
		"tick": server_tick,
		"last_input": last_input_sequence,
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"pitch": head.rotation.x if head != null else 0.0,
		"health": health,
		"magazine_rounds": magazine_rounds,
		"reserve_ammo": reserve_ammo,
		"reload_remaining": reload_remaining,
		"stance": int(stance),
		"weapon": int(weapon),
		"loadout_slots": loadout_slots.duplicate(),
		"active_slot": active_slot,
		"zoom_index": zoom_index,
		"bloom": bloom,
		"shot_counter": shot_counter,
		"ads_progress": ads_progress,
		"eliminated": eliminated,
		"carrying_core": is_carrying_core(),
		"player_class": int(player_class),
		"has_nuclear_vest": has_nuclear_vest,
		"has_ballistic_shield": has_ballistic_shield,
	}

func apply_input_frame(frame: Dictionary, delta: float, simulate_combat: bool) -> void:
	if frame.is_empty():
		apply_continuous_input({}, delta, simulate_combat)
		return
	if eliminated or not match_active:
		apply_continuous_input({}, delta, false)
		return
	apply_discrete_input(frame)
	apply_continuous_input(frame, delta, simulate_combat)

func apply_discrete_input(frame: Dictionary) -> void:
	if frame.is_empty() or eliminated or not match_active:
		return
	if bool(frame.get("crouch", false)):
		toggle_crouch()
	if bool(frame.get("prone", false)):
		toggle_prone()
	if bool(frame.get("weapon_switch", false)):
		switch_weapon()
	if bool(frame.get("reload", false)):
		reload_weapon()
	if bool(frame.get("jump", false)):
		_pending_jump = true

func apply_continuous_input(frame: Dictionary, delta: float, simulate_combat: bool) -> void:
	if eliminated or not match_active:
		_pending_jump = false
		_simulate_motion(Vector2.ZERO, false, delta)
		return
	# Absolute look values make a frame replayable after a correction and remove peer-specific mouse deltas.
	if not frame.is_empty():
		rotation.y = float(frame.get("yaw", rotation.y))
		if head != null:
			head.rotation.x = clampf(float(frame.get("pitch", head.rotation.x)), -1.05, 0.9)
		_aiming = bool(frame.get("aim", _aiming))
	var move_input := Vector2(float(frame.get("move_x", 0.0)), float(frame.get("move_y", 0.0))) if not frame.is_empty() else Vector2.ZERO
	var wants_jump := _pending_jump
	_pending_jump = false
	_simulate_motion(move_input, wants_jump, delta)
	if not frame.is_empty() and simulate_combat:
		if bool(frame.get("fire", false)):
			fire_forward()
		if bool(frame.get("melee", false)):
			melee_attack()

func apply_presentation_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	# Presentation state is deliberately side-effect free: it cannot raycast, damage, score, or change phase.
	global_position = state.get("position", global_position)
	velocity = state.get("velocity", Vector3.ZERO)
	rotation.y = float(state.get("yaw", rotation.y))
	if head != null:
		head.rotation.x = clampf(float(state.get("pitch", head.rotation.x)), -1.05, 0.9)
	health = clampf(float(state.get("health", health)), 0.0, HEALTH)
	if state.has("loadout_slots"):
		var next_slots: Array = state.get("loadout_slots", loadout_slots)
		if next_slots != loadout_slots:
			loadout_slots = next_slots.duplicate()
			_resolve_loadout_ammo()
	active_slot = clampi(int(state.get("active_slot", active_slot)), 0, maxi(0, loadout_slots.size() - 1))
	var capacity := int(RiftWeapons.row(RiftWeapons.clamp_weapon(int(loadout_slots[active_slot]) if not loadout_slots.is_empty() else int(weapon))).magazine_size)
	var reserve_cap := int(RiftWeapons.row(RiftWeapons.clamp_weapon(int(loadout_slots[active_slot]) if not loadout_slots.is_empty() else int(weapon))).reserve_ammo)
	magazine_rounds = clampi(int(state.get("magazine_rounds", magazine_rounds)), 0, capacity)
	reserve_ammo = clampi(int(state.get("reserve_ammo", reserve_ammo)), 0, reserve_cap)
	reload_remaining = maxf(0.0, float(state.get("reload_remaining", reload_remaining)))
	zoom_index = maxi(0, int(state.get("zoom_index", zoom_index)))
	bloom = maxf(0.0, float(state.get("bloom", bloom)))
	shot_counter = maxi(0, int(state.get("shot_counter", shot_counter)))
	ads_progress = clampf(float(state.get("ads_progress", ads_progress)), 0.0, 1.0)
	player_class = clampi(int(state.get("player_class", int(player_class))), int(PlayerClass.FRONTLINE), int(PlayerClass.SHIELD)) as PlayerClass
	has_nuclear_vest = bool(state.get("has_nuclear_vest", has_nuclear_vest))
	has_ballistic_shield = bool(state.get("has_ballistic_shield", has_ballistic_shield))
	var next_stance := clampi(int(state.get("stance", int(stance))), int(Stance.STAND), int(Stance.PRONE))
	if stance != next_stance:
		_apply_stance(next_stance as Stance)
	var next_weapon := RiftWeapons.clamp_weapon(int(state.get("weapon", int(weapon))))
	if weapon != next_weapon:
		set_weapon_presentation(next_weapon as Weapon)
	var next_eliminated := bool(state.get("eliminated", eliminated))
	if next_eliminated != eliminated:
		eliminated = next_eliminated
		if eliminated:
			_begin_death_presentation()
		else:
			_reset_death_presentation()
	else:
		eliminated = next_eliminated
	set_carrying_core(bool(state.get("carrying_core", carrying_core)))
	visible = _render_visuals and not _death_visual_hidden
	collision_layer = 0 if eliminated or not _authoritative_collision else 2

func reconcile_from_authority(state: Dictionary, unacknowledged_frames: Array, delta: float) -> void:
	if state.is_empty():
		return
	var server_position: Vector3 = state.get("position", global_position)
	var position_error := global_position.distance_to(server_position)
	var server_yaw := float(state.get("yaw", rotation.y))
	var yaw_error := absf(angle_difference(rotation.y, server_yaw))
	# Small errors are hidden by a short blend; large errors need an immediate authoritative reset.
	var corrected := state.duplicate(true)
	_pending_jump = false
	if position_error <= 0.8 and yaw_error <= 0.22:
		corrected["position"] = global_position.lerp(server_position, clampf(delta * 10.0, 0.0, 1.0))
		corrected["yaw"] = lerp_angle(rotation.y, server_yaw, clampf(delta * 10.0, 0.0, 1.0))
	apply_presentation_state(corrected)
	for frame in unacknowledged_frames:
		if frame is Dictionary:
			_apply_replay_frame(frame, delta)

func _apply_replay_frame(frame: Dictionary, delta: float) -> void:
	if eliminated or not match_active:
		return
	apply_discrete_input(frame)
	apply_continuous_input(frame, delta, false)

func _simulate_motion(move_input: Vector2, wants_jump: bool, delta: float) -> void:
	_fire_remaining = maxf(0.0, _fire_remaining - delta)
	_melee_remaining = maxf(0.0, _melee_remaining - delta)
	var active_row := RiftWeapons.row(int(weapon))
	bloom = maxf(0.0, bloom - float(active_row.bloom_decay) * delta)
	var ads_seconds := maxf(0.02, float(active_row.ads_seconds))
	ads_progress = clampf(ads_progress + (delta / ads_seconds) * (1.0 if _aiming else -1.0), 0.0, 1.0)
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			var capacity := int(active_row.magazine_size)
			var transfer := mini(capacity - magazine_rounds, reserve_ammo)
			magazine_rounds += transfer
			reserve_ammo -= transfer
	if eliminated or not match_active:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	var profile := standing_speed_profile(weapon, _aiming)
	var desired := right * move_input.x * float(profile.lateral) + forward * (-move_input.y) * float(profile.forward)
	var stance_speed := 1.0 if stance == Stance.STAND else 0.62 if stance == Stance.CROUCH else 0.3
	var mobility_scale := stance_speed * movement_speed_multiplier()
	velocity.x = move_toward(velocity.x, desired.x * mobility_scale, WALK_SPEED * 12.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z * mobility_scale, WALK_SPEED * 12.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = JUMP_SPEED if wants_jump and stance != Stance.PRONE else -0.1
	move_and_slide()

func set_stance(next_stance: Stance) -> void:
	if eliminated or not match_active or stance == next_stance:
		return
	_apply_stance(next_stance)

func _apply_stance(next_stance: Stance) -> void:
	stance = next_stance
	var body_height := 1.8
	var body_radius := 0.48
	match stance:
		Stance.CROUCH:
			body_height = 1.18
			body_radius = 0.42
		Stance.PRONE:
			body_height = 0.68
			body_radius = 0.32
	_capsule.height = body_height
	_capsule.radius = body_radius
	_collision.position.y = body_height * 0.5
	_body_visual_target_scale_y = body_height / 1.8
	head.position.y = body_height - 0.34

func toggle_crouch() -> void:
	set_stance(Stance.STAND if stance == Stance.CROUCH else Stance.CROUCH)

func toggle_prone() -> void:
	set_stance(Stance.STAND if stance == Stance.PRONE else Stance.PRONE)

func set_combat_pose(aiming: bool, delta: float) -> void:
	if eliminated:
		return
	_aiming = aiming
	if camera != null:
		var target_horizontal := RiftWeapons.ads_horizontal_fov(horizontal_fov, int(weapon), zoom_index) if aiming else horizontal_fov
		var target_vertical := _vertical_fov_for_horizontal(target_horizontal, _viewport_aspect())
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = lerpf(camera.fov, target_vertical, minf(1.0, delta * 13.0))

func _ads_weapon_anchor() -> Vector3:
	if is_shield_class():
		# Ordinary centered sight picture; the shield pitches down out of the
		# way underneath it rather than the gun stepping aside - see
		# SHIELD_ADS_WEAPON_ANCHOR. Render-only: the authoritative shot
		# origin still comes from RiftWeapons' optic_tip/ads_anchor formula
		# via `optic_tip_head_offset()`, so this never touches hit
		# registration or the crosshair.
		return SHIELD_ADS_WEAPON_ANCHOR
	# One calibration seam per weapon keeps its optic centered on the camera's aim ray.
	return Vector3(RiftWeapons.row(int(weapon)).get("ads_anchor", Vector3(0.0, -0.11, -0.9)))

static func optic_tip_head_offset(weapon_value: int) -> Vector3:
	var facts := RiftWeapons.row(RiftWeapons.clamp_weapon(weapon_value))
	return Vector3(facts.get("ads_anchor", Vector3.ZERO)) + Vector3(facts.get("optic_tip_local", Vector3.ZERO)) * FIRST_PERSON_WEAPON_SCALE

static func shot_origin_for(eye: Vector3, basis: Basis, aiming: bool, weapon_value: Weapon) -> Vector3:
	if aiming:
		# ADS bullets leave the centered optic tip on every weapon now that
		# iron sights are gone - the physical muzzle stays a separate
		# obstruction probe, while aim direction rides the optic's center ray.
		return eye + basis * optic_tip_head_offset(int(weapon_value))
	return eye

func authoritative_ads_optic_tip() -> Vector3:
	var eye := authoritative_eye_origin()
	var basis := head.global_transform.basis if head != null else global_transform.basis
	return eye + basis * optic_tip_head_offset(int(weapon))

func authoritative_shot_origin() -> Vector3:
	var eye := authoritative_eye_origin()
	var basis := head.global_transform.basis if head != null else global_transform.basis
	return shot_origin_for(eye, basis, _aiming, weapon)

func drive(move_input: Vector2, wants_fire: bool, wants_jump: bool, delta: float) -> void:
	if eliminated or not match_active:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	_simulate_motion(move_input, wants_jump, delta)

	if wants_fire:
		fire_forward()

func fire_forward() -> void:
	if eliminated or not match_active or _fire_remaining > 0.0 or reload_remaining > 0.0:
		return
	if magazine_rounds <= 0:
		reload_weapon()
		return
	var row := RiftWeapons.row(int(weapon))
	_fire_remaining = float(row.fire_interval)
	var plan := _accept_shot_plan()
	magazine_rounds -= 1
	fire_requested.emit(self, weapon, plan.eye_origin, plan.direction)

func fire_at(target: Vector3) -> void:
	if eliminated or not match_active or _fire_remaining > 0.0 or reload_remaining > 0.0:
		return
	if magazine_rounds <= 0:
		reload_weapon()
		return
	var row := RiftWeapons.row(int(weapon))
	_fire_remaining = float(row.fire_interval)
	var plan := _accept_shot_plan((target - authoritative_shot_origin()).normalized())
	magazine_rounds -= 1
	fire_requested.emit(self, weapon, plan.eye_origin, plan.direction)

func melee_attack() -> void:
	if eliminated or not match_active or _melee_remaining > 0.0:
		return
	var row := RiftWeapons.row(int(weapon))
	_melee_remaining = float(row.melee_cooldown)
	play_local_melee_swing()
	var origin := authoritative_eye_origin()
	var direction := authoritative_aim_direction()
	var reach := float(row.melee_range)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, 1 | 2)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := origin + direction * reach
	var hit_target := false
	var target_id := ""
	if not hit.is_empty():
		end = hit.position
		var collider: Object = hit.collider
		if collider is Duelist and collider != self and collider.team != team and not collider.eliminated:
			hit_target = true
			target_id = collider.actor_id
			collider.take_damage(float(row.melee_damage), self)
	melee_strike.emit(actor_id, weapon, origin, end, team, hit_target, target_id)

func switch_weapon() -> void:
	if eliminated or not match_active:
		return
	if _aiming and weapon == Weapon.SNIPER:
		var steps: Array = RiftWeapons.row(int(Weapon.SNIPER)).zoom_steps
		zoom_index = (zoom_index + 1) % maxi(1, steps.size())
		return
	if loadout_slots.size() < 2:
		return
	_slot_magazine[active_slot] = magazine_rounds
	_slot_reserve[active_slot] = reserve_ammo
	active_slot = 1 - active_slot
	magazine_rounds = int(_slot_magazine[active_slot])
	reserve_ammo = int(_slot_reserve[active_slot])
	reload_remaining = 0.0
	zoom_index = 0
	set_weapon_presentation(loadout_slots[active_slot] as Weapon)
	_fire_remaining = maxf(_fire_remaining, WEAPON_SWAP_LOCKOUT)

func reload_weapon() -> bool:
	if eliminated or not match_active or reload_remaining > 0.0:
		return false
	var row := RiftWeapons.row(int(weapon))
	var capacity := int(row.magazine_size)
	if magazine_rounds >= capacity or reserve_ammo <= 0:
		return false
	reload_remaining = float(row.reload_seconds)
	_fire_remaining = maxf(_fire_remaining, 0.12)
	return true

func take_damage(amount: float, attacker: Duelist) -> void:
	if eliminated or not match_active:
		return
	var applied := amount
	if has_ballistic_shield and attacker != null and is_instance_valid(attacker):
		var to_attacker := attacker.global_position - global_position
		to_attacker.y = 0.0
		var forward := -global_transform.basis.z
		forward.y = 0.0
		# A moveable frontal shield (Montagne-reference): it blocks whatever
		# arrives from within roughly a 120-degree arc of where the carrier is
		# currently facing, bullet or melee alike, and does not degrade.
		if to_attacker.length_squared() > 0.0001 and forward.length_squared() > 0.0001 and forward.normalized().dot(to_attacker.normalized()) > 0.5:
			applied = 0.0
	health = maxf(0.0, health - applied)
	apply_damage_presentation(applied, health)
	damaged.emit(applied, health, attacker.actor_id if attacker != null else "", attacker.global_position if attacker != null else Vector3.ZERO, int(attacker.team) if attacker != null else -1)
	if health <= 0.0:
		eliminated = true
		carrying_core = false
		_recoil_remaining = 0.0
		_recoil_kick = 0.0
		_recoil_lateral = 0.0
		_obstruction_remaining = 0.0
		_swap_motion = 0.0
		_pending_authoritative_shot_plan.clear()
		_begin_death_presentation()
		collision_layer = 0
		defeated.emit(self, attacker)

func respawn_at(point: Vector3) -> void:
	global_position = point
	velocity = Vector3.ZERO
	health = HEALTH
	eliminated = false
	carrying_core = false
	_reset_death_presentation()
	collision_layer = 2
	_aiming = false
	_recoil_remaining = 0.0
	_fire_flash_remaining = 0.0
	_damage_flash_remaining = 0.0
	_flinch_remaining = 0.0
	_obstruction_remaining = 0.0
	_swap_motion = 0.0
	_recoil_kick = 0.0
	_recoil_lateral = 0.0
	_melee_remaining = 0.0
	_melee_swing_remaining = 0.0
	bloom = 0.0
	shot_counter = 0
	ads_progress = 0.0
	_pending_authoritative_shot_plan.clear()
	if _body_visual_root != null:
		_body_visual_root.rotation = Vector3.ZERO
		_body_visual_root.position = Vector3.ZERO
	active_slot = 0
	zoom_index = 0
	_resolve_loadout_ammo()

func _begin_death_presentation() -> void:
	_death_visual_elapsed = 0.0
	_death_visual_hidden = false
	visible = _render_visuals
	_set_visual_transparency(0.0)

func _reset_death_presentation() -> void:
	_death_visual_elapsed = 0.0
	_death_visual_hidden = false
	visible = _render_visuals
	_set_visual_transparency(0.0)
	if _body_visual_root != null:
		_body_visual_root.position = Vector3.ZERO
		_body_visual_root.rotation.z = 0.0

func _tick_death_presentation(delta: float) -> void:
	if not eliminated or _death_visual_hidden:
		return
	_death_visual_elapsed += delta
	var fade_elapsed := _death_visual_elapsed - DEATH_VISUAL_HOLD_SECONDS
	if fade_elapsed <= 0.0:
		return
	var fade_progress := clampf(fade_elapsed / DEATH_VISUAL_FADE_SECONDS, 0.0, 1.0)
	_set_visual_transparency(fade_progress)
	if fade_progress >= 1.0:
		_death_visual_hidden = true
		visible = false

func _set_visual_transparency(amount: float) -> void:
	var geometry_nodes: Array[Node] = find_children("*", "GeometryInstance3D", true, false)
	for node: Node in geometry_nodes:
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).transparency = clampf(amount, 0.0, 1.0)
	# Forced: respawn must present a genuinely fresh weapon model even when the
	# respawning weapon is the same one the player died holding - see
	# set_weapon_presentation()'s comment for why the "unchanged, skip it"
	# optimization is wrong specifically here.
	set_weapon_presentation(loadout_slots[0] as Weapon, true)
	_apply_stance(Stance.STAND)

## Read-only mirror of `_recoil_kick`/`_recoil_lateral` for `DuelHud` to nudge
## the ADS/scope reticle by, so the crosshair reads as attached to the
## housing that is now visibly kicking under it, rather than floating dead
## center while the sight housing jumps around it. Same precedent as
## `ads_progress`/`zoom_index` being pushed into the HUD each frame - see
## `DuelHud.set_ads_state()`. Deliberately not a 3D-to-2D projection of the
## actual dot mesh; that's real optical work for a fix whose only job is
## making the housing's own motion visible in the reticle too.
func recoil_presentation() -> Vector2:
	return Vector2(_recoil_kick, _recoil_lateral)

func authoritative_eye_origin() -> Vector3:
	return head.global_position if head != null else global_position + Vector3.UP * 1.46

func authoritative_aim_direction() -> Vector3:
	return -head.global_transform.basis.z if head != null else -global_transform.basis.z

func physical_muzzle_position() -> Vector3:
	var eye := authoritative_eye_origin()
	var basis := head.global_transform.basis if head != null else global_transform.basis
	return eye + basis.x * 0.42 - basis.y * 0.42 - basis.z * 1.85

func consume_authoritative_shot_plan() -> Dictionary:
	if not _pending_authoritative_shot_plan.is_empty():
		var plan := _pending_authoritative_shot_plan.duplicate(true)
		_pending_authoritative_shot_plan.clear()
		return plan
	return _accept_shot_plan()

func play_weapon_obstruction() -> void:
	_obstruction_remaining = 0.2

## Builds the authoritative shot plan for the currently equipped weapon.
## Direction dispersion is a pure function of already-networked state
## (weapon row, velocity-derived speed/airborne, stance, ads_progress,
## bloom) sampled with a stateless hash keyed on (actor, shot_counter,
## pellet index) - never a RandomNumberGenerator, whose internal state is
## not part of the snapshot and would desync prediction from authority.
func _accept_shot_plan(forced_direction: Vector3 = Vector3.ZERO) -> Dictionary:
	var eye := authoritative_shot_origin()
	var base_direction := authoritative_aim_direction()
	var deliberate := forced_direction.length_squared() > 0.0001
	if deliberate:
		base_direction = forced_direction.normalized()
	var right := head.global_transform.basis.x
	var up := head.global_transform.basis.y
	var speed_t := clampf(Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 0.0, 1.0)
	var airborne := absf(velocity.y) > AIRBORNE_VELOCITY_Y
	var crouched := stance == Stance.CROUCH
	var cone := 0.0 if deliberate else RiftWeapons.cone_for(int(weapon), speed_t, crouched, airborne, ads_progress, bloom)
	last_shot_was_hip_followup = not deliberate and not _aiming and bloom > 0.05
	var offsets := RiftWeapons.pellet_offsets(int(weapon), actor_id.hash(), shot_counter, cone)
	var directions: Array[Vector3] = []
	for offset in offsets:
		directions.append((base_direction + right * offset.x + up * offset.y).normalized())
	var active_row := RiftWeapons.row(int(weapon))
	bloom = minf(bloom + 1.0, float(active_row.bloom_max) + 1.0)
	var plan := {
		"eye_origin": eye,
		"direction": directions[0],
		"directions": directions,
		"physical_muzzle": physical_muzzle_position(),
		"presentation_origin": eye + directions[0] * 0.18,
		"shot_id": shot_counter,
		"weapon": int(weapon),
		"hip_burst_followup": last_shot_was_hip_followup,
		"deliberate": deliberate,
	}
	shot_counter += 1
	_pending_authoritative_shot_plan = plan.duplicate(true)
	return plan

func _local_muzzle_obstructed() -> bool:
	if not _local_camera or get_world_3d() == null or not is_inside_tree():
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = BALLISTICS.MUZZLE_CONTACT_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, physical_muzzle_position())
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _team_color() -> Color:
	return Color("e0463c") if team == Team.RED else Color("4ba9ff")

func _team_glow() -> Color:
	return Color("ff7a68") if team == Team.RED else Color("7bdbff")

func _build_character_silhouette() -> void:
	# Blender-authored, low-poly modular armor. The same lightweight geometry
	# serves both teams; runtime materials provide RED/BLUE identity without
	# duplicating the asset. Named pivots preserve the existing procedural gait.
	var model_instance: Node = CHARACTER_MODEL.instantiate()
	if not model_instance is Node3D:
		push_error("Riftline character GLB did not instantiate as Node3D")
		model_instance.queue_free()
		return
	_body_visual_root = model_instance as Node3D
	_body_visual_root.name = "BlenderCharacter"
	add_child(_body_visual_root)
	_torso = _model_part("Torso")
	_model_head = _model_part("Head")
	_left_leg = _model_part("LeftLeg")
	_right_leg = _model_part("RightLeg")
	_left_arm = _model_part("LeftArm")
	_right_arm = _model_part("RightArm")
	_band = _body_visual_root.find_child("ACCENT_ChestStripe", true, false) as MeshInstance3D
	_cache_character_rest_pose()
	_apply_character_materials()
	var dark := NuclearMaterials.polymer(Color("111923"), 0.7)
	var brass := NuclearMaterials.metal(Color("7b8797"), 0.32)
	var glow := NuclearMaterials.emissive(_team_glow(), 1.4)
	_build_carrier_signal(glow)
	if player_class == PlayerClass.SHIELD:
		_build_ballistic_shield(dark, brass, glow)
	elif player_class == PlayerClass.RUNNER:
		_build_nuclear_vest_marker(glow)

func _model_part(part_name: String) -> Node3D:
	if _body_visual_root == null:
		return null
	var found: Node = _body_visual_root.find_child(part_name, true, false)
	return found as Node3D if found is Node3D else null

func _cache_character_rest_pose() -> void:
	if _torso != null:
		_torso_rest_position = _torso.position
		_torso_rest_rotation = _torso.rotation
	if _model_head != null:
		_model_head_rest_rotation = _model_head.rotation
	if _left_leg != null:
		_left_leg_rest_rotation = _left_leg.rotation
	if _right_leg != null:
		_right_leg_rest_rotation = _right_leg.rotation
	if _left_arm != null:
		_left_arm_rest_rotation = _left_arm.rotation
	if _right_arm != null:
		_right_arm_rest_rotation = _right_arm.rotation

func _apply_character_materials() -> void:
	if _body_visual_root == null:
		return
	var team_plate: Material = NuclearMaterials.painted_metal(_team_color(), 0.38)
	var undersuit: Material = NuclearMaterials.polymer(Color("101923"), 0.72)
	var armor: Material = NuclearMaterials.metal(Color("26313e"), 0.36)
	var hardware: Material = NuclearMaterials.metal(Color("566273"), 0.28)
	var team_light: Material = NuclearMaterials.emissive(_team_glow(), 2.2)
	var geometry_nodes: Array[Node] = _body_visual_root.find_children("*", "MeshInstance3D", true, false)
	for node: Node in geometry_nodes:
		var instance := node as MeshInstance3D
		if instance == null:
			continue
		instance.layers = 1
		if instance.name.begins_with("TEAM_"):
			instance.material_override = team_plate
		elif instance.name.begins_with("DARK_"):
			instance.material_override = undersuit
		elif instance.name.begins_with("ARMOR_"):
			instance.material_override = armor
		elif instance.name.begins_with("METAL_"):
			instance.material_override = hardware
		elif instance.name.begins_with("VISOR_") or instance.name.begins_with("ACCENT_"):
			instance.material_override = team_light
	# Damage presentation animates only this chest strip. Give it a local
	# material instance so one actor flashing cannot change every same-team
	# visor/accent through NuclearMaterials' intentional shared cache.
	if _band != null:
		_band.material_override = team_light.duplicate() as Material

func _torus(inner_radius: float, outer_radius: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = inner_radius + outer_radius
	mesh.rings = 14
	mesh.ring_segments = 8
	return mesh

func _build_carrier_signal(glow: Material) -> void:
	_carrier_signal_root = Node3D.new()
	_carrier_signal_root.name = "CarrierSignal"
	_carrier_signal_root.position = Vector3(0.0, 2.12, 0.0)
	_carrier_signal_root.visible = false
	add_child(_carrier_signal_root)
	for radius in [0.22, 0.34]:
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = radius
		ring_mesh.outer_radius = radius + 0.035
		ring_mesh.rings = 12
		ring_mesh.ring_segments = 8
		ring.mesh = ring_mesh
		ring.rotation.x = PI * 0.5
		ring.material_override = glow
		ring.layers = 1
		_carrier_signal_root.add_child(ring)

## Shield class equipment: a broad frontal plate carried in front of the
## torso, matching the "moveable frontal shield, not a deployable" reference.
func _build_ballistic_shield(dark: Material, brass: Material, glow: Material) -> void:
	_shield_plate = _add_body_part(_box(Vector3(0.62, 0.86, 0.07)), Vector3(0.0, 1.02, -0.46), dark)
	_add_body_part(_box(Vector3(0.66, 0.9, 0.02)), Vector3(0.0, 1.02, -0.50), brass)
	_add_body_part(_cylinder(0.07, 0.07, 0.4), Vector3(0.0, 1.02, -0.42), glow, Vector3(PI * 0.5, 0.0, 0.0))

## The Shield class's own first-person view of its shield: a ballistic
## riot-shield the carrier looks through (the vision port between the rib
## frames is open geometry, not a solid pane), carried vertically in front of
## him by default, rolled flat horizontal on ADS with the revolver riding
## above its edge, bumped forward on melee, and held vertical again through a
## reload. See `_process()` for the pose blend and `SHIELD_VERTICAL_*`/
## `SHIELD_HORIZONTAL_*`/`SHIELD_RELOAD_WEAPON_POSITION` for the numbers.
##
## `_build_character_silhouette()` - and with it `_build_ballistic_shield()` -
## is only ever built for the remote presentation, so up to now a Shield player
## was the one person in the match who could not see the piece of equipment
## that defines their class. This builds a separate, purpose-composed view
## model, seen from *behind* (the carrier's own side), with the arm brace and
## grip facing the camera and the left glove holding the grip - what actually
## sells "I am carrying this" rather than "a wall is stuck to my screen".
## Rendering only - `has_ballistic_shield` and every block and
## damage-reduction rule it feeds are untouched.
func _rebuild_first_person_shield() -> void:
	if not (_local_camera and _render_visuals) or camera == null:
		return
	if _fp_shield_root != null:
		_fp_shield_root.queue_free()
		_fp_shield_root = null
		_left_hand_root = null
	if not has_ballistic_shield:
		return
	_fp_shield_root = Node3D.new()
	_fp_shield_root.name = "FirstPersonShield"
	# Static build-time pose; `_process()` takes over every frame after the
	# first to blend this against the horizontal ADS/reload poses.
	_fp_shield_root.position = SHIELD_VERTICAL_POSITION
	_fp_shield_root.rotation = SHIELD_VERTICAL_ROTATION
	_shield_horizontal_t = 0.0
	camera.add_child(_fp_shield_root)
	var armour := NuclearMaterials.painted_metal(Color("323b46"), 0.60)
	var rib := NuclearMaterials.metal(Color("6e7883"), 0.48)
	var strap := NuclearMaterials.polymer(Color("24292f"), 0.60)
	var trim := NuclearMaterials.metal(Color("b98b46"), 0.40)
	var glow := NuclearMaterials.emissive(_team_glow(), 1.1)
	# Plate: stacked panels rather than one slab, each stepping slightly nearer
	# the player, so the face has real relief instead of one flat grey field.
	# The upper panel is cut into four pieces around the vision port rather than
	# spanning it. It used to be one full-width slab, which meant the "open"
	# port framed below was open only in the frame itself - there was solid
	# armour a few millimetres behind it and the carrier saw grey, not the
	# world. This is the one hole in the plate and it has to actually be a hole.
	#
	# The port itself spans x=[-0.175, 0.175] (nearly the full 0.42-wide plate)
	# and y=[0.080, 0.280] (0.20 tall - 3x the original slit), so the four
	# cutout panels below are sized to exactly surround that rectangle rather
	# than the old narrow slot.
	_add_shield_part(_box(Vector3(0.035, 0.26, 0.038)), Vector3(-0.1925, 0.180, 0.0), armour)
	_add_shield_part(_box(Vector3(0.035, 0.26, 0.038)), Vector3(0.1925, 0.180, 0.0), armour)
	_add_shield_part(_box(Vector3(0.35, 0.03, 0.038)), Vector3(0.0, 0.295, 0.0), armour)
	_add_shield_part(_box(Vector3(0.35, 0.03, 0.038)), Vector3(0.0, 0.065, 0.0), armour)
	_add_shield_part(_box(Vector3(0.42, 0.28, 0.044)), Vector3(0.0, -0.090, 0.007), armour)
	_add_shield_part(_box(Vector3(0.40, 0.22, 0.038)), Vector3(0.0, -0.330, 0.015), armour)
	# Reinforcing rib and the top lip - the value contrast that keeps the plate
	# from flattening out against a pale floor. The old middle rib (y=0.245)
	# is gone - the enlarged port now occupies that band, and a rib crossing
	# it would have re-blocked the view it exists to open up.
	_add_shield_part(_box(Vector3(0.44, 0.016, 0.056)), Vector3(0.0, 0.052, 0.007), rib)
	_add_shield_part(_box(Vector3(0.45, 0.030, 0.062)), Vector3(0.0, 0.318, 0.002), rib)
	for bolt_x in [-0.15, -0.05, 0.05, 0.15]:
		_add_shield_part(_sphere(0.010), Vector3(bolt_x, 0.318, 0.032), trim)
	# Leading edge: brass trim plus a team strip. These two are what separate
	# the shield from whatever is behind it at any background brightness.
	_add_shield_part(_box(Vector3(0.024, 0.70, 0.056)), Vector3(0.213, -0.040, 0.007), trim)
	_add_shield_part(_box(Vector3(0.013, 0.66, 0.018)), Vector3(0.213, -0.040, 0.035), glow)
	_add_shield_part(_box(Vector3(0.024, 0.70, 0.056)), Vector3(-0.213, -0.040, 0.007), rib)
	# Vision port frame: a thin lip top and bottom, matching the new
	# near-full-width, 3x-tall opening cut into the panels above.
	_add_shield_part(_box(Vector3(0.35, 0.018, 0.050)), Vector3(0.0, 0.280, 0.010), rib)
	_add_shield_part(_box(Vector3(0.35, 0.018, 0.050)), Vector3(0.0, 0.080, 0.010), rib)
	for mullion_x in [-0.09, 0.09]:
		_add_shield_part(_box(Vector3(0.014, 0.18, 0.046)), Vector3(mullion_x, 0.180, 0.010), rib)
	# Arm brace and forearm cuff, raised to just under the vision port so they
	# are actually in frame. This is the detail that reads as held equipment.
	_add_shield_part(_box(Vector3(0.26, 0.048, 0.040)), Vector3(0.030, 0.062, 0.066), rib)
	_add_shield_part(_torus(0.058, 0.017), Vector3(0.075, 0.062, 0.098), strap, Vector3(0.0, 0.0, PI * 0.5))
	_add_shield_part(_cylinder(0.023, 0.023, 0.15), Vector3(0.145, -0.055, 0.090), strap, Vector3(0.0, 0.0, PI * 0.5))
	_add_shield_part(_box(Vector3(0.044, 0.044, 0.096)), Vector3(0.050, -0.055, 0.066), rib)
	# Left hand grips the handle bar and is parented here, not `_weapon_rig` -
	# it rides the shield's own vertical/horizontal/melee-bump motion in
	# `_process()` (turning clockwise with it on ADS) instead of the weapon's.
	_left_hand_root = _build_glove_hand(NuclearMaterials.polymer(Color("1c2126"), 0.62), NuclearMaterials.polymer(Color("272c26"), 0.58))
	_left_hand_root.name = "ShieldHand"
	# The handle bar above runs along the shield's local X, so by
	# `_build_glove_hand()`'s convention the glove needs no rotation at all
	# here: its wrap axis is already X and its forearm already leaves toward
	# the carrier (+Z). It sits exactly on the bar rather than beside it.
	_left_hand_root.position = Vector3(0.145, -0.055, 0.090)
	_left_hand_root.rotation = Vector3(0.0, 0.0, -0.10)
	# Gloves are modelled in weapon-rig units; the shield is a direct child of
	# the camera at world scale, so the 0.38 the weapon root applies has to be
	# re-applied by hand or the glove arrives nearly three times life size.
	_left_hand_root.scale = Vector3.ONE * FIRST_PERSON_WEAPON_SCALE
	_fp_shield_root.add_child(_left_hand_root)

func _add_shield_part(mesh: Mesh, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	instance.layers = VIEW_MODEL_LAYER_MASK
	_fp_shield_root.add_child(instance)

## Runner class equipment: a chest-worn vest that keeps the class silhouette
## readable. Core carrying no longer deals damage to any class.
func _build_nuclear_vest_marker(glow: Material) -> void:
	_add_body_part(_box(Vector3(0.5, 0.5, 0.46)), Vector3(0.0, 1.05, 0.0), glow)

func _build_signal_hauler(cloth: Material, dark: Material, brass: Material, glow: Material) -> void:
	# Rejected alternative: a symmetrical chest rig. The offset coat panel and forked aerial give the courier forward motion.
	_add_body_part(_box(Vector3(0.66, 0.7, 0.09)), Vector3(-0.08, 0.91, -0.37), cloth, Vector3(0.0, 0.0, 0.08))
	_signal_spine = _add_body_part(_box(Vector3(0.12, 0.78, 0.16)), Vector3(0.0, 1.16, 0.34), dark)
	_add_body_part(_box(Vector3(0.1, 0.5, 0.12)), Vector3(-0.32, 1.18, 0.33), brass, Vector3(0.0, 0.0, 0.2))
	_add_body_part(_box(Vector3(0.08, 0.38, 0.08)), Vector3(0.0, 1.72, 0.36), brass, Vector3(0.0, 0.0, -0.28))
	_add_body_part(_box(Vector3(0.42, 0.06, 0.08)), Vector3(0.0, 1.88, 0.36), brass, Vector3(0.0, 0.0, 0.18))
	_add_body_part(_cylinder(0.13, 0.13, 0.38), Vector3(0.0, 1.17, -0.43), glow, Vector3(PI * 0.5, 0.0, 0.0))

func _build_storm_surveyor(cloth: Material, dark: Material, brass: Material, glow: Material) -> void:
	# Rejected alternative: a tall hood. The lateral mantle and folded wind-array frame read as precise survey gear.
	_add_body_part(_cylinder(0.16, 0.43, 0.82), Vector3(0.0, 0.88, -0.02), cloth)
	_add_body_part(_box(Vector3(0.92, 0.12, 0.26)), Vector3(0.0, 1.36, 0.36), cloth, Vector3(0.0, 0.0, 0.08))
	_survey_frame = _add_body_part(_box(Vector3(0.08, 0.92, 0.36)), Vector3(0.0, 1.37, 0.47), dark, Vector3(0.0, 0.0, 0.16))
	_add_body_part(_box(Vector3(0.82, 0.08, 0.16)), Vector3(0.0, 1.62, 0.48), brass, Vector3(0.0, 0.0, 0.11))
	_add_body_part(_box(Vector3(0.52, 0.05, 0.11)), Vector3(0.0, 1.87, 0.48), brass, Vector3(0.0, 0.0, -0.18))
	_add_body_part(_cylinder(0.1, 0.1, 0.28), Vector3(0.0, 1.1, -0.43), glow, Vector3(PI * 0.5, 0.0, 0.0))

func _build_first_person_weapon() -> void:
	_weapon_root = Node3D.new()
	_weapon_root.name = "FirstPersonWeapon"
	_weapon_root.position = FIRST_PERSON_HIP_ANCHOR
	_weapon_root.scale = Vector3.ONE * FIRST_PERSON_WEAPON_SCALE
	camera.add_child(_weapon_root)
	_weapon_rig = Node3D.new()
	_weapon_rig.name = "Rig"
	_weapon_rig.rotation = FIRST_PERSON_HIP_RIG_ROTATION
	_weapon_root.add_child(_weapon_rig)
	_build_view_model_lights()

## Key and fill for the view model only (`light_cull_mask` is layer 2, which
## nothing in the arena occupies). They are parented to the camera, so the
## weapon keeps a stable, readable shading direction no matter which way the
## player is facing - the arena's single world sun otherwise left the gun a
## featureless black cut-out for half of every rotation.
func _build_view_model_lights() -> void:
	# Key from over the player's right shoulder: the direction that puts a
	# highlight on the top and near faces, which is all the shape a primitive
	# weapon has to work with.
	# Specular is kept low: at anything higher the flat top of the receiver
	# clipped to pure white right under the sight window, which is the last
	# place on the screen that should be the brightest thing in the frame.
	_add_view_model_light("ViewModelKey", Vector3(-26.0, 26.0, 0.0), 1.38, Color("fff2e0"), 0.45)
	# Cool fill from the opposite side, so the shadow side is a readable dark
	# blue rather than the absolute black it used to be.
	_add_view_model_light("ViewModelFill", Vector3(12.0, -124.0, 0.0), 0.62, Color("9dc2e6"), 0.14)
	# Near-camera-aligned lift. Aiming down the sights turns the magazine, grip
	# and receiver face straight at the viewer, where neither key nor fill can
	# reach them; without this they read as one dead black column.
	_add_view_model_light("ViewModelLift", Vector3(8.0, -7.0, 0.0), 0.58, Color("cbd6de"), 0.04)

func _add_view_model_light(light_name: String, angles: Vector3, energy: float, tint: Color, specular: float) -> void:
	var light := DirectionalLight3D.new()
	light.name = light_name
	light.light_cull_mask = VIEW_MODEL_LAYER_MASK
	light.light_energy = energy
	light.light_color = tint
	light.light_specular = specular
	light.shadow_enabled = false
	light.rotation_degrees = angles
	camera.add_child(light)

func _build_world_weapon() -> void:
	_weapon_root = Node3D.new()
	_weapon_root.name = "WorldWeapon"
	_weapon_root.position = Vector3(0.38, -0.27, -0.64)
	_weapon_root.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	_weapon_root.scale = Vector3.ONE * 0.72
	head.add_child(_weapon_root)
	_weapon_rig = Node3D.new()
	_weapon_rig.name = "Rig"
	_weapon_root.add_child(_weapon_rig)

## An armoured tactical glove, built closed around whatever it is holding.
##
## Origin convention - this is what every caller depends on. Local (0,0,0) sits
## on the *grip axis*: the imaginary tube the curled fingers enclose. That axis
## runs along local X. The forearm leaves along +Z, the back of the hand faces
## +Y, and the thumb/index side is -X, which is what makes this a right hand.
## Placing a glove is therefore always the same instruction - put the origin on
## the thing being held and aim local X down that thing's axis - which is
## exactly what `HAND_GRIP_POSE` and the shield handle grip below both do, and
## why both of their rotations reduce to one readable term plus a quarter turn.
##
## Scale: built in weapon-rig units, the same 1 unit is about 0.36 m the
## `_build_*_model()` functions are drawn at, so a knuckle span of 0.245 here
## is a 88 mm hand. The shield glove lives outside `_weapon_root`'s 0.38 scale
## and re-applies that factor itself.
##
## The look is a hard-shell tactical gauntlet - PUBG/Siege proportions wearing
## Halo/Destiny plating - and it earns that from the same trick the weapons in
## this file use rather than from any imported mesh: nothing is ever a single
## flat box. Every soft mass carries a harder plate floating a few millimetres
## proud of it, seated on a darker shelf, so each step reads as a machined seam
## instead of a colour change.
func _build_glove_hand(glove: Material, cuff: Material, mirrored: bool = false) -> Node3D:
	var root := Node3D.new()
	# Armour and accent roles are mixed here rather than passed in, because
	# hands are deliberately team-neutral: nothing in this function may ever be
	# sourced from `_team_color()`. `glove` is the soft shell, `cuff` the
	# sleeve, `plate` the hard gauntlet, `shade` the recessed seams the plates
	# sit on, and `tell` the one small lit element on the wrist module.
	# `plate` is deliberately several stops lighter than anything else on the
	# glove. At the size a hand actually occupies in the frame the panel lines
	# and the 3 mm steps are sub-pixel; the only thing that survives is value
	# contrast, so the armour has to be the bright element against a near-black
	# shell or the whole hand collapses into one dark blob.
	var plate := NuclearMaterials.metal(Color("959eaa"), 0.34)
	var shade := NuclearMaterials.painted_metal(Color("22272d"), 0.58)
	var tell := NuclearMaterials.emissive(Color("e8a44e"), 0.9)
	# --- Wrist and forearm, on their own pivot.
	#
	# A gripping hand's forearm is *not* perpendicular to the thing it holds -
	# the wrist breaks toward the little finger by something like 35 degrees,
	# which is why a shooter's elbow ends up below and behind the grip rather
	# than level with it. Building that break in here rather than into every
	# pose is what keeps `HAND_GRIP_POSE` down to one meaningful number per
	# hand, and it is load-bearing visually: run the arm straight out of +Z
	# instead and it leaves the grip pointing back and *upward*, which parks
	# the flat disc of the elbow end cap in the middle of the frame. With the
	# break, every arm exits through the bottom edge of the screen, which is
	# where an arm belongs and is also the only place it can be cut off
	# without showing a cap.
	var arm := Node3D.new()
	arm.name = "Forearm"
	arm.position = Vector3(0.0, 0.056, 0.185)
	arm.rotation = Vector3(0.0, 0.62, 0.0)
	root.add_child(arm)
	# Cinched collar and its steel ring, then the sleeve under a bolted bracer.
	# The sleeve is the largest single mass on the glove and sits closest to
	# the camera, so it gets banded rather than left as one smooth tube.
	_add_child_part(arm, _cylinder(0.106, 0.120, 0.120), Vector3(0.0, 0.004, 0.052), cuff, Vector3(PI * 0.5, 0.0, 0.0))
	_add_child_part(arm, _torus(0.110, 0.026), Vector3(0.0, 0.004, 0.056), plate, Vector3(PI * 0.5, 0.0, 0.0))
	# The sleeve deliberately runs a long way past the elbow. It is not there to
	# be seen - it is there so that it is *never* seen ending. At the ADS pose
	# the weapon comes to the middle of the screen and the support arm sweeps in
	# from the left rather than dropping off the bottom, and a sleeve only as
	# long as a real forearm finishes inside the frame, parking the flat disc of
	# its end cap in open view. Run it past where the elbow would be and both
	# arms leave through the bottom edge in every pose the rig can reach.
	_add_child_part(arm, _tapered_cylinder(0.146, 0.102, 1.00), Vector3(0.0, 0.002, 0.610), cuff, Vector3(PI * 0.5, 0.0, 0.0))
	# Straps have to clear the *local* sleeve radius, which tapers along its
	# length - a fixed radius buries them at the far end and they read as
	# nothing at all.
	for strap_z in [0.290, 0.610, 0.930]:
		var sleeve_radius := lerpf(0.102, 0.146, clampf((strap_z - 0.110) / 1.000, 0.0, 1.0))
		_add_child_part(arm, _cylinder(sleeve_radius + 0.015, sleeve_radius + 0.013, 0.050), Vector3(0.0, 0.002, strap_z), shade, Vector3(PI * 0.5, 0.0, 0.0))
	_add_child_part(arm, _box(Vector3(0.190, 0.044, 0.620)), Vector3(0.0, 0.094, 0.440), plate, Vector3(-0.03, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		_add_child_part(arm, _box(Vector3(0.026, 0.062, 0.620)), Vector3(side * 0.098, 0.076, 0.440), shade, Vector3(-0.03, 0.0, 0.0))
	for rib_z in [0.250, 0.560]:
		_add_child_part(arm, _box(Vector3(0.202, 0.030, 0.034)), Vector3(0.0, 0.114, rib_z), shade)
		for side in [-1.0, 1.0]:
			_add_child_part(arm, _sphere(0.015), Vector3(side * 0.060, 0.126, rib_z), plate)
	# The module carrying the glove's single lit element, kept outboard so it
	# never sits on the sight line.
	_add_child_part(arm, _box(Vector3(0.048, 0.066, 0.104)), Vector3(0.112, 0.026, 0.074), shade, Vector3(0.0, 0.0, 0.14))
	_add_child_part(arm, _box(Vector3(0.014, 0.022, 0.056)), Vector3(0.140, 0.030, 0.074), tell, Vector3(0.0, 0.0, 0.14))
	# --- Palm mass: metacarpal shell with the thenar and hypothenar pads that
	# stop the hand reading as one rectangular block, and a rubber grip pad on
	# the underside where it actually meets the weapon.
	_add_child_part(root, _box(Vector3(0.212, 0.098, 0.250)), Vector3(0.0, 0.062, 0.062), glove, Vector3(-0.20, 0.0, 0.0))
	_add_child_part(root, _box(Vector3(0.196, 0.034, 0.206)), Vector3(0.0, 0.004, 0.070), shade, Vector3(-0.20, 0.0, 0.0))
	_add_child_part(root, _box(Vector3(0.078, 0.094, 0.142)), Vector3(-0.100, 0.030, 0.046), glove, Vector3(-0.20, 0.0, 0.18))
	_add_child_part(root, _box(Vector3(0.064, 0.086, 0.162)), Vector3(0.098, 0.030, 0.060), glove, Vector3(-0.20, 0.0, -0.14))
	# --- Back of the hand: a two-tier dorsal plate stepping toward the
	# knuckles, on a dark shelf, with a panel seam and side rails. This is the
	# largest flat area on the glove and the one that would look most like a
	# placeholder brick if it were left as a single box.
	_add_child_part(root, _box(Vector3(0.220, 0.032, 0.256)), Vector3(0.0, 0.104, 0.060), shade, Vector3(-0.20, 0.0, 0.0))
	# Two plates with a dark channel between them, not one slab: a single
	# 0.19 x 0.21 rectangle here is the largest unbroken face on the glove and
	# was reading as exactly the flat placeholder brick this redesign exists to
	# get away from.
	_add_child_part(root, _box(Vector3(0.180, 0.038, 0.108)), Vector3(0.0, 0.128, 0.104), plate, Vector3(-0.20, 0.0, 0.0))
	_add_child_part(root, _box(Vector3(0.170, 0.040, 0.086)), Vector3(0.0, 0.136, 0.006), plate, Vector3(-0.20, 0.0, 0.0))
	_add_child_part(root, _box(Vector3(0.142, 0.036, 0.104)), Vector3(0.0, 0.154, -0.024), plate, Vector3(-0.13, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		_add_child_part(root, _box(Vector3(0.020, 0.058, 0.228)), Vector3(side * 0.102, 0.108, 0.056), shade, Vector3(-0.20, 0.0, 0.0))
		_add_child_part(root, _box(Vector3(0.024, 0.026, 0.052)), Vector3(side * 0.088, 0.146, 0.104), plate, Vector3(-0.20, 0.0, 0.0))
	# --- Knuckles: four separately-stepped caps riding a dark bridge, which is
	# the single detail that reads as "armoured glove" from any distance.
	var finger_x := [-0.086, -0.029, 0.028, 0.084]
	var finger_w := [0.056, 0.056, 0.052, 0.046]
	_add_child_part(root, _box(Vector3(0.232, 0.034, 0.078)), Vector3(0.0, 0.116, -0.078), shade, Vector3(-0.10, 0.0, 0.0))
	for index in 4:
		_add_child_part(root, _box(Vector3(finger_w[index] * 0.92, 0.040, 0.064)), Vector3(finger_x[index], 0.150 - float(index) * 0.005, -0.080), plate, Vector3(-0.10, 0.0, 0.0))
	# --- Fingers, curled around the grip axis. Each phalanx is placed on the
	# wrap circle by angle rather than by hand-guessed coordinates, so the curl
	# stays a curl at any radius, and the outer fingers close a little further
	# than the index - a straight four-finger row is the tell of a fake hand.
	var seg_radius := [0.112, 0.104, 0.094]
	var seg_length := [0.108, 0.098, 0.084]
	var seg_angle := [152.0, 204.0, 254.0]
	for index in 4:
		for segment in 3:
			var theta := deg_to_rad(seg_angle[segment]) + float(index) * 0.038
			var radius: float = seg_radius[segment]
			var tangent := atan2(-cos(theta), -sin(theta))
			var thickness := 0.058 - float(segment) * 0.006
			_add_child_part(root, _box(Vector3(finger_w[index], thickness, seg_length[segment])), Vector3(finger_x[index], sin(theta) * radius, cos(theta) * radius), glove, Vector3(tangent, 0.0, 0.0))
			if segment < 2:
				_add_child_part(root, _box(Vector3(finger_w[index] * 0.80, 0.022, seg_length[segment] * 0.86)), Vector3(finger_x[index], sin(theta) * (radius + 0.038), cos(theta) * (radius + 0.038)), plate, Vector3(tangent, 0.0, 0.0))
	# --- Thumb, wrapping the far side. Its plated outer face is what tells the
	# eye which way round the hand is once the fingers are hidden by the weapon.
	_add_child_part(root, _box(Vector3(0.072, 0.068, 0.156)), Vector3(-0.108, 0.020, -0.062), glove, Vector3(0.62, -0.22, 0.0))
	_add_child_part(root, _box(Vector3(0.064, 0.062, 0.122)), Vector3(-0.120, -0.076, 0.012), glove, Vector3(0.10, -0.30, 0.0))
	_add_child_part(root, _box(Vector3(0.026, 0.056, 0.104)), Vector3(-0.152, -0.076, 0.010), plate, Vector3(0.10, -0.30, 0.0))
	if mirrored:
		_mirror_node_x(root)
	return root

## Turns a finished right-hand glove into a genuine left-hand one by mirroring
## it across its own local YZ plane - the plane the grip axis runs through - so
## the thumb, the stepped knuckle order and the wrist break all swap sides
## instead of the hand simply being relocated.
##
## The mirror is applied to the *transform hierarchy*, never as a negative
## scale. Every local transform T becomes F*T*F with F = diag(-1, 1, 1), and
## because F is its own inverse the composition telescopes -
## (F*T1*F)*(F*T2*F) = F*(T1*T2)*F - so mirroring each node locally mirrors the
## whole assembly exactly while every basis keeps a positive determinant. That
## is the whole point: a -1 scale would mirror it too, but it would also flip
## triangle winding, so the glove would render inside-out unless each of its
## ~100 parts carried a back-face-culling override, and the two-material
## glove/cuff signature this function is called with has nowhere to put that.
## Nothing about the mesh data has to change either - box, cylinder, sphere and
## torus are all already symmetric about their own local YZ plane, so only
## where the parts sit and which way they face moves.
func _mirror_node_x(node: Node3D) -> void:
	const FLIP_X := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))
	var local := node.transform
	node.transform = Transform3D(FLIP_X * local.basis * FLIP_X, Vector3(-local.origin.x, local.origin.y, local.origin.z))
	for child in node.get_children():
		var child_node := child as Node3D
		if child_node != null:
			_mirror_node_x(child_node)

func _add_child_part(root: Node3D, mesh: Mesh, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	instance.layers = VIEW_MODEL_LAYER_MASK if _local_camera else 1
	root.add_child(instance)
	return instance

## First-person hands. Parented under `_weapon_rig`, not the character body,
## so they inherit every motion that node already carries - recoil, ADS, hip
## cant, reload sway, melee swing - for free, without a second animation
## system that has to be kept in lockstep with the weapon's.
##
## The Shield class is the one exception on the left hand: it grips the
## shield's own handle bar and is built in `_rebuild_first_person_shield()`
## instead, so it rides the shield's vertical/horizontal/melee-bump motion,
## not the weapon's. That function runs before this one every rebuild and
## this leaves its result alone.
func _build_first_person_hands(kit: Dictionary) -> void:
	_right_hand_root = null
	if not is_shield_class():
		_left_hand_root = null
	if not _local_camera or _weapon_rig == null:
		return
	var glove: Material = kit.get("glove", NuclearMaterials.polymer(Color("1c2126"), 0.62))
	var cuff: Material = kit.get("glove_cuff", NuclearMaterials.polymer(Color("272c26"), 0.58))
	var pose: Dictionary = HAND_GRIP_POSE.get(weapon, HAND_GRIP_POSE[Weapon.RIFLE])
	_right_hand_root = _build_glove_hand(glove, cuff)
	_right_hand_root.name = "TriggerHand"
	_right_hand_root.position = pose.grip
	_right_hand_root.rotation = pose.grip_rot
	_weapon_rig.add_child(_right_hand_root)
	if is_shield_class():
		return
	_hand_support_rest = pose.support
	_left_hand_root = _build_glove_hand(glove, cuff, PISTOL_SUPPORT_MIRRORED and weapon == Weapon.PISTOL)
	_left_hand_root.name = "SupportHand"
	_left_hand_root.position = _hand_support_rest
	_left_hand_root.rotation = pose.support_rot
	# The pistol's off hand is not on the gun at the hip, so it must not be
	# drawn on the frame the weapon is built either - otherwise every weapon
	# swap onto the pistol flashes a whole second arm for one frame before
	# `_process()` folds it away. `_process()` owns it from here.
	if weapon == Weapon.PISTOL:
		_left_hand_root.visible = false
		_left_hand_root.scale = Vector3.ONE * PISTOL_SUPPORT_FOLDED_SCALE
	_weapon_rig.add_child(_left_hand_root)

## Rebuilds the equipped weapon's view model. Every weapon uses the
## realistic metal/polymer PBR materials from NuclearMaterials (the same
## factory the arena and characters use) rather than the flat, cartoon-shaded
## boxes the old single carbine used, and each archetype gets a distinct,
## tapered silhouette instead of a stack of identical cubes.
func _rebuild_weapon_models() -> void:
	_rebuild_first_person_shield()
	if _weapon_root == null or _weapon_rig == null:
		return
	if _local_camera:
		_weapon_root.position = FIRST_PERSON_HIP_ANCHOR
		_weapon_root.scale = Vector3.ONE * FIRST_PERSON_WEAPON_SCALE
		_weapon_rig.rotation = FIRST_PERSON_HIP_RIG_ROTATION
	_weapon_root.rotation = Vector3.ZERO
	_weapon_rig.position = Vector3.ZERO
	for child in _weapon_rig.get_children():
		child.queue_free()
	_weapon_mesh = null
	_weapon_core = null
	_muzzle_flare = null
	_muzzle_light = null
	_magazine_mesh = null
	_rail_slots.clear()
	# Four surface roles, shared by all five weapons so they read as one
	# armoury rather than five unrelated props. The previous palette leaned on
	# metallic 0.92 at a very dark albedo, which - with only a sky probe and no
	# view-model light - resolved to flat black on every weapon.
	var kit := {
		"steel": NuclearMaterials.metal(Color("7f8892"), 0.44),
		"dark": NuclearMaterials.metal(Color("545c66"), 0.52),
		"frame": NuclearMaterials.polymer(Color("3a4149"), 0.70),
		"grip": NuclearMaterials.polymer(Color("24292f"), 0.56),
		"brass": NuclearMaterials.metal(Color("b98b46"), 0.40),
		"wood": NuclearMaterials.polymer(Color("6a4527"), 0.58),
		"accent": NuclearMaterials.emissive(_team_glow().lerp(Color("e6a25b"), 0.4), 1.2),
		# The charge strip on the receiver flank - see _add_charge_strip().
		# Kept distinct from `accent` so its brightness can be tuned against a
		# moving, animated element rather than a static one.
		"rail": NuclearMaterials.emissive(_team_glow().lerp(Color("e6a25b"), 0.4), 1.0),
		"hot": NuclearMaterials.emissive(Color("fff0b0"), 3.6),
		# Deliberately not team-tinted: every player's own hands read the same
		# regardless of Red/Blue, which is a codebase label, not a cosmetic.
		"glove": NuclearMaterials.polymer(Color("1c2126"), 0.62),
		"glove_cuff": NuclearMaterials.polymer(Color("272c26"), 0.58),
	}
	match weapon:
		Weapon.RIFLE:
			_build_rifle_model(kit)
		Weapon.SMG:
			_build_smg_model(kit)
		Weapon.SHOTGUN:
			_build_shotgun_model(kit)
		Weapon.PISTOL:
			if is_shield_class():
				_build_revolver_model(kit)
			else:
				_build_pistol_model(kit)
		Weapon.SNIPER:
			_build_sniper_model(kit)
	if _muzzle_flare != null:
		_muzzle_flare.scale = Vector3.ONE * 0.001
	_build_first_person_hands(kit)

## Weapon-local position of the optical center. Everything a sight is built
## from is placed relative to this point, so the housing can be redesigned
## freely without ever drifting off the ray `optic_tip_head_offset()` derives.
func _optic_tip() -> Vector3:
	return Vector3(RiftWeapons.row(int(weapon)).get("optic_tip_local", Vector3.ZERO))

## Cuts a row of slots into a flat face - the single cheapest way to stop a
## primitive box from reading as a primitive box.
func _add_vent_slots(kit: Dictionary, count: int, span: Vector3, origin: Vector3, step: float) -> void:
	for index in count:
		_add_weapon_part(_box(span), origin + Vector3(0.0, 0.0, step * float(index)), kit.dark)

## A short length of Picatinny rail. Plain metal - see `_add_charge_strip()`
## for why nothing up here is allowed to glow.
func _add_rail(kit: Dictionary, y: float, z_start: float, teeth: int, width: float, step: float) -> void:
	_add_weapon_part(_box(Vector3(width, 0.026, absf(step) * float(teeth) + 0.06)), Vector3(0.0, y, z_start + step * (float(teeth) - 1.0) * 0.5), kit.frame)
	for index in teeth:
		_add_weapon_part(_box(Vector3(width * 0.82, 0.020, 0.030)), Vector3(0.0, y + 0.021, z_start + step * float(index)), kit.dark)

## The fire-sequence tell `_process` animates through `_rail_slots`: a short
## ladder of team-lit segments down the *side* of the receiver.
##
## It deliberately does not live on the top rail. Anything emissive up there
## sits directly beneath the sight window and, seen end-on while aiming, throws
## a bright cream runway straight through the middle of the sight picture -
## which is precisely what it did until this was moved.
func _add_charge_strip(kit: Dictionary, at: Vector3, count: int, step: float) -> void:
	_add_weapon_part(_box(Vector3(0.010, 0.036, absf(step) * float(count) + 0.030)), at, kit.dark)
	for index in count:
		var slide := step * (float(index) - float(count - 1) * 0.5)
		_rail_slots.append(_add_weapon_part(_box(Vector3(0.009, 0.020, 0.026)), at + Vector3(-0.006, 0.0, slide), _own_material(kit.rail)))

## `NuclearMaterials` hands back one cached, shared `ShaderMaterial` per
## parameter set, so any part whose emission `_set_material_glow()` animates
## has to hold a private copy - otherwise one duelist's muzzle flash writes
## into every other duelist's material, and the rail teeth can never show the
## per-tooth fire sequence because they are all literally the same material.
func _own_material(source: Material) -> Material:
	return source.duplicate() if source != null else null

## Turns the plain hot box every `_build_*_model()` already leaves in
## `_muzzle_flare` into an actual muzzle flash: four crossed emissive blades
## (the classic flash-star silhouette every real muzzle flash reads as) plus
## a brief point light, both parented under the flare box so `_process()`'s
## existing `_muzzle_flare.scale` animation drives every part of it together
## and nothing new has to be tracked to keep them in sync.
func _add_muzzle_flash_detail(hot: Material) -> void:
	if _muzzle_flare == null:
		return
	# Blades, spanning *across* the bore and spun about it, which is what makes
	# a star. The previous pass built these as boxes long in Z and then rotated
	# them about Z - five rods pointing down the barrel, coincident, spinning
	# about their own axis, so no star was ever drawn at all.
	#
	# Five of them, at irregular angles and three different lengths: an even
	# four-blade star at one length reads as a plus sign stamped on the screen.
	# The longest pair sits near horizontal, the axis a brake actually vents on.
	var blades := [
		[0.02, 0.021, 0.46], [PI * 0.5 + 0.05, 0.018, 0.34],
		[PI * 0.27, 0.015, 0.30], [PI * 0.72, 0.014, 0.25], [PI * 0.87, 0.012, 0.20],
	]
	for blade in blades:
		var thickness: float = blade[1]
		_add_child_part(_muzzle_flare, _box(Vector3(blade[2], thickness, thickness)), Vector3.ZERO, _own_material(hot), Vector3(0.0, 0.0, blade[0]))
	# Forward plume and core. The star alone is a flat decal facing the camera;
	# a cone thrown down the bore - wide at the crown, tapering to a point out
	# front - plus a bright bead give the flash depth from every angle except
	# dead astern, and it is the part that actually lights the barrel.
	_add_child_part(_muzzle_flare, _tapered_cylinder(0.052, 0.006, 0.32), Vector3(0.0, 0.0, -0.14), _own_material(hot), Vector3(PI * 0.5, 0.0, 0.0))
	_add_child_part(_muzzle_flare, _sphere(0.046), Vector3(0.0, 0.0, -0.01), _own_material(hot))
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "MuzzleLight"
	_muzzle_light.light_color = Color("ffdca0")
	_muzzle_light.omni_range = 3.4
	_muzzle_light.omni_attenuation = 1.6
	_muzzle_light.light_energy = 0.0
	_muzzle_light.light_cull_mask = VIEW_MODEL_LAYER_MASK if _local_camera else 1
	_muzzle_light.shadow_enabled = false
	_muzzle_flare.add_child(_muzzle_light)

## Enclosed trigger group - guard hoop plus the trigger blade inside it.
func _add_trigger_group(kit: Dictionary, at: Vector3, radius: float) -> void:
	_add_weapon_part(_torus(radius, 0.011), at, kit.dark, Vector3(0.0, PI * 0.5, 0.0))
	_add_weapon_part(_box(Vector3(0.016, radius * 1.05, 0.022)), at + Vector3(0.0, radius * 0.30, 0.0), kit.brass, Vector3(0.16, 0.0, 0.0))

## Hooded reflex sight, built as an open frame: base, two uprights and a hood,
## with nothing at all across the middle. The aiming dot is drawn by the HUD at
## exact screen center, so the player looks *through* a real housing instead of
## at an opaque emissive disc parked over the target - which is what the old
## single-lens version did.
func _add_reflex_sight(kit: Dictionary, half_width: float, hood: float, drop: float) -> void:
	var tip := _optic_tip()
	var depth := half_width * 0.66
	# Mount: a clamp block that visibly grips the rail below.
	_add_weapon_part(_box(Vector3(half_width * 2.0 + 0.03, 0.030, depth * 1.9)), tip + Vector3(0.0, -drop - 0.015, 0.0), kit.dark)
	_add_weapon_part(_box(Vector3(half_width * 2.0 + 0.06, 0.022, 0.034)), tip + Vector3(0.0, -drop - 0.034, depth * 0.7), kit.steel)
	_add_weapon_part(_box(Vector3(0.026, 0.030, 0.030)), tip + Vector3(half_width + 0.026, -drop - 0.032, depth * 0.7), kit.brass)
	# Uprights and hood frame the window without crossing it.
	for side in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(0.020, drop + hood, depth * 1.9)), tip + Vector3(side * half_width, (hood - drop) * 0.5, 0.0), kit.dark)
	_add_weapon_part(_box(Vector3(half_width * 2.0 + 0.02, 0.024, depth * 1.9)), tip + Vector3(0.0, hood + 0.012, 0.0), kit.dark)
	# Front and rear lips: a shallow shroud, so the housing has depth from the
	# side and still leaves the sight line completely clear.
	for face in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(half_width * 2.0 + 0.02, 0.020, 0.016)), tip + Vector3(0.0, hood - 0.004, face * depth * 0.95), kit.steel)
	# Emitter housing on the front lower lip, and its team-lit indicator.
	_add_weapon_part(_box(Vector3(0.034, 0.030, 0.036)), tip + Vector3(0.0, -drop + 0.026, -depth * 0.86), kit.dark)
	_weapon_core = _add_weapon_part(_box(Vector3(0.020, 0.016, 0.014)), tip + Vector3(0.0, -drop + 0.026, -depth * 1.02), _own_material(kit.accent))

## Trench-gun sight picture: a rear ghost ring you look *through*, and a small
## brass bead a metre further down the barrel. The two are deliberately sized
## against their distance from the eye - the ring subtends about four times the
## bead - so aimed they read as two objects at two depths instead of one slab.
func _add_ghost_ring_sights(kit: Dictionary, rear_z: float, front_z: float) -> void:
	var tip := _optic_tip()
	var aperture := 0.058
	# Rear: open ring on a stem. `TorusMesh` is built lying flat with its hole on
	# the Y axis, so it has to be stood upright to face the eye - unrotated it
	# renders edge-on as a bar straight across the sight line. Nothing crosses
	# the hole, so the target stays visible inside it.
	_add_weapon_part(_torus(aperture, 0.011), Vector3(0.0, tip.y, rear_z), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.026, 0.050, 0.030)), Vector3(0.0, tip.y - 0.094, rear_z), kit.dark)
	_add_weapon_part(_box(Vector3(0.058, 0.016, 0.048)), Vector3(0.0, tip.y - 0.054, rear_z), kit.steel)
	# Protective ears, parked outboard of the ring so they never enter the hole.
	for side in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(0.013, 0.070, 0.026)), Vector3(side * 0.076, tip.y - 0.010, rear_z), kit.dark)
	# Front: a low ramp, a slim post, and the bead sitting proud on top of it.
	_add_weapon_part(_box(Vector3(0.036, 0.020, 0.070)), Vector3(0.0, tip.y - 0.048, front_z), kit.dark)
	_add_weapon_part(_box(Vector3(0.013, 0.036, 0.018)), Vector3(0.0, tip.y - 0.026, front_z), kit.dark)
	_add_weapon_part(_sphere(0.016), Vector3(0.0, tip.y, front_z), kit.brass)
	for side in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(0.011, 0.042, 0.020)), Vector3(side * 0.028, tip.y - 0.020, front_z), kit.dark)

## Pistol three-dot irons. The rear notch gap is widened against its shorter
## distance to the eye so it still frames the front post with daylight either
## side; the post is the narrower, nearer-reading element you focus on.
func _add_notch_sights(kit: Dictionary, rear_z: float, front_z: float) -> void:
	var tip := _optic_tip()
	# Rear: two square blades with a 0.026 notch of daylight between them.
	_add_weapon_part(_box(Vector3(0.062, 0.014, 0.022)), Vector3(0.0, tip.y - 0.041, rear_z), kit.dark)
	for side in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(0.014, 0.034, 0.018)), Vector3(side * 0.022, tip.y - 0.017, rear_z), kit.dark)
		_add_weapon_part(_sphere(0.0045), Vector3(side * 0.022, tip.y - 0.016, rear_z + 0.010), kit.brass)
	# Front: a taller, narrower post on its own ramp, dotted to match.
	_add_weapon_part(_box(Vector3(0.030, 0.016, 0.028)), Vector3(0.0, tip.y - 0.048, front_z), kit.dark)
	_add_weapon_part(_box(Vector3(0.014, 0.044, 0.020)), Vector3(0.0, tip.y - 0.022, front_z), kit.dark)
	_add_weapon_part(_sphere(0.008), Vector3(0.0, tip.y - 0.013, front_z + 0.011), kit.brass)

## Full telescopic sight: tube, both bells, three turrets and two ring mounts.
## The ocular end is left open - the HUD's vignette is what turns this into a
## scope picture, and a solid lens here would only occlude the target.
func _add_scope(kit: Dictionary, tube_radius: float, ocular_z: float, objective_z: float) -> void:
	var tip := _optic_tip()
	var axis := Vector3(0.0, tip.y, 0.0)
	var length := ocular_z - objective_z
	var mid := (ocular_z + objective_z) * 0.5
	_add_weapon_part(_tube(tube_radius, tube_radius, length), axis + Vector3(0.0, 0.0, mid), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	# Ocular bell, with a brass eyepiece ring so the near end catches light.
	_add_weapon_part(_tube(tube_radius * 1.34, tube_radius * 1.08, 0.16), axis + Vector3(0.0, 0.0, ocular_z + 0.06), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_torus(tube_radius * 1.30, 0.014), axis + Vector3(0.0, 0.0, ocular_z + 0.135), kit.brass)
	# Objective bell and its sunshade lip.
	_add_weapon_part(_tube(tube_radius * 1.10, tube_radius * 1.50, 0.22), axis + Vector3(0.0, 0.0, objective_z - 0.08), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_torus(tube_radius * 1.48, 0.012), axis + Vector3(0.0, 0.0, objective_z - 0.19), kit.steel)
	# Elevation, windage and parallax turrets - the detail that separates a
	# scope from a length of pipe.
	var turret_z := mid - 0.02
	_add_weapon_part(_cylinder(tube_radius * 0.70, tube_radius * 0.78, 0.080), axis + Vector3(0.0, tube_radius + 0.040, turret_z), kit.dark)
	_add_weapon_part(_cylinder(tube_radius * 0.60, tube_radius * 0.60, 0.020), axis + Vector3(0.0, tube_radius + 0.090, turret_z), kit.brass)
	for side in [-1.0, 1.0]:
		_add_weapon_part(_cylinder(tube_radius * 0.58, tube_radius * 0.66, 0.070), axis + Vector3(side * (tube_radius + 0.035), 0.0, turret_z), kit.dark, Vector3(0.0, 0.0, PI * 0.5))
	# Ring mounts, clamped down onto the receiver rail.
	for ring_z in [objective_z + 0.16, ocular_z - 0.16]:
		_add_weapon_part(_torus(tube_radius + 0.006, 0.026), axis + Vector3(0.0, 0.0, ring_z), kit.dark)
		_add_weapon_part(_box(Vector3(0.10, tip.y * 0.52, 0.058)), Vector3(0.0, tip.y - tube_radius - tip.y * 0.26, ring_z), kit.dark)
	_weapon_core = _add_weapon_part(_box(Vector3(0.016, 0.026, 0.052)), axis + Vector3(tube_radius * 0.92, tube_radius * 0.58, ocular_z - 0.30), _own_material(kit.accent))

func _build_rifle_model(kit: Dictionary) -> void:
	# Rift Carbine - AR-pattern carbine. Reads on its two-part receiver, the
	# angled magazine, a long slotted handguard and a reflex sight up on the
	# rail; the buffer tube and stock give it the length an SMG must not have.
	_weapon_mesh = _add_weapon_part(_box(Vector3(0.115, 0.135, 0.62)), Vector3(0.0, 0.075, -0.10), kit.steel)
	_add_weapon_part(_box(Vector3(0.105, 0.120, 0.46)), Vector3(0.0, -0.030, -0.02), kit.frame)
	_add_weapon_part(_box(Vector3(0.012, 0.062, 0.150)), Vector3(0.063, 0.078, -0.04), kit.brass)
	# Handguard: slotted tube, gas block, barrel, brake.
	_add_weapon_part(_box(Vector3(0.112, 0.112, 0.70)), Vector3(0.0, 0.055, -0.62), kit.frame)
	_add_vent_slots(kit, 4, Vector3(0.126, 0.020, 0.052), Vector3(0.0, 0.100, -0.86), 0.140)
	_add_vent_slots(kit, 4, Vector3(0.126, 0.020, 0.052), Vector3(0.0, 0.010, -0.86), 0.140)
	_add_weapon_part(_box(Vector3(0.070, 0.078, 0.090)), Vector3(0.0, 0.108, -0.99), kit.dark)
	_add_weapon_part(_tapered_cylinder(0.027, 0.031, 0.34), Vector3(0.0, 0.055, -1.14), kit.steel, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_cylinder(0.043, 0.043, 0.10), Vector3(0.0, 0.055, -1.33), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_torus(0.036, 0.010), Vector3(0.0, 0.055, -1.30), kit.steel)
	# Magazine, grip, trigger group.
	_magazine_mesh = _add_weapon_part(_box(Vector3(0.075, 0.34, 0.135)), Vector3(0.0, -0.255, -0.05), kit.frame, Vector3(-0.13, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.090, 0.032, 0.150)), Vector3(0.0, -0.428, -0.028), kit.dark, Vector3(-0.13, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.075, 0.220, 0.105)), Vector3(0.0, -0.165, 0.140), kit.grip, Vector3(-0.36, 0.0, 0.0))
	_add_trigger_group(kit, Vector3(0.0, -0.078, 0.035), 0.052)
	# Buffer tube and collapsible stock.
	_add_weapon_part(_cylinder(0.044, 0.044, 0.34), Vector3(0.0, 0.058, 0.335), kit.steel, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.088, 0.155, 0.30)), Vector3(0.0, 0.020, 0.420), kit.frame)
	_add_weapon_part(_box(Vector3(0.098, 0.205, 0.042)), Vector3(0.0, 0.000, 0.578), kit.grip)
	# Charging handle and top rail.
	_add_weapon_part(_box(Vector3(0.092, 0.028, 0.060)), Vector3(0.0, 0.132, 0.215), kit.brass)
	_add_rail(kit, 0.150, -0.60, 6, 0.098, 0.140)
	_add_charge_strip(kit, Vector3(-0.062, 0.030, -0.10), 5, 0.078)
	_add_reflex_sight(kit, 0.098, 0.088, 0.104)
	_muzzle_flare = _add_weapon_part(_box(Vector3(0.070, 0.070, 0.100)), Vector3(0.0, 0.055, -1.41), _own_material(kit.hot))
	_add_muzzle_flash_detail(kit.hot)

func _build_smg_model(kit: Dictionary) -> void:
	# Riftline SMG - MP7 pattern. Deliberately stubby: magazine housed in the
	# grip rather than ahead of it, a vertical foregrip, a skeleton stock and a
	# short rail. Half the carbine's length at a glance.
	_weapon_mesh = _add_weapon_part(_box(Vector3(0.100, 0.145, 0.46)), Vector3(0.0, 0.030, -0.10), kit.frame)
	_add_weapon_part(_box(Vector3(0.106, 0.050, 0.44)), Vector3(0.0, 0.116, -0.10), kit.steel)
	_add_weapon_part(_box(Vector3(0.012, 0.048, 0.110)), Vector3(0.058, 0.032, -0.06), kit.brass)
	# Grip-housed magazine.
	_magazine_mesh = _add_weapon_part(_box(Vector3(0.078, 0.260, 0.115)), Vector3(0.0, -0.155, 0.062), kit.grip, Vector3(-0.19, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.090, 0.028, 0.132)), Vector3(0.0, -0.288, 0.087), kit.dark, Vector3(-0.19, 0.0, 0.0))
	_add_trigger_group(kit, Vector3(0.0, -0.052, -0.020), 0.048)
	# Shrouded barrel and vertical foregrip.
	_add_weapon_part(_box(Vector3(0.086, 0.086, 0.34)), Vector3(0.0, 0.030, -0.50), kit.frame)
	_add_vent_slots(kit, 3, Vector3(0.098, 0.018, 0.046), Vector3(0.0, 0.066, -0.62), 0.110)
	_add_weapon_part(_tapered_cylinder(0.021, 0.024, 0.18), Vector3(0.0, 0.030, -0.76), kit.steel, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_cylinder(0.032, 0.032, 0.070), Vector3(0.0, 0.030, -0.86), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.052, 0.190, 0.068)), Vector3(0.0, -0.118, -0.455), kit.grip, Vector3(0.11, 0.0, 0.0))
	# Skeleton stock: two struts and a butt plate, folded alongside the body.
	for side in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(0.017, 0.017, 0.34)), Vector3(side * 0.054, 0.098, 0.335), kit.steel)
	_add_weapon_part(_box(Vector3(0.128, 0.098, 0.030)), Vector3(0.0, 0.098, 0.510), kit.frame)
	_add_rail(kit, 0.150, -0.30, 4, 0.092, 0.120)
	_add_charge_strip(kit, Vector3(-0.055, 0.020, -0.10), 4, 0.072)
	_add_reflex_sight(kit, 0.084, 0.076, 0.090)
	_muzzle_flare = _add_weapon_part(_box(Vector3(0.058, 0.058, 0.080)), Vector3(0.0, 0.030, -0.93), _own_material(kit.hot))
	_add_muzzle_flash_detail(kit.hot)

func _build_shotgun_model(kit: Dictionary) -> void:
	# S1897 Pump - trench gun. Two parallel tubes, a wood pump and stock, the
	# exposed hammer the 1897 is known for, and a ventilated heat shield. No
	# optic: it aims over a brass bead, which is the whole point of the look.
	_weapon_mesh = _add_weapon_part(_box(Vector3(0.105, 0.155, 0.40)), Vector3(0.0, 0.020, 0.020), kit.steel)
	_add_weapon_part(_box(Vector3(0.108, 0.055, 0.26)), Vector3(0.0, 0.098, 0.020), kit.dark)
	# Barrel over magazine tube - the signature double-tube silhouette.
	_add_weapon_part(_cylinder(0.042, 0.044, 1.00), Vector3(0.0, 0.095, -0.62), kit.steel, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_cylinder(0.031, 0.031, 0.86), Vector3(0.0, -0.012, -0.55), kit.steel, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_torus(0.044, 0.011), Vector3(0.0, 0.095, -0.98), kit.dark)
	# Ventilated heat shield over the barrel.
	_add_weapon_part(_box(Vector3(0.100, 0.042, 0.52)), Vector3(0.0, 0.150, -0.62), kit.dark)
	for side in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(0.012, 0.072, 0.52)), Vector3(side * 0.048, 0.118, -0.62), kit.dark)
	_add_vent_slots(kit, 4, Vector3(0.108, 0.024, 0.048), Vector3(0.0, 0.128, -0.80), 0.120)
	# Wood pump and straight-wrist stock.
	_add_weapon_part(_box(Vector3(0.096, 0.100, 0.26)), Vector3(0.0, -0.012, -0.44), kit.wood)
	_add_vent_slots(kit, 3, Vector3(0.104, 0.014, 0.028), Vector3(0.0, -0.012, -0.52), 0.070)
	_add_weapon_part(_box(Vector3(0.100, 0.155, 0.46)), Vector3(0.0, -0.030, 0.440), kit.wood, Vector3(0.055, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.110, 0.200, 0.036)), Vector3(0.0, -0.056, 0.680), kit.dark, Vector3(0.055, 0.0, 0.0))
	_add_trigger_group(kit, Vector3(0.0, -0.068, -0.055), 0.050)
	# Exposed hammer, and a brass shell riding the loading port during reload.
	_add_weapon_part(_box(Vector3(0.028, 0.075, 0.045)), Vector3(0.0, 0.118, 0.196), kit.dark, Vector3(-0.30, 0.0, 0.0))
	_magazine_mesh = _add_weapon_part(_cylinder(0.026, 0.026, 0.100), Vector3(0.0, -0.048, -0.100), kit.brass, Vector3(PI * 0.5, 0.0, 0.0))
	_weapon_core = _add_weapon_part(_box(Vector3(0.014, 0.038, 0.090)), Vector3(0.056, 0.020, 0.130), _own_material(kit.accent))
	_add_charge_strip(kit, Vector3(-0.058, 0.014, 0.020), 4, 0.070)
	_add_ghost_ring_sights(kit, 0.060, -1.08)
	_muzzle_flare = _add_weapon_part(_box(Vector3(0.086, 0.086, 0.100)), Vector3(0.0, 0.095, -1.16), _own_material(kit.hot))
	_add_muzzle_flash_detail(kit.hot)

func _build_pistol_model(kit: Dictionary) -> void:
	# Sidearm 9 - compact striker-fired 9mm. Small, high-gripped, slide
	# serrations and three-dot irons. It must never read as a short carbine.
	_weapon_mesh = _add_weapon_part(_box(Vector3(0.086, 0.104, 0.44)), Vector3(0.0, 0.075, -0.10), kit.steel)
	for index in 4:
		_add_weapon_part(_box(Vector3(0.090, 0.076, 0.013)), Vector3(0.0, 0.075, 0.030 + 0.032 * float(index)), kit.dark)
	_add_weapon_part(_box(Vector3(0.080, 0.076, 0.34)), Vector3(0.0, -0.004, -0.060), kit.frame)
	_add_weapon_part(_box(Vector3(0.050, 0.022, 0.140)), Vector3(0.0, -0.040, -0.240), kit.dark)
	_add_weapon_part(_cylinder(0.025, 0.025, 0.060), Vector3(0.0, 0.075, -0.350), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.076, 0.235, 0.100)), Vector3(0.0, -0.152, 0.100), kit.grip, Vector3(-0.27, 0.0, 0.0))
	_magazine_mesh = _add_weapon_part(_box(Vector3(0.086, 0.026, 0.116)), Vector3(0.0, -0.272, 0.135), kit.dark, Vector3(-0.27, 0.0, 0.0))
	_add_trigger_group(kit, Vector3(0.0, -0.054, -0.012), 0.046)
	_add_weapon_part(_box(Vector3(0.012, 0.030, 0.060)), Vector3(0.046, 0.024, 0.055), kit.brass)
	# Breech face. Aimed, the slide is seen square-on from behind, where it was
	# otherwise one blank grey rectangle across the bottom half of the frame.
	_add_weapon_part(_box(Vector3(0.062, 0.078, 0.014)), Vector3(0.0, 0.075, 0.118), kit.dark)
	for serration_x in [-0.030, 0.030]:
		_add_weapon_part(_box(Vector3(0.011, 0.086, 0.020)), Vector3(serration_x, 0.075, 0.116), kit.grip)
	_add_weapon_part(_box(Vector3(0.030, 0.020, 0.016)), Vector3(0.0, 0.040, 0.117), kit.grip)
	_weapon_core = _add_weapon_part(_box(Vector3(0.012, 0.026, 0.060)), Vector3(-0.045, -0.012, -0.030), _own_material(kit.accent))
	_add_charge_strip(kit, Vector3(-0.046, 0.018, -0.050), 3, 0.058)
	_add_notch_sights(kit, 0.140, -0.300)
	_muzzle_flare = _add_weapon_part(_box(Vector3(0.048, 0.048, 0.060)), Vector3(0.0, 0.075, -0.400), _own_material(kit.hot))
	_add_muzzle_flash_detail(kit.hot)

## Shield class's sidearm: a break-top/DA revolver instead of the Runner's
## semi-auto Sidearm 9, so the two pistol carriers read as different weapons
## even though both use the shared RiftWeapons.PISTOL stat row. No magazine
## mesh - a revolver has none - because its reload happens tucked in behind
## the vertical shield where the mechanism is never on screen anyway; see
## `_process()`'s SHIELD_RELOAD_WEAPON_POSITION branch.
func _build_revolver_model(kit: Dictionary) -> void:
	_weapon_mesh = _add_weapon_part(_box(Vector3(0.072, 0.090, 0.28)), Vector3(0.0, 0.075, 0.030), kit.steel)
	_add_weapon_part(_tapered_cylinder(0.024, 0.030, 0.34), Vector3(0.0, 0.083, -0.250), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	# Exposed chamber drum, with its six chambers as separate cylinders -
	# the one part of a revolver a semi-auto never has, and the read that
	# sells "revolver" at a glance.
	_add_weapon_part(_cylinder(0.058, 0.058, 0.086), Vector3(0.0, 0.077, -0.068), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	for chamber_index in 6:
		var theta := TAU * float(chamber_index) / 6.0
		_add_weapon_part(_cylinder(0.010, 0.010, 0.090), Vector3(cos(theta) * 0.036, 0.077 + sin(theta) * 0.036, -0.068), kit.brass, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.020, 0.030, 0.130)), Vector3(0.0, 0.090, -0.005), kit.dark)
	# Exposed spur hammer - a semi-auto's slide has no equivalent silhouette.
	_add_weapon_part(_box(Vector3(0.014, 0.040, 0.020)), Vector3(0.0, 0.140, 0.085), kit.steel, Vector3(-0.25, 0.0, 0.0))
	_add_weapon_part(_box(Vector3(0.076, 0.220, 0.098)), Vector3(0.0, -0.130, 0.135), kit.wood, Vector3(-0.30, 0.0, 0.0))
	_add_trigger_group(kit, Vector3(0.0, -0.035, 0.020), 0.044)
	_add_notch_sights(kit, 0.120, -0.270)
	_weapon_core = _add_weapon_part(_box(Vector3(0.012, 0.020, 0.050)), Vector3(-0.040, 0.010, -0.010), _own_material(kit.accent))
	_muzzle_flare = _add_weapon_part(_box(Vector3(0.044, 0.044, 0.056)), Vector3(0.0, 0.083, -0.420), _own_material(kit.hot))
	_add_muzzle_flash_detail(kit.hot)

func _build_sniper_model(kit: Dictionary) -> void:
	# Longview Mk1 - Halo Infinite S7 as the named reference. Very long, heavy
	# chassis, big turreted scope riding high on ring mounts, ported brake and
	# a deployed bipod. Nothing else in the armoury is anywhere near this size.
	_weapon_mesh = _add_weapon_part(_box(Vector3(0.115, 0.160, 0.80)), Vector3(0.0, 0.000, 0.020), kit.steel)
	_add_weapon_part(_box(Vector3(0.092, 0.046, 0.92)), Vector3(0.0, -0.092, 0.000), kit.dark)
	# Free-floated barrel under a slotted shroud, ported muzzle brake.
	_add_weapon_part(_box(Vector3(0.100, 0.100, 0.52)), Vector3(0.0, 0.045, -0.62), kit.frame)
	_add_vent_slots(kit, 3, Vector3(0.114, 0.020, 0.052), Vector3(0.0, 0.086, -0.76), 0.130)
	_add_weapon_part(_tapered_cylinder(0.031, 0.043, 1.10), Vector3(0.0, 0.045, -0.95), kit.steel, Vector3(PI * 0.5, 0.0, 0.0))
	_add_weapon_part(_cylinder(0.054, 0.054, 0.140), Vector3(0.0, 0.045, -1.56), kit.dark, Vector3(PI * 0.5, 0.0, 0.0))
	for port_z in [-1.525, -1.585]:
		_add_weapon_part(_box(Vector3(0.126, 0.026, 0.030)), Vector3(0.0, 0.045, port_z), kit.dark)
	# Chassis stock: cheek riser, butt pad, pistol grip.
	_add_weapon_part(_box(Vector3(0.095, 0.170, 0.52)), Vector3(0.0, -0.030, 0.620), kit.frame)
	_add_weapon_part(_box(Vector3(0.086, 0.060, 0.30)), Vector3(0.0, 0.076, 0.560), kit.grip)
	_add_weapon_part(_box(Vector3(0.110, 0.210, 0.046)), Vector3(0.0, -0.050, 0.895), kit.grip)
	_add_weapon_part(_box(Vector3(0.076, 0.220, 0.100)), Vector3(0.0, -0.180, 0.300), kit.grip, Vector3(-0.32, 0.0, 0.0))
	_add_trigger_group(kit, Vector3(0.0, -0.092, 0.180), 0.050)
	# Detachable box magazine.
	_magazine_mesh = _add_weapon_part(_box(Vector3(0.076, 0.250, 0.160)), Vector3(0.0, -0.215, -0.080), kit.frame)
	_add_weapon_part(_box(Vector3(0.090, 0.028, 0.176)), Vector3(0.0, -0.352, -0.080), kit.dark)
	# Bolt handle - the one asymmetric feature on the whole armoury.
	_add_weapon_part(_cylinder(0.015, 0.015, 0.120), Vector3(0.118, 0.050, 0.200), kit.steel, Vector3(0.0, 0.0, PI * 0.5))
	_add_weapon_part(_sphere(0.028), Vector3(0.178, 0.050, 0.200), kit.brass)
	# Deployed bipod.
	for side in [-1.0, 1.0]:
		_add_weapon_part(_box(Vector3(0.018, 0.300, 0.018)), Vector3(side * 0.075, -0.230, -1.020), kit.dark, Vector3(0.0, 0.0, side * 0.30))
		_add_weapon_part(_box(Vector3(0.046, 0.016, 0.030)), Vector3(side * 0.120, -0.375, -1.020), kit.dark)
	_add_rail(kit, 0.088, -0.24, 5, 0.096, 0.130)
	_add_charge_strip(kit, Vector3(-0.062, -0.020, 0.020), 5, 0.086)
	_add_scope(kit, 0.056, 0.300, -0.520)
	_muzzle_flare = _add_weapon_part(_box(Vector3(0.062, 0.062, 0.090)), Vector3(0.0, 0.045, -1.66), _own_material(kit.hot))
	_add_muzzle_flash_detail(kit.hot)

func _add_weapon_part(mesh: Mesh, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	instance.layers = VIEW_MODEL_LAYER_MASK if _local_camera else 1
	# Parts hang off the rig, not the root: the root is animated every frame by
	# ADS/recoil/obstruction, the rig carries the static hip pose.
	var parent: Node3D = _weapon_rig if _weapon_rig != null else _weapon_root
	parent.add_child(instance)
	return instance

func _add_body_part(mesh: Mesh, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	instance.layers = 1
	if _body_visual_root != null:
		_body_visual_root.add_child(instance)
	else:
		add_child(instance)
	return instance

func _add_head_part(mesh: Mesh, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	head.add_child(instance)

func _box(dimensions: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return mesh

## An open-ended cylinder. Anything the aim ray passes through has to be a tube
## and not a cylinder: a capped `CylinderMesh` sitting on the sight line puts a
## solid disc squarely over the target, which is exactly what the scope's
## ocular did before this.
func _tube(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := _cylinder(top_radius, bottom_radius, height)
	mesh.cap_top = false
	mesh.cap_bottom = false
	return mesh

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh

func _cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	return mesh

## A cylinder with distinct top/bottom radii - used throughout the weapon
## models below so barrels and handguards taper instead of reading as
## uniform-diameter tubes.
func _tapered_cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	return _cylinder(top_radius, bottom_radius, height)

func _material(color: Color, emission_energy: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PULP_LIT
	material.set_shader_parameter("base_tint", color)
	material.set_shader_parameter("shadow_tint", Color("16253d").lerp(color, 0.2))
	material.set_shader_parameter("rim_tint", _team_glow())
	material.set_shader_parameter("rim_strength", 0.24)
	material.set_shader_parameter("glow_strength", emission_energy)
	material.set_shader_parameter("brush_scale", 2.4)
	return material

func _set_material_glow(instance: MeshInstance3D, glow: float) -> void:
	if instance == null or not (instance.material_override is ShaderMaterial):
		return
	var material := instance.material_override as ShaderMaterial
	if material.shader == NuclearMaterials.NUCLEAR_PBR:
		material.set_shader_parameter("emission_energy", glow)
	else:
		material.set_shader_parameter("glow_strength", glow)
