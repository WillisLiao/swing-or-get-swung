extends SceneTree

## Locks the Concourse V2 environment shell contract.
##
## The shell carries nine roles rather than eight: the blueprint's lighting sheet
## separates OBJECTIVE FOCUS lime from LANDMARK LIGHTING lime, and one shared role
## collapsed the two so decorative containment inserts bloomed as hard as the
## reactor.  The eight-role organisation could not support that distinction.
##
## The load-bearing check here is `_assert_every_solid_is_visible`: the shell is
## authored directly from RiftlineMapLayout's collision records, so a gameplay
## solid without authored geometry over it is an invisible wall and must fail the
## build rather than ship.

const EXPECTED_MESHES := [
	"FLOOR_Concourse", "STRUCT_Gunmetal", "SYSTEMS_DarkSteel", "GRATE_Vent",
	"HAZARD_Stripe", "LIGHT_Amber", "LIGHT_White", "CORE_Lime", "ACCENT_Lime",
]
const EXPECTED_TRIANGLES := 25992
const EXPECTED_BOUNDS := AABB(Vector3(-60.499, -1.0, -60.499), Vector3(120.998, 8.23, 120.998))
const EXPECTED_MATERIAL_VARIANTS := 9
# Every authored box contributes its eight corners to the solid it covers; the
# six ramp wedges contribute three vertices inside the thin collision slab.
const MINIMUM_COVERAGE_VERTICES := 3

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
	_assert_import_bounds(first_meshes)
	_assert_scene_has_no_gameplay_nodes(first)
	_assert_no_frame_callbacks()
	_assert_every_solid_is_visible(first_meshes)

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
	_assert_surface_language(first_materials)
	_assert_no_faction_identity(first_materials)

	var cached_count := NuclearMaterials.cached_variant_count()
	assert(cached_count == EXPECTED_MATERIAL_VARIANTS)
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
	assert(names == expected_names, "imported mesh roles changed: %s" % str(names))
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
	assert(total_triangles == EXPECTED_TRIANGLES,
		"authored triangle count changed: %d" % total_triangles)

func _assert_import_bounds(meshes: Dictionary) -> void:
	var combined := AABB()
	var has_bounds := false
	for mesh_name_variant in EXPECTED_MESHES:
		var mesh_name: String = mesh_name_variant
		var mesh_instance: MeshInstance3D = meshes[mesh_name]
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if not has_bounds:
			combined = mesh_bounds
			has_bounds = true
		else:
			combined = combined.merge(mesh_bounds)
	assert(combined.position.is_equal_approx(EXPECTED_BOUNDS.position),
		"import bounds position changed: %s" % str(combined.position))
	assert(combined.size.is_equal_approx(EXPECTED_BOUNDS.size),
		"import bounds size changed: %s" % str(combined.size))

## The regression guard for the invisible-wall class of bug.  Presentation
## suppresses the greybox path whenever the authored shell loads, so anything
## the layout makes solid must also be something the shell draws.
func _assert_every_solid_is_visible(meshes: Dictionary) -> void:
	var buckets: Dictionary = {}
	for mesh_name_variant in EXPECTED_MESHES:
		var mesh_name: String = mesh_name_variant
		var mesh_instance: MeshInstance3D = meshes[mesh_name]
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var key := Vector3i(floori(vertex.x / 8.0), floori(vertex.y / 8.0), floori(vertex.z / 8.0))
			if not buckets.has(key):
				buckets[key] = PackedVector3Array()
			var bucket: PackedVector3Array = buckets[key]
			bucket.append(vertex)
			buckets[key] = bucket

	var layout: Dictionary = RiftlineMapLayout.build()
	var solids: Array = layout.get("solids", [])
	var uncovered: Array[String] = []
	for solid_variant in solids:
		var solid: Dictionary = solid_variant
		var position: Vector3 = solid.get("position", Vector3.ZERO)
		var dimensions: Vector3 = solid.get("dimensions", Vector3.ONE)
		var rotation_y := float(solid.get("rotation_y", 0.0))
		var half := dimensions * 0.5 + Vector3(0.05, 0.05, 0.05)
		var reach: float = maxf(half.x, half.z)
		var hits := 0
		var min_key := Vector3i(
			floori((position.x - reach) / 8.0),
			floori((position.y - half.y) / 8.0),
			floori((position.z - reach) / 8.0))
		var max_key := Vector3i(
			floori((position.x + reach) / 8.0),
			floori((position.y + half.y) / 8.0),
			floori((position.z + reach) / 8.0))
		for bx in range(min_key.x, max_key.x + 1):
			for by in range(min_key.y, max_key.y + 1):
				for bz in range(min_key.z, max_key.z + 1):
					var bucket_variant: Variant = buckets.get(Vector3i(bx, by, bz), null)
					if bucket_variant == null:
						continue
					var bucket: PackedVector3Array = bucket_variant
					for vertex in bucket:
						var local := (vertex - position).rotated(Vector3.UP, -rotation_y)
						if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
							hits += 1
		if hits < MINIMUM_COVERAGE_VERTICES:
			uncovered.append("%s(%d)" % [str(solid.get("name", "unnamed")), hits])
	assert(uncovered.is_empty(),
		"gameplay solids with no authored geometry over them: %s" % ", ".join(uncovered))

## Every shell role must actually carry a manufactured surface pattern.  A flat
## albedo is what made the previous shell's authored panel work invisible.
func _assert_surface_language(materials: Dictionary) -> void:
	var patterns: Dictionary = {}
	for mesh_name_variant in EXPECTED_MESHES:
		var mesh_name: String = mesh_name_variant
		var material: ShaderMaterial = materials[mesh_name]
		var pattern := int(material.get_shader_parameter("surface_pattern"))
		assert(pattern > 0, "shell role has no surface pattern: %s" % mesh_name)
		assert(float(material.get_shader_parameter("pattern_strength")) > 0.0)
		patterns[pattern] = true
	# The blueprint's surface families have to stay visually distinct from each
	# other, not all collapse onto one pattern.
	assert(patterns.size() >= 5, "shell uses too few distinct surface patterns")

## The facility is neutral: no role may read as a persistent team identity.
func _assert_no_faction_identity(materials: Dictionary) -> void:
	for mesh_name_variant in EXPECTED_MESHES:
		var mesh_name: String = mesh_name_variant
		assert(not mesh_name.contains("RED") and not mesh_name.contains("BLUE"),
			"shell role carries a team name: %s" % mesh_name)
		var material: ShaderMaterial = materials[mesh_name]
		for parameter in ["albedo", "emission_color", "pattern_accent"]:
			var color: Color = material.get_shader_parameter(parameter)
			# Judged by hue band rather than by channel dominance: the blueprint's
			# amber maintenance colour is warm on purpose and sits near 38 degrees,
			# well clear of the team red at 8 degrees.  Near-neutral gunmetals can
			# land anywhere on the wheel, so only saturated colours are tested.
			if color.s <= 0.35:
				continue
			var hue := color.h
			var team_red := hue < 0.055 or hue > 0.945
			var team_blue := hue > 0.528 and hue < 0.722
			assert(not team_red and not team_blue,
				"shell %s.%s reads as a team colour: %s (hue %.3f)"
					% [mesh_name, parameter, color.to_html(false), hue])

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
	# Uniform colour ambient must stay the dominant diffuse source, because the
	# map is shadowless and the directional key alone cannot light interiors.
	# The bound is on it being substantial, not on a specific value - the exact
	# energy is balanced against tonemap exposure and moves with it.
	assert(environment.ambient_light_energy > 0.5)
	assert(environment.ambient_light_energy > environment.tonemap_exposure * 0.5)
	assert(environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY)
	# Post contrast must not crush the shell's recesses to black; the shadowless
	# map has no other source of contact darkening to lose.
	assert(environment.adjustment_contrast <= 1.0)
	arena.free()
