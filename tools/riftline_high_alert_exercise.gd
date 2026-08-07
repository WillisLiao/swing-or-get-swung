extends SceneTree

func _initialize() -> void:
	assert(RiftlineHighAlert.aims_at_target(Vector3(0.0, 1.5, 10.0), Vector3.FORWARD, Vector3(0.0, 1.5, 0.0)))
	assert(not RiftlineHighAlert.aims_at_target(Vector3(0.0, 1.5, 10.0), Vector3.RIGHT, Vector3(0.0, 1.5, 0.0)))
	assert(not RiftlineHighAlert.aims_at_target(Vector3(0.0, 1.5, 100.0), Vector3.FORWARD, Vector3(0.0, 1.5, 0.0)))

	var arena := Node3D.new()
	get_root().add_child(arena)
	var local := _make_duelist("local", Duelist.Team.RED, Vector3.ZERO, true)
	var attacker := _make_duelist("attacker", Duelist.Team.BLUE, Vector3(0.0, 0.0, 10.0), false)
	arena.add_child(local)
	arena.add_child(attacker)
	await process_frame

	assert(not RiftlineHighAlert.is_outside_view(local.camera, Vector3(0.0, 1.5, -10.0)))
	assert(RiftlineHighAlert.is_outside_view(local.camera, attacker.head.global_position))
	var edge_direction := RiftlineHighAlert.screen_edge_direction(local.camera, attacker.global_position)
	assert(edge_direction.y > 0.9)

	var chip := RiftlineHighAlert.new()
	var opponents: Array[Duelist] = [attacker]
	var warming: Dictionary = chip.evaluate(RiftlineHighAlert.TRIGGER_SECONDS - 0.01, local, opponents)
	assert(not bool(warming.active))
	var triggered: Dictionary = chip.evaluate(0.02, local, opponents)
	assert(bool(triggered.active))
	assert(bool(triggered.just_triggered))
	var held: Dictionary = chip.evaluate(0.02, local, opponents)
	assert(bool(held.active))
	assert(not bool(held.just_triggered))

	# A layer-1 cover block between attacker and target suppresses the chip even
	# though aim direction, ADS state, distance, and off-screen position match.
	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	cover.position = Vector3(0.0, 1.5, 5.0)
	var cover_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.5)
	cover_shape.shape = box
	cover.add_child(cover_shape)
	arena.add_child(cover)
	await physics_frame
	var blocked: Dictionary = chip.evaluate(RiftlineHighAlert.TRIGGER_SECONDS + 0.1, local, opponents)
	assert(not bool(blocked.active))

	var hud := DuelHud.new()
	get_root().add_child(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1280.0, 588.0)
	hud.show_high_alert(Vector2.RIGHT, 0.9)
	assert(hud.high_alert_direction.x > 0.99)
	assert(is_equal_approx(hud.high_alert_intensity, 0.9))
	hud.clear_high_alert()
	assert(is_zero_approx(hud.high_alert_intensity))

	print("Riftline high alert chip exercise: PASS")
	quit()

func _make_duelist(actor_id: String, team: Duelist.Team, position: Vector3, with_camera: bool) -> Duelist:
	var actor := Duelist.new()
	actor.actor_id = actor_id
	actor.team = team
	actor.position = position
	actor.ads_progress = 1.0
	actor.head = Node3D.new()
	actor.head.position = Vector3(0.0, 1.5, 0.0)
	actor.add_child(actor.head)
	if with_camera:
		actor.camera = Camera3D.new()
		actor.camera.fov = 60.0
		actor.head.add_child(actor.camera)
	return actor
