class_name RiftlineHighAlert
extends RefCounted

## Local-only "High Alert" chip evaluator.
##
## The chip never changes authority, snapshots, damage, or visibility. It only
## examines presentation state already available on this client, then asks the
## local physics world whether cover blocks the line between two duelists.

const TRIGGER_SECONDS := 0.5
const REARM_SECONDS := 5.0
const ADS_THRESHOLD := 0.55
const AIM_CONE_DEGREES := 5.5
const VIEW_MARGIN_DEGREES := 1.5
const MAX_DISTANCE := 95.0

var _focus_seconds: Dictionary = {}
var _rearm_seconds: Dictionary = {}

func reset() -> void:
	_focus_seconds.clear()
	_rearm_seconds.clear()

func evaluate(delta: float, local_duelist: Duelist, opponents: Array[Duelist]) -> Dictionary:
	var result := {
		"active": false,
		"direction": Vector2.ZERO,
		"intensity": 0.0,
		"just_triggered": false,
		"attacker_id": "",
	}
	_tick_rearm(delta)
	if local_duelist == null or local_duelist.eliminated or local_duelist.camera == null or local_duelist.head == null:
		_focus_seconds.clear()
		return result

	var seen_ids: Dictionary = {}
	var best_score := -INF
	for attacker in opponents:
		if attacker == null or not is_instance_valid(attacker) or attacker == local_duelist:
			continue
		var attacker_id := attacker.actor_id if not attacker.actor_id.is_empty() else str(attacker.get_instance_id())
		seen_ids[attacker_id] = true
		var previous_seconds: float = float(_focus_seconds.get(attacker_id, 0.0))
		if not _qualifies(local_duelist, attacker):
			_focus_seconds.erase(attacker_id)
			continue
		var focused_seconds := previous_seconds + maxf(0.0, delta)
		_focus_seconds[attacker_id] = focused_seconds
		if focused_seconds < TRIGGER_SECONDS:
			continue
		var distance := local_duelist.global_position.distance_to(attacker.global_position)
		var score := focused_seconds - distance * 0.001
		if score > best_score:
			best_score = score
			result["active"] = true
			result["direction"] = screen_edge_direction(local_duelist.camera, attacker.global_position)
			result["intensity"] = clampf((focused_seconds - TRIGGER_SECONDS) / 0.18 + 0.72, 0.72, 1.0)
			result["attacker_id"] = attacker_id
		var rearm: float = float(_rearm_seconds.get(attacker_id, 0.0))
		if previous_seconds < TRIGGER_SECONDS and rearm <= 0.0:
			result["just_triggered"] = true
			_rearm_seconds[attacker_id] = REARM_SECONDS

	for tracked_id in _focus_seconds.keys().duplicate():
		if not seen_ids.has(tracked_id):
			_focus_seconds.erase(tracked_id)
	return result

func _qualifies(local_duelist: Duelist, attacker: Duelist) -> bool:
	if attacker.eliminated or attacker.team == local_duelist.team or attacker.head == null:
		return false
	if attacker.ads_progress < ADS_THRESHOLD:
		return false
	var attacker_origin := attacker.head.global_position
	var target_point := local_duelist.head.global_position
	if not aims_at_target(attacker_origin, attacker.aim_direction(), target_point):
		return false
	if not is_outside_view(local_duelist.camera, attacker_origin):
		return false
	return _has_clear_line_of_sight(local_duelist, attacker, target_point)

func _has_clear_line_of_sight(local_duelist: Duelist, attacker: Duelist, target_point: Vector3) -> bool:
	var world: World3D = local_duelist.get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(attacker.head.global_position, target_point, 1)
	query.exclude = [attacker.get_rid(), local_duelist.get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()

func _tick_rearm(delta: float) -> void:
	for attacker_id in _rearm_seconds.keys().duplicate():
		var remaining: float = maxf(0.0, float(_rearm_seconds.get(attacker_id, 0.0)) - maxf(0.0, delta))
		if remaining <= 0.0:
			_rearm_seconds.erase(attacker_id)
		else:
			_rearm_seconds[attacker_id] = remaining

static func aims_at_target(attacker_origin: Vector3, attacker_forward: Vector3, target_point: Vector3) -> bool:
	var to_target := target_point - attacker_origin
	var distance := to_target.length()
	if distance <= 0.01 or distance > MAX_DISTANCE or attacker_forward.length_squared() <= 0.0001:
		return false
	return attacker_forward.normalized().dot(to_target / distance) >= cos(deg_to_rad(AIM_CONE_DEGREES))

static func is_outside_view(camera: Camera3D, world_point: Vector3) -> bool:
	if camera == null:
		return false
	var camera_local := camera.global_transform.basis.inverse() * (world_point - camera.global_position)
	var forward_depth := -camera_local.z
	if forward_depth <= 0.01:
		return true
	var viewport_size := camera.get_viewport().get_visible_rect().size if camera.get_viewport() != null else Vector2(1280.0, 588.0)
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	var vertical_half := deg_to_rad(camera.fov) * 0.5 + deg_to_rad(VIEW_MARGIN_DEGREES)
	var horizontal_half := atan(tan(deg_to_rad(camera.fov) * 0.5) * aspect) + deg_to_rad(VIEW_MARGIN_DEGREES)
	var horizontal_angle := absf(atan2(camera_local.x, forward_depth))
	var vertical_angle := absf(atan2(camera_local.y, Vector2(camera_local.x, camera_local.z).length()))
	return horizontal_angle > horizontal_half or vertical_angle > vertical_half

static func screen_edge_direction(camera: Camera3D, world_point: Vector3) -> Vector2:
	if camera == null:
		return Vector2.DOWN
	var to_attacker := world_point - camera.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() <= 0.0001:
		return Vector2.DOWN
	var camera_right := camera.global_transform.basis.x
	var camera_forward := -camera.global_transform.basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()
	var direction := Vector2(to_attacker.normalized().dot(camera_right), -to_attacker.normalized().dot(camera_forward))
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2.DOWN
