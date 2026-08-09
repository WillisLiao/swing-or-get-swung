extends Node3D

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var orbit_enabled := true

func _ready() -> void:
	camera.look_at(Vector3.ZERO, Vector3.UP)

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_SPACE):
		return
	if orbit_enabled:
		camera_rig.rotation.y += delta * 0.09
