@tool
class_name RiftlineMap
extends Node3D

# Nuclear Rush ships exactly one map: Robert's circular Concourse from PR #1,
# ported forward onto RED/BLUE team naming and rendered with the realistic
# NuclearMaterials PBR palette instead of the old illustrative pulp shader.

enum Id { CONCOURSE }

# Weathered industrial palette. Concrete greys and steel with one saturated
# accent per team for bases, pads, and the core marker.
const CONCRETE_FLOOR := Color("6b6f74")
const CONCRETE_WALL := Color("54585d")
const CONCRETE_LIGHT := Color("8b8f93")
const STEEL_DARK := Color("3c4247")
const STEEL_MID := Color("6d747b")
const RED_ACCENT := Color("c23b2e")
const BLUE_ACCENT := Color("2e6fc2")
const RED_ACCENT_LIGHT := Color("e0574a")
const BLUE_ACCENT_LIGHT := Color("4a8de0")
const CORE_ACCENT := Color("ffcf5e")

const CONCOURSE_RADIUS := 60.0
const CORE_SPAWN := Vector3(0.0, 0.72, 0.0)
const RED_GATE := Vector3(0.0, 0.05, 52.0)
const BLUE_GATE := Vector3(0.0, 0.05, -52.0)
const RED_LAUNCH_PAD := Vector3(0.0, 0.05, 51.5)
const BLUE_LAUNCH_PAD := Vector3(0.0, 0.05, -51.5)
const RED_SPAWNS := [
	Vector3(-7.5, 0.1, 48.0), Vector3(-2.5, 0.1, 48.0),
	Vector3(2.5, 0.1, 48.0), Vector3(7.5, 0.1, 48.0),
]
const BLUE_SPAWNS := [
	Vector3(7.5, 0.1, -48.0), Vector3(2.5, 0.1, -48.0),
	Vector3(-2.5, 0.1, -48.0), Vector3(-7.5, 0.1, -48.0),
]

@export var editor_preview_enabled := false

var _map_id: Id = Id.CONCOURSE
var _presentation_enabled := false
var _gates: Dictionary = {}
var _launch_pads: Dictionary = {}
var _spawns: Dictionary = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
var _solids: Array[Dictionary] = []
var _route_blockers: Array[Dictionary] = []
var _route_nodes: Array[Vector3] = []
var _ambient_motion: Array[Dictionary] = []
var _ambient_time := 0.0
var _objective_pulse_remaining := 0.0
var _objective_pulse_root: Node3D

func _ready() -> void:
	if Engine.is_editor_hint() and editor_preview_enabled:
		call_deferred("configure", Id.CONCOURSE, true)

func _process(delta: float) -> void:
	if not _presentation_enabled:
		return
	_ambient_time += delta
	_objective_pulse_remaining = maxf(0.0, _objective_pulse_remaining - delta)
	for entry in _ambient_motion:
		var root: Node3D = entry.get("root", null)
		if root == null or not is_instance_valid(root):
			continue
		var phase := float(entry.get("phase", 0.0))
		var frequency := float(entry.get("frequency", 0.2))
		var amplitude := float(entry.get("amplitude", 0.0))
		var axis := int(entry.get("axis", 1))
		var offset := sin(_ambient_time * frequency + phase) * amplitude
		if axis == 0:
			root.rotation.x = float(entry.get("base", 0.0)) + offset
		elif axis == 2:
			root.rotation.z = float(entry.get("base", 0.0)) + offset
		else:
			root.rotation.y = float(entry.get("base", 0.0)) + offset
	if _objective_pulse_root != null and is_instance_valid(_objective_pulse_root):
		var pulse := sin((1.0 - _objective_pulse_remaining / 0.34) * PI) if _objective_pulse_remaining > 0.0 else 0.0
		_objective_pulse_root.scale = Vector3.ONE * (1.0 + pulse * 0.035)

func configure(next_map_id: Id, presentation_enabled: bool) -> void:
	_clear_layout()
	_map_id = next_map_id
	_presentation_enabled = presentation_enabled
	_configure_concourse()
	_build_solids()
	if _presentation_enabled:
		_build_presentation()

func core_spawn_position() -> Vector3:
	return CORE_SPAWN

func launch_pad_positions() -> Dictionary:
	return _launch_pads.duplicate(true)

func gate_positions() -> Dictionary:
	return _gates.duplicate(true)

func spawn_points(team: Duelist.Team) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in _spawns.get(team, []):
		result.append(point)
	return result

func route_toward(origin: Vector3, destination: Vector3) -> Vector3:
	if _route_nodes.is_empty():
		return destination
	if origin.distance_squared_to(destination) < 4.0 or not _segment_hits_route_blocker(origin, destination):
		return destination
	var direct_distance := origin.distance_to(destination)
	var best := destination
	var best_score := INF
	for node in _route_nodes:
		if _point_in_solid(node) or origin.distance_to(node) < 3.0 or origin.distance_to(node) > 34.0:
			continue
		var node_to_goal := node.distance_to(destination)
		if node_to_goal > direct_distance + 12.0:
			continue
		if _segment_hits_route_blocker(origin, node):
			continue
		var score := origin.distance_to(node) + node_to_goal * 0.72
		if score < best_score:
			best_score = score
			best = node
	return best

func map_id() -> Id:
	return _map_id

func is_spawn_clear(point: Vector3) -> bool:
	return not _point_in_solid(point)

func solid_count() -> int:
	return _solids.size()

func tactical_facts() -> Dictionary:
	var red_gate: Vector3 = _gates.get(Duelist.Team.RED, Vector3.ZERO)
	var blue_gate: Vector3 = _gates.get(Duelist.Team.BLUE, Vector3.ZERO)
	var red_pad: Vector3 = _launch_pads.get(Duelist.Team.RED, Vector3.ZERO)
	var blue_pad: Vector3 = _launch_pads.get(Duelist.Team.BLUE, Vector3.ZERO)
	var red_home := red_gate.lerp(CORE_SPAWN, 0.38)
	var blue_home := blue_gate.lerp(CORE_SPAWN, 0.38)
	return {
		"core": CORE_SPAWN,
		"anchors": {
			"neutral_core": CORE_SPAWN,
			"home_pad": {Duelist.Team.RED: red_pad, Duelist.Team.BLUE: blue_pad},
			"home_approach": {Duelist.Team.RED: red_home, Duelist.Team.BLUE: blue_home},
			"enemy_pad": {Duelist.Team.RED: blue_pad, Duelist.Team.BLUE: red_pad},
			"center_return": {Duelist.Team.RED: Vector3(0.0, 0.1, 25.0), Duelist.Team.BLUE: Vector3(0.0, 0.1, -25.0)},
		},
		"lane_posts": {
			"west_arc": [Vector3(-31.0, 0.1, 31.0), Vector3(-39.0, 0.1, 0.0), Vector3(-31.0, 0.1, -31.0)],
			"center_drive": [Vector3(0.0, 0.1, 29.0), Vector3(2.3, 0.1, 13.0), Vector3(-2.3, 0.1, -13.0), Vector3(0.0, 0.1, -29.0)],
			"east_arc": [Vector3(31.0, 0.1, 31.0), Vector3(39.0, 0.1, 0.0), Vector3(31.0, 0.1, -31.0)],
		},
	}

func _clear_layout() -> void:
	for child in get_children():
		child.queue_free()
	_gates.clear()
	_launch_pads.clear()
	_spawns = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
	_solids.clear()
	_route_blockers.clear()
	_route_nodes.clear()
	_ambient_motion.clear()
	_ambient_time = 0.0
	_objective_pulse_remaining = 0.0
	_objective_pulse_root = null

func pulse_objective() -> void:
	if not _presentation_enabled:
		return
	_objective_pulse_remaining = 0.34

func ambient_motion_count() -> int:
	return _ambient_motion.size()

func _configure_concourse() -> void:
	_gates = {
		Duelist.Team.RED: RED_GATE,
		Duelist.Team.BLUE: BLUE_GATE,
	}
	_launch_pads = {
		Duelist.Team.RED: RED_LAUNCH_PAD,
		Duelist.Team.BLUE: BLUE_LAUNCH_PAD,
	}
	_spawns[Duelist.Team.RED] = RED_SPAWNS.duplicate()
	_spawns[Duelist.Team.BLUE] = BLUE_SPAWNS.duplicate()

	# A true circular play space: cylinder floor plus tangent wall segments.
	_add_cylinder_solid(Vector3(0.0, -0.5, 0.0), CONCOURSE_RADIUS * 2.0, 1.0, CONCRETE_FLOOR)
	var wall_segments := 40
	var wall_length := TAU * (CONCOURSE_RADIUS + 0.5) / float(wall_segments) + 0.35
	for index in wall_segments:
		var angle := TAU * float(index) / float(wall_segments)
		var wall_position := Vector3(cos(angle) * (CONCOURSE_RADIUS + 0.5), 2.75, sin(angle) * (CONCOURSE_RADIUS + 0.5))
		_add_solid(wall_position, Vector3(wall_length, 5.5, 1.2), CONCRETE_WALL, 0.0, false, PI * 0.5 - angle)

	# Opposing bases sit inside the north/south rim with four clear spawn slots.
	_add_route_solid(Vector3(0.0, 1.45, 55.0), Vector3(25.0, 2.9, 1.4), RED_ACCENT)
	_add_route_solid(Vector3(-13.0, 1.2, 50.0), Vector3(1.4, 2.4, 10.0), RED_ACCENT_LIGHT)
	_add_route_solid(Vector3(13.0, 1.2, 50.0), Vector3(1.4, 2.4, 10.0), RED_ACCENT_LIGHT)
	_add_route_solid(Vector3(0.0, 1.45, -55.0), Vector3(25.0, 2.9, 1.4), BLUE_ACCENT)
	_add_route_solid(Vector3(-13.0, 1.2, -50.0), Vector3(1.4, 2.4, 10.0), BLUE_ACCENT_LIGHT)
	_add_route_solid(Vector3(13.0, 1.2, -50.0), Vector3(1.4, 2.4, 10.0), BLUE_ACCENT_LIGHT)

	# The central pickup room is an open ring with equal north/south entrances.
	var chamber_segments := 16
	for index in chamber_segments:
		var angle := TAU * float(index) / float(chamber_segments)
		if absf(cos(angle)) < 0.34:
			continue
		var chamber_position := Vector3(cos(angle) * 8.2, 1.25, sin(angle) * 8.2)
		_add_route_solid(chamber_position, Vector3(3.4, 2.5, 0.7), CONCRETE_LIGHT if index % 2 == 0 else STEEL_DARK, PI * 0.5 - angle)

	# Free-standing cover follows the supplied top-down diagram.
	_add_concourse_diagram_cover()
	_add_concourse_layered_terrain()
	_add_launch_pads()
	_add_core_marker()

	_route_nodes = [
		Vector3(-30.0, 0.1, -40.0), Vector3(-10.0, 0.1, -40.0), Vector3(10.0, 0.1, -40.0), Vector3(30.0, 0.1, -40.0),
		Vector3(-39.0, 0.1, -20.0), Vector3(-28.0, 0.1, -20.0), Vector3(-10.0, 0.1, -22.0), Vector3(0.0, 0.1, -24.0), Vector3(-2.3, 0.1, -15.0), Vector3(2.3, 0.1, -15.0), Vector3(-2.3, 0.1, -12.0), Vector3(2.3, 0.1, -12.0), Vector3(-0.8, 0.1, -9.5), Vector3(0.8, 0.1, -9.5), Vector3(-0.8, 0.1, -7.0), Vector3(0.8, 0.1, -7.0), Vector3(10.0, 0.1, -22.0), Vector3(28.0, 0.1, -20.0), Vector3(39.0, 0.1, -20.0),
		Vector3(-42.0, 0.1, -10.0), Vector3(-42.0, 0.1, 0.0), Vector3(-42.0, 0.1, 10.0), Vector3(-38.0, 0.1, -14.0), Vector3(-27.0, 0.1, -14.0), Vector3(-38.0, 0.1, 14.0), Vector3(-27.0, 0.1, 14.0),
		Vector3(-28.0, 0.1, 0.0), Vector3(-11.0, 0.1, 0.0), Vector3(0.0, 0.1, 0.0), Vector3(11.0, 0.1, 0.0), Vector3(28.0, 0.1, 0.0),
		Vector3(27.0, 0.1, -14.0), Vector3(38.0, 0.1, -14.0), Vector3(27.0, 0.1, 14.0), Vector3(38.0, 0.1, 14.0), Vector3(42.0, 0.1, -10.0), Vector3(42.0, 0.1, 0.0), Vector3(42.0, 0.1, 10.0),
		Vector3(-39.0, 0.1, 20.0), Vector3(-28.0, 0.1, 20.0), Vector3(-10.0, 0.1, 22.0), Vector3(-2.3, 0.1, 15.0), Vector3(2.3, 0.1, 15.0), Vector3(-2.3, 0.1, 12.0), Vector3(2.3, 0.1, 12.0), Vector3(-0.8, 0.1, 9.5), Vector3(0.8, 0.1, 9.5), Vector3(-0.8, 0.1, 7.0), Vector3(0.8, 0.1, 7.0), Vector3(0.0, 0.1, 24.0), Vector3(10.0, 0.1, 22.0), Vector3(28.0, 0.1, 20.0), Vector3(39.0, 0.1, 20.0),
		Vector3(-30.0, 0.1, 40.0), Vector3(-10.0, 0.1, 40.0), Vector3(10.0, 0.1, 40.0), Vector3(30.0, 0.1, 40.0),
	]

func _add_concourse_diagram_cover() -> void:
	# Paired base blocks at the north and south tips of the diagram.
	for side in [-1.0, 1.0]:
		var half_name := "Red" if side > 0.0 else "Blue"
		var half_color := RED_ACCENT if side > 0.0 else BLUE_ACCENT
		_add_route_solid(Vector3(-3.2, 1.25, side * 43.0), Vector3(3.0, 2.5, 2.2), half_color, 0.0, "%sBaseCoverWest" % half_name)
		_add_route_solid(Vector3(3.2, 1.25, side * 43.0), Vector3(3.0, 2.5, 2.2), half_color, 0.0, "%sBaseCoverEast" % half_name)

	# Four tall rectangles on each side form the long oval around the objective.
	for x_sign in [-1.0, 1.0]:
		var lane_name := "West" if x_sign < 0.0 else "East"
		for index in 4:
			var z_position: float = [-24.0, -8.0, 8.0, 24.0][index]
			_add_route_solid(Vector3(x_sign * 32.0, 1.5, z_position), Vector3(2.2, 3.0, 5.2), CONCRETE_LIGHT, 0.0, "%sCoverColumn%d" % [lane_name, index + 1])

	# Inset shoulder blocks reproduce the four corners of the sketched oval.
	for side in [-1.0, 1.0]:
		for x_sign in [-1.0, 1.0]:
			var half_name := "Red" if side > 0.0 else "Blue"
			var lane_name := "West" if x_sign < 0.0 else "East"
			var shoulder_color := RED_ACCENT_LIGHT if x_sign * side > 0.0 else BLUE_ACCENT_LIGHT
			_add_route_solid(Vector3(x_sign * 25.0, 1.5, side * 34.0), Vector3(2.5, 3.0, 5.0), shoulder_color, 0.0, "%s%sShoulderCover" % [half_name, lane_name])

	# Three low round covers guard each open entrance without closing the core room.
	for side in [-1.0, 1.0]:
		var half_name := "Red" if side > 0.0 else "Blue"
		for index in 3:
			var x_position: float = [-4.6, 0.0, 4.6][index]
			_add_cylinder_solid(Vector3(x_position, 0.6, side * 15.0), 2.3, 1.2, CONCRETE_LIGHT, true, "%sCenterCover%d" % [half_name, index + 1])

func _add_concourse_layered_terrain() -> void:
	# Raised midfield decks create a playable upper route and a covered lower route.
	for side in [-1.0, 1.0]:
		var side_name := "Red" if side > 0.0 else "Blue"
		var deck_color := RED_ACCENT if side > 0.0 else BLUE_ACCENT
		var deck_z: float = float(side) * 29.0
		_add_solid(Vector3(0.0, 2.8, deck_z), Vector3(12.0, 0.6, 8.0), deck_color, 0.0, false, 0.0, "%sMidDeck" % side_name)
		_add_solid(Vector3(0.0, 3.65, deck_z - 3.72), Vector3(12.0, 1.15, 0.45), CONCRETE_LIGHT, 0.0, false, 0.0, "%sMidDeckRailA" % side_name, "metal")
		_add_solid(Vector3(0.0, 3.65, deck_z + 3.72), Vector3(12.0, 1.15, 0.45), CONCRETE_LIGHT, 0.0, false, 0.0, "%sMidDeckRailB" % side_name, "metal")
		for x_sign in [-1.0, 1.0]:
			var ramp_rotation := PI * 0.5 if x_sign < 0.0 else -PI * 0.5
			var ramp_side := "West" if x_sign < 0.0 else "East"
			_add_ramp(Vector3(x_sign * 9.0, 0.0, deck_z), Vector3(5.0, 0.2, 6.0), 3.1, deck_color, ramp_rotation, "%s%sRamp" % [side_name, ramp_side])
			for z_sign in [-1.0, 1.0]:
				var support_suffix := "A" if z_sign < 0.0 else "B"
				_add_route_solid(Vector3(x_sign * 5.25, 1.35, deck_z + z_sign * 2.8), Vector3(0.75, 2.7, 0.75), deck_color, 0.0, "%s%sSupport%s" % [side_name, ramp_side, support_suffix], "metal")

	# Covered outer corridors echo the reference's indoor/outdoor transitions.
	for x_sign in [-1.0, 1.0]:
		var corridor_name := "WestUnderpass" if x_sign < 0.0 else "EastUnderpass"
		var corridor_color := BLUE_ACCENT if x_sign < 0.0 else RED_ACCENT
		var corridor_x: float = float(x_sign) * 42.0
		_add_solid(Vector3(corridor_x, 3.25, 0.0), Vector3(10.0, 0.55, 14.0), corridor_color, 0.0, false, 0.0, corridor_name)
		_add_route_solid(Vector3(corridor_x - x_sign * 4.6, 1.4, 0.0), Vector3(0.8, 2.8, 14.0), CONCRETE_LIGHT, 0.0, "%sInnerWall" % corridor_name)
		_add_route_solid(Vector3(corridor_x + x_sign * 4.6, 1.4, 0.0), Vector3(0.8, 2.8, 14.0), corridor_color, 0.0, "%sOuterWall" % corridor_name)

func _add_launch_pads() -> void:
	# Presentation-only: a recessed pad with a raised rim and an emissive ring.
	# Neither adds a solid, so players can always walk onto the pad.
	if not _presentation_enabled:
		return
	_add_pad_landmark(RED_LAUNCH_PAD, RED_ACCENT, "RedLaunchPad")
	_add_pad_landmark(BLUE_LAUNCH_PAD, BLUE_ACCENT, "BlueLaunchPad")

func _add_pad_landmark(position: Vector3, accent: Color, node_name: String) -> void:
	var pad := _landmark_root(node_name)
	pad.position = position
	_add_cylinder_landmark(pad, Vector3.ZERO, 4.2, 0.14, NuclearMaterials.concrete(STEEL_DARK, 0.7))
	_add_cylinder_landmark(pad, Vector3(0.0, 0.02, 0.0), 3.4, 0.06, NuclearMaterials.metal(STEEL_MID, 0.32))
	_add_cylinder_landmark(pad, Vector3(0.0, 0.09, 0.0), 4.1, 0.06, NuclearMaterials.emissive(accent, 3.6))

func _add_core_marker() -> void:
	# Presentation-only: a low plinth plus an emissive marker in the center room.
	# No solid is added at the pickup point so the core remains reachable.
	if not _presentation_enabled:
		return
	var marker := _landmark_root("CoreMarker")
	marker.position = Vector3(CORE_SPAWN.x, 0.0, CORE_SPAWN.z)
	_objective_pulse_root = marker
	_register_ambient_motion(marker, 0.006, 0.28, 1.3, 1)
	_add_cylinder_landmark(marker, Vector3.ZERO, 2.3, 0.32, NuclearMaterials.concrete(STEEL_DARK, 0.7))
	_add_cylinder_landmark(marker, Vector3(0.0, 0.2, 0.0), 1.45, 0.16, NuclearMaterials.emissive(CORE_ACCENT, 4.5))

func _build_solids() -> void:
	for solid in _solids:
		_add_solid_node(solid)

func _build_presentation() -> void:
	_build_concourse_landmarks()
	_build_launch_gates()

func _add_solid(position: Vector3, dimensions: Vector3, color: Color, emission: float, route_blocker := false, rotation_y := 0.0, node_name := "", material_kind := "concrete") -> void:
	var spec := {"position": position, "dimensions": dimensions, "color": color, "emission": emission, "rotation_y": rotation_y, "name": node_name, "material_kind": material_kind}
	_solids.append(spec)
	if route_blocker:
		_route_blockers.append(spec)

func _add_route_solid(position: Vector3, dimensions: Vector3, color: Color, rotation_y := 0.0, node_name := "", material_kind := "painted_metal") -> void:
	_add_solid(position, dimensions, color, 0.0, true, rotation_y, node_name, material_kind)

func _add_cylinder_solid(position: Vector3, diameter: float, height: float, color: Color, route_blocker := false, node_name := "", material_kind := "concrete") -> void:
	var spec := {
		"position": position,
		"dimensions": Vector3(diameter, height, diameter),
		"color": color,
		"emission": 0.0,
		"shape": "cylinder",
		"rotation_y": 0.0,
		"name": node_name,
		"material_kind": material_kind,
	}
	_solids.append(spec)
	if route_blocker:
		_route_blockers.append(spec)

func _add_ramp(position: Vector3, dimensions: Vector3, rise: float, color: Color, rotation_y := 0.0, node_name := "", material_kind := "painted_metal") -> void:
	var spec := {"position": position, "dimensions": dimensions, "color": color, "emission": 0.0, "shape": "ramp", "rise": rise, "rotation_y": rotation_y, "name": node_name, "material_kind": material_kind}
	_solids.append(spec)

func _add_solid_node(spec: Dictionary) -> void:
	var body := StaticBody3D.new()
	var body_name := str(spec.get("name", ""))
	if not body_name.is_empty():
		body.name = body_name
	body.position = spec.position
	body.rotation.y = float(spec.get("rotation_y", 0.0))
	add_child(body)
	var shape_name := str(spec.get("shape", "box"))
	if _presentation_enabled:
		var mesh_instance := MeshInstance3D.new()
		if shape_name == "ramp":
			mesh_instance.mesh = _ramp_mesh(spec.dimensions, float(spec.get("rise", 0.0)))
		elif shape_name == "cylinder":
			var cylinder_mesh := CylinderMesh.new()
			cylinder_mesh.top_radius = float(spec.dimensions.x) * 0.5
			cylinder_mesh.bottom_radius = float(spec.dimensions.x) * 0.5
			cylinder_mesh.height = float(spec.dimensions.y)
			cylinder_mesh.radial_segments = 64
			mesh_instance.mesh = cylinder_mesh
		else:
			mesh_instance.mesh = _box_mesh(spec.dimensions)
		mesh_instance.material_override = _material_for_solid(spec)
		body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape: Shape3D
	if shape_name == "ramp":
		var ramp_shape := ConvexPolygonShape3D.new()
		var half_x := float(spec.dimensions.x) * 0.5
		var half_z := float(spec.dimensions.z) * 0.5
		ramp_shape.points = PackedVector3Array([
			Vector3(-half_x, 0.0, -half_z), Vector3(half_x, 0.0, -half_z),
			Vector3(-half_x, 0.0, half_z), Vector3(half_x, 0.0, half_z),
			Vector3(-half_x, float(spec.rise), half_z), Vector3(half_x, float(spec.rise), half_z),
		])
		shape = ramp_shape
	elif shape_name == "cylinder":
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = float(spec.dimensions.x) * 0.5
		cylinder_shape.height = float(spec.dimensions.y)
		shape = cylinder_shape
	else:
		var box_shape := BoxShape3D.new()
		box_shape.size = spec.dimensions
		shape = box_shape
	collision.shape = shape
	body.add_child(collision)

func _material_for_solid(spec: Dictionary) -> ShaderMaterial:
	var color: Color = spec.color
	var kind := str(spec.get("material_kind", "painted_metal"))
	if kind == "concrete":
		return NuclearMaterials.concrete(color)
	if kind == "metal":
		return NuclearMaterials.metal(color)
	return NuclearMaterials.painted_metal(color)

func _build_concourse_landmarks() -> void:
	var storm_ring := _landmark_root("StormRing")
	_register_ambient_motion(storm_ring, 0.002, 0.16, 2.9, 1)
	for index in 24:
		var angle := TAU * float(index) / 24.0
		var position := Vector3(cos(angle) * 57.8, 5.6, sin(angle) * 57.8)
		_add_landmark_part(storm_ring, _box_mesh(Vector3(15.0, 0.12, 0.12)), position, NuclearMaterials.metal(STEEL_MID, 0.3), Vector3(0.0, PI * 0.5 - angle, 0.0))

	var layered_terrain := _landmark_root("LayeredTerrain")
	for side in [-1.0, 1.0]:
		var deck_accent := RED_ACCENT_LIGHT if side > 0.0 else BLUE_ACCENT_LIGHT
		_add_landmark_part(layered_terrain, _box_mesh(Vector3(10.5, 0.08, 0.08)), Vector3(0.0, 3.15, side * 29.0), NuclearMaterials.emissive(deck_accent, 3.0))
	for x_sign in [-1.0, 1.0]:
		var corridor_accent := BLUE_ACCENT_LIGHT if x_sign < 0.0 else RED_ACCENT_LIGHT
		_add_landmark_part(layered_terrain, _box_mesh(Vector3(8.8, 0.08, 0.08)), Vector3(x_sign * 42.0, 3.58, -6.4), NuclearMaterials.emissive(corridor_accent, 3.0))
		_add_landmark_part(layered_terrain, _box_mesh(Vector3(8.8, 0.08, 0.08)), Vector3(x_sign * 42.0, 3.58, 6.4), NuclearMaterials.emissive(corridor_accent, 3.0))

func _build_launch_gates() -> void:
	_build_launch_gate(RED_GATE, RED_ACCENT)
	_build_launch_gate(BLUE_GATE, BLUE_ACCENT)

func _build_launch_gate(position: Vector3, accent: Color) -> void:
	var gate := Node3D.new()
	gate.name = "LaunchGate"
	gate.position = position
	add_child(gate)
	var frame_material := NuclearMaterials.metal(STEEL_MID, 0.34)
	var accent_material := NuclearMaterials.emissive(accent, 2.6)
	_add_landmark_part(gate, _box_mesh(Vector3(0.16, 3.4, 0.16)), Vector3(-0.72, 1.7, 0.0), frame_material)
	_add_landmark_part(gate, _box_mesh(Vector3(0.16, 3.4, 0.16)), Vector3(0.72, 1.7, 0.0), frame_material)
	_add_landmark_part(gate, _box_mesh(Vector3(1.55, 0.1, 0.1)), Vector3(0.0, 3.3, 0.0), accent_material)
	_add_landmark_part(gate, _box_mesh(Vector3(0.06, 2.7, 0.06)), Vector3(0.0, 1.5, 0.0), accent_material)

func _landmark_root(root_name: String, parent: Node3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	(parent if parent != null else self).add_child(root)
	return root

func _register_ambient_motion(root: Node3D, amplitude: float, frequency: float, phase: float, axis: int) -> void:
	if not _presentation_enabled or root == null:
		return
	_ambient_motion.append({
		"root": root,
		"amplitude": amplitude,
		"frequency": frequency,
		"phase": phase,
		"axis": axis,
		"base": root.rotation.x if axis == 0 else root.rotation.z if axis == 2 else root.rotation.y,
	})

func _add_landmark_part(parent: Node3D, mesh: Mesh, position: Vector3, material: ShaderMaterial, rotation: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	# Landmarks (storm-ring bars, deck/corridor accent strips, pad/core rings)
	# are presentation-only - never a route blocker or a `_build_solids()`
	# collision body - so they never need to read as cover in a shadow.  Every
	# one of them is a full extra draw across all shadow cascades otherwise;
	# see handoffs/HANDOFF.md's "Performance discipline" section.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _add_cylinder_landmark(parent: Node3D, position: Vector3, diameter: float, height: float, material: ShaderMaterial) -> void:
	var cylinder := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter * 0.5
	mesh.bottom_radius = diameter * 0.5
	mesh.height = height
	mesh.radial_segments = 48
	cylinder.mesh = mesh
	cylinder.position = position
	cylinder.material_override = material
	cylinder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cylinder)

func _box_mesh(dimensions: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return mesh

func _ramp_mesh(dimensions: Vector3, rise: float) -> ArrayMesh:
	var half_x := dimensions.x * 0.5
	var half_z := dimensions.z * 0.5
	var vertices := PackedVector3Array([
		Vector3(-half_x, 0.0, -half_z), Vector3(half_x, 0.0, -half_z),
		Vector3(-half_x, 0.0, half_z), Vector3(half_x, 0.0, half_z),
		Vector3(-half_x, rise, half_z), Vector3(half_x, rise, half_z),
	])
	var indices := PackedInt32Array([
		0, 2, 1, 0, 1, 5, 0, 5, 4,
		2, 4, 5, 2, 5, 3, 0, 4, 2, 1, 3, 5,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _segment_hits_route_blocker(origin: Vector3, destination: Vector3) -> bool:
	for blocker in _route_blockers:
		if _segment_hits_box(origin, destination, blocker.position, blocker.dimensions, 0.6, float(blocker.get("rotation_y", 0.0))):
			return true
	return false

func _segment_hits_box(origin: Vector3, destination: Vector3, center: Vector3, dimensions: Vector3, padding: float, rotation_y := 0.0) -> bool:
	var local_origin := (origin - center).rotated(Vector3.UP, -rotation_y)
	var local_destination := (destination - center).rotated(Vector3.UP, -rotation_y)
	var minimum := -dimensions * 0.5 - Vector3(padding, 1.0, padding)
	var maximum := dimensions * 0.5 + Vector3(padding, 1.0, padding)
	var start := Vector2(local_origin.x, local_origin.z)
	var end := Vector2(local_destination.x, local_destination.z)
	var delta := end - start
	var t_min := 0.0
	var t_max := 1.0
	for axis in 2:
		var value := start[axis]
		var direction := delta[axis]
		var low := minimum.x if axis == 0 else minimum.z
		var high := maximum.x if axis == 0 else maximum.z
		if is_zero_approx(direction):
			if value < low or value > high:
				return false
			continue
		var first := (low - value) / direction
		var last := (high - value) / direction
		if first > last:
			var swap := first
			first = last
			last = swap
		t_min = maxf(t_min, first)
		t_max = minf(t_max, last)
		if t_min > t_max:
			return false
	return true

func _point_in_solid(point: Vector3, padding := 0.0) -> bool:
	for solid in _solids:
		var center: Vector3 = solid.position
		var dimensions: Vector3 = solid.dimensions
		var local_point := (point - center).rotated(Vector3.UP, -float(solid.get("rotation_y", 0.0)))
		if str(solid.get("shape", "box")) == "cylinder":
			if Vector2(local_point.x, local_point.z).length() <= dimensions.x * 0.5 + padding and absf(local_point.y) <= dimensions.y * 0.5 + padding:
				return true
		elif absf(local_point.x) <= dimensions.x * 0.5 + padding and absf(local_point.y) <= dimensions.y * 0.5 + padding and absf(local_point.z) <= dimensions.z * 0.5 + padding:
			return true
	return false
