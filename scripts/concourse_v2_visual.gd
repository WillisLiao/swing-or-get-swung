class_name ConcourseV2Visual
extends Node3D

## Runtime-only visual shell for Concourse V2.
##
## The imported GLB owns presentation geometry only.  Gameplay collision stays
## in RiftlineMap, and the GLB's architecture is authored directly from the same
## gameplay-solid contract, so every surface the player can collide with is a surface
## the player can see.
##
## Each imported role binds to one blueprint surface family.  The nine opaque
## families plus one ballistic-glass family
## carry a deliberate luminance ladder: the previous shell painted 11,752
## triangles of authored panel work at a 1.06:1 ratio against their own
## background, which is why a fully modelled facility rendered as flat grey.
## The floor sits below the walls, per the blueprint's own material balance
## guideline - "keep floors darker than walls for clear player silhouette
## contrast" - so players read against the ground rather than dissolving into it.
##
## Emission energies form a deliberate ladder against the environment's glow
## threshold.  Nuclear-lime is deliberately two roles, not one: the blueprint's
## lighting sheet separates OBJECTIVE FOCUS from LANDMARK LIGHTING, and while
## they shared a role the decorative containment inserts bloomed exactly as hard
## as the reactor and out-massed it inside its own arena.  CORE_Lime alone
## crosses the glow threshold, so the objective is the single surface in the map
## that blooms; ACCENT_Lime sits below it and marks vertical access without
## competing.  Amber service lighting and white lane lighting stay below it too.
##
## None of the roles carries a team identity - the facility is neutral by
## construction, not by mirroring two faction colours.

const SURFACE_NONE := 0
const SURFACE_FLOOR_PLATE := 1
const SURFACE_WALL_PANEL := 2
const SURFACE_SCRATCHED_STEEL := 3
const SURFACE_GRATE := 4
const SURFACE_HAZARD := 5
const SURFACE_LIGHT_STRIP := 6
const SURFACE_CONCRETE := 7
const GLASS_ROLE := "GLASS_Ballistic"

## albedo, roughness, metallic, emission_color, emission_energy,
## surface_pattern, pattern_scale, pattern_strength, pattern_accent
const ENVIRONMENT_MATERIALS := {
	"FLOOR_Concourse": [
		Color("3b3c39"), 0.84, 0.08, Color("000000"), 0.0,
		SURFACE_FLOOR_PLATE, 1.0, 1.0, Color("2a2a26"),
	],
	"STRUCT_Gunmetal": [
		Color("5b5d58"), 0.66, 0.10, Color("000000"), 0.0,
		SURFACE_WALL_PANEL, 1.0, 1.0, Color("34352f"),
	],
	"SYSTEMS_DarkSteel": [
		Color("34352f"), 0.58, 0.22, Color("000000"), 0.0,
		SURFACE_SCRATCHED_STEEL, 1.35, 0.70, Color("232419"),
	],
	"GRATE_Vent": [
		Color("393a34"), 0.70, 0.12, Color("000000"), 0.0,
		SURFACE_GRATE, 1.0, 1.0, Color("17180f"),
	],
	"HAZARD_Stripe": [
		Color("c8871c"), 0.72, 0.10, Color("000000"), 0.0,
		SURFACE_HAZARD, 1.0, 1.0, Color("15171a"),
	],
	"LIGHT_Amber": [
		Color("d99a2b"), 0.46, 0.05, Color("ffab33"), 1.05,
		SURFACE_LIGHT_STRIP, 1.0, 1.0, Color("241a0c"),
	],
	"LIGHT_White": [
		Color("9a9890"), 0.42, 0.05, Color("f2f0e8"), 0.70,
		SURFACE_LIGHT_STRIP, 1.0, 1.0, Color("1c2226"),
	],
	"ACCENT_Lime": [
		Color("7eae16"), 0.44, 0.04, Color("93c81a"), 0.62,
		SURFACE_SCRATCHED_STEEL, 0.55, 0.55, Color("46600b"),
	],
	"CORE_Lime": [
		Color("9ad414"), 0.40, 0.04, Color("b6ec1e"), 3.30,
		SURFACE_SCRATCHED_STEEL, 0.55, 0.55, Color("5c7d0e"),
	],
}

var _environment_materials: Dictionary = {}
static var _cached_ballistic_glass: StandardMaterial3D

func _ready() -> void:
	for mesh_name_variant in ENVIRONMENT_MATERIALS.keys():
		var mesh_name: String = mesh_name_variant
		var recipe: Array = ENVIRONMENT_MATERIALS[mesh_name]
		var albedo: Color = recipe[0]
		var roughness: float = recipe[1]
		var metallic: float = recipe[2]
		var emission_color: Color = recipe[3]
		var emission_energy: float = recipe[4]
		var surface_pattern: int = recipe[5]
		var pattern_scale: float = recipe[6]
		var pattern_strength: float = recipe[7]
		var pattern_accent: Color = recipe[8]
		_environment_materials[mesh_name] = NuclearMaterials.clean_surface(
			albedo, roughness, metallic, emission_color, emission_energy,
			surface_pattern, pattern_scale, pattern_strength, pattern_accent,
		)
	_environment_materials[GLASS_ROLE] = _ballistic_glass_material()
	_bind_geometry(self)

func _ballistic_glass_material() -> StandardMaterial3D:
	if _cached_ballistic_glass != null:
		return _cached_ballistic_glass
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.38, 0.72, 0.76, 0.26)
	glass.metallic = 0.05
	glass.roughness = 0.18
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.disable_receive_shadows = true
	_cached_ballistic_glass = glass
	return _cached_ballistic_glass

func _bind_geometry(node: Node) -> void:
	for child_variant in node.get_children():
		var child: Node = child_variant
		if child is GeometryInstance3D:
			var geometry: GeometryInstance3D = child as GeometryInstance3D
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if geometry is MeshInstance3D:
				var mesh_instance: MeshInstance3D = geometry as MeshInstance3D
				var material_variant: Variant = _environment_materials.get(mesh_instance.name, null)
				if material_variant == null:
					push_error("ConcourseV2Visual unknown imported mesh prefix: %s" % mesh_instance.name)
				else:
					mesh_instance.material_override = material_variant as Material
		_bind_geometry(child)
