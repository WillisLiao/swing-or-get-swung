extends SceneTree

func _initialize() -> void:
	var app_roster := RiftlineRoster.new()
	assert(app_roster.configure(1, false, false))
	var host := app_roster.add_host()
	assert(str(host.actor_id) == "host")
	assert(int(host.team) == int(Duelist.Team.RED))
	var first_remote := app_roster.assign_peer(7)
	assert(str(first_remote.actor_id) == "peer_7")
	assert(int(first_remote.team) == int(Duelist.Team.BLUE))
	assert(app_roster.is_ready())

	var copy := app_roster.record("host")
	copy.team = int(Duelist.Team.BLUE)
	assert(int(app_roster.record("host").team) == int(Duelist.Team.RED))
	var public_record := app_roster.public_records()[0]
	assert(not public_record.has("peer_id"))
	assert(not public_record.has("address"))

	var full := RiftlineRoster.new()
	assert(full.configure(5, true, false))
	for peer_id in range(1, 11):
		assert(not full.assign_peer(peer_id).is_empty())
	var records := full.records()
	assert(records.size() == 10)
	assert(_count_team(records, Duelist.Team.RED) == 5)
	assert(_count_team(records, Duelist.Team.BLUE) == 5)
	assert(full.assign_peer(11).is_empty())
	assert(full.records().size() == 10)
	assert(_unique_actor_ids(records))
	assert(full.is_ready())

	var dedicated_tie := RiftlineRoster.new()
	assert(dedicated_tie.configure(1, true, false))
	dedicated_tie.add_host()
	var tie_remote := dedicated_tie.assign_peer(30)
	assert(int(tie_remote.team) == int(Duelist.Team.RED))

	var removed := full.remove_peer(1)
	assert(str(removed.actor_id) == "peer_1")
	assert(full.actor_for_peer(1).is_empty())
	var rejoinder := full.assign_peer(1)
	assert(str(rejoinder.actor_id) != "peer_1")
	assert(not rejoinder.is_empty())
	assert(_unique_actor_ids(full.records()))

	var readiness := RiftlineRoster.new()
	assert(readiness.configure(2, true, false))
	assert(not readiness.is_ready())
	readiness.assign_peer(20)
	readiness.assign_peer(21)
	assert(not readiness.is_ready())
	readiness.assign_peer(22)
	readiness.assign_peer(23)
	assert(readiness.is_ready())

	print("Riftline roster exercise: PASS")
	quit()

func _count_team(records: Array[Dictionary], team: Duelist.Team) -> int:
	var count := 0
	for entry in records:
		if int(entry.get("team", -1)) == int(team):
			count += 1
	return count

func _unique_actor_ids(records: Array[Dictionary]) -> bool:
	var seen := {}
	for entry in records:
		var actor_id := str(entry.get("actor_id", ""))
		if actor_id.is_empty() or seen.has(actor_id):
			return false
		seen[actor_id] = true
	return true
