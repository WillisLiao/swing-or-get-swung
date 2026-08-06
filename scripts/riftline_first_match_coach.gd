class_name RiftlineFirstMatchCoach
extends RefCounted

signal cue_changed(cue: Dictionary)

const CONFIG_PATH := "user://riftline_controls.cfg"
const SECTION := "first_match_coach_v1"
const VERSION := 1
const MOVE_THRESHOLD := 0.35
const LOOK_THRESHOLD := 1.5

enum Step { MOVE, LOOK, FIRE, COMPLETE }

var _step := Step.MOVE
var _visible := false

func begin_offline_match() -> void:
	if _is_complete():
		hide()
		return
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK and int(config.get_value(SECTION, "version", -1)) == VERSION:
		_step = clampi(int(config.get_value(SECTION, "step", int(Step.MOVE))), int(Step.MOVE), int(Step.COMPLETE)) as Step
	else:
		_step = Step.MOVE
	_visible = true
	_emit_cue()

func observe_movement(intent: Vector2) -> void:
	if _step == Step.MOVE and intent.length() >= MOVE_THRESHOLD:
		_advance(Step.LOOK)

func observe_look(delta: Vector2) -> void:
	if _step == Step.LOOK and delta.length() >= LOOK_THRESHOLD:
		_advance(Step.FIRE)

func observe_fire() -> void:
	if _step == Step.FIRE:
		_advance(Step.COMPLETE)

func hide() -> void:
	_visible = false
	cue_changed.emit({})

func reset_training() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	config.erase_section(SECTION)
	config.save(CONFIG_PATH)
	_step = Step.MOVE
	_visible = true
	_emit_cue()

func is_complete() -> bool:
	return _step == Step.COMPLETE

func _is_complete() -> bool:
	var config := ConfigFile.new()
	return config.load(CONFIG_PATH) == OK and int(config.get_value(SECTION, "version", -1)) == VERSION and bool(config.get_value(SECTION, "complete", false))

func _advance(next_step: Step) -> void:
	_step = next_step
	_save()
	_visible = next_step != Step.COMPLETE
	_emit_cue()

func _save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value(SECTION, "version", VERSION)
	config.set_value(SECTION, "step", int(_step))
	config.set_value(SECTION, "complete", _step == Step.COMPLETE)
	config.save(CONFIG_PATH)

func _emit_cue() -> void:
	if not _visible or _step == Step.COMPLETE:
		cue_changed.emit({})
		return
	var cue := {}
	match _step:
		Step.MOVE:
			cue = {"key": "move", "text": "DRAG LEFT SIDE TO MOVE", "region": "left"}
		Step.LOOK:
			cue = {"key": "look", "text": "DRAG RIGHT SIDE TO LOOK", "region": "right"}
		Step.FIRE:
			cue = {"key": "fire", "text": "HOLD FIRE TO ENGAGE", "region": "fire"}
	cue_changed.emit(cue)
