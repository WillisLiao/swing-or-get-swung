class_name BotDuelist
extends Duelist

## Objective-aware offline squad AI for Nuclear Rush.
##
## Combat remains opportunistic: bots keep moving toward their current squad
## goal while aiming and fighting. Objective decisions are deterministic per
## squad slot so a 4-player team naturally produces a runner, escort, defender,
## and raider without networking or saved AI state.

enum ObjectiveRole { RUNNER, ESCORT, DEFENDER, RAIDER }

# Mirrors RiftlineMatch.CoreState without introducing a global-class cycle
# (RiftlineMatch already references BotDuelist for bot auto-respawn).
const CORE_AT_CENTER := 0
const CORE_CARRIED := 1
const CORE_DROPPED := 2
const CORE_INSTALLED := 3
const CORE_RESPAWNING := 4

const OBJECTIVE_INTERACT_RADIUS := 2.75
const COMBAT_ACQUIRE_DISTANCE := 36.0
const OBJECTIVE_STOP_RADIUS := 1.35

var _target: Duelist
var _enemies: Array[Duelist] = []
var _decision_remaining := 0.0
var _reaction_remaining := 0.0
var _tracking_remaining := 0.0
var _shot_cadence_remaining := 0.0
var _burst_remaining := 0.0
var _target_locked := false
var _last_target_velocity := Vector3.ZERO
var _aim_offset := Vector3.ZERO
var _move_goal := Vector2.ZERO
var _random := RandomNumberGenerator.new()
## `RiftlineMap.route_toward()` walks every route node against every route
## blocker/solid when the direct line is obstructed - real CPU cost, and
## unconditional every physics tick for all seven bots was flagged as the
## likely-general-lag suspect in
## `handoffs/NEXT-SESSION-performance-regression.md`. The steering direction
## itself is still recomputed every tick from the cached waypoint below (a
## bot never looks frozen), only the expensive "which via-node to route
## through" decision is throttled.
const ROUTE_RECOMPUTE_SECONDS := 0.2
var _route_recompute_remaining := 0.0
var _route_waypoint := Vector3.ZERO
var _route_goal_cache := Vector3.ZERO
var _route_waypoint_valid := false
var _last_seen_position := Vector3.ZERO
var _last_seen_remaining := 0.0
var _stuck_elapsed := 0.0
var _last_motion_position := Vector3.ZERO
var _unstick_remaining := 0.0
var _unstick_sign := 1.0
var _unstick_jump_pending := false
var _objective_context: Dictionary = {}
var _objective_role: ObjectiveRole = ObjectiveRole.RUNNER
var _objective_intent := "seek_core"
var _objective_goal := Vector3.ZERO
var _wants_objective_interact := false
var _route_map: RiftlineMap

func set_opponents(enemies: Array[Duelist]) -> void:
	_enemies = enemies.duplicate()
	_select_target()

func configure_objective_ai(route_map: RiftlineMap, squad_index: int) -> void:
	_route_map = route_map
	_objective_role = posmod(squad_index, ObjectiveRole.size()) as ObjectiveRole
	_unstick_sign = -1.0 if squad_index % 2 == 0 else 1.0

## Expected keys: `core_state`, `core_position`, `core_carrier_id`,
## `core_carrier_team`, `installed_team`, `own_pad`, and `enemy_pad`.
func set_objective_context(context: Dictionary) -> void:
	_objective_context = context.duplicate(true)

func wants_objective_interact() -> bool:
	return _wants_objective_interact and match_active and not eliminated

func objective_plan() -> Dictionary:
	var core_state := int(_objective_context.get("core_state", CORE_AT_CENTER))
	var core_position: Vector3 = _objective_context.get("core_position", Vector3.ZERO)
	var carrier_id := str(_objective_context.get("core_carrier_id", ""))
	var carrier_team := int(_objective_context.get("core_carrier_team", int(team)))
	var installed_team := int(_objective_context.get("installed_team", int(team)))
	var own_pad: Vector3 = _objective_context.get("own_pad", position)
	var enemy_pad: Vector3 = _objective_context.get("enemy_pad", position)
	var plan := {
		"intent": "seek_core",
		"goal": core_position,
		"interact": false,
	}

	match core_state:
		CORE_CARRIED:
			if carrier_id == actor_id:
				plan.intent = "deliver_core"
				plan.goal = own_pad
				plan.interact = global_position.distance_to(own_pad) <= OBJECTIVE_INTERACT_RADIUS
			elif carrier_team == int(team):
				if _objective_role == ObjectiveRole.DEFENDER:
					plan.intent = "prepare_defense"
					plan.goal = own_pad.lerp(core_position, 0.20) + _formation_offset(2.0)
				else:
					plan.intent = "escort_carrier"
					plan.goal = core_position + _formation_offset(3.5)
			else:
				plan.intent = "intercept_carrier"
				plan.goal = core_position + _formation_offset(1.6)
		CORE_INSTALLED:
			if installed_team == int(team):
				plan.intent = "defend_launch"
				plan.goal = own_pad + _formation_offset(4.0)
			else:
				plan.intent = "cancel_launch"
				plan.goal = enemy_pad
				plan.interact = global_position.distance_to(enemy_pad) <= OBJECTIVE_INTERACT_RADIUS
		CORE_RESPAWNING:
			plan.intent = "reset_formation"
			plan.goal = own_pad.lerp(Vector3.ZERO, 0.42) + _formation_offset(3.0)
		CORE_AT_CENTER, CORE_DROPPED:
			match _objective_role:
				ObjectiveRole.RUNNER:
					plan.intent = "claim_core"
					plan.goal = core_position
				ObjectiveRole.ESCORT:
					plan.intent = "screen_core"
					plan.goal = core_position + _formation_offset(4.5)
				ObjectiveRole.DEFENDER:
					plan.intent = "hold_home_lane"
					plan.goal = own_pad.lerp(core_position, 0.36) + _formation_offset(3.0)
				ObjectiveRole.RAIDER:
					plan.intent = "contest_core"
					plan.goal = core_position + _formation_offset(1.4)
	return plan

func ai_state() -> Dictionary:
	return {
		"role": role_name(_objective_role),
		"intent": _objective_intent,
		"goal": _objective_goal,
		"wants_interact": wants_objective_interact(),
		"target_id": _target.actor_id if _target != null and is_instance_valid(_target) else "",
	}

static func role_name(role: ObjectiveRole) -> String:
	match role:
		ObjectiveRole.ESCORT:
			return "escort"
		ObjectiveRole.DEFENDER:
			return "defender"
		ObjectiveRole.RAIDER:
			return "raider"
		_:
			return "runner"

func _ready() -> void:
	_random.randomize()
	_last_motion_position = global_position

func hold_opening_position(_seconds: float) -> void:
	_target_locked = false
	_reaction_remaining = 0.0
	_tracking_remaining = 0.0
	_move_goal = Vector2.ZERO
	_last_seen_remaining = 0.0
	_wants_objective_interact = false

func _physics_process(delta: float) -> void:
	if eliminated:
		_wants_objective_interact = false
		return
	_tick_timers(delta)
	_update_stuck_recovery(delta)
	if not match_active:
		_target_locked = false
		_wants_objective_interact = false
		_move_goal = Vector2.ZERO
		drive(Vector2.ZERO, false, false, delta)
		return

	var plan: Dictionary = objective_plan()
	_objective_intent = str(plan.get("intent", "seek_core"))
	_objective_goal = plan.get("goal", global_position)
	_wants_objective_interact = bool(plan.get("interact", false))

	if _decision_remaining <= 0.0:
		_select_target()
		_decision_remaining = 0.18

	if _target == null:
		_face_objective(delta)
		_move_goal = _objective_move_input()
		set_combat_pose(false, delta)
		drive(_move_goal, false, _take_unstick_jump(), delta)
		return

	var has_los := _has_line_of_sight()
	var target_position := _target.global_position if has_los else _last_seen_position
	if not has_los and _last_seen_remaining <= 0.0:
		_target = null
		_target_locked = false
		_face_objective(delta)
		_move_goal = _objective_move_input()
		set_combat_pose(false, delta)
		drive(_move_goal, false, _take_unstick_jump(), delta)
		return

	var toward := target_position - global_position
	toward.y = 0.0
	var distance := toward.length()
	if distance < 0.01:
		return
	var desired_yaw := atan2(-toward.x, -toward.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, delta * 4.4))
	var aim_target := target_position + Vector3.UP * 0.98
	head.rotation.x = clampf(lerpf(head.rotation.x, _pitch_to(aim_target), delta * 4.0), -0.45, 0.4)

	if has_los:
		_last_seen_position = _target.global_position
		_last_seen_remaining = 0.72
		_update_target_lock(delta)
	else:
		_target_locked = false
		_reaction_remaining = 0.0
		_tracking_remaining = 0.0
	_move_goal = _combat_move_input(distance, has_los)
	set_combat_pose(_target_locked and _tracking_remaining <= 0.0, delta)
	drive(_move_goal, false, _take_unstick_jump(), delta)

	if not has_los or not _target_locked or _reaction_remaining > 0.0 or _tracking_remaining > 0.0 or _shot_cadence_remaining > 0.0:
		return
	var melee_range := float(RiftWeapons.row(int(weapon)).melee_range)
	if distance <= melee_range:
		melee_attack()
		return
	if _burst_remaining <= 0.0:
		_aim_offset = Vector3(_random.randf_range(-0.46, 0.46), _random.randf_range(-0.2, 0.2), 0.0)
		_burst_remaining = 0.72
	fire_at(_target.global_position + Vector3.UP * 0.98 + _aim_offset)
	_shot_cadence_remaining = 0.18
	_tracking_remaining = 0.1

func _tick_timers(delta: float) -> void:
	_last_seen_remaining = maxf(0.0, _last_seen_remaining - delta)
	_decision_remaining = maxf(0.0, _decision_remaining - delta)
	_reaction_remaining = maxf(0.0, _reaction_remaining - delta)
	_tracking_remaining = maxf(0.0, _tracking_remaining - delta)
	_shot_cadence_remaining = maxf(0.0, _shot_cadence_remaining - delta)
	_burst_remaining = maxf(0.0, _burst_remaining - delta)
	_unstick_remaining = maxf(0.0, _unstick_remaining - delta)
	_route_recompute_remaining = maxf(0.0, _route_recompute_remaining - delta)

func _update_stuck_recovery(delta: float) -> void:
	if _move_goal.length_squared() > 0.04 and global_position.distance_to(_last_motion_position) < 0.035:
		_stuck_elapsed += delta
	else:
		_stuck_elapsed = 0.0
	_last_motion_position = global_position
	if _stuck_elapsed <= 0.7:
		return
	_stuck_elapsed = 0.0
	_unstick_remaining = 0.8
	_unstick_sign *= -1.0
	_unstick_jump_pending = true

func _take_unstick_jump() -> bool:
	var wants_jump := _unstick_jump_pending
	_unstick_jump_pending = false
	return wants_jump

func _face_objective(delta: float) -> void:
	var toward := _objective_goal - global_position
	toward.y = 0.0
	if toward.length_squared() <= 0.01:
		return
	var desired_yaw := atan2(-toward.x, -toward.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, delta * 3.8))
	head.rotation.x = lerpf(head.rotation.x, 0.0, minf(1.0, delta * 4.0))

func _objective_move_input() -> Vector2:
	if _unstick_remaining > 0.0:
		return Vector2(_unstick_sign * 0.92, -0.24)
	var waypoint := _objective_goal
	if _route_map != null and is_instance_valid(_route_map):
		var goal_changed := not _route_waypoint_valid or _route_goal_cache.distance_squared_to(_objective_goal) > 9.0
		if _route_recompute_remaining <= 0.0 or goal_changed:
			_route_waypoint = _route_map.route_toward(global_position, _objective_goal)
			_route_goal_cache = _objective_goal
			_route_waypoint_valid = true
			# Small per-bot jitter so seven bots don't all recompute on the
			# same tick.
			_route_recompute_remaining = ROUTE_RECOMPUTE_SECONDS + _random.randf_range(0.0, 0.08)
		waypoint = _route_waypoint
	var world_direction := waypoint - global_position
	world_direction.y = 0.0
	if world_direction.length() <= OBJECTIVE_STOP_RADIUS:
		return Vector2.ZERO
	world_direction = world_direction.normalized()
	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	var move_input := Vector2(world_direction.dot(right.normalized()), -world_direction.dot(forward.normalized()))
	return move_input.limit_length(1.0)

func _combat_move_input(distance: float, has_los: bool) -> Vector2:
	var objective_move := _objective_move_input()
	if not has_los:
		return objective_move
	var phase := Time.get_ticks_msec() * 0.002 + float(abs(actor_id.hash() % 31))
	var strafe := sin(phase) * 0.42
	var combat_move := Vector2(strafe, 0.42 if distance < 6.5 else -0.14 if distance > 24.0 else 0.0)
	var objective_weight := 0.72 if _objective_intent in ["deliver_core", "cancel_launch", "intercept_carrier"] else 0.56
	return (objective_move * objective_weight + combat_move * (1.0 - objective_weight)).limit_length(1.0)

func _formation_offset(distance: float) -> Vector3:
	var side := -1.0 if _objective_role in [ObjectiveRole.ESCORT, ObjectiveRole.RAIDER] else 1.0
	var depth := -1.0 if team == Team.RED else 1.0
	return Vector3(side * distance, 0.0, depth * distance * 0.38)

func _update_target_lock(_delta: float) -> void:
	var current_velocity := _target.velocity
	var direction_changed := current_velocity.length() > 2.0 and _last_target_velocity.length() > 2.0 and current_velocity.normalized().dot(_last_target_velocity.normalized()) < 0.25
	_last_target_velocity = current_velocity
	if not _target_locked:
		_target_locked = true
		_reaction_remaining = 0.34
		_tracking_remaining = 0.22
	elif direction_changed:
		_reaction_remaining = maxf(_reaction_remaining, 0.22)
		_tracking_remaining = maxf(_tracking_remaining, 0.18)
		_target_locked = true

func _pitch_to(point: Vector3) -> float:
	var local_point := to_local(point)
	return atan2(local_point.y - head.position.y, -local_point.z)

func _has_line_of_sight() -> bool:
	return _target != null and _has_line_of_sight_to(_target)

func _select_target() -> void:
	var valid: Array[Duelist] = []
	for candidate in _enemies:
		if is_instance_valid(candidate) and candidate.match_active and not candidate.eliminated:
			valid.append(candidate)
	if valid.is_empty():
		_target = null
		return
	if _target != null and is_instance_valid(_target) and _target in valid:
		if _has_line_of_sight_to(_target):
			return
		if _last_seen_remaining > 0.0:
			return
		_target = null
	valid.sort_custom(func(a: Duelist, b: Duelist) -> bool:
		var a_distance := global_position.distance_squared_to(a.global_position)
		var b_distance := global_position.distance_squared_to(b.global_position)
		return a_distance < b_distance if not is_equal_approx(a_distance, b_distance) else a.actor_id < b.actor_id
	)
	for candidate in valid:
		if global_position.distance_to(candidate.global_position) <= COMBAT_ACQUIRE_DISTANCE and _has_line_of_sight_to(candidate):
			_target = candidate
			_last_seen_position = candidate.global_position
			_last_seen_remaining = 0.72
			return
	_target = null

func _has_line_of_sight_to(candidate: Duelist) -> bool:
	var world := get_world_3d()
	if world == null or head == null or candidate.head == null:
		return false
	var origin := head.global_position + Vector3.UP * 0.03
	var query := PhysicsRayQueryParameters3D.create(origin, candidate.head.global_position, 1 | 2)
	query.exclude = [get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == candidate
