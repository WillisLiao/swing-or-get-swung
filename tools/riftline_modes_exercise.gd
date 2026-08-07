extends SceneTree

# Locks the rules of Nuclear Rush, the only game mode: own-base core
# delivery, launch countdown, hold-to-cancel, first-to-3 scoring, the
# 10-minute continuous clock, and unbounded sudden death on a tie.

const RED := Duelist.Team.RED
const BLUE := Duelist.Team.BLUE

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "RiftlineModesExercise"
	get_root().add_child(root)
	await physics_frame
	await _test_pickup_at_center(root)
	await _test_carrier_flag_set_and_cleared(root)
	await _test_carrier_death_drops_core(root)
	await _test_dropped_core_returns_after_timeout(root)
	await _test_install_at_own_pad_starts_countdown(root)
	await _test_install_at_enemy_pad_refused(root)
	await _test_completed_countdown_scores_and_respawns(root)
	await _test_enemy_hold_to_cancel_stops_countdown(root)
	await _test_first_to_three_finishes_match(root)
	await _test_clock_expiry_unequal_scores_finishes(root)
	await _test_clock_expiry_tie_enters_sudden_death(root)
	await _test_launch_during_sudden_death_finishes_match(root)
	await _test_manual_respawn_gate(root)
	await _test_bot_auto_respawn(root)
	await _test_death_visual_cleanup(root)
	print("Nuclear Rush rules exercise: PASS")
	quit()

func _make_duelist(root: Node3D, team: Duelist.Team, actor_id: String, point: Vector3) -> Duelist:
	var duelist := Duelist.new()
	duelist.build(team, false, false, true)
	duelist.set_actor_id(actor_id)
	duelist.position = point
	root.add_child(duelist)
	duelist.set_match_active(true)
	return duelist

func _default_pads() -> Dictionary:
	return {RED: Vector3(0, 0.1, 50), BLUE: Vector3(0, 0.1, -50)}

func _make_match(root: Node3D, pads: Dictionary) -> RiftlineMatch:
	var match_node := RiftlineMatch.new()
	match_node.configure(pads, Vector3.ZERO, false)
	root.add_child(match_node)
	match_node.add_spawn(RED, Vector3(-30, 0.1, 0))
	match_node.add_spawn(BLUE, Vector3(30, 0.1, 0))
	return match_node

func _go_live(match_node: RiftlineMatch) -> void:
	match_node.begin()
	match_node._opening_remaining = 0.0
	await physics_frame
	assert(match_node.is_live())
	assert(match_node.phase == RiftlineMatch.Phase.LIVE)

func _test_pickup_at_center(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var red := _make_duelist(root, RED, "pick_red", Vector3(0, 0.1, 0))
	var blue_d := _make_duelist(root, BLUE, "pick_blue", Vector3(60, 0.1, 60))
	match_node.register_duelist(red, "pick_red")
	match_node.register_duelist(blue_d, "pick_blue")
	await _go_live(match_node)

	# begin() respawns every duelist at their team spawn point; move the
	# carrier candidate to the core before ticking.
	red.position = Vector3(0, 0.1, 0)
	blue_d.position = Vector3(60, 0.1, 60)
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	assert(match_node.core_carrier_id == "pick_red")
	assert(match_node.core_carrier_team == RED)
	assert(red.is_carrying_core())

func _test_carrier_flag_set_and_cleared(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var red := _make_duelist(root, RED, "flag_red", Vector3(0, 0.1, 0))
	match_node.register_duelist(red, "flag_red")
	await _go_live(match_node)

	red.position = Vector3(0, 0.1, 0)
	match_node._physics_process(0.05)
	assert(red.is_carrying_core())
	red.position = Vector3(5, 0.1, 5)
	match_node._physics_process(0.05)
	assert(match_node.core_position.distance_to(Vector3(5, 0.1, 5)) < 0.01)

	match_node.unregister_duelist("flag_red")
	assert(not red.is_carrying_core())
	assert(match_node.core_state == RiftlineMatch.CoreState.DROPPED)

func _test_carrier_death_drops_core(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var red := _make_duelist(root, RED, "die_red", Vector3(0, 0.1, 0))
	var blue_d := _make_duelist(root, BLUE, "die_blue", Vector3(60, 0.1, 60))
	match_node.register_duelist(red, "die_red")
	match_node.register_duelist(blue_d, "die_blue")
	await _go_live(match_node)

	red.position = Vector3(0, 0.1, 0)
	blue_d.position = Vector3(60, 0.1, 60)
	match_node._physics_process(0.05)
	assert(match_node.core_carrier_id == "die_red")
	red.position = Vector3(12, 0.1, -8)
	match_node._physics_process(0.05)

	red.eliminated = true
	match_node._on_defeated(red, blue_d)
	assert(match_node.core_state == RiftlineMatch.CoreState.DROPPED)
	assert(match_node.core_position.distance_to(Vector3(12, 0.1, -8)) < 0.01)
	assert(not red.is_carrying_core())

	# Either team can pick the dropped core back up, including the other team.
	blue_d.position = Vector3(12, 0.1, -8)
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	assert(match_node.core_carrier_team == BLUE)

func _test_dropped_core_returns_after_timeout(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var red := _make_duelist(root, RED, "ret_red", Vector3(0, 0.1, 0))
	match_node.register_duelist(red, "ret_red")
	await _go_live(match_node)

	red.position = Vector3(0, 0.1, 0)
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	red.position = Vector3(40, 0.1, 40)
	red.eliminated = true
	match_node._on_defeated(red, red)
	assert(match_node.core_state == RiftlineMatch.CoreState.DROPPED)

	red.position = Vector3(-500, 0.1, -500)
	for i in range(16):
		match_node._physics_process(1.0)
	assert(match_node.core_state == RiftlineMatch.CoreState.AT_CENTER)
	assert(match_node.core_position.distance_to(Vector3.ZERO) < 0.01)

func _test_install_at_own_pad_starts_countdown(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var red := _make_duelist(root, RED, "inst_red", Vector3(0, 0.1, 0))
	match_node.register_duelist(red, "inst_red")
	await _go_live(match_node)

	red.position = Vector3(0, 0.1, 0)
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	red.position = pads[RED]
	match_node.set_interact("inst_red", true)
	for i in range(30):
		match_node._physics_process(0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.INSTALLED)
	assert(match_node.installed_team == RED)
	assert(match_node.launch_remaining > 0.0)
	match_node.set_interact("inst_red", false)

func _test_install_at_enemy_pad_refused(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var red := _make_duelist(root, RED, "refuse_red", Vector3(0, 0.1, 0))
	match_node.register_duelist(red, "refuse_red")
	await _go_live(match_node)

	red.position = Vector3(0, 0.1, 0)
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	red.position = pads[BLUE]
	match_node.set_interact("refuse_red", true)
	for i in range(30):
		match_node._physics_process(0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	assert(match_node.install_progress == 0.0)
	match_node.set_interact("refuse_red", false)

func _test_completed_countdown_scores_and_respawns(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var red := _make_duelist(root, RED, "score_red", Vector3(0, 0.1, 0))
	match_node.register_duelist(red, "score_red")
	await _go_live(match_node)

	red.position = Vector3(0, 0.1, 0)
	match_node._physics_process(0.05)
	red.position = pads[RED]
	match_node.set_interact("score_red", true)
	for i in range(30):
		match_node._physics_process(0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.INSTALLED)
	match_node.set_interact("score_red", false)

	for i in range(260):
		match_node._physics_process(0.1)
	assert(int(match_node.scores[RED]) == 1)
	assert(match_node.core_state == RiftlineMatch.CoreState.RESPAWNING)

	for i in range(45):
		match_node._physics_process(0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.AT_CENTER)
	assert(match_node.core_position.distance_to(Vector3.ZERO) < 0.01)

func _test_enemy_hold_to_cancel_stops_countdown(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var red := _make_duelist(root, RED, "cancel_red", Vector3(0, 0.1, 0))
	var blue_d := _make_duelist(root, BLUE, "cancel_blue", Vector3(60, 0.1, 60))
	match_node.register_duelist(red, "cancel_red")
	match_node.register_duelist(blue_d, "cancel_blue")
	await _go_live(match_node)

	red.position = Vector3(0, 0.1, 0)
	match_node._physics_process(0.05)
	red.position = pads[RED]
	match_node.set_interact("cancel_red", true)
	for i in range(30):
		match_node._physics_process(0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.INSTALLED)
	match_node.set_interact("cancel_red", false)

	blue_d.position = pads[RED]
	match_node.set_interact("cancel_blue", true)
	for i in range(35):
		match_node._physics_process(0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.RESPAWNING)
	assert(int(match_node.scores[RED]) == 0)
	assert(int(match_node.scores[BLUE]) == 0)
	match_node.set_interact("cancel_blue", false)

func _test_first_to_three_finishes_match(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var winner_box: Array = [-1]
	match_node.match_finished.connect(func(w: Duelist.Team) -> void: winner_box[0] = int(w))
	var red := _make_duelist(root, RED, "win_red", Vector3(0, 0.1, 0))
	match_node.register_duelist(red, "win_red")
	await _go_live(match_node)

	match_node.scores[RED] = RiftlineMatch.POINTS_TO_WIN - 1

	red.position = Vector3(0, 0.1, 0)
	match_node._physics_process(0.05)
	red.position = pads[RED]
	match_node.set_interact("win_red", true)
	for i in range(30):
		match_node._physics_process(0.1)
	match_node.set_interact("win_red", false)
	for i in range(260):
		match_node._physics_process(0.1)

	assert(int(match_node.scores[RED]) == RiftlineMatch.POINTS_TO_WIN)
	assert(match_node.phase == RiftlineMatch.Phase.FINISHED)
	assert(int(winner_box[0]) == int(RED))

func _test_clock_expiry_unequal_scores_finishes(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var winner_box: Array = [-1]
	match_node.match_finished.connect(func(w: Duelist.Team) -> void: winner_box[0] = int(w))
	await _go_live(match_node)

	match_node.scores[RED] = 1
	match_node.scores[BLUE] = 0
	match_node.match_remaining = 0.05
	match_node._physics_process(0.1)

	assert(match_node.phase == RiftlineMatch.Phase.FINISHED)
	assert(int(winner_box[0]) == int(RED))

func _test_clock_expiry_tie_enters_sudden_death(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	await _go_live(match_node)

	match_node.scores[RED] = 1
	match_node.scores[BLUE] = 1
	match_node.match_remaining = 0.05
	match_node._physics_process(0.1)

	assert(match_node.phase == RiftlineMatch.Phase.SUDDEN_DEATH)
	assert(match_node.sudden_death)
	assert(match_node.is_live())

func _test_launch_during_sudden_death_finishes_match(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var winner_box: Array = [-1]
	match_node.match_finished.connect(func(w: Duelist.Team) -> void: winner_box[0] = int(w))
	await _go_live(match_node)

	match_node.scores[RED] = 1
	match_node.scores[BLUE] = 1
	match_node.phase = RiftlineMatch.Phase.SUDDEN_DEATH
	match_node.sudden_death = true
	match_node.core_state = RiftlineMatch.CoreState.INSTALLED
	match_node.installed_team = BLUE
	match_node.launch_remaining = 0.05
	match_node.cancel_progress = 0.0

	match_node._physics_process(0.1)

	assert(int(match_node.scores[BLUE]) == 2)
	assert(match_node.phase == RiftlineMatch.Phase.FINISHED)
	assert(int(winner_box[0]) == int(BLUE))

func _test_manual_respawn_gate(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var red := _make_duelist(root, RED, "respawn_red", Vector3(-30, 0.1, 0))
	var blue_d := _make_duelist(root, BLUE, "respawn_blue", Vector3(30, 0.1, 0))
	match_node.register_duelist(red, "respawn_red")
	match_node.register_duelist(blue_d, "respawn_blue")
	await _go_live(match_node)

	# Elimination no longer auto-respawns - it starts a minimum-death timer
	# and the actor stays down until an explicit request clears it.
	red.take_damage(Duelist.HEALTH, blue_d)
	assert(red.eliminated)
	assert(not match_node.can_respawn("respawn_red"))
	# A request before the minimum elapses is a no-op, not a queued action.
	assert(not match_node.request_respawn("respawn_red"))
	assert(red.eliminated)

	# Ticking short of the minimum still refuses.
	match_node._physics_process(RiftlineMatch.RESPAWN_MIN_SECONDS - 0.5)
	assert(not match_node.can_respawn("respawn_red"))
	assert(red.eliminated)

	# Crossing the minimum makes it eligible, but still does not respawn by
	# itself - only an explicit request does.
	match_node._physics_process(1.0)
	assert(match_node.can_respawn("respawn_red"))
	assert(red.eliminated)
	assert(is_zero_approx(match_node.respawn_seconds_remaining("respawn_red")))

	var respawned := [false]
	match_node.respawn_started.connect(func(victim: Duelist) -> void:
		if victim == red:
			respawned[0] = true)
	assert(match_node.request_respawn("respawn_red"))
	assert(not red.eliminated)
	assert(respawned[0])
	assert(not match_node.can_respawn("respawn_red"))

	# A second request right after respawning is a no-op (nothing to gate).
	assert(not match_node.request_respawn("respawn_red"))

func _test_bot_auto_respawn(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var bot := BotDuelist.new()
	bot.build(RED, false, false, true)
	bot.set_actor_id("respawn_bot")
	bot.position = Vector3(-30, 0.1, 0)
	root.add_child(bot)
	bot.set_match_active(true)
	var blue_d := _make_duelist(root, BLUE, "respawn_bot_enemy", Vector3(30, 0.1, 0))
	match_node.register_duelist(bot, "respawn_bot")
	match_node.register_duelist(blue_d, "respawn_bot_enemy")
	await _go_live(match_node)

	bot.take_damage(Duelist.HEALTH, blue_d)
	assert(bot.eliminated)
	match_node._physics_process(RiftlineMatch.RESPAWN_MIN_SECONDS - 0.1)
	assert(bot.eliminated)
	match_node._physics_process(0.2)
	assert(not bot.eliminated)
	assert(not match_node.can_respawn("respawn_bot"))

func _test_death_visual_cleanup(root: Node3D) -> void:
	var duelist := Duelist.new()
	duelist.build(RED, false, true, true)
	duelist.set_actor_id("death_visual")
	root.add_child(duelist)
	duelist.set_match_active(true)

	duelist.take_damage(Duelist.HEALTH, null)
	assert(duelist.eliminated)
	assert(duelist.visible)
	duelist._process(Duelist.DEATH_VISUAL_HOLD_SECONDS + Duelist.DEATH_VISUAL_FADE_SECONDS + 0.1)
	assert(not duelist.visible)

	duelist.respawn_at(Vector3.ZERO)
	assert(not duelist.eliminated)
	assert(duelist.visible)
	var geometry_nodes: Array[Node] = duelist.find_children("*", "GeometryInstance3D", true, false)
	for node: Node in geometry_nodes:
		assert(is_zero_approx((node as GeometryInstance3D).transparency))
