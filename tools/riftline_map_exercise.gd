extends SceneTree

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "NuclearRushMapExercise"
	get_root().add_child(root)

	var layout: Dictionary = RiftlineMapLayout.build()
	_assert_layout_contract(layout)

	var concourse := RiftlineMap.new()
	root.add_child(concourse)
	concourse.configure(RiftlineMap.Id.CONCOURSE, false)
	await process_frame
	assert(not _contains_mesh(concourse))
	assert(concourse.ambient_motion_count() == 0)
	assert(concourse.solid_count() == (layout.solids as Array).size())
	_assert_team_symmetry(concourse)
	_assert_spawn_clearance(concourse)
	_assert_routes(concourse)
	_assert_tactical_facts(concourse)
	_assert_sightlines(concourse)

	var rendered := RiftlineMap.new()
	root.add_child(rendered)
	rendered.configure(RiftlineMap.Id.CONCOURSE, true)
	assert(_contains_mesh(rendered))
	assert(rendered.ambient_motion_count() == 0)
	for landmark_name in ["RedLaunchPad", "BlueLaunchPad", "CoreMarker", "RedLaunchGate", "BlueLaunchGate"]:
		var landmark := _find_named_node(rendered, landmark_name)
		assert(landmark != null, "presentation is missing landmark: %s" % landmark_name)
		assert(_contains_mesh(landmark), "landmark has no geometry: %s" % landmark_name)
	assert(rendered.is_spawn_clear(rendered.core_spawn_position()))
	assert(rendered.is_spawn_clear(rendered.launch_pad_positions()[Duelist.Team.RED]))
	assert(rendered.is_spawn_clear(rendered.launch_pad_positions()[Duelist.Team.BLUE]))
	assert(rendered.solid_count() == concourse.solid_count())

	concourse.pulse_objective()
	assert(concourse.is_processing())

	print("Nuclear Rush Concourse V2 map exercise: PASS")
	quit()

func _assert_layout_contract(layout: Dictionary) -> void:
	for key in ["solids", "route_graphs", "spawns", "launch_pads", "gates", "core_spawn", "tactical_facts"]:
		assert(layout.has(key), "layout is missing key: %s" % key)
	var solids: Array = layout.solids
	assert(solids.size() > 80)
	for solid_variant in solids:
		var solid: Dictionary = solid_variant
		assert(solid.keys().size() == 9)
		for key in ["name", "shape", "position", "dimensions", "rotation_y", "rise", "material_role", "route_blocker", "casts_shadow"]:
			assert(solid.has(key), "solid is missing key: %s" % key)
		assert(solid.position is Vector3)
		assert(solid.dimensions is Vector3)

	var graphs: Dictionary = layout.route_graphs
	for lane in ["auto", "center", "maintenance", "overlook"]:
		assert(graphs.has(lane), "route graph is missing lane: %s" % lane)
		var graph: Dictionary = graphs[lane]
		var target_range: Vector2 = graph.target_range
		var nominal_distance: float = graph.gate_core_distance
		assert(nominal_distance >= target_range.x and nominal_distance <= target_range.y)
		assert(is_equal_approx(nominal_distance, float(graph.rotated_gate_core_distance)))
		assert(absf(float(graph.authored_path_length) - nominal_distance) < 8.0)

func _assert_team_symmetry(map: RiftlineMap) -> void:
	var gates := map.gate_positions()
	var pads := map.launch_pad_positions()
	var red_gate: Vector3 = gates[Duelist.Team.RED]
	var blue_gate: Vector3 = gates[Duelist.Team.BLUE]
	var red_pad: Vector3 = pads[Duelist.Team.RED]
	var blue_pad: Vector3 = pads[Duelist.Team.BLUE]
	assert(blue_gate.is_equal_approx(Vector3(-red_gate.x, red_gate.y, -red_gate.z)))
	assert(blue_pad.is_equal_approx(Vector3(-red_pad.x, red_pad.y, -red_pad.z)))
	var red_spawns := map.spawn_points(Duelist.Team.RED)
	var blue_spawns := map.spawn_points(Duelist.Team.BLUE)
	assert(red_spawns.size() == 4 and blue_spawns.size() == 4)
	for index in red_spawns.size():
		assert(blue_spawns[index].is_equal_approx(Vector3(-red_spawns[index].x, red_spawns[index].y, -red_spawns[index].z)))
	assert(red_gate.distance_to(map.core_spawn_position()) > 40.0)

func _assert_spawn_clearance(map: RiftlineMap) -> void:
	assert(map.is_spawn_clear(map.core_spawn_position()))
	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		var pad: Vector3 = map.launch_pad_positions()[team]
		assert(map.is_spawn_clear(pad))
		var spawns := map.spawn_points(team)
		for index in spawns.size():
			assert(map.is_spawn_clear(spawns[index]))
			for other_index in range(index + 1, spawns.size()):
				assert(spawns[index].distance_to(spawns[other_index]) >= 3.0)

func _assert_routes(map: RiftlineMap) -> void:
	var core := map.core_spawn_position()
	for lane in [&"center", &"maintenance", &"overlook"]:
		for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
			var spawns := map.spawn_points(team)
			for spawn in spawns:
				var spawn_route_ok := _has_authored_route(map, spawn, core, lane)
				assert(spawn_route_ok, "spawn %s cannot route to core in %s" % [spawn, lane])
			var pad: Vector3 = map.launch_pad_positions()[team]
			assert(_has_authored_route(map, core, pad, lane), "core cannot route to pad in %s" % lane)
			assert(_has_authored_route(map, pad, core, lane), "pad cannot route to core in %s" % lane)
	assert(_has_authored_route(map, map.gate_positions()[Duelist.Team.RED], map.gate_positions()[Duelist.Team.BLUE], &"center"))

func _assert_tactical_facts(map: RiftlineMap) -> void:
	var facts := map.tactical_facts()
	assert(int(facts.version) == RiftlineMapLayout.VERSION)
	assert(facts.has("anchors"))
	assert(facts.lane_posts.keys().size() == 3)
	for anchor_variant in facts.anchors.values():
		if anchor_variant is Vector3:
			assert(map.is_spawn_clear(anchor_variant))
		elif anchor_variant is Dictionary:
			for point_variant in anchor_variant.values():
				var point: Vector3 = point_variant
				assert(map.is_spawn_clear(point), "tactical anchor is inside a solid: %s" % point)
	for lane in facts.lane_posts.keys():
		for post_variant in facts.lane_posts[lane]:
			var post: Vector3 = post_variant
			assert(map.is_spawn_clear(post), "lane post is inside a solid: %s %s" % [lane, post])
			assert(_has_authored_route(map, post, map.core_spawn_position(), StringName(lane)))
	assert(facts.base_entrances.keys().size() == 2)
	assert(facts.bridge_sides.size() == 2)
	for bridge_side_variant in facts.bridge_sides:
		var bridge_side: Vector3 = bridge_side_variant
		assert(map.is_spawn_clear(bridge_side), "bridge side is inside a solid: %s" % bridge_side)
		assert(_has_authored_route(map, bridge_side, map.core_spawn_position(), &"overlook"))

func _assert_sightlines(map: RiftlineMap) -> void:
	var world := map.get_world_3d()
	assert(world != null)
	var space := world.direct_space_state
	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		var origin: Vector3 = map.gate_positions()[team] + Vector3.UP * 1.0
		var target := map.core_spawn_position() + Vector3.UP * 1.0
		var query := PhysicsRayQueryParameters3D.create(origin, target)
		var hit: Dictionary = space.intersect_ray(query)
		assert(not hit.is_empty(), "base gate has no authored sightline blocker")
	# Upper-level route exits must remain clear enough to descend toward the core.
	for post_variant in map.tactical_facts().lane_posts.overlook:
		var post: Vector3 = post_variant
		assert(_has_authored_route(map, post, map.core_spawn_position(), &"overlook"))

func _has_authored_route(map: RiftlineMap, origin: Vector3, goal: Vector3, lane: StringName) -> bool:
	var current := origin
	var previous := origin + Vector3(999.0, 0.0, 999.0)
	for _step in 96:
		var next := map.route_toward(current, goal, lane)
		assert(next.x >= -RiftlineMap.CONCOURSE_RADIUS - 2.0 and next.x <= RiftlineMap.CONCOURSE_RADIUS + 2.0)
		assert(next.z >= -RiftlineMap.CONCOURSE_RADIUS - 2.0 and next.z <= RiftlineMap.CONCOURSE_RADIUS + 2.0)
		if next.distance_to(goal) < 1.0:
			return true
		if next.distance_to(current) < 0.5 or next.distance_to(previous) < 0.5:
			return false
		previous = current
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
