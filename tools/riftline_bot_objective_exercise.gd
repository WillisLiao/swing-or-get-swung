extends SceneTree

func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var runner := _new_bot(root, "red_runner", Duelist.Team.RED, 0)
	var escort := _new_bot(root, "red_escort", Duelist.Team.RED, 1)
	var defender := _new_bot(root, "red_defender", Duelist.Team.RED, 2)
	await process_frame
	var own_pad := Vector3(0.0, 0.1, 50.0)
	var enemy_pad := Vector3(0.0, 0.1, -50.0)
	var center := Vector3.ZERO

	runner.set_objective_context(_context(0, center, "", Duelist.Team.RED, Duelist.Team.RED, own_pad, enemy_pad))
	var neutral_plan: Dictionary = runner.objective_plan()
	assert(str(neutral_plan.intent) == "claim_core")
	assert((neutral_plan.goal as Vector3).is_equal_approx(center))

	runner.set_objective_context(_context(1, Vector3(0.0, 0.1, 18.0), runner.actor_id, Duelist.Team.RED, Duelist.Team.RED, own_pad, enemy_pad))
	var delivery_plan: Dictionary = runner.objective_plan()
	assert(str(delivery_plan.intent) == "deliver_core")
	assert(not bool(delivery_plan.interact))
	runner.position = own_pad
	delivery_plan = runner.objective_plan()
	assert(bool(delivery_plan.interact))

	escort.set_objective_context(_context(1, Vector3(2.0, 0.1, 14.0), runner.actor_id, Duelist.Team.RED, Duelist.Team.RED, own_pad, enemy_pad))
	assert(str(escort.objective_plan().intent) == "escort_carrier")
	defender.set_objective_context(_context(1, Vector3(2.0, 0.1, 14.0), runner.actor_id, Duelist.Team.RED, Duelist.Team.RED, own_pad, enemy_pad))
	assert(str(defender.objective_plan().intent) == "prepare_defense")

	escort.set_objective_context(_context(1, Vector3(0.0, 0.1, 12.0), "blue_carrier", Duelist.Team.BLUE, Duelist.Team.RED, own_pad, enemy_pad))
	assert(str(escort.objective_plan().intent) == "intercept_carrier")
	escort.set_objective_context(_context(3, enemy_pad, "", Duelist.Team.BLUE, Duelist.Team.BLUE, own_pad, enemy_pad))
	escort.position = enemy_pad
	var cancel_plan: Dictionary = escort.objective_plan()
	assert(str(cancel_plan.intent) == "cancel_launch")
	assert(bool(cancel_plan.interact))
	defender.set_objective_context(_context(3, own_pad, "", Duelist.Team.RED, Duelist.Team.RED, own_pad, enemy_pad))
	assert(str(defender.objective_plan().intent) == "defend_launch")

	# Integrate the two critical autonomous interactions with the real rules:
	# runner installs at its own pad, then the enemy bot cancels that launch.
	var match_node := RiftlineMatch.new()
	root.add_child(match_node)
	match_node.configure({Duelist.Team.RED: own_pad, Duelist.Team.BLUE: enemy_pad}, center, false)
	match_node.add_spawn(Duelist.Team.RED, own_pad)
	match_node.add_spawn(Duelist.Team.BLUE, enemy_pad)
	var red_bot := _built_bot(root, "red_auto", Duelist.Team.RED, 0)
	var blue_bot := _built_bot(root, "blue_auto", Duelist.Team.BLUE, 0)
	match_node.register_duelist(red_bot, red_bot.actor_id)
	match_node.register_duelist(blue_bot, blue_bot.actor_id)
	match_node.begin()
	match_node._physics_process(RiftlineMatch.OPENING_HOLD_SECONDS + 0.1)
	red_bot.global_position = center
	blue_bot.global_position = enemy_pad
	match_node._physics_process(0.05)
	assert(match_node.core_state == RiftlineMatch.CoreState.CARRIED)
	assert(match_node.core_carrier_id == red_bot.actor_id)
	red_bot.set_objective_context(_context(1, center, red_bot.actor_id, Duelist.Team.RED, Duelist.Team.RED, own_pad, enemy_pad))
	red_bot.global_position = own_pad
	match_node.set_interact(red_bot.actor_id, bool(red_bot.objective_plan().interact))
	match_node._physics_process(RiftlineMatch.CORE_INSTALL_SECONDS + 0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.INSTALLED)
	assert(match_node.installed_team == Duelist.Team.RED)
	blue_bot.set_objective_context(_context(3, own_pad, "", Duelist.Team.RED, Duelist.Team.RED, enemy_pad, own_pad))
	blue_bot.global_position = own_pad
	match_node.set_interact(blue_bot.actor_id, bool(blue_bot.objective_plan().interact))
	match_node._physics_process(RiftlineMatch.LAUNCH_CANCEL_SECONDS + 0.1)
	assert(match_node.core_state == RiftlineMatch.CoreState.RESPAWNING)

	print("Riftline objective-aware bot exercise: PASS")
	quit()

func _new_bot(root: Node3D, actor_id: String, team: Duelist.Team, squad_index: int) -> BotDuelist:
	var bot := BotDuelist.new()
	bot.build(team, false, false, false)
	bot.set_actor_id(actor_id)
	bot.set_match_active(true)
	bot.configure_objective_ai(null, squad_index)
	root.add_child(bot)
	bot.set_physics_process(false)
	return bot

func _built_bot(root: Node3D, actor_id: String, team: Duelist.Team, squad_index: int) -> BotDuelist:
	var bot := BotDuelist.new()
	bot.build(team, false, false, true)
	bot.set_actor_id(actor_id)
	bot.configure_objective_ai(null, squad_index)
	root.add_child(bot)
	return bot

func _context(core_state: int, core_position: Vector3, carrier_id: String, carrier_team: Duelist.Team, installed_team: Duelist.Team, own_pad: Vector3, enemy_pad: Vector3) -> Dictionary:
	return {
		"core_state": core_state,
		"core_position": core_position,
		"core_carrier_id": carrier_id,
		"core_carrier_team": int(carrier_team),
		"installed_team": int(installed_team),
		"own_pad": own_pad,
		"enemy_pad": enemy_pad,
	}
