class_name RiftlineLobby
extends RefCounted

## Server-authoritative staging contract for a local Rift Link session.
##
## Peer IDs and roster records stay private to this module. Callers receive
## defensive public snapshots and must submit new intent through the narrow
## methods below rather than mutating lobby state directly.

signal state_changed(state: Dictionary)

enum Phase { STAGING, ARMING, LIVE, REMATCH, ABANDONED }

var roster: RiftlineRoster
var team_size := 4
var dedicated := false

var _phase: Phase = Phase.STAGING
var _revision := 0
var _launch_generation := 0
var _ready_by_actor: Dictionary = {}
var _rematch_ready_by_actor: Dictionary = {}
var _configured := false

func configure(next_team_size: int, is_dedicated_session: bool) -> void:
	if next_team_size < RiftlineRoster.MIN_TEAM_SIZE or next_team_size > RiftlineRoster.MAX_TEAM_SIZE:
		return
	team_size = next_team_size
	dedicated = is_dedicated_session
	roster = RiftlineRoster.new()
	if not roster.configure(team_size, dedicated, false):
		return
	_phase = Phase.STAGING
	_revision = 0
	_launch_generation = 0
	_ready_by_actor.clear()
	_rematch_ready_by_actor.clear()
	_configured = true

func add_host() -> Dictionary:
	if not _configured or dedicated or _phase != Phase.STAGING:
		return {}
	var record := roster.add_host()
	if record.is_empty():
		return {}
	_ready_by_actor[str(record.get("actor_id", ""))] = false
	_revision += 1
	_emit_state()
	return record.duplicate(true)

func admit_peer(peer_id: int) -> Dictionary:
	if not _configured or _phase != Phase.STAGING:
		return {}
	var record := roster.assign_peer(peer_id)
	if record.is_empty():
		return {}
	_ready_by_actor[str(record.get("actor_id", ""))] = false
	_revision += 1
	_emit_state()
	return record.duplicate(true)

func remove_peer(peer_id: int) -> Dictionary:
	if not _configured:
		return {}
	var existing := roster.actor_for_peer(peer_id)
	if existing.is_empty():
		return {}
	var removed := roster.remove_peer(peer_id)
	var actor_id := str(removed.get("actor_id", ""))
	_ready_by_actor.erase(actor_id)
	_rematch_ready_by_actor.erase(actor_id)
	if _phase == Phase.LIVE or _phase == Phase.ARMING:
		_phase = Phase.ABANDONED
		_revision += 1
		_emit_state()
		return removed
	_revision += 1
	_emit_state()
	return removed

func set_ready(peer_id: int, ready: bool) -> bool:
	return _set_ready_for_actor(_actor_id_for_peer(peer_id), ready)

func set_host_ready(ready: bool) -> bool:
	return _set_ready_for_actor("host", ready)

func _set_ready_for_actor(actor_id: String, ready: bool) -> bool:
	if not _configured or _phase != Phase.STAGING or actor_id.is_empty():
		return false
	if roster.record(actor_id).is_empty():
		return false
	if actor_id.is_empty() or bool(ready) == bool(_ready_by_actor.get(actor_id, false)):
		return false
	_ready_by_actor[actor_id] = ready
	_revision += 1
	_emit_state()
	return true

func start_live() -> bool:
	if not _configured or not _can_launch():
		return false
	_phase = Phase.ARMING
	_launch_generation += 1
	_revision += 1
	_emit_state()
	return true

func commit_live(generation: int = -1) -> bool:
	if not _configured or _phase != Phase.ARMING:
		return false
	if generation >= 0 and generation != _launch_generation:
		return false
	_phase = Phase.LIVE
	_revision += 1
	_emit_state()
	return true

func finish_match() -> void:
	if not _configured or _phase != Phase.LIVE:
		return
	_phase = Phase.REMATCH
	_rematch_ready_by_actor.clear()
	_revision += 1
	_emit_state()

func set_rematch_ready(peer_id: int, ready: bool) -> bool:
	if not _has_human_peer(peer_id):
		return false
	return _set_rematch_ready_for_actor(_actor_id_for_peer(peer_id), ready)

func set_host_rematch_ready(ready: bool) -> bool:
	return _set_rematch_ready_for_actor("host", ready)

func _set_rematch_ready_for_actor(actor_id: String, ready: bool) -> bool:
	if not _configured or _phase != Phase.REMATCH or actor_id.is_empty():
		return false
	if roster.record(actor_id).is_empty():
		return false
	if actor_id.is_empty() or bool(ready) == bool(_rematch_ready_by_actor.get(actor_id, false)):
		return false
	_rematch_ready_by_actor[actor_id] = ready
	_revision += 1
	_emit_state()
	return true

func start_rematch() -> bool:
	if not _configured or _phase != Phase.REMATCH or not _all_rematch_ready():
		return false
	_phase = Phase.ARMING
	_launch_generation += 1
	_revision += 1
	_emit_state()
	return true

func abandon_live(reason: String) -> void:
	if not _configured:
		return
	_phase = Phase.ABANDONED
	_revision += 1
	_emit_state(reason)

func reset_empty() -> bool:
	if not _configured or not dedicated or _phase != Phase.ABANDONED:
		return false
	roster = RiftlineRoster.new()
	if not roster.configure(team_size, true, false):
		return false
	_phase = Phase.STAGING
	_ready_by_actor.clear()
	_rematch_ready_by_actor.clear()
	_revision += 1
	_emit_state()
	return true

func can_launch() -> bool:
	return _can_launch()

func is_complete() -> bool:
	return _complete_human_roster()

func current_generation() -> int:
	return _launch_generation

func public_state() -> Dictionary:
	var entries: Array[Dictionary] = []
	var is_rematch := _phase == Phase.REMATCH
	for record in roster.public_records() if roster != null else []:
		var public_record := record.duplicate(true)
		var actor_id := str(public_record.get("actor_id", ""))
		public_record["ready"] = bool((_rematch_ready_by_actor if is_rematch else _ready_by_actor).get(actor_id, false))
		entries.append(public_record)
	var result := {
		"phase": int(_phase),
		"phase_name": Phase.keys()[int(_phase)].to_upper(),
		"team_size": team_size,
		"records": entries,
		"revision": _revision,
		"complete": _complete_human_roster(),
		"launchable": _can_launch(),
	}
	if _launch_generation > 0:
		result["launch_generation"] = _launch_generation
	return result

func _can_launch() -> bool:
	return _phase == Phase.STAGING and _complete_human_roster() and _all_ready()

func _complete_human_roster() -> bool:
	if roster == null:
		return false
	var records := roster.records()
	if records.size() != team_size * 2:
		return false
	for record in records:
		if not bool(record.get("human", false)):
			return false
	return roster.is_ready()

func _all_ready() -> bool:
	if roster == null:
		return false
	for record in roster.records():
		var actor_id := str(record.get("actor_id", ""))
		if not bool(_ready_by_actor.get(actor_id, false)):
			return false
	return true

func _all_rematch_ready() -> bool:
	if roster == null or roster.records().is_empty():
		return false
	for record in roster.records():
		var actor_id := str(record.get("actor_id", ""))
		if not bool(_rematch_ready_by_actor.get(actor_id, false)):
			return false
	return true

func _has_human_peer(peer_id: int) -> bool:
	return peer_id > 0 and not roster.actor_for_peer(peer_id).is_empty()

func _actor_id_for_peer(peer_id: int) -> String:
	return str(roster.actor_for_peer(peer_id).get("actor_id", ""))

func _emit_state(reason: String = "") -> void:
	var state := public_state()
	if not reason.is_empty():
		state["reason"] = reason
	state_changed.emit(state.duplicate(true))
