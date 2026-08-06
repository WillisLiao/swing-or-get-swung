extends RefCounted

# A small, tick-ordered presentation timeline for one remote duelist.
# The caller owns lifecycle resets; this module owns ordering and interpolation.
const SERVER_HZ := 20.0
const INTERPOLATION_TICKS := 2.5
const MAX_HISTORY := 12
const MAX_EXTRAPOLATION_SECONDS := 0.12

var _snapshots: Array[Dictionary] = []

func clear() -> void:
	_snapshots.clear()

func push(state: Dictionary, host_tick: int, arrival_time: float) -> void:
	if state.is_empty() or host_tick < 0:
		return
	var copy := state.duplicate(true)
	copy["_tick"] = host_tick
	copy["_arrival"] = arrival_time
	for index in _snapshots.size():
		var existing_tick := int(_snapshots[index]["_tick"])
		if host_tick == existing_tick:
			_snapshots[index] = copy
			return
		if host_tick < existing_tick:
			_snapshots.insert(index, copy)
			while _snapshots.size() > MAX_HISTORY:
				_snapshots.pop_front()
			return
	_snapshots.append(copy)
	while _snapshots.size() > MAX_HISTORY:
		_snapshots.pop_front()

func sample(now: float) -> Dictionary:
	if _snapshots.is_empty():
		return {}
	var latest: Dictionary = _snapshots[-1]
	var target_tick := float(latest["_tick"]) - INTERPOLATION_TICKS
	if target_tick <= float(_snapshots[0]["_tick"]):
		return _clean_state(_snapshots[0])
	for index in range(1, _snapshots.size()):
		var newer: Dictionary = _snapshots[index]
		if target_tick <= float(newer["_tick"]):
			var older: Dictionary = _snapshots[index - 1]
			var span := float(newer["_tick"]) - float(older["_tick"])
			var weight := 1.0 if span <= 0.0 else clampf((target_tick - float(older["_tick"])) / span, 0.0, 1.0)
			return _interpolate(older, newer, weight)
	if now - float(latest["_arrival"]) > MAX_EXTRAPOLATION_SECONDS:
		return _clean_state(latest)
	var elapsed := clampf(now - float(latest["_arrival"]), 0.0, MAX_EXTRAPOLATION_SECONDS)
	return _extrapolate(latest, elapsed)

func _interpolate(older: Dictionary, newer: Dictionary, weight: float) -> Dictionary:
	var result := newer.duplicate(true)
	result["position"] = _vector3(older.get("position", Vector3.ZERO)).lerp(_vector3(newer.get("position", Vector3.ZERO)), weight)
	result["velocity"] = _vector3(older.get("velocity", Vector3.ZERO)).lerp(_vector3(newer.get("velocity", Vector3.ZERO)), weight)
	result["yaw"] = lerp_angle(float(older.get("yaw", 0.0)), float(newer.get("yaw", 0.0)), weight)
	result["pitch"] = lerpf(float(older.get("pitch", 0.0)), float(newer.get("pitch", 0.0)), weight)
	result["health"] = lerpf(float(older.get("health", 100.0)), float(newer.get("health", 100.0)), weight)
	result["stance"] = int(older.get("stance", newer.get("stance", 0))) if weight < 0.5 else int(newer.get("stance", older.get("stance", 0)))
	result["weapon"] = int(older.get("weapon", newer.get("weapon", 0))) if weight < 0.5 else int(newer.get("weapon", older.get("weapon", 0)))
	result["eliminated"] = bool(older.get("eliminated", false)) if weight < 0.5 else bool(newer.get("eliminated", false))
	# Discrete combat and objective facts must never be blended between actors'
	# timeline samples.  Position and aim interpolate; these values take newest.
	for key in ["last_input", "magazine_rounds", "reserve_ammo", "reload_remaining", "carrying_seed"]:
		if newer.has(key):
			result[key] = newer[key]
	return _clean_state(result)

func _extrapolate(latest: Dictionary, elapsed: float) -> Dictionary:
	var result := _clean_state(latest)
	result["position"] = _vector3(latest.get("position", Vector3.ZERO)) + _vector3(latest.get("velocity", Vector3.ZERO)) * elapsed
	return result

func _clean_state(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("_tick")
	result.erase("_arrival")
	return result

func _vector3(value: Variant) -> Vector3:
	return value if value is Vector3 else Vector3.ZERO
