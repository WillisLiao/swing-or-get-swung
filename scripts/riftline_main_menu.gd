class_name RiftlineMainMenu
extends Control

## The true entry point and the destination of the settings panel's MAIN
## MENU action. Three top-level choices; picking one hands off to a class
## picker (RiftlineClassPanel) before RiftlineArena actually starts
## anything, and does not itself know about hosting/joining/bots - it only
## reports which the player picked.

signal create_game_requested
signal join_game_requested
signal drill_requested

## Visual language: the shared HUD design tokens and plate primitives live on
## `DuelHud` (see its "Design tokens" block). Every screen in the game reads
## them from there so the menu, the class picker, the lobby and the in-match
## HUD cannot drift into four different looks.
const RESPONSIVE := preload("res://scripts/riftline_responsive_layout.gd")

var _button_rects: Dictionary = {}
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_menu() -> void:
	visible = true
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var pressed := false
	var point := Vector2.ZERO
	if event is InputEventMouseButton:
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		point = event.position
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		point = event.position
	if pressed:
		for key in _button_rects.keys():
			if (_button_rects[key] as Rect2).has_point(point):
				_accept(str(key))
				accept_event()
				return

func _accept(key: String) -> void:
	match key:
		"create":
			visible = false
			create_game_requested.emit()
		"join":
			visible = false
			join_game_requested.emit()
		"drill":
			visible = false
			drill_requested.emit()

func _draw() -> void:
	if not visible:
		return
	_button_rects.clear()
	draw_rect(Rect2(Vector2.ZERO, size), DuelHud.HUD_VOID, true)
	var safe := RESPONSIVE.safe_rect(self)
	_draw_backdrop(safe)
	var left := safe.position.x + 26.0
	var top := maxf(safe.position.y + 96.0, safe.size.y * 0.26)

	# Title block: a team-neutral signal rule, the wordmark in tracked display
	# type, and the mode line as a technical tag underneath it.
	draw_rect(Rect2(Vector2(left, top - 44.0), Vector2(52.0, 3.0)), DuelHud.HUD_SIGNAL, true)
	DuelHud.draw_tracked(self, Vector2(left, top), "SWING OR GET SWUNG", DuelHud.FS_DISPLAY, DuelHud.HUD_TEXT, 4.0)
	DuelHud.draw_tracked(self, Vector2(left + 2.0, top + 24.0), "NUCLEAR RUSH  //  4V4  //  LOCAL LINK", DuelHud.FS_LABEL, DuelHud.HUD_TEXT_DIM)

	var button_width := minf(420.0, safe.size.x * 0.52)
	var button_height := 74.0
	var gap := 14.0
	var button_top := top + 62.0
	var entries := [
		{"key": "create", "label": "CREATE GAME", "note": "Host a LAN match for others to join.", "index": "01"},
		{"key": "join", "label": "JOIN GAME", "note": "Find a LAN match already hosted nearby.", "index": "02"},
		{"key": "drill", "label": "ENTER DRILL", "note": "Offline practice against bots.", "index": "03"},
	]
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var rect := Rect2(left, button_top + index * (button_height + gap), button_width, button_height)
		_register_button(str(entry.key), rect)
		_draw_entry(rect, str(entry.index), str(entry.label), str(entry.note), index == 0)

	DuelHud.draw_tracked(self, Vector2(left, safe.end.y - 16.0), "SOGS // BUILD 12 // MOBILE RENDERER", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_FAINT)

## The first entry is the primary action: amber leading edge, brighter plate,
## corner brackets. The other two are the same shape with the accent dropped
## to steel, so the hierarchy is carried by weight rather than by giving each
## button its own unrelated colour (the old menu was red / blue / green, which
## also collided with RED and BLUE meaning teams everywhere else).
func _draw_entry(rect: Rect2, ordinal: String, label: String, note: String, primary: bool) -> void:
	var accent: Color = DuelHud.HUD_SIGNAL if primary else DuelHud.HUD_EDGE_BRIGHT
	DuelHud.draw_plate(self, rect, Color(DuelHud.HUD_INK_RAISE if primary else DuelHud.HUD_INK, 0.94), Color(accent, 0.8 if primary else 0.5), DuelHud.HUD_CUT, DuelHud.CHAMFER_DIAG, 1.2)
	DuelHud.draw_accent_edge(self, rect, Color(accent, 0.95 if primary else 0.5), true, 3.0)
	if primary:
		DuelHud.draw_brackets(self, rect.grow(-6.0), Color(accent, 0.4), 13.0, 1.4)
	DuelHud.draw_tracked(self, rect.position + Vector2(20.0, 33.0), ordinal, DuelHud.FS_LABEL, Color(accent, 0.9), DuelHud.HUD_TRACK_TIGHT)
	DuelHud.draw_tracked(self, rect.position + Vector2(52.0, 34.0), label, DuelHud.FS_SUB, DuelHud.HUD_TEXT, 2.4)
	DuelHud.draw_body(self, rect.position + Vector2(53.0, 53.0), note, DuelHud.FS_LABEL, DuelHud.HUD_TEXT_DIM, rect.size.x - 90.0)
	# Trailing chevron: says "this goes somewhere" without a pill or an icon set.
	var mid := rect.position.y + rect.size.y * 0.5
	draw_polyline(PackedVector2Array([
		Vector2(rect.end.x - 26.0, mid - 6.0),
		Vector2(rect.end.x - 19.0, mid),
		Vector2(rect.end.x - 26.0, mid + 6.0),
	]), Color(accent, 0.9), 2.0)

## The right column is a mission brief, not decoration. There is exactly one
## mode and one map in this game, and a new player currently has nowhere to
## read the rules - so the space that would otherwise be an empty panel states
## them. Deliberately a spec list in the same technical register as the HUD.
const BRIEF_ROWS := [
	["MODE", "NUCLEAR RUSH"],
	["SQUAD", "4 V 4"],
	["ARENA", "CONCOURSE"],
	["CLOCK", "10:00"],
	["SCORE", "FIRST TO 3"],
	["INSTALL", "2.5S HOLD AT YOUR OWN PAD"],
	["LAUNCH", "25S COUNTDOWN, ENEMY CAN CANCEL"],
	["CARRY", "CORE COSTS SPEED, NOT HEALTH"],
]

func _draw_backdrop(safe: Rect2) -> void:
	var field := Rect2(
		Vector2(safe.position.x + safe.size.x * 0.56, safe.position.y + maxf(58.0, safe.size.y * 0.13)),
		Vector2(safe.size.x * 0.42, 0.0))
	field.size.y = minf(safe.end.y - field.position.y - 44.0, 62.0 + BRIEF_ROWS.size() * 26.0)
	DuelHud.draw_plate(self, field, Color(DuelHud.HUD_INK, 0.7), Color(DuelHud.HUD_EDGE, 0.7), DuelHud.HUD_CUT, DuelHud.CHAMFER_DIAG, 1.0)
	DuelHud.draw_brackets(self, field.grow(-6.0), Color(DuelHud.HUD_EDGE_BRIGHT, 0.4), 16.0, 1.4)
	DuelHud.draw_tracked(self, field.position + Vector2(20.0, 30.0), "MISSION BRIEF", DuelHud.FS_BODY, DuelHud.HUD_TEXT, 2.4)
	DuelHud.draw_rule(self, field.position + Vector2(20.0, 44.0), field.size.x - 40.0, Color(DuelHud.HUD_EDGE_BRIGHT, 0.75))
	var row_y := field.position.y + 68.0
	var value_x := field.position.x + 108.0
	for row in BRIEF_ROWS:
		if row_y > field.end.y - 8.0:
			break
		DuelHud.draw_tracked(self, Vector2(field.position.x + 20.0, row_y), str(row[0]), DuelHud.FS_MICRO, DuelHud.HUD_TEXT_FAINT)
		DuelHud.draw_tracked(self, Vector2(value_x, row_y), str(row[1]), DuelHud.FS_MICRO, DuelHud.HUD_TEXT_DIM)
		row_y += 26.0
	draw_line(safe.position + Vector2(0.0, -8.0), Vector2(safe.end.x, safe.position.y - 8.0), Color(DuelHud.HUD_EDGE, 0.6), 1.0)

func _register_button(key: String, rect: Rect2) -> void:
	_button_rects[key] = rect
