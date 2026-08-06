extends SceneTree

# Locks the live modes: team deathmatch, bomb, and the neutral-objective
# Nuke Rush race from center pickup to the opposing base.

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "RiftlineModesExercise"
	get_root().add_child(root)
	await physics_frame
	_test_deathmatch(root)
	_test_bomb(root)
	_test_nuke_rush(root)
	print("Riftline modes exercise: PASS")
	quit()

func _make_duelist(root: Node3D, team: Duelist.Team, actor_id: String, point: Vector3) -> Duelist:
	var duelist := Duelist.new()
	duelist.build(team, false, false, true)
	duelist.set_actor_id(actor_id)
	duelist.position = point
	root.add_child(duelist)
	duelist.set_match_active(true)
	return duelist

func _test_deathmatch(root: Node3D) -> void:
	var match_node := RiftlineMatch.new()
	match_node.configure([Vector3(0, 0, 0)], false, RiftlineMatch.GameMode.DEATHMATCH)
	root.add_child(match_node)
	match_node.add_spawn(Duelist.Team.SUN, Vector3(-30, 0.1, 0))
	match_node.add_spawn(Duelist.Team.SUN, Vector3(-30, 0.1, 10))
	match_node.add_spawn(Duelist.Team.VOID, Vector3(30, 0.1, 0))
	var sun := _make_duelist(root, Duelist.Team.SUN, "dm_sun", Vector3(-30, 0.1, 0))
	var void_d := _make_duelist(root, Duelist.Team.VOID, "dm_void", Vector3(30, 0.1, 0))
	match_node.register_duelist(sun, "dm_sun")
	match_node.register_duelist(void_d, "dm_void")
	match_node.begin()
	match_node._opening_remaining = 0.0
	await physics_frame
	assert(match_node.is_live())
	# Going live arms the duelists so they can actually move and fight.
	assert(sun.match_active)
	assert(void_d.match_active)

	# A kill scores the killer's team.
	match_node._on_defeated(void_d, sun)
	assert(match_node.scores[Duelist.Team.SUN] == 1)

	# Safe spawn prefers the point with fewer nearby enemies.  Park an enemy at
	# the first SUN point; the picker must choose the other one.
	var enemy_near := _make_duelist(root, Duelist.Team.VOID, "dm_near", Vector3(-29, 0.1, 0))
	var picked := match_node._pick_safe_spawn(sun)
	assert(picked.distance_to(Vector3(-30, 0.1, 10)) < 0.01)
	enemy_near.queue_free()

func _test_bomb(root: Node3D) -> void:
	var site_a := Vector3(0, 0.1, 20)
	var match_node := RiftlineMatch.new()
	match_node.configure([site_a], false, RiftlineMatch.GameMode.BOMB)
	root.add_child(match_node)
	match_node.add_spawn(Duelist.Team.SUN, Vector3(-30, 0.1, 0))
	match_node.add_spawn(Duelist.Team.VOID, Vector3(30, 0.1, 0))
	var attacker := _make_duelist(root, Duelist.Team.SUN, "b_sun", Vector3(-30, 0.1, 0))
	var defender := _make_duelist(root, Duelist.Team.VOID, "b_void", Vector3(30, 0.1, 0))
	match_node.register_duelist(attacker, "b_sun")
	match_node.register_duelist(defender, "b_void")
	match_node.begin()
	match_node._opening_remaining = 0.0
	await physics_frame
	assert(match_node.is_live())
	# SUN opens as the attacking side and holds the bomb.
	assert(match_node.bomb_team == Duelist.Team.SUN)
	assert(match_node.bomb_carrier_id == "b_sun")
	assert(match_node.bomb_state == RiftlineMatch.BombState.CARRIED)

	# Carrier plants at the site by holding interact.
	attacker.position = site_a
	match_node.set_interact("b_sun", true)
	match_node._tick_bomb(0.1)
	assert(match_node.bomb_state == RiftlineMatch.BombState.PLANTING)
	for i in range(40):
		match_node._tick_bomb(0.1)
	assert(match_node.bomb_state == RiftlineMatch.BombState.PLANTED)
	match_node.set_interact("b_sun", false)

	# Defender defuses by holding interact at the bomb.
	defender.position = site_a
	match_node.set_interact("b_void", true)
	for i in range(40):
		match_node._tick_bomb(0.1)
		if match_node.bomb_state == RiftlineMatch.BombState.DEFUSED:
			break
	assert(match_node.bomb_state == RiftlineMatch.BombState.DEFUSED)
	# Defuse awards the defending team (VOID) the round.
	assert(match_node.scores[Duelist.Team.VOID] == 1)

func _test_nuke_rush(root: Node3D) -> void:
	var sun_base := Vector3(0.0, 0.1, 30.0)
	var void_base := Vector3(0.0, 0.1, -30.0)
	var pickup := Vector3.ZERO
	var match_node := RiftlineMatch.new()
	match_node.configure([sun_base, void_base], false, RiftlineMatch.GameMode.NUKE_RUSH, pickup)
	root.add_child(match_node)
	match_node.add_spawn(Duelist.Team.SUN, sun_base)
	match_node.add_spawn(Duelist.Team.VOID, void_base)
	var sun := _make_duelist(root, Duelist.Team.SUN, "nuke_sun", Vector3(0.0, 0.1, 0.0))
	var void_d := _make_duelist(root, Duelist.Team.VOID, "nuke_void", Vector3(5.0, 0.1, 0.0))
	match_node.register_duelist(sun, "nuke_sun")
	match_node.register_duelist(void_d, "nuke_void")
	match_node.begin()
	match_node._opening_remaining = 0.0
	await physics_frame
	assert(match_node.is_live())
	assert(match_node.nuke_state == RiftlineMatch.NukeState.AT_CENTER)

	# The first player into the center room takes the neutral warhead.
	match_node._tick_nuke_rush(0.1)
	assert(match_node.nuke_state == RiftlineMatch.NukeState.CARRIED)
	assert(match_node.nuke_carrier_id == "nuke_sun")
	sun.position = Vector3(0.0, 0.1, -18.0)
	match_node._tick_nuke_rush(0.1)
	assert(float(match_node.nuke_progress[Duelist.Team.SUN]) > 0.5)

	# A carrier defeat drops the warhead and allows the opposing team to steal it.
	match_node._on_defeated(sun, void_d)
	assert(match_node.nuke_state == RiftlineMatch.NukeState.DROPPED)
	void_d.position = sun.position
	match_node._tick_nuke_rush(0.1)
	assert(match_node.nuke_carrier_id == "nuke_void")

	# Reaching the opposing base ends the match immediately.
	void_d.position = sun_base
	match_node._tick_nuke_rush(0.1)
	assert(match_node.nuke_state == RiftlineMatch.NukeState.DELIVERED)
	assert(match_node.phase == RiftlineMatch.Phase.FINISHED)
	assert(match_node.scores[Duelist.Team.VOID] == 1)

	# At timeout, the team with the furthest recorded push wins.
	var timeout_match := RiftlineMatch.new()
	timeout_match.configure([sun_base, void_base], false, RiftlineMatch.GameMode.NUKE_RUSH, pickup)
	root.add_child(timeout_match)
	timeout_match.nuke_progress[Duelist.Team.SUN] = 0.42
	timeout_match.nuke_progress[Duelist.Team.VOID] = 0.68
	timeout_match._finish_nuke_timeout()
	assert(timeout_match.phase == RiftlineMatch.Phase.FINISHED)
	assert(timeout_match.scores[Duelist.Team.VOID] == 1)

	# LAN descriptors preserve the third mode value for fork-to-upstream sessions.
	var network := RiftlineNetwork.new()
	var descriptor := network._descriptor_from_packet({"team_size": 5, "game_mode": 2, "map_id": int(RiftlineMap.Id.CONCOURSE)})
	assert(int(descriptor.game_mode) == int(RiftlineMatch.GameMode.NUKE_RUSH))
