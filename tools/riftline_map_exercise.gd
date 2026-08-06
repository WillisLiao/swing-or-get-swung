extends SceneTree

func _initialize() -> void:
	var root := Node.new()
	root.name = "NuclearRushMapExercise"
	get_root().add_child(root)
	await process_frame

	var concourse := RiftlineMap.new()
	root.add_child(concourse)
	concourse.configure(RiftlineMap.Id.CONCOURSE, false)
	assert(not _contains_mesh(concourse))
	assert(concourse.ambient_motion_count() == 0)
	assert(concourse.solid_count() > 0)

	var gates := concourse.gate_positions()
	assert(gates[Duelist.Team.RED] != gates[Duelist.Team.BLUE])
	var pads := concourse.launch_pad_positions()
	assert(pads.has(Duelist.Team.RED))
	assert(pads.has(Duelist.Team.BLUE))
	assert(pads[Duelist.Team.RED] != pads[Duelist.Team.BLUE])

	assert(concourse.is_spawn_clear(concourse.core_spawn_position()))
	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		assert(concourse.is_spawn_clear(pads[team]))

	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		var spawns := concourse.spawn_points(team)
		assert(spawns.size() == 4)
		for index in spawns.size():
			assert(concourse.is_spawn_clear(spawns[index]))
			for other_index in range(index + 1, spawns.size()):
				assert(spawns[index].distance_to(spawns[other_index]) >= 3.5)
			var core_goal := concourse.core_spawn_position()
			assert(_has_authored_route(concourse, spawns[index], core_goal))
			var own_pad: Vector3 = pads[team]
			assert(_has_authored_route(concourse, spawns[index], own_pad))

	var own_pad_red: Vector3 = pads[Duelist.Team.RED]
	var own_pad_blue: Vector3 = pads[Duelist.Team.BLUE]
	assert(concourse.is_spawn_clear(own_pad_red))
	assert(concourse.is_spawn_clear(own_pad_blue))
	assert(_has_authored_route(concourse, own_pad_red, concourse.core_spawn_position()))
	assert(_has_authored_route(concourse, own_pad_blue, concourse.core_spawn_position()))

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
			assert(_has_authored_route(concourse, post, concourse.core_spawn_position()))

	var rendered := RiftlineMap.new()
	root.add_child(rendered)
	rendered.configure(RiftlineMap.Id.CONCOURSE, true)
	assert(_contains_mesh(rendered))
	assert(rendered.ambient_motion_count() >= 1)

	# The pads are the delivery target and the core marker is the pickup point, so
	# a silent failure to build either one would make the mode unreadable while
	# every rule still passed its own test.
	for landmark_name in ["RedLaunchPad", "BlueLaunchPad", "CoreMarker"]:
		var landmark := _find_named_node(rendered, landmark_name)
		assert(landmark != null, "presentation is missing landmark: %s" % landmark_name)
		assert(_contains_mesh(landmark), "landmark has no geometry: %s" % landmark_name)

	# Pad and core geometry must never become collision, or a carrier could not
	# stand on the pad to install.
	assert(rendered.is_spawn_clear(RiftlineMap.RED_LAUNCH_PAD))
	assert(rendered.is_spawn_clear(RiftlineMap.BLUE_LAUNCH_PAD))
	assert(rendered.is_spawn_clear(rendered.core_spawn_position()))
	assert(rendered.solid_count() == concourse.solid_count())

	print("Nuclear Rush map exercise: PASS")
	quit()

func _has_authored_route(map: RiftlineMap, origin: Vector3, goal: Vector3) -> bool:
	var current := origin
	for _step in 64:
		var next := map.route_toward(current, goal)
		assert(next.x >= -RiftlineMap.CONCOURSE_RADIUS - 2.0 and next.x <= RiftlineMap.CONCOURSE_RADIUS + 2.0)
		assert(next.z >= -RiftlineMap.CONCOURSE_RADIUS - 2.0 and next.z <= RiftlineMap.CONCOURSE_RADIUS + 2.0)
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
