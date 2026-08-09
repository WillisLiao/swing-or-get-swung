extends SceneTree

## Dumps the frozen RiftlineMapLayout collision contract to JSON.
##
## The Concourse art pipeline authors its visible architecture directly from
## these records, so every gameplay solid gets a matching visible surface and no
## collider can become an invisible wall.  Blender reads the file this writes.
##
## Usage:
##   godot --headless --script tools/riftline_map_layout_dump.gd -- --out=/tmp/layout.json

func _initialize() -> void:
	var out_path := "res://../concourse_v2_layout.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_path = argument.substr(6)
	var layout: Dictionary = RiftlineMapLayout.build()
	var solids: Array = layout.get("solids", [])
	var records: Array = []
	for solid_variant in solids:
		var solid: Dictionary = solid_variant
		var position: Vector3 = solid.get("position", Vector3.ZERO)
		var dimensions: Vector3 = solid.get("dimensions", Vector3.ONE)
		records.append({
			"name": str(solid.get("name", "")),
			"shape": str(solid.get("shape", "box")),
			"position": [position.x, position.y, position.z],
			"dimensions": [dimensions.x, dimensions.y, dimensions.z],
			"rotation_y": float(solid.get("rotation_y", 0.0)),
			"rise": float(solid.get("rise", 0.0)),
			"material_role": str(solid.get("material_role", "concrete")),
			"route_blocker": bool(solid.get("route_blocker", false)),
		})
	var core_spawn: Vector3 = layout.get("core_spawn", Vector3.ZERO)
	var gates: Dictionary = layout.get("gates", {})
	var pads: Dictionary = layout.get("launch_pads", {})
	var red_gate: Vector3 = gates.get("red", Vector3.ZERO)
	var blue_gate: Vector3 = gates.get("blue", Vector3.ZERO)
	var red_pad: Vector3 = pads.get("red", Vector3.ZERO)
	var blue_pad: Vector3 = pads.get("blue", Vector3.ZERO)
	var payload := {
		"version": RiftlineMapLayout.VERSION,
		"concourse_radius": RiftlineMapLayout.CONCOURSE_RADIUS,
		"core_spawn": [core_spawn.x, core_spawn.y, core_spawn.z],
		"gates": {
			"red": [red_gate.x, red_gate.y, red_gate.z],
			"blue": [blue_gate.x, blue_gate.y, blue_gate.z],
		},
		"launch_pads": {
			"red": [red_pad.x, red_pad.y, red_pad.z],
			"blue": [blue_pad.x, blue_pad.y, blue_pad.z],
		},
		"solids": records,
	}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("layout dump could not open %s" % out_path)
		quit(1)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("Riftline layout dump: solids=%d path=%s" % [records.size(), out_path])
	quit()
