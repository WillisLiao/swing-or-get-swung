extends SceneTree

# Locks the lean contract end to end: the input frame carries the state, the
# authoritative eye moves sideways so the peek clears cover, presentation and
# snapshots round-trip it, the HUD offers hold and tap modes, the ADS option
# gates aiming without dropping the lean, and the network rejects frames that
# omit the field.

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "RiftlineLeanExercise"
	get_root().add_child(root)
	await physics_frame

	var duelist := _make_duelist(root, Duelist.Team.SUN, "sun_lean", Vector3.ZERO)

	# The frame carries lean as a clamped integer alongside the other intent.
	var frame := duelist.make_input_frame(1, Vector2.ZERO, false, false, false, false, false, false, false, false, 1)
	assert(int(frame.lean) == 1)
	var over_frame := duelist.make_input_frame(2, Vector2.ZERO, false, false, false, false, false, false, false, false, 9)
	assert(int(over_frame.lean) == 1)

	# Applying the frame moves the authoritative head, and therefore the eye
	# and the shot origin, sideways in the lean direction.
	duelist.apply_input_frame(frame, 0.016, false)
	assert(duelist.lean == 1)
	assert(is_equal_approx(duelist.head.position.x, Duelist.LEAN_HEAD_OFFSET))
	var eye := duelist.authoritative_eye_origin()
	assert(is_equal_approx(eye.x - duelist.global_position.x, Duelist.LEAN_HEAD_OFFSET))

	var left_frame := duelist.make_input_frame(3, Vector2.ZERO, false, false, false, false, false, false, false, false, -1)
	duelist.apply_input_frame(left_frame, 0.016, false)
	assert(duelist.lean == -1)
	assert(is_equal_approx(duelist.head.position.x, -Duelist.LEAN_HEAD_OFFSET))

	# While live, an empty frame keeps the continuous lean state, exactly like
	# aim; leaving the match is what re-centers it.
	duelist.apply_input_frame({}, 0.016, false)
	assert(duelist.lean == -1)
	duelist.set_match_active(false)
	assert(duelist.lean == 0)
	assert(is_equal_approx(duelist.head.position.x, 0.0))
	duelist.set_match_active(true)

	# Lean works from every stance, including prone.
	duelist.apply_input_frame(frame, 0.016, false)
	assert(duelist.lean == 1)
	duelist.set_stance(Duelist.Stance.PRONE)
	assert(duelist.lean == 1)
	duelist.set_lean(-1)
	assert(duelist.lean == -1)
	assert(is_equal_approx(duelist.head.position.x, -Duelist.LEAN_HEAD_OFFSET))
	duelist.set_stance(Duelist.Stance.STAND)
	duelist.set_lean(0)
	assert(duelist.lean == 0)

	# Snapshots carry lean and remote presentation applies it.
	duelist.set_lean(1)
	var snapshot := duelist.authoritative_state(7, 3)
	assert(int(snapshot.lean) == 1)
	var replica := _make_duelist(root, Duelist.Team.VOID, "void_lean", Vector3(8.0, 0.1, 0.0))
	replica.apply_presentation_state(snapshot)
	assert(replica.lean == 1)
	assert(is_equal_approx(replica.head.position.x, Duelist.LEAN_HEAD_OFFSET))

	# The HUD hold mode follows the finger; tap mode latches until tapped again.
	var hud := DuelHud.new()
	get_root().add_child(hud)
	hud.size = Vector2(1280.0, 588.0)
	await process_frame

	# Explicit modes keep the exercise independent of any saved preferences.
	hud.lean_hold_mode = true
	hud.lean_auto_ads = false
	assert(hud.lean_hold_mode)
	hud._apply_lean_press(-1, 21)
	assert(hud.lean_value() == -1)
	hud._apply_lean_release(-1, 21)
	assert(hud.lean_value() == 0)
	hud._apply_lean_press(1, 22)
	assert(hud.lean_value() == 1)
	hud._apply_lean_press(-1, 23)
	assert(hud.lean_value() == -1)
	hud._apply_lean_release(-1, 23)
	assert(hud.lean_value() == 1)
	hud._apply_lean_release(1, 22)
	assert(hud.lean_value() == 0)

	hud.lean_hold_mode = false
	hud._apply_lean_press(-1, 24)
	hud._apply_lean_release(-1, 24)
	assert(hud.lean_value() == -1)
	hud._apply_lean_press(-1, 25)
	hud._apply_lean_release(-1, 25)
	assert(hud.lean_value() == 0)
	hud._apply_lean_press(1, 26)
	hud._apply_lean_release(1, 26)
	assert(hud.lean_value() == 1)
	hud.lean_hold_mode = true
	assert(hud.lean_value() == 0)

	# The ADS button always aims; lean aims on its own only when LEAN ADS is on.
	hud.aim_held = true
	assert(hud.effective_aim(0))
	assert(hud.effective_aim(1))
	hud.aim_held = false
	assert(not hud.effective_aim(0))
	assert(not hud.effective_aim(1))
	hud.lean_auto_ads = true
	assert(hud.effective_aim(1))
	assert(hud.effective_aim(-1))
	assert(not hud.effective_aim(0))
	hud.lean_auto_ads = false

	# The network requires the lean field and clamps it into range.
	var network := RiftlineNetwork.new()
	root.add_child(network)
	var wire_frame := duelist.make_input_frame(4, Vector2.ZERO, false, false, false, false, false, false, false, false, 1)
	wire_frame["protocol"] = RiftlineNetwork.PROTOCOL_VERSION
	var validated := network._validate_input(1, wire_frame)
	assert(not validated.is_empty())
	assert(int(validated.lean) == 1)
	var missing := wire_frame.duplicate(true)
	missing.erase("lean")
	assert(network._validate_input(1, missing).is_empty())
	var stale := wire_frame.duplicate(true)
	stale["protocol"] = 6
	assert(network._validate_input(1, stale).is_empty())

	print("Riftline lean exercise: PASS")
	quit()

func _make_duelist(root: Node3D, team: Duelist.Team, actor_id: String, point: Vector3) -> Duelist:
	var duelist := Duelist.new()
	duelist.build(team, false, false, true)
	duelist.set_actor_id(actor_id)
	duelist.position = point
	root.add_child(duelist)
	duelist.set_match_active(true)
	return duelist
