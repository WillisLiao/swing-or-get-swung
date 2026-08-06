class_name RiftlineCombatFeedback
extends Node3D

## Presentation-only bridge for accepted combat and objective facts.
##
## This node deliberately knows nothing about authority, input, damage, or match
## rules.  It owns bounded audio voices and the small HUD
## signals that make an accepted fact easier to read.

signal damage_feedback(direction: Vector2, intensity: float, enemy_team: int)
signal hit_confirm_feedback
signal objective_feedback(event_type: String, scoring_team: int)

const SAMPLE_RATE := 22050
const WORLD_VOICE_COUNT := 12
const LOCAL_VOICE_COUNT := 4
const EVENT_CACHE_LIMIT := 256

var effects_enabled := true
var haptics_enabled := false

var _presentation_enabled := false
var _local_actor_id := ""
var _listener: Camera3D
var _world_players: Array[AudioStreamPlayer3D] = []
var _local_players: Array[AudioStreamPlayer] = []
var _world_streams: Dictionary = {}
var _local_streams: Dictionary = {}
var _seen_events: Dictionary = {}
var _voice_cursor := 0
var _local_voice_cursor := 0
var _last_damage_feedback_msec := -10000
var _configured := false
var _local_health := Duelist.HEALTH
var _skipped_low_priority := 0

func configure(presentation_enabled: bool, local_actor_id: String, listener: Camera3D) -> void:
	_presentation_enabled = presentation_enabled
	_local_actor_id = local_actor_id
	_listener = listener
	if not _presentation_enabled:
		stop_all()
		return
	if _configured:
		return
	_configured = true
	if _is_headless():
		return
	_build_audio_bank()
	_build_player_pools()

func set_preferences(next_effects_enabled: bool, _next_haptics_enabled: bool) -> void:
	effects_enabled = next_effects_enabled
	haptics_enabled = false
	if not effects_enabled:
		stop_all()

func weapon_fired(actor_id: String, weapon: Duelist.Weapon, origin: Vector3, local: bool) -> void:
	if not _presentation_enabled:
		return
	var event_name := "carbine_fire" if weapon == Duelist.Weapon.PULSE else "knife_fire"
	if local:
		_play_local(event_name)
	else:
		_play_world(event_name, origin, 1)

func projectile_impacted(fact: Dictionary, local_position: Vector3) -> void:
	if not _presentation_enabled:
		return
	var event_key := "impact:%s:%d" % [str(fact.get("session_id", "legacy")), int(fact.get("id", -1))]
	if _seen_events.has(event_key):
		return
	_remember_event(event_key)
	var impact_position: Vector3 = fact.get("position", Vector3.ZERO)
	var team := int(fact.get("team", int(Duelist.Team.RED)))
	_play_world("carbine_impact", impact_position, 2)
	var shooter_id := str(fact.get("shooter_id", ""))
	var target_id := str(fact.get("target_id", ""))
	var hit_duelist := bool(fact.get("hit_duelist", false))
	if hit_duelist and shooter_id == _local_actor_id and not target_id.is_empty() and target_id != _local_actor_id:
		_play_local("hit_confirm")
		hit_confirm_feedback.emit()
	if hit_duelist and target_id == _local_actor_id:
		var source_position: Variant = fact.get("source_position", null)
		var intensity := clampf(float(fact.get("damage", Duelist.HEALTH * 0.23)) / Duelist.HEALTH * 2.2, 0.2, 1.0)
		_emit_damage(_screen_direction(source_position, local_position) if source_position is Vector3 else Vector2.ZERO, intensity, team)

func knife_struck(actor_id: String, origin: Vector3, end: Vector3, team: Duelist.Team, local: bool, hit_target: bool, target_id: String = "", source_position: Variant = null, event_id: String = "", local_position: Vector3 = Vector3.ZERO) -> void:
	if not _presentation_enabled:
		return
	var event_key := "knife:%s" % event_id if not event_id.is_empty() else "knife:%s:%s:%s" % [actor_id, origin, end]
	if _seen_events.has(event_key):
		return
	_remember_event(event_key)
	if local:
		_play_local("knife_fire")
	else:
		_play_world("knife_fire", origin, 1)
	if local and hit_target:
		_play_local("hit_confirm")
		hit_confirm_feedback.emit()
	if hit_target and target_id == _local_actor_id:
		_emit_damage(_screen_direction(source_position, local_position) if source_position is Vector3 else Vector2.ZERO, 0.65, int(team))

func local_damage_received(source_position: Variant, enemy_team: int, local_position: Vector3) -> void:
	if not _presentation_enabled:
		return
	_emit_damage(_screen_direction(source_position, local_position) if source_position is Vector3 else Vector2.ZERO, 0.65, enemy_team)

func reload_started(local: bool) -> void:
	if not _presentation_enabled or not local:
		return
	_play_local("reload_start")

func reload_stage(local: bool) -> void:
	if not _presentation_enabled or not local:
		return
	_play_local("reload_stage")

func reload_completed(local: bool) -> void:
	if not _presentation_enabled or not local:
		return
	_play_local("reload_complete")

## The six objective events RiftlineMatch emits. Kept as one list so the audio
## bank and the dispatch check cannot drift apart.
const NUCLEAR_RUSH_EVENTS := [
	"core_picked_up", "core_dropped", "core_returned",
	"core_installed", "launch_cancelled", "launch_complete",
]

func objective_event(event_type: String, state: Dictionary, local: bool) -> void:
	if not _presentation_enabled:
		return
	var event_id := str(state.get("event_id", ""))
	var event_key := "objective:%s:%s" % [event_type, event_id if not event_id.is_empty() else str(state)]
	if _seen_events.has(event_key):
		return
	_remember_event(event_key)
	# The event strings are RiftlineMatch's objective_event vocabulary. Anything
	# outside it is ignored rather than played, so a new rule event stays silent
	# until a clip is deliberately added for it.
	if not event_type in NUCLEAR_RUSH_EVENTS:
		return
	var position: Vector3 = state.get("core_position", Vector3.ZERO)
	if local:
		_play_local(event_type)
	else:
		# A completed launch is the loudest fact in the match and must not be
		# dropped when the world voice pool is contended.
		_play_world(event_type, position, 4 if event_type == "launch_complete" else 3)
	objective_feedback.emit(event_type, int(state.get("installed_team", state.get("core_carrier_team", -1))))

func set_local_health(value: float) -> void:
	# Health itself remains a HUD concern.  Keeping the last accepted local value
	# here lets the feedback boundary rate-limit future cues without exposing it.
	_local_health = clampf(value, 0.0, Duelist.HEALTH)

func stop_all() -> void:
	for player in _world_players:
		if is_instance_valid(player):
			player.stop()
	for player in _local_players:
		if is_instance_valid(player):
			player.stop()

func diagnostics() -> Dictionary:
	var active_voices := 0
	for player in _world_players:
		if player.playing:
			active_voices += 1
	for player in _local_players:
		if player.playing:
			active_voices += 1
	return {
		"active_voices": active_voices,
		"world_pool": _world_players.size(),
		"local_pool": _local_players.size(),
		"seen_events": _seen_events.size(),
		"skipped_low_priority": _skipped_low_priority,
	}
func _build_audio_bank() -> void:
	_world_streams = {
		"carbine_fire": _make_clip(0.105, 190.0, 900.0, 0.85, 17),
		"knife_fire": _make_clip(0.11, 190.0, 520.0, 0.58, 29),
		"carbine_impact": _make_clip(0.055, 1250.0, 720.0, 0.44, 41),
		# Nuclear Rush core events. Rising sweeps read as gaining the objective,
		# falling ones as losing it; the launch is the longest and lowest clip so
		# it carries across the arena.
		"core_picked_up": _make_clip(0.18, 360.0, 860.0, 0.48, 53),
		"core_dropped": _make_clip(0.13, 620.0, 250.0, 0.52, 67),
		"core_returned": _make_clip(0.22, 280.0, 780.0, 0.5, 79),
		"core_installed": _make_clip(0.26, 300.0, 1020.0, 0.58, 97),
		"launch_cancelled": _make_clip(0.2, 520.0, 140.0, 0.56, 109),
		"launch_complete": _make_clip(0.42, 240.0, 1240.0, 0.66, 127),
	}
	_local_streams = {
		"carbine_fire": _make_clip(0.095, 230.0, 1050.0, 0.72, 101),
		"knife_fire": _make_clip(0.1, 220.0, 620.0, 0.62, 113),
		"carbine_impact": _make_clip(0.045, 1480.0, 880.0, 0.3, 127),
		"hit_confirm": _make_clip(0.06, 1660.0, 1040.0, 0.22, 139),
		"damage": _make_clip(0.12, 82.0, 62.0, 0.46, 151),
		"reload_start": _make_clip(0.08, 180.0, 360.0, 0.3, 163),
		"reload_stage": _make_clip(0.075, 270.0, 190.0, 0.25, 169),
		"reload_complete": _make_clip(0.105, 440.0, 760.0, 0.3, 179),
		"core_picked_up": _make_clip(0.16, 410.0, 930.0, 0.38, 191),
		"core_dropped": _make_clip(0.12, 540.0, 220.0, 0.38, 211),
		"core_returned": _make_clip(0.19, 300.0, 820.0, 0.4, 227),
		"core_installed": _make_clip(0.24, 320.0, 1120.0, 0.5, 239),
		"launch_cancelled": _make_clip(0.18, 480.0, 120.0, 0.48, 251),
		"launch_complete": _make_clip(0.36, 260.0, 1420.0, 0.6, 263),
	}

func _build_player_pools() -> void:
	for index in WORLD_VOICE_COUNT:
		var player := AudioStreamPlayer3D.new()
		player.name = "WorldVoice%02d" % index
		player.max_distance = 44.0
		player.unit_size = 10.0
		player.volume_db = -5.0
		add_child(player)
		_world_players.append(player)
	for index in LOCAL_VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "LocalVoice%02d" % index
		player.volume_db = -1.5
		add_child(player)
		_local_players.append(player)

func _play_world(event_name: String, position: Vector3, priority: int) -> void:
	if not effects_enabled or _is_headless() or _world_players.is_empty():
		return
	var player := _next_world_player(priority)
	if player == null:
		return
	player.stream = _world_streams.get(event_name, null)
	if player.stream == null:
		return
	player.global_position = position
	player.set_meta("priority", priority)
	player.play()

func _play_local(event_name: String) -> void:
	if not effects_enabled or _is_headless() or _local_players.is_empty():
		return
	var stream: AudioStream = _local_streams.get(event_name, null)
	if stream == null:
		return
	var player := _local_players[_local_voice_cursor]
	_local_voice_cursor = (_local_voice_cursor + 1) % _local_players.size()
	player.stream = stream
	player.play()

func _next_world_player(priority: int) -> AudioStreamPlayer3D:
	for offset in _world_players.size():
		var index := (_voice_cursor + offset) % _world_players.size()
		var candidate := _world_players[index]
		if not candidate.playing:
			_voice_cursor = (index + 1) % _world_players.size()
			return candidate
	var lowest := _world_players[_voice_cursor]
	for candidate in _world_players:
		if int(candidate.get_meta("priority", 0)) < int(lowest.get_meta("priority", 0)):
			lowest = candidate
	if priority < int(lowest.get_meta("priority", 0)):
		_skipped_low_priority += 1
		return null
	_voice_cursor = (_voice_cursor + 1) % _world_players.size()
	return lowest

func _screen_direction(source_position: Vector3, local_position: Vector3) -> Vector2:
	if _listener == null or source_position.distance_squared_to(local_position) < 0.0001:
		return Vector2.ZERO
	var to_source := source_position - local_position
	var camera_right := _listener.global_transform.basis.x.normalized()
	var camera_up := _listener.global_transform.basis.y.normalized()
	var direction := Vector2(to_source.dot(camera_right), -to_source.dot(camera_up))
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO

func _emit_damage(direction: Vector2, intensity: float, enemy_team: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_damage_feedback_msec < 75:
		return
	_last_damage_feedback_msec = now
	damage_feedback.emit(direction, clampf(intensity, 0.0, 1.0), enemy_team)
	_play_local("damage")
func _is_headless() -> bool:
	return DisplayServer.get_name().to_lower() == "headless"

func _remember_event(event_key: String) -> void:
	_seen_events[event_key] = true
	while _seen_events.size() > EVENT_CACHE_LIMIT:
		_seen_events.erase(_seen_events.keys()[0])

func _make_clip(duration: float, start_frequency: float, end_frequency: float, gain: float, seed: int) -> AudioStreamWAV:
	var sample_count := maxi(1, int(duration * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	var noise_state := seed
	for index in sample_count:
		var progress := float(index) / float(sample_count)
		var frequency := lerpf(start_frequency, end_frequency, progress)
		phase += TAU * frequency / SAMPLE_RATE
		noise_state = (noise_state * 1664525 + 1013904223) & 0x7fffffff
		var noise := (float(noise_state) / 1073741823.5) - 1.0
		var attack := clampf(progress / 0.06, 0.0, 1.0)
		var release := clampf((1.0 - progress) / 0.18, 0.0, 1.0)
		var envelope := attack * release
		var sample := (sin(phase) * 0.72 + noise * 0.18) * envelope * gain
		data.encode_s16(index * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
