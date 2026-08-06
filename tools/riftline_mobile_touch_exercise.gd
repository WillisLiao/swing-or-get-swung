extends SceneTree

var _requested_drill := ""

func _assert_vector_near(actual: Vector2, expected: Vector2, tolerance: float = 0.001) -> void:
	assert(actual.distance_to(expected) <= tolerance)

func _capture_drill(drill: String) -> void:
	_requested_drill = drill

func _initialize() -> void:
	# The practice panel is the first touch surface on iOS.  Exercise the real
	# Control input seam so a phone ScreenTouch cannot regress to the desktop
	# mouse-only path.
	var practice_panel := RiftlinePracticePanel.new()
	get_root().add_child(practice_panel)
	practice_panel.size = Vector2(1280.0, 588.0)
	practice_panel.drill_requested.connect(_capture_drill)
	practice_panel.show_entry("solo")
	await process_frame
	var enter_touch := InputEventScreenTouch.new()
	enter_touch.index = 1
	enter_touch.position = practice_panel._button_rects["enter"].get_center()
	enter_touch.pressed = true
	practice_panel._gui_input(enter_touch)
	assert(_requested_drill == "solo")
	assert(not practice_panel.visible)

	_requested_drill = ""
	practice_panel.show_entry("solo")
	await process_frame
	var choose_touch := InputEventScreenTouch.new()
	choose_touch.index = 2
	choose_touch.position = practice_panel._button_rects["choose"].get_center()
	choose_touch.pressed = true
	practice_panel._gui_input(choose_touch)
	assert(practice_panel._board)
	await process_frame
	var wing_touch := InputEventScreenTouch.new()
	wing_touch.index = 3
	wing_touch.position = practice_panel._button_rects["wing"].get_center()
	wing_touch.pressed = true
	practice_panel._gui_input(wing_touch)
	assert(_requested_drill == "wing")
	assert(not practice_panel.visible)
	practice_panel.free()

	var router := MobileTouchRouter.new()
	var safe := Rect2(20.0, 30.0, 980.0, 500.0)
	var left := Rect2(safe.position, Vector2(safe.size.x * 0.5, safe.size.y))
	router.configure(MobileTouchRouter.StickMode.FLOATING, Vector2(100.0, 400.0), 58.0)

	for point in [Vector2(80.0, 120.0), Vector2(260.0, 260.0), Vector2(480.0, 480.0)]:
		router.reset()
		assert(router.begin(1, point, left, 58.0) == MobileTouchRouter.Role.MOVE)
		assert(router.active_role(1) == MobileTouchRouter.Role.MOVE)

	router.reset()
	assert(router.begin(2, Vector2(760.0, 260.0), left, 58.0) == MobileTouchRouter.Role.LOOK)
	router.drag(2, Vector2(220.0, 270.0), Vector2(-12.0, 8.0))
	_assert_vector_near(router.take_look_delta(), Vector2(-12.0, 8.0))
	router.drag(2, Vector2(120.0, 270.0), Vector2(-7.0, 2.0))
	_assert_vector_near(router.take_look_delta(), Vector2(-7.0, 2.0))
	assert(router.begin(3, Vector2(800.0, 260.0), left, 58.0) == MobileTouchRouter.Role.NONE)

	router.reset()
	assert(router.begin(4, Vector2(80.0, 300.0), left, 58.0) == MobileTouchRouter.Role.MOVE)
	router.drag(4, Vector2(820.0, 300.0), Vector2.ZERO)
	assert(router.movement().x > 0.95)
	assert(router.stick_origin().x >= left.position.x + 58.0)
	assert(router.stick_origin().x <= left.end.x - 58.0)
	assert(router.stick_knob().x <= router.stick_origin().x + 58.0)
	assert(router.begin(5, Vector2(180.0, 300.0), left, 58.0) == MobileTouchRouter.Role.NONE)
	router.end(4)
	assert(router.begin(5, Vector2(180.0, 300.0), left, 58.0) == MobileTouchRouter.Role.MOVE)

	router.reset()
	assert(router.begin(6, Vector2(800.0, 250.0), left, 58.0) == MobileTouchRouter.Role.LOOK)
	assert(router.begin(7, Vector2(100.0, 250.0), left, 58.0) == MobileTouchRouter.Role.MOVE)
	router.end(7)
	router.drag(6, Vector2(700.0, 250.0), Vector2(4.0, 0.0))
	_assert_vector_near(router.take_look_delta(), Vector2(4.0, 0.0))
	router.reset()
	assert(router.movement() == Vector2.ZERO)
	_assert_vector_near(router.take_look_delta(), Vector2.ZERO)

	router.configure(MobileTouchRouter.StickMode.FIXED, Vector2(100.0, 400.0), 58.0)
	assert(router.begin(8, Vector2(260.0, 400.0), left, 58.0) == MobileTouchRouter.Role.NONE)
	assert(router.begin(9, Vector2(120.0, 410.0), left, 58.0) == MobileTouchRouter.Role.MOVE)
	router.end(9)

	# Untouched legacy defaults migrate, while a deliberately customized saved
	# layout remains distinguishable and therefore stays in place.
	var hud := DuelHud.new()
	var legacy: Dictionary = hud._legacy_default_layout()
	var revised: Dictionary = hud._default_layout()
	assert(legacy.move.center != revised.move.center)
	var config := ConfigFile.new()
	config.set_value(DuelHud.LAYOUT_SECTION, "version", 1)
	for key in DuelHud.MOVABLE_KEYS:
		var entry: Dictionary = legacy[key]
		config.set_value(DuelHud.LAYOUT_SECTION, "%s_center_x" % key, entry.center.x)
		config.set_value(DuelHud.LAYOUT_SECTION, "%s_center_y" % key, entry.center.y)
		config.set_value(DuelHud.LAYOUT_SECTION, "%s_scale" % key, entry.scale)
		config.set_value(DuelHud.LAYOUT_SECTION, "%s_opacity" % key, entry.opacity)
	assert(hud._saved_layout_matches(legacy, config))
	config.set_value(DuelHud.LAYOUT_SECTION, "move_center_x", float(legacy.move.center.x) + 0.08)
	assert(not hud._saved_layout_matches(legacy, config))
	hud.free()

	var settings_hud := DuelHud.new()
	get_root().add_child(settings_hud)
	settings_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	settings_hud.size = Vector2(1280.0, 588.0)
	await process_frame
	var settings_touch := InputEventScreenTouch.new()
	settings_touch.index = 11
	settings_touch.position = settings_hud._settings_center()
	settings_touch.pressed = true
	settings_hud._gui_input(settings_touch)
	assert(settings_hud._settings_open)
	assert(settings_hud._settings_owner_touch == 11)
	var owner_drag := InputEventScreenDrag.new()
	owner_drag.index = 11
	owner_drag.position = settings_hud._settings_center() + Vector2(20.0, 20.0)
	settings_hud._gui_input(owner_drag)
	assert(settings_hud._settings_open)
	var owner_release := InputEventScreenTouch.new()
	owner_release.index = 11
	owner_release.position = owner_drag.position
	owner_release.pressed = false
	settings_hud._gui_input(owner_release)
	assert(settings_hud._settings_open)
	var outside_touch := InputEventScreenTouch.new()
	outside_touch.index = 12
	outside_touch.position = Vector2(20.0, 20.0)
	outside_touch.pressed = true
	settings_hud._gui_input(outside_touch)
	assert(not settings_hud._settings_open)
	settings_hud.free()

	print("Riftline mobile touch exercise: PASS")
	quit()
