class_name RiftlineClassPanel
extends Control

## Reused in two contexts: before entering a game (pre-game class pick) and
## on the death screen (post-death re-pick + respawn gate). It only ever
## reports a selection and a confirm/cancel tap - the caller (RiftlineArena)
## owns what "confirm" actually does (start a drill, host, join, or respawn).

signal selection_changed(player_class: int, primary_weapon: int)
signal confirmed
signal cancelled

## Shares the game-wide design tokens and plate primitives defined on
## `DuelHud`; see the note there. Selection state is signalled with the system
## accent (amber), never with RED/BLUE - those two mean team identity
## everywhere else in this game and must not be spent on "this card is picked".
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
	draw_rect(Rect2(Vector2.ZERO, size), DuelHud.HUD_VOID, true)
	var safe := RESPONSIVE.safe_rect(self)
	var left := safe.position.x + 26.0
	var top := maxf(safe.position.y + 54.0, safe.size.y * 0.11)
	draw_rect(Rect2(Vector2(left, top - 30.0), Vector2(44.0, 3.0)), DuelHud.HUD_SIGNAL, true)
	DuelHud.draw_tracked(self, Vector2(left, top), _title.to_upper(), DuelHud.FS_TITLE, DuelHud.HUD_TEXT, 3.0)
	DuelHud.draw_tracked(self, Vector2(left + 1.0, top + 20.0), "LOADOUT RESOLVES FROM CLASS AUTOMATICALLY", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_DIM)
	DuelHud.draw_rule(self, Vector2(left, top + 34.0), safe.size.x - 52.0, Color(DuelHud.HUD_EDGE_BRIGHT, 0.7))

	var gap := 14.0
	var card_width := minf(300.0, (safe.size.x - 52.0 - gap * 3.0) / 4.0)
	var card_height := 138.0
	var cards_top := top + 52.0
	var start_x := safe.position.x + maxf(26.0, (safe.size.x - card_width * 4.0 - gap * 3.0) * 0.5)
	for index in CLASS_ORDER.size():
		var player_class: int = CLASS_ORDER[index]
		var rect := Rect2(start_x + index * (card_width + gap), cards_top, card_width, card_height)
		_register_button("class:%d" % player_class, rect)
		_draw_class_card(rect, player_class, int(_selected_class) == player_class)

	var primary_top := cards_top + card_height + 26.0
	if _selected_class == Duelist.PlayerClass.FRONTLINE:
		DuelHud.draw_tracked(self, Vector2(left, primary_top), "PRIMARY WEAPON", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_FAINT)
		var chip_width := 130.0
		var chip_height := 44.0
		for index in PRIMARY_ORDER.size():
			var weapon: int = PRIMARY_ORDER[index]
			var rect := Rect2(left + index * (chip_width + 10.0), primary_top + 14.0, chip_width, chip_height)
			var held := int(_selected_primary) == weapon
			_register_button("primary:%d" % weapon, rect)
			DuelHud.draw_plate(self, rect, Color(DuelHud.HUD_INK_RAISE if held else DuelHud.HUD_INK, 0.92), Color(DuelHud.HUD_SIGNAL if held else DuelHud.HUD_EDGE_BRIGHT, 0.9 if held else 0.45), DuelHud.HUD_CUT_SM, DuelHud.CHAMFER_DIAG, 1.4 if held else 1.0)
			if held:
				DuelHud.draw_accent_edge(self, rect, Color(DuelHud.HUD_SIGNAL, 0.95), true, 3.0)
			DuelHud.draw_tracked_centered(self, rect.get_center() + Vector2(2.0, 5.0), str(PRIMARY_LABELS.get(weapon, "")), DuelHud.FS_LABEL, DuelHud.HUD_TEXT if held else DuelHud.HUD_TEXT_DIM)

	# A rule and a one-line prompt tie the bottom action band to the content
	# above it, instead of leaving the CTA marooned in empty space.
	DuelHud.draw_rule(self, Vector2(left, safe.end.y - 112.0), safe.size.x - 52.0, Color(DuelHud.HUD_EDGE, 0.8))
	DuelHud.draw_tracked(self, Vector2(left, safe.end.y - 96.0), "CONFIRM TO DEPLOY WITH THIS LOADOUT", DuelHud.FS_MICRO, DuelHud.HUD_TEXT_FAINT)
	var cta_y := safe.end.y - 80.0
	var cta_rect := Rect2(left, cta_y, 268.0, 54.0)
	_register_button("cta", cta_rect)
	var cta_accent: Color = DuelHud.HUD_SIGNAL if _cta_enabled else DuelHud.HUD_TEXT_FAINT
	DuelHud.draw_plate(self, cta_rect, Color(cta_accent, 0.16 if _cta_enabled else 0.05), Color(cta_accent, 0.95 if _cta_enabled else 0.4), DuelHud.HUD_CUT_SM, DuelHud.CHAMFER_DIAG, 1.6)
	DuelHud.draw_accent_edge(self, cta_rect, Color(cta_accent, 0.95 if _cta_enabled else 0.35), true, 4.0)
	if _cta_enabled:
		DuelHud.draw_brackets(self, cta_rect.grow(-5.0), Color(cta_accent, 0.4), 12.0, 1.4)
	DuelHud.draw_tracked_centered(self, cta_rect.get_center() + Vector2(3.0, 5.0), _cta_label.to_upper(), DuelHud.FS_BODY, DuelHud.HUD_TEXT if _cta_enabled else DuelHud.HUD_TEXT_FAINT, 2.6)
	if not _cta_note.is_empty():
		DuelHud.draw_tracked(self, Vector2(cta_rect.end.x + 18.0, cta_y + 33.0), _cta_note.to_upper(), DuelHud.FS_LABEL, DuelHud.HUD_TEXT_DIM)
	if _show_cancel:
		var cancel_rect := Rect2(safe.end.x - 166.0, safe.end.y - 60.0, 140.0, 50.0)
		_register_button("cancel", cancel_rect)
		DuelHud.draw_plate(self, cancel_rect, Color(DuelHud.HUD_INK, 0.9), Color(DuelHud.HUD_EDGE_BRIGHT, 0.6), DuelHud.HUD_CUT_SM, DuelHud.CHAMFER_DIAG, 1.0)
		DuelHud.draw_tracked_centered(self, cancel_rect.get_center() + Vector2(0.0, 5.0), "BACK", DuelHud.FS_LABEL, DuelHud.HUD_TEXT_DIM)

## One card shape for all four classes: a class glyph in its own well, the
## class name, the loadout blurb, and a footer strip that carries the selected
## state. Selection is amber edge + brackets + a lit footer, so a picked card
## is unmistakable without saturating the whole card in colour.
func _draw_class_card(rect: Rect2, player_class: int, held: bool) -> void:
	var accent: Color = DuelHud.HUD_SIGNAL if held else DuelHud.HUD_EDGE_BRIGHT
	DuelHud.draw_plate(self, rect, Color(DuelHud.HUD_INK_RAISE if held else DuelHud.HUD_INK, 0.94), Color(accent, 0.85 if held else 0.42), DuelHud.HUD_CUT, DuelHud.CHAMFER_DIAG, 1.4 if held else 1.0)
	if held:
		DuelHud.draw_brackets(self, rect.grow(-6.0), Color(accent, 0.55), 15.0, 1.6)
	var well := Rect2(rect.position + Vector2(16.0, 16.0), Vector2(38.0, 38.0))
	DuelHud.draw_plate(self, well, Color(DuelHud.HUD_VOID, 0.75), Color(accent, 0.5 if held else 0.28), 5.0)
	_draw_class_glyph(well.get_center(), player_class, Color(accent, 0.98 if held else 0.6))
	DuelHud.draw_tracked(self, rect.position + Vector2(64.0, 40.0), str(CLASS_LABELS.get(player_class, "")), DuelHud.FS_BODY, DuelHud.HUD_TEXT if held else DuelHud.HUD_TEXT_DIM, 2.2)
	DuelHud.draw_body(self, rect.position + Vector2(17.0, 82.0), str(CLASS_BLURBS.get(player_class, "")), DuelHud.FS_LABEL, DuelHud.HUD_TEXT_DIM, rect.size.x - 34.0)
	var footer := Rect2(Vector2(rect.position.x + 1.0, rect.end.y - 26.0), Vector2(rect.size.x - 2.0, 25.0))
	draw_line(footer.position, Vector2(footer.end.x, footer.position.y), Color(DuelHud.HUD_EDGE, 0.8), 1.0)
	DuelHud.draw_tracked(self, footer.position + Vector2(15.0, 17.0), "SELECTED" if held else "AVAILABLE", DuelHud.FS_MICRO, Color(accent, 0.95) if held else DuelHud.HUD_TEXT_FAINT)
	if held:
		DuelHud.draw_accent_edge(self, Rect2(footer.position, Vector2(3.0, footer.size.y)), Color(accent, 0.95), true, 3.0)

## Four angular class marks drawn from the same stroke language as the HUD
## glyphs, so the picker is not four identical rectangles with different words.
func _draw_class_glyph(center: Vector2, player_class: int, color: Color) -> void:
	match player_class:
		Duelist.PlayerClass.FRONTLINE:
			draw_polyline(PackedVector2Array([center + Vector2(-8, 4), center + Vector2(0, -6), center + Vector2(8, 4)]), color, 2.2)
			draw_polyline(PackedVector2Array([center + Vector2(-8, 10), center + Vector2(0, 0), center + Vector2(8, 10)]), color, 2.2)
		Duelist.PlayerClass.SNIPER:
			draw_arc(center, 8.0, 0.0, TAU, 20, color, 1.8)
			draw_line(center + Vector2(-12, 0), center + Vector2(-4, 0), color, 1.8)
			draw_line(center + Vector2(4, 0), center + Vector2(12, 0), color, 1.8)
			draw_line(center + Vector2(0, -12), center + Vector2(0, -4), color, 1.8)
			draw_line(center + Vector2(0, 4), center + Vector2(0, 12), color, 1.8)
			draw_circle(center, 1.8, color)
		Duelist.PlayerClass.RUNNER:
			draw_polyline(PackedVector2Array([center + Vector2(-4, -10), center + Vector2(6, 0), center + Vector2(-4, 10)]), color, 2.2)
			draw_line(center + Vector2(-11, -5), center + Vector2(-6, -5), color, 1.6)
			draw_line(center + Vector2(-11, 0), center + Vector2(-7, 0), color, 1.6)
			draw_line(center + Vector2(-11, 5), center + Vector2(-6, 5), color, 1.6)
		Duelist.PlayerClass.SHIELD:
			var shield := PackedVector2Array([center + Vector2(-9, -10), center + Vector2(9, -10), center + Vector2(9, 2), center + Vector2(0, 11), center + Vector2(-9, 2)])
			draw_colored_polygon(shield, Color(color, 0.18))
			var loop := shield.duplicate()
			loop.append(shield[0])
			draw_polyline(loop, color, 2.0)

func _register_button(key: String, rect: Rect2) -> void:
	_button_rects[key] = rect
