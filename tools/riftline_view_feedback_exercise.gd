extends SceneTree

func _initialize() -> void:
	var narrow_vertical := Duelist.vertical_fov_for_horizontal(Duelist.DEFAULT_HORIZONTAL_FOV, 4.0 / 3.0)
	var wide_vertical := Duelist.vertical_fov_for_horizontal(Duelist.DEFAULT_HORIZONTAL_FOV, 16.0 / 9.0)
	assert(narrow_vertical > wide_vertical)
	assert(is_equal_approx(Duelist.vertical_fov_for_horizontal(80.0, 1.0), 80.0))
	assert(absf(Duelist.vertical_fov_for_horizontal(80.0, 2622.0 / 1206.0) - 42.2) < 0.2)
	assert(Duelist.ADS_HORIZONTAL_FOV_RATIO < 1.0)
	assert(is_equal_approx(DuelHud.reload_progress_for(Duelist.M4_RELOAD_SECONDS), 0.0))
	assert(is_equal_approx(DuelHud.reload_progress_for(0.0), 1.0))
	assert(DuelHud.reload_progress_for(-4.0) == 1.0)
	assert(Duelist.M4_HIP_STRAFE_MULTIPLIER == 0.76)
	assert(Duelist.ADS_MOVEMENT_MULTIPLIER == 0.82)
	assert(Duelist.KNIFE_RANGE == 2.1)
	assert(Duelist.KNIFE_DAMAGE == 50.0)
	assert(Duelist.KNIFE_COOLDOWN == 0.55)

	print("Riftline view and feedback exercise: PASS")
	quit()
