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
	await _test_respawn_rule_matrix(root)
	await _test_carrier_respawn_and_drop_timers(root)
	await _test_bot_auto_respawn(root)
	await _test_authoritative_carrier_damage(root)
	await _test_vest_immunity(root)
	await _test_low_health_carry_damage_drops_core(root)
	await _test_death_visual_cleanup(root)
	await _test_combat_stats(root)
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
	var health_before_carry: float = red.health
	red._simulate_motion(Vector2.ZERO, false, 1.0)
	assert(is_equal_approx(red.health, health_before_carry))
	assert(is_equal_approx(red.movement_speed_multiplier(), Duelist.CORE_CARRY_SPEED_MULTIPLIER))

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

func _test_combat_stats(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var red := _make_duelist(root, RED, "stats_red", Vector3(-30, 0.1, 0))
	var blue_d := _make_duelist(root, BLUE, "stats_blue", Vector3(30, 0.1, 0))
	match_node.register_duelist(red, "stats_red")
	match_node.register_duelist(blue_d, "stats_blue")
	await _go_live(match_node)

	blue_d.eliminated = true
	match_node._on_defeated(blue_d, red)
	var red_stats: Dictionary = match_node.combat_stats_for("stats_red")
	var blue_stats: Dictionary = match_node.combat_stats_for("stats_blue")
	assert(int(red_stats.get("kills", -1)) == 1)
	assert(int(red_stats.get("deaths", -1)) == 0)
	assert(int(blue_stats.get("kills", -1)) == 0)
	assert(int(blue_stats.get("deaths", -1)) == 1)

	# Respawning preserves the current match totals.
	match_node._respawn_elapsed["stats_blue"] = RiftlineMatch.RESPAWN_MIN_SECONDS
	assert(match_node.request_respawn("stats_blue"))
	blue_stats = match_node.combat_stats_for("stats_blue")
	assert(int(blue_stats.get("deaths", -1)) == 1)

	# A death without a valid opposing killer still counts as a death, but
	# must not fabricate a kill for anyone.
	red.eliminated = true
	match_node._on_defeated(red, null)
	red_stats = match_node.combat_stats_for("stats_red")
	assert(int(red_stats.get("kills", -1)) == 1)
	assert(int(red_stats.get("deaths", -1)) == 1)

	# LAN replicas receive the same authoritative totals in the match snapshot.
	var replica := _make_match(root, _default_pads())
	var snapshot: Dictionary = match_node.authoritative_state()
	snapshot["tick"] = 7
	replica.apply_replica_state(snapshot)
	assert(replica.combat_stats_for("stats_red") == {"kills": 1, "deaths": 1})
	assert(replica.combat_stats_for("stats_blue") == {"kills": 0, "deaths": 1})

	# A rematch is a new scoreboard.
	match_node._start_match()
	assert(match_node.combat_stats_for("stats_red") == {"kills": 0, "deaths": 0})
	assert(match_node.combat_stats_for("stats_blue") == {"kills": 0, "deaths": 0})

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
	assert(is_equal_approx(RiftlineMatch.RESPAWN_MIN_SECONDS, 6.0))

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

func _assert_respawn_boundary(root: Node3D, actor_id: String, sudden: bool, red_score: int, blue_score: int, installed: Duelist.Team) -> void:
	var match_node := _make_match(root, _default_pads())
	var red := _make_duelist(root, RED, actor_id, Vector3(-30, 0.1, 0))
	var blue_d := _make_duelist(root, BLUE, actor_id + "_enemy", Vector3(30, 0.1, 0))
	match_node.register_duelist(red, actor_id)
	match_node.register_duelist(blue_d, actor_id + "_enemy")
	await _go_live(match_node)
	match_node.scores[RED] = red_score
	match_node.scores[BLUE] = blue_score
	match_node.installed_team = installed
	if sudden:
		match_node.phase = RiftlineMatch.Phase.SUDDEN_DEATH
		match_node.sudden_death = true

	red.take_damage(Duelist.HEALTH, blue_d)
	assert(not match_node.can_respawn(actor_id))
	match_node._physics_process(5.99)
	assert(not match_node.can_respawn(actor_id))
	assert(red.eliminated)
	match_node._physics_process(0.01)
	assert(match_node.can_respawn(actor_id))
	assert(red.eliminated)
	assert(match_node.request_respawn(actor_id))
	assert(not red.eliminated)

func _test_respawn_rule_matrix(root: Node3D) -> void:
	# The same flat gate applies in normal play and sudden death, regardless of
	# score deficit or which team owns the installed objective.
	await _assert_respawn_boundary(root, "respawn_flat_live", false, 0, 0, RED)
	await _assert_respawn_boundary(root, "respawn_deficit_live", false, 0, 3, BLUE)
	await _assert_respawn_boundary(root, "respawn_sudden", true, 1, 1, BLUE)

func _test_carrier_respawn_and_drop_timers(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var red := _make_duelist(root, RED, "respawn_drop_red", Vector3.ZERO)
	var blue_d := _make_duelist(root, BLUE, "respawn_drop_blue", Vector3(60, 0.1, 60))
	match_node.register_duelist(red, "respawn_drop_red")
	match_node.register_duelist(blue_d, "respawn_drop_blue")
	await _go_live(match_node)

	red.position = Vector3.ZERO
	blue_d.position = Vector3(60, 0.1, 60)
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	red.position = Vector3(12, 0.1, -8)
	match_node._physics_process(0.05)
	red.eliminated = true
	match_node._on_defeated(red, blue_d)
	assert(match_node.core_state == RiftlineMatch.CoreState.DROPPED)
	assert(is_equal_approx(match_node.drop_return_remaining, RiftlineMatch.CORE_DROP_RETURN_SECONDS))

	match_node._physics_process(6.0)
	assert(match_node.can_respawn("respawn_drop_red"))
	assert(red.eliminated)
	assert(is_equal_approx(match_node.drop_return_remaining, 9.0))
	assert(match_node.request_respawn("respawn_drop_red"))
	assert(not red.eliminated)
	assert(match_node.core_state == RiftlineMatch.CoreState.DROPPED)

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
	match_node._physics_process(RiftlineMatch.RESPAWN_MIN_SECONDS - 0.01)
	assert(bot.eliminated)
	match_node._physics_process(0.01)
	assert(not bot.eliminated)
	assert(not match_node.can_respawn("respawn_bot"))

func _test_authoritative_carrier_damage(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var carrier := _make_duelist(root, RED, "damage_carrier", Vector3.ZERO)
	match_node.register_duelist(carrier, "damage_carrier")
	await _go_live(match_node)

	carrier.position = Vector3.ZERO
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	assert(is_equal_approx(RiftlineMatch.CORE_CARRY_DAMAGE_PER_SECOND, 2.5))
	var health_before: float = carrier.health
	# This invokes the authoritative match tick, not Duelist prediction.
	match_node._physics_process(1.0)
	assert(is_equal_approx(carrier.health, health_before - 2.5))
	assert(not carrier.eliminated)
	assert(is_equal_approx(carrier.movement_speed_multiplier(), Duelist.CORE_CARRY_SPEED_MULTIPLIER))

func _test_vest_immunity(root: Node3D) -> void:
	var match_node := _make_match(root, _default_pads())
	var runner := _make_duelist(root, RED, "vest_carrier", Vector3.ZERO)
	runner.configure_loadout(Duelist.PlayerClass.RUNNER)
	match_node.register_duelist(runner, "vest_carrier")
	await _go_live(match_node)

	runner.position = Vector3.ZERO
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	assert(runner.has_nuclear_vest)
	var health_before: float = runner.health
	match_node._physics_process(1.0)
	assert(is_equal_approx(runner.health, health_before))
	assert(not runner.eliminated)

func _test_low_health_carry_damage_drops_core(root: Node3D) -> void:
	var pads := _default_pads()
	var match_node := _make_match(root, pads)
	var carrier := _make_duelist(root, RED, "damage_death_carrier", Vector3.ZERO)
	match_node.register_duelist(carrier, "damage_death_carrier")
	await _go_live(match_node)

	carrier.position = Vector3.ZERO
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	carrier.position = pads[RED]
	match_node.set_interact("damage_death_carrier", true)
	carrier.health = 1.0
	match_node._physics_process(1.0)

	assert(carrier.eliminated)
	assert(not carrier.is_carrying_core())
	assert(match_node.core_state == RiftlineMatch.CoreState.DROPPED)
	assert(is_zero_approx(match_node.install_progress))
	assert(is_equal_approx(match_node.drop_return_remaining, RiftlineMatch.CORE_DROP_RETURN_SECONDS))
	assert(not match_node.can_respawn("damage_death_carrier"))
	match_node._physics_process(5.99)
	assert(not match_node.can_respawn("damage_death_carrier"))
	match_node._physics_process(0.01)
	assert(match_node.can_respawn("damage_death_carrier"))
	assert(is_equal_approx(match_node.drop_return_remaining, 9.0))
	assert(match_node.request_respawn("damage_death_carrier"))
	assert(not carrier.eliminated)
	assert(match_node.core_state == RiftlineMatch.CoreState.DROPPED)

func _test_death_visual_cleanup(root: Node3D) -> void:
	var duelist := Duelist.new()
	duelist.build(RED, false, true, true)
	duelist.set_actor_id("death_visual")
	root.add_child(duelist)
	duelist.set_match_active(true)
	assert(duelist._body_visual_root != null)
	assert(duelist._body_visual_root.name == "BlenderCharacter")
	assert(duelist._left_arm != null and duelist._right_arm != null)
	assert(duelist._left_leg != null and duelist._right_leg != null)
	var imported_geometry: Array[Node] = duelist._body_visual_root.find_children("*", "MeshInstance3D", true, false)
	assert(imported_geometry.size() >= 31)
	var red_plate := duelist._body_visual_root.find_child("TEAM_ChestPlate", true, false) as MeshInstance3D
	assert(red_plate != null and red_plate.material_override is ShaderMaterial)
	var red_albedo: Color = (red_plate.material_override as ShaderMaterial).get_shader_parameter("albedo")
	assert(red_albedo.is_equal_approx(duelist._team_color()))
	assert(duelist._band != null and duelist._band.material_override != red_plate.material_override)

	var blue_duelist := Duelist.new()
	blue_duelist.build(BLUE, false, true, true)
	root.add_child(blue_duelist)
	var blue_plate := blue_duelist._body_visual_root.find_child("TEAM_ChestPlate", true, false) as MeshInstance3D
	assert(blue_plate != null and blue_plate.material_override is ShaderMaterial)
	var blue_albedo: Color = (blue_plate.material_override as ShaderMaterial).get_shader_parameter("albedo")
	assert(blue_albedo.is_equal_approx(blue_duelist._team_color()))
	blue_duelist.queue_free()

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
