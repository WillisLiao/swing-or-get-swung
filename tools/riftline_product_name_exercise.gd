extends SceneTree

# The app icon label is deliberately the short form. iOS truncates a long
# `config/name` under the icon, so the full title "Swing or Get Swung" lives in
# docs and store copy while the home screen shows "SOGS".

func _initialize() -> void:
	assert(str(ProjectSettings.get_setting("application/config/name", "")) == "SOGS")
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	assert("Mobile" in features)

	# Landscape-only remains a hard product constraint for a competitive shooter.
	assert(int(ProjectSettings.get_setting("display/window/handheld/orientation", 0)) == 4)

	print("SOGS product name exercise: PASS")
	quit()
