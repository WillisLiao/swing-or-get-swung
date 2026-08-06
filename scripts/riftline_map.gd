@tool
class_name RiftlineMap
extends Node3D

const PULP_LIT := preload("res://shaders/pulp_lit.gdshader")
const STORMGLASS_SLATE := Color("33445a")
const STORMGLASS_DEEP := Color("1c2b43")
const CHALK_CERAMIC := Color("d8e0dc")
const OXIDIZED_COPPER := Color("895d4a")
const COPPER_LIGHT := Color("b77b5b")
const SEED_LIGHT := Color("fff0b0")

enum Id { DUEL_YARD, CONCOURSE }

@export var editor_preview_enabled := false
@export var editor_preview_map: Id = Id.CONCOURSE

const DUEL_SUN_SPAWN := Vector3(-15.0, 0.1, 6.0)
const DUEL_VOID_SPAWN := Vector3(16.0, 0.1, -6.0)
const DUEL_SUN_GATE := Vector3(-18.5, 0.05, 6.0)
const DUEL_VOID_GATE := Vector3(18.5, 0.05, -6.0)

const CONCOURSE_RADIUS := 60.0
const CONCOURSE_SEED := Vector3(0.0, 0.72, 0.0)
const CONCOURSE_SUN_GATE := Vector3(0.0, 0.05, 52.0)
const CONCOURSE_VOID_GATE := Vector3(0.0, 0.05, -52.0)
const CONCOURSE_SUN_SPAWNS := [
	Vector3(-7.5, 0.1, 48.0),
	Vector3(-2.5, 0.1, 48.0),
	Vector3(2.5, 0.1, 48.0),
	Vector3(7.5, 0.1, 48.0),
]
const CONCOURSE_VOID_SPAWNS := [
	Vector3(7.5, 0.1, -48.0),
	Vector3(2.5, 0.1, -48.0),
	Vector3(-2.5, 0.1, -48.0),
	Vector3(-7.5, 0.1, -48.0),
]

var _map_id: Id = Id.DUEL_YARD
var _presentation_enabled := false
var _seed_position := Vector3.ZERO
var _gates: Dictionary = {}
var _spawns: Dictionary = {Duelist.Team.SUN: [], Duelist.Team.VOID: []}
var _solids: Array[Dictionary] = []
var _route_blockers: Array[Dictionary] = []
var _route_nodes: Array[Vector3] = []
var _material_cache: Dictionary = {}
var _ambient_motion: Array[Dictionary] = []
var _ambient_time := 0.0
var _objective_pulse_remaining := 0.0
var _objective_pulse_root: Node3D

func _ready() -> void:
	if Engine.is_editor_hint() and editor_preview_enabled:
		call_deferred("configure", editor_preview_map, true)

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
	if _map_id == Id.CONCOURSE:
		_configure_concourse()
	else:
		_configure_duel_yard()
	_build_solids()
	if _presentation_enabled:
		_build_presentation()

func seed_position() -> Vector3:
	return _seed_position

func gate_positions() -> Dictionary:
	return _gates.duplicate(true)

func spawn_points(team: Duelist.Team) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in _spawns.get(team, []):
		result.append(point)
	return result

func route_toward(origin: Vector3, destination: Vector3) -> Vector3:
	if _map_id != Id.CONCOURSE or _route_nodes.is_empty():
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
	var sun_gate: Vector3 = _gates.get(Duelist.Team.SUN, Vector3.ZERO)
	var void_gate: Vector3 = _gates.get(Duelist.Team.VOID, Vector3.ZERO)
	var sun_home := sun_gate.lerp(_seed_position, 0.38)
	var void_home := void_gate.lerp(_seed_position, 0.38)
	if _map_id == Id.DUEL_YARD:
		return {
			"seed": _seed_position,
			"anchors": {
				"neutral_seed": _seed_position,
				"center_return": {"sun": sun_home, "void": void_home},
				"gate_escort": {"sun": void_gate, "void": sun_gate},
				"home_approach": {"sun": sun_home, "void": void_home},
			},
			"lane_posts": {"center": [Vector3(-7.0, 0.1, 0.0), Vector3(7.0, 0.1, 0.0)]},
		}
	return {
		"seed": _seed_position,
		"anchors": {
			"neutral_seed": _seed_position,
			"center_return": {"sun": Vector3(0.0, 0.1, 25.0), "void": Vector3(0.0, 0.1, -25.0)},
			"gate_escort": {"sun": Vector3(0.0, 0.1, -42.0), "void": Vector3(0.0, 0.1, 42.0)},
			"home_approach": {"sun": Vector3(10.0, 0.1, 40.0), "void": Vector3(-10.0, 0.1, -40.0)},
			"opposing_gate": {"sun": void_gate, "void": sun_gate},
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
	_seed_position = Vector3.ZERO
	_gates.clear()
	_spawns = {Duelist.Team.SUN: [], Duelist.Team.VOID: []}
	_solids.clear()
	_route_blockers.clear()
	_route_nodes.clear()
	_material_cache.clear()
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

func _configure_duel_yard() -> void:
	_seed_position = Vector3.ZERO
	_gates = {
		Duelist.Team.SUN: DUEL_SUN_GATE,
		Duelist.Team.VOID: DUEL_VOID_GATE,
	}
	_spawns[Duelist.Team.SUN] = [DUEL_SUN_SPAWN]
	_spawns[Duelist.Team.VOID] = [DUEL_VOID_SPAWN]
	_add_solid(Vector3(0, -0.5, 0), Vector3(44, 1, 32), Color("3d547c"), 0.0)
	_add_solid(Vector3(0, 3, -16), Vector3(44, 6, 1), Color("28496e"), 0.0)
	_add_solid(Vector3(0, 3, 16), Vector3(44, 6, 1), Color("28496e"), 0.0)
	_add_solid(Vector3(-22, 3, 0), Vector3(1, 6, 32), Color("28496e"), 0.0)
	_add_solid(Vector3(22, 3, 0), Vector3(1, 6, 32), Color("28496e"), 0.0)
	_add_solid(Vector3(-4, 1.7, -5), Vector3(3.2, 3.4, 3.2), Color("bd7254"), 0.0, true)
	_add_solid(Vector3(5, 1.7, 4), Vector3(3.2, 3.4, 3.2), Color("d39a52"), 0.0, true)
	_add_solid(Vector3(-10, 1.1, 6), Vector3(2.0, 2.2, 6.2), Color("496f8e"), 0.0, true)
	_add_solid(Vector3(11, 1.1, -6), Vector3(2.0, 2.2, 6.2), Color("496f8e"), 0.0, true)

func _configure_concourse() -> void:
	_seed_position = CONCOURSE_SEED
	_gates = {
		Duelist.Team.SUN: CONCOURSE_SUN_GATE,
		Duelist.Team.VOID: CONCOURSE_VOID_GATE,
	}
	_spawns[Duelist.Team.SUN] = CONCOURSE_SUN_SPAWNS.duplicate()
	_spawns[Duelist.Team.VOID] = CONCOURSE_VOID_SPAWNS.duplicate()

	# A true circular play space: cylinder floor plus tangent wall segments.
	_add_cylinder_solid(Vector3(0.0, -0.5, 0.0), CONCOURSE_RADIUS * 2.0, 1.0, STORMGLASS_SLATE)
	var wall_segments := 40
	var wall_length := TAU * (CONCOURSE_RADIUS + 0.5) / float(wall_segments) + 0.35
	for index in wall_segments:
		var angle := TAU * float(index) / float(wall_segments)
		var wall_position := Vector3(cos(angle) * (CONCOURSE_RADIUS + 0.5), 2.75, sin(angle) * (CONCOURSE_RADIUS + 0.5))
		_add_solid(wall_position, Vector3(wall_length, 5.5, 1.2), STORMGLASS_DEEP, 0.0, false, PI * 0.5 - angle)

	# Opposing bases sit inside the north/south rim with four clear spawn slots.
	_add_route_solid(Vector3(0.0, 1.45, 55.0), Vector3(25.0, 2.9, 1.4), OXIDIZED_COPPER)
	_add_route_solid(Vector3(-13.0, 1.2, 50.0), Vector3(1.4, 2.4, 10.0), COPPER_LIGHT)
	_add_route_solid(Vector3(13.0, 1.2, 50.0), Vector3(1.4, 2.4, 10.0), COPPER_LIGHT)
	_add_route_solid(Vector3(0.0, 1.45, -55.0), Vector3(25.0, 2.9, 1.4), STORMGLASS_DEEP)
	_add_route_solid(Vector3(-13.0, 1.2, -50.0), Vector3(1.4, 2.4, 10.0), CHALK_CERAMIC)
	_add_route_solid(Vector3(13.0, 1.2, -50.0), Vector3(1.4, 2.4, 10.0), CHALK_CERAMIC)

	# The central pickup room is an open ring with equal north/south entrances.
	var chamber_segments := 16
	for index in chamber_segments:
		var angle := TAU * float(index) / float(chamber_segments)
		if absf(cos(angle)) < 0.34:
			continue
		var chamber_position := Vector3(cos(angle) * 8.2, 1.25, sin(angle) * 8.2)
		_add_route_solid(chamber_position, Vector3(3.4, 2.5, 0.7), CHALK_CERAMIC if index % 2 == 0 else OXIDIZED_COPPER, PI * 0.5 - angle)

	# Free-standing cover follows the supplied top-down diagram.
	_add_concourse_diagram_cover()
	_add_concourse_layered_terrain()

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
		var half_name := "Sun" if side > 0.0 else "Void"
		var half_color := OXIDIZED_COPPER if side > 0.0 else STORMGLASS_DEEP
		_add_route_solid(Vector3(-3.2, 1.25, side * 43.0), Vector3(3.0, 2.5, 2.2), half_color, 0.0, "%sBaseCoverWest" % half_name)
		_add_route_solid(Vector3(3.2, 1.25, side * 43.0), Vector3(3.0, 2.5, 2.2), half_color, 0.0, "%sBaseCoverEast" % half_name)

	# Four tall rectangles on each side form the long oval around the objective.
	for x_sign in [-1.0, 1.0]:
		var lane_name := "West" if x_sign < 0.0 else "East"
		for index in 4:
			var z_position: float = [-24.0, -8.0, 8.0, 24.0][index]
			_add_route_solid(Vector3(x_sign * 32.0, 1.5, z_position), Vector3(2.2, 3.0, 5.2), CHALK_CERAMIC, 0.0, "%sCoverColumn%d" % [lane_name, index + 1])

	# Inset shoulder blocks reproduce the four corners of the sketched oval.
	for side in [-1.0, 1.0]:
		for x_sign in [-1.0, 1.0]:
			var half_name := "Sun" if side > 0.0 else "Void"
			var lane_name := "West" if x_sign < 0.0 else "East"
			var shoulder_color := COPPER_LIGHT if x_sign * side > 0.0 else STORMGLASS_DEEP
			_add_route_solid(Vector3(x_sign * 25.0, 1.5, side * 34.0), Vector3(2.5, 3.0, 5.0), shoulder_color, 0.0, "%s%sShoulderCover" % [half_name, lane_name])

	# Three low round covers guard each open entrance without closing the nuke room.
	for side in [-1.0, 1.0]:
		var half_name := "Sun" if side > 0.0 else "Void"
		for index in 3:
			var x_position: float = [-4.6, 0.0, 4.6][index]
			_add_cylinder_solid(Vector3(x_position, 0.6, side * 15.0), 2.3, 1.2, CHALK_CERAMIC, true, "%sCenterCover%d" % [half_name, index + 1])

func _add_concourse_layered_terrain() -> void:
	# Raised midfield decks create a playable upper route and a covered lower route.
	for side in [-1.0, 1.0]:
		var side_name := "Sun" if side > 0.0 else "Void"
		var deck_color := OXIDIZED_COPPER if side > 0.0 else STORMGLASS_DEEP
		var deck_z: float = float(side) * 29.0
		_add_solid(Vector3(0.0, 2.8, deck_z), Vector3(12.0, 0.6, 8.0), deck_color, 0.0, false, 0.0, "%sMidDeck" % side_name)
		_add_solid(Vector3(0.0, 3.65, deck_z - 3.72), Vector3(12.0, 1.15, 0.45), CHALK_CERAMIC, 0.0, false, 0.0, "%sMidDeckRailA" % side_name)
		_add_solid(Vector3(0.0, 3.65, deck_z + 3.72), Vector3(12.0, 1.15, 0.45), CHALK_CERAMIC, 0.0, false, 0.0, "%sMidDeckRailB" % side_name)
		for x_sign in [-1.0, 1.0]:
			var ramp_rotation := PI * 0.5 if x_sign < 0.0 else -PI * 0.5
			var ramp_side := "West" if x_sign < 0.0 else "East"
			_add_ramp(Vector3(x_sign * 9.0, 0.0, deck_z), Vector3(5.0, 0.2, 6.0), 3.1, deck_color, ramp_rotation, "%s%sRamp" % [side_name, ramp_side])
			for z_sign in [-1.0, 1.0]:
				var support_suffix := "A" if z_sign < 0.0 else "B"
				_add_route_solid(Vector3(x_sign * 5.25, 1.35, deck_z + z_sign * 2.8), Vector3(0.75, 2.7, 0.75), deck_color, 0.0, "%s%sSupport%s" % [side_name, ramp_side, support_suffix])

	# Covered outer corridors echo the reference's indoor/outdoor transitions.
	for x_sign in [-1.0, 1.0]:
		var corridor_name := "WestUnderpass" if x_sign < 0.0 else "EastUnderpass"
		var corridor_color := STORMGLASS_DEEP if x_sign < 0.0 else OXIDIZED_COPPER
		var corridor_x: float = float(x_sign) * 42.0
		_add_solid(Vector3(corridor_x, 3.25, 0.0), Vector3(10.0, 0.55, 14.0), corridor_color, 0.0, false, 0.0, corridor_name)
		_add_route_solid(Vector3(corridor_x - x_sign * 4.6, 1.4, 0.0), Vector3(0.8, 2.8, 14.0), CHALK_CERAMIC, 0.0, "%sInnerWall" % corridor_name)
		_add_route_solid(Vector3(corridor_x + x_sign * 4.6, 1.4, 0.0), Vector3(0.8, 2.8, 14.0), corridor_color, 0.0, "%sOuterWall" % corridor_name)

func _build_solids() -> void:
	for solid in _solids:
		_add_solid_node(solid)

func _build_presentation() -> void:
	if _map_id == Id.CONCOURSE:
		_build_concourse_landmarks()
	else:
		_build_duel_landmarks()
	_build_stormgates()

func _add_solid(position: Vector3, dimensions: Vector3, color: Color, emission: float, route_blocker := false, rotation_y := 0.0, node_name := "") -> void:
	var spec := {"position": position, "dimensions": dimensions, "color": color, "emission": emission, "rotation_y": rotation_y, "name": node_name}
	_solids.append(spec)
	if route_blocker:
		_route_blockers.append(spec)

func _add_route_solid(position: Vector3, dimensions: Vector3, color: Color, rotation_y := 0.0, node_name := "") -> void:
	_add_solid(position, dimensions, color, 0.0, true, rotation_y, node_name)

func _add_cylinder_solid(position: Vector3, diameter: float, height: float, color: Color, route_blocker := false, node_name := "") -> void:
	var spec := {
		"position": position,
		"dimensions": Vector3(diameter, height, diameter),
		"color": color,
		"emission": 0.0,
		"shape": "cylinder",
		"rotation_y": 0.0,
		"name": node_name,
	}
	_solids.append(spec)
	if route_blocker:
		_route_blockers.append(spec)

func _add_ramp(position: Vector3, dimensions: Vector3, rise: float, color: Color, rotation_y := 0.0, node_name := "") -> void:
	var spec := {"position": position, "dimensions": dimensions, "color": color, "emission": 0.0, "shape": "ramp", "rise": rise, "rotation_y": rotation_y, "name": node_name}
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
		mesh_instance.material_override = _pulp_material(spec.color, float(spec.emission))
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

func _build_duel_landmarks() -> void:
	_add_pulp_cylinder(Vector3(-4, 4.2, -5), 0.9, 1.7, Color("e5b46b"))
	_add_pulp_cylinder(Vector3(5, 4.2, 4), 0.9, 1.7, Color("e5b46b"))
	_add_emissive_rail(Vector3(0, 0.06, -10), Vector3(28, 0.08, 0.08), Color("a7dced"))
	_add_emissive_rail(Vector3(0, 0.06, 10), Vector3(28, 0.08, 0.08), Color("f4a55e"))
	_add_emissive_rail(Vector3(-15, 0.06, 0), Vector3(0.08, 0.08, 20), Color("a7dced"))
	_add_emissive_rail(Vector3(15, 0.06, 0), Vector3(0.08, 0.08, 20), Color("f4a55e"))

func _build_concourse_landmarks() -> void:
	# Base silhouettes mirror the hand sketch: blue north, orange south, four slots each.
	var sun_base := _landmark_root("SunBase")
	sun_base.position = CONCOURSE_SUN_GATE
	_register_ambient_motion(sun_base, 0.004, 0.31, 0.0, 2)
	_add_landmark_part(sun_base, _box_mesh(Vector3(24.0, 0.22, 0.22)), Vector3(0.0, 4.4, 2.8), COPPER_LIGHT, Vector3.ZERO, 0.8)
	for x_offset in [-7.5, -2.5, 2.5, 7.5]:
		_add_landmark_part(sun_base, _box_mesh(Vector3(1.5, 0.08, 2.4)), Vector3(x_offset, 0.06, -4.0), Color("ff9b4a"), Vector3.ZERO, 1.2)
	_add_landmark_part(sun_base, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(-12.0, 3.2, 2.8), CHALK_CERAMIC)
	_add_landmark_part(sun_base, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(12.0, 3.2, 2.8), CHALK_CERAMIC)

	var void_base := _landmark_root("VoidBase")
	void_base.position = CONCOURSE_VOID_GATE
	_register_ambient_motion(void_base, 0.004, 0.37, 0.8, 2)
	_add_landmark_part(void_base, _box_mesh(Vector3(24.0, 0.22, 0.22)), Vector3(0.0, 4.4, -2.8), Color("75dbff"), Vector3.ZERO, 0.8)
	for x_offset in [-7.5, -2.5, 2.5, 7.5]:
		_add_landmark_part(void_base, _box_mesh(Vector3(1.5, 0.08, 2.4)), Vector3(x_offset, 0.06, 4.0), Color("75dbff"), Vector3.ZERO, 1.2)
	_add_landmark_part(void_base, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(-12.0, 3.2, -2.8), CHALK_CERAMIC)
	_add_landmark_part(void_base, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(12.0, 3.2, -2.8), CHALK_CERAMIC)

	# The nuke model is supplied by the objective presenter; this room provides its pedestal and warnings.
	var pickup_room := _landmark_root("NukePickupRoom")
	_objective_pulse_root = pickup_room
	_register_ambient_motion(pickup_room, 0.006, 0.28, 1.3, 1)
	_add_pulp_cylinder(Vector3(0.0, 0.18, 0.0), 2.3, 0.32, STORMGLASS_DEEP, pickup_room)
	_add_pulp_cylinder(Vector3(0.0, 0.38, 0.0), 1.45, 0.16, SEED_LIGHT, pickup_room, 1.8)
	for direction in [-1.0, 1.0]:
		_add_landmark_part(pickup_room, _box_mesh(Vector3(5.4, 0.16, 0.16)), Vector3(0.0, 4.8, direction * 6.7), CHALK_CERAMIC, Vector3.ZERO, 0.45)
		_add_landmark_part(pickup_room, _box_mesh(Vector3(0.16, 4.6, 0.16)), Vector3(-2.6, 2.5, direction * 6.7), OXIDIZED_COPPER)
		_add_landmark_part(pickup_room, _box_mesh(Vector3(0.16, 4.6, 0.16)), Vector3(2.6, 2.5, direction * 6.7), OXIDIZED_COPPER)
	_add_emissive_rail(Vector3(0.0, 0.055, 10.5), Vector3(0.1, 0.08, 8.0), Color("ffb15c"), pickup_room)
	_add_emissive_rail(Vector3(0.0, 0.055, -10.5), Vector3(0.1, 0.08, 8.0), Color("75dbff"), pickup_room)

	var west_arc := _landmark_root("WestArc")
	_register_ambient_motion(west_arc, 0.003, 0.21, 1.9, 2)
	_add_emissive_rail(Vector3(-39.0, 0.06, 0.0), Vector3(0.08, 0.08, 52.0), Color("8bb8d5"), west_arc)
	_add_landmark_part(west_arc, _box_mesh(Vector3(0.18, 6.0, 0.18)), Vector3(-44.0, 3.0, 0.0), CHALK_CERAMIC, Vector3(0.0, 0.0, -0.14))

	var east_arc := _landmark_root("EastArc")
	_register_ambient_motion(east_arc, 0.003, 0.24, 2.4, 2)
	_add_emissive_rail(Vector3(39.0, 0.06, 0.0), Vector3(0.08, 0.08, 52.0), COPPER_LIGHT, east_arc)
	_add_landmark_part(east_arc, _box_mesh(Vector3(0.18, 6.0, 0.18)), Vector3(44.0, 3.0, 0.0), OXIDIZED_COPPER, Vector3(0.0, 0.0, 0.14))

	var storm_ring := _landmark_root("StormRing")
	_register_ambient_motion(storm_ring, 0.002, 0.16, 2.9, 1)
	for index in 24:
		var angle := TAU * float(index) / 24.0
		var position := Vector3(cos(angle) * 57.8, 5.6, sin(angle) * 57.8)
		_add_landmark_part(storm_ring, _box_mesh(Vector3(15.0, 0.12, 0.12)), position, Color("547da0"), Vector3(0.0, PI * 0.5 - angle, 0.0), 0.35)

	var layered_terrain := _landmark_root("LayeredTerrain")
	for side in [-1.0, 1.0]:
		var deck_accent := Color("ffb15c") if side > 0.0 else Color("75dbff")
		_add_emissive_rail(Vector3(0.0, 3.15, side * 29.0), Vector3(10.5, 0.08, 0.08), deck_accent, layered_terrain)
	for x_sign in [-1.0, 1.0]:
		var corridor_accent := Color("75dbff") if x_sign < 0.0 else Color("ffb15c")
		_add_emissive_rail(Vector3(x_sign * 42.0, 3.58, -6.4), Vector3(8.8, 0.08, 0.08), corridor_accent, layered_terrain)
		_add_emissive_rail(Vector3(x_sign * 42.0, 3.58, 6.4), Vector3(8.8, 0.08, 0.08), corridor_accent, layered_terrain)

func _build_stormgates() -> void:
	_build_stormgate(_gates[Duelist.Team.SUN], Color("ffb15c"), -1.0)
	_build_stormgate(_gates[Duelist.Team.VOID], Color("75dbff"), 1.0)

func _build_stormgate(position: Vector3, color: Color, lean: float) -> void:
	var gate := Node3D.new()
	gate.name = "Stormgate"
	gate.position = position
	add_child(gate)
	_add_landmark_part(gate, _box_mesh(Vector3(0.12, 3.4, 0.12)), Vector3(-0.72, 1.7, 0.0), color, Vector3(0.0, 0.0, lean * 0.08), 0.8)
	_add_landmark_part(gate, _box_mesh(Vector3(0.12, 3.4, 0.12)), Vector3(0.72, 1.7, 0.0), color, Vector3(0.0, 0.0, -lean * 0.08), 0.8)
	_add_landmark_part(gate, _box_mesh(Vector3(1.55, 0.08, 0.08)), Vector3(0.0, 3.3, 0.0), color.lerp(Color("fff4c7"), 0.3), Vector3(0.0, 0.0, lean * 0.08), 1.4)
	_add_landmark_part(gate, _box_mesh(Vector3(0.05, 2.7, 0.05)), Vector3(0.0, 1.5, 0.0), color, Vector3(0.0, 0.0, lean * 0.02), 2.0)

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

func _add_landmark_part(parent: Node3D, mesh: Mesh, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO, glow: float = 0.0) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = _pulp_material(color, glow)
	parent.add_child(instance)

func _add_emissive_rail(position: Vector3, dimensions: Vector3, color: Color, parent: Node3D = null) -> void:
	var rail := MeshInstance3D.new()
	rail.mesh = _box_mesh(dimensions)
	rail.position = position
	rail.material_override = _pulp_material(color, 5.5)
	(parent if parent != null else self).add_child(rail)

func _add_pulp_cylinder(position: Vector3, radius: float, height: float, color: Color, parent: Node3D = null, glow: float = 0.0) -> void:
	var cylinder := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.82
	mesh.bottom_radius = radius
	mesh.height = height
	cylinder.mesh = mesh
	cylinder.position = position
	cylinder.material_override = _pulp_material(color, glow)
	(parent if parent != null else self).add_child(cylinder)

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

func _pulp_material(color: Color, glow: float) -> ShaderMaterial:
	var cache_key := "%s|%.2f" % [color.to_html(false), glow]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
	var material := ShaderMaterial.new()
	material.shader = PULP_LIT
	material.set_shader_parameter("base_tint", color)
	material.set_shader_parameter("shadow_tint", Color("10213d").lerp(color, 0.2))
	material.set_shader_parameter("rim_tint", Color("dce9ef") if glow <= 0.0 else color)
	material.set_shader_parameter("rim_strength", 0.14 if glow <= 0.0 else 0.28)
	material.set_shader_parameter("glow_strength", glow)
	material.set_shader_parameter("brush_scale", 1.3)
	_material_cache[cache_key] = material
	return material

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
