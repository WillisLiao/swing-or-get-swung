extends SceneTree

const SENSOR_LANDSCAPE := 4

func _initialize() -> void:
	var orientation := int(ProjectSettings.get_setting("display/window/handheld/orientation", -1))
	assert(orientation == SENSOR_LANDSCAPE, "Riftline must follow both landscape sensor directions")
	print("Riftline orientation exercise: PASS")
	quit()
