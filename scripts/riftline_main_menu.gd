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

const INK := Color("071126")
const PANEL := Color("0e1d38")
const PAPER := Color("f1f6ff")
const MUTED := Color("9bb2d1")
const RED := Color("ff6a57")
const BLUE := Color("75dbff")
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
	draw_rect(Rect2(Vector2.ZERO, size), INK, true)
	var safe := RESPONSIVE.safe_rect(self)
	var left := safe.position.x + 22.0
	var top := maxf(safe.position.y + 74.0, safe.size.y * 0.2)
	draw_string(_font, Vector2(left, top), "SWING OR GET SWUNG", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, PAPER)
	draw_string(_font, Vector2(left, top + 36.0), "Nuclear Rush - 4v4", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, MUTED)

	var button_width := minf(360.0, safe.size.x - 44.0)
	var button_height := 66.0
	var gap := 18.0
	var button_top := top + 90.0
	var entries := [
		{"key": "create", "label": "CREATE GAME", "note": "Host a LAN match for others to join.", "color": RED},
		{"key": "join", "label": "JOIN GAME", "note": "Find a LAN match already hosted nearby.", "color": BLUE},
		{"key": "drill", "label": "ENTER DRILL", "note": "Offline practice against bots.", "color": Color("8fd6a8")},
	]
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var rect := Rect2(left, button_top + index * (button_height + gap), button_width, button_height)
		_register_button(str(entry.key), rect)
		draw_rect(rect, PANEL, true)
		draw_rect(rect, Color(entry.color, 0.85), false, 2.0)
		draw_string(_font, rect.position + Vector2(24.0, 28.0), str(entry.label), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, PAPER)
		draw_string(_font, rect.position + Vector2(24.0, 50.0), str(entry.note), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0, 12, MUTED)

func _register_button(key: String, rect: Rect2) -> void:
	_button_rects[key] = rect
