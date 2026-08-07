class_name RiftBallistics
extends Node3D

## Authority-only projectile simulation, data-driven across all five weapons.
##
## The public interface is intentionally small: callers submit an accepted fire
## request, advance the authority once per physics step, and clear on a phase
## boundary.  Projectile records never become scene nodes.  Per-weapon
## ballistics (speed, damage falloff, range, pellet count) are read from
## RiftWeapons and copied into each projectile record at spawn - a projectile
## must not look up the shooter's *current* weapon at impact time, since the
## shooter may have swapped weapons or slots since firing.

signal projectile_fired(fact: Dictionary)
signal projectile_impacted(fact: Dictionary)

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
	# The authority consumes the accepted plan from Duelist.  The retained
	# optional arguments keep old offline exercises source-compatible, but are
	# deliberately ignored so a caller cannot author an origin or trajectory.
	var plan := shooter.consume_authoritative_shot_plan()
	var origin: Vector3 = plan.get("eye_origin", shooter.authoritative_eye_origin())
	var directions: Array = plan.get("directions", [plan.get("direction", shooter.authoritative_aim_direction())])
	if directions.is_empty():
		return false
	var row := RiftWeapons.row(RiftWeapons.clamp_weapon(int(weapon)))
	var muzzle_position: Vector3 = plan.get("physical_muzzle", shooter.physical_muzzle_position())
	if _muzzle_is_embedded(shooter, muzzle_position):
		var obstruction_id := _next_projectile_id
		_next_projectile_id += 1
		projectile_impacted.emit({
			"type": "projectile_impacted",
			"session_id": _session_id,
			"id": obstruction_id,
			"team": int(shooter.team),
			"weapon": int(weapon),
			"shot_id": int(plan.get("shot_id", obstruction_id)),
			"pellet_index": 0,
			"pellet_count": directions.size(),
			"shooter_id": shooter.actor_id,
			"target_id": "",
			"source_position": origin,
			"damage": 0.0,
			"position": muzzle_position,
			"normal": -(directions[0] as Vector3),
			"hit_duelist": false,
			"obstructed": true,
		})
		return true
	var shot_id := int(plan.get("shot_id", 0))
	var presentation_origin: Vector3 = plan.get("presentation_origin", origin)
	var pellet_count := directions.size()
	for pellet_index in pellet_count:
		var direction := (directions[pellet_index] as Vector3)
		if direction.length_squared() < 0.000001:
			continue
		var velocity := direction.normalized() * float(row.projectile_speed)
		var projectile_id := _next_projectile_id
		_next_projectile_id += 1
		var projectile := {
			"id": projectile_id,
			"shooter": shooter,
			"shooter_id": shooter.actor_id,
			"team": int(shooter.team),
			"weapon": int(weapon),
			"shot_id": shot_id,
			"pellet_index": pellet_index,
			"pellet_count": pellet_count,
			"position": origin,
			"source_position": origin,
			"presentation_origin": presentation_origin,
			"velocity": velocity,
			"remaining_range": float(row.max_range),
			"damage_near": float(row.damage_near),
			"damage_far": float(row.damage_far),
			"falloff_start": float(row.falloff_start),
			"falloff_end": float(row.falloff_end),
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
			"shot_id": shot_id,
			"pellet_index": pellet_index,
			"pellet_count": pellet_count,
			"origin": origin,
			"presentation_origin": presentation_origin,
			"velocity": velocity,
			"hip_burst_followup": bool(plan.get("hip_burst_followup", false)),
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
	var damage := _damage_for_distance(projectile, source_position.distance_to(impact_position))
	if collider is Duelist and collider != shooter and not collider.eliminated and collider.match_active and collider.team != shooter.team:
		hit_duelist = true
		target_id = collider.actor_id
		collider.take_damage(damage, shooter)
	projectile_impacted.emit({
		"type": "projectile_impacted",
		"session_id": _session_id,
		"id": int(projectile.id),
		"team": int(projectile.team),
		"weapon": int(projectile.get("weapon", 0)),
		"shot_id": int(projectile.get("shot_id", 0)),
		"pellet_index": int(projectile.get("pellet_index", 0)),
		"pellet_count": int(projectile.get("pellet_count", 1)),
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
## that connects always does meaningful work - it never silently no-ops. Each
## projectile carries its own weapon's falloff scalars, copied at spawn.
func _damage_for_distance(projectile: Dictionary, distance: float) -> float:
	var near_damage := float(projectile.get("damage_near", 23.0))
	var far_damage := float(projectile.get("damage_far", 14.0))
	var falloff_start := float(projectile.get("falloff_start", 22.0))
	var falloff_end := float(projectile.get("falloff_end", 70.0))
	if distance <= falloff_start:
		return near_damage
	if distance >= falloff_end:
		return far_damage
	var t := (distance - falloff_start) / maxf(0.0001, falloff_end - falloff_start)
	return lerpf(near_damage, far_damage, t)
