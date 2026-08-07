class_name RiftlineArena
extends Node3D

const SNAPSHOT_BUFFER := preload("res://scripts/riftline_snapshot_buffer.gd")
const PRACTICE_PANEL := preload("res://scripts/riftline_practice_panel.gd")
const MAIN_MENU := preload("res://scripts/riftline_main_menu.gd")
const CLASS_PANEL := preload("res://scripts/riftline_class_panel.gd")
const HIGH_ALERT := preload("res://scripts/riftline_high_alert.gd")
const OPENING_HOLD_SECONDS := 2.5
const DEFAULT_OFFLINE_SQUAD_SIZE := 4

var ballistics: RiftBallistics
var hud: DuelHud
var coach: RiftlineFirstMatchCoach
var director: RiftlineMatch
var network: RiftlineNetwork
var arena_map: RiftlineMap
var rift_link: RiftLinkPanel
var practice_panel: Control
var main_menu: RiftlineMainMenu
var class_panel: RiftlineClassPanel
## Which top-level main-menu action the class panel is currently gating:
## "create" / "join" / "drill" pre-game, or "death" for the in-match
## post-elimination re-pick. Empty when the class panel isn't in use.
var _class_panel_context := ""
var _pending_player_class: Duelist.PlayerClass = Duelist.PlayerClass.FRONTLINE
var _pending_primary_weapon: Duelist.Weapon = Duelist.Weapon.RIFLE
## Local-only mirror of "seconds since the local player died," used purely to
## drive the death-screen countdown UI. The authoritative gate is always
## RiftlineMatch.can_respawn() (host) or the request simply being ignored
## until the host's own timer also clears (client) - this is display only.
var _local_death_elapsed := 0.0
var _local_was_eliminated := false
var _pending_respawn_request := false
var _mouse_captured := false
var _lan_active := false
var _lan_host := false
var _dedicated_server := false
var _presentation_enabled := true
var _lan_peer_ready := false
var _authority_match_started := false
var _lobby_arming_remaining := 0.0
var _lobby_revision := -1
var _lobby_generation := -1
var _lan_phase: RiftlineMatch.Phase = RiftlineMatch.Phase.OPENING
var _lan_tick := 0
var _local_input_sequence := 0
var _authoritative_duelists: Dictionary = {}
var _replica_duelists: Dictionary = {}
var _remote_snapshot_buffers: Dictionary = {}
var _continuous_inputs: Dictionary = {}
var _edge_queues: Dictionary = {}
var _last_sequences: Dictionary = {}
var _actor_for_peer: Dictionary = {}
var _ready_peers: Dictionary = {}
var _pending_inputs: Array[Dictionary] = []
var _local_duelist: Duelist
var combat_feedback: RiftlineCombatFeedback
var _high_alert: RiftlineHighAlert = HIGH_ALERT.new()
var _local_actor_id := ""
var _pending_actor_snapshots: Dictionary = {}
var _snapshot_remaining := 0.0
var _join_discovery_started := false
var _session_ready_for_snapshots := true
var _local_team: Duelist.Team = Duelist.Team.RED
var _capture_path := ""
var _capture_after := 2.0
var _capture_settings := false
var _capture_hud_layout := false
var _capture_character := false
var _capture_overview := false
var _capture_rift_link := false
var _offline_squad_size := DEFAULT_OFFLINE_SQUAD_SIZE
var _squad_preview := ""
var _tactics_preview := ""
var _practice_preview := ""
var _practice_drill := "solo"
var _practice_panel_active := false
var _capture_fixture_only := false
var _arena_preview := ""
var _relay_preview := ""
var _feedback_preview := ""
var _feedback_preview_elapsed := 0.0
var _arena_perf_sample := false
var _feedback_perf_sample := false
var _perf_elapsed := 0.0
var _perf_frame_times: Array[float] = []
var _perf_logged := false
var _objective_preview := ""
var _weapon_preview := ""
var _ballistics_preview := ""
var _motion_preview := ""
var _touch_preview := ""
var _rift_link_preview := ""
var _view_fov_preview := -1.0
var _reload_preview := ""
var _hud_preview := ""
var _loadout_preview := ""
var _relay_cue_shown := false
var _presentation_effects: Node3D
var _seen_projectile_fires: Dictionary = {}
var _presented_shot_ids: Dictionary = {}
var _seen_projectile_impacts: Dictionary = {}
var _last_projectile_fire_id := -1
var _last_projectile_impact_id := -1
var _pending_local_primary_predictions := 0
var _reload_was_active := false
var _reload_stage_played := false
var _knife_event_sequence := 0
var _projectile_presentation_pool: Node3D
var _nuke_core_root: Node3D
var _pad_nodes: Dictionary = {}
var _pad_ring_materials: Dictionary = {}
var _pad_base_colors: Dictionary = {}
var _tracer_pool: Array[MeshInstance3D] = []
var _impact_pool: Array[Node3D] = []
var _projectile_tracers: Dictionary = {}
var _tracer_cursor := 0
var _impact_cursor := 0
var _preview_ballistics_bodies: Array[Node] = []

func _ready() -> void:
	_build_network()
	var command_line_lan := network.start_command_line_mode()
	if not network.configuration_valid():
		push_error("Riftline rejected invalid command-line configuration")
		get_tree().quit()
		return
	_read_capture_arguments()
	_dedicated_server = network.is_dedicated_server()
	_presentation_enabled = not _dedicated_server
	if _dedicated_server:
		_build_arena()
		_enter_lan_runtime(true, false)
	else:
		_build_environment()
		_capture_fixture_only = _capture_settings or _capture_hud_layout or _view_fov_preview >= 0.0 or not _reload_preview.is_empty() or not _hud_preview.is_empty() or not _loadout_preview.is_empty() or not _squad_preview.is_empty() or not _arena_preview.is_empty() or not _feedback_preview.is_empty() or not _rift_link_preview.is_empty() or not _practice_preview.is_empty() or not _relay_preview.is_empty() or not _motion_preview.is_empty()
		var show_practice := not command_line_lan and _should_show_practice_panel()
		_build_hud()
		if _capture_settings:
			hud.open_settings()
		elif _capture_hud_layout:
			hud.open_hud_layout()
		_build_first_match_coach()
		_build_rift_link()
		if not _rift_link_preview.is_empty() and rift_link != null:
			hud.set_connection_flow_active(true)
			rift_link.apply_preview(_rift_link_preview)
		if show_practice:
			if not _practice_preview.is_empty():
				# Capture/preview tooling drives the old practice panel
				# directly, unchanged - it screenshots specific drill states.
				_practice_panel_active = true
				_build_practice_panel()
				practice_panel.apply_preview(_practice_preview)
			else:
				_build_main_menu()
				main_menu.show_menu()
		else:
			_build_arena()
			_build_match()
			if command_line_lan:
				_enter_lan_runtime(network.multiplayer.is_server(), false)
			else:
				if _squad_preview.is_empty() and _arena_preview.is_empty() and _feedback_preview.is_empty():
					coach.begin_offline_match()
				else:
					coach.hide()
					if not _touch_preview.is_empty():
						hud.set_touch_preview(_touch_preview)
				if not _arena_preview.is_empty():
					_apply_arena_preview()
				if not _capture_fixture_only:
					director.begin()
			_apply_weapon_preview()
			_apply_ballistics_preview()
			_apply_motion_preview()
			_apply_feedback_preview()
			_apply_contract_previews()
	if not _capture_path.is_empty():
		_capture_after_delay()

func _physics_process(delta: float) -> void:
	if _dedicated_server:
		_tick_dedicated_server(delta)
		return
	if _local_duelist == null:
		return
	_tick_perf_sample(delta)
	_sync_objective_presentation()
	_sync_squad_hud()
	_tick_feedback_preview(delta)
	_tick_death_screen(delta)
	_tick_high_alert(delta)
	if _lan_active:
		_tick_lobby_arming(delta)
		_tick_lan_duel(delta)
		return
	if hud.take_rematch():
		director.take_rematch()
	var wants_reload := hud.take_reload() or Input.is_action_just_pressed("reload")
	var look_delta := hud.take_look_delta()
	_local_duelist.apply_look(look_delta)
	if hud.take_reset_training() and coach != null and not _lan_active:
		coach.reset_training()
	if hud.gyro_enabled:
		var gyroscope := Input.get_gyroscope()
		_local_duelist.apply_look(Vector2(gyroscope.y, -gyroscope.x) * 2.4)
	if not director.is_live() or not hud.can_drive_combat():
		# Non-live beats can still show the arena and accept camera look, but no combat intent survives into the next phase.
		hud.take_jump()
		hud.take_crouch()
		hud.take_prone()
		hud.take_weapon_switch()
		hud.take_melee()
		if _motion_preview.is_empty():
			_local_duelist.set_combat_pose(false, delta)
		_local_duelist.drive(Vector2.ZERO, false, false, delta)
		hud.show_ammo(_local_duelist.magazine_rounds, _local_duelist.reserve_ammo, _local_duelist.reload_remaining)
		hud.show_damage(_local_duelist.health)
		return
	var keyboard := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var movement := hud.movement if hud.movement.length_squared() > 0.001 else keyboard
	if coach != null and not _lan_active:
		coach.observe_movement(movement)
		coach.observe_look(look_delta)
		if hud.fire_held or Input.is_action_pressed("fire"):
			coach.observe_fire()
	if hud.take_crouch():
		_local_duelist.toggle_crouch()
	if hud.take_prone():
		_local_duelist.toggle_prone()
	if hud.take_weapon_switch():
		_local_duelist.switch_weapon()
	if wants_reload:
		_local_duelist.reload_weapon()
	if hud.take_melee() or Input.is_action_just_pressed("melee"):
		_local_duelist.melee_attack()
	director.set_interact(_local_duelist.actor_id, hud.interact_held() or Input.is_action_pressed("interact"))
	_local_duelist.set_combat_pose(hud.aim_held, delta)
	_local_duelist.drive(movement, hud.fire_held or Input.is_action_pressed("fire"), hud.take_jump() or Input.is_action_just_pressed("jump"), delta)
	_tick_authority_ballistics(delta)
	hud.set_stance(_local_duelist.stance)
	hud.set_weapon(_local_duelist.weapon)
	hud.set_ads_state(_local_duelist.ads_progress, _local_duelist.zoom_index)
	hud.set_loadout_slots(_local_duelist.loadout_slots)
	hud.show_ammo(_local_duelist.magazine_rounds, _local_duelist.reserve_ammo, _local_duelist.reload_remaining)
	# Continuous sync, not just on the `damaged` signal - a signal only fires
	# on damage events, so without this a respawn (health silently reset to
	# 100 by Duelist.respawn_at()) left the HUD showing the stale 0 from the
	# killing blow until the player took damage again.
	hud.show_damage(_local_duelist.health)
	_sync_reload_feedback()
	_sync_objective_presentation()
	_sync_squad_hud()

func _unhandled_input(event: InputEvent) -> void:
	if _local_duelist == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_captured = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _mouse_captured:
		_local_duelist.apply_look(event.relative)

func _build_environment() -> void:
	# Realistic look: sky-sourced ambient and reflection (so the NuclearMaterials
	# metal-roughness response reads as metal), ACES tonemapping, soft shadows,
	# and bloom.  Mobile renderer only, so no SSAO/SSIL/SDFGI/SSR/volumetrics.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("335678")
	sky_material.sky_horizon_color = Color("8ba2b8")
	sky_material.sky_curve = 0.14
	sky_material.ground_bottom_color = Color("23262b")
	sky_material.ground_horizon_color = Color("6b6f74")
	sky_material.sun_angle_max = 2.0
	sky_material.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 1.0
	environment.glow_intensity = 0.85
	environment.glow_bloom = 0.12
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.fog_enabled = true
	environment.fog_light_color = Color("8ba2b8")
	environment.fog_density = 0.006
	environment.fog_depth_begin = 20.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.03
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-56, -28, 0)
	key.light_color = Color("fff3e0")
	key.light_energy = 1.4
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.light_angular_distance = 0.6
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-10, 5, 4)
	fill.light_color = Color("78a9c7")
	fill.light_energy = 0.4
	fill.omni_range = 24.0
	add_child(fill)

func _build_arena() -> void:
	arena_map = RiftlineMap.new()
	arena_map.name = "RiftlineMap"
	add_child(arena_map)
	arena_map.configure(RiftlineMap.Id.CONCOURSE, _presentation_enabled)
	if _presentation_enabled:
		_presentation_effects = Node3D.new()
		_presentation_effects.name = "PresentationEffects"
		add_child(_presentation_effects)
		_build_nuke_core_presentation()

func _build_match() -> void:
	director = RiftlineMatch.new()
	add_child(director)
	director.configure(arena_map.launch_pad_positions(), arena_map.core_spawn_position(), _presentation_enabled)
	_add_spawn_points()
	var offline_roster := RiftlineRoster.new()
	offline_roster.configure(maxi(1, _offline_squad_size), false, _offline_squad_size > 1)
	offline_roster.add_host()
	if _offline_squad_size > 1:
		for index in range(1, _offline_squad_size):
			offline_roster.add_bot("offline_actor_%d" % index, Duelist.Team.RED)
		for index in range(_offline_squad_size):
			offline_roster.add_bot("offline_actor_%d" % (_offline_squad_size + index), Duelist.Team.BLUE)
	else:
		offline_roster.add_bot("offline_actor_1", Duelist.Team.BLUE)
	for record in offline_roster.records():
		_ensure_actor(record, str(record.actor_id) == "host", not _capture_fixture_only)

	for duelist in _all_authority_actors():
		if duelist is BotDuelist:
			(duelist as BotDuelist).hold_opening_position(OPENING_HOLD_SECONDS)
	_populate_bot_opponents()

	_ensure_ballistics()
	director.score_changed.connect(_on_score_changed)
	director.phase_changed.connect(_on_phase_changed)
	director.match_finished.connect(_on_match_finished)
	director.objective_changed.connect(_on_objective_changed)
	director.objective_event.connect(_on_objective_event)
	_build_combat_feedback()

func _add_spawn_points() -> void:
	var points := arena_map.spawn_points(Duelist.Team.RED)
	if _offline_squad_size <= 1:
		points = [points[0]]
	for point in points:
		director.add_spawn(Duelist.Team.RED, point)
	points = arena_map.spawn_points(Duelist.Team.BLUE)
	if _offline_squad_size <= 1:
		points = [points[0]]
	for point in points:
		director.add_spawn(Duelist.Team.BLUE, point)

func _populate_bot_opponents() -> void:
	if director == null:
		return
	var red_roster: Array = director.rosters[Duelist.Team.RED]
	var blue_roster: Array = director.rosters[Duelist.Team.BLUE]
	for duelist in _all_authority_actors():
		if duelist is BotDuelist:
			var enemies: Array[Duelist] = []
			var enemy_roster: Array = red_roster if duelist.team == int(Duelist.Team.BLUE) else blue_roster
			for candidate in enemy_roster:
				if candidate is Duelist:
					enemies.append(candidate as Duelist)
			(duelist as BotDuelist).set_opponents(enemies)

func _tick_high_alert(delta: float) -> void:
	if hud == null or _high_alert == null:
		return
	var opponents: Array[Duelist] = []
	for candidate in _all_authority_actors():
		if candidate != _local_duelist and candidate.team != _local_duelist.team:
			opponents.append(candidate)
	for candidate in _all_replica_actors():
		if candidate != _local_duelist and candidate.team != _local_duelist.team and candidate not in opponents:
			opponents.append(candidate)
	var alert: Dictionary = _high_alert.evaluate(delta, _local_duelist, opponents)
	if bool(alert.get("active", false)):
		hud.show_high_alert(Vector2(alert.get("direction", Vector2.DOWN)), float(alert.get("intensity", 1.0)))
	if bool(alert.get("just_triggered", false)) and combat_feedback != null:
		combat_feedback.high_alert_warning()

func _ensure_actor(record: Dictionary, local_controlled: bool, authoritative_collision: bool) -> Duelist:
	var actor_id := str(record.get("actor_id", ""))
	var team_value := int(record.get("team", -1))
	if actor_id.is_empty() or team_value < int(Duelist.Team.RED) or team_value > int(Duelist.Team.BLUE):
		return null
	var authority_registry := not _lan_active or _lan_host or _dedicated_server
	var registry: Dictionary = _authoritative_duelists if authority_registry else _replica_duelists
	var existing: Variant = registry.get(actor_id, null)
	if existing is Duelist and is_instance_valid(existing):
		if existing.team == team_value as Duelist.Team:
			if local_controlled and hud != null:
				existing.set_horizontal_fov(hud.horizontal_fov)
			if local_controlled:
				_local_duelist = existing
				_local_actor_id = actor_id
			return existing
		_remove_actor(actor_id)
	var is_bot := not bool(record.get("human", true)) and not _lan_active
	var duelist: Duelist = BotDuelist.new() if is_bot else Duelist.new()
	duelist.name = "Actor_%s" % actor_id
	var should_render := _presentation_enabled and not _dedicated_server
	duelist.build(team_value as Duelist.Team, local_controlled and should_render, should_render, authoritative_collision)
	# The record carries whatever the pre-game class panel picked for a human
	# actor's own duelist; every other actor (remote players not yet synced,
	# bots) falls back to Frontline/Rifle until its own record/input frame
	# says otherwise.
	var record_class := clampi(int(record.get("player_class", int(Duelist.PlayerClass.FRONTLINE))), int(Duelist.PlayerClass.FRONTLINE), int(Duelist.PlayerClass.SHIELD)) as Duelist.PlayerClass
	var record_primary := RiftWeapons.clamp_weapon(int(record.get("primary_weapon", int(Duelist.Weapon.RIFLE)))) as Duelist.Weapon
	if local_controlled:
		record_class = _pending_player_class
		record_primary = _pending_primary_weapon
	duelist.configure_loadout(record_class, record_primary)
	duelist.set_friendly_presenter(not local_controlled and team_value == int(_local_team))
	var spawn := _spawn_for_actor(team_value as Duelist.Team, registry)
	duelist.position = spawn
	duelist.rotation.y = -PI * 0.5 if team_value == int(Duelist.Team.RED) else PI * 0.5
	duelist.set_actor_id(actor_id)
	if local_controlled and hud != null:
		duelist.set_horizontal_fov(hud.horizontal_fov)
	add_child(duelist)
	registry[actor_id] = duelist
	if director != null and not _capture_fixture_only:
		director.register_duelist(duelist, actor_id)
		if not authority_registry:
			duelist.set_match_active(director.is_live())
	if authoritative_collision:
		duelist.fire_requested.connect(_on_authority_fire_requested)
		if _lan_active:
			duelist.defeated.connect(_on_lan_defeat)
	elif local_controlled:
		duelist.fire_requested.connect(_on_local_fire_requested)
	duelist.melee_strike.connect(_on_melee_strike)
	if local_controlled:
		duelist.damaged.connect(_on_player_damaged)
		_local_duelist = duelist
		_local_actor_id = actor_id
	if not authority_registry and not local_controlled:
		_remote_snapshot_buffers[actor_id] = SNAPSHOT_BUFFER.new()
	return duelist

func _remove_actor(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	if director != null:
		director.unregister_duelist(actor_id)
	for registry in [_authoritative_duelists, _replica_duelists]:
		var candidate: Variant = registry.get(actor_id, null)
		if candidate is Duelist and is_instance_valid(candidate):
			candidate.queue_free()
		registry.erase(actor_id)
	_remote_snapshot_buffers.erase(actor_id)
	_pending_actor_snapshots.erase(actor_id)
	_continuous_inputs.erase(actor_id)
	_edge_queues.erase(actor_id)
	_last_sequences.erase(actor_id)
	if _local_actor_id == actor_id:
		_local_actor_id = ""
		_local_duelist = null

func _actor(actor_id: String) -> Duelist:
	var candidate: Variant = _authoritative_duelists.get(actor_id, null)
	if candidate is Duelist and is_instance_valid(candidate):
		return candidate
	candidate = _replica_duelists.get(actor_id, null)
	return candidate if candidate is Duelist and is_instance_valid(candidate) else null

func _all_authority_actors() -> Array[Duelist]:
	var result: Array[Duelist] = []
	for candidate in _authoritative_duelists.values():
		if candidate is Duelist and is_instance_valid(candidate):
			result.append(candidate)
	return result

func _all_replica_actors() -> Array[Duelist]:
	var result: Array[Duelist] = []
	for candidate in _replica_duelists.values():
		if candidate is Duelist and is_instance_valid(candidate):
			result.append(candidate)
	return result

func _spawn_for_actor(team: Duelist.Team, registry: Dictionary) -> Vector3:
	var points: Array[Vector3] = arena_map.spawn_points(team)
	if _offline_squad_size <= 1:
		points = [points[0]]
	var slot := 0
	for candidate in registry.values():
		if candidate is Duelist and candidate.team == team:
			slot += 1
	return points[posmod(slot, points.size())]

func _preview_actor() -> Duelist:
	for candidate in _all_authority_actors():
		if candidate != _local_duelist:
			return candidate
	return _local_duelist

func _actor_for_team(team: Duelist.Team) -> Duelist:
	for actor in _all_authority_actors():
		if actor.team == team:
			return actor
	for actor in _all_replica_actors():
		if actor.team == team:
			return actor
	return _local_duelist

func _sync_roster_records(records: Variant) -> void:
	var now_msec := Time.get_ticks_msec()
	for pending_actor_id in _pending_actor_snapshots.keys().duplicate():
		var pending_snapshot: Dictionary = _pending_actor_snapshots[pending_actor_id]
		if now_msec - int(pending_snapshot.get("arrival", now_msec)) > 1000:
			_pending_actor_snapshots.erase(pending_actor_id)
	var desired := {}
	var entries: Array = records if records is Array else []
	for raw_record in entries:
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = raw_record
		var actor_id := str(record.get("actor_id", ""))
		if actor_id.is_empty():
			continue
		desired[actor_id] = true
		var is_local := actor_id == _local_actor_id
		_ensure_actor(record, is_local, _lan_host or _dedicated_server or is_local)
	for actor_id in _authoritative_duelists.keys().duplicate():
		if not desired.has(actor_id):
			_remove_actor(actor_id)
	for actor_id in _replica_duelists.keys().duplicate():
		if not desired.has(actor_id):
			_remove_actor(actor_id)
	_sync_squad_hud()
	for actor_id in _pending_actor_snapshots.keys().duplicate():
		if _actor(str(actor_id)) != null:
			var pending: Dictionary = _pending_actor_snapshots[actor_id]
			_update_remote_snapshot(str(actor_id), pending.get("state", {}), int(pending.get("tick", -1)))
			_pending_actor_snapshots.erase(actor_id)

func _authority_records() -> Array[Dictionary]:
	if network != null and network.roster != null:
		return network.roster.records()
	return []

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = DuelHud.new()
	layer.add_child(hud)
	hud.rift_link_requested.connect(_on_rift_link_requested)
	hud.main_menu_requested.connect(_on_rift_link_cancelled)
	hud.feedback_preferences_changed.connect(_on_feedback_preferences_changed)
	hud.view_fov_changed.connect(_on_view_fov_changed)
	_build_combat_feedback()

func _build_combat_feedback() -> void:
	if not _presentation_enabled:
		return
	if combat_feedback == null:
		combat_feedback = RiftlineCombatFeedback.new()
		combat_feedback.name = "RiftlineCombatFeedback"
		add_child(combat_feedback)
		combat_feedback.damage_feedback.connect(_on_feedback_damage)
		combat_feedback.hit_confirm_feedback.connect(_on_feedback_hit_confirm)
	if not combat_feedback.objective_feedback.is_connected(_on_feedback_objective):
		combat_feedback.objective_feedback.connect(_on_feedback_objective)
	var listener := _local_duelist.camera if _local_duelist != null else null
	combat_feedback.configure(true, _local_actor_id, listener)
	if hud != null:
		combat_feedback.set_preferences(hud.effects_enabled, hud.haptics_enabled)

func _build_first_match_coach() -> void:
	coach = RiftlineFirstMatchCoach.new()
	coach.cue_changed.connect(hud.set_coach_cue)

func _build_network() -> void:
	network = RiftlineNetwork.new()
	add_child(network)
	network.session_status.connect(_on_network_status)
	network.host_discovered.connect(_on_host_discovered)
	network.peer_joined.connect(_on_network_peer_joined)
	network.peer_left.connect(_on_network_peer_left)
	network.input_received.connect(_on_network_input)
	network.snapshot_received.connect(_on_network_snapshot)
	network.reliable_event_received.connect(_on_network_event)
	network.team_assigned.connect(_on_team_assigned)
	network.actor_assigned.connect(_on_actor_assigned)
	network.roster_received.connect(_on_roster_received)
	network.session_descriptor_received.connect(_on_session_descriptor)
	network.lobby_state_received.connect(_on_lobby_state_received)
	network.lobby_live_received.connect(_on_lobby_live_received)
	network.lobby_abandoned_received.connect(_on_lobby_abandoned_received)

func _build_rift_link() -> void:

	var layer := CanvasLayer.new()
	add_child(layer)
	rift_link = RiftLinkPanel.new()
	layer.add_child(rift_link)
	rift_link.set_squad_mode(_offline_squad_size > 1 or network.team_size > 1)
	rift_link.host_requested.connect(_on_host_requested)
	rift_link.join_requested.connect(_on_join_requested)
	rift_link.cancel_requested.connect(_on_rift_link_cancelled)
	rift_link.retry_requested.connect(_on_join_retry_requested)
	rift_link.ready_requested.connect(_on_lobby_ready_requested)
	rift_link.rematch_requested.connect(_on_lobby_rematch_requested)

func _build_practice_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	practice_panel = PRACTICE_PANEL.new()
	layer.add_child(practice_panel)
	practice_panel.drill_requested.connect(_on_practice_drill_requested)
	practice_panel.local_rift_requested.connect(_on_practice_local_rift_requested)

func _build_main_menu() -> void:
	if main_menu != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	main_menu = MAIN_MENU.new()
	layer.add_child(main_menu)
	main_menu.create_game_requested.connect(_on_main_menu_create)
	main_menu.join_game_requested.connect(_on_main_menu_join)
	main_menu.drill_requested.connect(_on_main_menu_drill)

func _build_class_panel() -> void:
	if class_panel != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 22
	add_child(layer)
	class_panel = CLASS_PANEL.new()
	layer.add_child(class_panel)
	class_panel.visible = false
	class_panel.selection_changed.connect(_on_class_panel_selection_changed)
	class_panel.confirmed.connect(_on_class_panel_confirmed)
	class_panel.cancelled.connect(_on_class_panel_cancelled)

func _on_main_menu_create() -> void:
	_open_class_panel("create", "CHOOSE YOUR CLASS", "HOST GAME", true)

func _on_main_menu_join() -> void:
	_open_class_panel("join", "CHOOSE YOUR CLASS", "FIND GAME", true)

func _on_main_menu_drill() -> void:
	_open_class_panel("drill", "CHOOSE YOUR CLASS", "ENTER DRILL", true)

func _open_class_panel(context: String, title: String, cta_label: String, show_cancel: bool) -> void:
	_class_panel_context = context
	_build_class_panel()
	class_panel.configure(title, cta_label, show_cancel, _pending_player_class, _pending_primary_weapon)
	class_panel.visible = true

func _on_class_panel_selection_changed(player_class: int, primary_weapon: int) -> void:
	_pending_player_class = player_class as Duelist.PlayerClass
	_pending_primary_weapon = primary_weapon as Duelist.Weapon
	# On the death screen the pick takes effect immediately - the duelist is
	# eliminated and not rendering combat, so this is safe, and it means the
	# loadout is already correct by the time the respawn actually happens.
	if _class_panel_context == "death" and _local_duelist != null:
		_apply_pending_class_to_local_duelist()

func _apply_pending_class_to_local_duelist() -> void:
	if _local_duelist == null:
		return
	if _local_duelist.player_class != _pending_player_class or (_pending_player_class == Duelist.PlayerClass.FRONTLINE and int(_local_duelist.loadout_slots[0]) != int(_pending_primary_weapon)):
		_local_duelist.configure_loadout(_pending_player_class, _pending_primary_weapon)

func _on_class_panel_cancelled() -> void:
	class_panel.visible = false
	_class_panel_context = ""
	if main_menu != null:
		main_menu.show_menu()

func _on_class_panel_confirmed() -> void:
	var context := _class_panel_context
	match context:
		"create", "join", "drill":
			class_panel.visible = false
			_class_panel_context = ""
			_execute_pending_menu_action(context)
		"death":
			_request_local_respawn()

func _execute_pending_menu_action(action: String) -> void:
	match action:
		"create":
			_on_host_requested()
		"join":
			_on_join_requested()
		"drill":
			_start_practice_drill("full")

## The death screen: shown whenever the local player's own duelist becomes
## eliminated, hidden the moment they're alive again. Reuses the same
## RiftlineClassPanel as the pre-game picker, with the CTA repurposed as the
## respawn button and gated by RiftlineMatch.can_respawn() (or, for a
## non-host LAN client, the locally-mirrored countdown - see
## _local_death_elapsed).
func _tick_death_screen(delta: float) -> void:
	if _local_duelist == null:
		return
	var eliminated := _local_duelist.eliminated
	if eliminated and not _local_was_eliminated:
		_local_death_elapsed = 0.0
		_pending_player_class = _local_duelist.player_class
		_pending_primary_weapon = _local_duelist.loadout_slots[0] as Duelist.Weapon if not _local_duelist.loadout_slots.is_empty() else Duelist.Weapon.RIFLE
		_open_class_panel("death", "YOU WERE ELIMINATED", "RESPAWN", false)
	elif not eliminated and _local_was_eliminated:
		if class_panel != null and _class_panel_context == "death":
			class_panel.visible = false
			_class_panel_context = ""
		_pending_respawn_request = false
	_local_was_eliminated = eliminated
	if not eliminated or class_panel == null or _class_panel_context != "death":
		return
	_local_death_elapsed += delta
	var remaining := 0.0
	var eligible := false
	if _lan_active and not _lan_host:
		remaining = maxf(0.0, RiftlineMatch.RESPAWN_MIN_SECONDS - _local_death_elapsed)
		eligible = remaining <= 0.0
	elif director != null:
		remaining = director.respawn_seconds_remaining(_local_actor_id)
		eligible = director.can_respawn(_local_actor_id)
	class_panel.set_cta_state(eligible, "" if eligible else "Available in %ds" % int(ceil(remaining)))

func _request_local_respawn() -> void:
	if _local_duelist == null or not _local_duelist.eliminated:
		return
	if _lan_active and not _lan_host:
		_pending_respawn_request = true
		return
	if director != null:
		director.request_respawn(_local_actor_id)

## Host-side application of a remote peer's death-screen state, carried in
## the same per-tick continuous input every other combat field rides in.
## request_respawn() is itself idempotent/self-guarding (it's a no-op once
## the actor is alive again), so re-processing the same "respawn": true
## value on every subsequent tick is harmless.
func _apply_remote_respawn_and_class(actor_id: String, target: Duelist, continuous: Dictionary) -> void:
	var requested_class := clampi(int(continuous.get("class_id", int(Duelist.PlayerClass.FRONTLINE))), int(Duelist.PlayerClass.FRONTLINE), int(Duelist.PlayerClass.SHIELD)) as Duelist.PlayerClass
	var requested_primary := RiftWeapons.clamp_weapon(int(continuous.get("primary_weapon", int(Duelist.Weapon.RIFLE)))) as Duelist.Weapon
	if target.player_class != requested_class or (requested_class == Duelist.PlayerClass.FRONTLINE and (target.loadout_slots.is_empty() or int(target.loadout_slots[0]) != int(requested_primary))):
		target.configure_loadout(requested_class, requested_primary)
	if bool(continuous.get("respawn", false)) and director != null:
		director.request_respawn(actor_id)

func _should_show_practice_panel() -> bool:
	if not _practice_preview.is_empty():
		return true
	if not _capture_path.is_empty() or _offline_squad_size > 1:
		return false
	return _squad_preview.is_empty() and _arena_preview.is_empty() and _feedback_preview.is_empty() and _rift_link_preview.is_empty() and _objective_preview.is_empty() and _weapon_preview.is_empty() and _ballistics_preview.is_empty() and _motion_preview.is_empty() and _touch_preview.is_empty() and _relay_preview.is_empty() and _view_fov_preview < 0.0 and _reload_preview.is_empty() and _hud_preview.is_empty() and _loadout_preview.is_empty()

func _load_practice_drill() -> String:
	var config := ConfigFile.new()
	if config.load("user://riftline_practice.cfg") == OK:
		var stored := str(config.get_value("practice", "last_drill", "solo"))
		if stored in ["solo", "wing", "full"]:
			return stored
	return "solo"

func _save_practice_drill(drill: String) -> void:
	var config := ConfigFile.new()
	config.set_value("practice", "version", 1)
	config.set_value("practice", "last_drill", drill)
	config.save("user://riftline_practice.cfg")

func _on_practice_drill_requested(drill: String) -> void:
	_start_practice_drill(drill)

func _on_practice_local_rift_requested() -> void:
	if hud != null:
		hud.set_connection_flow_active(true)
	if rift_link != null:
		rift_link.open_menu()

## Single funnel for offline team size so no caller can ask the roster for more
## players than it will accept. Nuclear Rush is 4v4, so 4 is the ceiling.
func _set_offline_squad_size(value: int) -> void:
	_offline_squad_size = clampi(value, RiftlineRoster.MIN_TEAM_SIZE, RiftlineRoster.MAX_TEAM_SIZE)

func _start_practice_drill(drill: String) -> void:
	if drill not in ["solo", "wing", "full"]:
		drill = "solo"
	_practice_drill = drill
	# "full" is the real 4v4. Never exceed RiftlineRoster.MAX_TEAM_SIZE, or
	# roster.configure() rejects the size and the match never builds a roster.
	_set_offline_squad_size(int({"solo": 1, "wing": 3, "full": 4}.get(drill, 1)))
	_save_practice_drill(drill)
	_practice_panel_active = false
	if practice_panel != null:
		practice_panel.visible = false
	_build_arena()
	_build_match()
	if coach != null:
		if drill == "solo" and _practice_preview.is_empty():
			coach.begin_offline_match()
		else:
			coach.hide()
	if director != null:
		director.begin()
	if hud != null:
		hud.set_connection_flow_active(false)
		if drill == "wing":
			hud.show_practice_cue("TAKE THE RELAY")
		elif drill == "full":
			hud.show_practice_cue("SCREEN THE CARRIER")

func _on_player_damaged(_amount: float, remaining: float, attacker_id: String, source_position: Vector3, enemy_team: int) -> void:
	if hud != null:
		hud.show_damage(remaining)
	if combat_feedback != null:
		combat_feedback.set_local_health(remaining)
		combat_feedback.local_damage_received(source_position if not attacker_id.is_empty() else null, enemy_team, _local_duelist.global_position if _local_duelist != null else Vector3.ZERO)

func _on_feedback_damage(direction: Vector2, intensity: float, enemy_team: int) -> void:
	if hud != null:
		hud.show_damage_direction(direction, intensity, enemy_team)

func _on_feedback_hit_confirm() -> void:
	if hud != null:
		hud.show_hit_confirm()

func _on_feedback_objective(event_type: String, scoring_team: int) -> void:
	if hud != null:
		hud.show_objective_feedback(event_type, scoring_team)

func _on_feedback_preferences_changed(effects_enabled: bool, haptics_enabled: bool) -> void:
	if combat_feedback != null:
		combat_feedback.set_preferences(effects_enabled, haptics_enabled)

func _on_score_changed(red: int, blue_score: int) -> void:
	if hud != null:
		hud.set_score(red, blue_score)
	if _lan_host:
		network.publish_event({"type": "score", "red": red, "blue": blue_score})

func _on_objective_changed(state: Dictionary) -> void:
	if hud != null:
		hud.set_objective_state(state)
	_update_use_control(state)
	_push_bot_objective_context(state)

func _on_objective_event(event_type: String, state: Dictionary) -> void:
	if hud != null:
		hud.show_objective_event(event_type, state)
	if combat_feedback != null:
		var local_event := str(state.get("core_carrier_id", "")) == _local_actor_id
		combat_feedback.objective_event(event_type, state, local_event)
	if _lan_host:
		network.publish_event({"type": event_type, "state": state})

# The interact button (install/cancel) is available only when it would do something:
# the carrier standing on their own pad, or a living defender standing on the
# enemy's installed pad.
func _update_use_control(state: Dictionary) -> void:
	if hud == null:
		return
	hud.set_interact_available(_can_interact(state))

func _can_interact(state: Dictionary) -> bool:
	if _local_duelist == null or arena_map == null or _local_duelist.eliminated:
		return false
	var pads: Dictionary = arena_map.launch_pad_positions()
	var core_state := int(state.get("core_state", int(RiftlineMatch.CoreState.AT_CENTER)))
	if core_state == int(RiftlineMatch.CoreState.CARRIED) and str(state.get("core_carrier_id", "")) == _local_duelist.actor_id:
		var own_pad: Vector3 = pads.get(_local_duelist.team, Vector3.ZERO)
		return _local_duelist.global_position.distance_to(own_pad) <= RiftlineMatch.CORE_INSTALL_RADIUS
	if core_state == int(RiftlineMatch.CoreState.INSTALLED):
		var installed_team := int(state.get("installed_team", -1))
		if installed_team != int(_local_duelist.team):
			var enemy_pad: Vector3 = pads.get(installed_team, Vector3.ZERO)
			return _local_duelist.global_position.distance_to(enemy_pad) <= RiftlineMatch.LAUNCH_CANCEL_RADIUS
	return false

# Objective awareness for bots: Nuclear Rush rules live only in RiftlineMatch,
# this just forwards the replicated state so bot_duelist.gd can react.
func _push_bot_objective_context(state: Dictionary) -> void:
	if arena_map == null:
		return
	var pads: Dictionary = arena_map.launch_pad_positions()
	for duelist in _all_authority_actors():
		if not (duelist is BotDuelist):
			continue
		var enemy_team := Duelist.Team.BLUE if duelist.team == Duelist.Team.RED else Duelist.Team.RED
		(duelist as BotDuelist).set_objective_context({
			"core_state": int(state.get("core_state", int(RiftlineMatch.CoreState.AT_CENTER))),
			"core_position": state.get("core_position", Vector3.ZERO) as Vector3,
			"core_carrier_id": str(state.get("core_carrier_id", "")),
			"core_carrier_team": int(state.get("core_carrier_team", int(Duelist.Team.RED))),
			"installed_team": int(state.get("installed_team", int(Duelist.Team.RED))),
			"own_pad": pads.get(duelist.team, Vector3.ZERO) as Vector3,
			"enemy_pad": pads.get(enemy_team, Vector3.ZERO) as Vector3,
		})

func _on_match_finished(winner: Duelist.Team) -> void:
	_clear_ballistics()
	_clear_presentation_effects()
	if combat_feedback != null:
		combat_feedback.stop_all()
	if hud != null:
		hud.show_match_result(winner)
	if _lan_host:
		_authority_match_started = false
		network.publish_event({"type": "finished", "winner": int(winner)})
		network.publish_lobby_finished()

func _on_phase_changed(phase: RiftlineMatch.Phase) -> void:
	if phase != RiftlineMatch.Phase.LIVE:
		_clear_ballistics()
		_clear_presentation_effects()
		if combat_feedback != null:
			combat_feedback.stop_all()
	_lan_phase = phase
	if phase != RiftlineMatch.Phase.LIVE:
		_continuous_inputs.clear()
		_edge_queues.clear()
	if hud != null:
		hud.set_match_phase(phase)
		hud.set_combat_input_enabled(phase == RiftlineMatch.Phase.LIVE)
	if _lan_host:
		network.publish_event({"type": "phase", "phase": int(phase)})

func _ensure_ballistics() -> void:
	if ballistics != null:
		return
	ballistics = RiftBallistics.new()
	ballistics.name = "RiftBallistics"
	add_child(ballistics)
	ballistics.projectile_fired.connect(_on_projectile_fired)
	ballistics.projectile_impacted.connect(_on_projectile_impacted)
	_build_projectile_presentation_pool()

func _tick_authority_ballistics(delta: float) -> void:
	if ballistics == null or director == null or not director.is_live():
		return
	ballistics.tick_authority(delta)

func _clear_ballistics() -> void:
	if ballistics != null:
		ballistics.clear()
	_pending_local_primary_predictions = 0
	for tracer in _tracer_pool:
		if is_instance_valid(tracer):
			tracer.set_meta("token", int(tracer.get_meta("token", 0)) + 1)
			tracer.visible = false
	for impact in _impact_pool:
		if is_instance_valid(impact):
			impact.set_meta("token", int(impact.get_meta("token", 0)) + 1)
			impact.visible = false

func _on_authority_fire_requested(shooter: Duelist, fired_weapon: Duelist.Weapon, _origin: Vector3, _direction: Vector3) -> void:
	if ballistics != null:
		ballistics.fire(shooter, fired_weapon)

func _on_local_fire_requested(shooter: Duelist, fired_weapon: Duelist.Weapon, origin: Vector3, _direction: Vector3) -> void:
	if not _presentation_enabled:
		return
	# Joining clients predict only local presentation.  Combat remains authority-owned.
	# One fire_requested emission covers the whole shot even for a multi-pellet
	# shotgun blast (Duelist emits it once per trigger pull, not per pellet).
	_pending_local_primary_predictions = mini(_pending_local_primary_predictions + 1, 8)
	_play_shooter_fire(_local_team, fired_weapon)
	if combat_feedback != null:
		combat_feedback.weapon_fired(_local_actor_id, fired_weapon, origin, true)
	if hud != null:
		hud.show_primary_fire_feedback(shooter.last_shot_was_hip_followup)

func _sync_reload_feedback() -> void:
	if _local_duelist == null or combat_feedback == null:
		return
	var active := _local_duelist.reload_remaining > 0.0
	var reload_seconds: float = RiftWeapons.row(int(_local_duelist.weapon)).reload_seconds
	if active and not _reload_was_active:
		_reload_stage_played = false
		combat_feedback.reload_started(true)
	elif active and not _reload_stage_played and _local_duelist.reload_remaining <= reload_seconds * 0.5:
		_reload_stage_played = true
		combat_feedback.reload_stage(true)
	elif _reload_was_active and not active:
		combat_feedback.reload_completed(true)
	_reload_was_active = active

func _on_projectile_fired(fact: Dictionary) -> void:
	var projectile_id := int(fact.get("id", -1))
	var projectile_key := "%s:%d" % [str(fact.get("session_id", "legacy")), projectile_id]
	if projectile_id < 0 or _seen_projectile_fires.has(projectile_key):
		return
	_last_projectile_fire_id = maxi(_last_projectile_fire_id, projectile_id)
	_seen_projectile_fires[projectile_key] = Time.get_ticks_msec()
	_trim_projectile_cache(_seen_projectile_fires)
	var shooter_id := str(fact.get("shooter_id", ""))
	var fired_weapon := RiftWeapons.clamp_weapon(int(fact.get("weapon", 0))) as Duelist.Weapon
	# A shotgun shot spawns several pellets, each its own projectile_fired
	# fact sharing one shot_id - dedupe the *presentation* (audio/HUD kick) on
	# shot_id so it plays exactly once per trigger pull, while still spawning
	# a tracer per pellet below for the visual spread.
	var shot_key := "%s:%s:%d" % [str(fact.get("session_id", "legacy")), shooter_id, int(fact.get("shot_id", projectile_id))]
	var shot_already_presented := _presented_shot_ids.has(shot_key)
	_presented_shot_ids[shot_key] = Time.get_ticks_msec()
	_trim_projectile_cache(_presented_shot_ids)
	var local_prediction := _local_duelist != null and shooter_id == _local_duelist.actor_id and _pending_local_primary_predictions > 0
	if local_prediction and int(fact.get("pellet_index", 0)) == 0:
		_pending_local_primary_predictions -= 1
	if _presentation_enabled:
		if not local_prediction and not shot_already_presented:
			_play_shooter_fire_by_id(shooter_id, fired_weapon)
			if combat_feedback != null:
				combat_feedback.weapon_fired(shooter_id, fired_weapon, fact.get("origin", Vector3.ZERO), shooter_id == _local_actor_id)
			if _local_duelist != null and shooter_id == _local_duelist.actor_id and hud != null:
				hud.show_primary_fire_feedback(bool(fact.get("hip_burst_followup", false)))
		_spawn_projectile_tracer(fact)
	if _lan_host:
		network.publish_event(fact)

func _on_projectile_impacted(fact: Dictionary) -> void:
	var projectile_id := int(fact.get("id", -1))
	var projectile_key := "%s:%d" % [str(fact.get("session_id", "legacy")), projectile_id]
	if projectile_id < 0 or _seen_projectile_impacts.has(projectile_key):
		return
	_last_projectile_impact_id = maxi(_last_projectile_impact_id, projectile_id)
	_seen_projectile_impacts[projectile_key] = Time.get_ticks_msec()
	_trim_projectile_cache(_seen_projectile_impacts)
	_cancel_projectile_tracer(fact)
	if _presentation_enabled:
		var team := int(fact.get("team", int(Duelist.Team.RED))) as Duelist.Team
		_spawn_projectile_impact(fact.get("position", Vector3.ZERO), fact.get("normal", Vector3.UP), team, bool(fact.get("hit_duelist", false)))
		if bool(fact.get("obstructed", false)):
			_play_shooter_obstruction(str(fact.get("shooter_id", "")))
		if combat_feedback != null:
			combat_feedback.projectile_impacted(fact, _local_duelist.global_position if _local_duelist != null else Vector3.ZERO)
	if _lan_host:
		network.publish_event(fact)

func _trim_projectile_cache(cache: Dictionary) -> void:
	while cache.size() > 128:
		cache.erase(cache.keys()[0])

func _on_melee_strike(shooter_id: String, melee_weapon: Duelist.Weapon, origin: Vector3, end: Vector3, team: Duelist.Team, hit_target: bool, target_id: String) -> void:
	_knife_event_sequence += 1
	var event_id := "%s:%d" % [shooter_id, _knife_event_sequence]
	if _presentation_enabled:
		_show_melee_strike(shooter_id, melee_weapon, origin, end, team, hit_target)
		if combat_feedback != null:
			combat_feedback.melee_struck(shooter_id, melee_weapon, origin, end, team, shooter_id == _local_actor_id, hit_target, target_id, origin, event_id, _local_duelist.global_position if _local_duelist != null else Vector3.ZERO)
	if _lan_host:
		network.publish_event({"type": "melee_strike", "shooter_id": shooter_id, "weapon": int(melee_weapon), "origin": origin, "end": end, "team": int(team), "hit": hit_target, "target_id": target_id, "event_id": event_id})

func _show_melee_strike(shooter_id: String, melee_weapon: Duelist.Weapon, origin: Vector3, end: Vector3, team: Duelist.Team, hit_target: bool) -> void:
	if not _presentation_enabled:
		return
	var target := _actor(shooter_id)
	if target != null:
		# A swing lunge, not a muzzle flash - melee has no fire/recoil presentation.
		target.play_local_melee_swing()
	var accent := Color("ff6a57") if team == Duelist.Team.RED else Color("75dbff")
	_spawn_beam(origin, end, accent.lerp(Color("f4e3ff"), 0.35), 0.024, 0.07)
	_spawn_impact(end, accent, 0.12 if hit_target else 0.08, 0.1)

func _on_rift_link_requested() -> void:
	hud.set_connection_flow_active(true)
	rift_link.open_menu()

func _on_host_requested() -> void:
	_join_discovery_started = false
	rift_link.show_host()
	var error := network.host_lan()
	if error != OK:
		rift_link.set_status("LINK ERROR")
		return
	_enter_lan_runtime(true, true)

func _on_join_requested() -> void:
	hud.set_connection_flow_active(true)
	if not _join_discovery_started:
		_join_discovery_started = true
		rift_link.show_join()
		network.begin_lan_discovery()
		return
	var error := network.join_discovered_host()
	if error != OK:
		rift_link.set_status("NO RIFT FOUND")
	else:
		_enter_lan_runtime(false, true)
		rift_link.set_status("LINKING")

func _on_join_retry_requested() -> void:
	_join_discovery_started = true
	rift_link.show_join()
	rift_link.show_join()
	network.begin_lan_discovery()

func _on_rift_link_cancelled() -> void:
	_join_discovery_started = false
	if _lan_active and not _lan_host:
		network.submit_client_lobby_leave()
	_restore_offline_training("RIFT CLOSED")

func _on_network_status(status: String) -> void:
	if rift_link != null and rift_link.visible:
		rift_link.set_status(status)
	if status in ["LINK LOST", "LINK FAILED"] and _lan_active and not _dedicated_server:
		_show_severed_state("RIFT SEVERED")

func _on_host_discovered(session: Dictionary) -> void:
	_join_discovery_started = true
	if rift_link != null and rift_link.visible:
		rift_link.set_squad_mode(str(session.get("mode", "duel")) == "squad")
		rift_link.set_discovered_session(true)

func _on_network_peer_joined(peer_id: int) -> void:
	if not _lan_active:
		return
	if not _lan_host:
		_lan_peer_ready = false
		return
	var actor_id := network.peer_actor_id(peer_id)
	if actor_id.is_empty():
		return
	_actor_for_peer[peer_id] = actor_id
	_continuous_inputs[actor_id] = {}
	_edge_queues[actor_id] = []
	_last_sequences[actor_id] = -1
	if _lan_host:
		_sync_roster_records(_authority_records())


func _on_network_peer_left(peer_id: int) -> void:
	_clear_ballistics()
	var actor_id := str(_actor_for_peer.get(peer_id, network.peer_actor_id(peer_id)))
	_actor_for_peer.erase(peer_id)
	if not actor_id.is_empty():
		_remove_actor(actor_id)
	if _dedicated_server:
		_authority_match_started = false
		_ready_peers.erase(peer_id)
		_continuous_inputs.erase(actor_id)
		_edge_queues.erase(actor_id)
		_last_sequences.erase(actor_id)
		if director != null:
			_sync_roster_records(_authority_records())
		return
	if _lan_active and not _lan_host:
		_restore_offline_training("LINK LOST")

func _on_network_input(peer_id: int, frame: Dictionary) -> void:
	if not _lan_active or not _lan_host or director == null or not director.is_live():
		return
	var actor_id := str(_actor_for_peer.get(peer_id, network.peer_actor_id(peer_id)))
	if actor_id.is_empty() or _actor(actor_id) == null:
		return
	_continuous_inputs[actor_id] = _continuous_input(frame)
	var edges: Array = _edge_queues.get(actor_id, [])
	edges.append(_discrete_input(frame))
	_edge_queues[actor_id] = edges
	_last_sequences[actor_id] = int(frame.get("sequence", -1))

func _on_network_snapshot(snapshot: Dictionary) -> void:
	if not _lan_active or _lan_host or not _session_ready_for_snapshots or snapshot.is_empty():
		return
	if director != null:
		var replica_match: Dictionary = snapshot.get("match", snapshot).duplicate(true)
		replica_match["tick"] = int(snapshot.get("tick", -1))
		director.apply_replica_state(replica_match)
	var players: Dictionary = snapshot.get("players", {})
	var local_state: Dictionary = players.get(_local_actor_id, {})
	if not local_state.is_empty():
		var acknowledged := int(local_state.get("last_input", -1))
		var remaining: Array[Dictionary] = []
		for frame in _pending_inputs:
			if int(frame.get("sequence", -1)) > acknowledged:
				remaining.append(frame)
		_pending_inputs = remaining
		if _local_duelist != null:
			_local_duelist.reconcile_from_authority(local_state, _pending_inputs, 1.0 / 60.0)
	for actor_id in players.keys():
		if str(actor_id) == _local_actor_id:
			continue
		var remote_state: Dictionary = players[actor_id]
		if _actor(str(actor_id)) == null:
			_pending_actor_snapshots[str(actor_id)] = {"state": remote_state.duplicate(true), "tick": int(snapshot.get("tick", -1)), "arrival": Time.get_ticks_msec()}
		else:
			_update_remote_snapshot(str(actor_id), remote_state, int(snapshot.get("tick", -1)))
	if hud != null:
		var match_state: Dictionary = snapshot.get("match", snapshot)
		hud.set_score(int(match_state.get("red_score", 0)), int(match_state.get("blue_score", 0)))
	_sync_squad_hud()

func _on_network_event(event: Dictionary, sender_id: int) -> void:
	if event.is_empty():
		return
	var event_type := str(event.get("type", ""))
	if event_type in ["lobby_state", "lobby_live", "lobby_abandoned"]:
		var state: Dictionary = event.get("state", {})
		if not state.is_empty():
			_apply_lobby_state(state)
		if event_type == "lobby_state" and int(state.get("phase", -1)) == RiftlineLobby.Phase.ARMING and _lan_host:
			_begin_lobby_launch()
		elif event_type == "lobby_live":
			_on_lobby_live_state(state)
		elif event_type == "lobby_abandoned":
			if _dedicated_server:
				_clear_match_nodes()
				_authority_match_started = false
				_replace_match_for_lan(true)
			else:
				_show_severed_state(str(state.get("reason", "RIFT SEVERED")))
		return
	if _lan_host:
		return
	match event_type:
		"session":
			_on_session_descriptor({"team_size": int(event.get("team_size", 1))})
		"phase":
			_apply_client_phase(int(event.get("phase", int(RiftlineMatch.Phase.OPENING))))
		"score":
			if hud != null:
				hud.set_score(int(event.get("red", 0)), int(event.get("blue", 0)))
		"finished":
			_clear_ballistics()
			if hud != null:
				hud.show_match_result(int(event.get("winner", int(Duelist.Team.RED))) as Duelist.Team)
		"defeat":
			_apply_client_defeat(str(event.get("victim_id", "")))
		"projectile_fired":
			_on_projectile_fired(event)
		"projectile_impacted":
			_on_projectile_impacted(event)
		"melee_strike":
			var shot_id := str(event.get("shooter_id", ""))
			var shot_weapon := RiftWeapons.clamp_weapon(int(event.get("weapon", 0))) as Duelist.Weapon
			var shot_origin: Vector3 = event.get("origin", Vector3.ZERO)
			var shot_end: Vector3 = event.get("end", Vector3.ZERO)
			var shot_team := int(event.get("team", int(Duelist.Team.RED))) as Duelist.Team
			var shot_hit := bool(event.get("hit", false))
			var shot_target_id := str(event.get("target_id", ""))
			var shot_event_id := str(event.get("event_id", ""))
			_show_melee_strike(shot_id, shot_weapon, shot_origin, shot_end, shot_team, shot_hit)
			if combat_feedback != null:
				combat_feedback.melee_struck(shot_id, shot_weapon, shot_origin, shot_end, shot_team, shot_id == _local_actor_id, shot_hit, shot_target_id, shot_origin, shot_event_id, _local_duelist.global_position if _local_duelist != null else Vector3.ZERO)
		"spawn":
			_apply_client_spawn(str(event.get("actor_id", "")), event.get("position", null), float(event.get("yaw", 0.0)))
		"roster":
			_sync_roster_records(event.get("records", []))
		"core_picked_up", "core_dropped", "core_returned", "core_installed", "launch_cancelled", "launch_complete":
			var objective_event_state: Dictionary = event.get("state", {})
			_on_objective_event(str(event.get("type", "")), objective_event_state)

func _enter_lan_runtime(host: bool, from_player_flow: bool) -> void:
	if _lan_active:
		return
	if coach != null:
		coach.hide()
	_lan_active = true
	_lan_host = host
	_dedicated_server = network.is_dedicated_server()
	_lan_phase = RiftlineMatch.Phase.OPENING
	_lan_tick = 0
	_local_input_sequence = 0
	_pending_inputs.clear()
	_pending_actor_snapshots.clear()
	_clear_ballistics()
	_continuous_inputs.clear()
	_edge_queues.clear()
	_last_sequences.clear()
	_actor_for_peer.clear()
	_ready_peers.clear()
	_authority_match_started = false
	_lobby_arming_remaining = 0.0
	_session_ready_for_snapshots = host or _dedicated_server
	_local_actor_id = network.local_actor_id
	_local_team = network.local_team as Duelist.Team if network.local_team >= 0 else Duelist.Team.RED
	if rift_link != null:
		rift_link.set_local_actor(_local_actor_id, host)
	_replace_match_for_lan(host)
	if rift_link != null and not network.lobby_state.is_empty():
		rift_link.set_lobby_state(network.lobby_state)
	if hud != null:
		hud.set_connection_flow_active(false if not from_player_flow else true)
	if from_player_flow:
		# The panel remains up until the second human is ready, so the arena cannot consume stale touches.
		if hud != null:
			hud.set_combat_input_enabled(false)

func _on_session_descriptor(descriptor: Dictionary) -> void:
	if descriptor.is_empty() or not _lan_active or _lan_host or _dedicated_server:
		return
	# There is exactly one map and one mode, so a partial or stale descriptor
	# never needs to disagree about either - only team_size is negotiated.
	_session_ready_for_snapshots = false
	if network != null:
		network.team_size = clampi(int(descriptor.get("team_size", network.team_size)), RiftlineRoster.MIN_TEAM_SIZE, RiftlineRoster.MAX_TEAM_SIZE)
	_replace_match_for_lan(false)
	_session_ready_for_snapshots = true

func _replace_match_for_lan(host: bool) -> void:
	_clear_match_nodes()
	if host:
		_ensure_ballistics()
	elif ballistics != null:
		ballistics.queue_free()
		ballistics = null
	director = RiftlineMatch.new()
	add_child(director)
	if arena_map == null:
		_build_arena()
	director.configure(arena_map.launch_pad_positions(), arena_map.core_spawn_position(), _presentation_enabled)
	var team_points := arena_map.spawn_points(Duelist.Team.RED)
	if network.team_size <= 1:
		team_points = [team_points[0]]
	for point in team_points:
		director.add_spawn(Duelist.Team.RED, point)
	team_points = arena_map.spawn_points(Duelist.Team.BLUE)
	if network.team_size <= 1:
		team_points = [team_points[0]]
	for point in team_points:
		director.add_spawn(Duelist.Team.BLUE, point)
	director.score_changed.connect(_on_score_changed)
	director.phase_changed.connect(_on_phase_changed)
	director.match_finished.connect(_on_match_finished)
	director.respawn_started.connect(_on_lan_respawn_started)
	director.objective_changed.connect(_on_objective_changed)
	director.objective_event.connect(_on_objective_event)
	if host:
		_sync_roster_records(_authority_records())
	elif not _local_actor_id.is_empty():
		var local_record := {"actor_id": _local_actor_id, "team": int(_local_team), "human": true}
		_sync_roster_records([local_record])

func _clear_match_nodes() -> void:
	_clear_ballistics()
	_clear_ballistics_preview_bodies()
	_high_alert.reset()
	if hud != null:
		hud.clear_high_alert()
	if director != null:
		director.queue_free()
	for actor in _all_authority_actors():
		if is_instance_valid(actor):
			actor.queue_free()
	for actor in _all_replica_actors():
		if is_instance_valid(actor):
			actor.queue_free()
	_authoritative_duelists.clear()
	_replica_duelists.clear()
	_remote_snapshot_buffers.clear()
	_continuous_inputs.clear()
	_edge_queues.clear()
	_last_sequences.clear()
	director = null
	_local_duelist = null

func _start_host_match() -> void:
	if _authority_match_started or director == null:
		return
	_authority_match_started = true
	if director.phase == RiftlineMatch.Phase.FINISHED:
		director.take_rematch()
	else:
		director.begin()
	print("Riftline authoritative match started")
	for actor in _all_authority_actors():
		network.publish_event({"type": "spawn", "actor_id": actor.actor_id, "position": actor.global_position, "yaw": actor.rotation.y})

func _on_lobby_ready_requested(ready: bool) -> void:
	if not _lan_active or network == null:
		return
	if _lan_host:
		network.submit_lobby_ready(ready)
	elif not network.lobby_state.is_empty():
		network.submit_client_lobby_ready(ready, int(network.lobby_state.get("revision", 0)))

func _on_lobby_rematch_requested() -> void:
	if not _lan_active or network == null:
		return
	if _lan_host:
		network.submit_lobby_rematch_ready(true)
	elif not network.lobby_state.is_empty():
		network.submit_client_lobby_rematch_ready(true, int(network.lobby_state.get("revision", 0)))

func _apply_lobby_state(state: Dictionary) -> void:
	if state.is_empty() or not _lan_active:
		return
	var revision := int(state.get("revision", -1))
	var generation := int(state.get("launch_generation", _lobby_generation))
	if revision < _lobby_revision or generation < _lobby_generation:
		return
	_lobby_revision = revision
	_lobby_generation = maxi(_lobby_generation, generation)
	if network != null and not _lan_host:
		network.lobby_state = state.duplicate(true)
		_sync_roster_records(state.get("records", []))
	if rift_link != null and rift_link.visible:
		rift_link.set_lobby_state(state)
	var phase := int(state.get("phase", RiftlineLobby.Phase.STAGING))
	if hud != null and phase != RiftlineLobby.Phase.LIVE:
		hud.set_connection_flow_active(true)
		hud.set_combat_input_enabled(false)
	if phase == RiftlineLobby.Phase.ARMING:
		_session_ready_for_snapshots = false
	elif phase == RiftlineLobby.Phase.STAGING or phase == RiftlineLobby.Phase.REMATCH:
		_session_ready_for_snapshots = false

func _on_lobby_state_received(state: Dictionary) -> void:
	_apply_lobby_state(state)
	if int(state.get("phase", -1)) == RiftlineLobby.Phase.ARMING and _lan_host:
		_begin_lobby_launch()

func _on_lobby_live_received(state: Dictionary) -> void:
	_apply_lobby_state(state)
	_on_lobby_live_state(state)

func _on_lobby_abandoned_received(state: Dictionary) -> void:
	_apply_lobby_state(state)
	_show_severed_state(str(state.get("reason", "RIFT SEVERED")))

func _on_lobby_live_state(_state: Dictionary) -> void:
	if not _lan_active:
		return
	if not _lan_host and director != null and director.phase == RiftlineMatch.Phase.FINISHED:
		director.take_rematch()
	_session_ready_for_snapshots = true

func _begin_lobby_launch() -> void:
	if not _lan_host or director == null or _lobby_arming_remaining > 0.0:
		return
	_lobby_arming_remaining = 0.72
	if hud != null:
		hud.set_combat_input_enabled(false)

func _tick_lobby_arming(delta: float) -> void:
	if not _lan_host or _lobby_arming_remaining <= 0.0:
		return
	_lobby_arming_remaining = maxf(0.0, _lobby_arming_remaining - delta)
	if _lobby_arming_remaining <= 0.0:
		_start_host_match()
		network.publish_lobby_live()

func _show_severed_state(reason: String) -> void:
	if not _lan_active:
		return
	_clear_ballistics()
	_clear_presentation_effects()
	if combat_feedback != null:
		combat_feedback.stop_all()
	_clear_match_nodes()
	if hud != null:
		hud.set_connection_flow_active(true)
		hud.set_combat_input_enabled(false)
	if rift_link != null:
		rift_link.show_severed(reason)
	network.stop()
	_lan_host = false
	_lan_peer_ready = false

func _tick_lan_duel(delta: float) -> void:
	if _local_duelist == null:
		return
	_local_duelist.apply_look(hud.take_look_delta())
	if hud.gyro_enabled:
		var gyroscope := Input.get_gyroscope()
		_local_duelist.apply_look(Vector2(gyroscope.y, -gyroscope.x) * 2.4)
	var live := director != null and director.is_live() if _lan_host else _lan_phase == RiftlineMatch.Phase.LIVE
	var wants_reload := hud.take_reload() or Input.is_action_just_pressed("reload")
	var interact_held := hud.interact_held() or Input.is_action_pressed("interact")
	if not live or not hud.can_drive_combat():
		hud.take_jump()
		hud.take_crouch()
		hud.take_prone()
		hud.take_weapon_switch()
		hud.take_melee()
		_local_duelist.set_combat_pose(false, delta)
		_local_duelist.apply_input_frame({}, delta, false)
		# A non-host client's respawn/class picks still have to reach the
		# host even while dead or between phases, when the branch below (the
		# only other place a frame gets sent) is skipped - so send a
		# combat-idle frame here too, carrying only those two fields for real.
		if not _lan_host:
			var idle_frame := _local_duelist.make_input_frame(_local_input_sequence, Vector2.ZERO, false, false, false, false, false, false, false, false, false, false)
			idle_frame["protocol"] = RiftlineNetwork.PROTOCOL_VERSION
			idle_frame["respawn"] = _pending_respawn_request
			idle_frame["class_id"] = int(_pending_player_class)
			idle_frame["primary_weapon"] = int(_pending_primary_weapon)
			_local_input_sequence += 1
			network.send_input(idle_frame)
	else:
		var keyboard := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var movement := hud.movement if hud.movement.length_squared() > 0.001 else keyboard
		var frame := _local_duelist.make_input_frame(
			_local_input_sequence,
			movement,
			hud.aim_held,
			hud.fire_held or Input.is_action_pressed("fire"),
			hud.take_jump() or Input.is_action_just_pressed("jump"),
			hud.take_crouch(),
			hud.take_prone(),
			hud.take_weapon_switch(),
			wants_reload,
			false,
			interact_held,
			hud.take_melee() or Input.is_action_just_pressed("melee"))
		frame["protocol"] = RiftlineNetwork.PROTOCOL_VERSION
		frame["respawn"] = _pending_respawn_request
		frame["class_id"] = int(_pending_player_class)
		frame["primary_weapon"] = int(_pending_primary_weapon)
		_local_input_sequence += 1
		_local_duelist.set_combat_pose(bool(frame.aim), delta)
		if _lan_host:
			_local_duelist.apply_input_frame(frame, delta, true)
			director.set_interact(_local_actor_id, bool(frame.interact))
			for actor_id in _authoritative_duelists.keys():
				if str(actor_id) == _local_actor_id:
					continue
				var target := _actor(str(actor_id))
				if target == null:
					continue
				for edge in _edge_queues.get(actor_id, []):
					target.apply_discrete_input(edge)
				_edge_queues[actor_id] = []
				var continuous: Dictionary = _continuous_inputs.get(actor_id, {})
				target.apply_continuous_input(continuous, delta, true)
				director.set_interact(str(actor_id), bool(continuous.get("interact", false)))
				_apply_remote_respawn_and_class(str(actor_id), target, continuous)
		else:
			_local_duelist.apply_input_frame(frame, delta, false)
			if bool(frame.fire):
				# The joining client predicts only local presentation for every
				# weapon now - RiftBallistics.fire() self-guards on authority, so
				# damage remains authority-owned no matter which weapon fired.
				# Melee is deliberately NOT predicted here: it has no self-guard
				# and only ever runs through the authoritative simulate_combat
				# path, exactly like the knife it replaces.
				_local_duelist.fire_forward()
			_pending_inputs.append(frame)
			network.send_input(frame)
	hud.set_stance(_local_duelist.stance)
	hud.set_weapon(_local_duelist.weapon)
	hud.set_loadout_slots(_local_duelist.loadout_slots)
	hud.show_ammo(_local_duelist.magazine_rounds, _local_duelist.reserve_ammo, _local_duelist.reload_remaining)
	_sync_reload_feedback()
	hud.show_damage(_local_duelist.health)
	if not _lan_host:
		_smooth_remote_presentation()
	if _lan_host:
		_lan_tick += 1
		_tick_authority_ballistics(delta)
		_snapshot_remaining -= delta
		if _snapshot_remaining <= 0.0:
			_snapshot_remaining = 0.05
			_publish_lan_snapshot()

func _smooth_remote_presentation() -> void:
	for actor_id in _remote_snapshot_buffers.keys():
		var actor := _actor(str(actor_id))
		var buffer: RefCounted = _remote_snapshot_buffers[actor_id]
		if actor == null or buffer == null:
			continue
		var presented: Dictionary = buffer.sample(network.simulation_clock)
		if not presented.is_empty():
			actor.apply_presentation_state(presented)

func _update_remote_snapshot(actor_id: String, remote_state: Dictionary, host_tick: int) -> void:
	var actor := _actor(actor_id)
	var buffer: RefCounted = _remote_snapshot_buffers.get(actor_id, null)
	if actor == null or buffer == null or remote_state.is_empty():
		return
	var next_eliminated := bool(remote_state.get("eliminated", false))
	var previous: Dictionary = buffer.sample(network.simulation_clock)
	var should_reset := not previous.is_empty() and next_eliminated != bool(previous.get("eliminated", false))
	var incoming_position: Vector3 = remote_state.get("position", actor.global_position)
	if actor.global_position.distance_to(incoming_position) > 3.0:
		should_reset = true
	if should_reset:
		buffer.clear()
		actor.apply_presentation_state(remote_state)
	buffer.push(remote_state, host_tick, network.simulation_clock)

func _tick_dedicated_server(delta: float) -> void:
	if not _lan_active or director == null:
		return
	_tick_lobby_arming(delta)
	var applied: Dictionary = {}
	for actor_id in _authoritative_duelists.keys():
		var target: Duelist = _authoritative_duelists[actor_id]
		if target == null:
			continue
		if _continuous_inputs.has(actor_id):
			applied[actor_id] = true
		var edges: Array = _edge_queues.get(actor_id, [])
		_edge_queues[actor_id] = []
		if director.is_live():
			for edge in edges:
				target.apply_discrete_input(edge)
			var continuous: Dictionary = _continuous_inputs.get(actor_id, {})
			target.apply_continuous_input(continuous, delta, true)
			director.set_interact(str(actor_id), bool(continuous.get("interact", false)))
		else:
			target.apply_continuous_input({}, delta, false)
	for actor_id in _authoritative_duelists.keys():
		if not applied.has(actor_id):
			(_authoritative_duelists[actor_id] as Duelist).apply_continuous_input({}, delta, false)
	_tick_authority_ballistics(delta)
	_lan_tick += 1
	_snapshot_remaining -= delta
	if _snapshot_remaining <= 0.0:
		_snapshot_remaining = 0.05
		_publish_lan_snapshot()

func _publish_lan_snapshot() -> void:
	if director == null:
		return
	var match_state := director.authoritative_state()
	var players := {}
	for actor_id in _authoritative_duelists.keys():
		var duelist: Duelist = _authoritative_duelists[actor_id]
		players[actor_id] = duelist.authoritative_state(_lan_tick, _last_sequence_for(duelist))
	var snapshot := {
		"tick": _lan_tick,
		"match": match_state,
		"phase": int(match_state.get("phase", int(director.phase))),
		"red_score": int(match_state.get("red_score", 0)),
		"blue_score": int(match_state.get("blue_score", 0)),
		"objective": match_state.get("objective", {}),
		"players": players,
	}
	network.publish_snapshot(snapshot)

func _last_sequence_for(duelist: Duelist) -> int:
	return _local_input_sequence - 1 if duelist.actor_id == _local_actor_id else int(_last_sequences.get(duelist.actor_id, -1))

func _apply_client_phase(next_phase: int) -> void:
	_lan_phase = next_phase as RiftlineMatch.Phase
	if _lan_phase != RiftlineMatch.Phase.LIVE:
		_clear_ballistics()
	for buffer in _remote_snapshot_buffers.values():
		(buffer as RefCounted).clear()
	if hud != null:
		hud.set_match_phase(_lan_phase)
		hud.set_combat_input_enabled(_lan_phase == RiftlineMatch.Phase.LIVE)
	for actor in _all_replica_actors():
		actor.set_match_active(_lan_phase == RiftlineMatch.Phase.LIVE)
	if _lan_phase == RiftlineMatch.Phase.LIVE:
		if rift_link != null:
			rift_link.hide_panel()
		if hud != null:
			hud.set_connection_flow_active(false)

func _on_team_assigned(team_value: int) -> void:
	if team_value < int(Duelist.Team.RED) or team_value > int(Duelist.Team.BLUE):
		return
	_local_team = team_value as Duelist.Team

func _on_view_fov_changed(horizontal_degrees: float) -> void:
	if _local_duelist != null:
		_local_duelist.set_horizontal_fov(horizontal_degrees)

func _on_actor_assigned(actor_id: String, team_value: int) -> void:
	if actor_id.is_empty() or team_value < int(Duelist.Team.RED) or team_value > int(Duelist.Team.BLUE):
		return
	_local_actor_id = actor_id
	_local_team = team_value as Duelist.Team
	if _lan_active and not _lan_host and not _dedicated_server:
		_sync_roster_records([{"actor_id": actor_id, "team": team_value, "human": true}])

func _on_roster_received(records: Array[Dictionary]) -> void:
	if not _lan_active or _lan_host:
		return
	_sync_roster_records(records)

func _authority_roster_ready() -> bool:
	return network != null and network.lobby != null and network.lobby.can_launch()

func _on_lan_defeat(victim: Duelist, killer: Duelist) -> void:
	if _lan_host:
		network.publish_event({"type": "defeat", "victim_id": victim.actor_id, "killer_id": killer.actor_id})

func _on_lan_respawn_started(victim: Duelist) -> void:
	_clear_presentation_effects()
	if _lan_host:
		network.publish_event({"type": "spawn", "actor_id": victim.actor_id, "position": victim.global_position, "yaw": victim.rotation.y})

func _apply_client_defeat(actor_id: String) -> void:
	var victim := _actor(actor_id)
	if victim != null:
		victim.apply_presentation_state({"health": 0.0, "eliminated": true})

func _apply_client_spawn(actor_id: String, position: Variant = null, yaw: float = 0.0) -> void:
	_clear_ballistics()
	_clear_presentation_effects()
	var target := _actor(actor_id)
	if target == null:
		return
	if position == null or not position is Vector3:
		return
	target.apply_presentation_state({
		"position": position,
		"velocity": Vector3.ZERO,
		"yaw": yaw,
		"pitch": 0.0,
		"health": Duelist.HEALTH,
		"stance": int(Duelist.Stance.STAND),
		"weapon": int(target.loadout_slots[0]) if not target.loadout_slots.is_empty() else int(Duelist.Weapon.RIFLE),
		"active_slot": 0,
		"eliminated": false,
	})
	if target == _local_duelist:
		_pending_inputs.clear()

## Tears down whatever match/connection state is live and returns to the main
## menu - the destination for both the settings panel's MAIN MENU action and
## an unrecoverable connection loss. This used to silently drop the player
## into a fresh offline solo match instead, which is why MAIN MENU used to
## "go nowhere" from a bot drill (there was nothing left to distinguish it
## from just continuing).
func _restore_offline_training(message: String) -> void:
	_clear_ballistics()
	_clear_presentation_effects()
	if combat_feedback != null:
		combat_feedback.stop_all()
	if coach != null:
		coach.hide()
	_lan_active = false
	_lan_host = false
	_lan_peer_ready = false
	_pending_respawn_request = false
	network.stop()
	rift_link.hide_panel()
	hud.set_connection_flow_active(false)
	if class_panel != null:
		class_panel.visible = false
	_class_panel_context = ""
	_practice_panel_active = false
	if practice_panel != null:
		practice_panel.visible = false
	_clear_match_nodes()
	hud.show_connection_message(message)
	_build_main_menu()
	main_menu.show_menu()

func _sync_objective_presentation() -> void:
	if director == null or not _objective_preview.is_empty():
		return
	var state := director.objective_state()
	if hud != null:
		hud.set_objective_state(state)
		_update_use_control(state)
	_sync_nuke_core_presentation(state)
	_sync_launch_pad_presentation(state)
	_sync_interact_progress(state)

# The visible core node tracks only replicated objective state, never local
# authority guesses, so it stays correct on a client with no authority.
func _sync_nuke_core_presentation(state: Dictionary) -> void:
	if not _presentation_enabled or _nuke_core_root == null:
		return
	var core_state := int(state.get("core_state", int(RiftlineMatch.CoreState.AT_CENTER)))
	if core_state == int(RiftlineMatch.CoreState.RESPAWNING):
		_nuke_core_root.visible = false
		return
	_nuke_core_root.visible = true
	_nuke_core_root.global_position = state.get("core_position", Vector3.ZERO) as Vector3

func _sync_launch_pad_presentation(state: Dictionary) -> void:
	if not _presentation_enabled or arena_map == null:
		return
	var core_state := int(state.get("core_state", int(RiftlineMatch.CoreState.AT_CENTER)))
	var installed_team := int(state.get("installed_team", -1))
	var launch_remaining := float(state.get("launch_remaining", 0.0))
	var cancel_progress := float(state.get("cancel_progress", 0.0))
	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		var pad_node := _launch_pad_node(team)
		if pad_node == null:
			continue
		var material := _pad_ring_material(pad_node)
		if material == null:
			continue
		var base_color: Color = _pad_base_colors.get(pad_node, Color.WHITE)
		var active := core_state == int(RiftlineMatch.CoreState.INSTALLED) and installed_team == int(team)
		_apply_pad_material_state(material, base_color, active, launch_remaining, cancel_progress)

func _apply_pad_material_state(material: ShaderMaterial, base_color: Color, active: bool, launch_remaining: float, cancel_progress: float) -> void:
	var base_energy := 3.6
	if not active:
		material.set_shader_parameter("emission_color", base_color)
		material.set_shader_parameter("emission_energy", base_energy)
		return
	var progress := clampf(1.0 - launch_remaining / RiftlineMatch.LAUNCH_COUNTDOWN_SECONDS, 0.0, 1.0)
	if cancel_progress > 0.0:
		# A fast alarm flash that whitens toward the accent color as the
		# cancel hold nears completion, so a defender's progress is legible.
		var pulse := sin(Time.get_ticks_msec() * 0.001 * TAU * 6.0) * 0.5 + 0.5
		material.set_shader_parameter("emission_color", base_color.lerp(Color.WHITE, cancel_progress))
		material.set_shader_parameter("emission_energy", lerpf(2.0, 10.0, pulse))
		return
	var pulse_hz := lerpf(0.6, 3.2, progress)
	var pulse := sin(Time.get_ticks_msec() * 0.001 * TAU * pulse_hz) * 0.5 + 0.5
	material.set_shader_parameter("emission_color", base_color)
	material.set_shader_parameter("emission_energy", lerpf(base_energy, 9.0, pulse))

func _launch_pad_node(team: Duelist.Team) -> Node3D:
	if _pad_nodes.has(team) and is_instance_valid(_pad_nodes[team]):
		return _pad_nodes[team]
	if arena_map == null:
		return null
	var node_name := "RedLaunchPad" if team == Duelist.Team.RED else "BlueLaunchPad"
	var node := arena_map.get_node_or_null(node_name)
	if node == null:
		return null
	_pad_nodes[team] = node
	return node

func _pad_ring_material(pad_node: Node3D) -> ShaderMaterial:
	if _pad_ring_materials.has(pad_node):
		return _pad_ring_materials[pad_node]
	if pad_node.get_child_count() < 3:
		return null
	var ring := pad_node.get_child(2)
	if not (ring is MeshInstance3D) or not ((ring as MeshInstance3D).material_override is ShaderMaterial):
		return null
	var mesh_instance := ring as MeshInstance3D
	var material := (mesh_instance.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	mesh_instance.material_override = material
	_pad_ring_materials[pad_node] = material
	_pad_base_colors[pad_node] = material.get_shader_parameter("emission_color")
	return material

func _sync_interact_progress(state: Dictionary) -> void:
	if _local_duelist == null:
		return
	var core_state := int(state.get("core_state", int(RiftlineMatch.CoreState.AT_CENTER)))
	var progress := 0.0
	if core_state == int(RiftlineMatch.CoreState.CARRIED) and str(state.get("core_carrier_id", "")) == _local_duelist.actor_id:
		progress = float(state.get("install_progress", 0.0))
	elif core_state == int(RiftlineMatch.CoreState.INSTALLED) and int(state.get("installed_team", -1)) != int(_local_duelist.team):
		progress = float(state.get("cancel_progress", 0.0))
	_local_duelist.set_interact_progress(progress)

# The warhead body plus emissive core, parented under the arena root rather
# than the carrier, so it reads identically for the host and for replica
# clients: neither ever positions it from anything but core_position.
func _build_nuke_core_presentation() -> void:
	if _nuke_core_root != null:
		return
	_nuke_core_root = Node3D.new()
	_nuke_core_root.name = "NukeCore"
	add_child(_nuke_core_root)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.32
	body_mesh.height = 1.0
	body.mesh = body_mesh
	body.rotation.x = PI * 0.5
	body.position.y = 0.5
	body.material_override = NuclearMaterials.metal(Color("54585d"), 0.28)
	_nuke_core_root.add_child(body)
	var fin_material := NuclearMaterials.painted_metal(Color("c23b2e"))
	for angle_degrees in [0.0, 90.0, 180.0, 270.0]:
		var fin := MeshInstance3D.new()
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.05, 0.34, 0.22)
		fin.mesh = fin_mesh
		fin.material_override = fin_material
		fin.position = Vector3(0.0, 0.22, 0.0)
		fin.rotation.y = deg_to_rad(angle_degrees)
		fin.translate_object_local(Vector3(0.32, 0.0, 0.0))
		_nuke_core_root.add_child(fin)
	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.2
	glow_mesh.height = 0.4
	glow.mesh = glow_mesh
	glow.position.y = 0.5
	glow.material_override = NuclearMaterials.emissive(Color("ffcf5e"), 5.0)
	_nuke_core_root.add_child(glow)

func _tick_perf_sample(delta: float) -> void:
	if (not _arena_perf_sample and not _feedback_perf_sample) or _perf_logged:
		return
	_perf_elapsed += delta
	if _perf_elapsed < 2.0:
		return
	_perf_frame_times.append(delta)
	if _perf_frame_times.size() < 120:
		return
	var total := 0.0
	var minimum := INF
	var maximum := 0.0
	for frame_time in _perf_frame_times:
		total += frame_time
		minimum = minf(minimum, frame_time)
		maximum = maxf(maximum, frame_time)
	if _feedback_perf_sample:
		var diagnostics := combat_feedback.diagnostics() if combat_feedback != null else {}
		print("Riftline feedback perf sample: map=%s frames=%d avg_ms=%.2f min_ms=%.2f max_ms=%.2f active_voices=%d world_pool=%d local_pool=%d seen_events=%d skipped_low_priority=%d" % [arena_map.map_id(), _perf_frame_times.size(), total / _perf_frame_times.size() * 1000.0, minimum * 1000.0, maximum * 1000.0, int(diagnostics.get("active_voices", 0)), int(diagnostics.get("world_pool", 0)), int(diagnostics.get("local_pool", 0)), int(diagnostics.get("seen_events", 0)), int(diagnostics.get("skipped_low_priority", 0))])
	else:
		print("Riftline arena perf sample: map=%s frames=%d avg_ms=%.2f min_ms=%.2f max_ms=%.2f" % [arena_map.map_id(), _perf_frame_times.size(), total / _perf_frame_times.size() * 1000.0, minimum * 1000.0, maximum * 1000.0])
	_perf_logged = true

func _sync_squad_hud() -> void:
	if hud == null:
		return
	var actors := _all_replica_actors() if _lan_active and not _lan_host else _all_authority_actors()
	var records: Array[Dictionary] = []
	for actor in actors:
		records.append({"actor_id": actor.actor_id, "team": int(actor.team), "eliminated": actor.eliminated})
	var squad := _offline_squad_size > 1 or (network != null and network.team_size > 1) or records.size() > 2
	var hud_team := Duelist.Team.BLUE if _feedback_preview == "hud-blue" else _local_team
	hud.set_roster_state(records, int(hud_team), squad)

func _continuous_input(frame: Dictionary) -> Dictionary:
	return {
		"sequence": int(frame.get("sequence", -1)),
		"move_x": float(frame.get("move_x", 0.0)),
		"move_y": float(frame.get("move_y", 0.0)),
		"yaw": float(frame.get("yaw", 0.0)),
		"pitch": float(frame.get("pitch", 0.0)),
		"aim": bool(frame.get("aim", false)),
		"fire": bool(frame.get("fire", false)),
		"melee": bool(frame.get("melee", false)),
		"interact": bool(frame.get("interact", false)),
		"respawn": bool(frame.get("respawn", false)),
		"class_id": int(frame.get("class_id", int(Duelist.PlayerClass.FRONTLINE))),
		"primary_weapon": int(frame.get("primary_weapon", int(Duelist.Weapon.RIFLE))),
	}

func _discrete_input(frame: Dictionary) -> Dictionary:
	return {
		"sequence": int(frame.get("sequence", -1)),
		"jump": bool(frame.get("jump", false)),
		"crouch": bool(frame.get("crouch", false)),
		"prone": bool(frame.get("prone", false)),
		"weapon_switch": bool(frame.get("weapon_switch", false)),
		"reload": bool(frame.get("reload", false)),
		"pass_seed": bool(frame.get("pass_seed", false)),
	}

func _play_shooter_fire(team: Duelist.Team, fired_weapon: Duelist.Weapon) -> void:
	for actor in _all_authority_actors():
		if actor.team == team:
			actor.play_local_weapon_fire(fired_weapon) if actor == _local_duelist else actor.play_remote_weapon_fire(fired_weapon)
			return
	for actor in _all_replica_actors():
		if actor.team == team:
			actor.play_local_weapon_fire(fired_weapon) if actor == _local_duelist else actor.play_remote_weapon_fire(fired_weapon)
			return

func _play_shooter_fire_by_id(actor_id: String, fired_weapon: Duelist.Weapon) -> void:
	var actor := _actor(actor_id)
	if actor == null:
		return
	actor.play_local_weapon_fire(fired_weapon) if actor == _local_duelist else actor.play_remote_weapon_fire(fired_weapon)

func _play_shooter_obstruction(actor_id: String) -> void:
	var actor := _actor(actor_id)
	if actor != null:
		actor.play_weapon_obstruction()

func _build_projectile_presentation_pool() -> void:
	if not _presentation_enabled or _projectile_presentation_pool != null:
		return
	_projectile_presentation_pool = Node3D.new()
	_projectile_presentation_pool.name = "ProjectilePresentationPool"
	add_child(_projectile_presentation_pool)
	for _index in 12:
		var tracer := MeshInstance3D.new()
		var tracer_mesh := SphereMesh.new()
		tracer_mesh.radius = 0.045
		tracer_mesh.height = 0.09
		tracer_mesh.radial_segments = 8
		tracer_mesh.rings = 6
		tracer.mesh = tracer_mesh
		# A slight stretch along the direction of travel reads as a fast-moving
		# round without becoming a streak/line - the bullet itself stays a small
		# projectile, not a cross or a bar.
		tracer.scale = Vector3(1.0, 1.0, 2.4)
		tracer.material_override = NuclearMaterials.emissive(Color("fff0b0"), 6.0).duplicate()
		tracer.visible = false
		_projectile_presentation_pool.add_child(tracer)
		_tracer_pool.append(tracer)
	for _index in 8:
		var impact := Node3D.new()
		impact.name = "CarbineImpact"
		impact.visible = false
		# A flush circular scorch mark against the surface - an actual bullet
		# mark, not two crossed bars.
		var mark := MeshInstance3D.new()
		var mark_mesh := CylinderMesh.new()
		mark_mesh.top_radius = 0.05
		mark_mesh.bottom_radius = 0.1
		mark_mesh.height = 0.012
		mark_mesh.radial_segments = 10
		mark.mesh = mark_mesh
		mark.rotation.x = PI * 0.5
		mark.material_override = NuclearMaterials.emissive(Color("fff0b0"), 5.0).duplicate()
		impact.add_child(mark)
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.18
		ring_mesh.outer_radius = 0.22
		ring_mesh.rings = 12
		ring_mesh.ring_segments = 8
		ring.mesh = ring_mesh
		ring.rotation.x = PI * 0.5
		ring.material_override = NuclearMaterials.emissive(Color("fff0b0"), 4.0).duplicate()
		impact.add_child(ring)
		_projectile_presentation_pool.add_child(impact)
		_impact_pool.append(impact)

func _spawn_projectile_tracer(fact: Dictionary) -> void:
	if _tracer_pool.is_empty():
		return
	var tracer := _tracer_pool[_tracer_cursor]
	_tracer_cursor = (_tracer_cursor + 1) % _tracer_pool.size()
	var previous_projectile_key := str(tracer.get_meta("projectile_key", ""))
	if not previous_projectile_key.is_empty() and _projectile_tracers.get(previous_projectile_key) == tracer:
		_projectile_tracers.erase(previous_projectile_key)
	var token := int(tracer.get_meta("token", 0)) + 1
	tracer.set_meta("token", token)
	var origin: Vector3 = fact.get("presentation_origin", fact.get("origin", Vector3.ZERO))
	var velocity: Vector3 = fact.get("velocity", Vector3.ZERO)
	if velocity.length_squared() < 0.0001:
		return
	var direction := velocity.normalized()
	tracer.global_position = origin + direction * 0.55
	tracer.look_at(tracer.global_position + direction, Vector3.UP)
	tracer.scale = Vector3(1.0, 1.0, 2.4)
	tracer.visible = true
	var team := int(fact.get("team", int(Duelist.Team.RED))) as Duelist.Team
	_set_projectile_color(tracer, Color("ff6a57") if team == Duelist.Team.RED else Color("75dbff"), 4.0)
	var projectile_id := int(fact.get("id", -1))
	var projectile_key := "%s:%d" % [str(fact.get("session_id", "legacy")), projectile_id]
	tracer.set_meta("projectile_id", projectile_id)
	tracer.set_meta("projectile_key", projectile_key)
	if projectile_id >= 0:
		_projectile_tracers[projectile_key] = tracer
	_animate_projectile_tracer(tracer, origin, velocity, projectile_key, token)

func _animate_projectile_tracer(tracer: MeshInstance3D, origin: Vector3, velocity: Vector3, projectile_key: String, token: int) -> void:
	var elapsed := 0.0
	while elapsed < 0.07 and is_instance_valid(tracer) and int(tracer.get_meta("token", -1)) == token:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var direction := velocity.normalized()
		tracer.global_position = origin + direction * velocity.length() * elapsed
		tracer.look_at(tracer.global_position + direction, Vector3.UP)
	if is_instance_valid(tracer) and int(tracer.get_meta("token", -1)) == token:
		tracer.visible = false
	if _projectile_tracers.get(projectile_key) == tracer:
		_projectile_tracers.erase(projectile_key)

func _cancel_projectile_tracer(fact: Dictionary) -> void:
	var projectile_key := "%s:%d" % [str(fact.get("session_id", "legacy")), int(fact.get("id", -1))]
	var tracer: MeshInstance3D = _projectile_tracers.get(projectile_key)
	if is_instance_valid(tracer):
		tracer.set_meta("token", int(tracer.get_meta("token", 0)) + 1)
		tracer.visible = false
	_projectile_tracers.erase(projectile_key)

func _spawn_projectile_impact(point: Vector3, normal: Vector3, team: Duelist.Team, hit_duelist: bool) -> void:
	if _impact_pool.is_empty():
		return
	var impact := _impact_pool[_impact_cursor]
	_impact_cursor = (_impact_cursor + 1) % _impact_pool.size()
	var token := int(impact.get_meta("token", 0)) + 1
	impact.set_meta("token", token)
	impact.global_position = point
	var safe_normal := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	impact.look_at(point + safe_normal, Vector3.RIGHT if absf(safe_normal.dot(Vector3.UP)) > 0.92 else Vector3.UP)
	impact.scale = Vector3.ONE * (0.8 if hit_duelist else 0.5)
	var ring := impact.get_child(1) as MeshInstance3D
	if ring != null:
		ring.visible = hit_duelist
	for child in impact.get_children():
		_set_projectile_color(child as MeshInstance3D, Color("ff6a57") if team == Duelist.Team.RED else Color("75dbff"), 3.8 if hit_duelist else 2.8)
	impact.visible = true
	_animate_projectile_impact(impact, token)

func _animate_projectile_impact(impact: Node3D, token: int) -> void:
	var elapsed := 0.0
	while elapsed < 0.16 and is_instance_valid(impact) and int(impact.get_meta("token", -1)) == token:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		impact.scale = Vector3.ONE * (1.0 + elapsed * 2.0)
	if is_instance_valid(impact) and int(impact.get_meta("token", -1)) == token:
		impact.visible = false

func _set_projectile_color(instance: MeshInstance3D, color: Color, glow: float) -> void:
	if instance == null or not (instance.material_override is ShaderMaterial):
		return
	var material := instance.material_override as ShaderMaterial
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("emission_color", color)
	material.set_shader_parameter("emission_energy", glow)

func _spawn_beam(origin: Vector3, end: Vector3, color: Color, radius: float, lifetime: float) -> void:
	if _presentation_effects == null or origin.distance_squared_to(end) < 0.0001:
		return
	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = origin.distance_to(end)
	beam.mesh = mesh
	beam.material_override = NuclearMaterials.emissive(color, 5.5)
	beam.position = origin.lerp(end, 0.5)
	_presentation_effects.add_child(beam)
	beam.look_at(end, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_remove_presentation_node(beam, lifetime)

func _spawn_impact(point: Vector3, color: Color, radius: float, lifetime: float) -> void:
	if _presentation_effects == null:
		return
	var impact := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	impact.mesh = mesh
	impact.material_override = NuclearMaterials.emissive(color, 5.0)
	impact.position = point
	impact.scale = Vector3(1.0, 1.0, 0.42)
	_presentation_effects.add_child(impact)
	_remove_presentation_node(impact, lifetime)

func _spawn_delivery_pulse(gate_position: Vector3, color: Color) -> void:
	if _presentation_effects == null:
		return
	var pulse := MeshInstance3D.new()
	var pulse_mesh := TorusMesh.new()
	pulse_mesh.inner_radius = 0.28
	pulse_mesh.outer_radius = 0.36
	pulse_mesh.rings = 20
	pulse_mesh.ring_segments = 10
	pulse.mesh = pulse_mesh
	pulse.position = gate_position + Vector3.UP * 1.35
	pulse.material_override = NuclearMaterials.emissive(color, 4.2).duplicate()
	_presentation_effects.add_child(pulse)
	_animate_delivery_pulse(pulse)
	for side in [-1.0, 1.0]:
		var flare := MeshInstance3D.new()
		flare.mesh = _box_mesh(Vector3(0.08, 2.8, 0.08))
		flare.position = gate_position + Vector3(side * 0.72, 1.4, 0.0)
		flare.material_override = NuclearMaterials.emissive(color, 4.0)
		_presentation_effects.add_child(flare)
		_remove_presentation_node(flare, 0.24)

func _animate_delivery_pulse(pulse: MeshInstance3D) -> void:
	var elapsed := 0.0
	while elapsed < 0.42 and is_instance_valid(pulse):
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		var progress := clampf(elapsed / 0.42, 0.0, 1.0)
		pulse.scale = Vector3.ONE * (1.0 + progress * 2.4)
		if pulse.material_override is ShaderMaterial:
			(pulse.material_override as ShaderMaterial).set_shader_parameter("emission_energy", 4.2 * (1.0 - progress))
	if is_instance_valid(pulse):
		pulse.queue_free()

func _remove_presentation_node(node: Node, lifetime: float) -> void:
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(node):
		node.queue_free()

func _clear_presentation_effects() -> void:
	if _presentation_effects == null:
		return
	for child in _presentation_effects.get_children():
		child.queue_free()

func _box_mesh(dimensions: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return mesh

func _cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	return mesh

func _read_capture_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--after="):
			_capture_after = maxf(0.2, argument.trim_prefix("--after=").to_float())
		elif argument == "--settings":
			_capture_settings = true
		elif argument == "--hud-layout":
			_capture_hud_layout = true
		elif argument == "--character":
			_capture_character = true
		elif argument == "--overview":
			_capture_overview = true
		elif argument == "--rift-link":
			_capture_rift_link = true
		elif argument.begins_with("--offline-squad="):
			var requested_size := argument.trim_prefix("--offline-squad=")
			if requested_size.is_valid_int():
				_set_offline_squad_size(requested_size.to_int())
		elif argument.begins_with("--squad-preview="):
			_squad_preview = argument.trim_prefix("--squad-preview=")
			if _squad_preview == "three-versus-three":
				_set_offline_squad_size(3)
		elif argument.begins_with("--practice-preview="):
			_practice_preview = argument.trim_prefix("--practice-preview=")
		elif argument.begins_with("--tactics-preview="):
			_tactics_preview = argument.trim_prefix("--tactics-preview=")
			_set_offline_squad_size(4)
			_squad_preview = "tactics"
		elif argument.begins_with("--arena-preview="):
			_arena_preview = argument.trim_prefix("--arena-preview=")
			if _arena_preview in ["red-dock", "relay-basin", "windwalk", "service-run", "blue-dock", "carrier-gate", "first-person", "overview", "red-bay", "blue-bay"] and _offline_squad_size < 3:
				_set_offline_squad_size(3)
		elif argument.begins_with("--feedback-preview="):
			_feedback_preview = argument.trim_prefix("--feedback-preview=")
			if _feedback_preview == "squad-motion":
				_set_offline_squad_size(3)
		elif argument == "--arena-perf-sample":
			_arena_perf_sample = true
			_set_offline_squad_size(4)
		elif argument == "--feedback-perf-sample":
			_feedback_perf_sample = true
			_set_offline_squad_size(4)
		elif argument.begins_with("--objective-preview="):
			_objective_preview = argument.trim_prefix("--objective-preview=")
		elif argument.begins_with("--weapon-preview="):
			_weapon_preview = argument.trim_prefix("--weapon-preview=")
		elif argument.begins_with("--view-fov="):
			var requested_fov := argument.trim_prefix("--view-fov=").to_float()
			_view_fov_preview = clampf(requested_fov, Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV) if is_finite(requested_fov) else Duelist.DEFAULT_HORIZONTAL_FOV
		elif argument.begins_with("--reload-preview="):
			_reload_preview = argument.trim_prefix("--reload-preview=")
		elif argument.begins_with("--hud-preview="):
			_hud_preview = argument.trim_prefix("--hud-preview=")
		elif argument.begins_with("--loadout-preview="):
			_loadout_preview = argument.trim_prefix("--loadout-preview=")
		elif argument.begins_with("--ballistics-preview="):
			_ballistics_preview = argument.trim_prefix("--ballistics-preview=")
		elif argument.begins_with("--motion-preview="):
			_motion_preview = argument.trim_prefix("--motion-preview=")
			if _motion_preview in ["world-locomotion", "relay-machinery"]:
				_set_offline_squad_size(3)
		elif argument.begins_with("--touch-preview="):
			_touch_preview = argument.trim_prefix("--touch-preview=")
		elif argument.begins_with("--rift-link-preview="):
			_rift_link_preview = argument.trim_prefix("--rift-link-preview=")
		elif argument.begins_with("--relay-preview="):
			_relay_preview = argument.trim_prefix("--relay-preview=")
			_set_offline_squad_size(4 if _relay_preview in ["bot-relay", "full-crew"] else 3)
	if _capture_settings and hud != null:
		hud.open_settings()
	if _capture_hud_layout and hud != null:
		hud.open_hud_layout()
	if _capture_character and hud != null and _local_duelist != null:
		# This is a renderer-only inspection hook for silhouette review, not an alternate gameplay state.
		var preview_actor := _preview_actor()
		preview_actor.position = Vector3(-2.0, 0.1, 0.0)
		preview_actor.rotation.y = PI * 0.5
		_local_duelist.camera.cull_mask = 1
		_local_duelist.camera.global_position = Vector3(-8.0, 1.65, 0.0)
		_local_duelist.camera.look_at(preview_actor.global_position + Vector3.UP * 0.9)
		preview_actor.set_physics_process(false)
	if _capture_overview and hud != null and _local_duelist != null:
		# A renderer-only inspection hook that lets captures verify both spawn halves at once.
		_local_duelist.camera.cull_mask = 1
		_local_duelist.camera.global_position = Vector3(0.0, 31.0, 27.0)
		_local_duelist.camera.look_at(Vector3(0.0, 0.0, 0.0))
	if _capture_rift_link and hud != null:
		hud.set_connection_flow_active(true)
		rift_link.open_menu()
	if not _rift_link_preview.is_empty() and rift_link != null:
		hud.set_connection_flow_active(true)
		rift_link.apply_preview(_rift_link_preview)
	if not _touch_preview.is_empty():
		hud.set_touch_preview(_touch_preview)

func _apply_arena_preview() -> void:
	if _local_duelist == null or _local_duelist.camera == null:
		return
	_local_duelist.camera.cull_mask = 1
	var camera_position := Vector3(0.0, 31.0, 27.0)
	var look_target := Vector3.ZERO
	match _arena_preview:
		"overview":
			camera_position = Vector3(0.0, 31.0, 27.0)
			look_target = Vector3(0.0, 0.0, 0.0)
		"first-person":
			camera_position = Vector3(0.0, 1.65, 18.0)
			look_target = Vector3(0.0, 1.45, 0.0)
			_local_duelist.position = Vector3(0.0, 0.1, 18.0)
			_local_duelist.rotation.y = -PI * 0.5
		"windwalk":
			camera_position = Vector3(-18.0, 10.0, 40.0)
			look_target = Vector3(-8.0, 0.5, 24.0)
		"relay-basin":
			camera_position = Vector3(0.0, 8.5, 16.0)
			look_target = Vector3(0.0, 0.8, 0.0)
		"service-run":
			camera_position = Vector3(18.0, 10.0, -40.0)
			look_target = Vector3(8.0, 0.6, -24.0)
		"red-dock", "red-bay":
			camera_position = Vector3(-51.0, 5.5, 10.0)
			look_target = Vector3(-43.0, 1.2, 0.0)
		"blue-dock", "blue-bay":
			camera_position = Vector3(51.0, 5.5, -10.0)
			look_target = Vector3(43.0, 1.2, 0.0)
		"carrier-gate":
			camera_position = Vector3(35.0, 4.0, 7.0)
			look_target = Vector3(55.0, 1.4, 0.0)
			_local_duelist.position = Vector3(38.0, 0.1, 5.0)
			_local_duelist.rotation.y = -0.9
	_local_duelist.camera.global_position = camera_position
	_local_duelist.camera.look_at(look_target)
	for actor in _all_authority_actors():
		actor.set_physics_process(false)


func _apply_weapon_preview() -> void:
	if _local_duelist == null or _weapon_preview.is_empty():
		return
	# Freeze only the capture fixture in a clean live HUD state; it does not alter match authority.
	if director != null:
		director.set_physics_process(false)
	if hud != null:
		hud.set_match_phase(RiftlineMatch.Phase.LIVE)
		hud.set_combat_input_enabled(true)
	var preview := _weapon_preview
	if preview in ["m4-hip", "rifle-hip", "m4-world", "rifle-world"]:
		preview = "carbine-hip" if preview.ends_with("hip") else "carbine-world"
	elif preview in ["m4-ads", "m4-ads-sight", "rifle-ads"]:
		preview = "carbine-ads"
	elif preview in ["knife-hip", "knife-world", "melee"]:
		preview = "melee"
	match preview:
		"carbine-hip":
			_local_duelist.set_weapon_presentation(Duelist.Weapon.RIFLE)
			_local_duelist.set_combat_pose(false, 1.0)
			if hud != null:
				hud.aim_held = false
		"carbine-ads":
			_local_duelist.set_weapon_presentation(Duelist.Weapon.RIFLE)
			_local_duelist.set_combat_pose(true, 1.0)
			if hud != null:
				hud.aim_held = true
		"carbine-world":
			var preview_actor := _preview_actor()
			_local_duelist.camera.cull_mask = 1
			preview_actor.position = Vector3(-2.5, 0.1, 0.0)
			preview_actor.rotation.y = PI * 0.5
			_local_duelist.camera.global_position = Vector3(-6.0, 1.7, 0.0)
			_local_duelist.camera.look_at(preview_actor.global_position + Vector3.UP * 0.95)
			preview_actor.set_physics_process(false)
		"melee":
			# There is no dedicated melee weapon anymore - preview a swing of
			# whatever is currently equipped.
			_local_duelist.set_combat_pose(false, 1.0)
			_local_duelist.play_local_melee_swing()
			if hud != null:
				hud.aim_held = false

func _apply_contract_previews() -> void:
	if hud == null:
		return
	if _view_fov_preview >= 0.0:
		hud.set_view_fov(_view_fov_preview, false)
		if _local_duelist != null:
			_local_duelist.set_horizontal_fov(_view_fov_preview)
	if not _reload_preview.is_empty():
		if director != null:
			director.set_physics_process(false)
		hud.set_weapon(Duelist.Weapon.RIFLE)
		if _local_duelist != null:
			_local_duelist.set_weapon_presentation(Duelist.Weapon.RIFLE)
		var rifle_reload_seconds: float = RiftWeapons.row(int(Duelist.Weapon.RIFLE)).reload_seconds
		var reload_remaining := rifle_reload_seconds
		match _reload_preview:
			"half":
				reload_remaining = rifle_reload_seconds * 0.5
			"near-complete":
				reload_remaining = 0.04
			_:
				reload_remaining = rifle_reload_seconds
		hud.show_ammo(4, 24, reload_remaining)
	if not _hud_preview.is_empty():
		match _hud_preview:
			"bottom-vitals-mid":
				hud.health = 60.0
			"bottom-vitals-low":
				hud.health = 20.0
			_:
				hud.health = 100.0
		hud.queue_redraw()
	if not _loadout_preview.is_empty():
		var preview_weapon := Duelist.Weapon.RIFLE
		match _loadout_preview:
			"m4", "rifle":
				preview_weapon = Duelist.Weapon.RIFLE
			"smg":
				preview_weapon = Duelist.Weapon.SMG
			"shotgun":
				preview_weapon = Duelist.Weapon.SHOTGUN
			"pistol", "knife":
				preview_weapon = Duelist.Weapon.PISTOL
			"sniper":
				preview_weapon = Duelist.Weapon.SNIPER
		hud.set_weapon(preview_weapon)
		if _local_duelist != null:
			_local_duelist.set_weapon_presentation(preview_weapon)

func _apply_ballistics_preview() -> void:
	if _ballistics_preview.is_empty() or not _presentation_enabled or _local_duelist == null:
		return
	if director != null:
		director.set_physics_process(false)
	if hud != null:
		hud.set_match_phase(RiftlineMatch.Phase.LIVE)
		hud.set_combat_input_enabled(true)
		hud.set_coach_cue({})
	if coach != null:
		coach.hide()
	# Preview fixtures use the real authority path so captures can prove the
	# crosshair contract.  The fixtures are static presentation targets and never
	# become part of the map or gameplay state.
	_local_duelist.set_match_active(true)
	_local_duelist.position = Vector3.ZERO
	_local_duelist.rotation = Vector3.ZERO
	_local_duelist.head.rotation = Vector3.ZERO
	_clear_ballistics_preview_bodies()
	_spawn_ballistics_preview_solid(Vector3(0.0, 1.2, -9.0), Vector3(0.8, 2.4, 0.8), Color("bd7254"))
	match _ballistics_preview:
		"crosshair-clear-near-wall":
			_spawn_ballistics_preview_solid(Vector3(0.42, 1.2, -2.0), Vector3(0.22, 2.4, 0.24), Color("496f8e"))
			_local_duelist.set_combat_pose(false, 1.0)
			_local_duelist._fire_remaining = 0.0
			_local_duelist.fire_forward()
			ballistics.tick_authority(1.0 / 60.0)
		"muzzle-embedded":
			_spawn_ballistics_preview_solid(_local_duelist.physical_muzzle_position(), Vector3(0.4, 0.4, 0.4), Color("496f8e"))
			_local_duelist.set_combat_pose(false, 1.0)
			_local_duelist._fire_remaining = 0.0
			_local_duelist.fire_forward()
		"hip-burst":
			_local_duelist.set_combat_pose(false, 1.0)
			for _index in 3:
				_local_duelist._fire_remaining = 0.0
				_local_duelist.fire_forward()
				ballistics.tick_authority(1.0 / 60.0)
		"ads-burst":
			_local_duelist.set_combat_pose(true, 1.0)
			for _index in 3:
				_local_duelist._fire_remaining = 0.0
				_local_duelist.fire_forward()
				ballistics.tick_authority(1.0 / 60.0)
		"single-fire":
			_local_duelist.set_combat_pose(false, 1.0)
			_local_duelist._fire_remaining = 0.0
			_local_duelist.fire_forward()

func _spawn_ballistics_preview_solid(position: Vector3, dimensions: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box_mesh(dimensions)
	mesh.material_override = NuclearMaterials.painted_metal(color)
	body.add_child(mesh)
	add_child(body)
	_preview_ballistics_bodies.append(body)

func _clear_ballistics_preview_bodies() -> void:
	for body in _preview_ballistics_bodies:
		if is_instance_valid(body):
			body.queue_free()
	_preview_ballistics_bodies.clear()

func _apply_motion_preview() -> void:
	if _motion_preview.is_empty() or _local_duelist == null or _local_duelist.camera == null:
		return
	if director != null:
		director.set_physics_process(false)
	if coach != null:
		coach.hide()
	if hud != null:
		hud.set_match_phase(RiftlineMatch.Phase.LIVE)
		hud.set_combat_input_enabled(true)
		hud.set_coach_cue({})
	_local_duelist.set_match_active(true)
	match _motion_preview:
		"first-person-reload":
			_local_duelist.set_weapon_presentation(Duelist.Weapon.RIFLE)
			_local_duelist.magazine_rounds = 4
			_local_duelist.reserve_ammo = 24
			_local_duelist.reload_weapon()
		"weapon-tuck":
			_clear_ballistics_preview_bodies()
			_spawn_ballistics_preview_solid(_local_duelist.physical_muzzle_position(), Vector3(0.4, 0.4, 0.4), Color("496f8e"))
			_local_duelist.set_weapon_presentation(Duelist.Weapon.RIFLE)
			_local_duelist.set_combat_pose(false, 1.0)
		"world-locomotion":
			_local_duelist.camera.cull_mask = 1
			_local_duelist.camera.global_position = Vector3(-7.0, 3.2, 8.0)
			_local_duelist.camera.look_at(Vector3(0.0, 1.0, 1.0))
			var preview_actor := _preview_actor()
			preview_actor.position = Vector3(0.0, 0.1, 1.0)
			preview_actor.velocity = Vector3(1.8, 0.0, 0.4)
			preview_actor.set_match_active(true)
		"relay-machinery":
			_local_duelist.camera.cull_mask = 1
			_local_duelist.camera.global_position = Vector3(0.0, 15.0, 22.0)
			_local_duelist.camera.look_at(Vector3(0.0, 1.0, 0.0))
			for actor in _all_authority_actors():
				actor.set_match_active(true)

func _apply_feedback_preview() -> void:
	if _feedback_preview.is_empty() or _local_duelist == null or hud == null:
		return
	if director != null and _feedback_preview != "squad-motion":
		director.set_physics_process(false)
	hud.set_match_phase(RiftlineMatch.Phase.LIVE)
	hud.set_combat_input_enabled(true)
	if _feedback_preview == "squad-motion":
		_local_duelist.camera.cull_mask = 1
		_local_duelist.camera.global_position = Vector3(0.0, 7.5, 14.0)
		_local_duelist.camera.look_at(Vector3(0.0, 1.0, 2.0))
		var preview_positions := [Vector3(-4.0, 0.1, 2.0), Vector3(3.5, 0.1, 4.0), Vector3(0.0, 0.1, 7.0)]
		var preview_index := 0
		for actor in _all_authority_actors():
			if actor == _local_duelist:
				continue
			actor.global_position = preview_positions[mini(preview_index, preview_positions.size() - 1)]
			actor.velocity = Vector3(1.6 if actor.team == Duelist.Team.RED else -1.6, 0.0, 0.0)
			preview_index += 1
	elif _feedback_preview == "hud-blue":
		_local_team = Duelist.Team.BLUE
		_sync_squad_hud()
	elif _feedback_preview == "coach-move":
		hud.set_touch_preview("coach-move")
	_tick_feedback_preview(0.0)

func _tick_feedback_preview(delta: float) -> void:
	if _feedback_preview.is_empty() or _local_duelist == null or hud == null:
		return
	_feedback_preview_elapsed += delta
	var repeat_interval := 0.05 if _feedback_preview == "high-alert-back" else 0.18 if _feedback_preview in ["damage-left", "damage-right", "low-health", "hit-confirm"] else 0.42
	if _feedback_preview_elapsed < repeat_interval and delta > 0.0:
		return
	_feedback_preview_elapsed = 0.0
	var enemy_team := Duelist.Team.BLUE if _local_team == Duelist.Team.RED else Duelist.Team.RED
	match _feedback_preview:
		"carbine-fire":
			_local_duelist.set_weapon_presentation(Duelist.Weapon.RIFLE)
			_local_duelist.play_local_weapon_fire(Duelist.Weapon.RIFLE)
			combat_feedback.weapon_fired(_local_actor_id, Duelist.Weapon.RIFLE, _local_duelist.global_position, true)
			hud.show_primary_fire_feedback()
		"knife-fire":
			_local_duelist.play_local_melee_swing()
			combat_feedback.melee_struck(_local_actor_id, _local_duelist.weapon, _local_duelist.global_position, _local_duelist.global_position, _local_team, true, false, "")
		"reload":
			hud.set_weapon(Duelist.Weapon.RIFLE)
			hud.set_touch_preview("reloading")
			hud.show_ammo(4, 24, float(RiftWeapons.row(int(Duelist.Weapon.RIFLE)).reload_seconds) * 0.5)
			combat_feedback.reload_started(true)
		"hit-confirm":
			hud.show_hit_confirm()
			combat_feedback.hit_confirm_feedback.emit()
		"damage-left":
			hud.show_damage(22.0)
			hud.show_damage_direction(Vector2.LEFT, 1.0, int(enemy_team))
		"damage-right":
			hud.show_damage(22.0)
			hud.show_damage_direction(Vector2.RIGHT, 1.0, int(enemy_team))
		"high-alert-back":
			hud.show_high_alert(Vector2.DOWN, 1.0)
		"low-health":
			hud.show_damage(22.0)
		"seed-claimed":
			hud.show_objective_event("objective_claimed", {})
			hud.show_objective_feedback("objective_claimed", int(_local_team))
			combat_feedback.objective_event("objective_claimed", {"event_id": "preview-claimed", "position": _local_duelist.global_position}, true)
		"seed-delivered":
			hud.show_objective_event("objective_delivered", {"scoring_team": int(_local_team)})
			hud.show_objective_feedback("objective_delivered", int(_local_team))
			combat_feedback.objective_event("objective_delivered", {"event_id": "preview-delivered", "scoring_team": int(_local_team), "position": _local_duelist.global_position}, true)
		"hud-default", "hud-blue", "squad-motion", "coach-move":
			pass

func _show_capture_tracer(position: Vector3, direction: Vector3, team_value: int) -> void:
	if _tracer_pool.is_empty():
		return
	var tracer := _tracer_pool[_tracer_cursor]
	_tracer_cursor = (_tracer_cursor + 1) % _tracer_pool.size()
	tracer.set_meta("token", int(tracer.get_meta("token", 0)) + 1)
	tracer.global_position = position
	tracer.look_at(position + direction, Vector3.UP)
	tracer.scale = Vector3(0.35, 0.35, 0.65)
	tracer.visible = true
	_set_projectile_color(tracer, Color("ff6a57") if team_value == int(Duelist.Team.RED) else Color("75dbff"), 3.2)

func _show_capture_impact(point: Vector3, normal: Vector3, team: Duelist.Team, hit_duelist: bool) -> void:
	if _impact_pool.is_empty():
		return
	var impact := _impact_pool[_impact_cursor]
	_impact_cursor = (_impact_cursor + 1) % _impact_pool.size()
	impact.set_meta("token", int(impact.get_meta("token", 0)) + 1)
	impact.global_position = point
	impact.look_at(point + normal, Vector3.UP)
	impact.scale = Vector3.ONE * (0.8 if hit_duelist else 0.5)
	var ring := impact.get_child(1) as MeshInstance3D
	if ring != null:
		ring.visible = hit_duelist
	for child in impact.get_children():
		_set_projectile_color(child as MeshInstance3D, Color("ff6a57") if team == Duelist.Team.RED else Color("75dbff"), 2.8)
	impact.visible = true

func _capture_after_delay() -> void:
	await get_tree().create_timer(_capture_after).timeout
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		push_error("Could not capture Riftline: viewport texture is unavailable")
		get_tree().quit()
		return
	var image := viewport_texture.get_image()
	var error := image.save_png(_capture_path)
	if error != OK:
		push_error("Could not write Riftline capture: %s" % _capture_path)
	get_tree().quit()
