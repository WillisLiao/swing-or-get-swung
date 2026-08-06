extends SceneTree

func _initialize() -> void:
	var lobby := RiftlineLobby.new()
	assert(lobby.configure(1, RiftlineMap.Id.DUEL_YARD, false))
	var host := lobby.add_host()
	assert(not host.is_empty())
	assert(lobby.public_state().phase == RiftlineLobby.Phase.STAGING)
	assert(not lobby.start_live())
	assert(lobby.set_ready(-1, true) == false)
	assert(lobby.set_ready(-1, false) == false)
	assert(not lobby.public_state().launchable)

	var revision_before_peer := int(lobby.public_state().revision)
	var rival := lobby.admit_peer(7)
	assert(not rival.is_empty())
	assert(int(lobby.public_state().revision) > revision_before_peer)
	assert(not lobby.start_live())
	assert(lobby.set_ready(-1, true) == false)
	assert(lobby.set_ready(7, true))
	assert(not lobby.start_live())
	assert(lobby.set_ready(-1, true) == false)
	# The host is represented by peer zero internally, so the public authority
	# helper is exercised through the dedicated host intent below.
	assert(lobby.set_ready(0, true) == false)
	assert(lobby.set_host_ready(true))
	assert(lobby.start_live())
	var generation := lobby.current_generation()
	assert(int(lobby.public_state().phase) == RiftlineLobby.Phase.ARMING)
	assert(lobby.admit_peer(8).is_empty())
	assert(lobby.commit_live(generation))
	lobby.finish_match()
	assert(int(lobby.public_state().phase) == RiftlineLobby.Phase.REMATCH)
	assert(lobby.set_rematch_ready(7, true))
	assert(not lobby.start_rematch())
	assert(lobby.set_host_rematch_ready(true))
	assert(lobby.start_rematch())
	assert(lobby.commit_live(lobby.current_generation()))

	var squad := RiftlineLobby.new()
	assert(squad.configure(3, RiftlineMap.Id.CONCOURSE, true))
	for peer_id in range(1, 7):
		assert(not squad.admit_peer(peer_id).is_empty())
	var records: Array = squad.public_state().records
	assert(records.size() == 6)
	assert(_count_team(records, Duelist.Team.SUN) == 3)
	assert(_count_team(records, Duelist.Team.VOID) == 3)
	for record in records:
		assert(not record.has("peer_id"))
		assert(not record.has("address"))
	for peer_id in range(1, 7):
		assert(squad.set_ready(peer_id, true))
	assert(squad.start_live())
	assert(squad.commit_live(squad.current_generation()))
	var squad_revision := int(squad.public_state().revision)
	squad.remove_peer(1)
	assert(int(squad.public_state().phase) == RiftlineLobby.Phase.ABANDONED)
	assert(int(squad.public_state().revision) > squad_revision)
	assert(not _contains_bot(squad.public_state().records))
	assert(squad.reset_empty())
	assert(int(squad.public_state().phase) == RiftlineLobby.Phase.STAGING)
	assert(int(squad.public_state().team_size) == 3)
	assert(int(squad.public_state().arena_id) == RiftlineMap.Id.CONCOURSE)
	assert(not squad.admit_peer(20).is_empty())

	print("Riftline lobby exercise: PASS")
	quit()

func _count_team(records: Array, team: Duelist.Team) -> int:
	var count := 0
	for record in records:
		if int(record.get("team", -1)) == int(team):
			count += 1
	return count

func _contains_bot(records: Array) -> bool:
	for record in records:
		if not bool(record.get("human", true)):
			return true
	return false
