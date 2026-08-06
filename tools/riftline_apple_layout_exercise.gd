extends SceneTree

const RESPONSIVE := preload("res://scripts/riftline_responsive_layout.gd")

func _initialize() -> void:
	var control := Control.new()
	get_root().add_child(control)
	assert(str(ProjectSettings.get_setting("display/window/stretch/aspect", "keep")) == "expand")
	for viewport_size in [Vector2(1334.0, 750.0), Vector2(1024.0, 768.0), Vector2(2732.0, 2048.0)]:
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		control.size = viewport_size
		var safe := RESPONSIVE.safe_rect(control)
		assert(safe.size.x > 0.0 and safe.size.y > 0.0)
		assert(safe.position.x >= 0.0 and safe.position.y >= 0.0)
		assert(safe.end.x <= viewport_size.x and safe.end.y <= viewport_size.y)
	control.free()
	print("Riftline Apple layout exercise: PASS")
	quit()
