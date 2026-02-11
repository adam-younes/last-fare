class_name CameraController
extends Node3D
## Hybrid zone-based camera with mouse fine-adjust and lane drift injection.
## Hotkeys snap to predefined zones; mouse provides fine adjustment within each zone.
## When not looking forward, injects drift_steer into the car.

enum Zone { FORWARD, REARVIEW, PHONE, LEFT_MIRROR, RIGHT_MIRROR }

signal zone_changed(new_zone: Zone)

var current_zone: Zone = Zone.FORWARD
var _mouse_offset: Vector2 = Vector2.ZERO  # (yaw, pitch) offset in radians

# Zone target rotations as Vector2(pitch, yaw) in radians
var _zone_targets: Dictionary = {
	Zone.FORWARD:      Vector2(0.0, 0.0),
	Zone.REARVIEW:     Vector2(deg_to_rad(-12.0), deg_to_rad(25.0)),
	Zone.PHONE:        Vector2(deg_to_rad(-10.0), deg_to_rad(-20.0)),
	Zone.LEFT_MIRROR:  Vector2(0.0, deg_to_rad(-55.0)),
	Zone.RIGHT_MIRROR: Vector2(0.0, deg_to_rad(65.0)),
}

const MOUSE_SENSITIVITY := 0.002
const MOUSE_CLAMP := deg_to_rad(12.0)  # max mouse offset from zone center
const SNAP_SPEED := 8.0                # lerp speed for zone transitions

# -- Lane Drift --
var _drift_direction: float = 0.0
var _drift_timer: float = 0.0
const DRIFT_CHANGE_INTERVAL := 3.0
const DRIFT_RAMP_SPEED := 0.3
const DRIFT_MAX := 0.15

var _car: CharacterBody3D = null


func _ready() -> void:
	_car = get_parent().get_parent() as CharacterBody3D


func _process(delta: float) -> void:
	var prev_zone: Zone = current_zone
	_determine_zone()

	if current_zone != prev_zone:
		_mouse_offset = Vector2.ZERO
		zone_changed.emit(current_zone)

	# Lerp camera rotation toward target + mouse offset
	var target: Vector2 = _zone_targets[current_zone]
	var goal_pitch: float = target.x + _mouse_offset.y
	var goal_yaw: float = target.y + _mouse_offset.x

	rotation.x = lerp_angle(rotation.x, goal_pitch, SNAP_SPEED * delta)
	rotation.y = lerp_angle(rotation.y, goal_yaw, SNAP_SPEED * delta)

	# Update drift
	if _car:
		_update_drift(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_mouse_offset.x -= motion.relative.x * MOUSE_SENSITIVITY
		_mouse_offset.y -= motion.relative.y * MOUSE_SENSITIVITY

		# Clamp magnitude
		if _mouse_offset.length() > MOUSE_CLAMP:
			_mouse_offset = _mouse_offset.normalized() * MOUSE_CLAMP


func _determine_zone() -> void:
	if Input.is_action_pressed("look_mirror"):
		current_zone = Zone.REARVIEW
	elif Input.is_action_pressed("look_phone"):
		current_zone = Zone.PHONE
	else:
		current_zone = Zone.FORWARD


func _update_drift(delta: float) -> void:
	if current_zone == Zone.FORWARD:
		# Gradually remove drift when looking forward
		_drift_direction = move_toward(_drift_direction, 0.0, DRIFT_RAMP_SPEED * 2.0 * delta)
	else:
		# Build drift when not looking forward
		_drift_timer += delta
		if _drift_timer >= DRIFT_CHANGE_INTERVAL:
			_drift_timer = 0.0
			_drift_direction = randf_range(-DRIFT_MAX, DRIFT_MAX)
			if absf(_drift_direction) < 0.03:
				_drift_direction = 0.05 * signf(randf() - 0.5)

	_car.drift_steer = _drift_direction
