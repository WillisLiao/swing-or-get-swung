class_name RiftlineRoster
extends RefCounted

## Authority-owned actor identity and team assignment.
##
## The roster deliberately knows nothing about nodes, input, physics, or match
## rules.  Its small interface hides capacity, balancing, immutable IDs, and
## the difference between private authority records and public wire records.

signal actor_added(record: Dictionary)
signal actor_removed(actor_id: String)

const MIN_TEAM_SIZE := 1
const MAX_TEAM_SIZE := 4

var team_size := 4
var dedicated_session := false
var bot_fill_enabled := false

var _records_by_id: Dictionary = {}
var _actor_by_peer: Dictionary = {}
var _actor_by_token: Dictionary = {}
var _used_actor_ids: Dictionary = {}
var _peer_generations: Dictionary = {}

func configure(requested_team_size: int = 4, is_dedicated_session: bool = false, allow_bot_fill: bool = false) -> bool:
	if requested_team_size < MIN_TEAM_SIZE or requested_team_size > MAX_TEAM_SIZE:
		return false
	team_size = requested_team_size
	dedicated_session = is_dedicated_session
	bot_fill_enabled = allow_bot_fill
	return true

func add_host() -> Dictionary:
	if dedicated_session or _records_by_id.has("host"):
		return {}
	return _add_record("host", -1, Duelist.Team.RED, true)

func assign_peer(peer_id: int) -> Dictionary:
	if peer_id <= 0 or _actor_by_peer.has(peer_id):
		return {}
	var team := _balanced_team()
	if team < 0:
		return {}
	var actor_id := _next_peer_actor_id(peer_id)
	return _add_record(actor_id, peer_id, team as Duelist.Team, true, _new_rejoin_token())

func add_bot(actor_id: String, team: Duelist.Team) -> Dictionary:
	if actor_id.is_empty() or _used_actor_ids.has(actor_id) or not _has_room_for(team):
		return {}
	return _add_record(actor_id, -1, team, false)

func remove_peer(peer_id: int) -> Dictionary:
	var actor_id := str(_actor_by_peer.get(peer_id, ""))
	if actor_id.is_empty():
		return {}
	return remove_actor(actor_id)

func remove_actor(actor_id: String) -> Dictionary:
	var existing := record(actor_id)
	if existing.is_empty():
		return {}
	var peer_id := int(existing.get("peer_id", -1))
	if peer_id > 0:
		_actor_by_peer.erase(peer_id)
	var token := str(existing.get("rejoin_token", ""))
	if not token.is_empty():
		_actor_by_token.erase(token)
	_records_by_id.erase(actor_id)
	actor_removed.emit(actor_id)
	return existing

## Marks a human actor's connection as lost without freeing their slot. The
## record, team assignment, and rejoin token all survive so `reclaim()` can
## restore the same actor identity when the same client reconnects within
## the grace window. Distinct from `remove_peer`, which frees the slot for
## someone else immediately (used pre-match, where there is no match state
## worth preserving).
func disconnect_peer(peer_id: int) -> Dictionary:
	var actor_id := str(_actor_by_peer.get(peer_id, ""))
	if actor_id.is_empty():
		return {}
	var existing: Dictionary = _records_by_id[actor_id]
	if str(existing.get("rejoin_token", "")).is_empty():
		# No token to reclaim with (e.g. the host) - this is a hard removal.
		return remove_actor(actor_id)
	_actor_by_peer.erase(peer_id)
	existing["peer_id"] = -1
	existing["connected"] = false
	existing["disconnected_at"] = Time.get_ticks_msec()
	_records_by_id[actor_id] = existing
	return existing.duplicate(true)

## Restores a previously disconnected actor to a freshly connected peer id,
## presenting the rejoin token issued when that actor was first admitted.
## Returns {} if the token does not match a currently-disconnected actor.
func reclaim(token: String, peer_id: int) -> Dictionary:
	if token.is_empty() or peer_id <= 0 or _actor_by_peer.has(peer_id):
		return {}
	var actor_id := str(_actor_by_token.get(token, ""))
	if actor_id.is_empty() or not _records_by_id.has(actor_id):
		return {}
	var existing: Dictionary = _records_by_id[actor_id]
	if bool(existing.get("connected", true)):
		return {}
	existing["peer_id"] = peer_id
	existing["connected"] = true
	existing["disconnected_at"] = 0
	_records_by_id[actor_id] = existing
	_actor_by_peer[peer_id] = actor_id
	return existing.duplicate(true)

## Every currently disconnected human actor, for grace-timeout sweeps.
func disconnected_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for existing in _records_by_id.values():
		if not bool((existing as Dictionary).get("connected", true)):
			result.append((existing as Dictionary).duplicate(true))
	return result

func actor_for_peer(peer_id: int) -> Dictionary:
	var actor_id := str(_actor_by_peer.get(peer_id, ""))
	return record(actor_id)

func record(actor_id: String) -> Dictionary:
	var existing: Variant = _records_by_id.get(actor_id, null)
	return existing.duplicate(true) if existing is Dictionary else {}

func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for existing in _records_by_id.values():
		result.append((existing as Dictionary).duplicate(true))
	return result

func public_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for existing in _records_by_id.values():
		result.append(_public_record(existing))
	return result


func is_ready() -> bool:
	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		var count := _team_count(team, false if not bot_fill_enabled else true)
		if count < team_size:
			return false
	return true

func team_records(team: Duelist.Team) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for existing in _records_by_id.values():
		if int(existing.get("team", -1)) == int(team):
			result.append((existing as Dictionary).duplicate(true))
	return result

func _add_record(actor_id: String, peer_id: int, team: Duelist.Team, human: bool, rejoin_token: String = "") -> Dictionary:
	if actor_id.is_empty() or _records_by_id.has(actor_id) or not _has_room_for(team):
		return {}
	var next := {
		"actor_id": actor_id,
		"peer_id": peer_id,
		"team": int(team),
		"human": human,
		"connected": true,
		"disconnected_at": 0,
		"rejoin_token": rejoin_token,
	}
	_records_by_id[actor_id] = next
	_used_actor_ids[actor_id] = true
	if peer_id > 0:
		_actor_by_peer[peer_id] = actor_id
	if not rejoin_token.is_empty():
		_actor_by_token[rejoin_token] = actor_id
	actor_added.emit(next.duplicate(true))
	return next.duplicate(true)

func _new_rejoin_token() -> String:
	return "%d-%d-%d" % [Time.get_ticks_usec(), randi(), randi()]

func _balanced_team() -> int:
	var red_count := _team_count(Duelist.Team.RED, false)
	var blue_count := _team_count(Duelist.Team.BLUE, false)
	if red_count >= team_size and blue_count >= team_size:
		return -1
	if red_count < blue_count:
		return int(Duelist.Team.RED)
	if blue_count < red_count:
		return int(Duelist.Team.BLUE)
	# The app-hosted first remote remains the familiar Void rival.  Dedicated
	# sessions use Sun as their explicit deterministic tie-break.
	return int(Duelist.Team.RED) if dedicated_session else int(Duelist.Team.BLUE)

func _has_room_for(team: Duelist.Team) -> bool:
	return _team_count(team, true) < team_size

func _team_count(team: Duelist.Team, include_bots: bool) -> int:
	var count := 0
	for existing in _records_by_id.values():
		if int(existing.get("team", -1)) != int(team):
			continue
		if include_bots or bool(existing.get("human", false)):
			count += 1
	return count

func _next_peer_actor_id(peer_id: int) -> String:
	var generation := int(_peer_generations.get(peer_id, 0))
	var candidate := "peer_%d" % peer_id if generation == 0 else "peer_%d_%d" % [peer_id, generation + 1]
	while _used_actor_ids.has(candidate):
		generation += 1
		candidate = "peer_%d_%d" % [peer_id, generation + 1]
	_peer_generations[peer_id] = generation + 1
	return candidate

func _public_record(private_record: Dictionary) -> Dictionary:
	return {
		"actor_id": str(private_record.get("actor_id", "")),
		"team": int(private_record.get("team", -1)),
		"human": bool(private_record.get("human", false)),
		"connected": bool(private_record.get("connected", true)),
	}
