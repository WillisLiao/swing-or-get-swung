extends SceneTree

const BALLISTICS := preload("res://scripts/rift_ballistics.gd")

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "RiftBallisticsExercise"
	get_root().add_child(root)
	var ballistics := BALLISTICS.new()
	root.add_child(ballistics)

	var human := _make_duelist(root, Duelist.Team.RED, "human", Vector3.ZERO)
	var bot := _make_duelist(root, Duelist.Team.BLUE, "bot", Vector3(5.0, 0.0, 0.0))
	var impacts: Array[Dictionary] = []
	var fired: Array[Dictionary] = []
	ballistics.projectile_fired.connect(func(fact: Dictionary) -> void: fired.append(fact))
	ballistics.projectile_impacted.connect(func(fact: Dictionary) -> void: impacts.append(fact))
	await physics_frame

	var rifle_row := RiftWeapons.row(RiftWeapons.RIFLE)

	# A 60Hz step advances more than 13 meters, so a swept segment must still catch this blocker.
	var blocker := _make_solid(root, Vector3(0.0, 1.0, -13.0), Vector3(1.0, 2.0, 0.8))
	ballistics.fire(human, Duelist.Weapon.RIFLE, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	assert(fired.size() == 1)
	assert(is_equal_approx((fired[0].velocity as Vector3).length(), float(rifle_row.projectile_speed)))
	ballistics.tick_authority(1.0 / 60.0)
	assert(impacts.size() == 1)
	assert(not bool(impacts[0].hit_duelist))
	blocker.queue_free()
	await physics_frame

	# The old muzzle-offset fixture is now a clear eye lane.  The wall is close
	# to the rendered muzzle but outside the conservative embedded-contact probe.
	ballistics.clear()
	impacts.clear()
	var side_wall := _make_solid(root, Vector3(0.42, 1.2, -2.0), Vector3(0.22, 2.4, 0.24))
	ballistics.fire(human, Duelist.Weapon.RIFLE, Vector3(0.42, 1.04, -1.22), Vector3.FORWARD)
	ballistics.tick_authority(1.0 / 60.0)
	assert(impacts.is_empty())
	side_wall.queue_free()
	await physics_frame

	# Contact at the actual physical muzzle is a presentation-only world impact:
	# it never creates a projectile and never applies damage.
	ballistics.clear()
	impacts.clear()
	var embedded_wall := _make_solid(root, human.physical_muzzle_position(), Vector3(0.4, 0.4, 0.4))
	ballistics.fire(human, Duelist.Weapon.RIFLE, Vector3(99.0, 99.0, 99.0), Vector3.UP)
	assert(impacts.size() == 1)
	assert(bool(impacts[0].get("obstructed", false)))
	assert(is_zero_approx(float(impacts[0].get("damage", 1.0))))
	assert(ballistics.active_count() == 0)
	embedded_wall.queue_free()
	await physics_frame

	# The shooter RID is excluded from the sweep, so a muzzle that begins in its capsule cannot self-hit.
	ballistics.clear()
	impacts.clear()
	ballistics.fire(human, Duelist.Weapon.RIFLE, human.global_position + Vector3.UP, Vector3(0.0, 0.0, 1.0))
	ballistics.tick_authority(1.0 / 60.0)
	assert(impacts.is_empty())

	# Five separate valid authority collisions apply exactly 5 * damage_near and then eliminate the target.
	human.global_position = Vector3.ZERO
	bot.global_position = Vector3(0.0, 0.0, -10.0)
	bot.health = Duelist.HEALTH
	bot.eliminated = false
	bot.collision_layer = 2
	impacts.clear()
	await physics_frame
	for _index in 5:
		ballistics.fire(human, Duelist.Weapon.RIFLE, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
		ballistics.tick_authority(1.0 / 60.0)
		assert(is_equal_approx(bot.health, maxf(0.0, Duelist.HEALTH - (_index + 1) * float(rifle_row.damage_near))))
	assert(is_zero_approx(bot.health))
	assert(bot.eliminated)
	assert(impacts.size() == 5)
	assert(impacts.all(func(fact: Dictionary) -> bool: return bool(fact.hit_duelist)))
	assert(impacts.all(func(fact: Dictionary) -> bool: return str(fact.shooter_id) == "human" and str(fact.target_id) == "bot"))
	assert(impacts.all(func(fact: Dictionary) -> bool: return fact.has("source_position") and is_equal_approx(float(fact.damage), float(rifle_row.damage_near))))

	# Accepted hip-fire follow-ups widen the cone as bloom accumulates. Each
	# shot's sampled direction is indexed by a monotonic shot_counter (never
	# reset, so replay determinism holds across a reconcile) inside a disc
	# whose *radius* is the cone - a single sampled direction is stochastic,
	# so the underlying cone math (already exhaustively covered in
	# tools/riftline_weapon_mobility_exercise.gd) is what gets asserted here,
	# not a specific sample. What this block proves is that Duelist actually
	# feeds RiftWeapons.cone_for() with live, moving state: consecutive
	# non-deliberate shots are never bit-identical, and ADS visibly tightens
	# the group.
	ballistics.clear()
	fired.clear()
	human.global_position = Vector3.ZERO
	human.rotation.y = 0.0
	human.set_combat_pose(false, 0.1)
	human._simulate_motion(Vector2.ZERO, false, 2.0)
	human._fire_remaining = 0.0
	human._accept_shot_plan()
	ballistics.fire(human, Duelist.Weapon.RIFLE)
	human._fire_remaining = 0.0
	human._accept_shot_plan()
	ballistics.fire(human, Duelist.Weapon.RIFLE)
	assert(fired.size() >= 2)
	var first_velocity: Vector3 = fired[-2].velocity
	var followup_velocity: Vector3 = fired[-1].velocity
	assert(not first_velocity.is_equal_approx(followup_velocity))
	ballistics.clear()
	human.set_combat_pose(true, 5.0)
	human._simulate_motion(Vector2.ZERO, false, 5.0)
	fired.clear()
	human._fire_remaining = 0.0
	human._accept_shot_plan()
	ballistics.fire(human, Duelist.Weapon.RIFLE)
	assert(fired.size() == 1)
	ballistics.clear()
	human.set_combat_pose(false, 0.1)

	# The cone itself, over many draws, is provably tighter under ADS than
	# hip-fire and provably widens with accumulated bloom - averaged over a
	# large sample so single-draw stochastic noise cannot flip the result.
	var hip_cold_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, false, false, 0.0, 0.0)
	var hip_hot_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, false, false, 0.0, 5.0)
	var ads_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, false, false, 1.0, 0.0)
	assert(hip_hot_cone > hip_cold_cone)
	assert(ads_cone < hip_cold_cone)

	# A same-team target can be crossed by a projectile but never takes damage.
	var friendly := _make_duelist(root, Duelist.Team.RED, "friendly", Vector3(0.0, 0.0, -4.0))
	ballistics.clear()
	var friendly_health := friendly.health
	ballistics.fire(human, Duelist.Weapon.RIFLE, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	ballistics.tick_authority(1.0 / 60.0)
	assert(is_equal_approx(friendly.health, friendly_health))
	friendly.queue_free()
	await physics_frame
	impacts.clear()

	# clear() cancels in-flight state, so a late tick cannot damage after a phase reset.
	bot.eliminated = false
	bot.health = Duelist.HEALTH
	bot.collision_layer = 2
	ballistics.clear()
	ballistics.fire(human, Duelist.Weapon.RIFLE, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	ballistics.clear()
	ballistics.tick_authority(1.0 / 60.0)
	assert(is_equal_approx(bot.health, Duelist.HEALTH))
	assert(impacts.is_empty())

	# The shotgun fires several pellets from one trigger pull, sharing a
	# shot_id, and can deal more total damage per shot than any single-pellet
	# weapon at close range.
	ballistics.clear()
	fired.clear()
	impacts.clear()
	human.configure_loadout(Duelist.PlayerClass.FRONTLINE, Duelist.Weapon.SHOTGUN)
	human.global_position = Vector3.ZERO
	human.set_combat_pose(false, 0.1)
	bot.global_position = Vector3(0.0, 1.0, -4.0)
	bot.health = Duelist.HEALTH
	bot.eliminated = false
	bot.collision_layer = 2
	await physics_frame
	human._fire_remaining = 0.0
	human._accept_shot_plan()
	ballistics.fire(human, Duelist.Weapon.SHOTGUN, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	var shotgun_row := RiftWeapons.row(RiftWeapons.SHOTGUN)
	assert(fired.size() == int(shotgun_row.pellets))
	var shot_id := int(fired[0].get("shot_id", -1))
	assert(fired.all(func(fact: Dictionary) -> bool: return int(fact.get("shot_id", -2)) == shot_id))
	ballistics.tick_authority(1.0 / 60.0)
	assert(impacts.size() >= 1)
	assert(bot.health < Duelist.HEALTH)

	# Melee is now "swing whatever is equipped" - there is no dedicated knife
	# weapon, and it is one close-range authoritative strike per cooldown that
	# never creates a ballistics projectile.
	human.configure_loadout(Duelist.PlayerClass.FRONTLINE, Duelist.Weapon.RIFLE)
	var melee_strikes := [0]
	human.melee_strike.connect(func(_shooter_id: String, _weapon: Duelist.Weapon, _origin: Vector3, _end: Vector3, _team: Duelist.Team, _hit: bool, _target_id: String) -> void: melee_strikes[0] += 1)
	bot.global_position = Vector3(0.0, 1.0, -1.0)
	human.global_position = Vector3.ZERO
	human.rotation.y = 0.0
	human._melee_remaining = 0.0
	ballistics.clear()
	human.melee_attack()
	assert(melee_strikes[0] == 1)
	assert(ballistics.active_count() == 0)
	# The cooldown blocks an immediate repeat.
	human.melee_attack()
	assert(melee_strikes[0] == 1)

	human.set_weapon_presentation(Duelist.Weapon.RIFLE)
	human.magazine_rounds = 1
	human.reserve_ammo = 30
	human._fire_remaining = 0.0
	human.fire_forward()
	assert(human.magazine_rounds == 0)
	human._fire_remaining = 0.0
	assert(human.reload_weapon())
	assert(human.reload_remaining > 0.0)
	human.fire_forward()
	assert(human.magazine_rounds == 0)
	for _index in 40:
		human._simulate_motion(Vector2.ZERO, false, 0.1)
	assert(human.magazine_rounds == int(rifle_row.magazine_size))
	assert(human.reserve_ammo == 0)

	# Human and bot requests both cross the same authority module seam.
	bot.eliminated = false
	bot.health = Duelist.HEALTH
	bot.collision_layer = 2
	bot.magazine_rounds = int(RiftWeapons.row(int(bot.weapon)).magazine_size)
	var human_requests := [0]
	var bot_requests := [0]
	var authority_fire := func(shooter: Duelist, weapon: Duelist.Weapon, origin: Vector3, direction: Vector3) -> void:
		if shooter == human:
			human_requests[0] += 1
		else:
			bot_requests[0] += 1
		ballistics.fire(shooter, weapon, origin, direction)
	human.fire_requested.connect(authority_fire)
	bot.fire_requested.connect(authority_fire)
	human._fire_remaining = 0.0
	bot._fire_remaining = 0.0
	human.fire_forward()
	bot.fire_at(Vector3(0.0, 1.0, -4.0))
	assert(human_requests[0] == 1)
	assert(bot_requests[0] == 1)
	ballistics.clear()

	print("Riftline ballistics exercise: PASS")
	quit()

func _make_duelist(root: Node3D, team: Duelist.Team, actor_id: String, position: Vector3) -> Duelist:
	var duelist := Duelist.new()
	duelist.build(team, false, false, true)
	duelist.set_actor_id(actor_id)
	duelist.position = position
	root.add_child(duelist)
	duelist.set_match_active(true)
	return duelist

func _make_solid(root: Node3D, position: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	return body
