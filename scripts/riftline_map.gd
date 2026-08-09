@tool
class_name RiftlineMap
extends Node3D

## Runtime owner for the immutable Competitive Concourse V2 layout.
##
## Collision and navigation are authored by RiftlineMapLayout.  This node only
## translates those records into StaticBody3D nodes and, when presentation is
## requested, loads the visual scene or builds a cheap greybox fallback.

enum Id { CONCOURSE }

const VISUAL_SCENE_PATH := "res://scenes/concourse_v2_visual.tscn"
const VISUAL_SCENE_RESOURCE: PackedScene = preload("res://scenes/concourse_v2_visual.tscn")
const CONCOURSE_RADIUS := RiftlineMapLayout.CONCOURSE_RADIUS
const CORE_SPAWN := RiftlineMapLayout.CORE_SPAWN

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

const RED_GATE := Vector3(5.0, 0.05, 43.0)
const BLUE_GATE := Vector3(-5.0, 0.05, -43.0)
const RED_LAUNCH_PAD := Vector3(0.0, 0.05, 52.0)
const BLUE_LAUNCH_PAD := Vector3(0.0, 0.05, -52.0)

@export var editor_preview_enabled := false

var _map_id: Id = Id.CONCOURSE
var _presentation_enabled := false
var _layout: Dictionary = {}
var _gates: Dictionary = {}
var _launch_pads: Dictionary = {}
var _spawns: Dictionary = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
var _solids: Array[Dictionary] = []
var _route_blockers: Array[Dictionary] = []
var _route_graphs: Dictionary = {}
var _tactical_facts: Dictionary = {}
var _objective_pulse_remaining := 0.0
var _objective_pulse_root: Node3D
var _visual_scene_resource: PackedScene
var _visual_missing_reported := false
var _route_data_valid := true
var _route_error_reported := false

func _ready() -> void:
	if Engine.is_editor_hint() and editor_preview_enabled:
		call_deferred("configure", Id.CONCOURSE, true)

func _process(delta: float) -> void:
	# The map is not a continuously animated system.  Processing is enabled
	# only for the short, event-driven objective pulse.
	if _objective_pulse_remaining <= 0.0:
		set_process(false)
		return
	_objective_pulse_remaining = maxf(0.0, _objective_pulse_remaining - delta)
	if _objective_pulse_root == null or not is_instance_valid(_objective_pulse_root):
		set_process(false)
		return
	var progress := 1.0 - _objective_pulse_remaining / 0.34
	var pulse := sin(progress * PI) if _objective_pulse_remaining > 0.0 else 0.0
	_objective_pulse_root.scale = Vector3.ONE * (1.0 + pulse * 0.035)
	if _objective_pulse_remaining <= 0.0:
		_objective_pulse_root.scale = Vector3.ONE
		set_process(false)

func configure(next_map_id: Id, presentation_enabled: bool) -> void:
	_clear_layout()
	_map_id = next_map_id
	_presentation_enabled = presentation_enabled
	if _presentation_enabled:
		# Preload the authored shell so the shipping gameplay scene cannot
		# silently fall back to the old procedural map on a device export.
		_visual_scene_resource = VISUAL_SCENE_RESOURCE
	_layout = RiftlineMapLayout.build()
	_load_public_layout_data()
	_build_route_graphs()
	_build_solids()
	if _presentation_enabled:
		_build_presentation()
	else:
		set_process(false)

func core_spawn_position() -> Vector3:
	return CORE_SPAWN

func launch_pad_positions() -> Dictionary:
	return _launch_pads.duplicate(true)

func gate_positions() -> Dictionary:
	return _gates.duplicate(true)

func spawn_points(team: Duelist.Team) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var points: Array = _spawns.get(team, [])
	for point_variant in points:
		var point: Vector3 = point_variant
		result.append(point)
	return result

func route_toward(origin: Vector3, destination: Vector3, lane_hint: StringName = &"auto") -> Vector3:
	if not _route_data_valid:
		return destination
	if origin.distance_squared_to(destination) < 4.0 or not _segment_hits_route_blocker(origin, destination):
		return destination
	var lane := _select_lane(lane_hint)
	var graph_variant: Variant = _route_graphs.get(lane, null)
	if not graph_variant is Dictionary:
		_report_route_error("route graph is missing: %s" % lane)
		return destination
	var graph: Dictionary = graph_variant
	if absf(origin.z) > 48.0 and absf(destination.z) <= 48.0:
		var base_waypoint := _base_exit_waypoint(origin, destination, graph)
		if base_waypoint != origin:
			return base_waypoint
	var path := _select_path(graph, origin, destination)
	if path.size() < 2:
		_report_route_error("route graph has no usable path for lane %s" % lane)
		return destination
	var nearest_index := _nearest_path_index(path, origin)
	var target_index := _nearest_path_index(path, destination)
	var step := 1 if target_index >= nearest_index else -1
	var next_index := clampi(nearest_index + step, 0, path.size() - 1)
	var waypoint: Vector3 = path[next_index]
	if waypoint.distance_squared_to(origin) < 0.25 and next_index != target_index:
		next_index = clampi(next_index + step, 0, path.size() - 1)
		waypoint = path[next_index]
	return waypoint

func map_id() -> Id:
	return _map_id

func is_spawn_clear(point: Vector3) -> bool:
	return not _point_in_solid(point)

func solid_count() -> int:
	return _solids.size()

func tactical_facts() -> Dictionary:
	return _tactical_facts.duplicate(true)

func pulse_objective() -> void:
	if not _presentation_enabled or _objective_pulse_root == null:
		return
	_objective_pulse_remaining = 0.34
	set_process(true)

func ambient_motion_count() -> int:
	# Deliberately zero: the map has no continuous decorative animation.
	return 0

func _clear_layout() -> void:
	set_process(false)
	for child in get_children():
		child.queue_free()
	_layout.clear()
	_gates.clear()
	_launch_pads.clear()
	_spawns = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
	_solids.clear()
	_route_blockers.clear()
	_route_graphs.clear()
	_tactical_facts.clear()
	_objective_pulse_remaining = 0.0
	_objective_pulse_root = null
	_visual_scene_resource = null
	_route_data_valid = true
	_route_error_reported = false

func _load_public_layout_data() -> void:
	var gate_data: Dictionary = _layout.get("gates", {})
	var pad_data: Dictionary = _layout.get("launch_pads", {})
	var spawn_data: Dictionary = _layout.get("spawns", {})
	var red_gate: Vector3 = gate_data.get("red", RED_GATE)
	var blue_gate: Vector3 = gate_data.get("blue", BLUE_GATE)
	var red_pad: Vector3 = pad_data.get("red", RED_LAUNCH_PAD)
	var blue_pad: Vector3 = pad_data.get("blue", BLUE_LAUNCH_PAD)
	_gates = {Duelist.Team.RED: red_gate, Duelist.Team.BLUE: blue_gate}
	_launch_pads = {Duelist.Team.RED: red_pad, Duelist.Team.BLUE: blue_pad}
	var red_spawns: Array = spawn_data.get("red", [])
	var blue_spawns: Array = spawn_data.get("blue", [])
	_spawns[Duelist.Team.RED] = red_spawns.duplicate()
	_spawns[Duelist.Team.BLUE] = blue_spawns.duplicate()
	_tactical_facts = _layout.get("tactical_facts", {}).duplicate(true)

func _build_route_graphs() -> void:
	var graph_data: Dictionary = _layout.get("route_graphs", {})
	for lane_variant in [&"auto", &"center", &"maintenance", &"overlook"]:
		var lane := str(lane_variant)
		var graph_variant: Variant = graph_data.get(lane, null)
		if not graph_variant is Dictionary:
			_report_route_error("layout route graph is missing: %s" % lane)
			continue
		var graph: Dictionary = graph_variant
		if not _validate_route_graph(lane, graph):
			_report_route_error("layout route graph is invalid: %s" % lane)
			continue
		_route_graphs[lane] = graph
	if _route_graphs.size() != 4:
		_route_data_valid = false

func _validate_route_graph(lane: String, graph: Dictionary) -> bool:
	var paths_variant: Variant = graph.get("paths", null)
	if not paths_variant is Dictionary:
		return false
	var paths: Dictionary = paths_variant
	for path_name in ["red_to_core", "blue_to_core", "core_to_red", "core_to_blue", "red_to_blue", "blue_to_red"]:
		var path_variant: Variant = paths.get(path_name, null)
		if not path_variant is Array or (path_variant as Array).size() < 2:
			return false
	var target_range_variant: Variant = graph.get("target_range", null)
	if not target_range_variant is Vector2:
		return false
	var target_range: Vector2 = target_range_variant
	var distance: float = graph.get("gate_core_distance", -1.0)
	if distance < 0.0 or lane.is_empty() or target_range.x > target_range.y:
		return false
	return true

func _build_solids() -> void:
	var solid_data: Array = _layout.get("solids", [])
	for solid_variant in solid_data:
		var solid: Dictionary = solid_variant
		if not _validate_solid_record(solid):
			push_error("RiftlineMap ignored malformed solid record: %s" % str(solid.get("name", "unnamed")))
			continue
		_solids.append(solid)
		if bool(solid.get("route_blocker", false)):
			_route_blockers.append(solid)
		_add_solid_node(solid)

func _validate_solid_record(solid: Dictionary) -> bool:
	for key in ["name", "shape", "position", "dimensions", "rotation_y", "rise", "material_role", "route_blocker", "casts_shadow"]:
		if not solid.has(key):
			return false
	return solid.position is Vector3 and solid.dimensions is Vector3

func _build_presentation() -> void:
	if _visual_scene_resource != null:
		var visual_instance := _visual_scene_resource.instantiate()
		visual_instance.name = "ConcourseV2Visual"
		add_child(visual_instance)
		# The authored shell merges the objective's lime plinth and containment
		# glow into map-wide role meshes, so there is no single node to scale and
		# _objective_pulse_root stays null - pulse_objective() is deliberately
		# inert on this path.  The core's own dynamic feedback belongs to the
		# NukeCore actor in RiftlineArena, not to the static environment.  Only
		# the procedural greybox fallback below builds a pulseable CoreMarker.
		_objective_pulse_root = null
		return
	if not FileAccess.file_exists(VISUAL_SCENE_PATH):
		if not _visual_missing_reported:
			push_error("RiftlineMap visual scene is missing: %s; using procedural greybox fallback" % VISUAL_SCENE_PATH)
			_visual_missing_reported = true
		_build_procedural_fallback()
		return
	if not _visual_missing_reported:
		push_error("RiftlineMap visual scene could not be loaded: %s; using procedural greybox fallback" % VISUAL_SCENE_PATH)
		_visual_missing_reported = true
	_build_procedural_fallback()

func _build_procedural_fallback() -> void:
	var core_marker := _landmark_root("CoreMarker")
	core_marker.position = Vector3(CORE_SPAWN.x, 0.0, CORE_SPAWN.z)
	_objective_pulse_root = core_marker
	_add_cylinder_landmark(core_marker, Vector3.ZERO, 2.3, 0.32, NuclearMaterials.clean_surface(STEEL_DARK, 0.7, 0.25))
	_add_cylinder_landmark(core_marker, Vector3(0.0, 0.2, 0.0), 1.45, 0.16, NuclearMaterials.clean_surface(CORE_ACCENT, 0.34, 0.10, CORE_ACCENT, 4.5))
	_add_pad_landmark(_launch_pads[Duelist.Team.RED], RED_ACCENT, "RedLaunchPad")
	_add_pad_landmark(_launch_pads[Duelist.Team.BLUE], BLUE_ACCENT, "BlueLaunchPad")
	_build_launch_gate(_gates[Duelist.Team.RED], RED_ACCENT, "RedLaunchGate")
	_build_launch_gate(_gates[Duelist.Team.BLUE], BLUE_ACCENT, "BlueLaunchGate")

func _add_solid_node(spec: Dictionary) -> void:
	var body := StaticBody3D.new()
	var body_name := str(spec.get("name", "Solid"))
	body.name = body_name
	var position: Vector3 = spec.get("position", Vector3.ZERO)
	body.position = position
	body.rotation.y = float(spec.get("rotation_y", 0.0))
	add_child(body)
	var shape_name := str(spec.get("shape", "box"))
	var dimensions: Vector3 = spec.get("dimensions", Vector3.ONE)
	var rise := float(spec.get("rise", 0.0))
	if _presentation_enabled and _visual_scene_resource == null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "GreyboxMesh"
		if shape_name == "ramp":
			mesh_instance.mesh = _ramp_mesh(dimensions, rise)
		elif shape_name == "cylinder":
			var cylinder_mesh := CylinderMesh.new()
			cylinder_mesh.top_radius = dimensions.x * 0.5
			cylinder_mesh.bottom_radius = dimensions.x * 0.5
			cylinder_mesh.height = dimensions.y
			cylinder_mesh.radial_segments = 40
			mesh_instance.mesh = cylinder_mesh
		else:
			var box_mesh := BoxMesh.new()
			box_mesh.size = dimensions
			mesh_instance.mesh = box_mesh
		mesh_instance.material_override = _material_for_role(str(spec.get("material_role", "concrete")))
		# V2 keeps casts_shadow in the layout for compatibility, but the shipping
		# presentation is globally shadowless so no route can hide behind a cast
		# shadow or pay for a map shadow caster.
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	if shape_name == "ramp":
		var ramp_shape := ConvexPolygonShape3D.new()
		var half_x := dimensions.x * 0.5
		var half_z := dimensions.z * 0.5
		# The overlook ramps rise along local +X so their high edge meets the
		# overlook deck at the route nodes authored in RiftlineMapLayout.
		ramp_shape.points = PackedVector3Array([
			Vector3(-half_x, 0.0, -half_z), Vector3(-half_x, 0.0, half_z),
			Vector3(half_x, 0.0, -half_z), Vector3(half_x, 0.0, half_z),
			Vector3(half_x, rise, -half_z), Vector3(half_x, rise, half_z),
		])
		collision.shape = ramp_shape
	elif shape_name == "cylinder":
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = dimensions.x * 0.5
		cylinder_shape.height = dimensions.y
		collision.shape = cylinder_shape
	else:
		var box_shape := BoxShape3D.new()
		box_shape.size = dimensions
		collision.shape = box_shape
	body.add_child(collision)

func _material_for_role(role: String) -> ShaderMaterial:
	match role:
		"floor":
			return NuclearMaterials.clean_surface(CONCRETE_FLOOR, 0.7)
		"outer_wall", "concrete", "central_tower", "central_baffle", "central_column", "low_cover", "bridge_floor", "bridge_rail":
			return NuclearMaterials.clean_surface(CONCRETE_LIGHT if role == "central_baffle" else CONCRETE_WALL, 0.7)
		"red_accent":
			return NuclearMaterials.clean_surface(RED_ACCENT, 0.52, 0.25)
		"blue_accent":
			return NuclearMaterials.clean_surface(BLUE_ACCENT, 0.52, 0.25)
		"steel":
			return NuclearMaterials.clean_surface(STEEL_MID, 0.32, 0.92)
		_:
			return NuclearMaterials.clean_surface(STEEL_DARK, 0.52, 0.25)

func _add_pad_landmark(pad_position: Vector3, accent: Color, node_name: String) -> void:
	var pad := _landmark_root(node_name)
	pad.position = pad_position
	_add_cylinder_landmark(pad, Vector3.ZERO, 4.2, 0.14, NuclearMaterials.clean_surface(STEEL_DARK, 0.7, 0.25))
	_add_cylinder_landmark(pad, Vector3(0.0, 0.02, 0.0), 3.4, 0.06, NuclearMaterials.clean_surface(STEEL_MID, 0.32, 0.92))
	_add_cylinder_landmark(pad, Vector3(0.0, 0.09, 0.0), 4.1, 0.06, NuclearMaterials.clean_surface(accent, 0.34, 0.10, accent, 3.6))

func _build_launch_gate(gate_position: Vector3, accent: Color, node_name: String) -> void:
	var gate := _landmark_root(node_name)
	gate.position = gate_position
	var frame_material := NuclearMaterials.clean_surface(STEEL_MID, 0.34, 0.92)
	var accent_material := NuclearMaterials.clean_surface(accent, 0.34, 0.10, accent, 2.6)
	_add_landmark_part(gate, _box_mesh(Vector3(0.16, 3.4, 0.16)), Vector3(-0.72, 1.7, 0.0), frame_material)
	_add_landmark_part(gate, _box_mesh(Vector3(0.16, 3.4, 0.16)), Vector3(0.72, 1.7, 0.0), frame_material)
	_add_landmark_part(gate, _box_mesh(Vector3(1.55, 0.1, 0.1)), Vector3(0.0, 3.3, 0.0), accent_material)
	_add_landmark_part(gate, _box_mesh(Vector3(0.06, 2.7, 0.06)), Vector3(0.0, 1.5, 0.0), accent_material)

func _landmark_root(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	return root

func _add_landmark_part(parent: Node3D, mesh: Mesh, part_position: Vector3, material: ShaderMaterial) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = part_position
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _add_cylinder_landmark(parent: Node3D, landmark_position: Vector3, diameter: float, height: float, material: ShaderMaterial) -> void:
	var cylinder := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter * 0.5
	mesh.bottom_radius = diameter * 0.5
	mesh.height = height
	mesh.radial_segments = 32
	cylinder.mesh = mesh
	cylinder.position = landmark_position
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
		Vector3(-half_x, 0.0, -half_z), Vector3(-half_x, 0.0, half_z),
		Vector3(half_x, 0.0, -half_z), Vector3(half_x, 0.0, half_z),
		Vector3(half_x, rise, -half_z), Vector3(half_x, rise, half_z),
	])
	var indices := PackedInt32Array([
		0, 2, 3, 0, 3, 1, 0, 4, 5, 0, 5, 1,
		2, 4, 5, 2, 5, 3, 0, 2, 4, 1, 3, 5,
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _select_lane(lane_hint: StringName) -> String:
	var requested := str(lane_hint)
	if requested == "auto":
		return "center"
	if _route_graphs.has(requested):
		return requested
	return "center"

func _select_path(graph: Dictionary, origin: Vector3, destination: Vector3) -> Array[Vector3]:
	var paths: Dictionary = graph.get("paths", {})
	var path_name := "red_to_core"
	if destination.z < -2.0 and origin.z >= -2.0:
		path_name = "red_to_blue"
	elif destination.z >= 2.0 and origin.z < 2.0:
		path_name = "core_to_red"
	elif destination.z < -2.0:
		path_name = "blue_to_core"
	var path_variant: Variant = paths.get(path_name, [])
	if not path_variant is Array:
		return []
	var path: Array[Vector3] = []
	for point_variant in path_variant:
		var point: Vector3 = point_variant
		path.append(point)
	return path

func _base_exit_waypoint(origin: Vector3, _destination: Vector3, graph: Dictionary) -> Vector3:
	var team_prefix := "red" if origin.z > 0.0 else "blue"
	var paths: Dictionary = graph.get("paths", {})
	var path_name := "red_to_core" if team_prefix == "red" else "blue_to_core"
	var path_variant: Variant = paths.get(path_name, [])
	if not path_variant is Array:
		return _destination
	var team_sign := 1.0 if team_prefix == "red" else -1.0
	var local_x := origin.x * team_sign
	var local_side_x := 13.0 if local_x >= 0.0 else -13.0
	var upper := Vector3(team_sign * local_side_x, 0.1, team_sign * 58.0)
	var lower := Vector3(team_sign * local_side_x, 0.1, team_sign * 48.0)
	if origin.distance_squared_to(upper) > 1.0:
		return upper
	if origin.distance_squared_to(lower) > 1.0:
		return lower
	return origin

func _nearest_path_index(path: Array[Vector3], point: Vector3) -> int:
	var best_index := 0
	var best_distance := INF
	for index in path.size():
		var distance := point.distance_squared_to(path[index])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index

func _report_route_error(message: String) -> void:
	_route_data_valid = false
	if _route_error_reported:
		return
	_route_error_reported = true
	push_error("RiftlineMap route data error: %s" % message)

func _segment_hits_route_blocker(origin: Vector3, destination: Vector3) -> bool:
	for blocker in _route_blockers:
		var position: Vector3 = blocker.get("position", Vector3.ZERO)
		var dimensions: Vector3 = blocker.get("dimensions", Vector3.ZERO)
		var rotation_y := float(blocker.get("rotation_y", 0.0))
		if str(blocker.get("shape", "box")) == "ramp":
			continue
		if _segment_hits_box(origin, destination, position, dimensions, 0.35, rotation_y):
			return true
	return false

func _segment_hits_box(origin: Vector3, destination: Vector3, center: Vector3, dimensions: Vector3, padding: float, rotation_y: float) -> bool:
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
		if str(solid.get("shape", "box")) == "ramp":
			# Ramps are walkable surfaces, not spawn blockers.
			continue
		var center: Vector3 = solid.get("position", Vector3.ZERO)
		var dimensions: Vector3 = solid.get("dimensions", Vector3.ZERO)
		var rotation_y := float(solid.get("rotation_y", 0.0))
		var local_point := (point - center).rotated(Vector3.UP, -rotation_y)
		if str(solid.get("shape", "box")) == "cylinder":
			if Vector2(local_point.x, local_point.z).length() <= dimensions.x * 0.5 + padding and absf(local_point.y) <= dimensions.y * 0.5 + padding:
				return true
		elif absf(local_point.x) <= dimensions.x * 0.5 + padding and absf(local_point.y) <= dimensions.y * 0.5 + padding and absf(local_point.z) <= dimensions.z * 0.5 + padding:
			return true
	return false
