extends SceneTree

func _initialize() -> void:
	var root := Node.new()
	root.name = "RiftlineMapExercise"
	get_root().add_child(root)
	await process_frame

	var duel := RiftlineMap.new()
	root.add_child(duel)
	duel.configure(RiftlineMap.Id.DUEL_YARD, false)
	assert(duel.spawn_points(Duelist.Team.SUN).size() == 1)
	assert(duel.spawn_points(Duelist.Team.VOID).size() == 1)
	assert(duel.gate_positions()[Duelist.Team.SUN] != duel.gate_positions()[Duelist.Team.VOID])
	assert(duel.solid_count() > 0)

	var concourse := RiftlineMap.new()
	root.add_child(concourse)
	concourse.configure(RiftlineMap.Id.CONCOURSE, false)
	assert(not _contains_mesh(concourse))
	assert(concourse.ambient_motion_count() == 0)
	assert(Vector2(concourse.seed_position().x, concourse.seed_position().z).length() < 0.01)
	assert((concourse.gate_positions()[Duelist.Team.SUN] as Vector3).z > 0.0)
	assert((concourse.gate_positions()[Duelist.Team.VOID] as Vector3).z < 0.0)
	for team in [Duelist.Team.SUN, Duelist.Team.VOID]:
		var spawns := concourse.spawn_points(team)
		assert(spawns.size() == 4)
		for index in spawns.size():
			assert(concourse.is_spawn_clear(spawns[index]))
			for other_index in range(index + 1, spawns.size()):
				assert(spawns[index].distance_to(spawns[other_index]) >= 3.5)
			var goal := concourse.seed_position()
			assert(_has_authored_route(concourse, spawns[index], goal))
			var enemy_team := Duelist.Team.VOID if team == Duelist.Team.SUN else Duelist.Team.SUN
			assert(_has_authored_route(concourse, goal, concourse.gate_positions()[enemy_team]))
	var facts := concourse.tactical_facts()
	assert(facts.has("anchors"))
	assert(facts.lane_posts.keys().size() == 3)
	for anchor in facts.anchors.values():
		if anchor is Vector3:
			assert(concourse.is_spawn_clear(anchor))
		elif anchor is Dictionary:
			for point in anchor.values():
				assert(concourse.is_spawn_clear(point))
	for posts in facts.lane_posts.values():
		for post in posts:
			assert(concourse.is_spawn_clear(post))
			assert(_has_authored_route(concourse, post, concourse.seed_position()))

	var rendered := RiftlineMap.new()
	root.add_child(rendered)
	rendered.configure(RiftlineMap.Id.CONCOURSE, true)
	assert(_contains_mesh(rendered))
	assert(rendered.ambient_motion_count() >= 6)
	for landmark_name in ["SunBase", "VoidBase", "NukePickupRoom", "WestArc", "EastArc", "StormRing"]:
		assert(_find_named_node(rendered, landmark_name) != null)
	var rendered_duel := RiftlineMap.new()
	root.add_child(rendered_duel)
	rendered_duel.configure(RiftlineMap.Id.DUEL_YARD, true)
	assert(_find_named_node(rendered_duel, "DuelYardLandmarkFrame") == null)

	assert(RiftlineNetwork.default_arena_for_team_size(1) == RiftlineMap.Id.DUEL_YARD)
	assert(RiftlineNetwork.default_arena_for_team_size(3) == RiftlineMap.Id.CONCOURSE)
	assert(RiftlineNetwork.default_arena_for_team_size(5) == RiftlineMap.Id.CONCOURSE)
	assert(RiftlineNetwork.arena_id_from_name("duel-yard") == RiftlineMap.Id.DUEL_YARD)
	assert(RiftlineNetwork.arena_id_from_name("concourse") == RiftlineMap.Id.CONCOURSE)
	assert(RiftlineNetwork.arena_id_from_name("not-a-map") == -1)

	var nuke_scene_resource := load("res://nuke_rush_arena.tscn") as PackedScene
	assert(nuke_scene_resource != null)
	var nuke_scene := nuke_scene_resource.instantiate() as Node3D
	root.add_child(nuke_scene)
	var scene_map := nuke_scene.get_node("RiftlineMap") as RiftlineMap
	assert(scene_map != null)
	scene_map.configure(RiftlineMap.Id.CONCOURSE, false)
	assert(scene_map.spawn_points(Duelist.Team.SUN).size() == 4)
	assert(scene_map.spawn_points(Duelist.Team.VOID).size() == 4)

	print("Riftline map exercise: PASS")
	quit()

func _has_authored_route(map: RiftlineMap, origin: Vector3, goal: Vector3) -> bool:
	var current := origin
	for _step in 64:
		var next := map.route_toward(current, goal)
		assert(Vector2(next.x, next.z).length() <= RiftlineMap.CONCOURSE_RADIUS + 1.5)
		if next.distance_to(goal) < 1.0:
			return true
		if next.distance_to(current) < 0.5:
			return false
		current = next
	return false

func _contains_mesh(node: Node) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D:
			return true
		if _contains_mesh(child):
			return true
	return false

func _find_named_node(node: Node, wanted_name: String) -> Node:
	for child in node.get_children():
		if child.name == wanted_name:
			return child
		var nested := _find_named_node(child, wanted_name)
		if nested != null:
			return nested
	return null
