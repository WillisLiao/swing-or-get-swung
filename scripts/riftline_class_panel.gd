class_name RiftlineClassPanel
extends Control

## Reused in two contexts: before entering a game (pre-game class pick) and
## on the death screen (post-death re-pick + respawn gate). It only ever
## reports a selection and a confirm/cancel tap - the caller (RiftlineArena)
## owns what "confirm" actually does (start a drill, host, join, or respawn).

signal selection_changed(player_class: int, primary_weapon: int)
signal confirmed
signal cancelled

const INK := Color("071126")
const PANEL := Color("0e1d38")
const PAPER := Color("f1f6ff")
const MUTED := Color("9bb2d1")
const RED := Color("ff6a57")
const BLUE := Color("75dbff")
const GREEN := Color("7dffb0")
const RESPONSIVE := preload("res://scripts/riftline_responsive_layout.gd")

const CLASS_ORDER := [Duelist.PlayerClass.FRONTLINE, Duelist.PlayerClass.SNIPER, Duelist.PlayerClass.RUNNER, Duelist.PlayerClass.SHIELD]
const CLASS_LABELS := {
	Duelist.PlayerClass.FRONTLINE: "FRONTLINE",
	Duelist.PlayerClass.SNIPER: "SNIPER",
	Duelist.PlayerClass.RUNNER: "RUNNER",
	Duelist.PlayerClass.SHIELD: "SHIELD",
}
const CLASS_BLURBS := {
	Duelist.PlayerClass.FRONTLINE: "AR / SMG / shotgun + pistol",
	Duelist.PlayerClass.SNIPER: "Sniper rifle + pistol",
	Duelist.PlayerClass.RUNNER: "Pistol only. Wears the nuclear vest.",
	Duelist.PlayerClass.SHIELD: "Pistol only. Carries a ballistic shield.",
}
const PRIMARY_ORDER := [Duelist.Weapon.RIFLE, Duelist.Weapon.SMG, Duelist.Weapon.SHOTGUN]
const PRIMARY_LABELS := {
	Duelist.Weapon.RIFLE: "AR",
	Duelist.Weapon.SMG: "SMG",
	Duelist.Weapon.SHOTGUN: "SHOTGUN",
}

var _selected_class: Duelist.PlayerClass = Duelist.PlayerClass.FRONTLINE
var _selected_primary: Duelist.Weapon = Duelist.Weapon.RIFLE
var _title := "CHOOSE YOUR CLASS"
var _cta_label := "CONFIRM"
var _cta_enabled := true
var _cta_note := ""
var _show_cancel := false
var _button_rects: Dictionary = {}
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## `initial_class`/`initial_primary` seed the picker with whatever the caller
## already has selected (the local duelist's current loadout, or the
## previous pending choice) so reopening it doesn't silently reset a pick.
func configure(title: String, cta_label: String, show_cancel: bool, initial_class: Duelist.PlayerClass, initial_primary: Duelist.Weapon) -> void:
	_title = title
	_cta_label = cta_label
	_show_cancel = show_cancel
	_selected_class = initial_class
	_selected_primary = initial_primary if initial_primary in PRIMARY_ORDER else Duelist.Weapon.RIFLE
	_cta_enabled = true
	_cta_note = ""
	visible = true
	queue_redraw()

## Called every frame by the caller while a respawn timer is counting down,
## so the CTA button can be disabled/labeled until eligible.
func set_cta_state(enabled: bool, note: String = "") -> void:
	if _cta_enabled == enabled and _cta_note == note:
		return
	_cta_enabled = enabled
	_cta_note = note
	queue_redraw()

func selected_class() -> Duelist.PlayerClass:
	return _selected_class

func selected_primary() -> Duelist.Weapon:
	return _selected_primary

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
	if key == "cancel":
		cancelled.emit()
		return
	if key == "cta":
		if _cta_enabled:
			confirmed.emit()
		return
	if key.begins_with("class:"):
		_selected_class = int(key.trim_prefix("class:")) as Duelist.PlayerClass
		selection_changed.emit(int(_selected_class), int(_selected_primary))
		queue_redraw()
		return
	if key.begins_with("primary:"):
		_selected_primary = int(key.trim_prefix("primary:")) as Duelist.Weapon
		selection_changed.emit(int(_selected_class), int(_selected_primary))
		queue_redraw()
		return

func _draw() -> void:
	if not visible:
		return
	_button_rects.clear()
	draw_rect(Rect2(Vector2.ZERO, size), INK, true)
	var safe := RESPONSIVE.safe_rect(self)
	var left := safe.position.x + 22.0
	var top := maxf(safe.position.y + 48.0, safe.size.y * 0.1)
	draw_string(_font, Vector2(left, top), _title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, PAPER)
	draw_string(_font, Vector2(left, top + 30.0), "Four classes. Loadout follows automatically.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)

	var gap := 16.0
	var card_width := minf(300.0, (safe.size.x - 44.0 - gap * 3.0) / 4.0)
	var card_height := 168.0
	var cards_top := top + 62.0
	var start_x := safe.position.x + maxf(22.0, (safe.size.x - card_width * 4.0 - gap * 3.0) * 0.5)
	for index in CLASS_ORDER.size():
		var player_class: int = CLASS_ORDER[index]
		var rect := Rect2(start_x + index * (card_width + gap), cards_top, card_width, card_height)
		var held := int(_selected_class) == player_class
		_register_button("class:%d" % player_class, rect)
		draw_rect(rect, PANEL, true)
		draw_rect(rect, Color(RED if held else BLUE, 0.9 if held else 0.28), false, 2.0 if held else 1.0)
		draw_string(_font, rect.position + Vector2(16.0, 34.0), str(CLASS_LABELS.get(player_class, "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, PAPER if held else MUTED)
		draw_string(_font, rect.position + Vector2(16.0, 64.0), str(CLASS_BLURBS.get(player_class, "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32.0, 12, MUTED)
		if held:
			draw_string(_font, rect.position + Vector2(16.0, rect.size.y - 16.0), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, RED)

	var primary_top := cards_top + card_height + 22.0
	if _selected_class == Duelist.PlayerClass.FRONTLINE:
		draw_string(_font, Vector2(left, primary_top), "PRIMARY WEAPON", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, MUTED)
		var chip_width := 130.0
		var chip_height := 44.0
		for index in PRIMARY_ORDER.size():
			var weapon: int = PRIMARY_ORDER[index]
			var rect := Rect2(left + index * (chip_width + 12.0), primary_top + 16.0, chip_width, chip_height)
			var held := int(_selected_primary) == weapon
			_register_button("primary:%d" % weapon, rect)
			draw_rect(rect, PANEL, true)
			draw_rect(rect, Color(GREEN if held else BLUE, 0.9 if held else 0.28), false, 2.0 if held else 1.0)
			draw_string(_font, rect.get_center() + Vector2(-22.0, 5.0), str(PRIMARY_LABELS.get(weapon, "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, PAPER)

	var cta_y := safe.end.y - 96.0
	var cta_rect := Rect2(left, cta_y, 260.0, 58.0)
	_register_button("cta", cta_rect)
	var cta_color := RED if _cta_enabled else Color(MUTED, 0.35)
	draw_rect(cta_rect, cta_color, true)
	draw_string(_font, cta_rect.get_center() + Vector2(-float(_cta_label.length()) * 4.0, 6.0), _cta_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, INK if _cta_enabled else Color(PAPER, 0.6))
	if not _cta_note.is_empty():
		draw_string(_font, Vector2(cta_rect.end.x + 18.0, cta_y + 34.0), _cta_note, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)
	if _show_cancel:
		var cancel_rect := Rect2(safe.end.x - 162.0, safe.end.y - 62.0, 140.0, 52.0)
		_register_button("cancel", cancel_rect)
		draw_rect(cancel_rect, PANEL, true)
		draw_string(_font, cancel_rect.get_center() + Vector2(-24.0, 5.0), "BACK", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, PAPER)

func _register_button(key: String, rect: Rect2) -> void:
	_button_rects[key] = rect
