extends CharacterBody3D
## Player-controlled vehicle with throttle/brake/steering physics.

signal passenger_entered
signal passenger_exited
signal destination_reached

# -- Throttle --
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _current_speed: float = 0.0  # m/s, signed (negative = reverse)

const THROTTLE_RAMP := 3.3
const BRAKE_RAMP := 5.0
const MAX_FORWARD_SPEED := 25.0   # m/s (~56 mph)
const MAX_REVERSE_SPEED := 8.0    # m/s (~18 mph)
const ACCELERATION := 12.0        # m/s²
const BRAKE_DECEL := 20.0         # m/s²
const FRICTION_DECEL := 5.0       # natural slowdown m/s²
const HANDBRAKE_DECEL := 30.0     # m/s²

# -- Steering --
var _steer_input: float = 0.0    # -1 to 1, ramped
var _steer_angle: float = 0.0    # current effective angle in degrees
var drift_steer: float = 0.0     # injected by camera/attention system

const STEER_RAMP := 2.5
const STEER_RETURN := 3.0
const MAX_STEER_ANGLE := 35.0    # degrees

# -- Gear --
enum Gear { FORWARD, REVERSE }
var current_gear: Gear = Gear.FORWARD

# -- State --
var _is_handbraking: bool = false
var _has_passenger: bool = false

@onready var car_mesh: Node3D = $CarMesh
@onready var passenger_seat: Marker3D = $CarMesh/PassengerSeat
@onready var steering_wheel: MeshInstance3D = $SteeringWheel

var _steering_base_transform: Transform3D


func _ready() -> void:
	add_to_group("car_interior")
	if steering_wheel:
		_steering_base_transform = steering_wheel.transform


func _physics_process(delta: float) -> void:
	_read_input(delta)
	_update_speed(delta)
	_update_steering(delta)
	_apply_movement(delta)
	_update_visuals()


func _read_input(delta: float) -> void:
	# Throttle
	var throttle_pressed := Input.is_action_pressed("accelerate")
	_throttle_input = move_toward(_throttle_input, 1.0 if throttle_pressed else 0.0, THROTTLE_RAMP * delta)

	# Brake
	var brake_pressed := Input.is_action_pressed("brake")
	_brake_input = move_toward(_brake_input, 1.0 if brake_pressed else 0.0, BRAKE_RAMP * delta)

	# Steering
	var raw_steer := Input.get_axis("steer_left", "steer_right")
	if abs(raw_steer) > 0.01:
		_steer_input = move_toward(_steer_input, raw_steer, STEER_RAMP * delta)
	else:
		_steer_input = move_toward(_steer_input, 0.0, STEER_RETURN * delta)

	# Handbrake
	_is_handbraking = Input.is_action_pressed("handbrake")

	# Gear shifts
	if Input.is_action_just_pressed("shift_forward"):
		current_gear = Gear.FORWARD
	elif Input.is_action_just_pressed("shift_reverse"):
		current_gear = Gear.REVERSE


func _update_speed(delta: float) -> void:
	var max_speed: float
	var direction: float

	if current_gear == Gear.FORWARD:
		max_speed = MAX_FORWARD_SPEED
		direction = 1.0
	else:
		max_speed = MAX_REVERSE_SPEED
		direction = -1.0

	# Throttle acceleration
	if _throttle_input > 0.01:
		_current_speed = move_toward(_current_speed, max_speed * direction, ACCELERATION * _throttle_input * delta)

	# Brake deceleration
	if _brake_input > 0.01:
		_current_speed = move_toward(_current_speed, 0.0, BRAKE_DECEL * _brake_input * delta)

	# Handbrake
	if _is_handbraking:
		_current_speed = move_toward(_current_speed, 0.0, HANDBRAKE_DECEL * delta)

	# Friction (when no throttle and no handbrake)
	if _throttle_input < 0.01 and not _is_handbraking:
		_current_speed = move_toward(_current_speed, 0.0, FRICTION_DECEL * delta)


func _update_steering(delta: float) -> void:
	var total_steer := clampf(_steer_input + drift_steer, -1.0, 1.0)
	_steer_angle = total_steer * MAX_STEER_ANGLE

	# Only turn when moving
	if abs(_current_speed) > 0.5:
		var speed_factor := _current_speed / MAX_FORWARD_SPEED
		rotation.y -= deg_to_rad(_steer_angle * speed_factor * 2.0) * delta


func _apply_movement(delta: float) -> void:
	var forward := -transform.basis.z
	velocity = forward * _current_speed

	# Gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	move_and_slide()


func _update_visuals() -> void:
	if steering_wheel:
		var steer_rot := Basis(Vector3.UP, deg_to_rad(-_steer_angle * 3.0))
		steering_wheel.transform = _steering_base_transform * Transform3D(steer_rot, Vector3.ZERO)


# -- Public API --

func get_speed() -> float:
	return abs(_current_speed)


func get_speed_mph() -> float:
	return abs(_current_speed) * 2.237


func get_rpm() -> float:
	return remap(abs(_current_speed), 0.0, MAX_FORWARD_SPEED, 800.0, 6000.0)


func get_gear_string() -> String:
	return "D" if current_gear == Gear.FORWARD else "R"


func seat_passenger(node: Node3D) -> void:
	if passenger_seat:
		passenger_seat.add_child(node)
	_has_passenger = true
	passenger_entered.emit()


func remove_passenger() -> void:
	if passenger_seat:
		for child in passenger_seat.get_children():
			child.queue_free()
	_has_passenger = false
	passenger_exited.emit()


func has_passenger() -> bool:
	return _has_passenger
