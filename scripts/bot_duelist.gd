class_name BotDuelist
extends Duelist

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
var _last_seen_position := Vector3.ZERO
var _last_seen_remaining := 0.0
var _stuck_elapsed := 0.0
var _last_motion_position := Vector3.ZERO
var _objective_context: Dictionary = {}

func set_opponents(enemies: Array[Duelist]) -> void:
	_enemies = enemies.duplicate()
	_select_target()

## Objective awareness for Nuclear Rush, pushed by the arena every time the
## authoritative objective state changes.  Expected keys: `core_state`,
## `core_position`, `core_carrier_id`, `core_carrier_team`, `installed_team`,
## `own_pad`, `enemy_pad`.  Combat-only bots ignore it, so this is safe to call
## before objective behaviour exists.
func set_objective_context(context: Dictionary) -> void:
	_objective_context = context.duplicate(true)

func _ready() -> void:
	_random.randomize()

func hold_opening_position(_seconds: float) -> void:
	_target_locked = false
	_reaction_remaining = 0.0
	_tracking_remaining = 0.0
	_move_goal = Vector2.ZERO
	_last_seen_remaining = 0.0

func _physics_process(delta: float) -> void:
	if eliminated:
		return
	_last_seen_remaining = maxf(0.0, _last_seen_remaining - delta)
	if _move_goal.length_squared() > 0.04 and global_position.distance_to(_last_motion_position) < 0.04:
		_stuck_elapsed += delta
	else:
		_stuck_elapsed = 0.0
	_last_motion_position = global_position
	if _stuck_elapsed > 0.7:
		_stuck_elapsed = 0.0
	_select_target()
	if not match_active:
		_target_locked = false
		_move_goal = Vector2.ZERO
		drive(Vector2.ZERO, false, false, delta)
		return
	_decision_remaining = maxf(0.0, _decision_remaining - delta)
	_reaction_remaining = maxf(0.0, _reaction_remaining - delta)
	_tracking_remaining = maxf(0.0, _tracking_remaining - delta)
	_shot_cadence_remaining = maxf(0.0, _shot_cadence_remaining - delta)
	_burst_remaining = maxf(0.0, _burst_remaining - delta)
	if _target == null:
		if _decision_remaining <= 0.0:
			_move_goal = Vector2.ZERO
			_decide_movement(999.0, false)
			_decision_remaining = 0.16
		drive(_move_goal, false, false, delta)
		return

	var has_los := _has_line_of_sight()
	var target_position := _target.global_position if has_los else _last_seen_position
	if not has_los and _last_seen_remaining <= 0.0:
		_target = null
		if _decision_remaining <= 0.0:
			_decide_movement(999.0, false)
			_decision_remaining = 0.16
		drive(_move_goal, false, false, delta)
		return
	var toward := target_position - global_position
	toward.y = 0.0
	var distance := toward.length()
	if distance < 0.01:
		return

	# The bot turns toward the player's lane gradually so a mobile player can read and challenge the peek.
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
	if _decision_remaining <= 0.0:
		_decide_movement(distance, has_los)
		_decision_remaining = 0.16
	set_combat_pose(_target_locked and _tracking_remaining <= 0.0, delta)
	drive(_move_goal, false, false, delta)

	if not has_los or not _target_locked or _reaction_remaining > 0.0 or _tracking_remaining > 0.0 or _shot_cadence_remaining > 0.0:
		return
	if distance <= KNIFE_RANGE:
		if weapon != Weapon.KNIFE:
			set_weapon_presentation(Weapon.KNIFE)
		fire_forward()
		return
	if weapon == Weapon.KNIFE:
		set_weapon_presentation(Weapon.PULSE)
	if _burst_remaining <= 0.0:
		# Keep one bounded torso miss for a short burst, rather than rerolling aim on every frame.
		_aim_offset = Vector3(_random.randf_range(-0.46, 0.46), _random.randf_range(-0.2, 0.2), 0.0)
		_burst_remaining = 0.72
	fire_at(_target.global_position + Vector3.UP * 0.98 + _aim_offset)
	_shot_cadence_remaining = 0.18
	_tracking_remaining = 0.1

func _update_target_lock(delta: float) -> void:
	var current_velocity := _target.velocity
	var direction_changed := current_velocity.length() > 2.0 and _last_target_velocity.length() > 2.0 and current_velocity.normalized().dot(_last_target_velocity.normalized()) < 0.25
	_last_target_velocity = current_velocity
	if not _target_locked:
		_target_locked = true
		_reaction_remaining = 0.34
		_tracking_remaining = 0.22
	elif direction_changed:
		# A meaningful strafe change costs the bot a fresh read instead of a free head correction.
		_reaction_remaining = maxf(_reaction_remaining, 0.22)
		_tracking_remaining = maxf(_tracking_remaining, 0.18)
		_target_locked = true

func _decide_movement(distance: float, has_los: bool) -> void:
	var strafe := 0.0
	var advance := 0.0
	if distance > 18.0:
		advance = 0.34
	elif distance < 7.0:
		advance = -0.28
	elif has_los:
		# Short, deliberate peeks make the bot readable without turning it into a stationary target.
		strafe = _random.randf_range(-0.55, 0.55)
	else:
		advance = 0.24
	_move_goal = Vector2(strafe, -advance)

func _pitch_to(point: Vector3) -> float:
	var local_point := to_local(point)
	return atan2(local_point.y - head.position.y, -local_point.z)

func _has_line_of_sight() -> bool:
	var world := get_world_3d()
	if world == null or _target == null:
		return false
	var origin := head.global_position + Vector3.UP * 0.03
	var query := PhysicsRayQueryParameters3D.create(origin, _target.head.global_position, 1 | 2)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == _target

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
		if _has_line_of_sight_to(candidate) and global_position.distance_to(candidate.global_position) <= 18.0:
			_target = candidate
			_last_seen_position = candidate.global_position
			_last_seen_remaining = 0.72
			return
	_target = null

func _has_line_of_sight_to(candidate: Duelist) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var origin := head.global_position + Vector3.UP * 0.03
	var query := PhysicsRayQueryParameters3D.create(origin, candidate.head.global_position, 1 | 2)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == candidate
