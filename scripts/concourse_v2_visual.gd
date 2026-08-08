class_name ConcourseV2Visual
extends Node3D

## Runtime-only visual shell for Concourse V2.
##
## The imported GLB owns presentation geometry only.  Gameplay collision stays
## in RiftlineMap, and all imported surfaces are rebound to the shared clean
## NuclearMaterials cache so the authored hard-surface geometry supplies the
## detail without paying for the procedural noise path.

const ENVIRONMENT_MATERIALS := {
	"CONCRETE_Shell": [Color("737a80"), 0.78, 0.0, Color("000000"), 0.0],
	"STEEL_Structure": [Color("667078"), 0.34, 0.92, Color("000000"), 0.0],
	"DARK_Systems": [Color("2b3339"), 0.54, 0.25, Color("000000"), 0.0],
	"RED_Identity": [Color("b94238"), 0.48, 0.25, Color("000000"), 0.0],
	"BLUE_Identity": [Color("3e78b7"), 0.48, 0.25, Color("000000"), 0.0],
	"EMISSIVE_RED_Indicators": [Color("e05245"), 0.34, 0.10, Color("e05245"), 2.8],
	"EMISSIVE_BLUE_Indicators": [Color("65b7ff"), 0.34, 0.10, Color("65b7ff"), 2.8],
	"EMISSIVE_NEUTRAL_Core": [Color("ffd36b"), 0.32, 0.10, Color("ffd36b"), 3.8],
}

var _environment_materials: Dictionary = {}

func _ready() -> void:
	for mesh_name_variant in ENVIRONMENT_MATERIALS.keys():
		var mesh_name: String = mesh_name_variant
		var recipe: Array = ENVIRONMENT_MATERIALS[mesh_name]
		var albedo: Color = recipe[0]
		var roughness: float = recipe[1]
		var metallic: float = recipe[2]
		var emission_color: Color = recipe[3]
		var emission_energy: float = recipe[4]
		_environment_materials[mesh_name] = NuclearMaterials.clean_surface(
			albedo, roughness, metallic, emission_color, emission_energy,
		)
	_bind_geometry(self)

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
					mesh_instance.material_override = material_variant as ShaderMaterial
		_bind_geometry(child)
