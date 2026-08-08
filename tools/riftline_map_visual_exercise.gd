extends SceneTree

const EXPECTED_MESHES := [
	"CONCRETE_Shell", "STEEL_Structure", "DARK_Systems", "RED_Identity",
	"BLUE_Identity", "EMISSIVE_RED_Indicators", "EMISSIVE_BLUE_Indicators",
	"EMISSIVE_NEUTRAL_Core",
]
const EXPECTED_TRIANGLES := 14020

func _initialize() -> void:
	var visual_scene: PackedScene = load("res://scenes/concourse_v2_visual.tscn")
	assert(visual_scene != null)
	var root := Node3D.new()
	get_root().add_child(root)
	var first: Node = visual_scene.instantiate()
	root.add_child(first)
	await process_frame
	assert(first.name == "ConcourseV2Visual")
	assert(first.get_child_count() == 1)
	var imported: Node = first.get_child(0)
	assert(imported.name == "ImportedEnvironment")
	var first_meshes := _collect_meshes(first)
	assert(first_meshes.size() == EXPECTED_MESHES.size())
	_assert_mesh_contract(first_meshes)
	_assert_scene_has_no_gameplay_nodes(first)
	_assert_no_frame_callbacks()

	var first_materials: Dictionary = {}
	for mesh_name_variant in EXPECTED_MESHES:
		var mesh_name: String = mesh_name_variant
		var mesh_instance: MeshInstance3D = first_meshes[mesh_name]
		var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		assert(material != null, "missing clean material override: %s" % mesh_name)
		assert(bool(material.get_shader_parameter("clean_surface")))
		assert(material.get_shader_parameter("detail_strength") == 0.0)
		assert(material.get_shader_parameter("grime_strength") == 0.0)
		assert(material.get_shader_parameter("edge_wear") == 0.0)
		assert(material.get_shader_parameter("ao_strength") == 0.0)
		first_materials[mesh_name] = material

	var cached_count := NuclearMaterials.cached_variant_count()
	assert(cached_count == EXPECTED_MESHES.size())
	var second: Node = visual_scene.instantiate()
	root.add_child(second)
	await process_frame
	var second_meshes := _collect_meshes(second)
	assert(NuclearMaterials.cached_variant_count() == cached_count)
	for mesh_name_variant in EXPECTED_MESHES:
		var mesh_name: String = mesh_name_variant
		var second_material: ShaderMaterial = (second_meshes[mesh_name] as MeshInstance3D).material_override as ShaderMaterial
		assert(second_material == first_materials[mesh_name], "environment material was not reused: %s" % mesh_name)
	_assert_shadowless_environment()

	print("Concourse V2 visual exercise: PASS")
	quit()

func _collect_meshes(node: Node) -> Dictionary:
	var result: Dictionary = {}
	for child_variant in node.get_children():
		var child: Node = child_variant
		if child is MeshInstance3D:
			result[child.name] = child
		result.merge(_collect_meshes(child))
	return result

func _assert_mesh_contract(meshes: Dictionary) -> void:
	var names: Array[String] = []
	for name_variant in meshes.keys():
		names.append(str(name_variant))
	names.sort()
	var expected_names: Array = EXPECTED_MESHES.duplicate()
	expected_names.sort()
	assert(names == expected_names)
	var total_triangles := 0
	var total_surfaces := 0
	for mesh_name_variant in EXPECTED_MESHES:
		var mesh_name: String = mesh_name_variant
		var mesh_instance: MeshInstance3D = meshes[mesh_name]
		assert(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		var mesh: Mesh = mesh_instance.mesh
		assert(mesh != null)
		assert(mesh.get_surface_count() == 1)
		total_surfaces += mesh.get_surface_count()
		var arrays: Array = mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total_triangles += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	assert(total_surfaces == EXPECTED_MESHES.size())
	assert(total_triangles == EXPECTED_TRIANGLES)

func _assert_scene_has_no_gameplay_nodes(root: Node) -> void:
	for child_variant in root.get_children():
		var child: Node = child_variant
		assert(not child is CollisionObject3D)
		assert(not child is Camera3D)
		assert(not child is Light3D)
		assert(not child is WorldEnvironment)
		if child != root.get_child(0):
			assert(child.get_script() == null)
		_assert_scene_has_no_gameplay_nodes(child)

func _assert_no_frame_callbacks() -> void:
	var script_text := FileAccess.get_file_as_string("res://scripts/concourse_v2_visual.gd")
	assert("func _process" not in script_text)
	assert("func _physics_process" not in script_text)

func _assert_shadowless_environment() -> void:
	var arena := RiftlineArena.new()
	arena._build_environment()
	var world_environment: WorldEnvironment = null
	for child_variant in arena.get_children():
		var child: Node = child_variant
		if child is Light3D:
			var light: Light3D = child as Light3D
			assert(not light.shadow_enabled)
		if child is WorldEnvironment:
			world_environment = child as WorldEnvironment
	assert(world_environment != null)
	var environment: Environment = world_environment.environment
	assert(environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR)
	assert(environment.ambient_light_energy > 1.0)
	assert(environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY)
	arena.free()
