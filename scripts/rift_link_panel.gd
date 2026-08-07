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
	# One system accent for the whole flow. The old panel switched its entire
	# accent between amber and the BLUE team colour depending on view, which
	# read as "you are on blue team" rather than "you are searching".
	var accent := DuelHud.HUD_SIGNAL
	var panel := _panel_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(DuelHud.HUD_VOID, 0.9))
	DuelHud.draw_plate(self, panel, Color(DuelHud.HUD_INK, 0.99), Color(DuelHud.HUD_EDGE, 0.95), DuelHud.HUD_CUT, DuelHud.CHAMFER_DIAG, 1.2)
	DuelHud.draw_brackets(self, panel.grow(-7.0), Color(DuelHud.HUD_EDGE_BRIGHT, 0.5), 18.0, 1.6)
	DuelHud.draw_accent_edge(self, Rect2(panel.position + Vector2(DuelHud.HUD_CUT, 0.0), Vector2(panel.size.x - DuelHud.HUD_CUT, 3.0)), Color(accent, 0.9), false, 3.0)
	DuelHud.draw_tracked(self, panel.position + Vector2(34, 46), "RIFT LINK", DuelHud.FS_TITLE, DuelHud.HUD_TEXT, 3.2)
	DuelHud.draw_tracked(self, panel.position + Vector2(35, 64), "LOCAL RIFT" if not _squad_mode else "LOCAL SQUAD RIFT", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_DIM)
	_draw_status(panel, ThemeDB.fallback_font, accent)
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
		_draw_cancel(panel, ThemeDB.fallback_font)

func _draw_status(panel: Rect2, _font: Font, color: Color) -> void:
	# Status reads as a live telemetry line: a blinking carrier pip, the state,
	# and a rule running out to the panel edge.
	var pip := panel.position + Vector2(38, 104)
	var blink := 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse * 4.4))
	draw_circle(pip, 3.2, Color(color, blink))
	DuelHud.draw_tracked(self, panel.position + Vector2(50, 108), _status.to_upper(), DuelHud.FS_MICRO, Color(color, 0.98))
	var offset := 62.0 + DuelHud.tracked_width(DuelHud.hud_font(), _status.to_upper(), DuelHud.FS_MICRO)
	draw_line(panel.position + Vector2(offset, 104), panel.position + Vector2(panel.size.x - 36, 104), Color(DuelHud.HUD_EDGE, 0.9), 1.0)

func _draw_menu(panel: Rect2, color: Color) -> void:
	_draw_icon(panel.position + Vector2(panel.size.x * 0.5, 186), color, false)
	DuelHud.draw_tracked_centered(self, panel.position + Vector2(panel.size.x * 0.5, 254), "NEARBY DEVICES. ONE SHARED RIFT.", DuelHud.FS_SUB, DuelHud.HUD_TEXT, 2.6)
	DuelHud.draw_tracked_centered(self, panel.position + Vector2(panel.size.x * 0.5, 276), "LOCAL PLAY STAYS CLOSE TO THE AIR AROUND YOU.", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_DIM)
	_draw_action(_host_rect(), "OPEN LOCAL RIFT", color, true, "OPEN")
	_draw_action(_join_rect(), "FIND LOCAL RIFT", DuelHud.HUD_EDGE_BRIGHT, false, "SEEK")

func _draw_search(panel: Rect2, color: Color) -> void:
	_draw_icon(panel.position + Vector2(panel.size.x * 0.5, 186), color, _has_discovered_session)
	var title := "A LOCAL RIFT IS NEAR" if _has_discovered_session else "SEARCHING NEARBY RIFTS"
	var sub := "ENTER WHEN YOUR CREW IS READY" if _has_discovered_session else "LISTENING FOR A COMPATIBLE SESSION"
	DuelHud.draw_tracked_centered(self, panel.position + Vector2(panel.size.x * 0.5, 254), title, DuelHud.FS_SUB, DuelHud.HUD_TEXT, 2.6)
	DuelHud.draw_tracked_centered(self, panel.position + Vector2(panel.size.x * 0.5, 276), sub, DuelHud.FS_MICRO, Color(color, 0.92))
	_draw_action(_join_rect() if _has_discovered_session else _retry_rect(), "ENTER LOCAL RIFT" if _has_discovered_session else "SEARCH AGAIN", color, _has_discovered_session, "ENTER" if _has_discovered_session else "RETRY")

func _draw_staging(panel: Rect2, color: Color) -> void:
	var complete := bool(_state.get("complete", false))
	DuelHud.draw_tracked(self, panel.position + Vector2(36, 152), "CREW SIGNAL", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_FAINT)
	draw_line(panel.position + Vector2(126, 148), panel.position + Vector2(panel.size.x - 36, 148), Color(DuelHud.HUD_EDGE, 0.9), 1.0)
	_draw_crew(panel.position + Vector2(36, 186), panel.size.x - 72.0, color)
	var helper := "CREW SET - READY WHEN YOU ARE" if complete else "WAITING FOR THE CREW"
	DuelHud.draw_tracked(self, panel.position + Vector2(36, 306), helper, DuelHud.FS_BODY, DuelHud.HUD_TEXT, 2.2)
	if complete:
		_draw_action(_ready_rect(), "READY" if not _local_ready() else "MARKED READY", color, not _local_ready(), "READY")
	else:
		DuelHud.draw_tracked(self, panel.position + Vector2(36, 330), "THE RIFT OPENS WHEN EVERY CREW MEMBER IS PRESENT.", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_DIM)

func _draw_arming(panel: Rect2, color: Color) -> void:
	var center := panel.position + Vector2(panel.size.x * 0.5, panel.size.y * 0.50)
	var pulse := 0.5 + 0.34 * sin(_pulse * 5.2)
	# Two counter-rotating arcs inside an octagonal housing: a machine spinning
	# up, matching the octagonal control language used in the match HUD.
	DuelHud.draw_control_ring(self, center, 62.0, Color(DuelHud.HUD_VOID, 0.6), Color(color, 0.35), 1.4)
	draw_arc(center, 52.0, _pulse * 1.7, _pulse * 1.7 + PI * 1.1, 32, Color(color, 0.4 + pulse * 0.4), 3.0)
	draw_arc(center, 36.0, -_pulse * 2.4, -_pulse * 2.4 + PI * 1.3, 28, Color(color, 0.96), 3.0)
	DuelHud.draw_control_ring(self, center, 18.0, Color(color, 0.16 + pulse * 0.2), Color(color, 0.95), 1.6)
	DuelHud.draw_tracked_centered(self, center + Vector2(0, 104), "RIFT ARMING", DuelHud.FS_SUB, DuelHud.HUD_TEXT, 3.0)
	DuelHud.draw_tracked_centered(self, center + Vector2(0, 126), "HOLDING THE CREW TOGETHER", DuelHud.FS_MICRO, Color(color, 0.92))

func _draw_rematch(panel: Rect2, color: Color) -> void:
	DuelHud.draw_tracked(self, panel.position + Vector2(36, 158), "CREW REFORMING", DuelHud.FS_TITLE, DuelHud.HUD_TEXT, 3.0)
	DuelHud.draw_tracked(self, panel.position + Vector2(37, 180), "THE NEXT RIFT WAITS FOR EVERYONE.", DuelHud.FS_MICRO, Color(color, 0.92))
	_draw_crew(panel.position + Vector2(36, 232), panel.size.x - 72.0, color)
	_draw_action(_ready_rect(), "READY FOR REMATCH" if not _local_ready() else "REMATCH MARKED", color, not _local_ready(), "REMATCH")

func _draw_severed(panel: Rect2, color: Color) -> void:
	_draw_icon(panel.position + Vector2(panel.size.x * 0.5, 186), DuelHud.HUD_ALERT, true)
	DuelHud.draw_tracked_centered(self, panel.position + Vector2(panel.size.x * 0.5, 256), "RIFT SEVERED", DuelHud.FS_TITLE, DuelHud.HUD_TEXT, 3.2)
	DuelHud.draw_tracked_centered(self, panel.position + Vector2(panel.size.x * 0.5, 280), "THE LOCAL SESSION ENDED SAFELY.", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_DIM)
	_draw_action(_return_rect(), "RETURN TO TRAINING", color, true, "RETURN")

func _draw_action(rect: Rect2, label: String, color: Color, primary: bool, feedback_key: String) -> void:
	var feedback := _press_feedback == feedback_key and _feedback_remaining > 0.0
	var fill := Color(color, 0.34 if feedback else (0.16 if primary else 0.06))
	DuelHud.draw_plate(self, rect, fill, Color(color, 0.95 if primary else 0.5), DuelHud.HUD_CUT_SM, DuelHud.CHAMFER_DIAG, 1.6 if primary else 1.1)
	DuelHud.draw_accent_edge(self, rect, Color(color, 0.95 if primary else 0.45), true, 3.0)
	if primary:
		DuelHud.draw_brackets(self, rect.grow(-5.0), Color(color, 0.4), 12.0, 1.4)
	DuelHud.draw_tracked_centered(self, rect.get_center() + Vector2(3, 5), label, DuelHud.FS_BODY, DuelHud.HUD_TEXT if primary else DuelHud.HUD_TEXT_DIM, 2.6)

func _draw_cancel(_panel: Rect2, _font: Font) -> void:
	var rect := _cancel_rect()
	DuelHud.draw_plate(self, rect, Color(DuelHud.HUD_VOID, 0.7), Color(DuelHud.HUD_EDGE_BRIGHT, 0.6), DuelHud.HUD_CUT_SM, DuelHud.CHAMFER_DIAG, 1.0)
	DuelHud.draw_tracked_centered(self, rect.get_center() + Vector2(0, 5), "CANCEL", DuelHud.FS_LABEL, DuelHud.HUD_TEXT_DIM)

func _draw_icon(center: Vector2, color: Color, active: bool) -> void:
	# Link emblem: an octagonal housing with two facing brackets closing on a
	# bar - "two devices, one link" - lit when the link is real.
	DuelHud.draw_control_ring(self, center, 44.0, Color(color, 0.08 if not active else 0.16), Color(color, 0.4 if not active else 0.9), 1.8)
	draw_arc(center, 27.0, -1.1, 1.2, 16, Color(color, 0.9), 3.0)
	draw_arc(center, 27.0, 2.0, 4.3, 16, Color(color, 0.9), 3.0)
	draw_line(center + Vector2(-11, 0), center + Vector2(11, 0), Color(color, 0.98), 2.4)
	if active:
		DuelHud.draw_control_ring(self, center, 52.0, Color(0, 0, 0, 0), Color(color, 0.22 + 0.2 * (0.5 + 0.5 * sin(_pulse * 4.0))), 1.4)

## Crew slots as machined bays, one row per team. An empty bay is an outlined
## slot, a filled one is a solid plate in that team's colour, and a ready crew
## member gets an amber tick above the bay. RED and BLUE keep their existing
## meaning; only the shape language changed.
func _draw_crew(origin: Vector2, width: float, _color: Color) -> void:
	var rows := [Duelist.Team.RED, Duelist.Team.BLUE]
	var row_height := 50.0
	for row in rows.size():
		var team: Duelist.Team = rows[row]
		var team_color := DuelHud.HUD_TEAM_RED if team == Duelist.Team.RED else DuelHud.HUD_TEAM_BLUE
		var records := _team_records(team)
		var count := maxi(1, int(_state.get("team_size", 1)))
		# Team tag leads the row and the bays follow it, so an under-filled crew
		# does not leave the tag stranded at the far side of an empty rule.
		var bays_left := origin.x + 62.0
		var gap := minf(42.0, (width - 160.0) / float(count))
		var row_y := origin.y + row * row_height
		var tag := "RED" if team == Duelist.Team.RED else "BLUE"
		DuelHud.draw_tracked(self, Vector2(origin.x, row_y + 5.0), tag, DuelHud.FS_MICRO, Color(team_color, 0.95))
		var filled_count := mini(records.size(), count)
		DuelHud.draw_tracked(self, Vector2(bays_left + count * gap + 12.0, row_y + 5.0), "%d/%d" % [filled_count, count], DuelHud.FS_MICRO, DuelHud.HUD_TEXT_FAINT)
		draw_line(Vector2(origin.x, row_y + 22.0), Vector2(origin.x + width, row_y + 22.0), Color(DuelHud.HUD_EDGE, 0.5), 1.0)
		for index in count:
			var bay := Rect2(Vector2(bays_left + index * gap, row_y - 12.0), Vector2(28.0, 30.0))
			var record: Dictionary = records[index] if index < records.size() else {}
			var filled := not record.is_empty()
			var ready := filled and bool(record.get("ready", false))
			DuelHud.draw_plate(self, bay, Color(team_color, 0.72) if filled else Color(DuelHud.HUD_VOID, 0.65), Color(team_color, 0.95 if filled else 0.32), 5.0, DuelHud.CHAMFER_DIAG, 1.4 if filled else 1.0)
			if filled:
				# Occupied bays carry an operator mark, so a filled slot is a
				# person and not just a coloured rectangle.
				draw_circle(bay.get_center() + Vector2(0.0, -4.0), 3.4, Color(DuelHud.HUD_VOID, 0.72))
				draw_line(bay.get_center() + Vector2(-5.0, 6.0), bay.get_center() + Vector2(5.0, 6.0), Color(DuelHud.HUD_VOID, 0.72), 3.0)
			if ready:
				DuelHud.draw_tracked_centered(self, Vector2(bay.get_center().x, bay.position.y - 5.0), "RDY", 9, Color(DuelHud.HUD_SIGNAL, 0.98), DuelHud.HUD_TRACK_TIGHT)

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
