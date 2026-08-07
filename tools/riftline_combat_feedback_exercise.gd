extends SceneTree

const FEEDBACK := preload("res://scripts/riftline_combat_feedback.gd")

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "RiftlineCombatFeedbackExercise"
	get_root().add_child(root)
	var feedback := FEEDBACK.new()
	root.add_child(feedback)
	var camera := Camera3D.new()
	root.add_child(camera)
	await process_frame

	# Presentation-disabled mode is a harmless no-op and never allocates voices.
	feedback.configure(false, "local", camera)
	feedback.weapon_fired("local", Duelist.Weapon.RIFLE, Vector3.ZERO, true)
	assert(feedback._world_players.is_empty())
	assert(feedback._local_players.is_empty())

	var damage_count := [0]
	var hit_count := [0]
	feedback.damage_feedback.connect(func(_direction: Vector2, _intensity: float, _team: int) -> void: damage_count[0] += 1)
	feedback.hit_confirm_feedback.connect(func() -> void: hit_count[0] += 1)
	feedback.configure(true, "local", camera)
	await process_frame
	feedback.set_preferences(true, false)
	assert(feedback.effects_enabled)
	assert(not feedback.haptics_enabled)
	assert(feedback._world_players.is_empty())
	assert(feedback._local_players.is_empty())
	var preferences := ConfigFile.new()
	DuelHud.save_feedback_preferences(preferences, false, true)
	var reloaded_preferences := DuelHud.load_feedback_preferences(preferences, true, false)
	assert(not reloaded_preferences.effects_enabled)
	assert(not reloaded_preferences.haptics_enabled)

	var local := _make_duelist(root, Duelist.Team.RED, "local")
	var enemy := _make_duelist(root, Duelist.Team.BLUE, "enemy")
	var initial_health := local.health
	var initial_weapon := local.weapon
	var impact := {
		"type": "projectile_impacted",
		"session_id": "exercise",
		"id": 4,
		"shooter_id": enemy.actor_id,
		"target_id": local.actor_id,
		"team": int(enemy.team),
		"hit_duelist": true,
		"damage": Duelist.HEALTH * 0.23,
		"source_position": Vector3(2.0, 1.0, 0.0),
		"position": Vector3.ZERO,
	}
	feedback.projectile_impacted(impact, local.global_position)
	feedback.projectile_impacted(impact, local.global_position)
	assert(damage_count[0] == 1)
	assert(hit_count[0] == 0)
	assert(is_equal_approx(local.health, initial_health))
	assert(local.weapon == initial_weapon)

	impact.shooter_id = local.actor_id
	impact.target_id = enemy.actor_id
	impact.id = 5
	feedback.projectile_impacted(impact, local.global_position)
	assert(hit_count[0] == 1)
	assert(is_equal_approx(local.health, initial_health))
	assert(enemy.health == Duelist.HEALTH)
	feedback._last_damage_feedback_msec = -10000
	# Melee is "swing whatever is equipped" now - melee_struck carries the
	# actual weapon rather than a dedicated knife identity.
	feedback.melee_struck("enemy", Duelist.Weapon.SHOTGUN, Vector3(2.0, 1.0, 0.0), Vector3.ZERO, Duelist.Team.BLUE, false, true, "local", Vector3(2.0, 1.0, 0.0), "melee:1", local.global_position)
	feedback.melee_struck("enemy", Duelist.Weapon.SHOTGUN, Vector3(2.0, 1.0, 0.0), Vector3.ZERO, Duelist.Team.BLUE, false, true, "local", Vector3(2.0, 1.0, 0.0), "melee:1", local.global_position)
	assert(damage_count[0] == 2)

	# Reusing the event path remains a no-op in headless mode and never allocates voices.
	for index in 20:
		feedback.weapon_fired("remote-%d" % index, Duelist.Weapon.RIFLE, Vector3.ZERO, false)
	assert(feedback._world_players.is_empty())
	assert(feedback._local_players.is_empty())
	feedback.stop_all()
	feedback._world_streams.clear()
	feedback._local_streams.clear()

	print("Riftline combat feedback exercise: PASS")
	root.free()
	quit()

func _make_duelist(root: Node3D, team: Duelist.Team, actor_id: String) -> Duelist:
	var duelist := Duelist.new()
	duelist.build(team, false, false, false)
	duelist.set_actor_id(actor_id)
	duelist.set_match_active(true)
	root.add_child(duelist)
	return duelist
