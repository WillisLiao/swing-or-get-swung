extends SceneTree

# Guards the art foundation every other system builds on.
#
# Loading a .gdshader runs Godot's shader-language parser even headless, so a
# syntax error or an unknown built-in in `nuclear_pbr.gdshader` fails here rather
# than as a blank grey frame on a device. Also pins the NuclearMaterials surface
# so a future edit cannot quietly drop a uniform the map and arena rely on.

const EXPECTED_UNIFORMS := [
	"albedo", "metallic", "roughness", "detail_scale", "detail_strength",
	"normal_strength", "grime_strength", "edge_wear", "ao_strength",
	"emission_color", "emission_energy", "clean_surface",
]

func _initialize() -> void:
	var shader: Shader = load("res://shaders/nuclear_pbr.gdshader")
	assert(shader != null)
	assert(shader.code.length() > 0)

	# Every uniform the factory sets must actually exist on the shader. Godot
	# silently ignores set_shader_parameter for an unknown name, so a typo here
	# would only show up as a material that does not respond to its parameters.
	var declared: Array[String] = []
	for entry in shader.get_shader_uniform_list(true):
		var uniform: Dictionary = entry
		declared.append(str(uniform.get("name", "")))
	for name in EXPECTED_UNIFORMS:
		assert(name in declared, "nuclear_pbr is missing uniform: %s" % name)

	NuclearMaterials.clear_cache()

	var presets: Array[ShaderMaterial] = [
		NuclearMaterials.concrete(Color("6b6f72")),
		NuclearMaterials.metal(Color("8d949b")),
		NuclearMaterials.painted_metal(Color("3f5668")),
		NuclearMaterials.polymer(Color("2b2f33")),
		NuclearMaterials.marking(Color("d8c65a")),
		NuclearMaterials.emissive(Color("6fd7ff"), 4.0),
	]
	for material in presets:
		assert(material != null)
		assert(material.shader == shader)
		# A material that failed to take its parameters reports null here.
		assert(material.get_shader_parameter("roughness") != null)
		assert(material.get_shader_parameter("albedo") != null)

	assert(NuclearMaterials.cached_variant_count() == presets.size())

	# Identical requests must return the same instance: the arena builds hundreds
	# of meshes and each distinct ShaderMaterial costs its own uniform buffer.
	var first := NuclearMaterials.concrete(Color("6b6f72"))
	var second := NuclearMaterials.concrete(Color("6b6f72"))
	assert(first == second)
	assert(NuclearMaterials.cached_variant_count() == presets.size())

	# Differing parameters must not collide in the cache key.
	var rougher := NuclearMaterials.concrete(Color("6b6f72"), 0.71)
	assert(rougher != first)
	assert(NuclearMaterials.cached_variant_count() == presets.size() + 1)

	# Imported Concourse shells use the clean path: it keeps authored PBR
	# response but exits before procedural relief, grime, dust, and AO work.
	var clean := NuclearMaterials.clean_surface(Color("737a80"), 0.78, 0.0)
	var clean_again := NuclearMaterials.clean_surface(Color("737a80"), 0.78, 0.0)
	assert(clean == clean_again)
	assert(bool(clean.get_shader_parameter("clean_surface")))
	assert(clean.get_shader_parameter("detail_strength") == 0.0)
	assert(clean.get_shader_parameter("grime_strength") == 0.0)
	assert(clean.get_shader_parameter("edge_wear") == 0.0)
	assert(clean.get_shader_parameter("ao_strength") == 0.0)
	assert(NuclearMaterials.cached_variant_count() == presets.size() + 2)
	assert(clean != first)

	print("Nuclear materials exercise: PASS")
	quit()
