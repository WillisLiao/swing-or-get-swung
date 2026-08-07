class_name DuelHud
extends Control

signal rift_link_requested
signal main_menu_requested
signal feedback_preferences_changed(effects_enabled: bool, haptics_enabled: bool)
signal view_fov_changed(horizontal_degrees: float)

const CONFIG_PATH := "user://riftline_controls.cfg"
const RESPONSIVE := preload("res://scripts/riftline_responsive_layout.gd")
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
# Optional drag-look: holding the ADS button and dragging that same
# finger can also steer the camera.  Off by default.
var ads_button_look := false
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
		var confirm_color := Color("fff0b0", 0.95 * hit_confirm)
		var confirm_radius := 23.0 + (1.0 - hit_confirm) * 7.0
		for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
			var direction := Vector2.RIGHT.rotated(angle)
			var inner := center + direction * (confirm_radius - 7.0)
			var outer := center + direction * confirm_radius
			draw_line(inner, outer, confirm_color, 2.5)

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
	draw_circle(stick_center, stick_radius, Color("08142a", 0.42 * stick_alpha))
	draw_arc(stick_center, stick_radius, 0.0, TAU, 32, Color(friendly, 0.38 * stick_alpha), 2.0)
	if _stick_mode == MobileTouchRouter.StickMode.FIXED or stick_is_active or _stick_visual_opacity > 0.01:
		draw_circle(knob, 24.0 * _control_scale("move"), Color(friendly, 0.34 * stick_alpha))
		draw_arc(knob, 24.0 * _control_scale("move"), 0.0, TAU, 24, Color(friendly, 0.9 * stick_alpha), 2.0)

	_draw_button("left_fire", friendly, _left_fire_touch >= 0)
	_draw_button("right_fire", friendly, _right_fire_touch >= 0)
	# Every weapon ADS's through an optic now, so the ADS button is no longer
	# weapon-gated the way it was when only the carbine could aim.
	_draw_button("ads", enemy, aim_held)
	_draw_button("jump", enemy, _jump_touch >= 0)
	_draw_button("crouch", friendly, _stance == Duelist.Stance.CROUCH)
	_draw_button("prone", friendly, _stance == Duelist.Stance.PRONE)
	_draw_button("swap", Color("c292ff"), _switch_touch >= 0)
	if _interact_available:
		_draw_button("interact", friendly, _interact_touch >= 0)
	_draw_button_fixed(_reload_center(), _reload_radius(), Color("e6a25b"), reload_remaining > 0.0, "reload")
	_draw_button_fixed(_melee_center(), _melee_radius(), Color("8fd6a8"), _melee_touch >= 0, "melee")
	_draw_weapon_indicator(friendly)
	_draw_button_fixed(_settings_center(), 24.0, enemy, _settings_open, "settings")
	if _touch_preview in ["two-thumb", "four-finger"]:
		_draw_button_preview("left_fire", friendly)
		_draw_button_preview("right_fire", friendly)
	if _touch_preview == "reloading":
		_draw_reload_sweep(_reload_center(), _reload_radius(), Color("fff0b0"), reload_progress_for(reload_remaining))
	if _touch_preview in ["floating-left", "floating-edge"]:
		_draw_preview_floating_stick(friendly)

	var safe := _safe_rect()
	_draw_vitality_strip(safe, friendly)
	_draw_objective_strip(safe, friendly, enemy)
	if _squad_readability:
		_draw_team_life_strip(safe, friendly, enemy)
	if damage_direction_intensity > 0.0:
		var damage_color := _team_color(damage_enemy_team)
		var direction := damage_direction if damage_direction.length_squared() > 0.01 else Vector2.DOWN
		var edge_radius := minf(size.x, size.y) * 0.44
		var edge_angle := atan2(direction.y, direction.x)
		draw_arc(center, edge_radius, edge_angle - 0.18, edge_angle + 0.18, 14, Color(damage_color, damage_direction_intensity * 0.9), 7.0)
	if _match_result_visible:
		_draw_match_result()
	elif _match_phase == RiftlineMatch.Phase.OPENING:
		_draw_round_beat("ROUND START", "FIGHT", friendly)
	if not _connection_message.is_empty():
		var message_rect := Rect2(Vector2(size.x * 0.5 - 170.0, _safe_rect().position.y + 52.0), Vector2(340.0, 46.0))
		draw_rect(message_rect, Color("0b1730", 0.94))
		draw_line(message_rect.position, message_rect.position + Vector2(message_rect.size.x, 0), enemy, 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, message_rect.get_center() + Vector2(-font.get_string_size(_connection_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5, 5), _connection_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f1f6ff"))

func _friendly_color() -> Color:
	return _team_color(_roster_local_team)

func _enemy_color() -> Color:
	return _team_color(Duelist.Team.BLUE if _roster_local_team == int(Duelist.Team.RED) else Duelist.Team.RED)

func _draw_vitality_strip(safe: Rect2, friendly: Color) -> void:
	# A continuous 0-100 bar. Every point of damage moves the fill; this is
	# not a chunked "hits remaining" meter, since damage varies per weapon
	# (SMG/pistol chip damage vs. sniper one-shots) and a fixed hit count
	# would lie about how much health is actually left.
	var bar_size := Vector2(132.0, 14.0)
	var origin := Vector2(safe.get_center().x - bar_size.x * 0.5, safe.end.y - 46.0)
	var track := Rect2(origin, bar_size)
	var fraction := clampf(health / Duelist.HEALTH, 0.0, 1.0)
	var low_pulse := 0.7 + sin(Time.get_ticks_msec() * 0.012) * 0.3 if health <= 30.0 else 1.0
	var fill_color := Color("ef8b78", low_pulse) if health <= 30.0 else Color("f5e6bd") if health <= 60.0 else friendly
	draw_rect(track, Color("0b1730", 0.72))
	if fraction > 0.0:
		draw_rect(Rect2(track.position, Vector2(track.size.x * fraction, track.size.y)), Color(fill_color, 0.92))
	var ticks: Array[float] = [0.25, 0.5, 0.75]
	for tick in ticks:
		var tick_x: float = track.position.x + track.size.x * tick
		draw_line(Vector2(tick_x, track.position.y), Vector2(tick_x, track.end.y), Color("0b1730", 0.55), 1.0)
	draw_rect(track, Color("f1f6ff", 0.7), false, 1.2)
	var label := str(ceili(health))
	var font := ThemeDB.fallback_font
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(track.get_center().x - label_width * 0.5, track.position.y - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f1f6ff", 0.9))


func _team_color(team: int) -> Color:
	return Color("ff6a57") if team == int(Duelist.Team.RED) else Color("71cfff")

func _draw_objective_strip(safe: Rect2, friendly: Color, enemy: Color) -> void:
	var center := Vector2(size.x * 0.5, safe.position.y + 18.0)
	var font := get_theme_font("font", "Label")
	var small_font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-96.0, 6.0), "%d/%d" % [_red_score, RiftlineMatch.POINTS_TO_WIN], HORIZONTAL_ALIGNMENT_CENTER, -1, 20, friendly)
	draw_string(font, center + Vector2(96.0, 6.0), "%d/%d" % [_blue_score, RiftlineMatch.POINTS_TO_WIN], HORIZONTAL_ALIGNMENT_CENTER, -1, 20, enemy)
	var sudden_death := bool(_objective_state.get("sudden_death", false))
	if sudden_death:
		var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
		var label := "SUDDEN DEATH"
		var label_width := small_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(small_font, center + Vector2(-label_width * 0.5, 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ff6b57", pulse))
	else:
		var match_remaining := float(_objective_state.get("match_remaining", RiftlineMatch.MATCH_SECONDS))
		var clock := _format_clock(match_remaining)
		var clock_width := small_font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(small_font, center + Vector2(-clock_width * 0.5, 6.0), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("fff4c7", 0.92))
	_draw_core_status(Vector2(center.x, center.y + 20.0), friendly, enemy)
	if _score_pulse > 0.0:
		draw_arc(center, 10.0 + (1.0 - _score_pulse) * 14.0, 0.0, TAU, 24, Color("fff4c7", _score_pulse * 0.85), 2.0)
	if objective_feedback_pulse > 0.0:
		var feedback_color := _team_color(objective_feedback_team) if objective_feedback_team >= 0 else Color("fff0b0")
		draw_arc(center, 10.0 + (1.0 - objective_feedback_pulse) * 18.0, 0.0, TAU, 24, Color(feedback_color, objective_feedback_pulse * 0.9), 2.5)

func _draw_core_status(point: Vector2, friendly: Color, enemy: Color) -> void:
	var font := ThemeDB.fallback_font
	var core_state := int(_objective_state.get("core_state", int(RiftlineMatch.CoreState.AT_CENTER)))
	var text := "CORE AT CENTER"
	var accent := Color("fff4c7")
	match core_state:
		int(RiftlineMatch.CoreState.CARRIED):
			var carrier_team := int(_objective_state.get("core_carrier_team", int(Duelist.Team.RED)))
			accent = _team_color(carrier_team)
			text = "CORE CARRIED - %s" % ("RED" if carrier_team == int(Duelist.Team.RED) else "BLUE")
		int(RiftlineMatch.CoreState.DROPPED):
			text = "CORE DROPPED"
			accent = Color("ff9b57")
		int(RiftlineMatch.CoreState.INSTALLED):
			var installed_team := int(_objective_state.get("installed_team", int(Duelist.Team.RED)))
			accent = _team_color(installed_team)
			text = "LAUNCHING - %s" % ("RED" if installed_team == int(Duelist.Team.RED) else "BLUE")
		int(RiftlineMatch.CoreState.RESPAWNING):
			text = "CORE RETURNING"
			accent = Color("9bb2d1")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, point + Vector2(-text_width * 0.5, 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent)

	var install_progress := float(_objective_state.get("install_progress", 0.0))
	var cancel_progress := float(_objective_state.get("cancel_progress", 0.0))
	if install_progress > 0.0:
		_draw_hold_arc(point + Vector2(0.0, 30.0), install_progress, friendly)
	if cancel_progress > 0.0:
		_draw_hold_arc(point + Vector2(0.0, 30.0), cancel_progress, enemy)

	if core_state == int(RiftlineMatch.CoreState.INSTALLED):
		var launch_remaining := float(_objective_state.get("launch_remaining", 0.0))
		var installed_team := int(_objective_state.get("installed_team", int(Duelist.Team.RED)))
		var launch_color := _team_color(installed_team)
		var launch_text := _format_clock(launch_remaining)
		var launch_width := font.get_string_size(launch_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, point + Vector2(-launch_width * 0.5, 58.0), launch_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, launch_color)

func _draw_hold_arc(center: Vector2, progress: float, color: Color) -> void:
	var radius := 13.0
	draw_arc(center, radius, 0.0, TAU, 24, Color(color, 0.22), 1.4)
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 20, color, 3.0)

static func _format_clock(seconds: float) -> String:
	var total := maxi(0, int(floor(maxf(seconds, 0.0))))
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]

func _draw_team_life_strip(safe: Rect2, friendly: Color, enemy: Color) -> void:
	var center := Vector2(size.x * 0.5, safe.position.y + 45.0)
	var red_index := 0
	var blue_index := 0
	for record in _roster_state:
		var team := int(record.get("team", -1))
		var eliminated := bool(record.get("eliminated", false))
		var is_local_team := team == _roster_local_team
		var color := friendly if team == int(Duelist.Team.RED) else enemy
		var slot := red_index if team == int(Duelist.Team.RED) else blue_index
		var direction := -1.0 if team == int(Duelist.Team.RED) else 1.0
		var point := center + Vector2(direction * (34.0 + slot * 15.0), 0.0)
		_draw_team_marker(point, color, not eliminated, is_local_team)
		if team == int(Duelist.Team.RED):
			red_index += 1
		else:
			blue_index += 1

func _draw_team_marker(center: Vector2, color: Color, living: bool, friendly_marker: bool) -> void:
	var half_width := 5.0 if friendly_marker else 4.0
	var height := 5.0 if living else 4.0
	var chevron := PackedVector2Array([
		center + Vector2(-half_width, -height),
		center + Vector2(half_width, 0.0),
		center + Vector2(-half_width, height),
	])
	if living:
		draw_colored_polygon(chevron, Color(color, 0.72))
	else:
		draw_polyline(chevron, Color(color, 0.72), 1.4)
		draw_line(center + Vector2(-half_width * 0.5, 0.0), center + Vector2(half_width * 0.5, 0.0), Color("f1f6ff", 0.76), 1.0)

func _draw_button(key: String, color: Color, active: bool) -> void:
	var spec: Dictionary = _control_specs()[key]
	_draw_button_fixed(_control_center(key), _control_radius(key), color, active, key, _control_opacity(key))

func _draw_button_fixed(center: Vector2, radius: float, color: Color, active: bool, label: String, opacity: float = 1.0) -> void:
	var fill_alpha := 0.56 if active else 0.20
	var outline_alpha := 0.95 if active else 0.34
	draw_circle(center, radius, Color("071126", fill_alpha * opacity))
	draw_arc(center, radius, 0.0, TAU, 32, Color(color, outline_alpha * opacity), 2.5 if active else 1.35)
	if _control_specs().has(label) or label == "reload" or label == "settings" or label == "melee":
		_draw_control_glyph(center, radius, color, label, active, opacity)
		return
	var font := ThemeDB.fallback_font
	var font_size := 13 if label.length() > 1 else 20
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-text_width * 0.5, font_size * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color, 0.98 * opacity))

func _draw_control_glyph(center: Vector2, radius: float, color: Color, key: String, active: bool, opacity: float) -> void:
	var glyph_color := Color(color, (0.98 if active else 0.58) * opacity)
	var weight := 3.0 if active else 1.8
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
			draw_circle(center, radius * 0.10, Color("071126", 0.72 * opacity))

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

func _draw_weapon_indicator(color: Color) -> void:
	var safe := _safe_rect()
	var center := Vector2(safe.end.x - 170.0, safe.end.y - 74.0)
	if _loadout_slots.size() == 1:
		_draw_loadout_plate(center, RiftWeapons.clamp_weapon(int(_loadout_slots[0])) as Duelist.Weapon, color)
		_draw_magazine_read(center + Vector2(0.0, 30.0), color)
		if reload_remaining > 0.0:
			_draw_reload_sweep(center, 24.0, Color("fff0b0"), reload_progress_for(reload_remaining, float(RiftWeapons.row(int(_weapon)).reload_seconds)))
		return
	_draw_loadout_plate(center - Vector2(48.0, 0.0), RiftWeapons.clamp_weapon(int(_loadout_slots[0])) as Duelist.Weapon, color)
	_draw_loadout_plate(center + Vector2(48.0, 0.0), RiftWeapons.clamp_weapon(int(_loadout_slots[1])) as Duelist.Weapon, color)
	var active_offset := Vector2(-48.0, 0.0) if int(_weapon) == RiftWeapons.clamp_weapon(int(_loadout_slots[0])) else Vector2(48.0, 0.0)
	_draw_magazine_read(center + active_offset + Vector2(0.0, 30.0), color)
	if reload_remaining > 0.0:
		_draw_reload_sweep(center + active_offset, 24.0, Color("fff0b0"), reload_progress_for(reload_remaining, float(RiftWeapons.row(int(_weapon)).reload_seconds)))

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
	# One stroked annulus from the circle out past the farthest corner masks
	# the whole surround in a single call, with no overlapping alpha to seam.
	var reach := center.length() + 8.0
	if reach > radius:
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
	var plate_color := color if held else Color("9bb2d1")
	draw_rect(Rect2(center - Vector2(32.0, 22.0), Vector2(64.0, 44.0)), Color("071126", 0.72), true)
	draw_rect(Rect2(center - Vector2(32.0, 22.0), Vector2(64.0, 44.0)), Color(plate_color, 0.95 if held else 0.34), false, 2.0 if held else 1.0)
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

func _draw_magazine_read(center: Vector2, color: Color) -> void:
	var capacity := int(RiftWeapons.row(int(_weapon)).magazine_size)
	var reserve_capacity := int(RiftWeapons.row(int(_weapon)).reserve_ammo)
	var magazine_ratio := clampf(float(magazine_rounds) / float(maxi(1, capacity)), 0.0, 1.0)
	var filled_segments := ceili(magazine_ratio * 5.0) if magazine_rounds > 0 else 0
	for index in 5:
		var segment := Rect2(center + Vector2(-28.0 + index * 12.0, -4.0), Vector2(9.0, 8.0))
		draw_rect(segment, Color(color, 0.88 if index < filled_segments else 0.14), index < filled_segments)
		draw_rect(segment, Color(color, 0.56), false, 1.0)
	var reserve_ratio := clampf(float(reserve_ammo) / float(maxi(1, reserve_capacity)), 0.0, 1.0)
	var reserve_blocks := ceili(reserve_ratio * 3.0) if reserve_ammo > 0 else 0
	for index in 3:
		var block := Rect2(center + Vector2(-17.0 + index * 12.0, 10.0), Vector2(8.0, 4.0))
		draw_rect(block, Color("fff0b0", 0.7 if index < reserve_blocks else 0.12), index < reserve_blocks)
		draw_rect(block, Color("fff0b0", 0.42), false, 1.0)

static func reload_progress_for(remaining: float, reload_seconds: float = 2.0) -> float:
	return clampf(1.0 - remaining / maxf(0.05, reload_seconds), 0.0, 1.0)

func _draw_reload_sweep(center: Vector2, radius: float, color: Color, progress: float) -> void:
	var phase := clampf(progress, 0.0, 1.0)
	draw_arc(center, radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * phase, 24, Color(color, 0.92), 3.0)
	draw_line(center + Vector2(-radius * 0.42, radius * 0.42), center + Vector2(radius * 0.42, radius * 0.42), Color(color, 0.82), 2.0)

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
	var rect := Rect2(Vector2(size.x * 0.5 - 190.0, safe.position.y + 62.0), Vector2(380.0, 30.0))
	if region == "seed":
		rect = Rect2(Vector2(size.x * 0.5 - 260.0, safe.end.y - 148.0), Vector2(520.0, 30.0))
	draw_rect(rect, Color("071126", 0.72 * cue_alpha), true)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(accent, 0.75 * cue_alpha), 1.5)
	var font := ThemeDB.fallback_font
	var text := str(_coach_display_cue.get("text", ""))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, rect.get_center() + Vector2(-width * 0.5, 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f1f6ff", 0.95 * cue_alpha))

func _draw_match_result() -> void:
	var accent := _friendly_color() if _match_result_victory else _enemy_color()
	var card := _match_result_card()
	draw_rect(Rect2(Vector2.ZERO, size), Color("020612", 0.78))
	draw_rect(card, Color("0b1730", 0.99))
	draw_line(card.position, card.position + Vector2(card.size.x, 0), accent, 3.0)
	var emblem := card.position + Vector2(54, 62)
	if _match_result_victory:
		var diamond := PackedVector2Array([emblem + Vector2(0, -22), emblem + Vector2(22, 0), emblem + Vector2(0, 22), emblem + Vector2(-22, 0)])
		draw_colored_polygon(diamond, Color(accent, 0.26))
		draw_polyline(diamond, Color(accent, 0.96), 2.5)
	else:
		draw_circle(emblem, 22.0, Color(accent, 0.2))
		draw_arc(emblem, 22.0, 0.0, TAU, 24, accent, 2.5)
		draw_line(emblem + Vector2(-10, -10), emblem + Vector2(10, 10), accent, 2.5)
		draw_line(emblem + Vector2(10, -10), emblem + Vector2(-10, 10), accent, 2.5)
	var font := ThemeDB.fallback_font
	var title := "VICTORY" if _match_result_victory else "DEFEAT"
	draw_string(font, card.position + Vector2(98, 67), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("f1f6ff"))
	draw_string(font, card.position + Vector2(100, 94), "THE RIFT HOLDS" if _match_result_victory else "THE RIFT PUSHES BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(accent, 0.92))
	draw_string(font, card.position + Vector2(32, 128), "RESET THE DUEL AND TRY A NEW LINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b6c9e8"))
	draw_rect(_rematch_rect(), Color(accent, 0.16), true)
	draw_rect(_rematch_rect(), Color(accent, 0.92), false, 1.8)
	var label := "REMATCH"
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, _rematch_rect().get_center() + Vector2(-label_width * 0.5, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, accent)

func _draw_round_beat(title: String, subtitle: String, accent: Color) -> void:
	var center := size * 0.5 + Vector2(0, 72)
	var width := 290.0 if title == "READY" else 380.0
	var rect := Rect2(center - Vector2(width * 0.5, 28), Vector2(width, 56))
	draw_rect(rect, Color("071126", 0.72))
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), accent, 2.0)
	var font := ThemeDB.fallback_font
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, center + Vector2(-title_width * 0.5, 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f1f6ff"))
	var subtitle_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, center + Vector2(-subtitle_width * 0.5, 20), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(accent, 0.9))

func _match_result_card() -> Rect2:
	return Rect2(size * 0.5 - Vector2(260, 130), Vector2(520, 260))

func _rematch_rect() -> Rect2:
	var card := _match_result_card()
	return Rect2(card.position + Vector2(140, 174), Vector2(240, 54))

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
	if Rect2(panel.position + Vector2(24, 188), Vector2(142, 44)).has_point(point):
		return "aim_chip"
	if Rect2(panel.position + Vector2(184, 188), Vector2(142, 44)).has_point(point):
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
	return Rect2(panel.position + Vector2(154, 108), Vector2(panel.size.x - 190, 24))

func _ads_track_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position + Vector2(154, 154), Vector2(panel.size.x - 190, 24))

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

func _draw_settings_panel(friendly: Color, enemy: Color) -> void:
	var panel := _settings_panel()
	draw_rect(Rect2(Vector2.ZERO, size), Color("020612", 0.68))
	draw_rect(panel, Color("0b1730", 0.98))
	draw_line(panel.position, panel.position + Vector2(panel.size.x, 0), friendly, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(24, 34), "COMBAT SETTINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f1f6ff"))
	draw_string(font, panel.position + Vector2(24, 68), "VIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, enemy)
	_draw_view_slider(_view_track_rect(panel), friendly)
	draw_string(font, panel.position + Vector2(24, 111), "CAMERA", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, enemy)
	draw_string(font, panel.position + Vector2(24, 157), "ADS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, enemy)
	_draw_setting_slider(_camera_track_rect(panel).position, panel.size.x - 190, camera_sensitivity, friendly)
	_draw_setting_slider(_ads_track_rect(panel).position, panel.size.x - 190, ads_sensitivity, friendly)
	draw_string(font, panel.position + Vector2(24, SETTINGS_TOGGLES_TOP - SETTINGS_LABEL_GAP), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("92a7c7"))
	_draw_setting_chip(_aim_rect(panel), "AIM %s" % ("TAP" if _aim_toggle else "HOLD"), friendly, _aim_toggle)
	_draw_setting_chip(_gyro_rect(panel), "GYRO %s" % ("ON" if gyro_enabled else "OFF"), Color("c292ff"), gyro_enabled)
	_draw_setting_chip(_effects_rect(panel), "EFFECTS %s" % ("ON" if effects_enabled else "OFF"), friendly, effects_enabled)
	_draw_setting_chip(_stick_mode_rect(panel), "STICK %s" % ("FLOAT" if _stick_mode == MobileTouchRouter.StickMode.FLOATING else "FIXED"), friendly, _stick_mode == MobileTouchRouter.StickMode.FLOATING)
	_draw_setting_chip(_ads_look_rect(panel), "ADS LOOK %s" % ("ON" if ads_button_look else "OFF"), Color("c292ff"), ads_button_look)
	draw_string(font, panel.position + Vector2(24, _settings_actions_top() - SETTINGS_LABEL_GAP), "ACTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("92a7c7"))
	_draw_setting_chip(_hud_layout_rect(panel), "HUD LAYOUT", enemy, true)
	_draw_setting_chip(_rift_link_rect(panel), "RIFT LINK", Color("71cfff"), false)
	_draw_setting_chip(_reset_training_rect(panel), "RESET TRAINING", Color("e57c70"), false)
	_draw_setting_chip(_main_menu_rect(panel), "MAIN MENU", Color("e57c70"), false)
	draw_string(font, panel.position + Vector2(24, panel.size.y - 22), "Tap outside to return", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("92a7c7"))

func _draw_setting_slider(position: Vector2, width: float, value: float, color: Color) -> void:
	draw_line(position, position + Vector2(width, 0), Color("233b64"), 5.0)
	var normalized := (value - 0.3) / 1.4
	draw_line(position, position + Vector2(width * normalized, 0), color, 5.0)
	draw_circle(position + Vector2(width * normalized, 0), 9.0, color)

func _view_track_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position + Vector2(154, 65), Vector2(panel.size.x - 190, 24))

func _view_from_point(point_x: float, track_x: float) -> float:
	return clampf(Duelist.MIN_HORIZONTAL_FOV + ((point_x - track_x) / maxf(1.0, _view_track_rect(_settings_panel()).size.x)) * (Duelist.MAX_HORIZONTAL_FOV - Duelist.MIN_HORIZONTAL_FOV), Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV)

func _draw_view_slider(rect: Rect2, color: Color) -> void:
	var normalized := inverse_lerp(Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV, horizontal_fov)
	draw_line(rect.position + Vector2(0, rect.size.y * 0.5), rect.end - Vector2(0, rect.size.y * 0.5), Color("233b64"), 5.0)
	draw_line(rect.position + Vector2(0, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * normalized, rect.size.y * 0.5), color, 5.0)
	draw_circle(rect.position + Vector2(rect.size.x * normalized, rect.size.y * 0.5), 9.0, color)
	var font := ThemeDB.fallback_font
	for mark in [{"x": 0.0, "label": "TIGHT"}, {"x": 0.5, "label": "STANDARD"}, {"x": 1.0, "label": "WIDE"}]:
		var x := rect.position.x + rect.size.x * float(mark.x)
		var label := str(mark.label)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(x - width * 0.5, rect.position.y + 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("92a7c7"))

func _draw_setting_chip(rect: Rect2, text: String, color: Color, active: bool) -> void:
	draw_rect(rect, Color(color, 0.18 if active else 0.07), true)
	draw_rect(rect, Color(color, 0.86), false, 1.4)
	var font := ThemeDB.fallback_font
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, rect.get_center() + Vector2(-text_width * 0.5, 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

func _draw_layout_editor() -> void:
	var friendly := _friendly_color()
	var enemy := _enemy_color()
	draw_rect(Rect2(Vector2.ZERO, size), Color("020612", 0.62))
	var safe := _safe_rect()
	for x in range(int(safe.position.x), int(safe.end.x) + 1, 32):
		draw_line(Vector2(x, safe.position.y), Vector2(x, safe.end.y), Color("8ea8cf", 0.11), 1.0)
	for y in range(int(safe.position.y), int(safe.end.y) + 1, 32):
		draw_line(Vector2(safe.position.x, y), Vector2(safe.end.x, y), Color("8ea8cf", 0.11), 1.0)
	draw_rect(safe, Color(enemy, 0.44), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, safe.position + Vector2(12, 26), "HUD LAYOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f1f6ff"))
	draw_string(font, safe.position + Vector2(12, 48), "Select a control, then drag to place", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b6c9e8"))
	for key in MOVABLE_KEYS:
		_draw_editor_control(key, friendly if key in ["move", "left_fire", "right_fire", "crouch", "prone"] else enemy)
	var panel := _editor_panel()
	draw_rect(panel, Color("0b1730", 0.98))
	draw_line(panel.position, panel.position + Vector2(panel.size.x, 0), friendly, 2.0)
	var selected_label := "SELECT A CONTROL" if _selected_layout_key.is_empty() else str(_control_specs()[_selected_layout_key].label)
	draw_string(font, panel.position + Vector2(20, 25), selected_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, enemy)
	draw_string(font, panel.position + Vector2(170, 25), "GRID LOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("92a7c7"))
	_draw_setting_chip(_editor_button_rect("size_down"), "SIZE -", friendly, false)
	_draw_setting_chip(_editor_button_rect("size_up"), "SIZE +", friendly, false)
	_draw_setting_chip(_editor_button_rect("opacity_down"), "FADE -", Color("c292ff"), false)
	_draw_setting_chip(_editor_button_rect("opacity_up"), "FADE +", Color("c292ff"), false)
	_draw_setting_chip(_editor_button_rect("two_thumb"), "TWO THUMB", enemy, false)
	_draw_setting_chip(_editor_button_rect("four_finger"), "FOUR FINGER", enemy, false)
	_draw_setting_chip(_editor_button_rect("reset"), "RESET", Color("e57c70"), false)
	_draw_setting_chip(_editor_button_rect("done"), "DONE", friendly, true)

func _draw_editor_control(key: String, color: Color) -> void:
	var center := _control_center(key)
	var radius := _control_radius(key)
	var opacity := _control_opacity(key)
	var spec: Dictionary = _control_specs()[key]
	if key == "move":
		draw_circle(center, radius, Color("08142a", 0.5 * opacity))
		draw_arc(center, radius, 0.0, TAU, 32, Color(color, 0.82 * opacity), 2.0)
	else:
		draw_circle(center, radius, Color("071126", 0.62 * opacity))
		draw_arc(center, radius, 0.0, TAU, 32, Color(color, 0.9 * opacity), 2.2)
	var font := ThemeDB.fallback_font
	var label := "MOVE" if key == "move" else str(spec.label)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, center + Vector2(-width * 0.5, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(color, opacity))
	if key == _selected_layout_key:
		draw_arc(center, radius + 8.0, 0.0, TAU, 40, Color("f1f6ff", 0.95), 3.0)
		draw_circle(center, 4.0, Color("f1f6ff"))

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
	var height := clampf(safe.size.y * 0.82, 540.0, 620.0)
	return Rect2(safe.get_center() - Vector2(width, height) * 0.5, Vector2(width, height))

## A consistent 2-column grid shared by every toggle and action chip, so
## nothing in the panel is hand-placed pixel-by-pixel: every row lines up
## under the same margins and every chip in a column shares the same width.
const SETTINGS_GRID_MARGIN := 24.0
const SETTINGS_GRID_GAP := 10.0
const SETTINGS_CHIP_HEIGHT := 42.0
const SETTINGS_ROW_PITCH := 50.0
const SETTINGS_TOGGLES_TOP := 212.0
const SETTINGS_SECTION_GAP := 20.0
const SETTINGS_LABEL_GAP := 18.0

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
	camera_sensitivity = _config_float(config, "sensitivity", "camera", camera_sensitivity, 0.3, 1.7)
	ads_sensitivity = _config_float(config, "sensitivity", "ads", ads_sensitivity, 0.3, 1.7)
	horizontal_fov = _config_float(config, VIEW_SECTION, "horizontal_fov", Duelist.DEFAULT_HORIZONTAL_FOV, Duelist.MIN_HORIZONTAL_FOV, Duelist.MAX_HORIZONTAL_FOV)
	gyro_enabled = bool(config.get_value("controls", "gyro", gyro_enabled))
	_aim_toggle = bool(config.get_value("controls", "aim_toggle", _aim_toggle))
	ads_button_look = bool(config.get_value("controls", "ads_button_look", ads_button_look))
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
	config.set_value("controls", "gyro", gyro_enabled)
	config.set_value("controls", "aim_toggle", _aim_toggle)
	config.set_value("controls", "ads_button_look", ads_button_look)
	config.set_value("controls", "stick_mode", "fixed" if _stick_mode == MobileTouchRouter.StickMode.FIXED else "floating")
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
