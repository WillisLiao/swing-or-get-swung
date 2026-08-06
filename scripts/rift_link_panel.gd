class_name RiftLinkPanel
extends Control

const RESPONSIVE := preload("res://scripts/riftline_responsive_layout.gd")

signal host_requested
signal join_requested
signal cancel_requested
signal retry_requested
signal ready_requested(ready: bool)
signal rematch_requested

enum View { MENU, HOST_STAGING, JOIN_SEARCH, JOIN_STAGING, ARMING, REMATCH, SEVERED }

const MIN_ACTION_HEIGHT := 52.0
const OUTER_MARGIN := 48.0

var _view: View = View.MENU
var _status := "CHOOSE A LOCAL LINK"
var _has_discovered_session := false
var _press_feedback := ""
var _feedback_remaining := 0.0
var _squad_mode := false
var _state: Dictionary = {}
var _local_actor_id := ""
var _local_is_host := false
var _preview_name := ""
var _pulse := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _process(delta: float) -> void:
	_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
	_pulse += delta
	if _feedback_remaining <= 0.0:
		_press_feedback = ""
	queue_redraw()

func open_menu() -> void:
	_view = View.MENU
	_status = "CHOOSE A LOCAL LINK"
	_has_discovered_session = false
	_state.clear()
	_preview_name = ""
	visible = true
	queue_redraw()

func show_host() -> void:
	_view = View.HOST_STAGING
	_status = "CREW INCOMPLETE"
	_local_is_host = true
	visible = true
	queue_redraw()

func show_join() -> void:
	_view = View.JOIN_SEARCH
	_status = "SEARCHING NEARBY RIFTS"
	_local_is_host = false
	visible = true
	queue_redraw()

func hide_panel() -> void:
	visible = false

func set_status(status: String) -> void:
	_status = status
	if status == "RIFT FOUND":
		_has_discovered_session = true
	queue_redraw()

func set_squad_mode(enabled: bool) -> void:
	_squad_mode = enabled
	queue_redraw()

func set_discovered_session(found: bool) -> void:
	_has_discovered_session = found
	if found:
		_status = "A LOCAL RIFT IS NEAR"
	queue_redraw()

func set_local_actor(actor_id: String, is_host: bool) -> void:
	_local_actor_id = actor_id
	_local_is_host = is_host

func set_lobby_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	_state = state.duplicate(true)
	_squad_mode = int(state.get("team_size", 1)) > 1
	var phase := int(state.get("phase", RiftlineLobby.Phase.STAGING))
	match phase:
		RiftlineLobby.Phase.ARMING:
			_view = View.ARMING
			_status = "RIFT ARMING"
		RiftlineLobby.Phase.REMATCH:
			_view = View.REMATCH
			_status = "CREW REFORMING"
		RiftlineLobby.Phase.ABANDONED:
			_view = View.SEVERED
			_status = "RIFT SEVERED"
		RiftlineLobby.Phase.LIVE:
			_view = View.ARMING
			_status = "RIFT LIVE"
		_:
			_view = View.HOST_STAGING if _local_is_host else View.JOIN_STAGING
			_status = _staging_status()
	visible = true
	queue_redraw()

func show_severed(reason: String = "RIFT SEVERED") -> void:
	_view = View.SEVERED
	_status = reason if not reason.is_empty() else "RIFT SEVERED"
	visible = true
	queue_redraw()

func apply_preview(name: String) -> void:
	_preview_name = name
	_local_is_host = name.begins_with("host") or name == "arming" or name == "rematch" or name == "severed"
	visible = true
	var state := _preview_state(name)
	if not state.is_empty():
		set_lobby_state(state)
	match name:
		"menu": open_menu()
		"join-searching": show_join()
		"join-found":
			show_join()
			set_discovered_session(true)
		"host-empty", "host-crew", "host-ready":
			_local_is_host = true
			set_lobby_state(state)
		"squad-crew":
			_local_is_host = true
			set_lobby_state(state)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_tap(event.position)

func _handle_tap(point: Vector2) -> void:
	if _cancel_rect().grow(10.0).has_point(point):
		_press_feedback = "CANCEL"
		_feedback_remaining = 0.2
		cancel_requested.emit()
		return
	match _view:
		View.MENU:
			if _host_rect().has_point(point):
				_press_feedback = "OPEN"
				_feedback_remaining = 0.2
				host_requested.emit()
			elif _join_rect().has_point(point):
				_press_feedback = "SEEK"
				_feedback_remaining = 0.2
				join_requested.emit()
		View.JOIN_SEARCH:
			if _has_discovered_session and _join_rect().has_point(point):
				_press_feedback = "ENTER"
				_feedback_remaining = 0.2
				join_requested.emit()
			elif not _has_discovered_session and _retry_rect().has_point(point):
				_press_feedback = "RETRY"
				_feedback_remaining = 0.2
				retry_requested.emit()
		View.HOST_STAGING, View.JOIN_STAGING:
			if _ready_rect().has_point(point) and bool(_state.get("complete", false)):
				_press_feedback = "READY"
				_feedback_remaining = 0.2
				ready_requested.emit(not _local_ready())
		View.REMATCH:
			if _ready_rect().has_point(point):
				_press_feedback = "REMATCH"
				_feedback_remaining = 0.2
				rematch_requested.emit()
		View.SEVERED:
			if _return_rect().has_point(point):
				_press_feedback = "RETURN"
				_feedback_remaining = 0.2
				cancel_requested.emit()

func _draw() -> void:
	var safe := _safe_rect()
	var accent := Color("ffad5d") if _view != View.JOIN_SEARCH and _view != View.JOIN_STAGING else Color("71cfff")
	var panel := Rect2(safe.position + Vector2(OUTER_MARGIN, 34), Vector2(safe.size.x - OUTER_MARGIN * 2.0, safe.size.y - 68))
	draw_rect(Rect2(Vector2.ZERO, size), Color("020612", 0.88))
	draw_rect(panel, Color("09162d", 0.98))
	draw_line(panel.position, panel.position + Vector2(panel.size.x, 0), accent, 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(34, 42), "RIFT LINK", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f1f6ff"))
	draw_string(font, panel.position + Vector2(36, 70), "LOCAL RIFT" if not _squad_mode else "LOCAL SQUAD RIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a9bfe2"))
	_draw_status(panel, font, accent)
	match _view:
		View.MENU:
			_draw_menu(panel, accent)
		View.HOST_STAGING, View.JOIN_STAGING:
			_draw_staging(panel, accent)
		View.JOIN_SEARCH:
			_draw_search(panel, accent)
		View.ARMING:
			_draw_arming(panel, accent)
		View.REMATCH:
			_draw_rematch(panel, accent)
		View.SEVERED:
			_draw_severed(panel, accent)
	if _view != View.MENU and _view != View.SEVERED:
		_draw_cancel(panel, font)

func _draw_status(panel: Rect2, font: Font, color: Color) -> void:
	draw_string(font, panel.position + Vector2(36, 108), _status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	draw_line(panel.position + Vector2(36, 120), panel.position + Vector2(panel.size.x - 36, 120), Color("20375d"), 1.0)

func _draw_menu(panel: Rect2, color: Color) -> void:
	_draw_icon(panel.position + Vector2(panel.size.x * 0.5, 190), color, false)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(0, 250), "NEARBY DEVICES. ONE SHARED RIFT.", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 17, Color("f1f6ff"))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(0, 278), "LOCAL PLAY STAYS CLOSE TO THE AIR AROUND YOU.", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 12, Color("a9bfe2"))
	_draw_action(_host_rect(), "OPEN LOCAL RIFT", color, true, "OPEN")
	_draw_action(_join_rect(), "FIND LOCAL RIFT", Color("71cfff"), false, "SEEK")

func _draw_search(panel: Rect2, color: Color) -> void:
	_draw_icon(panel.position + Vector2(panel.size.x * 0.5, 190), color, _has_discovered_session)
	var title := "A LOCAL RIFT IS NEAR" if _has_discovered_session else "SEARCHING NEARBY RIFTS"
	var sub := "ENTER WHEN YOUR CREW IS READY" if _has_discovered_session else "LISTENING FOR A COMPATIBLE SESSION"
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(0, 250), title, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 19, Color("f1f6ff"))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(0, 278), sub, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 12, Color(color, 0.92))
	_draw_action(_join_rect() if _has_discovered_session else _retry_rect(), "ENTER LOCAL RIFT" if _has_discovered_session else "SEARCH AGAIN", color, _has_discovered_session, "ENTER" if _has_discovered_session else "RETRY")

func _draw_staging(panel: Rect2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(36, 164), "CREW SIGNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a9bfe2"))
	_draw_crew(panel.position + Vector2(36, 196), panel.size.x - 72.0, color)
	var helper := "CREW SET. READY WHEN SET." if bool(_state.get("complete", false)) else "WAITING FOR THE CREW"
	draw_string(font, panel.position + Vector2(36, 318), helper, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f1f6ff"))
	if bool(_state.get("complete", false)):
		_draw_action(_ready_rect(), "READY" if not _local_ready() else "MARKED READY", color, not _local_ready(), "READY")
	else:
		draw_string(font, panel.position + Vector2(36, 370), "THE RIFT OPENS WHEN EVERY CREW MEMBER IS PRESENT.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a9bfe2"))

func _draw_arming(panel: Rect2, color: Color) -> void:
	var center := panel.position + Vector2(panel.size.x * 0.5, panel.size.y * 0.53)
	var pulse := 0.56 + 0.28 * sin(_pulse * 5.2)
	draw_circle(center, 58.0, Color(color, 0.08))
	draw_arc(center, 58.0, -PI * 0.7, PI * 0.7, 32, Color(color, pulse), 3.0)
	draw_arc(center, 36.0, PI * 0.3, PI * 1.7, 24, Color(color, 0.96), 3.0)
	draw_line(center + Vector2(-13, 0), center + Vector2(13, 0), color, 2.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-120, 102), "RIFT ARMING", HORIZONTAL_ALIGNMENT_CENTER, 240, 20, Color("f1f6ff"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-200, 128), "HOLDING THE CREW TOGETHER", HORIZONTAL_ALIGNMENT_CENTER, 400, 12, Color(color, 0.92))

func _draw_rematch(panel: Rect2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(36, 164), "CREW REFORMING", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("f1f6ff"))
	draw_string(font, panel.position + Vector2(36, 194), "THE NEXT RIFT WAITS FOR EVERYONE.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(color, 0.92))
	_draw_crew(panel.position + Vector2(36, 236), panel.size.x - 72.0, color)
	_draw_action(_ready_rect(), "READY FOR REMATCH" if not _local_ready() else "REMATCH MARKED", color, not _local_ready(), "REMATCH")

func _draw_severed(panel: Rect2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	_draw_icon(panel.position + Vector2(panel.size.x * 0.5, 190), color, true)
	draw_string(font, panel.position + Vector2(0, 252), "RIFT SEVERED", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 22, Color("f1f6ff"))
	draw_string(font, panel.position + Vector2(0, 282), "THE LOCAL SESSION ENDED SAFELY.", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 13, Color(color, 0.92))
	_draw_action(_return_rect(), "RETURN TO TRAINING", color, true, "RETURN")

func _draw_action(rect: Rect2, label: String, color: Color, primary: bool, feedback_key: String) -> void:
	var feedback := _press_feedback == feedback_key and _feedback_remaining > 0.0
	draw_rect(rect, Color(color, 0.24 if primary else 0.1) if not feedback else Color(color, 0.4), true)
	draw_rect(rect, Color(color, 0.96), false, 2.0)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, rect.get_center() + Vector2(-width * 0.5, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)

func _draw_cancel(panel: Rect2, font: Font) -> void:
	draw_rect(_cancel_rect(), Color("101f3a", 0.7), true)
	draw_rect(_cancel_rect(), Color("7890b2", 0.8), false, 1.2)
	draw_string(font, _cancel_rect().get_center() + Vector2(-32, 5), "CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b6c9e8"))

func _draw_icon(center: Vector2, color: Color, active: bool) -> void:
	draw_circle(center, 42.0, Color(color, 0.12 if not active else 0.22))
	draw_arc(center, 42.0, 0.0, TAU, 32, Color(color, 0.46 if not active else 0.94), 2.0)
	draw_arc(center, 26.0, -1.1, 1.2, 16, color, 3.0)
	draw_arc(center, 26.0, 2.0, 4.3, 16, color, 3.0)
	draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), color, 2.0)

func _draw_crew(origin: Vector2, width: float, color: Color) -> void:
	var rows := [Duelist.Team.RED, Duelist.Team.BLUE]
	var row_height := 48.0
	for row in rows.size():
		var team: Duelist.Team = rows[row]
		var team_color := Color("ff6a57") if team == Duelist.Team.RED else Color("71cfff")
		var records := _team_records(team)
		var count := maxi(1, int(_state.get("team_size", 1)))
		var gap := minf(42.0, (width - 24.0) / float(count))
		for index in count:
			var center := origin + Vector2(index * gap + 18.0, row * row_height)
			var record: Dictionary = records[index] if index < records.size() else {}
			var filled := not record.is_empty()
			var ready := filled and bool(record.get("ready", false))
			if team == Duelist.Team.RED:
				draw_colored_polygon(PackedVector2Array([center + Vector2(0, -11), center + Vector2(11, 0), center + Vector2(0, 11), center + Vector2(-11, 0)]), Color(team_color, 0.88 if filled else 0.08))
				draw_polyline(PackedVector2Array([center + Vector2(0, -11), center + Vector2(11, 0), center + Vector2(0, 11), center + Vector2(-11, 0), center + Vector2(0, -11)]), Color(team_color, 0.95), 2.0)
			else:
				draw_circle(center, 10.0, Color(team_color, 0.82 if filled else 0.08))
				draw_arc(center, 10.0, 0.0, TAU, 20, Color(team_color, 0.95), 2.0)
			if ready:
				draw_arc(center, 16.0, -PI * 0.82, -PI * 0.18, 12, Color("f1f6ff", 0.96), 2.0)
		draw_string(ThemeDB.fallback_font, origin + Vector2(width - 64.0, row * row_height + 5.0), "RED" if team == Duelist.Team.RED else "BLUE", HORIZONTAL_ALIGNMENT_RIGHT, 64, 11, Color(team_color, 0.86))

func _team_records(team: Duelist.Team) -> Array:
	var result: Array = []
	for record in _state.get("records", []):
		if int(record.get("team", -1)) == int(team):
			result.append(record)
	return result

func _local_ready() -> bool:
	for record in _state.get("records", []):
		if str(record.get("actor_id", "")) == _local_actor_id:
			return bool(record.get("ready", false))
	return false

func _staging_status() -> String:
	if not bool(_state.get("complete", false)):
		return "CREW INCOMPLETE"
	return "MARKED READY" if _local_ready() else "CREW SET. READY WHEN SET."

func _preview_state(name: String) -> Dictionary:
	var team_size := 1
	var records: Array[Dictionary] = []
	var phase := RiftlineLobby.Phase.STAGING
	var complete := false
	match name:
		"host-empty":
			records = [{"actor_id": "host", "team": int(Duelist.Team.RED), "human": true, "ready": false}]
			_local_actor_id = "host"
		"host-crew":
			records = [{"actor_id": "host", "team": int(Duelist.Team.RED), "human": true, "ready": false}, {"actor_id": "peer", "team": int(Duelist.Team.BLUE), "human": true, "ready": false}]
			_local_actor_id = "host"
			complete = true
		"host-ready":
			records = [{"actor_id": "host", "team": int(Duelist.Team.RED), "human": true, "ready": true}, {"actor_id": "peer", "team": int(Duelist.Team.BLUE), "human": true, "ready": false}]
			_local_actor_id = "host"
			complete = true
		"arming":
			phase = RiftlineLobby.Phase.ARMING
			records = [{"actor_id": "host", "team": int(Duelist.Team.RED), "human": true, "ready": true}, {"actor_id": "peer", "team": int(Duelist.Team.BLUE), "human": true, "ready": true}]
			_local_actor_id = "host"
			complete = true
		"rematch":
			phase = RiftlineLobby.Phase.REMATCH
			records = [{"actor_id": "host", "team": int(Duelist.Team.RED), "human": true, "ready": true}, {"actor_id": "peer", "team": int(Duelist.Team.BLUE), "human": true, "ready": false}]
			_local_actor_id = "host"
			complete = true
		"severed":
			phase = RiftlineLobby.Phase.ABANDONED
			_local_actor_id = "host"
		"squad-crew":
			team_size = 4
			complete = true
			_local_actor_id = "peer_1"
			for index in team_size:
				records.append({"actor_id": "peer_%d" % index, "team": int(Duelist.Team.RED), "human": true, "ready": index == 1})
				records.append({"actor_id": "peer_%d" % (index + team_size), "team": int(Duelist.Team.BLUE), "human": true, "ready": index == 2})
		_:
			return {}
	# No `arena_id`/`arena_name`: there is one map, so the lobby state no longer
	# carries a map field and nothing downstream reads one.
	return {"phase": phase, "team_size": team_size, "records": records, "revision": 4, "complete": complete, "launchable": false}

func _host_rect() -> Rect2:
	var panel := _panel_rect()
	return Rect2(panel.position + Vector2(82, _action_stack_top()), Vector2(panel.size.x - 164, MIN_ACTION_HEIGHT))

func _join_rect() -> Rect2:
	var panel := _panel_rect()
	return Rect2(panel.position + Vector2(82, _action_stack_top() + 64), Vector2(panel.size.x - 164, MIN_ACTION_HEIGHT))

func _retry_rect() -> Rect2:
	return _host_rect()

func _ready_rect() -> Rect2:
	var panel := _panel_rect()
	return Rect2(panel.position + Vector2(82, panel.size.y - 124), Vector2(panel.size.x - 164, MIN_ACTION_HEIGHT))

func _return_rect() -> Rect2:
	return _ready_rect()

func _cancel_rect() -> Rect2:
	var panel := _panel_rect()
	return Rect2(panel.position + Vector2(82, panel.size.y - 60), Vector2(panel.size.x - 164, 44))

func _action_stack_top() -> float:
	return maxf(0.0, _panel_rect().size.y - 188.0)

func _panel_rect() -> Rect2:
	var safe := _safe_rect()
	return Rect2(safe.position + Vector2(OUTER_MARGIN, 34), Vector2(safe.size.x - OUTER_MARGIN * 2.0, safe.size.y - 68))

func _safe_rect() -> Rect2:
	return RESPONSIVE.safe_rect(self)
