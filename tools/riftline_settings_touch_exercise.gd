extends SceneTree

# Regression coverage for the settings-panel touch-capture bug: pressing one
# slider and sliding onto another control used to re-hit-test on every drag
# frame, moving the second slider, toggling chips repeatedly, or closing the
# panel.  This drives real InputEventScreenTouch / InputEventScreenDrag
# objects through DuelHud._gui_input() to prove the fix.

func _press(hud: DuelHud, index: int, position: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = position
	touch.pressed = true
	hud._gui_input(touch)

func _release(hud: DuelHud, index: int, position: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = position
	touch.pressed = false
	hud._gui_input(touch)

func _drag(hud: DuelHud, index: int, position: Vector2, relative: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = position
	drag.relative = relative
	hud._gui_input(drag)

func _new_hud() -> DuelHud:
	var hud := DuelHud.new()
	get_root().add_child(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1280.0, 588.0)
	return hud

func _initialize() -> void:
	var hud := _new_hud()
	await process_frame
	hud.open_settings()
	var panel := hud._settings_panel()
	var camera_track := hud._camera_track_rect(panel)
	var ads_track := hud._ads_track_rect(panel)
	var aim_chip := Rect2(panel.position + Vector2(24, 188), Vector2(142, 44))
	var camera_point := camera_track.position + Vector2(camera_track.size.x * 0.3, camera_track.size.y * 0.5)

	# (a) press the CAMERA slider, then drag horizontally on it: the slider
	# must still track a normal drag on the control it captured.
	var starting_ads := hud.ads_sensitivity
	_press(hud, 1, camera_point)
	var after_press_camera := hud.camera_sensitivity
	var drag_point := camera_track.position + Vector2(camera_track.size.x * 0.75, camera_track.size.y * 0.5)
	_drag(hud, 1, drag_point, drag_point - camera_point)
	# The drag must keep tracking the slider it captured, not freeze it.
	assert(not is_equal_approx(hud.camera_sensitivity, after_press_camera))
	assert(is_equal_approx(hud.ads_sensitivity, starting_ads))
	_release(hud, 1, drag_point)
	assert(hud._settings_open)

	# (b) press the CAMERA slider, then drag DOWN onto the ADS slider without
	# lifting: only the captured (camera) control may respond; ads_sensitivity
	# and every chip must stay exactly where they were.
	hud.camera_sensitivity = 1.0
	hud.ads_sensitivity = 0.72
	hud._aim_toggle = false
	hud.gyro_enabled = false
	_press(hud, 2, camera_point)
	var ads_point := ads_track.position + Vector2(ads_track.size.x * 0.3, ads_track.size.y * 0.5)
	_drag(hud, 2, ads_point, ads_point - camera_point)
	assert(is_equal_approx(hud.ads_sensitivity, 0.72))
	assert(not hud._aim_toggle)
	assert(not hud.gyro_enabled)
	assert(hud._settings_open)
	_release(hud, 2, ads_point)

	# (c) press the CAMERA slider, then drag onto the AIM chip: the chip must
	# not toggle.
	hud.camera_sensitivity = 1.0
	hud._aim_toggle = false
	_press(hud, 3, camera_point)
	var aim_point := aim_chip.get_center()
	_drag(hud, 3, aim_point, aim_point - camera_point)
	assert(not hud._aim_toggle)
	_release(hud, 3, aim_point)

	# (d) a captured drag that wanders across the AIM chip repeatedly must
	# never toggle it, even across many drag frames in the same gesture.
	hud._aim_toggle = false
	_press(hud, 4, camera_point)
	for step in 6:
		var wander := aim_chip.get_center() + Vector2(step * 2.0, 0.0)
		_drag(hud, 4, wander, Vector2(2.0, 0.0))
	assert(not hud._aim_toggle)
	_release(hud, 4, aim_chip.get_center())

	# (e) a press landing directly on the AIM chip toggles it exactly once.
	hud._aim_toggle = false
	_press(hud, 5, aim_chip.get_center())
	assert(hud._aim_toggle)
	_drag(hud, 5, aim_chip.get_center() + Vector2(4.0, 0.0), Vector2(4.0, 0.0))
	assert(hud._aim_toggle)
	_release(hud, 5, aim_chip.get_center())
	assert(hud._aim_toggle)

	# (f) a captured drag that leaves the panel entirely must not close it -
	# only a press whose own down event lands outside the panel may close it.
	_press(hud, 6, camera_point)
	var far_outside := panel.position + Vector2(-400.0, -400.0)
	_drag(hud, 6, far_outside, far_outside - camera_point)
	assert(hud._settings_open)
	_release(hud, 6, far_outside)
	assert(hud._settings_open)

	# (g) a drag whose index does not match the captured touch is ignored
	# entirely: a second, uncaptured finger must not hijack or double-apply.
	hud.camera_sensitivity = 1.0
	hud.ads_sensitivity = 0.72
	_press(hud, 7, camera_point)
	var mismatched_point := ads_track.position + Vector2(ads_track.size.x * 0.6, ads_track.size.y * 0.5)
	_drag(hud, 8, mismatched_point, Vector2(20.0, 0.0))
	assert(is_equal_approx(hud.ads_sensitivity, 0.72))
	_release(hud, 7, camera_point)

	# A press that genuinely starts outside the panel still closes it.
	var outside_press := panel.position + Vector2(-40.0, -40.0)
	_press(hud, 9, outside_press)
	assert(not hud._settings_open)

	hud.free()
	print("SOGS settings touch exercise: PASS")
	quit()
