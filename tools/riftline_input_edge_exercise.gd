extends SceneTree

# This command-line exercise mirrors the server's two-lane command handling:
# continuous intent is retained between ticks, while accepted edge commands
# enter a queue and are consumed once.
class EdgeProbe:
	var last_sequence := -1
	var pending_edges: Array[Dictionary] = []
	var movement_ticks := 0
	var fire_ticks := 0
	var crouch_actions := 0
	var prone_actions := 0
	var jump_actions := 0
	var weapon_swap_actions := 0
	var reload_actions := 0

	func accept(frame: Dictionary) -> void:
		var sequence := int(frame.get("sequence", -1))
		if sequence <= last_sequence:
			return
		last_sequence = sequence
		pending_edges.append(frame.duplicate(true))

	func tick(continuous: Dictionary) -> void:
		movement_ticks += 1 if absf(float(continuous.get("move_x", 0.0))) > 0.01 or absf(float(continuous.get("move_y", 0.0))) > 0.01 else 0
		fire_ticks += 1 if bool(continuous.get("fire", false)) else 0
		for frame in pending_edges:
			crouch_actions += 1 if bool(frame.get("crouch", false)) else 0
			prone_actions += 1 if bool(frame.get("prone", false)) else 0
			jump_actions += 1 if bool(frame.get("jump", false)) else 0
			weapon_swap_actions += 1 if bool(frame.get("weapon_switch", false)) else 0
			reload_actions += 1 if bool(frame.get("reload", false)) else 0
		pending_edges.clear()

func _initialize() -> void:
	var probe := EdgeProbe.new()
	var continuous := {"move_x": 0.65, "move_y": -0.2, "fire": true}
	probe.accept({"sequence": 10, "crouch": true})
	probe.accept({"sequence": 10, "crouch": true})
	probe.tick(continuous)
	probe.tick(continuous)
	probe.accept({"sequence": 11, "prone": true})
	probe.tick(continuous)
	probe.accept({"sequence": 12, "jump": true})
	probe.tick(continuous)
	probe.accept({"sequence": 13, "weapon_switch": true})
	probe.tick(continuous)
	probe.accept({"sequence": 14, "reload": true})
	probe.tick(continuous)
	probe.tick(continuous)
	assert(probe.crouch_actions == 1)
	assert(probe.prone_actions == 1)
	assert(probe.jump_actions == 1)
	assert(probe.weapon_swap_actions == 1)
	assert(probe.reload_actions == 1)
	assert(probe.movement_ticks == 7)
	assert(probe.fire_ticks == 7)
	print("Riftline input edge exercise: PASS")
	quit()
