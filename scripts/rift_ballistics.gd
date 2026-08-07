class_name RiftBallistics
extends Node3D

## Authority-only projectile simulation for the Rift Carbine.
##
## The public interface is intentionally small: callers submit an accepted fire
## request, advance the authority once per physics step, and clear on a phase
## boundary.  Projectile records never become scene nodes.

signal projectile_fired(fact: Dictionary)
signal projectile_impacted(fact: Dictionary)

const M4_PROJECTILE_SPEED := 800.0
const M4_FIRE_INTERVAL := 0.086
const M4_DAMAGE := 23.0
const M4_DAMAGE_FAR := 14.0
const M4_FALLOFF_START := 22.0
const M4_FALLOFF_END := 70.0
const M4_MAX_RANGE := 95.0
# 0.086 seconds is approximately 700 RPM, and 23 damage means five body hits to
# eliminate a 100 HP duelist inside FALLOFF_START (close competitive lanes).
# Damage falls off linearly from there to FALLOFF_END, floors at 14 (about
# eight hits) out to MAX_RANGE, and never drops further - a shot that lands
# always registers, it just does less work at range. MAX_RANGE (95m) comfortably
# covers the Concourse's longest open sightlines (60m radius / 120m diameter)
# so a projectile crossing the core room does not vanish before reaching a
# target still inside the arena.
const PROJECTILE_GRAVITY := 9.81
const COLLISION_MASK := 1 | 2
const WORLD_COLLISION_MASK := 1
# 18 mm is enough to detect a barrel actually inside a wall while leaving a
# near-side surface outside the probe, which is important for crosshair truth.
const MUZZLE_CONTACT_RADIUS := 0.018

var _next_projectile_id := 1
var _session_id := str(Time.get_ticks_usec())
var _projectiles: Array[Dictionary] = []

func fire(shooter: Duelist, weapon: Duelist.Weapon, _legacy_origin: Vector3 = Vector3.ZERO, _legacy_direction: Vector3 = Vector3.ZERO) -> bool:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return false
	if not is_instance_valid(shooter) or not shooter.match_active or shooter.eliminated:
		return false
	if weapon != Duelist.Weapon.PULSE:
		return false
	# The authority consumes the accepted plan from Duelist.  The retained
	# optional arguments keep old offline exercises source-compatible, but are
	# deliberately ignored so a caller cannot author an origin or trajectory.
	var plan := shooter.consume_authoritative_shot_plan()
	var origin: Vector3 = plan.get("eye_origin", shooter.authoritative_eye_origin())
	var direction: Vector3 = plan.get("direction", shooter.authoritative_aim_direction())
	if direction.length_squared() < 0.000001:
		return false
	if _muzzle_is_embedded(shooter, plan.get("physical_muzzle", shooter.physical_muzzle_position())):
		var obstruction_id := _next_projectile_id
		_next_projectile_id += 1
		projectile_impacted.emit({
			"type": "projectile_impacted",
			"session_id": _session_id,
			"id": obstruction_id,
			"team": int(shooter.team),
			"weapon": int(weapon),
			"shooter_id": shooter.actor_id,
			"target_id": "",
			"source_position": origin,
			"damage": 0.0,
			"position": plan.get("physical_muzzle", origin),
			"normal": -direction,
			"hit_duelist": false,
			"obstructed": true,
		})
		return true
	var velocity := direction.normalized() * M4_PROJECTILE_SPEED
	var projectile_id := _next_projectile_id
	_next_projectile_id += 1
	var projectile := {
		"id": projectile_id,
		"shooter": shooter,
		"shooter_id": shooter.actor_id,
		"team": int(shooter.team),
		"weapon": int(weapon),
		"position": origin,
		"source_position": origin,
		"presentation_origin": plan.get("presentation_origin", origin),
		"velocity": velocity,
		"remaining_range": M4_MAX_RANGE,
		"hip_burst_index": int(plan.get("hip_burst_index", 0)),
		"hip_burst_followup": bool(plan.get("hip_burst_followup", false)),
	}
	_projectiles.append(projectile)
	projectile_fired.emit({
		"type": "projectile_fired",
		"session_id": _session_id,
		"id": projectile_id,
		"shooter_id": shooter.actor_id,
		"team": int(shooter.team),
		"weapon": int(weapon),
		"origin": origin,
		"presentation_origin": projectile.get("presentation_origin", origin),
		"velocity": velocity,
		"hip_burst_index": projectile.get("hip_burst_index", 0),
		"hip_burst_followup": projectile.get("hip_burst_followup", false),
	})
	return true

func tick_authority(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if delta <= 0.0 or _projectiles.is_empty():
		return
	var index := 0
	while index < _projectiles.size():
		var projectile := _projectiles[index]
		var shooter: Variant = projectile.get("shooter", null)
		if not shooter is Duelist or not is_instance_valid(shooter) or shooter.eliminated or not shooter.match_active:
			_projectiles.remove_at(index)
			continue

		var previous_position: Vector3 = projectile.position
		var velocity: Vector3 = projectile.velocity
		velocity.y -= PROJECTILE_GRAVITY * delta
		var travel := velocity * delta
		var travel_distance := travel.length()
		var remaining_range := float(projectile.remaining_range)
		if travel_distance > remaining_range:
			travel = travel.normalized() * remaining_range
			travel_distance = remaining_range
		var next_position := previous_position + travel
		var hit := _sweep(previous_position, next_position, shooter)
		if not hit.is_empty():
			_handle_impact(projectile, hit)
			_projectiles.remove_at(index)
			continue
		if remaining_range <= travel_distance + 0.0001:
			_projectiles.remove_at(index)
			continue
		projectile.position = next_position
		projectile.velocity = velocity
		projectile.remaining_range = remaining_range - travel_distance
		_projectiles[index] = projectile
		index += 1

func clear() -> void:
	_projectiles.clear()

func active_count() -> int:
	return _projectiles.size()

func _sweep(from: Vector3, to: Vector3, shooter: Duelist) -> Dictionary:
	if from.distance_squared_to(to) < 0.0000001:
		return {}
	var world := get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, COLLISION_MASK)
	query.exclude = [shooter.get_rid()]
	return world.direct_space_state.intersect_ray(query)

func _muzzle_is_embedded(shooter: Duelist, muzzle_position: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = MUZZLE_CONTACT_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, muzzle_position)
	query.collision_mask = WORLD_COLLISION_MASK
	query.exclude = [shooter.get_rid()]
	# A small overlap is intentionally used instead of an eye-to-muzzle ray.
	# Proximity to a wall is not obstruction; the muzzle must actually occupy it.
	return not world.direct_space_state.intersect_shape(query, 1).is_empty()

func _handle_impact(projectile: Dictionary, hit: Dictionary) -> void:
	var shooter: Duelist = projectile.shooter
	var collider: Object = hit.get("collider", null)
	var hit_duelist := false
	var target_id := ""
	var source_position: Vector3 = projectile.get("source_position", projectile.get("position", Vector3.ZERO))
	var impact_position: Vector3 = hit.get("position", projectile.position)
	var damage := _damage_for_distance(source_position.distance_to(impact_position))
	if collider is Duelist and collider != shooter and not collider.eliminated and collider.match_active and collider.team != shooter.team:
		hit_duelist = true
		target_id = collider.actor_id
		collider.take_damage(damage, shooter)
	projectile_impacted.emit({
		"type": "projectile_impacted",
		"session_id": _session_id,
		"id": int(projectile.id),
		"team": int(projectile.team),
		"shooter_id": str(projectile.get("shooter_id", "")),
		"target_id": target_id,
		"source_position": source_position,
		"damage": damage if hit_duelist else 0.0,
		"position": impact_position,
		"normal": hit.get("normal", Vector3.UP),
		"hit_duelist": hit_duelist,
		"obstructed": false,
	})

## Linear falloff from the close-range plate to the floor damage, so a shot
## that connects always does meaningful work - it never silently no-ops.
func _damage_for_distance(distance: float) -> float:
	if distance <= M4_FALLOFF_START:
		return M4_DAMAGE
	if distance >= M4_FALLOFF_END:
		return M4_DAMAGE_FAR
	var t := (distance - M4_FALLOFF_START) / (M4_FALLOFF_END - M4_FALLOFF_START)
	return lerpf(M4_DAMAGE, M4_DAMAGE_FAR, t)
