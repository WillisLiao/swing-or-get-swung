class_name RiftlineNetwork
extends Node

signal session_status(status: String)
signal host_discovered(session: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal input_received(peer_id: int, frame: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal reliable_event_received(event: Dictionary, sender_id: int)
signal team_assigned(team: int)
signal actor_assigned(actor_id: String, team: int)
signal roster_received(records: Array[Dictionary])
signal session_descriptor_received(descriptor: Dictionary)
signal lobby_state_received(state: Dictionary)
signal lobby_live_received(state: Dictionary)
signal lobby_abandoned_received(state: Dictionary)

const PROJECT_ID := "riftline-lan"
const PROTOCOL_VERSION := 9
const APP_HOST_DUEL_REMOTE_SLOTS := 1
const APP_HOST_SQUAD_REMOTE_SLOTS := 9
const DEDICATED_REMOTE_SLOTS := 10
const ENET_PORT := 34711
const DISCOVERY_PORT := 34712
const INPUT_CHANNEL := 1
const SNAPSHOT_CHANNEL := 2
const MAX_FUTURE_INPUT := 24
const MAX_MOVE_COMPONENT := 1.05
const MAX_VIEW_TURN_PER_FRAME := 0.55
const ADVERTISEMENT_INTERVAL := 0.65
const DISCOVERY_TTL := 4.0

enum SessionRole { OFFLINE, APP_HOST, DEDICATED_SERVER, JOINING_CLIENT }

var _peer: ENetMultiplayerPeer
var _discovery_socket: PacketPeerUDP
var _discovery_listening := false
var _advertising := false
var _advertisement_remaining := 0.0
var _discovered_address := ""
var _discovered_marker := ""
var _last_input_sequence: Dictionary = {}
var _last_input_view: Dictionary = {}
var roster: RiftlineRoster
var lobby: RiftlineLobby
var lobby_state: Dictionary = {}
var team_size := 1
var game_mode: int = 0
var arena_id: RiftlineMap.Id = RiftlineMap.Id.DUEL_YARD
var arena_override_set := false
var discovered_session: Dictionary = {}
var session_descriptor: Dictionary = {}
var _configuration_valid := true
var local_actor_id := ""
var _session_marker := ""
var session_role: SessionRole = SessionRole.OFFLINE
var local_team := -1
var simulation_clock := 0.0
var _sim_latency := 0.0
var _sim_jitter := 0.0
var _sim_loss_percent := 0.0
var _sim_random := RandomNumberGenerator.new()
var _sim_queue: Array[Dictionary] = []
var _sim_unreliable_sequence := 0
var _sim_last_unreliable_release := -1
var _sim_reliable_release_after := 0.0
var _lobby_auto_ready := false
var _last_logged_lobby_phase := -1

func _ready() -> void:
	_read_command_line_options()
	roster = RiftlineRoster.new()
	roster.configure(team_size, session_role == SessionRole.DEDICATED_SERVER, false)
	lobby = RiftlineLobby.new()
	lobby.configure(team_size, arena_id, session_role == SessionRole.DEDICATED_SERVER)
	roster = lobby.roster
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	simulation_clock += delta
	_release_simulated_messages()
	if _advertising:
		_advertisement_remaining -= delta
		if _advertisement_remaining <= 0.0:
			_advertisement_remaining = ADVERTISEMENT_INTERVAL
			_advertise_session()
	if _discovery_listening:
		_poll_discovery()

func host_lan() -> Error:
	stop()
	if not _configuration_valid:
		session_status.emit("LINK ERROR")
		return ERR_INVALID_PARAMETER
	session_role = SessionRole.APP_HOST
	_configure_roster(false)
	_configure_lobby(false)
	var remote_slots := APP_HOST_SQUAD_REMOTE_SLOTS if team_size > 1 else APP_HOST_DUEL_REMOTE_SLOTS
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(ENET_PORT, remote_slots)
	if error != OK:
		_peer = null
		session_status.emit("LINK ERROR")
		return error
	multiplayer.multiplayer_peer = _peer
	var host_record := lobby.add_host()
	local_actor_id = str(host_record.get("actor_id", ""))
	local_team = int(host_record.get("team", -1))
	_session_marker = _new_session_marker()
	session_descriptor = _descriptor_from_packet(_session_event())
	_start_advertising()
	if _lobby_auto_ready:
		submit_lobby_ready(true)
	session_status.emit("WAITING FOR RIVAL")
	return OK

func begin_lan_discovery() -> void:
	stop()
	session_role = SessionRole.JOINING_CLIENT
	_discovery_socket = PacketPeerUDP.new()
	var error := _discovery_socket.bind(DISCOVERY_PORT)
	if error != OK:
		_discovery_socket = null
		session_status.emit("SCAN UNAVAILABLE")
		return
	_discovery_listening = true
	session_status.emit("SEEKING RIFT")

func join_discovered_host() -> Error:
	if _discovered_address.is_empty():
		session_status.emit("NO RIFT FOUND")
		return ERR_UNAVAILABLE
	return _join_address(_discovered_address)

func stop() -> void:
	_stop_discovery()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_peer = null
	_last_input_sequence.clear()
	_last_input_view.clear()
	_configure_roster(session_role == SessionRole.DEDICATED_SERVER)
	_configure_lobby(session_role == SessionRole.DEDICATED_SERVER)
	local_actor_id = ""
	local_team = -1
	_discovered_address = ""
	_discovered_marker = ""
	discovered_session.clear()
	session_descriptor.clear()
	_session_marker = ""
	_sim_queue.clear()
	_sim_reliable_release_after = simulation_clock
	session_role = SessionRole.OFFLINE
	lobby_state.clear()

func send_input(frame: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	_queue_or_send({"kind": "input", "frame": frame})

func publish_snapshot(snapshot: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_queue_or_send({"kind": "snapshot", "snapshot": snapshot})

func publish_event(event: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		reliable_event_received.emit(event, multiplayer.get_unique_id())
		_queue_or_send({"kind": "event", "event": event}, true)
	else:
		_queue_or_send({"kind": "client_event", "event": event}, true)

func submit_lobby_ready(ready: bool) -> bool:
	if lobby == null or not multiplayer.is_server():
		return false
	var changed := lobby.set_host_ready(ready)
	if changed:
		_broadcast_lobby_state()
		_maybe_arm_lobby()
	return changed

func submit_lobby_rematch_ready(ready: bool) -> bool:
	if lobby == null or not multiplayer.is_server():
		return false
	var changed := lobby.set_host_rematch_ready(ready)
	if changed:
		_broadcast_lobby_state()
		_maybe_arm_rematch()
	return changed

func publish_lobby_live() -> bool:
	if lobby == null or not multiplayer.is_server():
		return false
	if not lobby.commit_live(lobby.current_generation()):
		return false
	_broadcast_lobby_event("lobby_live", lobby.public_state())
	return true

func publish_lobby_finished() -> void:
	if lobby == null or not multiplayer.is_server():
		return
	lobby.finish_match()
	_broadcast_lobby_state()

func publish_lobby_abandoned(reason: String) -> void:
	if lobby == null or not multiplayer.is_server():
		return
	lobby.abandon_live(reason)
	_broadcast_lobby_event("lobby_abandoned", lobby.public_state())

func _submit_client_lobby_intent(event: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	_queue_or_send({"kind": "client_event", "event": event}, true)

func submit_client_lobby_ready(ready: bool, revision: int) -> void:
	_submit_client_lobby_intent({"type": "lobby_ready", "ready": ready, "revision": revision})

func submit_client_lobby_rematch_ready(ready: bool, revision: int) -> void:
	_submit_client_lobby_intent({"type": "lobby_rematch_ready", "ready": ready, "revision": revision})

func submit_client_lobby_leave() -> void:
	_submit_client_lobby_intent({"type": "lobby_leave"})

func start_command_line_mode() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "--dedicated-server":
			return _start_dedicated_server() == OK
		if argument == "--lan-host":
			return host_lan() == OK
		if argument.begins_with("--lan-join="):
			var address := argument.trim_prefix("--lan-join=")
			if not _is_ipv4(address):
				session_status.emit("LINK ERROR")
				return false
			_discovered_address = address
			session_role = SessionRole.JOINING_CLIENT
			return _join_address(address) == OK
	return false

func is_active() -> bool:
	return multiplayer.multiplayer_peer != null

func _join_address(address: String) -> Error:
	var expected_descriptor := session_descriptor.duplicate(true)
	var expected_arena := arena_id
	var expected_team_size := team_size
	stop()
	session_role = SessionRole.JOINING_CLIENT
	if not expected_descriptor.is_empty():
		session_descriptor = expected_descriptor
		arena_id = expected_arena
		team_size = expected_team_size
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, ENET_PORT)
	if error != OK:
		_peer = null
		session_status.emit("LINK ERROR")
		return error
	multiplayer.multiplayer_peer = _peer
	session_status.emit("LINKING")
	return OK

func _start_advertising() -> void:
	_discovery_socket = PacketPeerUDP.new()
	var error := _discovery_socket.bind(0)
	if error != OK:
		_discovery_socket = null
		_advertising = false
		return
	_discovery_socket.set_broadcast_enabled(true)
	_discovery_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_advertising = true
	_advertisement_remaining = 0.0

func _stop_discovery() -> void:
	_advertising = false
	_discovery_listening = false
	_advertisement_remaining = 0.0
	if _discovery_socket != null:
		_discovery_socket.close()
	_discovery_socket = null

func _advertise_session() -> void:
	if not _advertising or _discovery_socket == null or not multiplayer.is_server():
		return
	var packet := {
		"project": PROJECT_ID,
		"version": PROTOCOL_VERSION,
		"marker": _session_marker,
		"kind": "dedicated" if session_role == SessionRole.DEDICATED_SERVER else "app_host",
		"mode": "squad" if team_size > 1 else "duel",
		"team_size": team_size,
		"game_mode": game_mode,
		"map_id": arena_name(arena_id),
		"issued": Time.get_ticks_msec(),
	}
	_discovery_socket.put_packet(JSON.stringify(packet).to_utf8_buffer())

func _poll_discovery() -> void:
	if _discovery_socket == null:
		return
	while _discovery_socket.get_available_packet_count() > 0:
		var raw := _discovery_socket.get_packet()
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var packet: Dictionary = parsed
		if packet.get("project", "") != PROJECT_ID or int(packet.get("version", -1)) != PROTOCOL_VERSION:
			if packet.get("project", "") == PROJECT_ID and int(packet.get("version", -1)) != PROTOCOL_VERSION:
				session_status.emit("RIFT VERSION MISMATCH")
			continue
		var issued := int(packet.get("issued", 0))
		if issued > 0 and Time.get_ticks_msec() - issued > int(DISCOVERY_TTL * 1000.0):
			continue
		var marker := str(packet.get("marker", ""))
		if marker.is_empty() or marker == _discovered_marker:
			continue
		_discovered_marker = marker
		_discovered_address = _discovery_socket.get_packet_ip()
		discovered_session = packet.duplicate(true)
		session_descriptor = _descriptor_from_packet(packet)
		arena_id = int(session_descriptor.get("map_id", int(arena_id))) as RiftlineMap.Id
		team_size = int(session_descriptor.get("team_size", team_size))
		game_mode = clampi(int(session_descriptor.get("game_mode", game_mode)), 0, 1)
		host_discovered.emit({"marker": marker, "address": _discovered_address, "mode": str(packet.get("mode", "duel")), "team_size": int(packet.get("team_size", 1)), "map_id": str(packet.get("map_id", "duel-yard")), "label": "RIFT FOUND"})
		session_status.emit("RIFT FOUND")

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		var assigned := lobby.admit_peer(peer_id) if lobby != null else {}
		if assigned.is_empty():
			_peer.disconnect_peer(peer_id, true)
			session_status.emit("RIFT FULL")
			return
		_send_server_event(peer_id, _session_event())
		_send_server_event(peer_id, {"type": "assigned_actor", "actor_id": assigned.actor_id, "team": int(assigned.team)})
		_broadcast_roster()
		_broadcast_lobby_state()
		session_status.emit("RIVAL LINKED")
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_last_input_sequence.erase(peer_id)
	_last_input_view.erase(peer_id)
	if multiplayer.is_server():
		var removed := lobby.remove_peer(peer_id) if lobby != null else roster.remove_peer(peer_id)
		if not removed.is_empty():
			_broadcast_roster()
			if lobby != null and int(lobby.public_state().phase) == RiftlineLobby.Phase.ABANDONED:
				_broadcast_lobby_event("lobby_abandoned", lobby.public_state())
				if session_role == SessionRole.DEDICATED_SERVER and lobby.reset_empty():
					_broadcast_lobby_state()
			else:
				_broadcast_lobby_state()
	peer_left.emit(peer_id)
	session_status.emit("LINK LOST")

func _on_connected_to_server() -> void:
	_stop_discovery()
	session_status.emit("RIVAL LINKED")
	peer_joined.emit(1)

func _on_connection_failed() -> void:
	session_status.emit("LINK FAILED")
	stop()

func _on_server_disconnected() -> void:
	session_status.emit("LINK LOST")
	peer_left.emit(1)
	stop()

@rpc("any_peer", "call_remote", "unreliable_ordered", INPUT_CHANNEL)
func _rpc_input(frame: Dictionary) -> void:
	if not multiplayer.is_server() or frame.is_empty():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if int(frame.get("protocol", -1)) != PROTOCOL_VERSION:
		_peer.disconnect_peer(sender, true)
		session_status.emit("RIFT VERSION MISMATCH")
		return
	var validated := _validate_input(sender, frame)
	if validated.is_empty():
		return
	var sequence := int(validated.sequence)
	var previous := int(_last_input_sequence.get(sender, -1))
	if sequence <= previous or sequence > previous + MAX_FUTURE_INPUT:
		return
	_last_input_sequence[sender] = sequence
	_last_input_view[sender] = float(validated.yaw)
	input_received.emit(sender, validated)

@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)
func _rpc_snapshot(snapshot: Dictionary) -> void:
	if multiplayer.is_server():
		return
	if not snapshot.has("tick") or not snapshot.has("players"):
		return
	snapshot_received.emit(snapshot)

@rpc("authority", "reliable")
func _rpc_event(event: Dictionary) -> void:
	if multiplayer.is_server():
		return
	reliable_event_received.emit(event, 1)
	var event_type := str(event.get("type", ""))
	if event_type == "assigned_actor":
		local_actor_id = str(event.get("actor_id", ""))
		local_team = int(event.get("team", -1))
		actor_assigned.emit(local_actor_id, local_team)
		team_assigned.emit(local_team)
	elif event_type == "roster":
		var public_records: Array[Dictionary] = _validated_public_records(event.get("records", []))
		roster_received.emit(public_records)
	elif event_type == "session":
		if int(event.get("protocol", -1)) != PROTOCOL_VERSION:
			session_status.emit("RIFT VERSION MISMATCH")
			stop()
			return
		var descriptor := _descriptor_from_packet(event)
		session_descriptor = descriptor
		arena_id = int(descriptor.get("map_id", int(arena_id))) as RiftlineMap.Id
		team_size = clampi(int(descriptor.get("team_size", team_size)), RiftlineRoster.MIN_TEAM_SIZE, RiftlineRoster.MAX_TEAM_SIZE)
		game_mode = clampi(int(descriptor.get("game_mode", game_mode)), 0, 1)
		session_descriptor_received.emit(descriptor)
	elif event_type == "lobby_state":
		lobby_state = _validated_lobby_state(event.get("state", {}))
		lobby_state_received.emit(lobby_state.duplicate(true))
		if not multiplayer.is_server() and int(lobby_state.get("phase", -1)) == RiftlineLobby.Phase.STAGING and not local_actor_id.is_empty():
			if _lobby_auto_ready:
				submit_client_lobby_ready(true, int(lobby_state.get("revision", 0)))
	elif event_type == "lobby_live":
		lobby_state = _validated_lobby_state(event.get("state", {}))
		lobby_live_received.emit(lobby_state.duplicate(true))
	elif event_type == "lobby_abandoned":
		lobby_state = _validated_lobby_state(event.get("state", {}))
		lobby_abandoned_received.emit(lobby_state.duplicate(true))

@rpc("any_peer", "reliable")
func _rpc_client_event(event: Dictionary) -> void:
	if not multiplayer.is_server() or event.is_empty():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _handle_lobby_intent(event, sender):
		return
	reliable_event_received.emit(event, sender)

func peer_team(peer_id: int) -> int:
	if roster == null:
		return -1
	return int(roster.actor_for_peer(peer_id).get("team", -1))

func peer_actor_id(peer_id: int) -> String:
	if roster == null:
		return ""
	return str(roster.actor_for_peer(peer_id).get("actor_id", ""))

func is_authority_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func is_dedicated_server() -> bool:
	return session_role == SessionRole.DEDICATED_SERVER

func configuration_valid() -> bool:
	return _configuration_valid

static func default_arena_for_team_size(requested_team_size: int) -> RiftlineMap.Id:
	return RiftlineMap.Id.CONCOURSE if requested_team_size > 1 else RiftlineMap.Id.DUEL_YARD

func arena_name(next_arena_id: RiftlineMap.Id) -> String:
	return "concourse" if next_arena_id == RiftlineMap.Id.CONCOURSE else "duel-yard"

static func arena_id_from_name(value: String) -> int:
	if value == "duel-yard":
		return RiftlineMap.Id.DUEL_YARD
	if value == "concourse":
		return RiftlineMap.Id.CONCOURSE
	return -1

func _session_event() -> Dictionary:
	return {
		"type": "session",
		"team_size": team_size,
		"game_mode": game_mode,
		"map_id": int(arena_id),
		"map_name": arena_name(arena_id),
		"protocol": PROTOCOL_VERSION,
	}

func _descriptor_from_packet(packet: Dictionary) -> Dictionary:
	var raw_map: Variant = packet.get("map_id", -1)
	var map_value := int(raw_map) if raw_map is int else arena_id_from_name(str(raw_map))
	if map_value < 0:
		map_value = arena_id_from_name(str(packet.get("map_name", "")))
	return {
		"team_size": clampi(int(packet.get("team_size", team_size)), RiftlineRoster.MIN_TEAM_SIZE, RiftlineRoster.MAX_TEAM_SIZE),
		"game_mode": clampi(int(packet.get("game_mode", game_mode)), 0, 1),
		"map_id": map_value if map_value in [RiftlineMap.Id.DUEL_YARD, RiftlineMap.Id.CONCOURSE] else int(default_arena_for_team_size(int(packet.get("team_size", team_size)))),
		"protocol": int(packet.get("protocol", packet.get("version", PROTOCOL_VERSION))),
	}

func _start_dedicated_server() -> Error:
	stop()
	if not _configuration_valid:
		session_status.emit("LINK ERROR")
		return ERR_INVALID_PARAMETER
	session_role = SessionRole.DEDICATED_SERVER
	_configure_lobby(true)
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(ENET_PORT, DEDICATED_REMOTE_SLOTS)
	if error != OK:
		_peer = null
		session_status.emit("LINK ERROR")
		return error
	multiplayer.multiplayer_peer = _peer
	_session_marker = _new_session_marker()
	session_descriptor = _descriptor_from_packet(_session_event())
	_start_advertising()
	print("Riftline dedicated authority listening on LAN")
	print("Riftline dedicated lobby: staging")
	return OK

func _validate_input(peer_id: int, frame: Dictionary) -> Dictionary:
	if int(frame.get("protocol", -1)) != PROTOCOL_VERSION:
		return {}
	if not frame.has("sequence") or typeof(frame.sequence) != TYPE_INT:
		return {}
	for key in ["move_x", "move_y", "yaw", "pitch"]:
		if not frame.has(key) or not _is_finite_number(frame[key]):
			return {}
	var move_x := float(frame.move_x)
	var move_y := float(frame.move_y)
	if absf(move_x) > MAX_MOVE_COMPONENT or absf(move_y) > MAX_MOVE_COMPONENT:
		return {}
	var yaw := float(frame.yaw)
	var pitch := clampf(float(frame.pitch), -1.05, 0.9)
	if _last_input_view.has(peer_id) and absf(angle_difference(float(_last_input_view[peer_id]), yaw)) > MAX_VIEW_TURN_PER_FRAME:
		return {}
	for key in ["aim", "fire", "jump", "crouch", "prone", "weapon_switch", "reload", "pass_seed", "interact"]:
		if not frame.has(key) or typeof(frame[key]) != TYPE_BOOL:
			return {}
	if not frame.has("lean") or not _is_finite_number(frame["lean"]):
		return {}
	return {
		"protocol": PROTOCOL_VERSION,
		"sequence": int(frame.sequence),
		"move_x": clampf(move_x, -1.0, 1.0),
		"move_y": clampf(move_y, -1.0, 1.0),
		"yaw": yaw,
		"pitch": pitch,
		"aim": bool(frame.aim),
		"fire": bool(frame.fire),
		"jump": bool(frame.jump),
		"crouch": bool(frame.crouch),
		"prone": bool(frame.prone),
		"weapon_switch": bool(frame.weapon_switch),
		"reload": bool(frame.reload),
		"pass_seed": bool(frame.pass_seed),
		"interact": bool(frame.interact),
		"lean": clampi(int(frame["lean"]), -1, 1),
	}

func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

func _read_command_line_options() -> void:
	var arena_override := -1
	var arena_preview_requested := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--dedicated-server":
			session_role = SessionRole.DEDICATED_SERVER
		elif argument == "--lan-host":
			session_role = SessionRole.APP_HOST
		elif argument.begins_with("--lan-join="):
			session_role = SessionRole.JOINING_CLIENT
		elif argument.begins_with("--team-size="):
			var raw_size := argument.trim_prefix("--team-size=")
			if not raw_size.is_valid_int():
				_configuration_valid = false
				continue
			var requested_size := raw_size.to_int()
			if requested_size < RiftlineRoster.MIN_TEAM_SIZE or requested_size > RiftlineRoster.MAX_TEAM_SIZE:
				_configuration_valid = false
				continue
			team_size = requested_size
		elif argument.begins_with("--mode="):
			var mode_name := argument.trim_prefix("--mode=")
			if mode_name == "bomb":
				game_mode = 1
			elif mode_name == "deathmatch":
				game_mode = 0
			else:
				_configuration_valid = false
		elif argument.begins_with("--arena="):
			var requested_arena := arena_id_from_name(argument.trim_prefix("--arena="))
			if requested_arena < 0:
				_configuration_valid = false
			else:
				arena_override = requested_arena
				arena_override_set = true
		elif argument.begins_with("--arena-preview="):
			arena_preview_requested = true
		elif argument.begins_with("--net-sim-latency-ms="):
			_sim_latency = maxf(0.0, argument.trim_prefix("--net-sim-latency-ms=").to_float() / 1000.0)
		elif argument.begins_with("--net-sim-jitter-ms="):
			_sim_jitter = maxf(0.0, argument.trim_prefix("--net-sim-jitter-ms=").to_float() / 1000.0)
		elif argument.begins_with("--net-sim-loss-percent="):
			_sim_loss_percent = clampf(argument.trim_prefix("--net-sim-loss-percent=").to_float(), 0.0, 100.0)
		elif argument.begins_with("--net-sim-seed="):
			_sim_random.seed = int(argument.trim_prefix("--net-sim-seed="))
		elif argument == "--lobby-auto-ready":
			_lobby_auto_ready = true
	arena_id = arena_override as RiftlineMap.Id if arena_override >= 0 else RiftlineMap.Id.CONCOURSE if arena_preview_requested else default_arena_for_team_size(team_size)
	if _sim_latency > 0.0 or _sim_jitter > 0.0 or _sim_loss_percent > 0.0:
		print("Riftline network test profile: latency=%dms jitter=%dms loss=%.1f%%" % [_sim_latency * 1000.0, _sim_jitter * 1000.0, _sim_loss_percent])

func _queue_or_send(message: Dictionary, reliable: bool = false) -> void:
	if _sim_latency <= 0.0 and _sim_jitter <= 0.0 and _sim_loss_percent <= 0.0:
		_send_message(message)
		return
	if not reliable and _sim_random.randf() * 100.0 < _sim_loss_percent:
		return
	var delay := _sim_latency + _sim_random.randf_range(-_sim_jitter, _sim_jitter)
	delay = maxf(0.0, delay)
	var queued := message.duplicate(true)
	queued["release_at"] = simulation_clock + delay
	queued["reliable"] = reliable
	if not reliable:
		queued["order"] = _sim_unreliable_sequence
		_sim_unreliable_sequence += 1
	else:
		queued["release_at"] = maxf(float(queued.release_at), _sim_reliable_release_after)
		_sim_reliable_release_after = float(queued.release_at)
	_sim_queue.append(queued)

func _release_simulated_messages() -> void:
	if _sim_queue.is_empty():
		return
	var ready: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for message in _sim_queue:
		if float(message.release_at) <= simulation_clock:
			ready.append(message)
		else:
			waiting.append(message)
	_sim_queue = waiting
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.release_at) < float(b.release_at))
	for message in ready:
		if not bool(message.reliable):
			var order := int(message.order)
			if order <= _sim_last_unreliable_release:
				continue
			_sim_last_unreliable_release = order
		_send_message(message)

func _send_message(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"input":
			_rpc_input.rpc_id(1, message.frame)
		"snapshot":
			_rpc_snapshot.rpc(message.snapshot)
		"event":
			_rpc_event.rpc(message.event)
		"event_to_peer":
			_rpc_event.rpc_id(int(message.peer_id), message.event)
		"client_event":
			_rpc_client_event.rpc_id(1, message.event)

func _send_server_event(peer_id: int, event: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	_queue_or_send({"kind": "event_to_peer", "peer_id": peer_id, "event": event}, true)

func _broadcast_roster() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var public_records := roster.public_records()
	_queue_or_send({"kind": "event", "event": {"type": "roster", "records": public_records}}, true)

func _configure_roster(is_dedicated: bool) -> void:
	roster = RiftlineRoster.new()
	roster.configure(team_size, is_dedicated, false)

func _configure_lobby(is_dedicated: bool) -> void:
	lobby = RiftlineLobby.new()
	lobby.configure(team_size, arena_id, is_dedicated)
	roster = lobby.roster
	lobby_state = lobby.public_state()

func _broadcast_lobby_state() -> void:
	if lobby == null or multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	lobby_state = lobby.public_state()
	_broadcast_lobby_event("lobby_state", lobby_state)

func _broadcast_lobby_event(event_type: String, state: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var event := {"type": event_type, "state": state.duplicate(true)}
	_log_lobby_phase(state)
	reliable_event_received.emit(event, multiplayer.get_unique_id())
	_queue_or_send({"kind": "event", "event": event}, true)

func _log_lobby_phase(state: Dictionary) -> void:
	if session_role != SessionRole.DEDICATED_SERVER:
		return
	var phase := int(state.get("phase", -1))
	if phase == _last_logged_lobby_phase:
		return
	_last_logged_lobby_phase = phase
	var labels := ["staging", "arming", "live", "rematch", "abandoned"]
	if phase >= 0 and phase < labels.size():
		print("Riftline dedicated lobby: %s" % labels[phase])

func _handle_lobby_intent(event: Dictionary, sender_id: int) -> bool:
	if lobby == null or not multiplayer.is_server():
		return false
	var event_type := str(event.get("type", ""))
	if event_type == "lobby_leave":
		var removed := lobby.remove_peer(sender_id)
		if not removed.is_empty():
			_broadcast_roster()
			_broadcast_lobby_event("lobby_abandoned" if int(lobby.public_state().phase) == RiftlineLobby.Phase.ABANDONED else "lobby_state", lobby.public_state())
		return true
	if event_type not in ["lobby_ready", "lobby_rematch_ready"]:
		return false
	if typeof(event.get("ready", null)) != TYPE_BOOL or typeof(event.get("revision", null)) != TYPE_INT:
		_broadcast_lobby_state()
		return true
	if int(event.revision) != int(lobby.public_state().revision):
		_broadcast_lobby_state()
		return true
	var changed := lobby.set_ready(sender_id, bool(event.ready)) if event_type == "lobby_ready" else lobby.set_rematch_ready(sender_id, bool(event.ready))
	if changed:
		_broadcast_lobby_state()
		_maybe_arm_lobby() if event_type == "lobby_ready" else _maybe_arm_rematch()
	else:
		_broadcast_lobby_state()
	return true

func _maybe_arm_lobby() -> void:
	if lobby != null and lobby.start_live():
		_broadcast_lobby_state()

func _maybe_arm_rematch() -> void:
	if lobby != null and lobby.start_rematch():
		_broadcast_lobby_state()

func _validated_lobby_state(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var state: Dictionary = value
	var result := {
		"phase": clampi(int(state.get("phase", RiftlineLobby.Phase.STAGING)), RiftlineLobby.Phase.STAGING, RiftlineLobby.Phase.ABANDONED),
		"arena_id": int(state.get("arena_id", int(arena_id))),
		"arena_name": str(state.get("arena_name", arena_name(arena_id))),
		"team_size": clampi(int(state.get("team_size", team_size)), RiftlineRoster.MIN_TEAM_SIZE, RiftlineRoster.MAX_TEAM_SIZE),
		"game_mode": clampi(int(state.get("game_mode", game_mode)), 0, 1),
		"revision": maxi(0, int(state.get("revision", 0))),
		"records": _validated_public_records(state.get("records", [])),
		"complete": bool(state.get("complete", false)),
		"launchable": bool(state.get("launchable", false)),
	}
	if state.has("launch_generation"):
		result["launch_generation"] = maxi(0, int(state.get("launch_generation", 0)))
	if state.has("reason"):
		result["reason"] = str(state.get("reason", ""))
	return result

func _validated_public_records(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for candidate in value:
		if not candidate is Dictionary:
			continue
		if candidate.has("peer_id") or candidate.has("address") or candidate.has("hostname"):
			continue
		var actor_id := str(candidate.get("actor_id", ""))
		var team := int(candidate.get("team", -1))
		if actor_id.is_empty() or team < Duelist.Team.SUN or team > Duelist.Team.VOID:
			continue
		result.append({"actor_id": actor_id, "team": team, "human": bool(candidate.get("human", false))})
	return result

func _new_session_marker() -> String:
	return "%s-%s" % [Time.get_ticks_msec(), randi()]

func _is_ipv4(address: String) -> bool:
	var pieces := address.split(".")
	if pieces.size() != 4:
		return false
	for piece in pieces:
		if piece.is_empty() or not piece.is_valid_int() or int(piece) < 0 or int(piece) > 255:
			return false
	return true
