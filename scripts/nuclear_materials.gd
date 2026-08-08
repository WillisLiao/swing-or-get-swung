class_name NuclearMaterials
extends RefCounted

# Single source of truth for how Nuclear Rush surfaces look.
#
# Every mesh in the game - map geometry, characters, weapons, the core - asks
# this factory for its material, so the realistic metal-roughness look stays
# consistent without any imported texture.  Materials are cached per parameter
# set: the arena builds hundreds of meshes and each distinct ShaderMaterial
# costs a uniform buffer, so re-use matters on mobile.

const NUCLEAR_PBR := preload("res://shaders/nuclear_pbr.gdshader")

static var _cache: Dictionary = {}

static func _material_key(
	albedo: Color,
	roughness: float,
	metallic: float,
	emission_color: Color,
	emission_energy: float,
	clean_path: bool,
	detail_scale: float,
	detail_strength: float,
	normal_strength: float,
	grime_strength: float,
	edge_wear: float,
	ao_strength: float
) -> String:
	return "%s|%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%.3f" % [
		"clean" if clean_path else "detailed", albedo.to_html(false), roughness, metallic,
		detail_scale, detail_strength, normal_strength, grime_strength, edge_wear,
		ao_strength, emission_color.to_html(false), emission_energy,
	]

static func _build_material(
	albedo: Color,
	roughness: float,
	metallic: float,
	emission_color: Color,
	emission_energy: float,
	clean_path: bool,
	detail_scale: float,
	detail_strength: float,
	normal_strength: float,
	grime_strength: float,
	edge_wear: float,
	ao_strength: float
) -> ShaderMaterial:
	var key := _material_key(
		albedo, roughness, metallic, emission_color, emission_energy, clean_path,
		detail_scale, detail_strength, normal_strength, grime_strength, edge_wear,
		ao_strength,
	)
	var cached: Variant = _cache.get(key, null)
	if cached != null:
		return cached as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = NUCLEAR_PBR
	material.set_shader_parameter("albedo", albedo)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("metallic", metallic)
	material.set_shader_parameter("clean_surface", clean_path)
	material.set_shader_parameter("detail_scale", detail_scale)
	material.set_shader_parameter("detail_strength", detail_strength)
	material.set_shader_parameter("normal_strength", normal_strength)
	material.set_shader_parameter("grime_strength", grime_strength)
	material.set_shader_parameter("edge_wear", edge_wear)
	material.set_shader_parameter("ao_strength", ao_strength)
	material.set_shader_parameter("emission_color", emission_color)
	material.set_shader_parameter("emission_energy", emission_energy)
	_cache[key] = material
	return material

## Full control. Every preset below funnels through this.
static func surface(
	albedo: Color,
	roughness: float,
	metallic: float = 0.0,
	detail_scale: float = 1.6,
	detail_strength: float = 0.35,
	normal_strength: float = 1.0,
	grime_strength: float = 0.30,
	edge_wear: float = 0.25,
	ao_strength: float = 0.50,
	emission_color: Color = Color(0.0, 0.0, 0.0, 1.0),
	emission_energy: float = 0.0
) -> ShaderMaterial:
	return _build_material(
		albedo, roughness, metallic, emission_color, emission_energy, false,
		detail_scale, detail_strength, normal_strength, grime_strength, edge_wear,
		ao_strength,
	)

## Clean manufactured surface for imported map and character shells.
## The shader keeps the same PBR response but skips all procedural detail work.
static func clean_surface(
	albedo: Color,
	roughness: float,
	metallic: float = 0.0,
	emission_color: Color = Color(0.0, 0.0, 0.0, 1.0),
	emission_energy: float = 0.0
) -> ShaderMaterial:
	return _build_material(
		albedo, roughness, metallic, emission_color, emission_energy, true,
		1.6, 0.0, 0.0, 0.0, 0.0, 0.0,
	)

## Poured/precast structural concrete. Coarse relief, no metallic response.
static func concrete(albedo: Color, roughness: float = 0.86) -> ShaderMaterial:
	return surface(albedo, roughness, 0.0, 0.9, 0.42, 1.3, 0.38, 0.34, 0.62)

## Bare structural steel, hull plate, blast doors.
static func metal(albedo: Color, roughness: float = 0.38) -> ShaderMaterial:
	return surface(albedo, roughness, 0.92, 3.1, 0.26, 0.9, 0.26, 0.16, 0.44)

## Painted or coated metal - most base and cover geometry.
static func painted_metal(albedo: Color, roughness: float = 0.52) -> ShaderMaterial:
	return surface(albedo, roughness, 0.25, 2.2, 0.28, 0.85, 0.30, 0.22, 0.48)

## Matte polymer: character gear, grips, cabling.
static func polymer(albedo: Color, roughness: float = 0.68) -> ShaderMaterial:
	return surface(albedo, roughness, 0.05, 4.0, 0.20, 0.7, 0.18, 0.10, 0.40)

## Hazard striping, floor decals, painted lane markings.
static func marking(albedo: Color, emission_energy: float = 0.35) -> ShaderMaterial:
	return surface(albedo, 0.62, 0.0, 1.4, 0.18, 0.5, 0.16, 0.12, 0.32, albedo, emission_energy)

## Light panels, indicator strips, the core's glow.
static func emissive(color: Color, energy: float = 3.0) -> ShaderMaterial:
	return surface(color, 0.34, 0.10, 2.0, 0.12, 0.4, 0.06, 0.04, 0.20, color, energy)

## Test/tooling helper: how many distinct materials the cache has handed out.
static func cached_variant_count() -> int:
	return _cache.size()

## Tooling helper so headless exercises can start from a clean cache.
static func clear_cache() -> void:
	_cache.clear()
