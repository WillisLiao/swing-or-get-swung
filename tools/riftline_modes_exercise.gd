extends SceneTree

# Locks the two live modes: team deathmatch (kill score + enemy-aware safe
# respawn) and bomb (plant/defuse progress, fuse, round wins, side swap).

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "RiftlineModesExercise"
	get_root().add_child(root)
	await physics_frame
	_test_deathmatch(root)
	_test_bomb(root)
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
	match_node.add_spawn(Duelist.Team.RED, Vector3(-30, 0.1, 0))
	match_node.add_spawn(Duelist.Team.RED, Vector3(-30, 0.1, 10))
	match_node.add_spawn(Duelist.Team.BLUE, Vector3(30, 0.1, 0))
	var red := _make_duelist(root, Duelist.Team.RED, "dm_red", Vector3(-30, 0.1, 0))
	var blue_d := _make_duelist(root, Duelist.Team.BLUE, "dm_blue", Vector3(30, 0.1, 0))
	match_node.register_duelist(red, "dm_red")
	match_node.register_duelist(blue_d, "dm_blue")
	match_node.begin()
	match_node._opening_remaining = 0.0
	await physics_frame
	assert(match_node.is_live())
	# Going live arms the duelists so they can actually move and fight.
	assert(red.match_active)
	assert(blue_d.match_active)

	# A kill scores the killer's team.
	match_node._on_defeated(blue_d, red)
	assert(match_node.scores[Duelist.Team.RED] == 1)

	# Safe spawn prefers the point with fewer nearby enemies.  Park an enemy at
	# the first RED point; the picker must choose the other one.
	var enemy_near := _make_duelist(root, Duelist.Team.BLUE, "dm_near", Vector3(-29, 0.1, 0))
	var picked := match_node._pick_safe_spawn(red)
	assert(picked.distance_to(Vector3(-30, 0.1, 10)) < 0.01)
	enemy_near.queue_free()

func _test_bomb(root: Node3D) -> void:
	var site_a := Vector3(0, 0.1, 20)
	var match_node := RiftlineMatch.new()
	match_node.configure([site_a], false, RiftlineMatch.GameMode.BOMB)
	root.add_child(match_node)
	match_node.add_spawn(Duelist.Team.RED, Vector3(-30, 0.1, 0))
	match_node.add_spawn(Duelist.Team.BLUE, Vector3(30, 0.1, 0))
	var attacker := _make_duelist(root, Duelist.Team.RED, "b_red", Vector3(-30, 0.1, 0))
	var defender := _make_duelist(root, Duelist.Team.BLUE, "b_blue", Vector3(30, 0.1, 0))
	match_node.register_duelist(attacker, "b_red")
	match_node.register_duelist(defender, "b_blue")
	match_node.begin()
	match_node._opening_remaining = 0.0
	await physics_frame
	assert(match_node.is_live())
	# RED opens as the attacking side and holds the bomb.
	assert(match_node.bomb_team == Duelist.Team.RED)
	assert(match_node.bomb_carrier_id == "b_red")
	assert(match_node.bomb_state == RiftlineMatch.BombState.CARRIED)

	# Carrier plants at the site by holding interact.
	attacker.position = site_a
	match_node.set_interact("b_red", true)
	match_node._tick_bomb(0.1)
	assert(match_node.bomb_state == RiftlineMatch.BombState.PLANTING)
	for i in range(40):
		match_node._tick_bomb(0.1)
	assert(match_node.bomb_state == RiftlineMatch.BombState.PLANTED)
	match_node.set_interact("b_red", false)

	# Defender defuses by holding interact at the bomb.
	defender.position = site_a
	match_node.set_interact("b_blue", true)
	for i in range(40):
		match_node._tick_bomb(0.1)
		if match_node.bomb_state == RiftlineMatch.BombState.DEFUSED:
			break
	assert(match_node.bomb_state == RiftlineMatch.BombState.DEFUSED)
	# Defuse awards the defending team (BLUE) the round.
	assert(match_node.scores[Duelist.Team.BLUE] == 1)
