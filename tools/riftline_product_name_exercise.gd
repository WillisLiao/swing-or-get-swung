extends SceneTree

func _initialize() -> void:
	assert(str(ProjectSettings.get_setting("application/config/name", "")) == "WhoYouPeekin")
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	assert("Mobile" in features)

	print("Riftline product name exercise: PASS")
	quit()
