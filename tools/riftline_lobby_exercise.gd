extends SceneTree

func _initialize() -> void:
	var lobby := RiftlineLobby.new()
	lobby.configure(1, false)
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

	# Nuclear Rush is 4v4: a squad lobby fills 4-a-side with no map or mode to
	# negotiate.
	var squad := RiftlineLobby.new()
	squad.configure(4, true)
	for peer_id in range(1, 9):
		assert(not squad.admit_peer(peer_id).is_empty())
	var records: Array = squad.public_state().records
	assert(records.size() == 8)
	assert(_count_team(records, Duelist.Team.RED) == 4)
	assert(_count_team(records, Duelist.Team.BLUE) == 4)
	for record in records:
		assert(not record.has("peer_id"))
		assert(not record.has("address"))
	for peer_id in range(1, 9):
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
	assert(int(squad.public_state().team_size) == 4)
	assert(not squad.admit_peer(20).is_empty())

	# A dropped connection mid-match is a reserved grace window, not an
	# instant loss for the other seven players - this is the mobile-network
	# hardening the reconnect flow exists for.
	var grace := RiftlineLobby.new()
	grace.configure(4, true)
	var grace_records: Array[Dictionary] = []
	for peer_id in range(1, 9):
		grace_records.append(grace.admit_peer(peer_id))
	for peer_id in range(1, 9):
		assert(grace.set_ready(peer_id, true))
	assert(grace.start_live())
	assert(grace.commit_live(grace.current_generation()))
	var dropped_token := str(grace_records[2].get("rejoin_token", ""))
	assert(not dropped_token.is_empty())
	var dropped_team := int(grace_records[2].get("team", -1))
	var grace_revision := int(grace.public_state().revision)
	var disconnected := grace.disconnect_peer(3)
	assert(not disconnected.is_empty())
	assert(not bool(disconnected.get("connected", true)))
	assert(int(grace.public_state().phase) == RiftlineLobby.Phase.LIVE)
	assert(int(grace.public_state().revision) > grace_revision)
	var disconnected_record: Dictionary = {}
	for record in grace.public_state().records:
		if str(record.get("actor_id", "")) == str(disconnected.get("actor_id", "")):
			disconnected_record = record
	assert(not disconnected_record.is_empty())
	assert(not bool(disconnected_record.get("connected", true)))

	# A stranger presenting a wrong token cannot steal the reserved slot.
	assert(grace.reclaim_peer("not-the-token", 9).is_empty())
	assert(not grace.sweep_grace(Time.get_ticks_msec()))

	# The same client, presenting the token it was issued, gets its actor
	# identity and team back under a brand new peer id.
	var reclaimed := grace.reclaim_peer(dropped_token, 9)
	assert(not reclaimed.is_empty())
	assert(int(reclaimed.get("team", -1)) == dropped_team)
	assert(int(grace.public_state().phase) == RiftlineLobby.Phase.LIVE)
	assert(bool(reclaimed.get("connected", false)))

	# A grace window that fully expires without reconnect still abandons the
	# match, exactly as an immediate disconnect used to.
	grace.disconnect_peer(9)
	assert(int(grace.public_state().phase) == RiftlineLobby.Phase.LIVE)
	assert(grace.sweep_grace(Time.get_ticks_msec() + RiftlineLobby.RECONNECT_GRACE_MS + 1))
	assert(int(grace.public_state().phase) == RiftlineLobby.Phase.ABANDONED)

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
