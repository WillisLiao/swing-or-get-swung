class_name RiftlineMatch
extends Node

# Authoritative rules for deathmatch, bomb defuse, and Nuke Rush. Nuke Rush
# places one neutral warhead at center; either team can carry it into the enemy
# base, while timeout awards the team with the furthest recorded push.

signal score_changed(sun: int, void_score: int)
signal phase_changed(phase: Phase)
signal match_finished(winner: Duelist.Team)
signal respawn_started(victim: Duelist)
signal objective_changed(state: Dictionary)
signal objective_event(event_type: String, state: Dictionary)

enum Phase { OPENING, LIVE, INTERMISSION, FINISHED }
enum GameMode { DEATHMATCH, BOMB, NUKE_RUSH }
enum BombState { ARMING, CARRIED, PLANTING, PLANTED, DEFUSING, DETONATED, DEFUSED }
enum NukeState { AT_CENTER, CARRIED, DROPPED, DELIVERED }

const OPENING_HOLD_SECONDS := 2.5
const INTERMISSION_SECONDS := 1.5
const RESPAWN_DELAY_SECONDS := 1.1

const DM_SCORE_TO_WIN := 20
const DM_SAFE_SPAWN_RADIUS := 9.0

const BOMB_ROUNDS_TO_WIN := 2
const BOMB_PLANT_SECONDS := 3.0
const BOMB_DEFUSE_SECONDS := 3.0
const BOMB_FUSE_SECONDS := 40.0
const BOMB_SITE_RADIUS := 2.6
const BOMB_DEFUSE_RADIUS := 2.2

const NUKE_MATCH_SECONDS := 180.0
const NUKE_OVERTIME_SECONDS := 30.0
const NUKE_PICKUP_RADIUS := 1.8
const NUKE_DELIVERY_RADIUS := 3.4

var mode: GameMode = GameMode.DEATHMATCH

var rosters: Dictionary = {Duelist.Team.SUN: [], Duelist.Team.VOID: []}
var scores: Dictionary = {Duelist.Team.SUN: 0, Duelist.Team.VOID: 0}
var spawn_points: Dictionary = {Duelist.Team.SUN: [], Duelist.Team.VOID: []}
var bomb_sites: Array = []
var phase: Phase = Phase.OPENING

var bomb_state: BombState = BombState.CARRIED
var bomb_team: Duelist.Team = Duelist.Team.SUN
var bomb_carrier_id := ""
var bomb_position := Vector3.ZERO
var bomb_plant_progress := 0.0
var bomb_defuse_progress := 0.0
var bomb_fuse_remaining := 0.0

var nuke_state: NukeState = NukeState.AT_CENTER
var nuke_carrier_id := ""
var nuke_carrier_team: Duelist.Team = Duelist.Team.SUN
var nuke_position := Vector3.ZERO
var nuke_pickup_position := Vector3.ZERO
var nuke_time_remaining := NUKE_MATCH_SECONDS
var nuke_progress: Dictionary = {Duelist.Team.SUN: 0.0, Duelist.Team.VOID: 0.0}
var nuke_overtime := false

var _presentation_enabled := false
var _duelists_by_id: Dictionary = {}
var _round_generation := 0
var _respawn_generation: Dictionary = {}
var _opening_remaining := 0.0
var _intermission_remaining := 0.0
var _started := false
var _winner: Duelist.Team = Duelist.Team.SUN
var _last_replica_tick := -1
var _interact_held: Dictionary = {}

func configure(sites: Array, presentation_enabled: bool, game_mode: GameMode, pickup_position: Vector3 = Vector3.ZERO) -> void:
	bomb_sites = sites.duplicate()
	_presentation_enabled = presentation_enabled
	mode = game_mode
	nuke_pickup_position = pickup_position
	if mode == GameMode.NUKE_RUSH:
		nuke_position = nuke_pickup_position

func add_spawn(team: Duelist.Team, point: Vector3) -> void:
	spawn_points[team].append(point)

func register_duelist(duelist: Duelist, actor_id: String) -> void:
	if not is_instance_valid(duelist) or actor_id.is_empty():
		return
	duelist.set_actor_id(actor_id)
	if duelist in rosters[duelist.team]:
		_duelists_by_id[actor_id] = duelist
		return
	rosters[duelist.team].append(duelist)
	_duelists_by_id[actor_id] = duelist
	_respawn_generation[actor_id] = 0
	duelist.defeated.connect(_on_defeated)

func unregister_duelist(actor_id: String) -> void:
	var duelist: Variant = _duelists_by_id.get(actor_id, null)
	if not duelist is Duelist:
		return
	if duelist in rosters[duelist.team]:
		rosters[duelist.team].erase(duelist)
	_duelists_by_id.erase(actor_id)
	_respawn_generation.erase(actor_id)
	_interact_held.erase(actor_id)
	if rosters[Duelist.Team.SUN].is_empty() or rosters[Duelist.Team.VOID].is_empty():
		_started = false
		_cancel_respawns()
		_set_phase(Phase.OPENING)

func begin() -> void:
	if _started:
		return
	_started = true
	_start_round()

func is_live() -> bool:
	return phase == Phase.LIVE

func take_rematch() -> bool:
	if phase != Phase.FINISHED:
		return false
	_start_round()
	return true

func set_interact(actor_id: String, held: bool) -> void:
	_interact_held[actor_id] = held

func authoritative_state() -> Dictionary:
	return {
		"phase": int(phase),
		"mode": int(mode),
		"sun_score": int(scores[Duelist.Team.SUN]),
		"void_score": int(scores[Duelist.Team.VOID]),
		"objective": _objective_state(),
	}

func apply_replica_state(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var tick := int(snapshot.get("tick", -1))
	if tick >= 0 and tick <= _last_replica_tick:
		return
	if tick >= 0:
		_last_replica_tick = tick
	var next_phase := clampi(int(snapshot.get("phase", int(phase))), int(Phase.OPENING), int(Phase.FINISHED)) as Phase
	var phase_changed_locally := next_phase != phase
	phase = next_phase
	mode = clampi(int(snapshot.get("mode", int(mode))), int(GameMode.DEATHMATCH), int(GameMode.NUKE_RUSH)) as GameMode
	scores[Duelist.Team.SUN] = int(snapshot.get("sun_score", 0))
	scores[Duelist.Team.VOID] = int(snapshot.get("void_score", 0))
	var objective: Dictionary = snapshot.get("objective", {})
	_apply_objective_presentation(objective)
	if phase_changed_locally:
		_set_phase(phase)
	score_changed.emit(scores[Duelist.Team.SUN], scores[Duelist.Team.VOID])

func objective_state() -> Dictionary:
	return _objective_state()

func _objective_state() -> Dictionary:
	if mode == GameMode.DEATHMATCH:
		return {"mode": int(mode)}
	if mode == GameMode.NUKE_RUSH:
		return {
			"mode": int(mode),
			"nuke_state": int(nuke_state),
			"nuke_carrier_id": nuke_carrier_id,
			"nuke_carrier_team": int(nuke_carrier_team),
			"nuke_position": nuke_position,
			"time_remaining": nuke_time_remaining,
			"sun_progress": float(nuke_progress[Duelist.Team.SUN]),
			"void_progress": float(nuke_progress[Duelist.Team.VOID]),
			"overtime": nuke_overtime,
		}
	return {
		"mode": int(mode),
		"bomb_state": int(bomb_state),
		"bomb_team": int(bomb_team),
		"bomb_carrier_id": bomb_carrier_id,
		"bomb_position": bomb_position,
		"plant_progress": bomb_plant_progress,
		"defuse_progress": bomb_defuse_progress,
		"fuse_remaining": bomb_fuse_remaining,
	}

func _physics_process(delta: float) -> void:
	if not _started:
		return
	if phase == Phase.OPENING:
		_opening_remaining = maxf(0.0, _opening_remaining - delta)
		if _opening_remaining <= 0.0:
			_set_phase(Phase.LIVE)
	elif phase == Phase.INTERMISSION:
		_intermission_remaining = maxf(0.0, _intermission_remaining - delta)
		if _intermission_remaining <= 0.0:
			_start_round()
	elif phase == Phase.LIVE:
		if mode == GameMode.BOMB:
			_tick_bomb(delta)
		elif mode == GameMode.NUKE_RUSH:
			_tick_nuke_rush(delta)

func _start_round() -> void:
	_round_generation += 1
	_opening_remaining = OPENING_HOLD_SECONDS
	_intermission_remaining = 0.0
	_cancel_respawns()
	_reset_duelists_to_spawns()
	if mode == GameMode.BOMB:
		# Side swap each round; SUN opens as the first attacking side.
		bomb_team = _next_attacking_team()
		_reset_bomb()
	elif mode == GameMode.NUKE_RUSH:
		_reset_nuke_rush()
	_set_phase(Phase.OPENING)
	objective_changed.emit(_objective_state())

func _next_attacking_team() -> Duelist.Team:
	if _round_generation == 0:
		return Duelist.Team.SUN
	return Duelist.Team.VOID if bomb_team == Duelist.Team.SUN else Duelist.Team.SUN

func _reset_bomb() -> void:
	bomb_state = BombState.CARRIED
	bomb_plant_progress = 0.0
	bomb_defuse_progress = 0.0
	bomb_fuse_remaining = 0.0
	var attackers: Array = rosters[bomb_team]
	bomb_carrier_id = attackers[0].actor_id if not attackers.is_empty() else ""
	var carrier: Variant = _duelists_by_id.get(bomb_carrier_id, null)
	if carrier is Duelist:
		bomb_position = carrier.global_position

func _reset_nuke_rush() -> void:
	nuke_state = NukeState.AT_CENTER
	nuke_carrier_id = ""
	nuke_position = nuke_pickup_position
	nuke_time_remaining = NUKE_MATCH_SECONDS
	nuke_progress = {Duelist.Team.SUN: 0.0, Duelist.Team.VOID: 0.0}
	nuke_overtime = false

func _reset_duelists_to_spawns() -> void:
	for team in [Duelist.Team.SUN, Duelist.Team.VOID]:
		var roster: Array = rosters[team]
		var points: Array = spawn_points[team]
		for i in roster.size():
			var duelist: Variant = roster[i]
			if duelist is Duelist and points.size() > 0:
				duelist.respawn_at(points[posmod(i, points.size())])

func _on_defeated(victim: Duelist, killer: Duelist) -> void:
	if phase != Phase.LIVE or not _is_registered(victim) or not _is_registered(killer):
		return
	if killer == victim or killer.team == victim.team:
		return
	if mode == GameMode.DEATHMATCH:
		scores[killer.team] += 1
		score_changed.emit(scores[Duelist.Team.SUN], scores[Duelist.Team.VOID])
		_schedule_respawn(victim)
		if scores[killer.team] >= DM_SCORE_TO_WIN:
			_finish_match(killer.team)
	elif mode == GameMode.BOMB:
		_on_bomb_mode_defeat(victim)
	else:
		_on_nuke_rush_defeat(victim)

func _on_nuke_rush_defeat(victim: Duelist) -> void:
	if victim.actor_id == nuke_carrier_id and nuke_state == NukeState.CARRIED:
		nuke_state = NukeState.DROPPED
		nuke_carrier_id = ""
		nuke_position = victim.global_position
		objective_changed.emit(_objective_state())
		objective_event.emit("nuke_dropped", _objective_state())
	_schedule_respawn(victim)

func _on_bomb_mode_defeat(victim: Duelist) -> void:
	# If the carrier falls, the bomb drops at their position for a teammate to pick up.
	if victim.actor_id == bomb_carrier_id and bomb_state == BombState.CARRIED:
		bomb_state = BombState.ARMING
		bomb_carrier_id = ""
		bomb_position = victim.global_position
		objective_changed.emit(_objective_state())
		objective_event.emit("bomb_dropped", _objective_state())
		_hand_bomb_to_attacker()
	_check_team_wipe()

func _hand_bomb_to_attacker() -> void:
	var attackers: Array = rosters[bomb_team]
	for attacker in attackers:
		if attacker is Duelist and not attacker.eliminated:
			bomb_carrier_id = attacker.actor_id
			bomb_state = BombState.CARRIED
			return

func _check_team_wipe() -> void:
	if bomb_state == BombState.PLANTED:
		return
	var sun_alive := _living_count(Duelist.Team.SUN)
	var void_alive := _living_count(Duelist.Team.VOID)
	if sun_alive <= 0 and void_alive <= 0:
		_end_round(_other(bomb_team))
	elif sun_alive <= 0:
		_end_round(Duelist.Team.VOID)
	elif void_alive <= 0:
		_end_round(Duelist.Team.SUN)

func _tick_bomb(delta: float) -> void:
	match bomb_state:
		BombState.CARRIED:
			var carrier: Variant = _duelists_by_id.get(bomb_carrier_id, null)
			if carrier is Duelist:
				bomb_position = carrier.global_position
				if bool(_interact_held.get(bomb_carrier_id, false)) and _near_any_site(bomb_position):
					bomb_state = BombState.PLANTING
					bomb_plant_progress = 0.0
		BombState.PLANTING:
			var carrier: Variant = _duelists_by_id.get(bomb_carrier_id, null)
			if not (carrier is Duelist and not carrier.eliminated and bool(_interact_held.get(bomb_carrier_id, false)) and _near_any_site(carrier.global_position)):
				bomb_state = BombState.CARRIED
				bomb_plant_progress = 0.0
			else:
				bomb_plant_progress = minf(1.0, bomb_plant_progress + delta / BOMB_PLANT_SECONDS)
				if bomb_plant_progress >= 1.0:
					bomb_state = BombState.PLANTED
					bomb_fuse_remaining = BOMB_FUSE_SECONDS
					bomb_position = carrier.global_position
					objective_event.emit("bomb_planted", _objective_state())
		BombState.PLANTED:
			bomb_fuse_remaining = maxf(0.0, bomb_fuse_remaining - delta)
			_tick_defuse(delta)
			if bomb_fuse_remaining <= 0.0:
				bomb_state = BombState.DETONATED
				_end_round(bomb_team)
		BombState.ARMING:
			_hand_bomb_to_attacker()
	objective_changed.emit(_objective_state())

func _tick_nuke_rush(delta: float) -> void:
	nuke_time_remaining = maxf(0.0, nuke_time_remaining - delta)
	if nuke_state == NukeState.CARRIED:
		var carrier_value: Variant = _duelists_by_id.get(nuke_carrier_id, null)
		if not (carrier_value is Duelist) or (carrier_value as Duelist).eliminated:
			nuke_state = NukeState.DROPPED
			nuke_carrier_id = ""
			objective_event.emit("nuke_dropped", _objective_state())
		else:
			var carrier := carrier_value as Duelist
			nuke_carrier_team = carrier.team
			nuke_position = carrier.global_position + Vector3.UP * 0.9
			var enemy_base := _base_for_team(_other(carrier.team))
			var full_run := maxf(0.001, _flat_distance(nuke_pickup_position, enemy_base))
			var current_progress := clampf(1.0 - _flat_distance(carrier.global_position, enemy_base) / full_run, 0.0, 1.0)
			nuke_progress[carrier.team] = maxf(float(nuke_progress[carrier.team]), current_progress)
			if _flat_distance(carrier.global_position, enemy_base) <= NUKE_DELIVERY_RADIUS:
				_deliver_nuke(carrier.team)
				return
	elif nuke_state == NukeState.AT_CENTER or nuke_state == NukeState.DROPPED:
		var picker := _find_nuke_picker()
		if picker != null:
			nuke_state = NukeState.CARRIED
			nuke_carrier_id = picker.actor_id
			nuke_carrier_team = picker.team
			nuke_position = picker.global_position + Vector3.UP * 0.9
			objective_event.emit("nuke_picked_up", _objective_state())
	if nuke_time_remaining <= 0.0:
		_finish_nuke_timeout()
		return
	objective_changed.emit(_objective_state())

func _find_nuke_picker() -> Duelist:
	var nearest: Duelist
	var nearest_distance := NUKE_PICKUP_RADIUS
	for team in [Duelist.Team.SUN, Duelist.Team.VOID]:
		for candidate_value in rosters[team]:
			if not (candidate_value is Duelist):
				continue
			var candidate := candidate_value as Duelist
			if candidate.eliminated:
				continue
			var distance := _flat_distance(candidate.global_position, nuke_position)
			if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and (nearest == null or candidate.actor_id < nearest.actor_id)):
				nearest = candidate
				nearest_distance = distance
	return nearest

func _deliver_nuke(team: Duelist.Team) -> void:
	nuke_state = NukeState.DELIVERED
	nuke_progress[team] = 1.0
	scores[team] = 1
	score_changed.emit(scores[Duelist.Team.SUN], scores[Duelist.Team.VOID])
	objective_changed.emit(_objective_state())
	objective_event.emit("nuke_delivered", _objective_state())
	_finish_match(team)

func _finish_nuke_timeout() -> void:
	var sun_progress := float(nuke_progress[Duelist.Team.SUN])
	var void_progress := float(nuke_progress[Duelist.Team.VOID])
	if is_equal_approx(sun_progress, void_progress) and not nuke_overtime:
		nuke_overtime = true
		nuke_time_remaining = NUKE_OVERTIME_SECONDS
		objective_event.emit("nuke_overtime", _objective_state())
		objective_changed.emit(_objective_state())
		return
	var winner := Duelist.Team.SUN if sun_progress > void_progress else Duelist.Team.VOID
	if is_equal_approx(sun_progress, void_progress):
		winner = nuke_carrier_team
	scores[winner] = 1
	score_changed.emit(scores[Duelist.Team.SUN], scores[Duelist.Team.VOID])
	objective_event.emit("nuke_timeout", _objective_state())
	_finish_match(winner)

func _base_for_team(team: Duelist.Team) -> Vector3:
	var index := 0 if team == Duelist.Team.SUN else 1
	if index >= bomb_sites.size():
		return nuke_pickup_position
	return bomb_sites[index] as Vector3

func _flat_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

func _tick_defuse(delta: float) -> void:
	var defuser_id := _find_defuser()
	if defuser_id.is_empty():
		bomb_defuse_progress = 0.0
		return
	bomb_state = BombState.DEFUSING
	bomb_defuse_progress = minf(1.0, bomb_defuse_progress + delta / BOMB_DEFUSE_SECONDS)
	if bomb_defuse_progress >= 1.0:
		bomb_state = BombState.DEFUSED
		_end_round(_other(bomb_team))

func _find_defuser() -> String:
	var defenders: Array = rosters[_other(bomb_team)]
	for defender in defenders:
		if defender is Duelist and not defender.eliminated \
			and bool(_interact_held.get(defender.actor_id, false)) \
			and (defender.global_position - bomb_position).length() <= BOMB_DEFUSE_RADIUS:
			return defender.actor_id
	return ""

func _near_any_site(point: Vector3) -> bool:
	for site in bomb_sites:
		if (point - (site as Vector3)).length() <= BOMB_SITE_RADIUS:
			return true
	return false

func _end_round(winner: Duelist.Team) -> void:
	scores[winner] += 1
	score_changed.emit(scores[Duelist.Team.SUN], scores[Duelist.Team.VOID])
	objective_event.emit("round_won", _objective_state())
	if scores[winner] >= BOMB_ROUNDS_TO_WIN:
		_finish_match(winner)
	else:
		_intermission_remaining = INTERMISSION_SECONDS
		_set_phase(Phase.INTERMISSION)

func _finish_match(winner: Duelist.Team) -> void:
	_winner = winner
	_set_phase(Phase.FINISHED)
	match_finished.emit(winner)

func _schedule_respawn(victim: Duelist) -> void:
	var actor_id := victim.actor_id
	var generation := int(_respawn_generation.get(actor_id, 0)) + 1
	_respawn_generation[actor_id] = generation
	var round_generation := _round_generation
	await get_tree().create_timer(RESPAWN_DELAY_SECONDS).timeout
	if round_generation != _round_generation or generation != int(_respawn_generation.get(actor_id, -1)):
		return
	if phase != Phase.LIVE or not is_instance_valid(victim) or not victim.eliminated:
		return
	_respawn_duelist(victim)

func _respawn_duelist(victim: Duelist) -> void:
	var point := _pick_safe_spawn(victim)
	if point == Vector3.INF:
		return
	victim.respawn_at(point)
	respawn_started.emit(victim)

# Enemy-aware dynamic spawn: prefer the own-team point with the fewest live
# enemies inside the safe radius, breaking ties by greatest distance to the
# nearest enemy.  This is the "spawn where there are fewer enemies" rule.
func _pick_safe_spawn(victim: Duelist) -> Vector3:
	var points: Array = spawn_points[victim.team]
	if points.is_empty():
		return Vector3.INF
	var enemies := _living_duelists(_other(victim.team))
	var best_point: Vector3 = Vector3.INF
	var best_count := 999
	var best_distance := -1.0
	for point in points:
		var p: Vector3 = point as Vector3
		var nearby := 0
		var nearest: float = 1e9
		for enemy in enemies:
			var d: float = ((enemy as Duelist).global_position - p).length()
			if d <= DM_SAFE_SPAWN_RADIUS:
				nearby += 1
			nearest = minf(nearest, d)
		if nearby < best_count or (nearby == best_count and nearest > best_distance):
			best_count = nearby
			best_distance = nearest
			best_point = p
	return best_point

func _living_duelists(team: Duelist.Team) -> Array:
	var result: Array = []
	for duelist in rosters[team]:
		if duelist is Duelist and not duelist.eliminated:
			result.append(duelist)
	return result

func _living_count(team: Duelist.Team) -> int:
	return _living_duelists(team).size()

func _other(team: Duelist.Team) -> Duelist.Team:
	return Duelist.Team.VOID if team == Duelist.Team.SUN else Duelist.Team.SUN

func _is_registered(duelist: Duelist) -> bool:
	return duelist != null and rosters[duelist.team].has(duelist)

func _cancel_respawns() -> void:
	for key in _respawn_generation.keys():
		_respawn_generation[key] = int(_respawn_generation[key]) + 1

func _set_phase(next_phase: Phase) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	_set_duelists_active(phase == Phase.LIVE)
	phase_changed.emit(phase)

func _set_duelists_active(active: bool) -> void:
	for duelist in _duelists_by_id.values():
		if duelist is Duelist:
			(duelist as Duelist).set_match_active(active)

func _apply_objective_presentation(objective: Dictionary) -> void:
	if objective.is_empty():
		return
	if mode == GameMode.NUKE_RUSH:
		nuke_state = clampi(int(objective.get("nuke_state", int(nuke_state))), int(NukeState.AT_CENTER), int(NukeState.DELIVERED)) as NukeState
		nuke_carrier_id = str(objective.get("nuke_carrier_id", nuke_carrier_id))
		nuke_carrier_team = clampi(int(objective.get("nuke_carrier_team", int(nuke_carrier_team))), int(Duelist.Team.SUN), int(Duelist.Team.VOID)) as Duelist.Team
		nuke_position = objective.get("nuke_position", nuke_position) as Vector3
		nuke_time_remaining = float(objective.get("time_remaining", nuke_time_remaining))
		nuke_progress[Duelist.Team.SUN] = float(objective.get("sun_progress", nuke_progress[Duelist.Team.SUN]))
		nuke_progress[Duelist.Team.VOID] = float(objective.get("void_progress", nuke_progress[Duelist.Team.VOID]))
		nuke_overtime = bool(objective.get("overtime", nuke_overtime))
		return
	bomb_state = clampi(int(objective.get("bomb_state", int(bomb_state))), int(BombState.ARMING), int(BombState.DEFUSED)) as BombState
	bomb_team = int(objective.get("bomb_team", int(bomb_team))) as Duelist.Team
	bomb_carrier_id = str(objective.get("bomb_carrier_id", bomb_carrier_id))
	bomb_position = objective.get("bomb_position", bomb_position) as Vector3
	bomb_plant_progress = float(objective.get("plant_progress", bomb_plant_progress))
	bomb_defuse_progress = float(objective.get("defuse_progress", bomb_defuse_progress))
	bomb_fuse_remaining = float(objective.get("fuse_remaining", bomb_fuse_remaining))
