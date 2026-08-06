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

const DUEL_SUN_SPAWN := Vector3(-15.0, 0.1, 6.0)
const DUEL_VOID_SPAWN := Vector3(16.0, 0.1, -6.0)
const DUEL_SUN_GATE := Vector3(-18.5, 0.05, 6.0)
const DUEL_VOID_GATE := Vector3(18.5, 0.05, -6.0)

const CONCOURSE_SEED := Vector3(0.0, 0.7, 0.0)
const CONCOURSE_SUN_GATE := Vector3(-56.0, 0.05, 0.0)
const CONCOURSE_VOID_GATE := Vector3(56.0, 0.05, 0.0)
const CONCOURSE_SUN_SPAWNS := [
	Vector3(-48.0, 0.1, -16.0),
	Vector3(-48.0, 0.1, -8.0),
	Vector3(-48.0, 0.1, 0.0),
	Vector3(-48.0, 0.1, 8.0),
	Vector3(-48.0, 0.1, 16.0),
]
const CONCOURSE_VOID_SPAWNS := [
	Vector3(48.0, 0.1, 16.0),
	Vector3(48.0, 0.1, 8.0),
	Vector3(48.0, 0.1, 0.0),
	Vector3(48.0, 0.1, -8.0),
	Vector3(48.0, 0.1, -16.0),
]

var _map_id: Id = Id.DUEL_YARD
var _presentation_enabled := false
var _seed_position := Vector3.ZERO
var _gates: Dictionary = {}
var _spawns: Dictionary = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
var _solids: Array[Dictionary] = []
var _route_blockers: Array[Dictionary] = []
var _route_nodes: Array[Vector3] = []
var _material_cache: Dictionary = {}
var _ambient_motion: Array[Dictionary] = []
var _ambient_time := 0.0
var _objective_pulse_remaining := 0.0
var _objective_pulse_root: Node3D

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
	var red_gate: Vector3 = _gates.get(Duelist.Team.RED, Vector3.ZERO)
	var blue_gate: Vector3 = _gates.get(Duelist.Team.BLUE, Vector3.ZERO)
	var red_home := red_gate.lerp(_seed_position, 0.38)
	var blue_home := blue_gate.lerp(_seed_position, 0.38)
	if _map_id == Id.DUEL_YARD:
		return {
			"seed": _seed_position,
			"anchors": {
				"neutral_seed": _seed_position,
				"center_return": {"red": red_home, "blue": blue_home},
				"gate_escort": {"red": blue_gate, "blue": red_gate},
				"home_approach": {"red": red_home, "blue": blue_home},
			},
			"lane_posts": {"center": [Vector3(-7.0, 0.1, 0.0), Vector3(7.0, 0.1, 0.0)]},
		}
	return {
		"seed": _seed_position,
		"anchors": {
			"neutral_seed": _seed_position,
			"center_return": {"red": Vector3(-26.0, 0.1, 0.0), "blue": Vector3(26.0, 0.1, 0.0)},
			"gate_escort": {"red": Vector3(40.0, 0.1, 0.0), "blue": Vector3(-40.0, 0.1, 0.0)},
			"home_approach": {"red": Vector3(-40.0, 0.1, 0.0), "blue": Vector3(40.0, 0.1, 0.0)},
			"opposing_gate": {"red": blue_gate, "blue": red_gate},
		},
		"lane_posts": {
			"windwalk": [Vector3(-34.0, 0.1, 25.0), Vector3(0.0, 0.1, 27.0), Vector3(34.0, 0.1, 25.0)],
			"relay_basin": [Vector3(-25.0, 0.1, 0.0), Vector3(0.0, 0.1, 0.0), Vector3(25.0, 0.1, 0.0)],
			"service_run": [Vector3(-34.0, 0.1, -25.0), Vector3(0.0, 0.1, -27.0), Vector3(34.0, 0.1, -25.0)],
		},
	}

func _clear_layout() -> void:
	for child in get_children():
		child.queue_free()
	_seed_position = Vector3.ZERO
	_gates.clear()
	_spawns = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
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
		Duelist.Team.RED: DUEL_SUN_GATE,
		Duelist.Team.BLUE: DUEL_VOID_GATE,
	}
	_spawns[Duelist.Team.RED] = [DUEL_SUN_SPAWN]
	_spawns[Duelist.Team.BLUE] = [DUEL_VOID_SPAWN]
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
		Duelist.Team.RED: CONCOURSE_SUN_GATE,
		Duelist.Team.BLUE: CONCOURSE_VOID_GATE,
	}
	_spawns[Duelist.Team.RED] = CONCOURSE_SUN_SPAWNS.duplicate()
	_spawns[Duelist.Team.BLUE] = CONCOURSE_VOID_SPAWNS.duplicate()

	# The footprint stays compatible with the existing match and network seams.
	# Neutral geometry owns the palette; team color only appears on gates and actors.
	_add_solid(Vector3(0, -0.5, 0), Vector3(124, 1, 76), STORMGLASS_SLATE, 0.0)
	_add_solid(Vector3(0, 3, -38), Vector3(124, 6, 1), STORMGLASS_DEEP, 0.0)
	_add_solid(Vector3(0, 3, 38), Vector3(124, 6, 1), STORMGLASS_DEEP, 0.0)
	_add_solid(Vector3(-62, 3, 0), Vector3(1, 6, 76), STORMGLASS_DEEP, 0.0)
	_add_solid(Vector3(62, 3, 0), Vector3(1, 6, 76), STORMGLASS_DEEP, 0.0)

	# Sun Dock: split exits and a protected central sight break.
	_add_route_solid(Vector3(-45, 1.55, -13), Vector3(2.4, 3.1, 7.0), CHALK_CERAMIC)
	_add_route_solid(Vector3(-43, 1.2, 0), Vector3(2.4, 2.4, 4.2), STORMGLASS_DEEP)
	_add_route_solid(Vector3(-45, 1.35, 13), Vector3(2.0, 2.7, 6.0), CHALK_CERAMIC)
	_add_route_solid(Vector3(-40.5, 0.9, -20), Vector3(5.0, 1.8, 3.0), OXIDIZED_COPPER)
	_add_route_solid(Vector3(-40.5, 0.9, 20), Vector3(5.0, 1.8, 3.0), COPPER_LIGHT)

	# Void Dock: equivalent timing with suspended-fin and slanted-canopy silhouettes.
	_add_route_solid(Vector3(45, 1.55, 13), Vector3(2.4, 3.1, 7.0), CHALK_CERAMIC)
	_add_route_solid(Vector3(43, 1.2, 0), Vector3(2.4, 2.4, 4.2), STORMGLASS_DEEP)
	_add_route_solid(Vector3(45, 1.35, -13), Vector3(2.0, 2.7, 6.0), CHALK_CERAMIC)
	_add_route_solid(Vector3(40.5, 0.9, 20), Vector3(5.0, 1.8, 3.0), OXIDIZED_COPPER)
	_add_route_solid(Vector3(40.5, 0.9, -20), Vector3(5.0, 1.8, 3.0), COPPER_LIGHT)

	# Relay Basin: four low plates keep the center dangerous without making it empty.
	_add_route_solid(Vector3(-8, 0.75, -5), Vector3(5.5, 1.5, 2.8), OXIDIZED_COPPER)
	_add_route_solid(Vector3(7, 0.9, 5), Vector3(5.0, 1.8, 3.2), COPPER_LIGHT)
	_add_route_solid(Vector3(-1, 0.7, 10), Vector3(3.0, 1.4, 2.6), CHALK_CERAMIC)
	_add_route_solid(Vector3(2, 0.72, -10), Vector3(3.4, 1.44, 2.8), STORMGLASS_DEEP)

	# Windwalk: a modest rise, two cover choices, and an uninterrupted outer edge.
	_add_route_solid(Vector3(-28, 1.0, 25), Vector3(4.5, 2.0, 3.2), CHALK_CERAMIC)
	_add_route_solid(Vector3(-8, 0.75, 29), Vector3(3.0, 1.5, 3.4), STORMGLASS_DEEP)
	_add_route_solid(Vector3(14, 1.15, 24), Vector3(4.4, 2.3, 3.0), CHALK_CERAMIC)
	_add_route_solid(Vector3(29, 0.75, 29), Vector3(3.0, 1.5, 3.2), STORMGLASS_DEEP)
	_add_ramp(Vector3(-19, 0.0, 20), Vector3(8.0, 1.6, 8.0), 1.6, CHALK_CERAMIC)

	# Service Run: warm, low, and readable through staggered under-gantry cover.
	_add_route_solid(Vector3(-29, 0.75, -27), Vector3(5.4, 1.5, 3.4), COPPER_LIGHT)
	_add_route_solid(Vector3(-10, 1.05, -24), Vector3(3.4, 2.1, 5.4), OXIDIZED_COPPER)
	_add_route_solid(Vector3(13, 0.8, -30), Vector3(5.8, 1.6, 3.2), COPPER_LIGHT)
	_add_route_solid(Vector3(30, 1.0, -25), Vector3(4.2, 2.0, 3.8), OXIDIZED_COPPER)

	_route_nodes = [
		Vector3(-39, 0.1, 25), Vector3(-27, 0.1, 25), Vector3(-11, 0.1, 26), Vector3(11, 0.1, 26), Vector3(27, 0.1, 25), Vector3(39, 0.1, 25),
		Vector3(-39, 0.1, 0), Vector3(-24, 0.1, 0), Vector3(-12, 0.1, 0), Vector3(0, 0.1, 0), Vector3(12, 0.1, 0), Vector3(24, 0.1, 0), Vector3(39, 0.1, 0),
		Vector3(-39, 0.1, -25), Vector3(-27, 0.1, -25), Vector3(-11, 0.1, -26), Vector3(11, 0.1, -26), Vector3(27, 0.1, -25), Vector3(39, 0.1, -25),
	]

func _build_solids() -> void:
	for solid in _solids:
		_add_solid_node(solid)

func _build_presentation() -> void:
	if _map_id == Id.CONCOURSE:
		_build_concourse_landmarks()
	else:
		_build_duel_landmarks()
	_build_stormgates()

func _add_solid(position: Vector3, dimensions: Vector3, color: Color, emission: float, route_blocker := false) -> void:
	var spec := {"position": position, "dimensions": dimensions, "color": color, "emission": emission}
	_solids.append(spec)
	if route_blocker:
		_route_blockers.append(spec)

func _add_route_solid(position: Vector3, dimensions: Vector3, color: Color) -> void:
	_add_solid(position, dimensions, color, 0.0, true)

func _add_ramp(position: Vector3, dimensions: Vector3, rise: float, color: Color) -> void:
	var spec := {"position": position, "dimensions": dimensions, "color": color, "emission": 0.0, "shape": "ramp", "rise": rise}
	_solids.append(spec)
	_route_blockers.append(spec)

func _add_solid_node(spec: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.position = spec.position
	add_child(body)
	if _presentation_enabled:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _ramp_mesh(spec.dimensions, float(spec.get("rise", 0.0))) if str(spec.get("shape", "box")) == "ramp" else _box_mesh(spec.dimensions)
		mesh_instance.material_override = _pulp_material(spec.color, float(spec.emission))
		body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape: Shape3D
	if str(spec.get("shape", "box")) == "ramp":
		var ramp_shape := ConvexPolygonShape3D.new()
		var half_x := float(spec.dimensions.x) * 0.5
		var half_z := float(spec.dimensions.z) * 0.5
		ramp_shape.points = PackedVector3Array([
			Vector3(-half_x, 0.0, -half_z), Vector3(half_x, 0.0, -half_z),
			Vector3(-half_x, 0.0, half_z), Vector3(half_x, 0.0, half_z),
			Vector3(-half_x, float(spec.rise), half_z), Vector3(half_x, float(spec.rise), half_z),
		])
		shape = ramp_shape
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
	# No vertex colors are needed for this authored layer; every new part uses
	# the shared pulp shader's uniform palette instead.
	var red_dock := _landmark_root("RedDock")
	_register_ambient_motion(red_dock, 0.004, 0.31, 0.0, 1)
	_add_landmark_part(red_dock, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(-7.0, 3.4, 0.0), CHALK_CERAMIC)
	_add_landmark_part(red_dock, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(7.0, 3.4, 0.0), CHALK_CERAMIC, Vector3(0.0, 0.0, 0.08))
	_add_landmark_part(red_dock, _box_mesh(Vector3(14.2, 0.24, 0.24)), Vector3(0.0, 6.8, 0.0), COPPER_LIGHT, Vector3.ZERO, 0.55)
	_add_landmark_part(red_dock, _box_mesh(Vector3(0.16, 3.5, 0.16)), Vector3(-2.6, 2.0, 2.6), OXIDIZED_COPPER, Vector3(0.0, 0.0, -0.2))
	_add_landmark_part(red_dock, _box_mesh(Vector3(0.16, 3.5, 0.16)), Vector3(2.6, 2.0, 2.6), OXIDIZED_COPPER, Vector3(0.0, 0.0, 0.2))
	_add_landmark_part(red_dock, _box_mesh(Vector3(5.5, 0.18, 0.18)), Vector3(0.0, 3.75, 2.6), CHALK_CERAMIC, Vector3(0.0, 0.0, 0.0), 0.35)
	_add_landmark_part(red_dock, _box_mesh(Vector3(5.5, 0.16, 0.16)), Vector3(0.0, 1.0, -3.4), COPPER_LIGHT)
	_add_landmark_part(red_dock, _box_mesh(Vector3(0.16, 1.9, 0.16)), Vector3(-2.3, 0.95, -3.4), OXIDIZED_COPPER)
	_add_landmark_part(red_dock, _box_mesh(Vector3(0.16, 1.9, 0.16)), Vector3(2.3, 0.95, -3.4), OXIDIZED_COPPER)

	var blue_dock := _landmark_root("BlueDock")
	_register_ambient_motion(blue_dock, 0.004, 0.44, 0.7, 1)
	blue_dock.scale.x = -1.0
	_add_landmark_part(blue_dock, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(-7.0, 3.4, 0.0), CHALK_CERAMIC)
	_add_landmark_part(blue_dock, _box_mesh(Vector3(0.22, 7.0, 0.22)), Vector3(7.0, 3.4, 0.0), CHALK_CERAMIC, Vector3(0.0, 0.0, -0.08))
	_add_landmark_part(blue_dock, _box_mesh(Vector3(14.2, 0.24, 0.24)), Vector3(0.0, 6.8, 0.0), OXIDIZED_COPPER, Vector3.ZERO, 0.55)
	_add_landmark_part(blue_dock, _box_mesh(Vector3(0.18, 5.0, 0.18)), Vector3(-4.5, 3.9, -2.8), STORMGLASS_DEEP, Vector3(0.0, 0.0, -0.28))
	_add_landmark_part(blue_dock, _box_mesh(Vector3(0.18, 5.0, 0.18)), Vector3(0.0, 3.0, -2.8), STORMGLASS_DEEP, Vector3(0.0, 0.0, -0.18))
	_add_landmark_part(blue_dock, _box_mesh(Vector3(0.18, 5.0, 0.18)), Vector3(4.5, 4.3, -2.8), STORMGLASS_DEEP, Vector3(0.0, 0.0, -0.34))
	_add_landmark_part(blue_dock, _box_mesh(Vector3(10.5, 0.18, 0.18)), Vector3(0.0, 5.9, -2.8), CHALK_CERAMIC, Vector3(0.0, 0.0, 0.12), 0.35)

	var relay_basin := _landmark_root("RelayBasin")
	_objective_pulse_root = relay_basin
	_register_ambient_motion(relay_basin, 0.006, 0.27, 1.2, 2)
	_add_landmark_part(relay_basin, _box_mesh(Vector3(5.0, 0.18, 0.18)), Vector3(-2.5, 4.9, 0.0), CHALK_CERAMIC, Vector3(0.0, 0.0, -0.16), 0.55)
	_add_landmark_part(relay_basin, _box_mesh(Vector3(5.0, 0.18, 0.18)), Vector3(2.5, 4.9, 0.0), CHALK_CERAMIC, Vector3(0.0, 0.0, 0.16), 0.55)
	_add_landmark_part(relay_basin, _box_mesh(Vector3(0.18, 0.18, 4.2)), Vector3(0.0, 4.9, -2.1), OXIDIZED_COPPER, Vector3(0.16, 0.0, 0.0), 0.4)
	_add_landmark_part(relay_basin, _box_mesh(Vector3(0.18, 0.18, 4.2)), Vector3(0.0, 4.9, 2.1), OXIDIZED_COPPER, Vector3(-0.16, 0.0, 0.0), 0.4)
	_add_pulp_cylinder(Vector3(0.0, 1.35, 0.0), 0.42, 2.7, SEED_LIGHT, relay_basin, 3.2)
	for frame_data in [[Vector3(-4.5, 0.0, 3.5), -0.15], [Vector3(4.5, 0.0, -3.5), 0.15]]:
		var frame := _landmark_root("SignalFrame", relay_basin)
		frame.position = frame_data[0]
		frame.rotation.y = float(frame_data[1])
		_add_landmark_part(frame, _box_mesh(Vector3(0.14, 4.6, 0.14)), Vector3(-1.0, 2.0, 0.0), CHALK_CERAMIC)
		_add_landmark_part(frame, _box_mesh(Vector3(0.14, 4.6, 0.14)), Vector3(1.0, 2.0, 0.0), CHALK_CERAMIC)
		_add_landmark_part(frame, _box_mesh(Vector3(2.2, 0.14, 0.14)), Vector3(0.0, 4.1, 0.0), SEED_LIGHT, Vector3.ZERO, 1.4)

	var windwalk := _landmark_root("Windwalk")
	_register_ambient_motion(windwalk, 0.005, 0.22, 1.9, 2)
	var mast := _landmark_root("TransitMast", windwalk)
	mast.position = Vector3(-8.0, 0.0, 0.0)
	mast.rotation.z = -0.12
	_add_landmark_part(mast, _box_mesh(Vector3(0.28, 8.0, 0.28)), Vector3.ZERO, CHALK_CERAMIC)
	_add_landmark_part(mast, _box_mesh(Vector3(4.6, 0.16, 0.16)), Vector3(1.15, 2.8, 0.0), CHALK_CERAMIC, Vector3(0.0, 0.0, 0.18), 0.6)
	_add_landmark_part(mast, _box_mesh(Vector3(0.14, 2.0, 0.14)), Vector3(2.2, 2.15, 0.0), COPPER_LIGHT, Vector3(0.0, 0.0, -0.22), 0.8)
	_add_emissive_rail(Vector3(0.0, 0.06, 8.0), Vector3(78.0, 0.08, 0.08), Color("8bb8d5"), windwalk)
	_add_landmark_part(windwalk, _box_mesh(Vector3(0.14, 0.14, 8.0)), Vector3(-27.0, 2.2, -1.0), CHALK_CERAMIC, Vector3(0.0, 0.0, -0.16), 0.3)
	_add_landmark_part(windwalk, _box_mesh(Vector3(0.14, 0.14, 8.0)), Vector3(27.0, 2.2, -1.0), CHALK_CERAMIC, Vector3(0.0, 0.0, 0.16), 0.3)

	var service_run := _landmark_root("ServiceRun")
	_register_ambient_motion(service_run, 0.003, 0.36, 2.4, 1)
	var gantry := _landmark_root("MaintenanceGantry", service_run)
	gantry.position = Vector3(8.0, 0.0, 0.0)
	_add_landmark_part(gantry, _box_mesh(Vector3(0.22, 4.8, 0.22)), Vector3(-2.0, 2.0, 0.0), OXIDIZED_COPPER)
	_add_landmark_part(gantry, _box_mesh(Vector3(0.22, 4.8, 0.22)), Vector3(2.0, 2.0, 0.0), OXIDIZED_COPPER)
	_add_landmark_part(gantry, _box_mesh(Vector3(4.4, 0.18, 0.18)), Vector3(0.0, 4.2, 0.0), COPPER_LIGHT, Vector3.ZERO, 1.0)
	_add_pulp_cylinder(Vector3(-18.0, 1.0, 0.0), 0.8, 1.8, OXIDIZED_COPPER, service_run)
	_add_pulp_cylinder(Vector3(20.0, 0.8, 0.0), 0.65, 1.4, COPPER_LIGHT, service_run)
	_add_landmark_part(service_run, _box_mesh(Vector3(7.0, 2.4, 0.16)), Vector3(-19.0, 2.4, 0.0), STORMGLASS_DEEP, Vector3.ZERO, 0.2)
	_add_landmark_part(service_run, _box_mesh(Vector3(7.0, 2.4, 0.16)), Vector3(22.0, 2.4, 0.0), STORMGLASS_DEEP, Vector3.ZERO, 0.2)
	_add_emissive_rail(Vector3(0.0, 0.06, -8.0), Vector3(78.0, 0.08, 0.08), COPPER_LIGHT, service_run)

	var storm_horizon := _landmark_root("StormHorizon")
	_register_ambient_motion(storm_horizon, 0.003, 0.18, 2.9, 2)
	storm_horizon.position = Vector3(0.0, 0.0, 42.0)
	_add_landmark_part(storm_horizon, _box_mesh(Vector3(18.0, 0.22, 0.22)), Vector3(-20.0, 9.0, 0.0), STORMGLASS_DEEP, Vector3(0.0, 0.0, -0.1))
	_add_landmark_part(storm_horizon, _box_mesh(Vector3(0.22, 15.0, 0.22)), Vector3(-28.0, 3.0, 0.0), OXIDIZED_COPPER, Vector3(0.0, 0.0, -0.18))
	_add_landmark_part(storm_horizon, _box_mesh(Vector3(0.22, 15.0, 0.22)), Vector3(-12.0, 3.0, 0.0), STORMGLASS_DEEP, Vector3(0.0, 0.0, 0.18))
	_add_landmark_part(storm_horizon, _box_mesh(Vector3(22.0, 0.18, 0.18)), Vector3(19.0, 5.0, 0.0), CHALK_CERAMIC, Vector3(0.0, 0.0, 0.12), 0.22)

func _build_stormgates() -> void:
	_build_stormgate(_gates[Duelist.Team.RED], Color("ff6a57"), -1.0)
	_build_stormgate(_gates[Duelist.Team.BLUE], Color("75dbff"), 1.0)

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
		if _segment_hits_box(origin, destination, blocker.position, blocker.dimensions, 0.6):
			return true
	return false

func _segment_hits_box(origin: Vector3, destination: Vector3, center: Vector3, dimensions: Vector3, padding: float) -> bool:
	var minimum := center - dimensions * 0.5 - Vector3(padding, 1.0, padding)
	var maximum := center + dimensions * 0.5 + Vector3(padding, 1.0, padding)
	var start := Vector2(origin.x, origin.z)
	var end := Vector2(destination.x, destination.z)
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
		if absf(point.x - center.x) <= dimensions.x * 0.5 + padding and absf(point.y - center.y) <= dimensions.y * 0.5 + padding and absf(point.z - center.z) <= dimensions.z * 0.5 + padding:
			return true
	return false
