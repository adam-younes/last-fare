extends CharacterBody3D
## Player-controlled vehicle with automatic transmission physics.

signal passenger_entered
signal passenger_exited
signal destination_reached

# -- Input State --
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _steer_input: float = 0.0
var _steer_angle: float = 0.0
var _effective_steer_angle: float = 0.0  # smoothed, grip-limited front wheel angle
var drift_steer: float = 0.0
var _is_handbraking: bool = false

# -- Input Ramp Rates --
const THROTTLE_RAMP := 3.3
const BRAKE_RAMP := 3.5
const STEER_RAMP := 2.5
const STEER_RETURN := 3.0

# -- Steering --
const MAX_STEER_ANGLE := 17.5    # degrees (max front wheel deflection at full lock)
const WHEELBASE := 2.7           # meters (front axle to rear axle, typical sedan)
const MAX_LATERAL_G := 0.8       # tire grip limit (street tires, dry road)
const STEER_RESPONSE := 5.0     # how quickly effective wheel angle catches up (exp smoothing)

# -- Speed Limits --
const MAX_FORWARD_SPEED := 31.3   # m/s (~70 mph)
const MAX_REVERSE_SPEED := 8.0    # m/s (~18 mph)

# -- Braking & Friction --
const BRAKE_DECEL := 9.0          # m/s² (~0.9g, realistic hard braking)
const FRICTION_DECEL := 3.0       # natural slowdown m/s²
const HANDBRAKE_DECEL := 14.0     # m/s² (rear wheels only)
const ENGINE_BRAKE_FACTOR := 0.8  # multiplied by gear ratio for engine braking

# -- Engine --
const IDLE_RPM := 800.0
const REDLINE_RPM := 6500.0
const RPM_LIMITER := 6800.0
const ENGINE_FORCE := 2.2         # base force multiplier (torque * ratio * this = m/s²)

# -- Transmission (6-speed automatic) --
const GEAR_RATIOS: Array[float] = [3.8, 2.5, 1.8, 1.3, 1.0, 0.8]
const REVERSE_RATIO := 3.5
const SPEED_TO_RPM := 200.0       # RPM = speed_m_s * gear_ratio * this
const UPSHIFT_RPM := 3000.0
const DOWNSHIFT_RPM := 1200.0
const KICKDOWN_RPM := 4000.0
const SHIFT_DURATION := 0.25      # seconds of torque cut during gear change
const RPM_SMOOTH_UP := 12.0       # exponential smoothing rate (RPM rising)
const RPM_SMOOTH_DOWN := 8.0      # exponential smoothing rate (RPM falling)

# -- Drive Mode --
enum DriveMode { DRIVE, REVERSE }
var drive_mode: DriveMode = DriveMode.DRIVE

# -- State --
var _current_speed: float = 0.0    # m/s, signed (negative = reverse)
var _engine_rpm: float = IDLE_RPM
var _current_gear: int = 0         # 0-indexed into GEAR_RATIOS
var _shift_timer: float = 0.0
var _vertical_velocity: float = 0.0
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
	_update_transmission(delta)
	_update_speed(delta)
	_update_rpm(delta)
	_update_steering(delta)
	_apply_movement(delta)
	_update_visuals()


func _read_input(delta: float) -> void:
	# Throttle
	var throttle_pressed: bool = Input.is_action_pressed("accelerate")
	_throttle_input = move_toward(_throttle_input, 1.0 if throttle_pressed else 0.0, THROTTLE_RAMP * delta)

	# Brake
	var brake_pressed: bool = Input.is_action_pressed("brake")
	_brake_input = move_toward(_brake_input, 1.0 if brake_pressed else 0.0, BRAKE_RAMP * delta)

	# Steering
	var raw_steer: float = Input.get_axis("steer_left", "steer_right")
	if abs(raw_steer) > 0.01:
		_steer_input = move_toward(_steer_input, raw_steer, STEER_RAMP * delta)
	else:
		_steer_input = move_toward(_steer_input, 0.0, STEER_RETURN * delta)

	# Handbrake
	_is_handbraking = Input.is_action_pressed("handbrake")

	# Drive mode
	if Input.is_action_just_pressed("shift_forward"):
		drive_mode = DriveMode.DRIVE
	elif Input.is_action_just_pressed("shift_reverse"):
		drive_mode = DriveMode.REVERSE


func _get_current_ratio() -> float:
	if drive_mode == DriveMode.REVERSE:
		return REVERSE_RATIO
	return float(GEAR_RATIOS[_current_gear])


func _torque_at_rpm(rpm: float) -> float:
	## Normalized engine torque curve (0.0 to 1.0).
	## Models a typical 4-cylinder sedan: builds torque from idle, peaks at
	## 2800-4200 RPM, then tapers off toward redline with a power plateau.
	if rpm < 1200.0:
		return remap(rpm, IDLE_RPM, 1200.0, 0.25, 0.55)
	elif rpm < 2800.0:
		return remap(rpm, 1200.0, 2800.0, 0.55, 1.0)
	elif rpm < 4200.0:
		return 1.0  # Peak torque plateau
	elif rpm < 5200.0:
		return remap(rpm, 4200.0, 5200.0, 1.0, 0.88)
	elif rpm < 6000.0:
		return remap(rpm, 5200.0, 6000.0, 0.88, 0.65)
	elif rpm < REDLINE_RPM:
		return remap(rpm, 6000.0, REDLINE_RPM, 0.65, 0.35)
	else:
		return 0.05  # Rev limiter fuel cut


func _update_transmission(delta: float) -> void:
	if _shift_timer > 0.0:
		_shift_timer -= delta

	# Only auto-shift in DRIVE
	if drive_mode != DriveMode.DRIVE:
		return

	var speed: float = absf(_current_speed)

	# Reset to first gear when nearly stopped
	if speed < 0.5:
		_current_gear = 0
		return

	# Don't shift during cooldown
	if _shift_timer > 0.0:
		return

	var rpm: float = speed * float(GEAR_RATIOS[_current_gear]) * SPEED_TO_RPM

	# Upshift
	if rpm >= UPSHIFT_RPM and _current_gear < GEAR_RATIOS.size() - 1:
		_current_gear += 1
		_shift_timer = SHIFT_DURATION
	# Downshift
	elif rpm <= DOWNSHIFT_RPM and _current_gear > 0:
		_current_gear -= 1
		_shift_timer = SHIFT_DURATION
	# Kick-down: hard throttle at low RPM triggers downshift for more power
	elif _throttle_input > 0.9 and _current_gear > 0 and rpm < KICKDOWN_RPM:
		var lower_rpm: float = speed * float(GEAR_RATIOS[_current_gear - 1]) * SPEED_TO_RPM
		if lower_rpm < UPSHIFT_RPM:
			_current_gear -= 1
			_shift_timer = SHIFT_DURATION


func _update_speed(delta: float) -> void:
	var direction: float = 1.0 if drive_mode == DriveMode.DRIVE else -1.0
	var max_speed: float = MAX_FORWARD_SPEED if drive_mode == DriveMode.DRIVE else MAX_REVERSE_SPEED
	var ratio: float = _get_current_ratio()
	var shifting: bool = _shift_timer > 0.0

	# Throttle: engine force from torque curve * gear ratio
	if _throttle_input > 0.01 and not shifting:
		var torque: float = _torque_at_rpm(_engine_rpm)
		var drive_force: float = torque * ratio * ENGINE_FORCE * _throttle_input
		_current_speed = move_toward(_current_speed, max_speed * direction, drive_force * delta)

	# Brake (quadratic curve: light tap = gentle, full press = hard stop)
	if _brake_input > 0.01:
		var brake_force: float = _brake_input * _brake_input * BRAKE_DECEL
		_current_speed = move_toward(_current_speed, 0.0, brake_force * delta)

	# Handbrake
	if _is_handbraking:
		_current_speed = move_toward(_current_speed, 0.0, HANDBRAKE_DECEL * delta)

	# Friction + engine braking (when coasting)
	if _throttle_input < 0.01 and not _is_handbraking:
		var engine_brake: float = ratio * ENGINE_BRAKE_FACTOR
		_current_speed = move_toward(_current_speed, 0.0, (FRICTION_DECEL + engine_brake) * delta)


func _update_rpm(delta: float) -> void:
	var speed: float = absf(_current_speed)
	var ratio: float = _get_current_ratio()

	# Target RPM from wheel speed through transmission
	var wheel_rpm: float = speed * ratio * SPEED_TO_RPM
	var target_rpm: float = maxf(wheel_rpm, IDLE_RPM)

	# Torque converter slip: throttle raises RPM freely at low speed
	var slip: float = clampf(1.0 - speed / 3.0, 0.0, 1.0)
	target_rpm = maxf(target_rpm, IDLE_RPM + _throttle_input * 2500.0 * slip)

	target_rpm = minf(target_rpm, RPM_LIMITER)

	# Exponential smoothing (faster rising, slower falling for shift feel)
	var smooth: float = RPM_SMOOTH_UP if target_rpm > _engine_rpm else RPM_SMOOTH_DOWN
	_engine_rpm = lerpf(_engine_rpm, target_rpm, 1.0 - exp(-smooth * delta))


func _update_steering(delta: float) -> void:
	var total_steer: float = clampf(_steer_input + drift_steer, -1.0, 1.0)
	_steer_angle = total_steer * MAX_STEER_ANGLE  # visual steering wheel angle

	var speed: float = absf(_current_speed)

	# Target effective angle: grip-limited by lateral g at current speed
	var target_angle: float = _steer_angle
	if speed > 1.0:
		var max_angle_rad: float = atan(MAX_LATERAL_G * 9.81 * WHEELBASE / (speed * speed))
		var max_angle_deg: float = minf(rad_to_deg(max_angle_rad), MAX_STEER_ANGLE)
		target_angle = clampf(_steer_angle, -max_angle_deg, max_angle_deg)

	# Smoothly ramp effective front wheel angle toward target
	_effective_steer_angle = lerpf(_effective_steer_angle, target_angle, 1.0 - exp(-STEER_RESPONSE * delta))

	if speed > 0.5:
		# Bicycle model: yaw_rate = v * tan(front_wheel_angle) / wheelbase
		var yaw_rate: float = speed * tan(deg_to_rad(_effective_steer_angle)) / WHEELBASE
		rotation.y -= yaw_rate * signf(_current_speed) * delta


func _apply_movement(delta: float) -> void:
	var forward: Vector3 = -transform.basis.z
	velocity = forward * _current_speed

	# Gravity (accumulated so the car falls properly)
	if is_on_floor():
		_vertical_velocity = 0.0
	else:
		_vertical_velocity -= 9.8 * delta

	velocity.y = _vertical_velocity
	move_and_slide()


func _update_visuals() -> void:
	if steering_wheel:
		var steer_rot: Basis = Basis(Vector3.UP, deg_to_rad(-_steer_angle * 3.0))
		steering_wheel.transform = _steering_base_transform * Transform3D(steer_rot, Vector3.ZERO)


# -- Public API --

func get_speed() -> float:
	return absf(_current_speed)


func get_speed_mph() -> float:
	return absf(_current_speed) * 2.237


func get_rpm() -> float:
	return _engine_rpm


func get_gear_string() -> String:
	if drive_mode == DriveMode.REVERSE:
		return "R"
	return str(_current_gear + 1)


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
