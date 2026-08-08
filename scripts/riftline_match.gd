class_name RiftlineMatch
extends Node

# Authoritative rules for Nuclear Rush, the only game mode.  A single core
# spawns at the map center; each team must carry it back to their OWN launch
# pad and hold a launch countdown against a hold-to-cancel defense.  The
# match is one continuous clock with no rounds and no base swap.  The host
# runs this simulation; clients receive authoritative_state() snapshots and
# feed them through apply_replica_state().

signal score_changed(red: int, blue: int)
signal phase_changed(phase: Phase)
signal match_finished(winner: Duelist.Team)
signal objective_changed(state: Dictionary)
signal objective_event(event_type: String, state: Dictionary)
signal respawn_started(victim: Duelist)
signal combat_stats_changed(state: Dictionary)

enum Phase { OPENING, LIVE, SUDDEN_DEATH, FINISHED }
enum GameMode { NUCLEAR_RUSH }
enum CoreState { AT_CENTER, CARRIED, DROPPED, INSTALLED, RESPAWNING }

const OPENING_HOLD_SECONDS := 2.5
# The minimum time a player is dead before they may respawn. Unlike the old
# instant/auto respawn, reaching this minimum does not respawn them by
# itself - it only unlocks the respawn action (see can_respawn/
# request_respawn), giving the death screen's class picker somewhere to sit.
const RESPAWN_MIN_SECONDS := 5.0
const SAFE_SPAWN_RADIUS := 9.0
const MATCH_SECONDS := 600.0
const POINTS_TO_WIN := 3
const CORE_PICKUP_RADIUS := 2.0
const CORE_INSTALL_RADIUS := 3.0
const CORE_INSTALL_SECONDS := 2.5
const LAUNCH_COUNTDOWN_SECONDS := 25.0
const LAUNCH_CANCEL_SECONDS := 3.0
const LAUNCH_CANCEL_RADIUS := 3.0
const CORE_DROP_RETURN_SECONDS := 15.0
const CORE_RESPAWN_DELAY_SECONDS := 4.0

var mode: GameMode = GameMode.NUCLEAR_RUSH
var rosters: Dictionary = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
var scores: Dictionary = {Duelist.Team.RED: 0, Duelist.Team.BLUE: 0}
var spawn_points: Dictionary = {Duelist.Team.RED: [], Duelist.Team.BLUE: []}
var launch_pads: Dictionary = {}
var core_spawn := Vector3.ZERO
var phase: Phase = Phase.OPENING
var core_state: CoreState = CoreState.AT_CENTER
var core_position := Vector3.ZERO
var core_carrier_id := ""
var core_carrier_team: Duelist.Team = Duelist.Team.RED
var installed_team: Duelist.Team = Duelist.Team.RED
var install_progress := 0.0
var cancel_progress := 0.0
var launch_remaining := 0.0
var drop_return_remaining := 0.0
var core_respawn_remaining := 0.0
var match_remaining := MATCH_SECONDS
var sudden_death := false

var _presentation_enabled := false
var _duelists_by_id: Dictionary = {}
## Seconds each currently-eliminated actor has been dead, ticked in
## _physics_process. Presence in this dict (rather than a bool) is also what
## `_is_registered`/`can_respawn` use to know someone is mid-death.
var _respawn_elapsed: Dictionary = {}
var _opening_remaining := 0.0
var _started := false
var _winner: Duelist.Team = Duelist.Team.RED
var _last_replica_tick := -1
var _interact_held: Dictionary = {}
var _combat_stats: Dictionary = {}

func configure(pads: Dictionary, core_spawn_position: Vector3, presentation_enabled: bool) -> void:
	launch_pads = pads.duplicate()
	core_spawn = core_spawn_position
	_presentation_enabled = presentation_enabled
	mode = GameMode.NUCLEAR_RUSH

func add_spawn(team: Duelist.Team, point: Vector3) -> void:
	spawn_points[team].append(point)

func register_duelist(duelist: Duelist, actor_id: String) -> void:
	if not is_instance_valid(duelist) or actor_id.is_empty():
		return
	duelist.set_actor_id(actor_id)
	_ensure_combat_stats(actor_id)
	if duelist in rosters[duelist.team]:
		_duelists_by_id[actor_id] = duelist
		return
	rosters[duelist.team].append(duelist)
	_duelists_by_id[actor_id] = duelist
	duelist.defeated.connect(_on_defeated)

func unregister_duelist(actor_id: String) -> void:
	var duelist: Variant = _duelists_by_id.get(actor_id, null)
	if not duelist is Duelist:
		return
	if actor_id == core_carrier_id:
		_drop_core((duelist as Duelist).global_position)
	if duelist in rosters[(duelist as Duelist).team]:
		rosters[(duelist as Duelist).team].erase(duelist)
	_duelists_by_id.erase(actor_id)
	_respawn_elapsed.erase(actor_id)
	_interact_held.erase(actor_id)
	if rosters[Duelist.Team.RED].is_empty() or rosters[Duelist.Team.BLUE].is_empty():
		_started = false
		_cancel_respawns()
		_set_phase(Phase.OPENING)

func begin() -> void:
	if _started:
		return
	_started = true
	_start_match()

func is_live() -> bool:
	return phase == Phase.LIVE or phase == Phase.SUDDEN_DEATH

func take_rematch() -> bool:
	if phase != Phase.FINISHED:
		return false
	_start_match()
	return true

func set_interact(actor_id: String, held: bool) -> void:
	_interact_held[actor_id] = held

func authoritative_state() -> Dictionary:
	return {
		"phase": int(phase),
		"mode": int(mode),
		"red_score": int(scores[Duelist.Team.RED]),
		"blue_score": int(scores[Duelist.Team.BLUE]),
		"objective": objective_state(),
		"combat_stats": combat_stats_state(),
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
	mode = clampi(int(snapshot.get("mode", int(mode))), int(GameMode.NUCLEAR_RUSH), int(GameMode.NUCLEAR_RUSH)) as GameMode
	var next_red := int(snapshot.get("red_score", scores[Duelist.Team.RED]))
	var next_blue := int(snapshot.get("blue_score", scores[Duelist.Team.BLUE]))
	var score_changed_locally := next_red != int(scores[Duelist.Team.RED]) or next_blue != int(scores[Duelist.Team.BLUE])
	scores[Duelist.Team.RED] = next_red
	scores[Duelist.Team.BLUE] = next_blue
	var objective: Dictionary = snapshot.get("objective", {})
	_apply_objective_presentation(objective)
	var incoming_stats: Variant = snapshot.get("combat_stats", null)
	if incoming_stats is Dictionary:
		_apply_replica_combat_stats(incoming_stats as Dictionary)
	if phase_changed_locally:
		_set_phase(phase)
	if score_changed_locally:
		score_changed.emit(scores[Duelist.Team.RED], scores[Duelist.Team.BLUE])

func objective_state() -> Dictionary:
	return {
		"mode": int(mode),
		"core_state": int(core_state),
		"core_position": core_position,
		"core_carrier_id": core_carrier_id,
		"core_carrier_team": int(core_carrier_team),
		"installed_team": int(installed_team),
		"install_progress": install_progress,
		"cancel_progress": cancel_progress,
		"launch_remaining": launch_remaining,
		"match_remaining": match_remaining,
		"sudden_death": sudden_death,
	}

func combat_stats_for(actor_id: String) -> Dictionary:
	var row_value: Variant = _combat_stats.get(actor_id, {})
	if not row_value is Dictionary:
		return {"kills": 0, "deaths": 0}
	var row := row_value as Dictionary
	return {
		"kills": maxi(0, int(row.get("kills", 0))),
		"deaths": maxi(0, int(row.get("deaths", 0))),
	}

func combat_stats_state() -> Dictionary:
	var snapshot: Dictionary = {}
	for actor_id_value: Variant in _combat_stats.keys():
		var actor_id := str(actor_id_value)
		if actor_id.is_empty():
			continue
		snapshot[actor_id] = combat_stats_for(actor_id)
	return snapshot

func _physics_process(delta: float) -> void:
	if not _started:
		return
	if phase == Phase.OPENING:
		_opening_remaining = maxf(0.0, _opening_remaining - delta)
		if _opening_remaining <= 0.0:
			_set_phase(Phase.LIVE)
		return
	if phase == Phase.LIVE:
		match_remaining = maxf(0.0, match_remaining - delta)
	if phase == Phase.LIVE or phase == Phase.SUDDEN_DEATH:
		_tick_core(delta)
		_tick_respawn_timers(delta)
		if phase == Phase.LIVE and match_remaining <= 0.0:
			_on_clock_expired()

func _tick_respawn_timers(delta: float) -> void:
	var ready_bots: Array[String] = []
	for actor_id_value: Variant in _respawn_elapsed.keys():
		var actor_id := str(actor_id_value)
		var elapsed := float(_respawn_elapsed[actor_id]) + delta
		_respawn_elapsed[actor_id] = elapsed
		var duelist: Variant = _duelists_by_id.get(actor_id, null)
		if elapsed >= RESPAWN_MIN_SECONDS and duelist is BotDuelist:
			ready_bots.append(actor_id)
	# request_respawn() erases from _respawn_elapsed, so defer these calls
	# until after dictionary iteration. Human actors still use the death-screen
	# button; only bots auto-request once the same authoritative gate opens.
	for actor_id: String in ready_bots:
		request_respawn(actor_id)

func _start_match() -> void:
	_opening_remaining = OPENING_HOLD_SECONDS
	scores[Duelist.Team.RED] = 0
	scores[Duelist.Team.BLUE] = 0
	match_remaining = MATCH_SECONDS
	sudden_death = false
	_cancel_respawns()
	_reset_combat_stats()
	_reset_duelists_to_spawns()
	_reset_core()
	_set_phase(Phase.OPENING)
	objective_changed.emit(objective_state())

func _reset_core() -> void:
	core_state = CoreState.AT_CENTER
	core_position = core_spawn
	core_carrier_id = ""
	install_progress = 0.0
	cancel_progress = 0.0
	launch_remaining = 0.0
	drop_return_remaining = 0.0
	core_respawn_remaining = 0.0

func _reset_duelists_to_spawns() -> void:
	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		var roster: Array = rosters[team]
		var points: Array = spawn_points[team]
		for i in roster.size():
			var duelist: Variant = roster[i]
			if duelist is Duelist:
				(duelist as Duelist).set_carrying_core(false)
				if points.size() > 0:
					(duelist as Duelist).respawn_at(points[posmod(i, points.size())])

func _on_defeated(victim: Duelist, killer: Duelist) -> void:
	if not is_live() or not _is_registered(victim):
		return
	_record_defeat(victim, killer)
	if victim.actor_id == core_carrier_id and core_state == CoreState.CARRIED:
		_drop_core(victim.global_position)
	_begin_death(victim)

func _ensure_combat_stats(actor_id: String) -> void:
	if actor_id.is_empty() or _combat_stats.has(actor_id):
		return
	_combat_stats[actor_id] = {"kills": 0, "deaths": 0}

func _reset_combat_stats() -> void:
	_combat_stats.clear()
	for actor_id_value: Variant in _duelists_by_id.keys():
		_ensure_combat_stats(str(actor_id_value))
	combat_stats_changed.emit(combat_stats_state())

func _record_defeat(victim: Duelist, killer: Duelist) -> void:
	_ensure_combat_stats(victim.actor_id)
	var victim_row: Dictionary = combat_stats_for(victim.actor_id)
	victim_row["deaths"] = int(victim_row.get("deaths", 0)) + 1
	_combat_stats[victim.actor_id] = victim_row
	if killer != null and is_instance_valid(killer) and _is_registered(killer) and killer != victim and killer.team != victim.team:
		_ensure_combat_stats(killer.actor_id)
		var killer_row: Dictionary = combat_stats_for(killer.actor_id)
		killer_row["kills"] = int(killer_row.get("kills", 0)) + 1
		_combat_stats[killer.actor_id] = killer_row
	combat_stats_changed.emit(combat_stats_state())

func _apply_replica_combat_stats(incoming: Dictionary) -> void:
	var next_stats: Dictionary = {}
	for actor_id_value: Variant in incoming.keys():
		var actor_id := str(actor_id_value)
		var row_value: Variant = incoming.get(actor_id_value, {})
		if actor_id.is_empty() or not row_value is Dictionary:
			continue
		var row := row_value as Dictionary
		next_stats[actor_id] = {
			"kills": maxi(0, int(row.get("kills", 0))),
			"deaths": maxi(0, int(row.get("deaths", 0))),
		}
	if next_stats == _combat_stats:
		return
	_combat_stats = next_stats
	combat_stats_changed.emit(combat_stats_state())

func _tick_core(delta: float) -> void:
	var changed := false
	match core_state:
		CoreState.AT_CENTER:
			changed = _try_pickup(core_spawn) or changed
		CoreState.CARRIED:
			changed = _tick_carried(delta) or changed
		CoreState.DROPPED:
			changed = _tick_dropped(delta) or changed
		CoreState.INSTALLED:
			changed = _tick_installed(delta) or changed
		CoreState.RESPAWNING:
			changed = _tick_respawning(delta) or changed
	if changed:
		objective_changed.emit(objective_state())

func _try_pickup(at_point: Vector3) -> bool:
	var picker: Duelist = _nearest_living_within(at_point, CORE_PICKUP_RADIUS)
	if picker == null:
		return false
	core_state = CoreState.CARRIED
	core_carrier_id = picker.actor_id
	core_carrier_team = picker.team
	core_position = picker.global_position
	picker.set_carrying_core(true)
	objective_event.emit("core_picked_up", objective_state())
	return true

func _nearest_living_within(at_point: Vector3, radius: float) -> Duelist:
	var best: Duelist = null
	var best_distance := radius
	for team in [Duelist.Team.RED, Duelist.Team.BLUE]:
		for duelist in rosters[team]:
			if not (duelist is Duelist) or (duelist as Duelist).eliminated:
				continue
			var d := (duelist as Duelist).global_position
			var distance := d.distance_to(at_point)
			if distance > radius:
				continue
			if best == null or distance < best_distance or \
				(is_equal_approx(distance, best_distance) and (duelist as Duelist).actor_id < best.actor_id):
				best = duelist as Duelist
				best_distance = distance
	return best

func _tick_carried(delta: float) -> bool:
	var carrier: Variant = _duelists_by_id.get(core_carrier_id, null)
	if not (carrier is Duelist) or (carrier as Duelist).eliminated:
		_drop_core(core_position)
		return true
	var d := carrier as Duelist
	core_position = d.global_position
	if not launch_pads.has(core_carrier_team):
		if install_progress != 0.0:
			install_progress = 0.0
			return true
		return false
	var own_pad: Vector3 = launch_pads[core_carrier_team]
	var within := core_position.distance_to(own_pad) <= CORE_INSTALL_RADIUS
	var holding := bool(_interact_held.get(core_carrier_id, false))
	if within and holding:
		install_progress = minf(1.0, install_progress + delta / CORE_INSTALL_SECONDS)
		if install_progress >= 1.0:
			_install_core(own_pad)
		return true
	if install_progress != 0.0:
		install_progress = 0.0
		return true
	return false

func _install_core(pad_position: Vector3) -> void:
	var d: Variant = _duelists_by_id.get(core_carrier_id, null)
	if d is Duelist:
		(d as Duelist).set_carrying_core(false)
	core_state = CoreState.INSTALLED
	installed_team = core_carrier_team
	core_position = pad_position
	core_carrier_id = ""
	install_progress = 0.0
	cancel_progress = 0.0
	launch_remaining = LAUNCH_COUNTDOWN_SECONDS
	objective_event.emit("core_installed", objective_state())

func _drop_core(at_point: Vector3) -> void:
	var d: Variant = _duelists_by_id.get(core_carrier_id, null)
	if d is Duelist:
		(d as Duelist).set_carrying_core(false)
	core_state = CoreState.DROPPED
	core_position = at_point
	core_carrier_id = ""
	install_progress = 0.0
	drop_return_remaining = CORE_DROP_RETURN_SECONDS
	objective_event.emit("core_dropped", objective_state())

func _tick_dropped(delta: float) -> bool:
	if _try_pickup(core_position):
		return true
	drop_return_remaining = maxf(0.0, drop_return_remaining - delta)
	if drop_return_remaining <= 0.0:
		core_state = CoreState.AT_CENTER
		core_position = core_spawn
		objective_event.emit("core_returned", objective_state())
		return true
	return false

func _tick_installed(delta: float) -> bool:
	if not launch_pads.has(installed_team):
		return false
	var pad: Vector3 = launch_pads[installed_team]
	var defending_team := _other(installed_team)
	var cancelling := false
	for duelist in rosters[defending_team]:
		if not (duelist is Duelist) or (duelist as Duelist).eliminated:
			continue
		var d := duelist as Duelist
		if d.global_position.distance_to(pad) <= LAUNCH_CANCEL_RADIUS and bool(_interact_held.get(d.actor_id, false)):
			cancelling = true
			break
	if cancelling:
		cancel_progress = minf(1.0, cancel_progress + delta / LAUNCH_CANCEL_SECONDS)
	elif cancel_progress != 0.0:
		cancel_progress = 0.0
	if cancel_progress >= 1.0:
		objective_event.emit("launch_cancelled", objective_state())
		_begin_respawning()
		return true
	launch_remaining = maxf(0.0, launch_remaining - delta)
	if launch_remaining <= 0.0:
		var winner := installed_team
		scores[winner] += 1
		score_changed.emit(scores[Duelist.Team.RED], scores[Duelist.Team.BLUE])
		objective_event.emit("launch_complete", objective_state())
		if scores[winner] >= POINTS_TO_WIN:
			_finish_match(winner)
			return true
		if sudden_death:
			_finish_match(winner)
			return true
		_begin_respawning()
		return true
	return true

func _begin_respawning() -> void:
	core_state = CoreState.RESPAWNING
	core_respawn_remaining = CORE_RESPAWN_DELAY_SECONDS
	install_progress = 0.0
	cancel_progress = 0.0
	launch_remaining = 0.0

func _tick_respawning(delta: float) -> bool:
	core_respawn_remaining = maxf(0.0, core_respawn_remaining - delta)
	if core_respawn_remaining <= 0.0:
		core_state = CoreState.AT_CENTER
		core_position = core_spawn
		objective_event.emit("core_returned", objective_state())
		return true
	return false

func _on_clock_expired() -> void:
	var red: int = scores[Duelist.Team.RED]
	var blue: int = scores[Duelist.Team.BLUE]
	if red != blue:
		_finish_match(Duelist.Team.RED if red > blue else Duelist.Team.BLUE)
	else:
		sudden_death = true
		_set_phase(Phase.SUDDEN_DEATH)

func _finish_match(winner: Duelist.Team) -> void:
	_winner = winner
	_set_phase(Phase.FINISHED)
	match_finished.emit(winner)

func _begin_death(victim: Duelist) -> void:
	_respawn_elapsed[victim.actor_id] = 0.0

## True once an eliminated actor has cleared the minimum death time and may
## respawn. False for an actor who isn't currently tracked as dead at all
## (already alive, or never registered) as well as one still waiting it out.
func can_respawn(actor_id: String) -> bool:
	return _respawn_elapsed.has(actor_id) and float(_respawn_elapsed[actor_id]) >= RESPAWN_MIN_SECONDS

## Seconds still owed on the minimum death timer, 0 once respawn-eligible.
func respawn_seconds_remaining(actor_id: String) -> float:
	if not _respawn_elapsed.has(actor_id):
		return 0.0
	return maxf(0.0, RESPAWN_MIN_SECONDS - float(_respawn_elapsed[actor_id]))

## The respawn action itself - unlike the old auto-respawn, this only ever
## fires from an explicit request (the death screen's Respawn button), never
## on a timer alone. Returns false (a no-op) if it's not actually eligible
## yet, so a stray/late client request can't jump the queue.
func request_respawn(actor_id: String) -> bool:
	if not can_respawn(actor_id):
		return false
	var victim: Variant = _duelists_by_id.get(actor_id, null)
	if not victim is Duelist or not is_instance_valid(victim) or not (victim as Duelist).eliminated:
		return false
	if not is_live():
		return false
	_respawn_elapsed.erase(actor_id)
	_respawn_duelist(victim as Duelist)
	return true

func _respawn_duelist(victim: Duelist) -> void:
	var point := _pick_safe_spawn(victim)
	if point == Vector3.INF:
		return
	victim.respawn_at(point)
	# The LAN host turns this into a `spawn` event for remote clients. Without it
	# a respawn is invisible to every other device in the match.
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
			if d <= SAFE_SPAWN_RADIUS:
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

func _other(team: Duelist.Team) -> Duelist.Team:
	return Duelist.Team.BLUE if team == Duelist.Team.RED else Duelist.Team.RED

func _is_registered(duelist: Duelist) -> bool:
	return duelist != null and rosters[duelist.team].has(duelist)

func _cancel_respawns() -> void:
	_respawn_elapsed.clear()

func _set_phase(next_phase: Phase) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	_set_duelists_active(is_live())
	phase_changed.emit(phase)

func _set_duelists_active(active: bool) -> void:
	for duelist in _duelists_by_id.values():
		if duelist is Duelist:
			(duelist as Duelist).set_match_active(active)

func _apply_objective_presentation(objective: Dictionary) -> void:
	if objective.is_empty():
		return
	core_state = clampi(int(objective.get("core_state", int(core_state))), int(CoreState.AT_CENTER), int(CoreState.RESPAWNING)) as CoreState
	core_position = objective.get("core_position", core_position) as Vector3
	core_carrier_id = str(objective.get("core_carrier_id", core_carrier_id))
	core_carrier_team = int(objective.get("core_carrier_team", int(core_carrier_team))) as Duelist.Team
	installed_team = int(objective.get("installed_team", int(installed_team))) as Duelist.Team
	install_progress = float(objective.get("install_progress", install_progress))
	cancel_progress = float(objective.get("cancel_progress", cancel_progress))
	launch_remaining = float(objective.get("launch_remaining", launch_remaining))
	match_remaining = float(objective.get("match_remaining", match_remaining))
	sudden_death = bool(objective.get("sudden_death", sudden_death))
