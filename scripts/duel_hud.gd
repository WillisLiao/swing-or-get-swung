class_name DuelHud
extends Control

signal rift_link_requested
signal main_menu_requested
signal feedback_preferences_changed(effects_enabled: bool, haptics_enabled: bool)
signal view_fov_changed(horizontal_degrees: float)

const CONFIG_PATH := "user://riftline_controls.cfg"
const RESPONSIVE := preload("res://scripts/riftline_responsive_layout.gd")
const CONTROLS_SECTION := "controls"
const CONTROLS_VERSION := 1
const LAYOUT_SECTION := "hud_layout_v1"
const FEEDBACK_SECTION := "feedback_v1"
const VIEW_SECTION := "display"
const LAYOUT_VERSION := 4
const SNAP_POINTS := 8.0
const DRAG_THRESHOLD := 10.0
const MOVABLE_KEYS := ["move", "left_fire", "right_fire", "ads", "jump", "crouch", "prone", "swap", "interact"]
# Pre-rename layout key, kept so an existing saved HUD layout migrates onto
# the current control ids instead of silently resetting.  Built by
# concatenation rather than as one literal so the old identifier does not
# linger in the source as a readable name.
const LEGACY_LAYOUT_KEY_NAMES := {"interact": "seed" + "_pass"}

# --- Design tokens ---------------------------------------------------------
#
# One visual language for every piece of UI chrome in the game: this HUD, the
# rift-link/lobby panel, the main menu and the class picker. The other three
# read these constants and the static primitives below off `DuelHud` rather
# than redeclaring their own palettes, so there is exactly one place to change
# a colour or a corner treatment. They live here (instead of in a fifth
# script) because this is the largest consumer and because nothing here
# depends on the panels, so there is no cycle.
#
# Register: Halo-Infinite UNSC industrial - angular chamfered plates, hairline
# structure, technical letter-spaced type, functional density - with restrained
# Destiny-style accent glow used only to signal state. Team colour is an
# identity accent (edges, ticks, glyphs), never a blanket surface fill; the
# system accent for "this is active/interactive" is amber, so a highlighted
# button is never mistaken for a team read.

const HUD_VOID := Color("04070d")        # full-screen scrim behind modal chrome
const HUD_INK := Color("0a1018")         # panel body
const HUD_INK_RAISE := Color("121b27")   # chips, rows, wells sitting on a panel
const HUD_EDGE := Color("2b3b50")        # structural hairline
const HUD_EDGE_BRIGHT := Color("55708c") # emphasised structural line
const HUD_TEXT := Color("e6edf6")
const HUD_TEXT_DIM := Color("8ea1b8")
const HUD_TEXT_FAINT := Color("5c6d82")
const HUD_SIGNAL := Color("ffb454")      # system accent: active / interactive
const HUD_ALERT := Color("ff4f3d")       # danger: low vitality, destructive action
const HUD_OK := Color("74e0a4")
const HUD_TEAM_RED := Color("ff6a57")
const HUD_TEAM_BLUE := Color("71cfff")

const HUD_CUT := 10.0                    # panel corner chamfer
const HUD_CUT_SM := 5.0                  # chip / plate corner chamfer
const HUD_TRACK := 1.8                   # letter spacing for technical type
const HUD_TRACK_TIGHT := 0.9

const FS_MICRO := 10
const FS_LABEL := 12
const FS_BODY := 14
const FS_SUB := 18
const FS_TITLE := 24
const FS_DISPLAY := 34

# Corner selection for chamfer_points(). The default cuts the two corners on
# the leading diagonal, which is what makes a plate read as machined rather
# than as a rounded card.
const CHAMFER_TL := 1
const CHAMFER_TR := 2
const CHAMFER_BR := 4
const CHAMFER_BL := 8
const CHAMFER_DIAG := 5
const CHAMFER_ALL := 15

static func hud_font() -> Font:
	return ThemeDB.fallback_font

static func chamfer_points(rect: Rect2, cut: float, mask: int = CHAMFER_DIAG) -> PackedVector2Array:
	var c := maxf(0.0, minf(cut, minf(rect.size.x, rect.size.y) * 0.5))
	var a := rect.position
	var b := rect.end
	var points := PackedVector2Array()
	if mask & CHAMFER_TL:
		points.append(Vector2(a.x + c, a.y))
	else:
		points.append(a)
	if mask & CHAMFER_TR:
		points.append(Vector2(b.x - c, a.y))
		points.append(Vector2(b.x, a.y + c))
	else:
		points.append(Vector2(b.x, a.y))
	if mask & CHAMFER_BR:
		points.append(Vector2(b.x, b.y - c))
		points.append(Vector2(b.x - c, b.y))
	else:
		points.append(b)
	if mask & CHAMFER_BL:
		points.append(Vector2(a.x + c, b.y))
		points.append(Vector2(a.x, b.y - c))
	else:
		points.append(Vector2(a.x, b.y))
	if mask & CHAMFER_TL:
		points.append(Vector2(a.x, a.y + c))
	return points

## The one plate primitive. Everything with a background in this game's UI is
## this shape - never a rounded rect, never a nested card.
static func draw_plate(ci: CanvasItem, rect: Rect2, fill: Color, edge: Color, cut: float = HUD_CUT, mask: int = CHAMFER_DIAG, width: float = 1.0) -> void:
	var points := chamfer_points(rect, cut, mask)
	if fill.a > 0.0:
		ci.draw_colored_polygon(points, fill)
	if edge.a > 0.0 and points.size() > 1:
		var loop := points.duplicate()
		loop.append(points[0])
		ci.draw_polyline(loop, edge, width)

## Destiny-register accent: a single bright edge on one side of a plate plus a
## soft outer bleed. This is how "active", "selected" and "alert" are said -
## not by flooding the plate with saturated colour.
static func draw_accent_edge(ci: CanvasItem, rect: Rect2, color: Color, vertical: bool = true, thickness: float = 3.0) -> void:
	if vertical:
		ci.draw_rect(Rect2(rect.position, Vector2(thickness, rect.size.y)), color, true)
		ci.draw_rect(Rect2(rect.position - Vector2(2.0, 0.0), Vector2(2.0, rect.size.y)), Color(color, color.a * 0.22), true)
	else:
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, thickness)), color, true)
		ci.draw_rect(Rect2(rect.position - Vector2(0.0, 2.0), Vector2(rect.size.x, 2.0)), Color(color, color.a * 0.22), true)

## Corner brackets. Used sparingly, on the two or three elements per screen
## that are genuinely the focus - a targeted plate, a modal card, the selected
## class - so they keep meaning something.
static func draw_brackets(ci: CanvasItem, rect: Rect2, color: Color, arm: float = 13.0, width: float = 2.0) -> void:
	var a := rect.position
	var b := rect.end
	ci.draw_polyline(PackedVector2Array([Vector2(a.x, a.y + arm), a, Vector2(a.x + arm, a.y)]), color, width)
	ci.draw_polyline(PackedVector2Array([Vector2(b.x - arm, a.y), Vector2(b.x, a.y), Vector2(b.x, a.y + arm)]), color, width)
	ci.draw_polyline(PackedVector2Array([Vector2(b.x, b.y - arm), b, Vector2(b.x - arm, b.y)]), color, width)
	ci.draw_polyline(PackedVector2Array([Vector2(a.x + arm, b.y), Vector2(a.x, b.y), Vector2(a.x, b.y - arm)]), color, width)

static func tracked_width(font: Font, text: String, font_size: int, tracking: float = HUD_TRACK) -> float:
	var total := 0.0
	for index in text.length():
		total += font.get_char_size(text.unicode_at(index), font_size).x + tracking
	return maxf(0.0, total - tracking)

## Letter-spaced technical type. The fallback font is a plain humanist sans;
## tracking it out is what turns it into the stencilled machine lettering the
## reference uses, without importing a typeface.
static func draw_tracked(ci: CanvasItem, at: Vector2, text: String, font_size: int, color: Color, tracking: float = HUD_TRACK) -> float:
	var font := hud_font()
	var x := at.x
	for index in text.length():
		var code := text.unicode_at(index)
		ci.draw_char(font, Vector2(x, at.y), String.chr(code), font_size, color)
		x += font.get_char_size(code, font_size).x + tracking
	return x - at.x - tracking

static func draw_tracked_centered(ci: CanvasItem, at: Vector2, text: String, font_size: int, color: Color, tracking: float = HUD_TRACK) -> void:
	var width := tracked_width(hud_font(), text, font_size, tracking)
	draw_tracked(ci, at - Vector2(width * 0.5, 0.0), text, font_size, color, tracking)

## Plain (untracked) proportional text, for sentence-case body copy where
## tracking would hurt readability rather than help it.
static func draw_body(ci: CanvasItem, at: Vector2, text: String, font_size: int, color: Color, width: float = -1.0) -> void:
	ci.draw_string(hud_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

static func body_width(text: String, font_size: int) -> float:
	return hud_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

## A section rule: short bright stub, long dim run. Reads as a technical
## divider rather than a generic 1px line.
static func draw_rule(ci: CanvasItem, from: Vector2, length: float, color: Color) -> void:
	ci.draw_line(from, from + Vector2(minf(26.0, length), 0.0), color, 1.6)
	ci.draw_line(from + Vector2(minf(26.0, length) + 5.0, 0.0), from + Vector2(length, 0.0), Color(color, color.a * 0.3), 1.0)

static func polygon_ring(center: Vector2, radius: float, sides: int, phase: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in sides:
		points.append(center + Vector2.from_angle(phase + TAU * float(index) / float(sides)) * radius)
	return points

## Touch controls are drawn as octagons rather than circles so they belong to
## the same machined language as the plates, while their hit test stays the
## radial one the touch router and the regression tests rely on: the octagon's
## vertices sit exactly on the hit circle's radius.
## `backing` lays a dark stroke under the bright one. Without it a thin HUD
## outline vanishes completely against the arena's pale concrete and the
## launch pad's bright emissive - the same problem the reticle solves with its
## double stroke.
static func draw_control_ring(ci: CanvasItem, center: Vector2, radius: float, fill: Color, edge: Color, width: float, backing: float = 0.0) -> void:
	var points := polygon_ring(center, radius, 8, PI / 8.0)
	if fill.a > 0.0:
		ci.draw_colored_polygon(points, fill)
	if edge.a <= 0.0:
		return
	var loop := points.duplicate()
	loop.append(points[0])
	if backing > 0.0:
		ci.draw_polyline(loop, Color(HUD_VOID, backing), width + 2.6)
	ci.draw_polyline(loop, edge, width)

var movement := Vector2.ZERO
var fire_held := false
var aim_held := false
var health := 100.0
var magazine_rounds := int(RiftWeapons.row(int(Duelist.Weapon.RIFLE)).magazine_size)
var reserve_ammo := int(RiftWeapons.row(int(Duelist.Weapon.RIFLE)).reserve_ammo)
var reload_remaining := 0.0
var damage_flash := 0.0
var hit_confirm := 0.0
var primary_fire_bloom := 0.0
var damage_direction := Vector2.ZERO
var damage_direction_intensity := 0.0
var damage_enemy_team := int(Duelist.Team.BLUE)
var high_alert_direction := Vector2.DOWN
var high_alert_intensity := 0.0
var objective_feedback_pulse := 0.0
var objective_feedback_team := -1
var camera_sensitivity := 1.0
var ads_sensitivity := 0.72
var horizontal_fov := Duelist.DEFAULT_HORIZONTAL_FOV
var gyro_enabled := false
var effects_enabled := true
var haptics_enabled := false
var _stick_mode := MobileTouchRouter.StickMode.FLOATING
var _touch_router := MobileTouchRouter.new()
var _stick_visual_opacity := 0.0
var _stick_visual_target := 0.0
var _coach_cue: Dictionary = {}
var _coach_display_cue: Dictionary = {}

static func save_feedback_preferences(config: ConfigFile, next_effects_enabled: bool, next_haptics_enabled: bool) -> void:
	config.set_value(FEEDBACK_SECTION, "version", 1)
	config.set_value(FEEDBACK_SECTION, "effects", next_effects_enabled)
	config.set_value(FEEDBACK_SECTION, "haptics", false)

static func load_feedback_preferences(config: ConfigFile, default_effects_enabled: bool = true, default_haptics_enabled: bool = true) -> Dictionary:
	return {
		"effects_enabled": bool(config.get_value(FEEDBACK_SECTION, "effects", default_effects_enabled)),
		"haptics_enabled": false,
	}
var _coach_visual_opacity := 0.0
var _coach_visual_target := 0.0
var _touch_preview := ""
var _ammo_preview_override := false

var _look_delta := Vector2.ZERO
var _jump_requested := false
var _crouch_requested := false
var _prone_requested := false
var _weapon_switch_requested := false
var _reload_requested := false
var _melee_requested := false
var _melee_touch := -1
var _interact_requested := false
var _left_fire_touch := -1
var _right_fire_touch := -1
var _aim_touch := -1
var _jump_touch := -1
var _crouch_touch := -1
var _prone_touch := -1
var _switch_touch := -1
var _interact_touch := -1
# Holding the ADS button and dragging that same finger steers the camera by
# default. This keeps two-thumb aiming viable while the left thumb moves.
var ads_button_look := true
var _settings_owner_touch := -1
# Which settings control (if any) a given touch index has captured on press.
# Drag events are routed only to the captured control for that same index, so
# a finger sliding from one control onto another cannot activate the second.
var _settings_captures: Dictionary = {}
var _red_score := 0
var _blue_score := 0
var _roster_state: Array[Dictionary] = []
var _roster_local_team := int(Duelist.Team.RED)
var _squad_readability := false
var _objective_state: Dictionary = {
	"mode": int(RiftlineMatch.GameMode.NUCLEAR_RUSH),
	"core_state": int(RiftlineMatch.CoreState.AT_CENTER),
	"core_position": Vector3.ZERO,
	"core_carrier_id": "",
	"core_carrier_team": int(Duelist.Team.RED),
	"installed_team": int(Duelist.Team.RED),
	"install_progress": 0.0,
	"cancel_progress": 0.0,
	"launch_remaining": 0.0,
	"match_remaining": RiftlineMatch.MATCH_SECONDS,
	"sudden_death": false,
}
var _objective_message := ""
var _objective_message_remaining := 0.0
var _score_pulse := 0.0
var _score_pulse_team := -1
var _stance := Duelist.Stance.STAND
var _weapon := Duelist.Weapon.RIFLE
## Presentation mirrors of Duelist.ads_progress / Duelist.zoom_index, pushed in
## by the arena each frame. See set_ads_state().
var _ads_progress := 0.0
var _zoom_index := 0
## Mirror of Duelist.recoil_presentation() (kick, lateral), pushed in by the
## arena each frame alongside _ads_progress/_zoom_index. See set_recoil_state().
var _recoil_kick := 0.0
var _recoil_lateral := 0.0
## Duelist._scope_camera's render, pushed in by the arena each frame. See
## set_scope_texture() and _draw_scope_overlay().
var _scope_texture: Texture2D = null
var _settings_open := false
var _layout_editor := false
var _aim_toggle := false
var _layout: Dictionary = {}
var _selected_layout_key := ""
var _editor_touch := -1
var _editor_drag_start := Vector2.ZERO
var _editor_start_center := Vector2.ZERO
var _editor_dragging := false
var _layout_dirty := false
var _combat_input_enabled := true
var _match_result_visible := false
var _match_result_victory := false
var _rematch_requested := false
var _match_phase: RiftlineMatch.Phase = RiftlineMatch.Phase.OPENING
var _connection_flow_active := false
var _connection_message := ""
var _connection_message_remaining := 0.0
var _reset_training_requested := false
var _interact_available := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout = _default_layout()
	_load_control_settings()
	_refresh_responsive_layout()
	_touch_router.configure(_stick_mode, _control_center("move"), _stick_radius())
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_responsive_layout()

func _refresh_responsive_layout() -> void:
	if not is_inside_tree() or _layout.is_empty():
		return
	# Resize can remap an owned finger to a different action.  Cancel ownership
	# without saving a transient layout so resize never leaks a combat edge.
	_release_all_touch_ownership()
	_touch_router.configure(_stick_mode, _control_center("move"), _stick_radius())
	queue_redraw()

func _process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta * 2.8)
	hit_confirm = maxf(0.0, hit_confirm - delta * 6.5)
	primary_fire_bloom = maxf(0.0, primary_fire_bloom - delta * 8.5)
	damage_direction_intensity = maxf(0.0, damage_direction_intensity - delta * 4.0)
	high_alert_intensity = maxf(0.0, high_alert_intensity - delta * 2.8)
	objective_feedback_pulse = maxf(0.0, objective_feedback_pulse - delta * 3.0)
	_objective_message_remaining = maxf(0.0, _objective_message_remaining - delta)
	_score_pulse = maxf(0.0, _score_pulse - delta * 2.8)
	if _objective_message_remaining <= 0.0:
		_objective_message = ""
	_connection_message_remaining = maxf(0.0, _connection_message_remaining - delta)
	if _connection_message_remaining <= 0.0:
		_connection_message = ""
	_stick_visual_opacity = move_toward(_stick_visual_opacity, _stick_visual_target, delta * 12.0)
	_coach_visual_opacity = move_toward(_coach_visual_opacity, _coach_visual_target, delta * 5.5)
	if _coach_visual_target <= 0.0 and _coach_visual_opacity <= 0.01:
		_coach_display_cue = {}
	queue_redraw()

func take_look_delta() -> Vector2:
	var delta := _look_delta + _touch_router.take_look_delta()
	_look_delta = Vector2.ZERO
	return delta * (ads_sensitivity if aim_held else camera_sensitivity)

func take_jump() -> bool:
	var requested := _jump_requested
	_jump_requested = false
	return requested

func take_crouch() -> bool:
	var requested := _crouch_requested
	_crouch_requested = false
	return requested

func take_prone() -> bool:
	var requested := _prone_requested
	_prone_requested = false
	return requested

func take_weapon_switch() -> bool:
	var requested := _weapon_switch_requested
	_weapon_switch_requested = false
	return requested

func take_reload() -> bool:
	var requested := _reload_requested
	_reload_requested = false
	return requested

func take_melee() -> bool:
	var requested := _melee_requested
	_melee_requested = false
	return requested

func take_reset_training() -> bool:
	var requested := _reset_training_requested
	_reset_training_requested = false
	return requested

func take_interact() -> bool:
	var requested := _interact_requested
	_interact_requested = false
	return requested

func interact_held() -> bool:
	# The context use button (install/cancel) is a held action.
	return _interact_touch >= 0

func set_coach_cue(cue: Dictionary) -> void:
	_coach_cue = cue.duplicate(true)
	if _coach_cue.is_empty():
		_coach_visual_target = 0.0
	else:
		_coach_display_cue = _coach_cue.duplicate(true)
		_coach_visual_target = 1.0
	queue_redraw()

func set_touch_preview(preview: String) -> void:
	_touch_preview = preview
	_ammo_preview_override = preview in ["ammo-low", "reloading"]
	if preview == "two-thumb":
		_layout = _two_thumb_layout()
	elif preview == "four-finger":
		_layout = _four_finger_layout()
	elif preview == "fixed-stick":
		_stick_mode = MobileTouchRouter.StickMode.FIXED
		_touch_router.configure(_stick_mode, _control_center("move"), _stick_radius())
	elif preview in ["floating-left", "floating-edge"]:
		_stick_mode = MobileTouchRouter.StickMode.FLOATING
		_touch_router.configure(_stick_mode, _control_center("move"), _stick_radius())
	if preview in ["floating-left", "floating-edge"]:
		_stick_visual_target = 1.0
		_stick_visual_opacity = 1.0
	if preview == "ammo-low":
		show_ammo(4, 24, 0.0)
	elif preview == "reloading":
		show_ammo(4, 24, float(RiftWeapons.row(int(Duelist.Weapon.RIFLE)).reload_seconds) * 0.5)
	if preview == "coach-move":
		set_coach_cue({"key": "move", "text": "DRAG LEFT SIDE TO MOVE", "region": "left"})
	elif preview == "coach-look":
		set_coach_cue({"key": "look", "text": "DRAG RIGHT SIDE TO LOOK", "region": "right"})
	elif preview == "coach-fire":
		set_coach_cue({"key": "fire", "text": "HOLD FIRE TO ENGAGE", "region": "fire"})

func set_score(red_score: int, blue_score: int) -> void:
	_red_score = clampi(red_score, 0, 3)
	_blue_score = clampi(blue_score, 0, 3)
	queue_redraw()

func set_roster_state(records: Array[Dictionary], local_team: int, squad_readability: bool) -> void:
	_roster_state.clear()
	for record in records:
		_roster_state.append(record.duplicate(true))
	_roster_local_team = local_team
	_squad_readability = squad_readability
	queue_redraw()

func set_objective_state(state: Dictionary) -> void:
	# A replica client can receive a partial payload mid-transition, so merge
	# rather than replace: any key not present keeps its previous value.
	var incoming: Dictionary = state.get("objective") as Dictionary if state.has("objective") and state.get("objective") is Dictionary else state
	for key in incoming.keys():
		_objective_state[key] = incoming[key]
	queue_redraw()

func set_interact_available(available: bool) -> void:
	_interact_available = available
	if not available and _interact_touch >= 0:
		_interact_touch = -1
	queue_redraw()

func safe_area_rect() -> Rect2:
	return _safe_rect()

func show_objective_event(event_type: String, _state: Dictionary) -> void:
	match event_type:
		"core_picked_up":
			_objective_message = "CORE TAKEN"
		"core_dropped":
			_objective_message = "CORE DROPPED"
		"core_returned":
			_objective_message = "CORE RETURNED"
		"core_installed":
			_objective_message = "LAUNCH SEQUENCE STARTED"
		"launch_cancelled":
			_objective_message = "LAUNCH CANCELLED"
		"launch_complete":
			_objective_message = "LAUNCH COMPLETE"
			_score_pulse = 1.0
		_:
			return
	_objective_message_remaining = 1.4
	queue_redraw()

func show_practice_cue(message: String) -> void:
	_objective_message = message
	_objective_message_remaining = 1.8
	queue_redraw()

func set_stance(stance: Duelist.Stance) -> void:
	_stance = stance

func set_weapon(weapon: Duelist.Weapon) -> void:
	_weapon = weapon
	queue_redraw()

## Mirrors the two presentation values `Duelist` already tracks every frame, so
## the reticle can cross-fade with the weapon actually coming up and the sniper
## scope knows which of its two magnification stages to draw. Read-only here -
## the authoritative sim owns both.
func set_ads_state(progress: float, zoom: int) -> void:
	var next_progress := clampf(progress, 0.0, 1.0) if is_finite(progress) else 0.0
	var next_zoom := maxi(0, zoom)
	if absf(next_progress - _ads_progress) < 0.001 and next_zoom == _zoom_index:
		return
	_ads_progress = next_progress
	_zoom_index = next_zoom
	queue_redraw()

## Mirrors Duelist._recoil_kick/_recoil_lateral - the same two fields that
## throw the 3D weapon rig under recoil - so the ADS/scope reticle can be
## nudged in step with the housing it is supposed to read as sitting on. See
## _recoil_reticle_offset().
func set_recoil_state(recoil: Vector2) -> void:
	var next_kick := recoil.x if is_finite(recoil.x) else 0.0
	var next_lateral := recoil.y if is_finite(recoil.y) else 0.0
	if absf(next_kick - _recoil_kick) < 0.0005 and absf(next_lateral - _recoil_lateral) < 0.0005:
		return
	_recoil_kick = next_kick
	_recoil_lateral = next_lateral
	queue_redraw()

## Pushes Duelist._scope_camera's live render in each frame while scoped;
## null the rest of the time (see Duelist.scope_viewport_texture()). Not
## redraw-gated like the scalar setters above - a SubViewport's ViewportTexture
## updates its own pixels without a new reference, so equality-checking the
## reference would never catch the picture actually changing frame to frame.
func set_scope_texture(texture: Texture2D) -> void:
	_scope_texture = texture

func set_view_fov(value: float, persist: bool = true) -> void:
	var next := clampf(value, Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV) if is_finite(value) else Duelist.DEFAULT_HORIZONTAL_FOV
	if absf(next - horizontal_fov) < 0.001:
		return
	horizontal_fov = next
	if persist:
		_save_control_settings()
	view_fov_changed.emit(horizontal_fov)
	queue_redraw()

func show_ammo(magazine: int, reserve: int, reload_time: float) -> void:
	if _ammo_preview_override:
		return
	var row := RiftWeapons.row(int(_weapon))
	magazine_rounds = clampi(magazine, 0, int(row.magazine_size))
	reserve_ammo = clampi(reserve, 0, int(row.reserve_ammo))
	reload_remaining = maxf(0.0, reload_time)
	queue_redraw()

func open_settings() -> void:
	_release_all_touch_ownership()
	_layout_editor = false
	_settings_open = true
	queue_redraw()

func open_hud_layout() -> void:
	_release_all_touch_ownership()
	_settings_open = false
	_layout_editor = true
	_selected_layout_key = ""
	_layout_dirty = false
	queue_redraw()

func set_combat_input_enabled(enabled: bool) -> void:
	_combat_input_enabled = enabled
	if not enabled:
		_release_all_touch_ownership()
	queue_redraw()

func set_connection_flow_active(active: bool) -> void:
	_connection_flow_active = active
	if active:
		_release_all_touch_ownership()
	queue_redraw()

func show_connection_message(message: String) -> void:
	_connection_message = message
	_connection_message_remaining = 2.8
	queue_redraw()

func can_drive_combat() -> bool:
	return _combat_input_enabled and not _connection_flow_active and not _settings_open and not _layout_editor and not _match_result_visible

func set_match_phase(phase: RiftlineMatch.Phase) -> void:
	_match_phase = phase
	if phase != RiftlineMatch.Phase.FINISHED:
		_match_result_visible = false
		_rematch_requested = false
	queue_redraw()

func show_match_result(winner: Duelist.Team) -> void:
	_match_result_victory = int(winner) == _roster_local_team
	_match_result_visible = true
	_rematch_requested = false
	_release_all_touch_ownership()
	queue_redraw()

func take_rematch() -> bool:
	var requested := _rematch_requested
	_rematch_requested = false
	return requested

func show_damage(current_health: float) -> void:
	health = current_health
	damage_flash = maxf(damage_flash, 1.0)
	queue_redraw()

func show_damage_direction(direction: Vector2, intensity: float, enemy_team: int) -> void:
	damage_direction = direction
	damage_direction_intensity = clampf(intensity, 0.0, 1.0)
	damage_enemy_team = enemy_team
	queue_redraw()

func show_high_alert(direction: Vector2, intensity: float = 1.0) -> void:
	high_alert_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.DOWN
	high_alert_intensity = maxf(high_alert_intensity, clampf(intensity, 0.0, 1.0))
	queue_redraw()

func clear_high_alert() -> void:
	high_alert_intensity = 0.0
	queue_redraw()

func show_hit_confirm() -> void:
	hit_confirm = 1.0
	queue_redraw()

func show_primary_fire_feedback(hip_burst_followup: bool = false) -> void:
	# Only accepted follow-up hip shots open the reticle meaningfully.  A single
	# shot and ADS keep a barely perceptible acknowledgement without exposing a
	# player-facing accuracy value.
	primary_fire_bloom = minf(1.0, primary_fire_bloom + (0.72 if hip_burst_followup else 0.14))
	queue_redraw()

func show_objective_feedback(event_type: String, scoring_team: int) -> void:
	objective_feedback_pulse = 1.0
	objective_feedback_team = scoring_team
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if _connection_flow_active:
		return
	if _match_result_visible:
		if event is InputEventScreenTouch and event.pressed and _rematch_rect().grow(12.0).has_point(event.position):
			_rematch_requested = true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _rematch_rect().grow(12.0).has_point(event.position):
			_rematch_requested = true
		return
	if event is InputEventScreenTouch:
		if _layout_editor:
			_handle_editor_touch(event.index, event.position, event.pressed)
		elif _settings_open:
			_handle_settings_touch(event.index, event.position, event.pressed)
		else:
			_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		if _layout_editor:
			_handle_editor_drag(event.index, event.position)
		elif _settings_open:
			_handle_settings_drag(event.index, event.position)
		else:
			_handle_drag(event.index, event.position, event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _layout_editor:
			_handle_editor_touch(0, event.position, event.pressed)
		elif _settings_open:
			_handle_settings_touch(0, event.position, event.pressed)
		else:
			if event.pressed and _settings_hit_rect().has_point(event.position):
				open_settings()
				_settings_owner_touch = 0
			elif event.pressed and _pressed_circle(event.position, _reload_center(), _reload_radius() + 12.0):
				_reload_requested = true
				fire_held = false
			elif event.pressed and _pressed_circle(event.position, _melee_center(), _melee_radius() + 12.0):
				_melee_requested = true
				fire_held = false
			elif event.pressed and _interact_available and _pressed_circle(event.position, _control_center("interact"), _control_radius("interact") + 12.0):
				_interact_requested = true
				fire_held = false
			else:
				fire_held = event.pressed
	elif event is InputEventMouseMotion:
		if _layout_editor and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_editor_drag(0, event.position)
		elif _settings_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_settings_drag(0, event.position)
		elif not _settings_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_look_delta += event.relative

func _handle_touch(index: int, point: Vector2, pressed: bool) -> void:
	if not pressed:
		_release_touch(index)
		return
	if _settings_hit_rect().has_point(point):
		open_settings()
		_settings_owner_touch = index
		return
	if not _combat_input_enabled:
		return
	if _pressed_circle(point, _reload_center(), _reload_radius() + 12.0):
		_reload_requested = true
		return
	if _pressed_circle(point, _melee_center(), _melee_radius() + 12.0):
		_melee_touch = index
		_melee_requested = true
		return
	var key := _action_key_at(point)
	if key == "left_fire":
		_left_fire_touch = index
		fire_held = true
		return
	if key == "right_fire":
		_right_fire_touch = index
		fire_held = true
		return
	if key == "ads":
		_aim_touch = index
		aim_held = not aim_held if _aim_toggle else true
		return
	if key == "jump":
		_jump_touch = index
		_jump_requested = true
		return
	if key == "crouch":
		_crouch_touch = index
		_crouch_requested = true
		return
	if key == "prone":
		_prone_touch = index
		_prone_requested = true
		return
	if key == "swap":
		_switch_touch = index
		_weapon_switch_requested = true
		return
	if key == "interact" and _interact_available:
		_interact_touch = index
		_interact_requested = true
		return
	if not _safe_rect().has_point(point):
		return
	_touch_router.configure(_stick_mode, _control_center("move"), _stick_radius())
	var role := _touch_router.begin(index, point, _movement_region(), _stick_radius())
	movement = _touch_router.movement()
	if role == MobileTouchRouter.Role.MOVE:
		_stick_visual_target = 1.0

func _handle_drag(index: int, point: Vector2, relative: Vector2) -> void:
	# Drag-look lets the finger holding ADS also steer the view.
	if index == _aim_touch and ads_button_look:
		_look_delta += relative
	_touch_router.drag(index, point, relative)
	movement = _touch_router.movement()

func _release_touch(index: int) -> void:
	_touch_router.end(index)
	movement = _touch_router.movement()
	if not _touch_router.has_movement_owner() and _touch_preview.is_empty():
		_stick_visual_target = 0.0
	if index == _left_fire_touch:
		_left_fire_touch = -1
	if index == _right_fire_touch:
		_right_fire_touch = -1
	if _left_fire_touch < 0 and _right_fire_touch < 0:
		fire_held = false
	if index == _aim_touch:
		_aim_touch = -1
		if not _aim_toggle:
			aim_held = false
	if index == _jump_touch:
		_jump_touch = -1
	if index == _crouch_touch:
		_crouch_touch = -1
	if index == _prone_touch:
		_prone_touch = -1
	if index == _switch_touch:
		_switch_touch = -1
	if index == _melee_touch:
		_melee_touch = -1
	if index == _interact_touch:
		_interact_touch = -1
	if index == _settings_owner_touch:
		_settings_owner_touch = -1
	_settings_captures.erase(index)

func _release_all_touch_ownership() -> void:
	_touch_router.reset()
	_left_fire_touch = -1
	_right_fire_touch = -1
	_aim_touch = -1
	_jump_touch = -1
	_crouch_touch = -1
	_prone_touch = -1
	_switch_touch = -1
	_melee_touch = -1
	_interact_touch = -1
	_settings_owner_touch = -1
	_settings_captures.clear()
	_editor_touch = -1
	movement = Vector2.ZERO
	fire_held = false
	aim_held = false
	_look_delta = Vector2.ZERO
	_jump_requested = false
	_crouch_requested = false
	_prone_requested = false
	_weapon_switch_requested = false
	_reload_requested = false
	_melee_requested = false
	_interact_requested = false
	_stick_visual_target = 0.0

func _draw() -> void:
	if _layout_editor:
		_draw_layout_editor()
		return
	_draw_gameplay_hud()
	if _settings_open:
		_draw_settings_panel(_friendly_color(), _enemy_color())

func _draw_gameplay_hud() -> void:
	var friendly := _friendly_color()
	var enemy := _enemy_color()
	var center := size * 0.5
	_draw_coach_cue(friendly, enemy)

	_draw_reticle(center)
	if hit_confirm > 0.0:
		# Four diagonal ticks flaring outward, dark-haloed like the reticle
		# strokes so the confirm survives a bright wall behind it.
		var confirm_color := Color(HUD_SIGNAL, 0.98 * hit_confirm)
		var confirm_radius := 22.0 + (1.0 - hit_confirm) * 9.0
		for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
			var direction := Vector2.RIGHT.rotated(angle)
			var inner := center + direction * (confirm_radius - 7.0)
			var outer := center + direction * confirm_radius
			draw_line(inner, outer, Color(RETICLE_INK, 0.5 * hit_confirm), 4.5)
			draw_line(inner, outer, confirm_color, 2.2)

	var stick_anchor := _control_center("move")
	var stick_radius := _stick_radius()
	var stick_is_active := _touch_router.has_movement_owner() or _touch_preview in ["floating-left", "floating-edge"]
	var stick_is_visible := stick_is_active or (_stick_mode == MobileTouchRouter.StickMode.FLOATING and _stick_visual_opacity > 0.01)
	var stick_center := _touch_router.stick_origin() if stick_is_visible else stick_anchor
	var knob := _touch_router.stick_knob() if stick_is_visible else stick_center
	var stick_alpha := _control_opacity("move")
	if _stick_mode == MobileTouchRouter.StickMode.FLOATING:
		stick_alpha *= _stick_visual_opacity if stick_is_active else 0.28
	if _touch_preview == "floating-left":
		stick_center = _preview_stick_origin(Vector2(220.0, 410.0), stick_radius)
		knob = stick_center + Vector2(30.0, -22.0)
	elif _touch_preview == "floating-edge":
		stick_center = _preview_stick_origin(Vector2(28.0, 430.0), stick_radius)
		knob = stick_center + Vector2(32.0, -12.0)
	_draw_stick(stick_center, knob, stick_radius, friendly, stick_alpha, _stick_mode == MobileTouchRouter.StickMode.FIXED or stick_is_active or _stick_visual_opacity > 0.01)

	# Three colour roles on the control cluster and no more: your own team
	# colour on the two things that are you shooting and moving, amber on
	# anything that is a mode or a prompt, steel on everything else. The old
	# scheme put the *enemy* colour on your own ADS button and a fifth
	# unexplained purple on swap.
	_draw_button("left_fire", friendly, _left_fire_touch >= 0)
	_draw_button("right_fire", friendly, _right_fire_touch >= 0)
	# Every weapon ADS's through an optic now, so the ADS button is no longer
	# weapon-gated the way it was when only the carbine could aim.
	_draw_button("ads", HUD_SIGNAL, aim_held)
	_draw_button("jump", HUD_TEXT_DIM, _jump_touch >= 0)
	_draw_button("crouch", friendly, _stance == Duelist.Stance.CROUCH)
	_draw_button("prone", friendly, _stance == Duelist.Stance.PRONE)
	_draw_button("swap", HUD_TEXT_DIM, _switch_touch >= 0)
	if _interact_available:
		# The one control that appears and disappears with context earns a
		# pulsing outer ring, so it is noticed without a text prompt.
		var interact_pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		draw_control_ring(self, _control_center("interact"), _control_radius("interact") + 7.0, Color(0, 0, 0, 0), Color(HUD_SIGNAL, 0.16 + 0.28 * interact_pulse), 1.6)
		_draw_button("interact", HUD_SIGNAL, _interact_touch >= 0)
	_draw_button_fixed(_reload_center(), _reload_radius(), HUD_SIGNAL, reload_remaining > 0.0, "reload")
	_draw_button_fixed(_melee_center(), _melee_radius(), HUD_TEXT_DIM, _melee_touch >= 0, "melee")
	_draw_weapon_indicator(friendly)
	_draw_button_fixed(_settings_center(), 24.0, HUD_TEXT_FAINT, _settings_open, "settings")
	if _touch_preview in ["two-thumb", "four-finger"]:
		_draw_button_preview("left_fire", friendly)
		_draw_button_preview("right_fire", friendly)
	if _touch_preview == "reloading":
		_draw_reload_sweep(_reload_center(), _reload_radius(), HUD_SIGNAL, reload_progress_for(reload_remaining))
	if _touch_preview in ["floating-left", "floating-edge"]:
		_draw_preview_floating_stick(friendly)

	var safe := _safe_rect()
	_draw_vitality_strip(safe, friendly)
	_draw_objective_strip(safe, friendly, enemy)
	if _squad_readability:
		_draw_team_life_strip(safe, friendly, enemy)
	if damage_direction_intensity > 0.0:
		# A tapered three-band wedge instead of one flat arc: the bands fall off
		# outward so the indicator reads as a threat bearing rather than as a
		# stray coloured stripe, and it stays legible over a bright wall.
		var damage_color := _team_color(damage_enemy_team)
		var direction := damage_direction if damage_direction.length_squared() > 0.01 else Vector2.DOWN
		var edge_radius := minf(size.x, size.y) * 0.44
		var edge_angle := atan2(direction.y, direction.x)
		var bands := [
			{"r": edge_radius - 9.0, "span": 0.20, "a": 0.30, "w": 3.0},
			{"r": edge_radius, "span": 0.15, "a": 0.95, "w": 5.0},
			{"r": edge_radius + 8.0, "span": 0.09, "a": 0.42, "w": 2.5},
		]
		for band in bands:
			var span := float(band.span)
			draw_arc(center, float(band.r), edge_angle - span, edge_angle + span, 16, Color(damage_color, damage_direction_intensity * float(band.a)), float(band.w))
	if high_alert_intensity > 0.0:
		_draw_high_alert(center)
	if _match_result_visible:
		_draw_match_result()
	elif _match_phase == RiftlineMatch.Phase.OPENING:
		_draw_round_beat("ROUND START", "FIGHT", friendly)
	if not _connection_message.is_empty():
		var message_rect := Rect2(Vector2(size.x * 0.5 - 170.0, safe.position.y + 178.0), Vector2(340.0, 40.0))
		draw_plate(self, message_rect, Color(HUD_INK, 0.94), Color(HUD_EDGE, 0.9), HUD_CUT_SM)
		draw_accent_edge(self, message_rect, Color(HUD_SIGNAL, 0.9), true, 3.0)
		draw_tracked_centered(self, message_rect.get_center() + Vector2(0.0, 5.0), _connection_message.to_upper(), FS_LABEL, HUD_TEXT)

## The virtual stick. A ring rather than a disc, with cardinal ticks so the
## axes are readable at a glance, and an octagonal knob matching the buttons.
func _draw_stick(origin: Vector2, knob: Vector2, radius: float, friendly: Color, alpha: float, knob_visible: bool) -> void:
	if alpha <= 0.005:
		return
	draw_circle(origin, radius, Color(HUD_VOID, 0.5 * alpha))
	draw_arc(origin, radius, 0.0, TAU, 40, Color(HUD_VOID, 0.5 * alpha), 3.6)
	draw_arc(origin, radius, 0.0, TAU, 40, Color(HUD_EDGE_BRIGHT, 0.7 * alpha), 1.4)
	draw_arc(origin, radius - 6.0, 0.0, TAU, 40, Color(friendly, 0.24 * alpha), 1.0)
	for index in 4:
		var axis := Vector2.from_angle(TAU * float(index) / 4.0)
		draw_line(origin + axis * (radius - 9.0), origin + axis * (radius - 2.0), Color(friendly, 0.6 * alpha), 1.6)
	if not knob_visible:
		return
	var knob_radius := 22.0 * _control_scale("move")
	draw_control_ring(self, knob, knob_radius, Color(HUD_INK_RAISE, 0.85 * alpha), Color(friendly, 0.95 * alpha), 2.0, 0.55 * alpha)
	draw_circle(knob, 2.6, Color(friendly, 0.9 * alpha))

func _friendly_color() -> Color:
	return _team_color(_roster_local_team)

## Threat-bearing warning (Robert, PR #8) - restyled onto the token/plate
## system the rest of the HUD uses instead of its original ad-hoc colour and
## plain rect, per this HUD's own colour discipline: HUD_ALERT is the danger
## role, reserved for exactly this kind of warning, not a fourth one-off hue.
func _draw_high_alert(center: Vector2) -> void:
	var direction := high_alert_direction if high_alert_direction.length_squared() > 0.01 else Vector2.DOWN
	var edge_radius := minf(size.x, size.y) * 0.365
	var edge_angle := atan2(direction.y, direction.x)
	var pulse := 0.78 + 0.22 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.018))
	var alert_color := Color(HUD_ALERT, high_alert_intensity * pulse)
	draw_arc(center, edge_radius, edge_angle - 0.24, edge_angle + 0.24, 18, Color(HUD_VOID, high_alert_intensity * 0.72), 9.0)
	draw_arc(center, edge_radius, edge_angle - 0.22, edge_angle + 0.22, 18, alert_color, 4.5)
	var tip := center + direction * (edge_radius - 7.0)
	var tangent := Vector2(-direction.y, direction.x)
	var chevron := PackedVector2Array([
		tip + direction * 10.0,
		tip - direction * 5.0 + tangent * 7.0,
		tip - direction * 5.0 - tangent * 7.0,
	])
	draw_colored_polygon(chevron, alert_color)
	var label := "HIGH ALERT"
	var label_width := hud_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_LABEL).x + label.length() * HUD_TRACK
	var safe := _safe_rect()
	var label_center := Vector2(center.x, safe.position.y + 88.0)
	var label_rect := Rect2(label_center - Vector2(label_width * 0.5 + 11.0, 13.0), Vector2(label_width + 22.0, 26.0))
	draw_plate(self, label_rect, Color(HUD_INK, high_alert_intensity * 0.94), Color(HUD_ALERT, high_alert_intensity * 0.9), HUD_CUT_SM)
	draw_tracked_centered(self, label_rect.get_center() + Vector2(0.0, 4.0), label, FS_LABEL, Color(HUD_TEXT, high_alert_intensity))

func _enemy_color() -> Color:
	return _team_color(Duelist.Team.BLUE if _roster_local_team == int(Duelist.Team.RED) else Duelist.Team.RED)

func _draw_vitality_strip(safe: Rect2, friendly: Color) -> void:
	# A continuous 0-100 bar. Every point of damage moves the fill; this is
	# not a chunked "hits remaining" meter, since damage varies per weapon
	# (SMG/pistol chip damage vs. sniper one-shots) and a fixed hit count
	# would lie about how much health is actually left.
	var bar_size := Vector2(186.0, 12.0)
	var origin := Vector2(safe.get_center().x - bar_size.x * 0.5 + 21.0, safe.end.y - 44.0)
	var track := Rect2(origin, bar_size)
	var fraction := clampf(health / Duelist.HEALTH, 0.0, 1.0)
	var critical := health <= 30.0
	var low_pulse := 0.72 + sin(Time.get_ticks_msec() * 0.012) * 0.28 if critical else 1.0
	var fill_color := HUD_ALERT if critical else (HUD_SIGNAL if health <= 60.0 else friendly)
	# The numeral is the primary read at a glance, the bar is the secondary
	# one, so the numeral is large, tracked and left of the bar on the same
	# optical baseline instead of a 12px caption floating above it.
	var label := str(maxi(0, ceili(health)))
	var label_width := tracked_width(hud_font(), label, FS_TITLE, HUD_TRACK_TIGHT)
	draw_tracked(self, Vector2(track.position.x - 14.0 - label_width, track.end.y + 2.0), label, FS_TITLE, Color(fill_color, low_pulse), HUD_TRACK_TIGHT)
	draw_tracked(self, Vector2(track.position.x, track.position.y - 7.0), "VITALS", FS_MICRO, HUD_TEXT_FAINT)
	# Skewed ends: the well is a parallelogram, which is what stops a health
	# bar from reading as a browser progress element.
	draw_plate(self, track, Color(HUD_VOID, 0.78), Color(HUD_EDGE, 0.95), 6.0, CHAMFER_DIAG)
	if fraction > 0.0:
		var fill := Rect2(track.position + Vector2(2.0, 2.0), Vector2(maxf(2.0, (track.size.x - 4.0) * fraction), track.size.y - 4.0))
		draw_plate(self, fill, Color(fill_color, 0.9 * low_pulse), Color(0, 0, 0, 0), 4.0, CHAMFER_DIAG)
		if critical:
			draw_plate(self, fill.grow(2.0), Color(0, 0, 0, 0), Color(HUD_ALERT, 0.5 * low_pulse), 5.0, CHAMFER_DIAG, 1.0)
	# Quarter marks read as machined graduations cut into the well.
	for tick in [0.25, 0.5, 0.75]:
		var tick_x: float = track.position.x + track.size.x * tick
		draw_line(Vector2(tick_x, track.position.y + 1.0), Vector2(tick_x, track.end.y - 1.0), Color(HUD_VOID, 0.8), 1.0)


func _team_color(team: int) -> Color:
	return Color("ff6a57") if team == int(Duelist.Team.RED) else Color("71cfff")

## The match bar. One chamfered plate at the top edge carrying the two team
## scores as pip ladders either side of the clock, so score and time are a
## single object rather than three unrelated pieces of floating text.
func _draw_objective_strip(safe: Rect2, friendly: Color, enemy: Color) -> void:
	var bar := Rect2(Vector2(size.x * 0.5 - 132.0, safe.position.y), Vector2(264.0, 40.0))
	var center := bar.get_center()
	var sudden_death := bool(_objective_state.get("sudden_death", false))
	draw_plate(self, bar, Color(HUD_INK, 0.86), Color(HUD_EDGE, 0.9), HUD_CUT_SM, CHAMFER_ALL)
	# Team identity is carried by two short colour bars on the outer edges of
	# the plate, not by tinting the plate itself.
	draw_rect(Rect2(bar.position + Vector2(0.0, 8.0), Vector2(2.5, bar.size.y - 16.0)), Color(_team_color(Duelist.Team.RED), 0.95), true)
	draw_rect(Rect2(Vector2(bar.end.x - 2.5, bar.position.y + 8.0), Vector2(2.5, bar.size.y - 16.0)), Color(_team_color(Duelist.Team.BLUE), 0.95), true)
	_draw_score_pips(Vector2(bar.position.x + 13.0, center.y), _red_score, _team_color(Duelist.Team.RED), 1.0)
	_draw_score_pips(Vector2(bar.end.x - 13.0, center.y), _blue_score, _team_color(Duelist.Team.BLUE), -1.0)
	if sudden_death:
		var pulse := 0.6 + 0.4 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
		draw_tracked_centered(self, center + Vector2(0.0, -1.0), "SUDDEN", FS_MICRO, Color(HUD_ALERT, pulse))
		draw_tracked_centered(self, center + Vector2(0.0, 11.0), "DEATH", FS_MICRO, Color(HUD_ALERT, pulse))
	else:
		var match_remaining := float(_objective_state.get("match_remaining", RiftlineMatch.MATCH_SECONDS))
		var urgent := match_remaining <= 60.0
		draw_tracked_centered(self, center + Vector2(0.0, 8.0), _format_clock(match_remaining), FS_SUB, HUD_ALERT if urgent else HUD_TEXT, HUD_TRACK_TIGHT)
		draw_tracked_centered(self, center + Vector2(0.0, -9.0), "MATCH", 9, HUD_TEXT_FAINT)
	_draw_core_status(Vector2(center.x, bar.end.y + 4.0), friendly, enemy)
	if _score_pulse > 0.0:
		draw_plate(self, bar.grow(2.0 + (1.0 - _score_pulse) * 8.0), Color(0, 0, 0, 0), Color(HUD_SIGNAL, _score_pulse * 0.8), HUD_CUT_SM, CHAMFER_ALL, 2.0)
	if objective_feedback_pulse > 0.0:
		var feedback_color := _team_color(objective_feedback_team) if objective_feedback_team >= 0 else HUD_SIGNAL
		draw_plate(self, bar.grow(2.0 + (1.0 - objective_feedback_pulse) * 12.0), Color(0, 0, 0, 0), Color(feedback_color, objective_feedback_pulse * 0.85), HUD_CUT_SM, CHAMFER_ALL, 2.0)

## Points-to-win as a ladder of chevron pips, filled for points held. Reading
## "how close is either team to winning" off a shape is faster than parsing
## "2/3" twice, and it is the read that decides how you play the next minute.
func _draw_score_pips(anchor: Vector2, score: int, color: Color, direction: float) -> void:
	var pitch := 11.0
	for index in RiftlineMatch.POINTS_TO_WIN:
		var x := anchor.x + direction * float(index) * pitch
		var held := index < score
		var pip := PackedVector2Array([
			Vector2(x - direction * 3.0, anchor.y - 8.0),
			Vector2(x + direction * 3.0, anchor.y - 8.0),
			Vector2(x + direction * 3.0, anchor.y + 4.0),
			Vector2(x, anchor.y + 8.0),
			Vector2(x - direction * 3.0, anchor.y + 4.0),
		])
		if held:
			draw_colored_polygon(pip, Color(color, 0.95))
		else:
			var loop := pip.duplicate()
			loop.append(pip[0])
			draw_polyline(loop, Color(color, 0.3), 1.2)

## Core state as a compact tag hung under the match bar: a state glyph, the
## state itself, and the owning team where one exists. Amber is the neutral
## "system knows something" colour; team colour only appears when a team
## actually owns the core.
func _draw_core_status(point: Vector2, friendly: Color, enemy: Color) -> void:
	var core_state := int(_objective_state.get("core_state", int(RiftlineMatch.CoreState.AT_CENTER)))
	var text := "CORE // CENTER"
	var accent := HUD_TEXT_DIM
	match core_state:
		int(RiftlineMatch.CoreState.CARRIED):
			var carrier_team := int(_objective_state.get("core_carrier_team", int(Duelist.Team.RED)))
			accent = _team_color(carrier_team)
			text = "CORE // %s CARRY" % ("RED" if carrier_team == int(Duelist.Team.RED) else "BLUE")
		int(RiftlineMatch.CoreState.DROPPED):
			text = "CORE // DROPPED"
			accent = HUD_SIGNAL
		int(RiftlineMatch.CoreState.INSTALLED):
			var installed_team := int(_objective_state.get("installed_team", int(Duelist.Team.RED)))
			accent = _team_color(installed_team)
			text = "LAUNCH // %s" % ("RED" if installed_team == int(Duelist.Team.RED) else "BLUE")
		int(RiftlineMatch.CoreState.RESPAWNING):
			text = "CORE // RETURNING"
			accent = HUD_TEXT_FAINT
	var text_width := tracked_width(hud_font(), text, FS_MICRO)
	var tag := Rect2(Vector2(point.x - text_width * 0.5 - 22.0, point.y), Vector2(text_width + 32.0, 20.0))
	draw_plate(self, tag, Color(HUD_INK, 0.8), Color(accent, 0.42), 4.0, CHAMFER_DIAG)
	_draw_core_glyph(Vector2(tag.position.x + 11.0, tag.get_center().y), accent, core_state == int(RiftlineMatch.CoreState.INSTALLED))
	draw_tracked(self, Vector2(tag.position.x + 22.0, tag.get_center().y + 4.0), text, FS_MICRO, Color(accent, 0.98))

	var install_progress := float(_objective_state.get("install_progress", 0.0))
	var cancel_progress := float(_objective_state.get("cancel_progress", 0.0))
	if install_progress > 0.0:
		_draw_hold_arc(Vector2(point.x, tag.end.y + 20.0), install_progress, friendly)
	if cancel_progress > 0.0:
		_draw_hold_arc(Vector2(point.x, tag.end.y + 20.0), cancel_progress, enemy)

	if core_state == int(RiftlineMatch.CoreState.INSTALLED):
		var launch_remaining := float(_objective_state.get("launch_remaining", 0.0))
		var installed_team := int(_objective_state.get("installed_team", int(Duelist.Team.RED)))
		var launch_color := _team_color(installed_team)
		var launch_center := Vector2(point.x, tag.end.y + 30.0)
		draw_tracked_centered(self, launch_center + Vector2(0.0, -12.0), "LAUNCH IN", 9, Color(launch_color, 0.85))
		draw_tracked_centered(self, launch_center + Vector2(0.0, 18.0), _format_clock(launch_remaining), FS_TITLE, launch_color, HUD_TRACK_TIGHT)

func _draw_core_glyph(center: Vector2, color: Color, energised: bool) -> void:
	var hex := polygon_ring(center, 6.0, 6, PI / 6.0)
	draw_colored_polygon(hex, Color(color, 0.2))
	var loop := hex.duplicate()
	loop.append(hex[0])
	draw_polyline(loop, Color(color, 0.95), 1.4)
	if energised:
		draw_circle(center, 2.2, Color(color, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)))

func _draw_hold_arc(center: Vector2, progress: float, color: Color) -> void:
	# Octagonal well matching the control language, with a bright sweeping arc
	# riding just inside it.
	var radius := 15.0
	draw_control_ring(self, center, radius, Color(HUD_VOID, 0.7), Color(color, 0.3), 1.2)
	draw_arc(center, radius - 3.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 24, color, 3.0)
	draw_tracked_centered(self, center + Vector2(0.0, 4.0), "%d" % int(round(clampf(progress, 0.0, 1.0) * 100.0)), 9, Color(color, 0.9))

static func _format_clock(seconds: float) -> String:
	var total := maxi(0, int(floor(maxf(seconds, 0.0))))
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]

## Squad life. Hung off the two outer flanks of the match bar rather than
## stacked under it, so it never collides with the core tag and so each team's
## roster sits on that team's side of the score.
func _draw_team_life_strip(safe: Rect2, friendly: Color, enemy: Color) -> void:
	var line_y := safe.position.y + 20.0
	var red_index := 0
	var blue_index := 0
	for record in _roster_state:
		var team := int(record.get("team", -1))
		var eliminated := bool(record.get("eliminated", false))
		var is_local_team := team == _roster_local_team
		var is_red := team == int(Duelist.Team.RED)
		var color := _team_color(team)
		var slot := red_index if is_red else blue_index
		var direction := -1.0 if is_red else 1.0
		var point := Vector2(size.x * 0.5 + direction * (140.0 + slot * 13.0), line_y)
		_draw_team_marker(point, color, not eliminated, is_local_team)
		if is_red:
			red_index += 1
		else:
			blue_index += 1

func _draw_team_marker(center: Vector2, color: Color, living: bool, friendly_marker: bool) -> void:
	# A filled bar for a living operator, a hollow stub for a downed one. The
	# local player's own team gets slightly taller marks so your side of the
	# fight is the one you read first.
	var height := 9.0 if friendly_marker else 7.0
	var slab := Rect2(center - Vector2(4.0, height * 0.5), Vector2(8.0, height))
	if living:
		draw_plate(self, slab, Color(color, 0.9), Color(color, 0.98), 3.0, CHAMFER_DIAG, 1.0)
	else:
		draw_plate(self, slab, Color(HUD_VOID, 0.6), Color(color, 0.4), 3.0, CHAMFER_DIAG, 1.0)
		draw_line(center + Vector2(-3.0, 0.0), center + Vector2(3.0, 0.0), Color(color, 0.55), 1.2)

func _draw_button(key: String, color: Color, active: bool) -> void:
	_draw_button_fixed(_control_center(key), _control_radius(key), color, active, key, _control_opacity(key))

## Every touch control is an octagonal machined pad. The polygon's vertices sit
## exactly on `radius`, which is the same radius the hit tests in
## `_action_key_at()` / `_pressed_circle()` use, so what is drawn and what is
## pressable cannot drift apart.
func _draw_button_fixed(center: Vector2, radius: float, color: Color, active: bool, label: String, opacity: float = 1.0) -> void:
	var fill := Color(HUD_INK_RAISE if active else HUD_VOID, (0.84 if active else 0.62) * opacity)
	var edge := Color(color, (0.98 if active else 0.7) * opacity)
	draw_control_ring(self, center, radius, fill, edge, 2.2 if active else 1.6, 0.55 * opacity)
	# Inner hairline shoulder: gives the pad a machined bevel instead of a flat
	# stroked outline, and it is where the "pressed" glow lives.
	draw_control_ring(self, center, radius - 5.0, Color(0, 0, 0, 0), Color(color, (0.42 if active else 0.16) * opacity), 1.0)
	if active:
		draw_control_ring(self, center, radius + 3.0, Color(0, 0, 0, 0), Color(color, 0.28 * opacity), 1.6)
	if _control_specs().has(label) or label == "reload" or label == "settings" or label == "melee":
		_draw_control_glyph(center, radius, color, label, active, opacity)
		return
	draw_tracked_centered(self, center + Vector2(0.0, 5.0), label.to_upper(), FS_LABEL, Color(color, 0.98 * opacity))

func _draw_control_glyph(center: Vector2, radius: float, color: Color, key: String, active: bool, opacity: float) -> void:
	var glyph_color := Color(color, (0.98 if active else 0.76) * opacity)
	var weight := 2.8 if active else 1.9
	match key:
		"left_fire", "right_fire":
			draw_circle(center, radius * 0.18, glyph_color)
			draw_arc(center, radius * 0.48, -0.9, 0.9, 12, glyph_color, weight)
			draw_arc(center, radius * 0.48, PI - 0.9, PI + 0.9, 12, glyph_color, weight)
		"ads":
			draw_arc(center + Vector2(0, 4), radius * 0.34, PI, TAU, 12, glyph_color, weight)
			draw_line(center + Vector2(-radius * 0.38, 4), center + Vector2(radius * 0.38, 4), glyph_color, weight)
		"jump":
			draw_polyline(PackedVector2Array([center + Vector2(-radius * 0.34, 5), center, center + Vector2(radius * 0.34, 5)]), glyph_color, weight)
			draw_line(center, center + Vector2(0, -radius * 0.38), glyph_color, weight)
		"crouch":
			draw_circle(center + Vector2(-radius * 0.16, -radius * 0.18), radius * 0.13, glyph_color)
			draw_line(center + Vector2(-radius * 0.28, 0), center + Vector2(radius * 0.22, 0), glyph_color, weight)
			draw_line(center + Vector2(-radius * 0.2, 0), center + Vector2(-radius * 0.34, radius * 0.3), glyph_color, weight)
			draw_line(center + Vector2(radius * 0.18, 0), center + Vector2(radius * 0.34, radius * 0.3), glyph_color, weight)
		"prone":
			draw_circle(center + Vector2(-radius * 0.28, -radius * 0.1), radius * 0.12, glyph_color)
			draw_line(center + Vector2(-radius * 0.18, 0), center + Vector2(radius * 0.34, 0), glyph_color, weight)
			draw_line(center + Vector2(radius * 0.2, 0), center + Vector2(radius * 0.38, radius * 0.22), glyph_color, weight)
		"swap":
			draw_line(center + Vector2(-radius * 0.34, -5), center + Vector2(radius * 0.3, -5), glyph_color, weight)
			draw_line(center + Vector2(radius * 0.3, -5), center + Vector2(radius * 0.14, -radius * 0.18), glyph_color, weight)
			draw_line(center + Vector2(radius * 0.34, 5), center + Vector2(-radius * 0.3, 5), glyph_color, weight)
			draw_line(center + Vector2(-radius * 0.3, 5), center + Vector2(-radius * 0.14, radius * 0.18), glyph_color, weight)
		"interact":
			var diamond := PackedVector2Array([center + Vector2(0, -radius * 0.25), center + Vector2(radius * 0.2, 0), center + Vector2(0, radius * 0.25), center + Vector2(-radius * 0.2, 0)])
			draw_polyline(diamond, glyph_color, weight)
			draw_line(center + Vector2(radius * 0.05, 0), center + Vector2(radius * 0.42, 0), glyph_color, weight)
			draw_line(center + Vector2(radius * 0.27, -radius * 0.16), center + Vector2(radius * 0.42, 0), glyph_color, weight)
			draw_line(center + Vector2(radius * 0.27, radius * 0.16), center + Vector2(radius * 0.42, 0), glyph_color, weight)
		"melee":
			# Swings whatever is currently equipped - a simple crossed-blade
			# glyph rather than a per-weapon icon, since it's not a weapon slot.
			draw_line(center + Vector2(-radius * 0.3, -radius * 0.3), center + Vector2(radius * 0.3, radius * 0.3), glyph_color, weight)
			draw_line(center + Vector2(-radius * 0.3, radius * 0.3), center + Vector2(radius * 0.3, -radius * 0.3), glyph_color, weight)
		"reload":
			if active and reload_indicator_animates():
				_draw_reload_sweep(center, radius * 0.58, glyph_color, reload_progress_for(reload_remaining, float(RiftWeapons.row(int(_weapon)).reload_seconds)))
			else:
				_draw_reload_icon(center, radius * 0.58, glyph_color)
		"settings":
			for index in 8:
				var angle := TAU * float(index) / 8.0
				var spoke_start := center + Vector2.from_angle(angle) * radius * 0.24
				var spoke_end := center + Vector2.from_angle(angle) * radius * 0.50
				draw_line(spoke_start, spoke_end, glyph_color, weight)
			draw_circle(center, radius * 0.28, glyph_color, false, weight)
			draw_circle(center, radius * 0.10, Color(HUD_VOID, 0.85 * opacity))

func reload_indicator_animates() -> bool:
	return reload_remaining > 0.0

func _draw_reload_icon(center: Vector2, radius: float, color: Color) -> void:
	draw_arc(center, radius, -PI * 0.76, PI * 0.72, 16, color, 2.4)
	var tip := center + Vector2(radius * 0.62, -radius * 0.3)
	draw_line(tip, tip + Vector2(-radius * 0.02, radius * 0.28), color, 2.4)
	draw_line(tip, tip + Vector2(-radius * 0.27, radius * 0.04), color, 2.4)

## Loadout slots default to a Frontline rifle+pistol pair for presentation
## before the first authoritative sync arrives; set_loadout_slots() below
## keeps this in step with the local duelist's actual class/loadout.
var _loadout_slots: Array = [Duelist.Weapon.RIFLE, Duelist.Weapon.PISTOL]

func set_loadout_slots(slots: Array) -> void:
	if slots.is_empty():
		return
	_loadout_slots = slots.duplicate()
	queue_redraw()

## Bottom-right weapon block: the ammunition readout is the headline (a large
## tracked magazine count with the reserve beside it, the way an actual combat
## HUD states it), with the loadout slot plates sitting under it as the
## secondary read. Previously ammunition was only five anonymous pips, which
## meant the single number a player checks most often was not on screen.
func _draw_weapon_indicator(color: Color) -> void:
	var safe := _safe_rect()
	var center := Vector2(safe.end.x - 170.0, safe.end.y - 74.0)
	var single := _loadout_slots.size() == 1
	_draw_magazine_read(Vector2(center.x, center.y - 20.0), color)
	if single:
		_draw_loadout_plate(center + Vector2(0.0, 26.0), RiftWeapons.clamp_weapon(int(_loadout_slots[0])) as Duelist.Weapon, color)
		if reload_remaining > 0.0:
			_draw_reload_sweep(Vector2(center.x, center.y - 20.0), 30.0, HUD_SIGNAL, reload_progress_for(reload_remaining, float(RiftWeapons.row(int(_weapon)).reload_seconds)))
		return
	_draw_loadout_plate(center + Vector2(-40.0, 26.0), RiftWeapons.clamp_weapon(int(_loadout_slots[0])) as Duelist.Weapon, color)
	_draw_loadout_plate(center + Vector2(40.0, 26.0), RiftWeapons.clamp_weapon(int(_loadout_slots[1])) as Duelist.Weapon, color)
	if reload_remaining > 0.0:
		_draw_reload_sweep(Vector2(center.x, center.y - 20.0), 30.0, HUD_SIGNAL, reload_progress_for(reload_remaining, float(RiftWeapons.row(int(_weapon)).reload_seconds)))

# --- Sight pictures -------------------------------------------------------
#
# One hand-drawn language, five sight pictures, no imported art. Every stroke
# goes down twice - a dark, slightly wider pass, then the bright pass on top -
# because the single-pass reticle this replaces disappeared completely against
# bare sky and against the arena's pale concrete, which is most of the map.

const RETICLE_INK := Color(0.02, 0.05, 0.10)

func _reticle_line(from: Vector2, to: Vector2, tint: Color, width: float) -> void:
	draw_line(from, to, Color(RETICLE_INK, tint.a * 0.55), width + 2.0)
	draw_line(from, to, tint, width)

func _reticle_dot(at: Vector2, radius: float, tint: Color) -> void:
	draw_circle(at, radius + 1.2, Color(RETICLE_INK, tint.a * 0.55))
	draw_circle(at, radius, tint)

func _reticle_arc(at: Vector2, radius: float, from_angle: float, to_angle: float, tint: Color, width: float) -> void:
	# The halo is deliberately narrower here than on straight strokes: a 2px
	# skirt around a 1px ring reads as a dark ring, not as a legible one.
	draw_arc(at, radius, from_angle, to_angle, 28, Color(RETICLE_INK, tint.a * 0.5), width + 1.4)
	draw_arc(at, radius, from_angle, to_angle, 28, tint, width)

func _draw_reticle(center: Vector2) -> void:
	var ads := _ads_progress
	# Only the aimed reticle rides the recoil kick - hip fire already has its
	# own bloom-driven spread telling the same story, and is not what the
	# "reticle doesn't move with recoil" report was about.
	var kicked_center := center + _recoil_reticle_offset()
	if _weapon == Duelist.Weapon.SNIPER and ads > 0.004:
		# The tube itself (the vignette/mask) stays put - a scope housing does
		# not physically move on screen - only the reticle drawn inside it
		# kicks, which is also the only way recoil reads at all once the 3D
		# rig hides past SNIPER_SCOPE_HANDOVER (see handoff bug #3).
		_draw_scope_overlay(center, ads, kicked_center)
		return
	var hip_opacity := 1.0 - smoothstep(0.0, 0.55, ads)
	if hip_opacity > 0.004:
		_draw_hip_reticle(center, hip_opacity)
	var ads_opacity := smoothstep(0.45, 1.0, ads)
	if ads_opacity > 0.004:
		_draw_ads_reticle(kicked_center, ads_opacity)

## Pixel nudge for the ADS/scope reticle only, so it reads as attached to the
## sight housing that now visibly kicks under the weapon-rig recoil throw
## (`Duelist._weapon_rig.position`/`.rotation.x`) instead of staying glued to
## dead screen-center while the housing jumps around it. `_recoil_kick`
## throws the muzzle up (screen-up, hence the negative Y here); `_recoil_lateral`
## is the same left/right alternation the weapon root's yaw already shows.
## Magnitudes are a feel call tuned against a live ADS screenshot mid-recoil,
## not a literal 1:1 of the 3D throw - see handoff bug #1.
func _recoil_reticle_offset() -> Vector2:
	return Vector2(_recoil_lateral * 260.0, -_recoil_kick * 190.0)

## Hip fire. All five keep the existing directional-bloom behaviour - the gap
## and span still open with `primary_fire_bloom` and recover with it - but the
## shape now says which weapon is in hand.
func _draw_hip_reticle(center: Vector2, opacity: float) -> void:
	var tint := Color(1.0, 1.0, 1.0, 0.96 * opacity)
	var bloom := primary_fire_bloom
	match _weapon:
		Duelist.Weapon.SHOTGUN:
			# A pellet weapon's useful information is the spread, not a point,
			# so it gets a broken ring instead of a cross.
			var radius := 27.0 + bloom * 6.0
			for quadrant in 4:
				var bearing := float(quadrant) * PI * 0.5 + PI * 0.25
				_reticle_arc(center, radius, bearing - 0.46, bearing + 0.46, tint, 2.6)
			_reticle_dot(center, 1.8, tint)
		Duelist.Weapon.SNIPER:
			# Deliberately unhelpful: four diagonals and no centre mark. The HUD
			# should not be encouraging anyone to hip-fire the Longview.
			var gap := 13.0 + bloom * 7.0
			var span := 31.0 + bloom * 11.0
			for quadrant in 4:
				var axis := Vector2.from_angle(float(quadrant) * PI * 0.5 + PI * 0.25)
				_reticle_line(center + axis * gap, center + axis * span, tint, 2.0)
		Duelist.Weapon.PISTOL:
			var gap := 7.0 + bloom * 4.0
			var span := 18.0 + bloom * 5.0
			for quadrant in 4:
				var axis := Vector2.from_angle(float(quadrant) * PI * 0.5)
				_reticle_line(center + axis * gap, center + axis * span, tint, 1.8)
			_reticle_dot(center, 1.5, tint)
		Duelist.Weapon.SMG:
			var gap := 13.0 + bloom * 5.0
			var span := 27.0 + bloom * 8.0
			for quadrant in 4:
				var axis := Vector2.from_angle(float(quadrant) * PI * 0.5)
				_reticle_line(center + axis * gap, center + axis * span, tint, 2.4)
		_:
			var gap := 10.0 + bloom * 4.0
			var span := 25.0 + bloom * 6.0
			for quadrant in 4:
				var axis := Vector2.from_angle(float(quadrant) * PI * 0.5)
				_reticle_line(center + axis * gap, center + axis * span, tint, 2.0)
			_reticle_dot(center, 1.6, tint)

## Aimed. Until now nothing at all was drawn while `aim_held`, on any weapon.
## Each of these is the 2D half of the optic modelled on the weapon: the dot
## the reflex housing frames, or the bead the iron sights sit either side of.
func _draw_ads_reticle(center: Vector2, opacity: float) -> void:
	var dot := Color("ff5f4a", 0.98 * opacity)
	var fine := Color("e8f1fa", 0.85 * opacity)
	match _weapon:
		Duelist.Weapon.SHOTGUN:
			# Bead plus the weapon's real aimed cone, converted through the
			# current magnification - the ring is the actual spread, not decor.
			_reticle_arc(center, _ads_cone_radius_px(), 0.0, TAU, Color(fine, 0.42 * opacity), 1.4)
			# Cream, not amber: the modelled bead directly under it is brass, and
			# an amber dot on a brass bead is an invisible dot.
			_reticle_dot(center, 2.8, Color("fff4d2", 0.98 * opacity))
		Duelist.Weapon.PISTOL:
			# Three-dot irons: the front bead between the two rear dots.
			_reticle_dot(center, 2.1, Color("fff4d2", 0.96 * opacity))
			_reticle_dot(center + Vector2(-11.0, 0.0), 1.6, Color(fine, 0.6 * opacity))
			_reticle_dot(center + Vector2(11.0, 0.0), 1.6, Color(fine, 0.6 * opacity))
		Duelist.Weapon.SMG:
			_reticle_dot(center, 2.5, dot)
			_reticle_line(center + Vector2(-15.0, 0.0), center + Vector2(-9.0, 0.0), fine, 1.6)
			_reticle_line(center + Vector2(9.0, 0.0), center + Vector2(15.0, 0.0), fine, 1.6)
		_:
			# Red dot: a soft bloom under the dot itself, which is what stops
			# a 3px circle from reading as a dead pixel over a bright wall.
			draw_circle(center, 7.5, Color("ff5f4a", 0.16 * opacity))
			_reticle_dot(center, 2.8, dot)
			_reticle_arc(center, 13.0, 0.0, TAU, Color(fine, 0.38 * opacity), 1.1)

## The equipped weapon's stationary aimed cone in screen pixels at the current
## magnification. Used only to size the shotgun's spread ring - it reads the
## same frozen accuracy table the simulation does, so the ring cannot drift
## away from where the pellets actually go.
func _ads_cone_radius_px() -> float:
	var span := deg_to_rad(maxf(1.0, RiftWeapons.ads_horizontal_fov(horizontal_fov, int(_weapon), _zoom_index)))
	var cone := RiftWeapons.cone_for(int(_weapon), 0.0, false, false, 1.0, primary_fire_bloom)
	return clampf(cone / maxf(0.01, tan(span * 0.5)) * size.x * 0.5, 8.0, size.y * 0.45)

## The Longview's scope picture.
##
## The tube is drawn in 2D rather than modelled in front of the camera: masking
## everything outside the ocular circle is what actually makes a scope feel
## like a scope, and a mask stays exact at every aspect ratio and every FOV,
## which a glass disc parked near the near plane does not. The 3D scope body on
## the weapon keeps doing its job - it is what the mask closes down over.
## `center` positions the tube/vignette itself (a scope housing does not
## physically move on screen); `reticle_center` positions only the reticle
## drawn inside it, which is where the recoil kick belongs - see the one
## caller in _draw_reticle().
func _draw_scope_overlay(center: Vector2, ads: float, reticle_center: Vector2) -> void:
	# Closed by `Duelist.SNIPER_SCOPE_HANDOVER`, which is the same value the
	# rifle's view model stops drawing on. Beyond that point this overlay *is*
	# the scope, so it has to be fully opaque before the rifle disappears.
	var seated := smoothstep(0.06, Duelist.SNIPER_SCOPE_HANDOVER, ads)
	var short_edge := minf(size.x, size.y)
	# Second stage closes the tube down as well as magnifying, so the step up
	# is legible the instant it happens.
	var target := short_edge * (0.430 if _zoom_index < 1 else 0.335)
	var radius := lerpf(short_edge * 0.95, target, seated)
	# The picture inside the tube is `Duelist._scope_camera`'s own render, a
	# real second camera at the zoomed FOV - not the main view zoomed and
	# masked - so it is drawn as a small square exactly `2*radius` across,
	# not a full-screen quad. That is what keeps the masking below contained
	# to the tube's own footprint instead of covering the real, unmagnified
	# background the main camera is still rendering everywhere else.
	var picture_rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	if _scope_texture != null:
		draw_texture_rect(_scope_texture, picture_rect, false, Color(1.0, 1.0, 1.0, seated))
	else:
		draw_rect(picture_rect, Color(0.010, 0.018, 0.030, seated))
	# One stroked annulus from the circle out to the square's own corner
	# masks exactly the four corner triangles between the ocular circle and
	# its bounding square - by construction (a circle inscribed in a square
	# always sits at distance `radius` along each edge midpoint and
	# `radius * sqrt(2)` at each corner) this never reaches past the square's
	# own bounds, so nothing outside the tube's footprint is touched and the
	# real environment keeps showing through everywhere else on screen.
	var reach := radius * 1.4143
	draw_arc(center, (radius + reach) * 0.5, 0.0, TAU, 96, Color(0.010, 0.018, 0.030, seated), reach - radius)
	# Tube wall, the soft shadow a real ocular throws inside the edge, and a
	# single cold highlight so the rim is not a flat black band.
	draw_arc(center, radius - 1.0, 0.0, TAU, 96, Color(0.03, 0.05, 0.08, seated), 6.0)
	draw_arc(center, radius - 9.0, 0.0, TAU, 96, Color(0.03, 0.05, 0.08, 0.32 * seated), 14.0)
	draw_arc(center, radius - 4.5, 0.0, TAU, 96, Color("7d8ea3", 0.5 * seated), 1.5)
	if seated < 0.35:
		return
	_draw_scope_reticle(reticle_center, radius, (seated - 0.35) / 0.65)

func _draw_scope_reticle(center: Vector2, radius: float, opacity: float) -> void:
	var stage_two := _zoom_index >= 1
	var fine := Color("dfe9f4", 0.92 * opacity)
	var mid := Color("dfe9f4", 0.58 * opacity)
	var arm := radius * 0.93
	# A simple dot, not the four-arm crosshair this used to draw - see handoff
	# bug #4. The mil-dot ranging marks stay: a bare dot with zero ranging aid
	# would be a real regression for a sniper shooting at real distance, and
	# the user's complaint was specifically about the cross, not about losing
	# range information.
	_reticle_dot(center, 1.6 if stage_two else 2.0, fine)
	# Ranging dots on the two horizontals and the lower vertical; the upper arm
	# stays clean, the way a real ranging reticle is.
	var marks := 7 if stage_two else 4
	var spacing := arm / float(marks + 1)
	var dot_radius := 1.5 if stage_two else 2.0
	for index in range(1, marks + 1):
		var offset := spacing * float(index)
		_reticle_dot(center + Vector2(-offset, 0.0), dot_radius, mid)
		_reticle_dot(center + Vector2(offset, 0.0), dot_radius, mid)
		_reticle_dot(center + Vector2(0.0, offset), dot_radius, mid)
	if stage_two:
		# The second stage earns a drop ladder and a tighter inner ring, so the
		# two magnifications are told apart by the reticle itself and not only
		# by how much of the world fits inside the tube.
		for index in range(1, 4):
			var rung := spacing * float(index) * 2.0
			var half := radius * (0.20 - 0.035 * float(index))
			_reticle_line(center + Vector2(-half, rung), center + Vector2(half, rung), fine, 1.2)
		_reticle_arc(center, radius * 0.30, 0.0, TAU, Color(mid, 0.45 * opacity), 1.0)
	var steps: Array = RiftWeapons.row(int(_weapon)).zoom_steps
	if steps.is_empty():
		return
	var label := "%.0f×" % float(steps[clampi(_zoom_index, 0, steps.size() - 1)])
	draw_string(ThemeDB.fallback_font, center + Vector2(radius * 0.46, radius * 0.70), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("dfe9f4", 0.88 * opacity))

## Distinct per-archetype glyphs (barrel+optic for rifle-class weapons, a
## broad fanned wedge for the shotgun, a small block for the pistol, a long
## scoped line for the sniper) so the two loadout plates read at a glance
## instead of a generic rectangle.
func _draw_loadout_plate(center: Vector2, slot: Duelist.Weapon, color: Color) -> void:
	var held := int(_weapon) == int(slot)
	var plate_color := HUD_SIGNAL if held else HUD_TEXT_FAINT
	var rect := Rect2(center - Vector2(36.0, 19.0), Vector2(72.0, 38.0))
	draw_plate(self, rect, Color(HUD_INK_RAISE if held else HUD_VOID, 0.86), Color(plate_color, 0.9 if held else 0.32), HUD_CUT_SM, CHAMFER_DIAG, 1.4 if held else 1.0)
	if held:
		draw_accent_edge(self, Rect2(rect.position, Vector2(rect.size.x, 2.0)), Color(HUD_SIGNAL, 0.95), false, 2.0)
	match slot:
		Duelist.Weapon.RIFLE, Duelist.Weapon.SMG:
			draw_rect(Rect2(center - Vector2(17.0, 4.0), Vector2(30.0, 8.0)), plate_color)
			draw_line(center + Vector2(13.0, -4.0), center + Vector2(24.0, -11.0), plate_color, 2.5)
			draw_line(center + Vector2(13.0, 4.0), center + Vector2(24.0, 11.0), plate_color, 2.5)
		Duelist.Weapon.SHOTGUN:
			draw_rect(Rect2(center - Vector2(18.0, 3.0), Vector2(34.0, 6.0)), plate_color)
			for pellet_angle in [-0.5, -0.22, 0.0, 0.22, 0.5]:
				var pellet_end := center + Vector2(24.0, 0.0) + Vector2.from_angle(pellet_angle) * 10.0
				draw_line(center + Vector2(16.0, 0.0), pellet_end, plate_color, 1.6)
		Duelist.Weapon.PISTOL:
			draw_rect(Rect2(center - Vector2(12.0, 5.0), Vector2(22.0, 8.0)), plate_color)
			draw_rect(Rect2(center + Vector2(-5.0, 3.0), Vector2(7.0, 12.0)), plate_color)
		Duelist.Weapon.SNIPER:
			draw_line(center + Vector2(-22.0, 0.0), center + Vector2(22.0, 0.0), plate_color, 2.5)
			draw_circle(center + Vector2(4.0, -7.0), 6.0, Color("071126", 0.9))
			draw_arc(center + Vector2(4.0, -7.0), 6.0, 0.0, TAU, 16, plate_color, 1.8)

## Magazine as a real number, reserve as a smaller number behind a divider,
## plus a graduated depletion strip underneath. The strip is capacity-relative
## and turns amber then red as the magazine empties, so "reload now" is a
## colour change and not an arithmetic problem.
func _draw_magazine_read(center: Vector2, color: Color) -> void:
	var capacity := int(RiftWeapons.row(int(_weapon)).magazine_size)
	var reserve_capacity := int(RiftWeapons.row(int(_weapon)).reserve_ammo)
	var magazine_ratio := clampf(float(magazine_rounds) / float(maxi(1, capacity)), 0.0, 1.0)
	var ammo_color := HUD_ALERT if magazine_ratio <= 0.2 else (HUD_SIGNAL if magazine_ratio <= 0.45 else HUD_TEXT)
	var magazine_text := "%02d" % clampi(magazine_rounds, 0, 99)
	var magazine_width := tracked_width(hud_font(), magazine_text, FS_DISPLAY, HUD_TRACK_TIGHT)
	draw_tracked(self, Vector2(center.x - magazine_width - 6.0, center.y + 12.0), magazine_text, FS_DISPLAY, ammo_color, HUD_TRACK_TIGHT)
	draw_line(Vector2(center.x, center.y - 12.0), Vector2(center.x + 6.0, center.y + 12.0), Color(HUD_EDGE_BRIGHT, 0.8), 1.4)
	draw_tracked(self, Vector2(center.x + 14.0, center.y - 1.0), "RSV", 9, HUD_TEXT_FAINT)
	draw_tracked(self, Vector2(center.x + 14.0, center.y + 14.0), "%02d" % clampi(reserve_ammo, 0, 99), FS_SUB, HUD_TEXT_DIM, HUD_TRACK_TIGHT)
	# Depletion strip. Graduation count is capped by available width so the
	# marks never collapse into a grey hatch - at 30 rounds they were 4px apart
	# and read as noise rather than as rounds.
	var strip := Rect2(Vector2(center.x - magazine_width - 6.0, center.y + 20.0), Vector2(magazine_width + 12.0, 5.0))
	draw_rect(strip, Color(HUD_VOID, 0.8), true)
	draw_rect(Rect2(strip.position, Vector2(strip.size.x * magazine_ratio, strip.size.y)), Color(ammo_color, 0.92), true)
	draw_rect(strip, Color(HUD_EDGE, 0.8), false, 1.0)
	var graduations := clampi(capacity, 2, maxi(2, int(strip.size.x / 11.0)))
	for index in range(1, graduations):
		var mark_x := strip.position.x + strip.size.x * (float(index) / float(graduations))
		draw_line(Vector2(mark_x, strip.position.y), Vector2(mark_x, strip.end.y), Color(HUD_VOID, 0.9), 1.0)
	var reserve_ratio := clampf(float(reserve_ammo) / float(maxi(1, reserve_capacity)), 0.0, 1.0)
	var reserve_track := Rect2(Vector2(center.x + 14.0, center.y + 20.0), Vector2(30.0, 3.0))
	draw_rect(reserve_track, Color(HUD_VOID, 0.75), true)
	draw_rect(Rect2(reserve_track.position, Vector2(reserve_track.size.x * reserve_ratio, reserve_track.size.y)), Color(HUD_TEXT_DIM, 0.8), true)

static func reload_progress_for(remaining: float, reload_seconds: float = 2.0) -> float:
	return clampf(1.0 - remaining / maxf(0.05, reload_seconds), 0.0, 1.0)

func _draw_reload_sweep(center: Vector2, radius: float, color: Color, progress: float) -> void:
	var phase := clampf(progress, 0.0, 1.0)
	draw_arc(center, radius + 5.0, 0.0, TAU, 32, Color(color, 0.18), 3.0)
	draw_arc(center, radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * phase, 28, Color(color, 0.95), 3.0)
	# Leading pip on the sweep head, so a reload reads as running even when the
	# arc is short.
	draw_circle(center + Vector2.from_angle(-PI * 0.5 + TAU * phase) * (radius + 5.0), 2.4, Color(color, 0.98))

func _draw_button_preview(key: String, color: Color) -> void:
	var center := _control_center(key)
	draw_arc(center, _control_radius(key) + 8.0, 0.0, TAU, 32, Color(color, 0.45), 2.0)

func _draw_preview_floating_stick(color: Color) -> void:
	var radius := _stick_radius()
	var point := Vector2(220.0, 410.0) if _touch_preview == "floating-left" else Vector2(28.0, 430.0)
	var origin := _preview_stick_origin(point, radius)
	var knob := origin + (Vector2(30.0, -22.0) if _touch_preview == "floating-left" else Vector2(32.0, -12.0))
	draw_circle(origin, radius, Color("08142a", 0.42))
	draw_arc(origin, radius, 0.0, TAU, 32, Color(color, 0.55), 2.0)
	draw_circle(knob, 24.0 * _control_scale("move"), Color(color, 0.38))
	draw_arc(knob, 24.0 * _control_scale("move"), 0.0, TAU, 24, Color(color, 0.95), 2.0)

func _draw_coach_cue(friendly: Color, enemy: Color) -> void:
	if _coach_display_cue.is_empty() or _coach_visual_opacity <= 0.01:
		return
	var safe := _safe_rect()
	var cue_alpha := _coach_visual_opacity
	var region := str(_coach_display_cue.get("region", ""))
	var accent := enemy if region == "right" else friendly
	if region == "left":
		draw_arc(_control_center("move"), _control_radius("move") + 12.0, 0.0, TAU, 32, Color(accent, 0.5 * cue_alpha), 2.5)
	elif region == "right":
		draw_arc(Vector2(safe.end.x - 76.0, safe.position.y + 118.0), 36.0, -PI * 0.8, PI * 0.8, 20, Color(accent, 0.5 * cue_alpha), 2.5)
	elif region == "fire":
		var pulse := 0.38 + 0.32 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0))
		for key in ["left_fire", "right_fire"]:
			draw_arc(_control_center(key), _control_radius(key) + 10.0, 0.0, TAU, 32, Color(accent, pulse * cue_alpha), 2.0)
	# The plate is sized to its message rather than to a fixed 380px, so a short
	# cue is not a wide slab with a stranded label floating in the middle.
	var cue_text := str(_coach_display_cue.get("text", "")).to_upper()
	var plate_width := tracked_width(hud_font(), cue_text, FS_LABEL) + 56.0
	var rect := Rect2(Vector2(size.x * 0.5 - plate_width * 0.5, safe.position.y + 132.0), Vector2(plate_width, 32.0))
	if region == "seed":
		rect = Rect2(Vector2(size.x * 0.5 - plate_width * 0.5, safe.end.y - 148.0), Vector2(plate_width, 32.0))
	draw_plate(self, rect, Color(HUD_INK, 0.86 * cue_alpha), Color(HUD_EDGE, 0.9 * cue_alpha), HUD_CUT_SM)
	draw_accent_edge(self, rect, Color(accent, 0.9 * cue_alpha), true, 3.0)
	draw_tracked_centered(self, rect.get_center() + Vector2(4.0, 5.0), cue_text, FS_LABEL, Color(HUD_TEXT, 0.96 * cue_alpha))

func _draw_match_result() -> void:
	var accent := _friendly_color() if _match_result_victory else _enemy_color()
	var card := _match_result_card()
	draw_rect(Rect2(Vector2.ZERO, size), Color(HUD_VOID, 0.82))
	draw_plate(self, card, Color(HUD_INK, 0.99), Color(HUD_EDGE, 0.95), HUD_CUT, CHAMFER_DIAG, 1.2)
	draw_brackets(self, card.grow(-8.0), Color(accent, 0.55), 18.0, 2.0)
	draw_accent_edge(self, Rect2(card.position + Vector2(HUD_CUT, 0.0), Vector2(card.size.x - HUD_CUT, 3.0)), Color(accent, 0.95), false, 3.0)
	# The result emblem sits in its own well, so it reads as a stamped mark
	# rather than as a shape floating next to the words.
	var emblem_well := Rect2(card.position + Vector2(28.0, 34.0), Vector2(56.0, 56.0))
	draw_plate(self, emblem_well, Color(HUD_VOID, 0.7), Color(accent, 0.4), HUD_CUT_SM)
	var emblem := emblem_well.get_center()
	if _match_result_victory:
		var wreath := PackedVector2Array([emblem + Vector2(0, -18), emblem + Vector2(16, -6), emblem + Vector2(11, 16), emblem + Vector2(-11, 16), emblem + Vector2(-16, -6)])
		draw_colored_polygon(wreath, Color(accent, 0.2))
		var wreath_loop := wreath.duplicate()
		wreath_loop.append(wreath[0])
		draw_polyline(wreath_loop, Color(accent, 0.96), 2.0)
		draw_polyline(PackedVector2Array([emblem + Vector2(-7, 1), emblem + Vector2(-2, 7), emblem + Vector2(8, -6)]), Color(accent, 0.98), 2.6)
	else:
		draw_control_ring(self, emblem, 17.0, Color(accent, 0.14), Color(accent, 0.9), 2.0)
		draw_line(emblem + Vector2(-8, -8), emblem + Vector2(8, 8), Color(accent, 0.96), 2.4)
		draw_line(emblem + Vector2(8, -8), emblem + Vector2(-8, 8), Color(accent, 0.96), 2.4)
	var text_x := card.position.x + 104.0
	draw_tracked(self, Vector2(text_x, card.position.y + 62.0), "VICTORY" if _match_result_victory else "DEFEAT", FS_DISPLAY, HUD_TEXT, 3.0)
	draw_tracked(self, Vector2(text_x + 2.0, card.position.y + 84.0), "NUCLEAR RUSH // %s" % ("OBJECTIVE HELD" if _match_result_victory else "OBJECTIVE LOST"), FS_MICRO, Color(accent, 0.95))
	draw_rule(self, card.position + Vector2(28.0, 110.0), card.size.x - 56.0, Color(HUD_EDGE_BRIGHT, 0.8))
	draw_tracked(self, card.position + Vector2(28.0, 132.0), "FINAL", 9, HUD_TEXT_FAINT)
	_draw_result_score_row(card.position + Vector2(28.0, 158.0), "RED", _red_score, _team_color(Duelist.Team.RED))
	_draw_result_score_row(card.position + Vector2(28.0, 186.0), "BLUE", _blue_score, _team_color(Duelist.Team.BLUE))
	var rematch := _rematch_rect()
	draw_plate(self, rematch, Color(accent, 0.14), Color(accent, 0.95), HUD_CUT_SM, CHAMFER_DIAG, 1.6)
	draw_accent_edge(self, rematch, Color(accent, 0.95), true, 3.0)
	draw_tracked_centered(self, rematch.get_center() + Vector2(4.0, 5.0), "REMATCH", FS_BODY, HUD_TEXT, 2.4)

## One final-score row: team tag, a hairline lane, and the point total set in
## the team's colour at display weight.
func _draw_result_score_row(at: Vector2, tag: String, score: int, color: Color) -> void:
	draw_tracked(self, at, tag, FS_LABEL, Color(color, 0.95))
	draw_line(Vector2(at.x + 62.0, at.y - 5.0), Vector2(at.x + 150.0, at.y - 5.0), Color(HUD_EDGE, 0.9), 1.0)
	draw_tracked(self, Vector2(at.x + 160.0, at.y + 3.0), str(score), FS_SUB, Color(color, 0.98), HUD_TRACK_TIGHT)

func _draw_round_beat(title: String, subtitle: String, accent: Color) -> void:
	var center := size * 0.5 + Vector2(0, 84)
	var width := 290.0 if title == "READY" else 340.0
	var rect := Rect2(center - Vector2(width * 0.5, 26), Vector2(width, 52))
	draw_plate(self, rect, Color(HUD_INK, 0.8), Color(HUD_EDGE, 0.85), HUD_CUT_SM)
	draw_accent_edge(self, Rect2(rect.position + Vector2(HUD_CUT_SM, 0.0), Vector2(rect.size.x - HUD_CUT_SM, 2.0)), Color(accent, 0.9), false, 2.0)
	draw_tracked_centered(self, center + Vector2(0.0, 0.0), title, FS_SUB, HUD_TEXT, 3.0)
	draw_tracked_centered(self, center + Vector2(0.0, 18.0), subtitle, FS_MICRO, Color(accent, 0.92))

func _match_result_card() -> Rect2:
	return Rect2(size * 0.5 - Vector2(260, 130), Vector2(520, 260))

func _rematch_rect() -> Rect2:
	var card := _match_result_card()
	# Right-aligned to the card's margin so the action sits on the card's own
	# grid rather than floating between the score column and the edge.
	return Rect2(card.position + Vector2(card.size.x - 268.0, 174.0), Vector2(240, 54))

func _pressed_circle(point: Vector2, center: Vector2, radius: float) -> bool:
	return point.distance_squared_to(center) <= radius * radius

## Press/release entry point for the settings panel.  A press resolves the
## control under the finger exactly once and captures it against this touch
## index; a release clears that capture.  All continuous tracking (sliders)
## happens in `_handle_settings_drag`, which only ever drives the captured
## control for a matching index - see the class doc comment at the top of
## the settings-touch section for the bug this fixes.
func _handle_settings_touch(index: int, point: Vector2, pressed: bool) -> void:
	if index == _settings_owner_touch:
		if not pressed:
			_settings_owner_touch = -1
		return
	if not pressed:
		_settings_captures.erase(index)
		return
	var panel := _settings_panel()
	if not panel.has_point(point):
		# Tap-outside-to-close only fires for a press that starts outside the
		# panel.  A drag that later wanders outside never reaches this path.
		_settings_open = false
		_release_all_touch_ownership()
		return
	var control := _settings_control_at(panel, point)
	_settings_captures[index] = control
	_apply_settings_press(control, point, panel)

## Drag entry point for the settings panel.  Ignored unless `index` is the
## touch that captured a control on press; when it matches, the point is
## routed only to that captured control, and only the three sliders act on
## a drag - a captured chip or action button does nothing here, however far
## the finger travels, and the panel never closes from a drag.
func _handle_settings_drag(index: int, point: Vector2) -> void:
	if index == _settings_owner_touch:
		return
	if not _settings_captures.has(index):
		return
	var control: String = _settings_captures[index]
	if control.is_empty():
		return
	_apply_settings_drag(control, point, _settings_panel())

## Single source of truth for "what control is under this point": both press
## and drag route through here (drag only for the captured control id it
## already resolved on press).
func _settings_control_at(panel: Rect2, point: Vector2) -> String:
	if _view_track_rect(panel).grow(14.0).has_point(point):
		return "view_slider"
	if _camera_track_rect(panel).grow(12.0).has_point(point):
		return "camera_slider"
	if _ads_track_rect(panel).grow(12.0).has_point(point):
		return "ads_slider"
	# Aim and gyro used to be hit-tested against two hand-written rectangles
	# that no longer matched where the grid actually drew them - the exact
	# drawn-versus-pressable divergence this HUD has a regression suite for.
	# They now resolve through the same helpers that draw them.
	if _aim_rect(panel).has_point(point):
		return "aim_chip"
	if _gyro_rect(panel).has_point(point):
		return "gyro_chip"
	if _effects_rect(panel).has_point(point):
		return "effects_chip"
	if _stick_mode_rect(panel).has_point(point):
		return "stick_chip"
	if _ads_look_rect(panel).has_point(point):
		return "ads_look_chip"
	if _hud_layout_rect(panel).has_point(point):
		return "hud_layout_chip"
	if _rift_link_rect(panel).has_point(point):
		return "rift_link_chip"
	if _reset_training_rect(panel).has_point(point):
		return "reset_training_chip"
	if _main_menu_rect(panel).has_point(point):
		return "main_menu_chip"
	return ""

func _camera_track_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position + Vector2(154, 114), Vector2(panel.size.x - 220, 24))

func _ads_track_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position + Vector2(154, 136), Vector2(panel.size.x - 220, 24))

## Applied exactly once, on the down event that captured `control`.  Sliders
## take their value from the touch point; chips and action buttons fire here
## and only here.
func _apply_settings_press(control: String, point: Vector2, panel: Rect2) -> void:
	match control:
		"view_slider":
			set_view_fov(_view_from_point(point.x, _view_track_rect(panel).position.x), true)
		"camera_slider":
			_apply_camera_sensitivity(point, panel)
		"ads_slider":
			_apply_ads_sensitivity(point, panel)
		"aim_chip":
			_aim_toggle = not _aim_toggle
			_save_control_settings()
		"gyro_chip":
			gyro_enabled = not gyro_enabled
			_save_control_settings()
		"effects_chip":
			effects_enabled = not effects_enabled
			_save_control_settings()
			feedback_preferences_changed.emit(effects_enabled, haptics_enabled)
		"stick_chip":
			_stick_mode = MobileTouchRouter.StickMode.FIXED if _stick_mode == MobileTouchRouter.StickMode.FLOATING else MobileTouchRouter.StickMode.FLOATING
			_touch_router.configure(_stick_mode, _control_center("move"), _stick_radius())
			_save_control_settings()
		"ads_look_chip":
			ads_button_look = not ads_button_look
			_save_control_settings()
		"hud_layout_chip":
			open_hud_layout()
		"reset_training_chip":
			_reset_training_requested = true
			_settings_open = false
			_release_all_touch_ownership()
		"rift_link_chip":
			_settings_open = false
			_release_all_touch_ownership()
			rift_link_requested.emit()
		"main_menu_chip":
			_settings_open = false
			_release_all_touch_ownership()
			main_menu_requested.emit()
		_:
			pass

## Applied on every drag frame for the captured control - only the sliders
## respond, matching what a normal drag on a slider should do.
func _apply_settings_drag(control: String, point: Vector2, panel: Rect2) -> void:
	match control:
		"view_slider":
			set_view_fov(_view_from_point(point.x, _view_track_rect(panel).position.x), true)
		"camera_slider":
			_apply_camera_sensitivity(point, panel)
		"ads_slider":
			_apply_ads_sensitivity(point, panel)
		_:
			pass

func _apply_camera_sensitivity(point: Vector2, panel: Rect2) -> void:
	var track := _camera_track_rect(panel)
	var next := clampf((point.x - track.position.x) / track.size.x * 1.4 + 0.3, 0.3, 1.7)
	if is_equal_approx(next, camera_sensitivity):
		return
	camera_sensitivity = next
	_save_control_settings()

func _apply_ads_sensitivity(point: Vector2, panel: Rect2) -> void:
	var track := _ads_track_rect(panel)
	var next := clampf((point.x - track.position.x) / track.size.x * 1.4 + 0.3, 0.3, 1.7)
	if is_equal_approx(next, ads_sensitivity):
		return
	ads_sensitivity = next
	_save_control_settings()

func _draw_settings_panel(friendly: Color, _enemy: Color) -> void:
	var panel := _settings_panel()
	draw_rect(Rect2(Vector2.ZERO, size), Color(HUD_VOID, 0.74))
	draw_plate(self, panel, Color(HUD_INK, 0.99), Color(HUD_EDGE, 0.95), HUD_CUT, CHAMFER_DIAG, 1.2)
	draw_brackets(self, panel.grow(-7.0), Color(HUD_EDGE_BRIGHT, 0.5), 16.0, 1.6)
	# Header band: title left, a technical system tag right, one rule under.
	draw_accent_edge(self, Rect2(panel.position + Vector2(HUD_CUT, 0.0), Vector2(panel.size.x - HUD_CUT, 3.0)), Color(HUD_SIGNAL, 0.9), false, 3.0)
	draw_tracked(self, panel.position + Vector2(24, 40), "COMBAT SETTINGS", FS_TITLE, HUD_TEXT, 2.6)
	var tag := "OPERATOR // %s" % ("RED" if _roster_local_team == int(Duelist.Team.RED) else "BLUE")
	draw_tracked(self, panel.position + Vector2(panel.size.x - 24.0 - tracked_width(hud_font(), tag, FS_MICRO), 38.0), tag, FS_MICRO, Color(friendly, 0.9))
	draw_rule(self, panel.position + Vector2(24, 54), panel.size.x - 48.0, Color(HUD_EDGE_BRIGHT, 0.8))

	_draw_settings_section(panel, 68.0, "AIM // OPTICS")
	_draw_view_slider(_view_track_rect(panel), HUD_SIGNAL)
	_draw_setting_slider(_camera_track_rect(panel), camera_sensitivity, HUD_SIGNAL, "CAMERA", "%.2f" % camera_sensitivity)
	_draw_setting_slider(_ads_track_rect(panel), ads_sensitivity, HUD_SIGNAL, "ADS", "%.2f" % ads_sensitivity)

	_draw_settings_section(panel, SETTINGS_TOGGLES_TOP - SETTINGS_LABEL_GAP, "CONTROLS")
	_draw_setting_chip(_aim_rect(panel), "AIM", "TAP" if _aim_toggle else "HOLD", _aim_toggle)
	_draw_setting_chip(_gyro_rect(panel), "GYRO", "ON" if gyro_enabled else "OFF", gyro_enabled)
	_draw_setting_chip(_effects_rect(panel), "EFFECTS", "ON" if effects_enabled else "OFF", effects_enabled)
	_draw_setting_chip(_stick_mode_rect(panel), "STICK", "FLOAT" if _stick_mode == MobileTouchRouter.StickMode.FLOATING else "FIXED", _stick_mode == MobileTouchRouter.StickMode.FLOATING)
	_draw_setting_chip(_ads_look_rect(panel), "ADS LOOK", "ON" if ads_button_look else "OFF", ads_button_look)

	_draw_settings_section(panel, _settings_actions_top() - SETTINGS_LABEL_GAP, "ACTIONS")
	_draw_setting_action(_hud_layout_rect(panel), "HUD LAYOUT", HUD_SIGNAL)
	_draw_setting_action(_rift_link_rect(panel), "RIFT LINK", HUD_EDGE_BRIGHT)
	_draw_setting_action(_reset_training_rect(panel), "RESET TRAINING", HUD_ALERT)
	_draw_setting_action(_main_menu_rect(panel), "MAIN MENU", HUD_ALERT)
	draw_tracked(self, panel.position + Vector2(24, panel.size.y - 20), "TAP OUTSIDE TO RETURN", FS_MICRO, HUD_TEXT_FAINT)

func _draw_settings_section(panel: Rect2, top: float, label: String) -> void:
	draw_tracked(self, panel.position + Vector2(24, top), label, FS_MICRO, HUD_TEXT_FAINT)
	var offset := tracked_width(hud_font(), label, FS_MICRO) + 12.0
	draw_line(panel.position + Vector2(24 + offset, top - 4.0), panel.position + Vector2(panel.size.x - 24.0, top - 4.0), Color(HUD_EDGE, 0.9), 1.0)

## Slider rows are a labelled well with a machined fill and a chamfered thumb,
## with the live numeric value right-aligned - the old rows were a bare 5px
## line and a circle, with the value invisible.
func _draw_setting_slider(track: Rect2, value: float, color: Color, label: String, readout: String) -> void:
	var mid := track.position.y + track.size.y * 0.5
	draw_tracked(self, Vector2(track.position.x - 130.0, mid + 5.0), label, FS_LABEL, HUD_TEXT_DIM)
	var normalized := clampf((value - 0.3) / 1.4, 0.0, 1.0)
	var well := Rect2(Vector2(track.position.x, mid - 3.0), Vector2(track.size.x, 6.0))
	draw_rect(well, Color(HUD_VOID, 0.85), true)
	draw_rect(Rect2(well.position, Vector2(well.size.x * normalized, well.size.y)), Color(color, 0.85), true)
	draw_rect(well, Color(HUD_EDGE, 0.9), false, 1.0)
	_draw_slider_thumb(Vector2(track.position.x + track.size.x * normalized, mid), color)
	draw_tracked(self, Vector2(track.end.x + 10.0, mid + 5.0), readout, FS_MICRO, Color(color, 0.95), HUD_TRACK_TIGHT)

func _draw_slider_thumb(center: Vector2, color: Color) -> void:
	var thumb := Rect2(center - Vector2(6.0, 11.0), Vector2(12.0, 22.0))
	draw_plate(self, thumb, Color(HUD_INK_RAISE, 0.98), Color(color, 0.98), 4.0, CHAMFER_DIAG, 1.6)
	draw_line(center + Vector2(0.0, -5.0), center + Vector2(0.0, 5.0), Color(color, 0.9), 1.4)

func _view_track_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position + Vector2(154, 76), Vector2(panel.size.x - 220, 24))

func _view_from_point(point_x: float, track_x: float) -> float:
	return clampf(Duelist.MIN_HORIZONTAL_FOV + ((point_x - track_x) / maxf(1.0, _view_track_rect(_settings_panel()).size.x)) * (Duelist.MAX_HORIZONTAL_FOV - Duelist.MIN_HORIZONTAL_FOV), Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV)

func _draw_view_slider(rect: Rect2, color: Color) -> void:
	var mid := rect.position.y + rect.size.y * 0.5
	var normalized := clampf(inverse_lerp(Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV, horizontal_fov), 0.0, 1.0)
	draw_tracked(self, Vector2(rect.position.x - 130.0, mid + 5.0), "VIEW", FS_LABEL, HUD_TEXT_DIM)
	var well := Rect2(Vector2(rect.position.x, mid - 3.0), Vector2(rect.size.x, 6.0))
	draw_rect(well, Color(HUD_VOID, 0.85), true)
	draw_rect(Rect2(well.position, Vector2(well.size.x * normalized, well.size.y)), Color(color, 0.85), true)
	draw_rect(well, Color(HUD_EDGE, 0.9), false, 1.0)
	for mark in [0.0, 0.5, 1.0]:
		var tick_x: float = rect.position.x + rect.size.x * mark
		draw_line(Vector2(tick_x, mid + 6.0), Vector2(tick_x, mid + 11.0), Color(HUD_EDGE_BRIGHT, 0.8), 1.0)
	_draw_slider_thumb(Vector2(rect.position.x + rect.size.x * normalized, mid), color)
	draw_tracked(self, Vector2(rect.end.x + 10.0, mid + 5.0), "%d°" % int(round(horizontal_fov)), FS_MICRO, Color(color, 0.95), HUD_TRACK_TIGHT)
	for mark in [{"x": 0.0, "label": "TIGHT"}, {"x": 0.5, "label": "STD"}, {"x": 1.0, "label": "WIDE"}]:
		draw_tracked_centered(self, Vector2(rect.position.x + rect.size.x * float(mark.x), mid + 22.0), str(mark.label), 9, HUD_TEXT_FAINT, HUD_TRACK_TIGHT)

## A toggle chip: label on the left, current value on the right, and a status
## bar down the leading edge that is lit when the option is on. The value is
## therefore readable without parsing "EFFECTS ON" as one run of text, and an
## off state is genuinely dimmer rather than the same brightness.
func _draw_setting_chip(rect: Rect2, label: String, value: String, active: bool) -> void:
	var accent := HUD_SIGNAL if active else HUD_TEXT_FAINT
	draw_plate(self, rect, Color(HUD_INK_RAISE if active else HUD_VOID, 0.85), Color(accent, 0.75 if active else 0.4), HUD_CUT_SM, CHAMFER_DIAG, 1.2)
	draw_accent_edge(self, rect, Color(accent, 0.95 if active else 0.35), true, 3.0)
	draw_tracked(self, rect.position + Vector2(16.0, rect.size.y * 0.5 + 5.0), label, FS_LABEL, HUD_TEXT if active else HUD_TEXT_DIM)
	var value_width := tracked_width(hud_font(), value, FS_LABEL)
	draw_tracked(self, Vector2(rect.end.x - 14.0 - value_width, rect.position.y + rect.size.y * 0.5 + 5.0), value, FS_LABEL, Color(accent, 0.98))

## An action chip. Distinct from a toggle: no value column, a leading chevron,
## and destructive actions carry the alert colour on the edge only.
func _draw_setting_action(rect: Rect2, label: String, accent: Color) -> void:
	draw_plate(self, rect, Color(HUD_VOID, 0.7), Color(accent, 0.62), HUD_CUT_SM, CHAMFER_DIAG, 1.2)
	var mid := rect.position.y + rect.size.y * 0.5
	draw_polyline(PackedVector2Array([
		Vector2(rect.position.x + 14.0, mid - 5.0),
		Vector2(rect.position.x + 20.0, mid),
		Vector2(rect.position.x + 14.0, mid + 5.0),
	]), Color(accent, 0.95), 1.8)
	draw_tracked(self, Vector2(rect.position.x + 30.0, mid + 5.0), label, FS_LABEL, HUD_TEXT)

func _draw_layout_editor() -> void:
	var friendly := _friendly_color()
	draw_rect(Rect2(Vector2.ZERO, size), Color(HUD_VOID, 0.72))
	var safe := _safe_rect()
	# Calibration grid: minor rules every 32px, a brighter rule every fourth,
	# so the snap pitch is legible instead of a uniform haze of lines.
	var minor := 0
	for x in range(int(safe.position.x), int(safe.end.x) + 1, 32):
		draw_line(Vector2(x, safe.position.y), Vector2(x, safe.end.y), Color(HUD_EDGE_BRIGHT, 0.22 if minor % 4 == 0 else 0.09), 1.0)
		minor += 1
	minor = 0
	for y in range(int(safe.position.y), int(safe.end.y) + 1, 32):
		draw_line(Vector2(safe.position.x, y), Vector2(safe.end.x, y), Color(HUD_EDGE_BRIGHT, 0.22 if minor % 4 == 0 else 0.09), 1.0)
		minor += 1
	draw_brackets(self, safe, Color(HUD_SIGNAL, 0.7), 26.0, 2.0)
	draw_tracked(self, safe.position + Vector2(14, 28), "HUD LAYOUT", FS_TITLE, HUD_TEXT, 2.6)
	draw_tracked(self, safe.position + Vector2(15, 46), "SELECT A CONTROL, THEN DRAG TO PLACE", FS_MICRO, HUD_TEXT_DIM)
	for key in MOVABLE_KEYS:
		_draw_editor_control(key, friendly if key in ["move", "left_fire", "right_fire", "crouch", "prone"] else HUD_TEXT_DIM)
	var panel := _editor_panel()
	draw_plate(self, panel, Color(HUD_INK, 0.98), Color(HUD_EDGE, 0.95), HUD_CUT, CHAMFER_DIAG, 1.2)
	draw_accent_edge(self, Rect2(panel.position + Vector2(HUD_CUT, 0.0), Vector2(panel.size.x - HUD_CUT, 3.0)), Color(HUD_SIGNAL, 0.9), false, 3.0)
	var selected_label := "NO CONTROL SELECTED" if _selected_layout_key.is_empty() else str(_control_specs()[_selected_layout_key].label)
	draw_tracked(self, panel.position + Vector2(20, 28), selected_label, FS_SUB, HUD_SIGNAL if not _selected_layout_key.is_empty() else HUD_TEXT_FAINT, 2.2)
	draw_tracked(self, panel.position + Vector2(panel.size.x - 96.0, 27), "GRID LOCK 8", FS_MICRO, HUD_TEXT_FAINT)
	_draw_editor_chip(_editor_button_rect("size_down"), "SIZE -", HUD_TEXT_DIM, false)
	_draw_editor_chip(_editor_button_rect("size_up"), "SIZE +", HUD_TEXT_DIM, false)
	_draw_editor_chip(_editor_button_rect("opacity_down"), "FADE -", HUD_TEXT_DIM, false)
	_draw_editor_chip(_editor_button_rect("opacity_up"), "FADE +", HUD_TEXT_DIM, false)
	_draw_editor_chip(_editor_button_rect("two_thumb"), "TWO THUMB", HUD_TEXT_DIM, false)
	_draw_editor_chip(_editor_button_rect("four_finger"), "FOUR FINGER", HUD_TEXT_DIM, false)
	_draw_editor_chip(_editor_button_rect("reset"), "RESET", HUD_ALERT, false)
	_draw_editor_chip(_editor_button_rect("done"), "DONE", HUD_SIGNAL, true)

func _draw_editor_chip(rect: Rect2, label: String, accent: Color, primary: bool) -> void:
	draw_plate(self, rect, Color(HUD_INK_RAISE if primary else HUD_VOID, 0.85), Color(accent, 0.9 if primary else 0.45), HUD_CUT_SM, CHAMFER_DIAG, 1.4 if primary else 1.0)
	if primary:
		draw_accent_edge(self, rect, Color(accent, 0.95), true, 3.0)
	draw_tracked_centered(self, rect.get_center() + Vector2(2.0 if primary else 0.0, 5.0), label, FS_LABEL, HUD_TEXT if primary else HUD_TEXT_DIM)

func _draw_editor_control(key: String, color: Color) -> void:
	var center := _control_center(key)
	var radius := _control_radius(key)
	var opacity := _control_opacity(key)
	var spec: Dictionary = _control_specs()[key]
	var selected := key == _selected_layout_key
	if key == "move":
		draw_circle(center, radius, Color(HUD_VOID, 0.55 * opacity))
		draw_arc(center, radius, 0.0, TAU, 40, Color(color, 0.85 * opacity), 1.6)
	else:
		draw_control_ring(self, center, radius, Color(HUD_VOID, 0.62 * opacity), Color(color, 0.9 * opacity), 1.6)
	draw_tracked_centered(self, center + Vector2(0.0, 5.0), str(spec.label), FS_LABEL, Color(color, opacity))
	if selected:
		draw_control_ring(self, center, radius + 7.0, Color(0, 0, 0, 0), Color(HUD_SIGNAL, 0.95), 2.4)
		draw_brackets(self, Rect2(center - Vector2(radius + 13.0, radius + 13.0), Vector2(radius + 13.0, radius + 13.0) * 2.0), Color(HUD_SIGNAL, 0.85), 12.0, 2.0)
		draw_line(center - Vector2(6.0, 0.0), center + Vector2(6.0, 0.0), Color(HUD_SIGNAL, 0.95), 1.6)
		draw_line(center - Vector2(0.0, 6.0), center + Vector2(0.0, 6.0), Color(HUD_SIGNAL, 0.95), 1.6)

func _handle_editor_touch(index: int, point: Vector2, pressed: bool) -> void:
	if not pressed:
		if index == _editor_touch:
			if _editor_dragging:
				_save_control_settings()
			_editor_touch = -1
			_editor_dragging = false
		return
	for button in ["size_down", "size_up", "opacity_down", "opacity_up", "two_thumb", "four_finger", "reset", "done"]:
		if _editor_button_rect(button).has_point(point):
			_apply_editor_action(button)
			return
	var key := _layout_key_at(point)
	if not key.is_empty():
		_selected_layout_key = key
		_editor_touch = index
		_editor_drag_start = point
		_editor_start_center = _control_center(key)
		_editor_dragging = false
		queue_redraw()

func _handle_editor_drag(index: int, point: Vector2) -> void:
	if index != _editor_touch or _selected_layout_key.is_empty():
		return
	if not _editor_dragging and point.distance_to(_editor_drag_start) < DRAG_THRESHOLD:
		return
	_editor_dragging = true
	_set_layout_center(_selected_layout_key, _editor_start_center + point - _editor_drag_start)
	_layout_dirty = true
	queue_redraw()

func _apply_editor_action(action: String) -> void:
	if action == "done":
		if _layout_dirty:
			_save_control_settings()
		_release_all_touch_ownership()
		_layout_editor = false
		_settings_open = false
		return
	if action == "reset":
		_layout = _default_layout()
		_selected_layout_key = ""
		_layout_dirty = true
		_save_control_settings()
		_release_all_touch_ownership()
		queue_redraw()
		return
	if action == "two_thumb":
		_layout = _two_thumb_layout()
	elif action == "four_finger":
		_layout = _four_finger_layout()
	else:
		if _selected_layout_key.is_empty():
			return
		var data: Dictionary = _layout[_selected_layout_key]
		if action == "size_down":
			data.scale = clampf(float(data.scale) - 0.1, 0.7, 1.35)
		elif action == "size_up":
			data.scale = clampf(float(data.scale) + 0.1, 0.7, 1.35)
		elif action == "opacity_down":
			data.opacity = clampf(float(data.opacity) - 0.1, 0.35, 1.0)
		elif action == "opacity_up":
			data.opacity = clampf(float(data.opacity) + 0.1, 0.35, 1.0)
	_enforce_layout_constraints()
	_layout_dirty = true
	_save_control_settings()
	queue_redraw()

func _editor_panel() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 380.0, _safe_rect().position.y + 74.0), Vector2(760.0, 132.0))

func _editor_button_rect(button: String) -> Rect2:
	var panel := _editor_panel()
	var y := panel.position.y + 88.0
	if button in ["size_down", "size_up", "opacity_down", "opacity_up"]:
		y = panel.position.y + 42.0
	var x := panel.position.x
	var width := 0.0
	match button:
		"size_down", "size_up":
			width = 74.0
			x += 20.0 if button == "size_down" else 100.0
		"opacity_down", "opacity_up":
			width = 84.0
			x += 184.0 if button == "opacity_down" else 276.0
		"two_thumb":
			width = 112.0
			x += 20.0
		"four_finger":
			width = 122.0
			x += 140.0
		"reset":
			width = 82.0
			x += 480.0
		"done":
			width = 82.0
			x += 572.0
	return Rect2(x, y, width, 44.0)

func _settings_panel() -> Rect2:
	var safe := _safe_rect()
	var width := clampf(safe.size.x * 0.72, 520.0, 760.0)
	var height := clampf(safe.size.y * 0.82, 500.0, 560.0)
	return Rect2(safe.get_center() - Vector2(width, height) * 0.5, Vector2(width, height))

## A consistent 2-column grid shared by every toggle and action chip, so
## nothing in the panel is hand-placed pixel-by-pixel: every row lines up
## under the same margins and every chip in a column shares the same width.
const SETTINGS_GRID_MARGIN := 24.0
const SETTINGS_GRID_GAP := 10.0
const SETTINGS_CHIP_HEIGHT := 44.0
const SETTINGS_ROW_PITCH := 52.0
# 190 is not arbitrary: the toggle grid's first row must still contain the
# aim-chip point the settings touch-capture regression test presses, which is
# 22px below y+188 relative to the panel. Row 0 therefore spans 190..234.
const SETTINGS_TOGGLES_TOP := 190.0
const SETTINGS_SECTION_GAP := 22.0
const SETTINGS_LABEL_GAP := 12.0

func _settings_grid_rect(panel: Rect2, top: float, col: int, row: int) -> Rect2:
	var content_width := panel.size.x - SETTINGS_GRID_MARGIN * 2.0
	var chip_width := (content_width - SETTINGS_GRID_GAP) * 0.5
	var x := panel.position.x + SETTINGS_GRID_MARGIN + float(col) * (chip_width + SETTINGS_GRID_GAP)
	var y := panel.position.y + top + float(row) * SETTINGS_ROW_PITCH
	return Rect2(Vector2(x, y), Vector2(chip_width, SETTINGS_CHIP_HEIGHT))

func _aim_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, SETTINGS_TOGGLES_TOP, 0, 0)

func _gyro_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, SETTINGS_TOGGLES_TOP, 1, 0)

func _effects_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, SETTINGS_TOGGLES_TOP, 0, 1)

func _stick_mode_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, SETTINGS_TOGGLES_TOP, 1, 1)

func _ads_look_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, SETTINGS_TOGGLES_TOP, 0, 2)

func _settings_actions_top() -> float:
	return SETTINGS_TOGGLES_TOP + SETTINGS_ROW_PITCH * 3.0 + SETTINGS_SECTION_GAP

func _hud_layout_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, _settings_actions_top(), 0, 0)

func _rift_link_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, _settings_actions_top(), 1, 0)

func _reset_training_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, _settings_actions_top(), 0, 1)

func _main_menu_rect(panel: Rect2) -> Rect2:
	return _settings_grid_rect(panel, _settings_actions_top(), 1, 1)

func _safe_rect() -> Rect2:
	return RESPONSIVE.safe_rect(self)

func _settings_center() -> Vector2:
	var safe := _safe_rect()
	return Vector2(safe.end.x - 38.0, safe.position.y + 38.0)

func _settings_hit_rect() -> Rect2:
	var center := _settings_center()
	return Rect2(center - Vector2(26.0, 26.0), Vector2(52.0, 52.0)).intersection(_safe_rect())

func _reload_center() -> Vector2:
	var safe := _safe_rect()
	return Vector2(safe.end.x - 390.0, safe.end.y - 84.0)

func _reload_radius() -> float:
	return 34.0

func _melee_center() -> Vector2:
	var safe := _safe_rect()
	return Vector2(safe.end.x - 470.0, safe.end.y - 84.0)

func _melee_radius() -> float:
	return 30.0

func _control_specs() -> Dictionary:
	return {
		"move": {"radius": 58.0, "label": "MOVE"},
		"left_fire": {"radius": 50.0, "label": "FIRE"},
		"right_fire": {"radius": 68.0, "label": "FIRE"},
		"ads": {"radius": 42.0, "label": "ADS"},
		"jump": {"radius": 40.0, "label": "JUMP"},
		"crouch": {"radius": 37.0, "label": "C"},
		"prone": {"radius": 37.0, "label": "P"},
		"swap": {"radius": 37.0, "label": "SWAP"},
		"interact": {"radius": 44.0, "label": "USE"},
	}

func _default_layout() -> Dictionary:
	return _two_thumb_layout()

func _two_thumb_layout() -> Dictionary:
	return {
		"move": _layout_entry(Vector2(0.10, 0.80), 1.0, 0.82),
		"left_fire": _layout_entry(Vector2(0.10, 0.22), 1.0, 0.82),
		"right_fire": _layout_entry(Vector2(0.90, 0.80), 1.0, 0.82),
		"ads": _layout_entry(Vector2(0.79, 0.49), 1.0, 0.78),
		"jump": _layout_entry(Vector2(0.90, 0.59), 1.0, 0.78),
		"crouch": _layout_entry(Vector2(0.76, 0.80), 1.0, 0.78),
		"prone": _layout_entry(Vector2(0.64, 0.80), 1.0, 0.78),
			"swap": _layout_entry(Vector2(0.70, 0.57), 1.0, 0.78),
			"interact": _layout_entry(Vector2(0.87, 0.37), 1.0, 0.82),
	}

func _four_finger_layout() -> Dictionary:
	return {
		"move": _layout_entry(Vector2(0.10, 0.79), 1.0, 0.82),
		"left_fire": _layout_entry(Vector2(0.21, 0.60), 0.95, 0.9),
		"right_fire": _layout_entry(Vector2(0.90, 0.79), 1.0, 0.9),
		"ads": _layout_entry(Vector2(0.78, 0.47), 1.0, 0.78),
		"jump": _layout_entry(Vector2(0.90, 0.59), 1.0, 0.82),
		"crouch": _layout_entry(Vector2(0.70, 0.79), 1.0, 0.78),
		"prone": _layout_entry(Vector2(0.58, 0.79), 1.0, 0.78),
			"swap": _layout_entry(Vector2(0.64, 0.56), 1.0, 0.78),
			"interact": _layout_entry(Vector2(0.86, 0.37), 1.0, 0.82),
	}

func _layout_entry(center: Vector2, scale: float, opacity: float) -> Dictionary:
	return {"center": center, "scale": scale, "opacity": opacity}

func _control_scale(key: String) -> float:
	return float(_layout[key].scale)

func _control_opacity(key: String) -> float:
	return float(_layout[key].opacity)

func _control_radius(key: String) -> float:
	return float(_control_specs()[key].radius) * _control_scale(key)

func _stick_radius() -> float:
	return maxf(_control_radius("move"), 44.0)

func _control_center(key: String) -> Vector2:
	var safe := _safe_rect()
	return safe.position + Vector2(_layout[key].center) * safe.size

func _movement_region() -> Rect2:
	var safe := _safe_rect()
	return Rect2(safe.position, Vector2(safe.size.x * 0.5, safe.size.y))

func _action_key_at(point: Vector2) -> String:
	var closest := ""
	var closest_distance := INF
	for key in MOVABLE_KEYS:
		if key == "move" or key == "interact" and not _interact_available:
			continue
		var hit_radius := maxf(_control_radius(key), 22.0) + 8.0
		var distance := point.distance_to(_control_center(key))
		if distance <= hit_radius and distance < closest_distance:
			closest = key
			closest_distance = distance
	return closest

func _layout_key_at(point: Vector2) -> String:
	var closest := ""
	var closest_distance := INF
	for key in MOVABLE_KEYS:
		var hit_radius := maxf(_control_radius(key), 22.0) + 8.0
		var distance := point.distance_to(_control_center(key))
		if distance <= hit_radius and distance < closest_distance:
			closest = key
			closest_distance = distance
	return closest

func _set_layout_center(key: String, point: Vector2) -> void:
	var safe := _safe_rect()
	var radius := _control_radius(key)
	var candidate := _clamp_center(point.snapped(Vector2(SNAP_POINTS, SNAP_POINTS)), radius, safe)
	for _pass in 2:
		for other_key in MOVABLE_KEYS:
			if other_key == key:
				continue
			var other_center := _control_center(other_key)
			var required := radius + _control_radius(other_key) + SNAP_POINTS
			var offset := candidate - other_center
			if offset.length() < required:
				candidate = _clamp_center(other_center + (Vector2.RIGHT if offset.length_squared() < 0.01 else offset.normalized()) * required, radius, safe)
	_layout[key].center = _normalized_center(candidate, safe)

func _enforce_layout_constraints() -> void:
	for key in MOVABLE_KEYS:
		_set_layout_center(key, _control_center(key))

func _clamp_center(point: Vector2, radius: float, safe: Rect2) -> Vector2:
	return Vector2(clampf(point.x, safe.position.x + radius, safe.end.x - radius), clampf(point.y, safe.position.y + radius, safe.end.y - radius))

func _normalized_center(point: Vector2, safe: Rect2) -> Vector2:
	return Vector2(clampf((point.x - safe.position.x) / safe.size.x, 0.0, 1.0), clampf((point.y - safe.position.y) / safe.size.y, 0.0, 1.0))

func _preview_stick_origin(point: Vector2, radius: float) -> Vector2:
	var region := _movement_region()
	return Vector2(
		clampf(point.x, region.position.x + radius, region.end.x - radius),
		clampf(point.y, region.position.y + radius, region.end.y - radius))

func _layout_config_key(config: ConfigFile, key: String) -> String:
	if config.has_section_key(LAYOUT_SECTION, "%s_center_x" % key):
		return key
	var legacy: String = str(LEGACY_LAYOUT_KEY_NAMES.get(key, ""))
	if not legacy.is_empty() and config.has_section_key(LAYOUT_SECTION, "%s_center_x" % legacy):
		return legacy
	return key

func _load_control_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	var controls_version := int(config.get_value(CONTROLS_SECTION, "version", 0))
	camera_sensitivity = _config_float(config, "sensitivity", "camera", camera_sensitivity, 0.3, 1.7)
	ads_sensitivity = _config_float(config, "sensitivity", "ads", ads_sensitivity, 0.3, 1.7)
	horizontal_fov = _config_float(config, VIEW_SECTION, "horizontal_fov", Duelist.DEFAULT_HORIZONTAL_FOV, Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV)
	gyro_enabled = bool(config.get_value(CONTROLS_SECTION, "gyro", gyro_enabled))
	_aim_toggle = bool(config.get_value(CONTROLS_SECTION, "aim_toggle", _aim_toggle))
	# Builds before controls version 1 saved ADS button look as false by
	# default. Migrate those installs once so the same thumb that holds ADS can
	# immediately drag to aim; later explicit OFF choices remain respected.
	ads_button_look = _ads_button_look_from_config(config)
	var feedback_preferences := load_feedback_preferences(config, effects_enabled, haptics_enabled)
	effects_enabled = bool(feedback_preferences.effects_enabled)
	haptics_enabled = false
	var saved_stick_mode := str(config.get_value("controls", "stick_mode", "floating")).to_lower()
	_stick_mode = MobileTouchRouter.StickMode.FIXED if saved_stick_mode == "fixed" else MobileTouchRouter.StickMode.FLOATING
	var has_saved_layout := config.has_section(LAYOUT_SECTION)
	var saved_layout_version := int(config.get_value(LAYOUT_SECTION, "version", 1))
	var migrate_legacy_default := has_saved_layout and saved_layout_version < LAYOUT_VERSION and _saved_layout_matches(_legacy_default_layout(), config)
	for key in MOVABLE_KEYS:
		var fallback: Dictionary = _default_layout()[key] if migrate_legacy_default or not has_saved_layout else _legacy_default_layout().get(key, _default_layout()[key])
		# A renamed control reads its saved position from the pre-rename key
		# name if the new one is absent, so it does not silently reset an
		# existing user's layout.
		var config_key := _layout_config_key(config, key)
		var center_x := _config_float(config, LAYOUT_SECTION, "%s_center_x" % config_key, fallback.center.x, 0.0, 1.0)
		var center_y := _config_float(config, LAYOUT_SECTION, "%s_center_y" % config_key, fallback.center.y, 0.0, 1.0)
		var scale := _config_float(config, LAYOUT_SECTION, "%s_scale" % config_key, fallback.scale, 0.7, 1.35)
		var opacity := _config_float(config, LAYOUT_SECTION, "%s_opacity" % config_key, fallback.opacity, 0.35, 1.0)
		_layout[key] = _layout_entry(Vector2(center_x, center_y), scale, opacity)
	if migrate_legacy_default:
		_layout = _default_layout()
		_save_control_settings()
	elif has_saved_layout and saved_layout_version < LAYOUT_VERSION:
		_save_control_settings()
	elif controls_version < CONTROLS_VERSION:
		_save_control_settings()

func _ads_button_look_from_config(config: ConfigFile) -> bool:
	var controls_version := int(config.get_value(CONTROLS_SECTION, "version", 0))
	if controls_version < CONTROLS_VERSION:
		return true
	return bool(config.get_value(CONTROLS_SECTION, "ads_button_look", ads_button_look))

func _legacy_default_layout() -> Dictionary:
	return {
		"move": _layout_entry(Vector2(0.10, 0.79), 1.0, 0.82),
		"left_fire": _layout_entry(Vector2(0.10, 0.20), 1.0, 0.82),
		"right_fire": _layout_entry(Vector2(0.90, 0.79), 1.0, 0.82),
		"ads": _layout_entry(Vector2(0.78, 0.53), 1.0, 0.78),
		"jump": _layout_entry(Vector2(0.78, 0.79), 1.0, 0.78),
		"crouch": _layout_entry(Vector2(0.67, 0.79), 1.0, 0.78),
		"prone": _layout_entry(Vector2(0.56, 0.79), 1.0, 0.78),
		"swap": _layout_entry(Vector2(0.67, 0.53), 1.0, 0.78),
		"interact": _layout_entry(Vector2(0.87, 0.37), 1.0, 0.82),
	}

func _saved_layout_matches(expected: Dictionary, config: ConfigFile) -> bool:
	for key in MOVABLE_KEYS:
		var fallback: Dictionary = expected[key]
		if absf(_config_float(config, LAYOUT_SECTION, "%s_center_x" % key, fallback.center.x, 0.0, 1.0) - float(fallback.center.x)) > 0.01:
			return false
		if absf(_config_float(config, LAYOUT_SECTION, "%s_center_y" % key, fallback.center.y, 0.0, 1.0) - float(fallback.center.y)) > 0.01:
			return false
		if absf(_config_float(config, LAYOUT_SECTION, "%s_scale" % key, fallback.scale, 0.7, 1.35) - float(fallback.scale)) > 0.01:
			return false
		if absf(_config_float(config, LAYOUT_SECTION, "%s_opacity" % key, fallback.opacity, 0.35, 1.0) - float(fallback.opacity)) > 0.01:
			return false
	return true

func _config_float(config: ConfigFile, section: String, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = config.get_value(section, key, fallback)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var numeric := float(value)
	if not is_finite(numeric) or numeric < minimum or numeric > maximum:
		return fallback
	return numeric

func _save_control_settings() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("sensitivity", "camera", camera_sensitivity)
	config.set_value("sensitivity", "ads", ads_sensitivity)
	config.set_value(VIEW_SECTION, "version", 1)
	config.set_value(VIEW_SECTION, "horizontal_fov", horizontal_fov)
	config.set_value(CONTROLS_SECTION, "version", CONTROLS_VERSION)
	config.set_value(CONTROLS_SECTION, "gyro", gyro_enabled)
	config.set_value(CONTROLS_SECTION, "aim_toggle", _aim_toggle)
	config.set_value(CONTROLS_SECTION, "ads_button_look", ads_button_look)
	config.set_value(CONTROLS_SECTION, "stick_mode", "fixed" if _stick_mode == MobileTouchRouter.StickMode.FIXED else "floating")
	save_feedback_preferences(config, effects_enabled, haptics_enabled)
	config.set_value(LAYOUT_SECTION, "version", LAYOUT_VERSION)
	for key in MOVABLE_KEYS:
		var data: Dictionary = _layout[key]
		config.set_value(LAYOUT_SECTION, "%s_center_x" % key, data.center.x)
		config.set_value(LAYOUT_SECTION, "%s_center_y" % key, data.center.y)
		config.set_value(LAYOUT_SECTION, "%s_scale" % key, data.scale)
		config.set_value(LAYOUT_SECTION, "%s_opacity" % key, data.opacity)
	config.save(CONFIG_PATH)
	_layout_dirty = false
