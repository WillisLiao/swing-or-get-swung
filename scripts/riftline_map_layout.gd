class_name RiftlineMapLayout
extends RefCounted

## Immutable gameplay contract for Competitive Concourse V2.
##
## This file contains positions and route facts only.  Rendering and physics
## node construction stay in RiftlineMap so the same authored data can be
## exercised without creating a presentation tree.

const VERSION := 7
const CONCOURSE_RADIUS := 60.0
const CORE_SPAWN := Vector3(0.0, 0.72, 0.0)

static func build() -> Dictionary:
	var solids: Array[Dictionary] = []
	_add_outer_shell(solids)
	_add_central_structure(solids)
	_add_team_structures(solids, 1.0, "red")
	_add_team_structures(solids, -1.0, "blue")

	var red_spawns: Array[Vector3] = [
		_team_position(1.0, Vector3(-9.5, 0.1, 55.5)),
		_team_position(1.0, Vector3(-6.0, 0.1, 56.2)),
		_team_position(1.0, Vector3(6.0, 0.1, 56.2)),
		_team_position(1.0, Vector3(9.5, 0.1, 55.5)),
	]
	var blue_spawns: Array[Vector3] = []
	for point in red_spawns:
		blue_spawns.append(_team_position(-1.0, _team_local_from_world(point)))

	var red_gate := _team_position(1.0, Vector3(5.0, 0.05, 43.0))
	var blue_gate := _team_position(-1.0, Vector3(5.0, 0.05, 43.0))
	var red_pad := _team_position(1.0, Vector3(0.0, 0.05, 52.0))
	var blue_pad := _team_position(-1.0, Vector3(0.0, 0.05, 52.0))

	var route_graphs: Dictionary = {}
	for lane in [&"auto", &"center", &"maintenance", &"overlook"]:
		var lane_name := str(lane)
		var red_path: Array[Vector3] = _lane_path(lane_name)
		var graph: Dictionary = _build_route_graph(lane_name, red_path, red_spawns, blue_spawns, red_gate, blue_gate, red_pad, blue_pad)
		route_graphs[lane_name] = graph

	var tactical_facts: Dictionary = _build_tactical_facts(red_gate, blue_gate, red_pad, blue_pad, red_spawns, blue_spawns)
	return {
		"solids": solids,
		"route_graphs": route_graphs,
		"spawns": {"red": red_spawns, "blue": blue_spawns},
		"launch_pads": {"red": red_pad, "blue": blue_pad},
		"gates": {"red": red_gate, "blue": blue_gate},
		"core_spawn": CORE_SPAWN,
		"tactical_facts": tactical_facts,
	}

static func _add_outer_shell(solids: Array[Dictionary]) -> void:
	solids.append(_solid("ConcourseFloor", "cylinder", Vector3(0.0, -0.5, 0.0), Vector3(120.0, 1.0, 120.0), 0.0, 0.0, "floor", false, true))
	var wall_count := 40
	var wall_radius := CONCOURSE_RADIUS - 0.5
	var wall_length := TAU * wall_radius / float(wall_count) + 0.12
	for index in wall_count:
		var angle := TAU * float(index) / float(wall_count)
		var position := Vector3(cos(angle) * wall_radius, 3.6, sin(angle) * wall_radius)
		solids.append(_solid(
			"OuterWall%02d" % index,
			"box",
			position,
			Vector3(wall_length, 7.2, 1.2),
			PI * 0.5 - angle,
			0.0,
			"outer_wall",
			true,
			true,
		))

static func _add_central_structure(solids: Array[Dictionary]) -> void:
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			solids.append(_solid(
				"CoreTower_%s_%s" % ["W" if x_sign < 0.0 else "E", "S" if z_sign < 0.0 else "N"],
				"box",
				Vector3(x_sign * 10.0, 2.9, z_sign * 9.0),
				Vector3(6.0, 5.8, 6.0),
				0.0,
				0.0,
				"central_tower",
				true,
				true,
			))
	solids.append(_solid("NorthBaffle", "box", Vector3(-3.0, 2.0, 6.0), Vector3(8.0, 4.0, 1.2), 0.0, 0.0, "central_baffle", true, true))
	solids.append(_solid("SouthBaffle", "box", Vector3(3.0, 2.0, -6.0), Vector3(8.0, 4.0, 1.2), 0.0, 0.0, "central_baffle", true, true))
	for x_sign in [-1.0, 1.0]:
		# Structural support ends at the bridge underside (y=2.6).  The former
		# 4 m column projected through the deck and left less than one player
		# width beside each rail, silently blocking the through route.
		solids.append(_solid("CoreColumn_%s" % ("W" if x_sign < 0.0 else "E"), "box", Vector3(x_sign * 5.0, 1.3, 0.0), Vector3(1.4, 2.6, 1.4), 0.0, 0.0, "central_column", true, true))
	for z_sign in [-1.0, 1.0]:
		solids.append(_solid("CoreLowCover_%s" % ("S" if z_sign < 0.0 else "N"), "box", Vector3(0.0, 0.6, z_sign * 3.2), Vector3(3.0, 1.2, 1.2), 0.0, 0.0, "low_cover", true, true))

	# The bridge is walkable on both sides of its full-height sightline break.
	# Wide mirrored ramps now connect the arena floor directly to each end.  The
	# old shell read as climbable from the centre but left a 3.2 m vertical step;
	# a 9 m run keeps this replacement shallow enough for the player controller.
	solids.append(_solid("CentralBridgeRamp_W", "ramp", Vector3(-16.5, 0.0, 0.0), Vector3(9.0, 0.2, 4.5), 0.0, 3.2, "steel", false, true))
	solids.append(_solid("CentralBridgeRamp_E", "ramp", Vector3(16.5, 0.0, 0.0), Vector3(9.0, 0.2, 4.5), PI, 3.2, "steel", false, true))
	solids.append(_solid("CentralBridgeFloor", "box", Vector3(0.0, 2.9, 0.0), Vector3(24.0, 0.6, 4.0), 0.0, 0.0, "bridge_floor", false, true))
	for z_sign in [-1.0, 1.0]:
		solids.append(_solid("CentralBridgeRail_%s" % ("S" if z_sign < 0.0 else "N"), "box", Vector3(0.0, 3.55, z_sign * 1.75), Vector3(24.0, 1.3, 0.5), 0.0, 0.0, "bridge_rail", true, true))

static func _add_team_structures(solids: Array[Dictionary], team_sign: float, team_name: String) -> void:
	var accent_role := team_name + "_accent"
	var team_prefix := team_name.capitalize()
	var add_box := func(name: String, local_position: Vector3, dimensions: Vector3, route_blocker := true, material_role := "concrete", local_rotation_y: float = 0.0) -> void:
		var team_rotation := local_rotation_y + (PI if team_sign < 0.0 else 0.0)
		solids.append(_solid(team_prefix + name, "box", _team_position(team_sign, local_position), dimensions, team_rotation, 0.0, material_role if material_role != "concrete" else accent_role, route_blocker, true))

	add_box.call("RearBulkhead", Vector3(0.0, 3.2, 59.0), Vector3(28.0, 6.4, 1.2))
	add_box.call("BaseRoof", Vector3(0.0, 6.1, 51.0), Vector3(28.0, 0.6, 16.0), false, "steel")
	for x_sign in [-1.0, 1.0]:
		add_box.call("RearSideWall%s" % ("W" if x_sign < 0.0 else "E"), Vector3(x_sign * 14.0, 3.2, 55.0), Vector3(1.2, 6.4, 8.0))
		add_box.call("FrontSideWall%s" % ("W" if x_sign < 0.0 else "E"), Vector3(x_sign * 14.0, 3.2, 45.5), Vector3(1.2, 6.4, 3.0))
	for piece in [
		{"name": "W", "center": -10.5, "width": 7.0},
		{"name": "C", "center": 0.0, "width": 6.0},
		{"name": "E", "center": 10.5, "width": 7.0},
	]:
		add_box.call("FrontWall%s" % piece.name, Vector3(float(piece.center), 3.2, 43.0), Vector3(float(piece.width), 6.4, 1.2))
	add_box.call("InnerBlastWall", Vector3(0.0, 2.8, 48.5), Vector3(9.0, 5.6, 1.2))
	for x_sign in [-1.0, 1.0]:
		add_box.call("PadScreen%s" % ("W" if x_sign < 0.0 else "E"), Vector3(x_sign * 8.5, 2.8, 52.5), Vector3(1.2, 5.6, 6.5))
		add_box.call("SpawnPocketScreen%s" % ("W" if x_sign < 0.0 else "E"), Vector3(x_sign * 8.0, 2.2, 54.0), Vector3(7.0, 4.4, 0.8))
	add_box.call("ApproachBaffle", Vector3(0.0, 2.0, 35.0), Vector3(12.0, 4.0, 1.2))
	add_box.call("OffsetBaffle", Vector3(-5.5, 2.0, 25.0), Vector3(11.0, 4.0, 1.2))
	for x_sign in [-1.0, 1.0]:
		add_box.call("GateSideFin%s" % ("W" if x_sign < 0.0 else "E"), Vector3(x_sign * 11.5, 3.2, 38.0), Vector3(1.2, 6.4, 8.0))

	# Maintenance corridor: a covered outer lane with a deliberately split inner wall.
	add_box.call("MaintenanceRoof", Vector3(-28.0, 3.45, 26.0), Vector3(10.0, 0.6, 28.0), false, "steel")
	add_box.call("MaintenanceOuterWall", Vector3(-33.0, 2.0, 26.0), Vector3(1.2, 4.0, 28.0))
	add_box.call("MaintenanceInnerWallSouth", Vector3(-23.0, 2.0, 16.0), Vector3(1.2, 4.0, 8.0))
	add_box.call("MaintenanceInnerWallNorth", Vector3(-23.0, 2.0, 33.0), Vector3(1.2, 4.0, 14.0))
	for cover in [
		{"u": -30.0, "v": 18.0},
		{"u": -26.5, "v": 27.5},
		{"u": -30.0, "v": 36.0},
	]:
		add_box.call("MaintenanceCover_%s" % cover.v, Vector3(float(cover.u), 0.6, float(cover.v)), Vector3(1.2, 1.2, 1.2))

	# The overlook is a broad second-floor combat platform rather than a boxed
	# corridor.  A low outer rail keeps the long sightline open; staggered cover
	# forces a shallow slalom while preserving a player-width route between both
	# stair landings.  The portal at the north end is deliberately wider than a
	# squad so it reads as a destination without becoming another choke blocker.
	add_box.call("OverlookFloor", Vector3(27.0, 2.9, 26.0), Vector3(10.0, 0.6, 28.0), false, "steel")
	add_box.call("OverlookOuterRail", Vector3(31.6, 3.85, 26.0), Vector3(0.8, 1.3, 28.0))
	add_box.call("OverlookInnerParapetSouth", Vector3(22.0, 3.85, 20.0), Vector3(1.2, 1.3, 4.0))
	# The north parapet mirrors the 4 m south parapet around the centre cover.
	# Both now leave the same 1.75 m gap before their nearest ramp edge, so the
	# two stair approaches look and play identically.
	add_box.call("OverlookInnerParapetNorth", Vector3(22.0, 3.85, 32.0), Vector3(1.2, 1.3, 4.0))
	# A player-height centre-facing wall closes the exposed middle edge without
	# reaching either stair mouth.  It joins the two existing low parapets at
	# v=22 and v=30, leaving the full ramp approaches at v=14 and v=38 clear.
	add_box.call("OverlookCenterCover", Vector3(22.0, 4.1, 26.0), Vector3(1.2, 1.8, 8.0))
	add_box.call("OverlookDivider", Vector3(24.8, 5.0, 22.5), Vector3(5.0, 3.6, 1.0), true, "concrete", deg_to_rad(-12.0))
	add_box.call("OverlookCoverSouth", Vector3(29.2, 3.9, 27.2), Vector3(3.2, 1.4, 1.4))
	add_box.call("OverlookCoverNorth", Vector3(25.0, 3.9, 31.4), Vector3(3.2, 1.4, 1.4))
	add_box.call("OverlookGateInner", Vector3(22.8, 5.0, 35.0), Vector3(1.2, 3.6, 1.2))
	add_box.call("OverlookGateOuter", Vector3(31.2, 5.0, 35.0), Vector3(1.2, 3.6, 1.2))
	add_box.call("OverlookGateHeader", Vector3(27.0, 6.65, 35.0), Vector3(9.6, 0.6, 1.2), false, "steel")

	# The two ramps use local +U as their rise direction and end on the local
	# overlook deck.  The former diagonal upper connector, its rails, and its
	# blocker were removed so the new straight central bridge owns the only
	# through route above the arena floor.
	for v_value in [14.0, 38.0]:
		var ramp_position := _team_position(team_sign, Vector3(17.5, 0.0, v_value))
		solids.append(_solid(team_prefix + "OverlookRamp%s" % v_value, "ramp", ramp_position, Vector3(9.0, 0.2, 4.5), PI if team_sign < 0.0 else 0.0, 3.2, "steel", false, true))

static func _solid(name: String, shape: String, position: Vector3, dimensions: Vector3, rotation_y: float, rise: float, material_role: String, route_blocker: bool, casts_shadow: bool) -> Dictionary:
	return {
		"name": name,
		"shape": shape,
		"position": position,
		"dimensions": dimensions,
		"rotation_y": rotation_y,
		"rise": rise,
		"material_role": material_role,
		"route_blocker": route_blocker,
		"casts_shadow": casts_shadow,
	}

static func _team_position(team_sign: float, local_position: Vector3) -> Vector3:
	return Vector3(team_sign * local_position.x, local_position.y, team_sign * local_position.z)

static func _team_local_from_world(world_position: Vector3) -> Vector3:
	return Vector3(world_position.x, world_position.y, world_position.z)

static func _lane_path(lane: String) -> Array[Vector3]:
	match lane:
		"maintenance":
			return [
				Vector3(5.0, 0.05, 43.0), Vector3(-1.0, 0.1, 35.0),
				Vector3(-10.0, 0.1, 28.0), Vector3(-10.0, 0.1, 14.0),
				Vector3(-6.0, 0.1, 6.0), CORE_SPAWN,
			]
		"overlook":
			return [
				Vector3(5.0, 0.05, 43.0), Vector3(12.0, 0.1, 32.0),
				Vector3(18.0, 0.1, 22.0), Vector3(18.0, 0.1, 10.0),
				Vector3(18.0, 0.1, 4.0), Vector3(6.0, 0.1, 3.0),
				CORE_SPAWN,
			]
		_:
			return [
				Vector3(5.0, 0.05, 43.0), Vector3(5.0, 0.1, 35.0),
				Vector3(4.0, 0.1, 25.0), Vector3(3.0, 0.1, 14.0),
				Vector3(2.0, 0.1, 7.0), CORE_SPAWN,
			]

static func _build_route_graph(lane: String, red_path: Array[Vector3], red_spawns: Array[Vector3], blue_spawns: Array[Vector3], red_gate: Vector3, blue_gate: Vector3, red_pad: Vector3, blue_pad: Vector3) -> Dictionary:
	var graph: Dictionary = {
		"lane": lane,
		"nodes": [],
		"edges": [],
		"paths": {},
		"gate_core_distance": _target_distance(lane),
		"authored_path_length": _path_length(red_path),
		"rotated_gate_core_distance": 0.0,
		"target_range": _target_range(lane),
	}
	var nodes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var blue_path: Array[Vector3] = []
	for point in red_path:
		blue_path.append(_team_position(-1.0, point))
	var red_ids: Array[String] = []
	var blue_ids: Array[String] = []
	for index in red_path.size():
		var red_id := "red_lane_%02d" % index
		var blue_id := "blue_lane_%02d" % index
		_add_node(nodes, red_id, red_path[index], "lane")
		_add_node(nodes, blue_id, blue_path[index], "lane")
		red_ids.append(red_id)
		blue_ids.append(blue_id)
	_add_path_edges(edges, red_ids)
	_add_path_edges(edges, blue_ids)

	var core_to_red: Array[Vector3] = red_path.duplicate()
	var core_to_blue: Array[Vector3] = blue_path.duplicate()
	var red_base_prefix: Array[Vector3] = [red_pad, _team_position(1.0, Vector3(0.0, 0.1, 58.0)), _team_position(1.0, Vector3(13.0, 0.1, 58.0)), _team_position(1.0, Vector3(13.0, 0.1, 48.0)), red_gate]
	var blue_base_prefix: Array[Vector3] = [blue_pad, _team_position(-1.0, Vector3(0.0, 0.1, 58.0)), _team_position(-1.0, Vector3(13.0, 0.1, 58.0)), _team_position(-1.0, Vector3(13.0, 0.1, 48.0)), blue_gate]
	var red_to_core: Array[Vector3] = red_base_prefix.duplicate()
	for index in range(1, red_path.size()):
		red_to_core.append(red_path[index])
	var blue_to_core: Array[Vector3] = blue_base_prefix.duplicate()
	for index in range(1, blue_path.size()):
		blue_to_core.append(blue_path[index])
	core_to_red = red_to_core.duplicate()
	core_to_red.reverse()
	core_to_blue = blue_to_core.duplicate()
	core_to_blue.reverse()
	var red_to_blue: Array[Vector3] = red_to_core.duplicate()
	for index in range(blue_to_core.size() - 2, -1, -1):
		red_to_blue.append(blue_to_core[index])
	var blue_to_red: Array[Vector3] = blue_to_core.duplicate()
	for index in range(red_to_core.size() - 2, -1, -1):
		blue_to_red.append(red_to_core[index])
	graph.paths = {
		"red_to_core": red_to_core,
		"blue_to_core": blue_to_core,
		"core_to_red": core_to_red,
		"core_to_blue": core_to_blue,
		"red_to_blue": red_to_blue,
		"blue_to_red": blue_to_red,
	}

	# Add all base anchors and spawn pockets to every lane graph.  Their
	# connectivity is authored once here, then route_toward only selects the
	# requested lane graph at runtime.
	_add_node(nodes, "red_gate", red_gate, "base_entrance")
	_add_node(nodes, "blue_gate", blue_gate, "base_entrance")
	_add_node(nodes, "red_pad", red_pad, "launch_pad")
	_add_node(nodes, "blue_pad", blue_pad, "launch_pad")
	for index in red_spawns.size():
		_add_node(nodes, "red_spawn_%02d" % index, red_spawns[index], "spawn_pocket")
		_add_node(nodes, "blue_spawn_%02d" % index, blue_spawns[index], "spawn_pocket")
	for team_sign in [1.0, -1.0]:
		var team_prefix := "red" if team_sign > 0.0 else "blue"
		var escape_outer := _team_position(team_sign, Vector3(13.0, 0.1, 58.0))
		var escape_inner := _team_position(team_sign, Vector3(-13.0, 0.1, 58.0))
		var escape_outer_low := _team_position(team_sign, Vector3(13.0, 0.1, 48.0))
		var escape_inner_low := _team_position(team_sign, Vector3(-13.0, 0.1, 48.0))
		var pad_exit := _team_position(team_sign, Vector3(0.0, 0.1, 58.0))
		_add_node(nodes, team_prefix + "_escape_outer", escape_outer, "base_escape")
		_add_node(nodes, team_prefix + "_escape_inner", escape_inner, "base_escape")
		_add_node(nodes, team_prefix + "_escape_outer_low", escape_outer_low, "base_escape")
		_add_node(nodes, team_prefix + "_escape_inner_low", escape_inner_low, "base_escape")
		_add_node(nodes, team_prefix + "_pad_exit", pad_exit, "base_escape")
		_add_edge(edges, team_prefix + "_escape_outer", team_prefix + "_escape_outer_low")
		_add_edge(edges, team_prefix + "_escape_inner", team_prefix + "_escape_inner_low")
		_add_edge(edges, team_prefix + "_escape_outer_low", team_prefix + "_gate")
		_add_edge(edges, team_prefix + "_escape_inner_low", team_prefix + "_gate")
		_add_edge(edges, team_prefix + "_pad", team_prefix + "_pad_exit")
		_add_edge(edges, team_prefix + "_pad_exit", team_prefix + "_escape_outer")
		_add_edge(edges, team_prefix + "_pad_exit", team_prefix + "_escape_inner")
		for index in red_spawns.size():
			var spawn_id := team_prefix + "_spawn_%02d" % index
			var spawn_point: Vector3 = red_spawns[index] if team_sign > 0.0 else blue_spawns[index]
			_add_edge(edges, spawn_id, team_prefix + ("_escape_inner" if spawn_point.x < 0.0 else "_escape_outer"))
		_add_edge(edges, team_prefix + "_gate", "red_lane_00" if team_sign > 0.0 else "blue_lane_00")
		_add_edge(edges, team_prefix + "_pad", team_prefix + "_pad_exit")

	# Tactical nodes are explicit even when a lane does not use them as its
	# primary path, which lets exercises verify upper and lower coverage.
	var tactical_points: Array[Dictionary] = _tactical_route_nodes()
	for node in tactical_points:
		_add_node(nodes, str(node.id), node.position, str(node.kind))
	graph.nodes = nodes
	graph.edges = edges
	graph.rotated_gate_core_distance = _target_distance(lane)
	return graph

static func _build_tactical_facts(red_gate: Vector3, blue_gate: Vector3, red_pad: Vector3, blue_pad: Vector3, red_spawns: Array[Vector3], blue_spawns: Array[Vector3]) -> Dictionary:
	return {
		"version": VERSION,
		"core": CORE_SPAWN,
		"anchors": {
			"neutral_core": CORE_SPAWN,
			"home_pad": {"red": red_pad, "blue": blue_pad},
			"home_approach": {"red": red_gate, "blue": blue_gate},
			"enemy_pad": {"red": blue_pad, "blue": red_pad},
			"center_return": {"red": Vector3(4.0, 0.1, 25.0), "blue": Vector3(-4.0, 0.1, -25.0)},
		},
		"lane_posts": {
			"maintenance": [Vector3(-28.0, 0.1, 32.0), Vector3(-28.0, 0.1, 20.0), Vector3(-18.0, 0.1, 8.0)],
			"center": [Vector3(4.0, 0.1, 25.0), Vector3(3.0, 0.1, 14.0), Vector3(2.0, 0.1, 7.0)],
			"overlook": [Vector3(18.0, 0.1, 22.0), Vector3(18.0, 0.1, 10.0), Vector3(18.0, 0.1, 4.0)],
		},
		"base_entrances": {"red": red_gate, "blue": blue_gate},
		"bridge_sides": [Vector3(-6.0, 3.35, 0.0), Vector3(6.0, 3.35, 0.0)],
		"bridge_access": {
			"west_bottom": Vector3(-21.0, 0.1, 0.0),
			"west_top": Vector3(-12.0, 3.35, 0.0),
			"east_bottom": Vector3(21.0, 0.1, 0.0),
			"east_top": Vector3(12.0, 3.35, 0.0),
		},
		"spawn_pockets": {"red": red_spawns, "blue": blue_spawns},
		"sightline_tests": [
			{"from": red_gate, "to": CORE_SPAWN, "must_block": true},
			{"from": blue_gate, "to": CORE_SPAWN, "must_block": true},
		],
	}

static func _tactical_route_nodes() -> Array[Dictionary]:
	return [
		{"id": "maintenance_red_entrance", "position": Vector3(-23.0, 0.1, 35.0), "kind": "maintenance_entrance"},
		{"id": "maintenance_red_end", "position": Vector3(-28.0, 0.1, 12.0), "kind": "maintenance_end"},
		{"id": "overlook_red_ramp_bottom_14", "position": Vector3(13.0, 0.1, 14.0), "kind": "ramp_bottom"},
		{"id": "overlook_red_ramp_top_14", "position": Vector3(22.0, 3.35, 14.0), "kind": "ramp_top"},
		{"id": "overlook_red_ramp_bottom_38", "position": Vector3(13.0, 0.1, 38.0), "kind": "ramp_bottom"},
		{"id": "overlook_red_ramp_top_38", "position": Vector3(22.0, 3.35, 38.0), "kind": "ramp_top"},
		{"id": "bridge_north_side", "position": Vector3(6.0, 3.35, 0.0), "kind": "bridge_side"},
		{"id": "bridge_south_side", "position": Vector3(-6.0, 3.35, 0.0), "kind": "bridge_side"},
		{"id": "bridge_west_ramp_bottom", "position": Vector3(-21.0, 0.1, 0.0), "kind": "ramp_bottom"},
		{"id": "bridge_west_ramp_top", "position": Vector3(-12.0, 3.35, 0.0), "kind": "ramp_top"},
		{"id": "bridge_east_ramp_bottom", "position": Vector3(21.0, 0.1, 0.0), "kind": "ramp_bottom"},
		{"id": "bridge_east_ramp_top", "position": Vector3(12.0, 3.35, 0.0), "kind": "ramp_top"},
	]

static func _target_range(lane: String) -> Vector2:
	match lane:
		"maintenance":
			return Vector2(50.0, 60.0)
		"overlook":
			return Vector2(55.0, 65.0)
		_:
			return Vector2(44.0, 50.0)

static func _target_distance(lane: String) -> float:
	match lane:
		"maintenance":
			return 56.0
		"overlook":
			return 64.0
		_:
			return 46.0

static func _add_node(nodes: Array[Dictionary], node_id: String, position: Vector3, kind: String) -> void:
	for existing in nodes:
		if str(existing.get("id", "")) == node_id:
			return
	nodes.append({"id": node_id, "position": position, "kind": kind})

static func _add_edge(edges: Array[Dictionary], from_id: String, to_id: String) -> void:
	for edge in edges:
		if (str(edge.get("from", "")) == from_id and str(edge.get("to", "")) == to_id) or (str(edge.get("from", "")) == to_id and str(edge.get("to", "")) == from_id):
			return
	edges.append({"from": from_id, "to": to_id})

static func _add_path_edges(edges: Array[Dictionary], ids: Array[String]) -> void:
	for index in range(ids.size() - 1):
		_add_edge(edges, ids[index], ids[index + 1])

static func _path_length(path: Array[Vector3]) -> float:
	var length := 0.0
	for index in range(path.size() - 1):
		length += path[index].distance_to(path[index + 1])
	return length
