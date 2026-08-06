class_name MobileTouchRouter
extends RefCounted

## Deep input-ownership module for the two-thumb mobile contract.
## The caller rejects explicit action controls before entering this interface.

enum Role { NONE, MOVE, LOOK }
enum StickMode { FLOATING, FIXED }

var _stick_mode := StickMode.FLOATING
var _fixed_origin := Vector2.ZERO
var _fixed_radius := 58.0
var _move_touch := -1
var _look_touch := -1
var _movement := Vector2.ZERO
var _look_delta := Vector2.ZERO
var _stick_origin := Vector2.ZERO
var _stick_knob := Vector2.ZERO

func configure(stick_mode: StickMode, fixed_origin: Vector2, fixed_radius: float) -> void:
	_stick_mode = stick_mode
	_fixed_origin = fixed_origin
	_fixed_radius = maxf(1.0, fixed_radius)
	if _move_touch < 0:
		_stick_origin = _fixed_origin
		_stick_knob = _fixed_origin

func begin(touch_id: int, point: Vector2, movement_region: Rect2, stick_radius: float) -> Role:
	if _move_touch == touch_id or _look_touch == touch_id:
		return active_role(touch_id)
	var radius := maxf(1.0, stick_radius)
	var role := Role.NONE
	if _stick_mode == StickMode.FIXED:
		if _move_touch < 0 and point.distance_to(_fixed_origin) <= _fixed_radius + 20.0:
			role = Role.MOVE
	else:
		if _move_touch < 0 and movement_region.has_point(point):
			role = Role.MOVE
	if role == Role.MOVE:
		_move_touch = touch_id
		_stick_origin = _clamp_origin(point, movement_region, radius) if _stick_mode == StickMode.FLOATING else _fixed_origin
		_stick_knob = _stick_origin
		_movement = Vector2.ZERO
		return role
	if _look_touch < 0 and not movement_region.has_point(point):
		_look_touch = touch_id
		return Role.LOOK
	return Role.NONE

func drag(touch_id: int, point: Vector2, relative: Vector2) -> void:
	if touch_id == _move_touch:
		var radius := maxf(1.0, _fixed_radius if _stick_mode == StickMode.FIXED else _stick_radius_for_origin())
		_stick_knob = _stick_origin + (point - _stick_origin).limit_length(radius)
		_movement = (_stick_knob - _stick_origin) / radius
	elif touch_id == _look_touch:
		_look_delta += relative

func end(touch_id: int) -> void:
	if touch_id == _move_touch:
		_move_touch = -1
		_movement = Vector2.ZERO
		_stick_knob = _stick_origin
	if touch_id == _look_touch:
		_look_touch = -1

func reset() -> void:
	_move_touch = -1
	_look_touch = -1
	_movement = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_stick_origin = _fixed_origin
	_stick_knob = _fixed_origin

func movement() -> Vector2:
	return _movement

func take_look_delta() -> Vector2:
	var result := _look_delta
	_look_delta = Vector2.ZERO
	return result

func stick_origin() -> Vector2:
	return _stick_origin

func stick_knob() -> Vector2:
	return _stick_knob

func active_role(touch_id: int) -> Role:
	if touch_id == _move_touch:
		return Role.MOVE
	if touch_id == _look_touch:
		return Role.LOOK
	return Role.NONE

func has_movement_owner() -> bool:
	return _move_touch >= 0

func has_look_owner() -> bool:
	return _look_touch >= 0

var _last_floating_radius := 58.0

func _clamp_origin(point: Vector2, region: Rect2, radius: float) -> Vector2:
	_last_floating_radius = radius
	var min_x := region.position.x + radius
	var max_x := region.end.x - radius
	var min_y := region.position.y + radius
	var max_y := region.end.y - radius
	return Vector2(
		clampf(point.x, min_x, max_x) if min_x <= max_x else region.get_center().x,
		clampf(point.y, min_y, max_y) if min_y <= max_y else region.get_center().y)

func _stick_radius_for_origin() -> float:
	return _last_floating_radius
