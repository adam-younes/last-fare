class_name TrafficVehicle
extends CharacterBody3D
## AI vehicle that follows road paths, obeys traffic lights, and reacts to obstacles.

signal vehicle_despawning

enum State { DRIVING, BRAKING, STOPPED, TURNING }

var _state: State = State.DRIVING
var _current_speed: float = 0.0
var _target_speed: float = 13.4
var _path_points: PackedVector3Array
var _path_index: int = 0
var _assigned_road: RoadSegment = null
var _assigned_direction: int = 1
var _road_network: RoadNetwork = null
var _stopped_timer: float = 0.0
var _honk_cooldown: float = 0.0
var _vertical_velocity: float = 0.0
var _cleared_intersections: Dictionary = {}  # Intersection -> true (stop signs already stopped at)

const ACCELERATION := 6.0
const BRAKE_DECEL := 12.0
const STOP_DISTANCE := 3.0
const HONK_COOLDOWN := 5.0
const TURN_SPEED := 5.0
const STEER_LERP := 4.0

@onready var front_ray: RayCast3D = $FrontRay


func initialize(road: RoadSegment, direction: int, network: RoadNetwork) -> void:
	_assigned_road = road
	_assigned_direction = direction
	_road_network = network
	_target_speed = road.speed_limit * randf_range(0.9, 1.1)
	_path_points = road.get_lane_points(0, direction, 40)
	_path_index = _find_nearest_path_index()
	_state = State.DRIVING


func _physics_process(delta: float) -> void:
	if _path_points.is_empty():
		return

	_honk_cooldown = maxf(_honk_cooldown - delta, 0.0)

	match _state:
		State.DRIVING:
			_process_driving(delta)
		State.BRAKING:
			_process_braking(delta)
		State.STOPPED:
			_process_stopped(delta)
		State.TURNING:
			_process_turning(delta)

	# Apply movement
	var forward: Vector3 = -transform.basis.z
	velocity = forward * _current_speed

	# Gravity — accumulate like car_interior.gd for realistic falling
	if is_on_floor():
		_vertical_velocity = 0.0
	else:
		_vertical_velocity -= 9.8 * delta

	velocity.y = _vertical_velocity
	move_and_slide()


func _process_driving(delta: float) -> void:
	# Accelerate toward target speed
	_current_speed = move_toward(_current_speed, _target_speed, ACCELERATION * delta)

	# Follow path
	_steer_toward_path(delta)
	_advance_path_index()

	# Check for obstacles via raycast
	if front_ray and front_ray.is_colliding():
		var dist: float = global_position.distance_to(front_ray.get_collision_point())
		if dist < STOP_DISTANCE * 2.0:
			_state = State.BRAKING
			return

	# Check for traffic lights
	if _should_stop_at_intersection():
		_state = State.BRAKING
		return

	# Check if reached end of road
	if _path_index >= _path_points.size() - 1:
		_try_next_road()


func _process_braking(delta: float) -> void:
	_current_speed = move_toward(_current_speed, 0.0, BRAKE_DECEL * delta)
	_steer_toward_path(delta)

	if _current_speed < 0.1:
		_current_speed = 0.0
		_state = State.STOPPED
		_stopped_timer = 0.0
		return

	# Check if path is clear again
	var obstacle_clear: bool = true
	if front_ray and front_ray.is_colliding():
		var dist: float = global_position.distance_to(front_ray.get_collision_point())
		if dist < STOP_DISTANCE * 2.0:
			obstacle_clear = false

	if obstacle_clear and not _should_stop_at_intersection():
		_state = State.DRIVING


func _process_stopped(delta: float) -> void:
	_stopped_timer += delta

	# Clear stop sign after waiting
	if _stopped_timer > 1.5:
		var intersection: Intersection = _road_network.get_road_end_intersection(
			_assigned_road, _assigned_direction
		)
		if intersection and intersection.is_stop_sign():
			_cleared_intersections[intersection] = true

	# Check if can resume
	var obstacle_clear: bool = true
	if front_ray and front_ray.is_colliding():
		var dist: float = global_position.distance_to(front_ray.get_collision_point())
		if dist < STOP_DISTANCE * 2.5:
			obstacle_clear = false

	if obstacle_clear and not _should_stop_at_intersection():
		_state = State.DRIVING
		_stopped_timer = 0.0
		return

	# Honk if stuck behind something for too long
	if _stopped_timer > 3.0 and _honk_cooldown <= 0.0:
		if front_ray and front_ray.is_colliding():
			var collider: Object = front_ray.get_collider()
			if collider and collider.is_in_group("car_interior"):
				_honk()


func _process_turning(delta: float) -> void:
	_current_speed = move_toward(_current_speed, TURN_SPEED, ACCELERATION * delta)
	_steer_toward_path(delta)
	_advance_path_index()

	if _path_index >= _path_points.size() - 1:
		_state = State.DRIVING


func _steer_toward_path(delta: float) -> void:
	if _path_index >= _path_points.size():
		return

	var target_point: Vector3 = _path_points[_path_index]
	target_point.y = global_position.y  # Keep on same horizontal plane
	var dir: Vector3 = (target_point - global_position)
	if dir.length() < 0.01:
		return

	var target_angle: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, STEER_LERP * delta)


func _advance_path_index() -> void:
	if _path_index >= _path_points.size():
		return

	var target: Vector3 = _path_points[_path_index]
	var flat_pos: Vector3 = Vector3(global_position.x, 0.0, global_position.z)
	var flat_target: Vector3 = Vector3(target.x, 0.0, target.z)

	if flat_pos.distance_to(flat_target) < 2.0:
		_path_index += 1


func _should_stop_at_intersection() -> bool:
	if not _road_network or not _assigned_road:
		return false

	var intersection: Intersection = _road_network.get_road_end_intersection(
		_assigned_road, _assigned_direction
	)
	if not intersection:
		return false

	var to_intersection: Vector3 = intersection.global_position - global_position
	var dist: float = to_intersection.length()

	if dist < STOP_DISTANCE or dist > 15.0:
		return false

	var forward: Vector3 = -transform.basis.z
	if forward.dot(to_intersection.normalized()) < 0.0:
		return false

	# Stop signs: check if already cleared
	if intersection.is_stop_sign():
		return not _cleared_intersections.has(intersection)

	# Traffic lights: stop if not green
	var light_state: Intersection.LightState = intersection.get_light_state(_assigned_road)
	return light_state != Intersection.LightState.GREEN


func _try_next_road() -> void:
	if not _road_network:
		_self_despawn()
		return

	# Get the intersection at the end of our current road (in our travel direction)
	var intersection: Intersection = _road_network.get_road_end_intersection(
		_assigned_road, _assigned_direction
	)
	if not intersection:
		_self_despawn()
		return

	# Get all connected roads at this intersection, excluding our current road
	var candidates: Array[Dictionary] = _road_network.get_connected_roads(
		intersection, _assigned_road
	)
	if candidates.is_empty():
		_self_despawn()
		return

	# Pick a random connected road
	var choice: Dictionary = candidates[randi() % candidates.size()]
	var next_road: RoadSegment = choice["road"] as RoadSegment
	var next_dir: int = choice["direction"] as int

	_assigned_road = next_road
	_assigned_direction = next_dir
	_target_speed = next_road.speed_limit * randf_range(0.9, 1.1)
	_path_points = next_road.get_lane_points(0, next_dir, 40)
	_path_index = 0
	_state = State.TURNING
	_cleared_intersections.clear()


func _self_despawn() -> void:
	vehicle_despawning.emit()
	queue_free()


func _honk() -> void:
	_honk_cooldown = HONK_COOLDOWN
	# Audio would go here when we have horn sounds


func _find_nearest_path_index() -> int:
	var best_idx: int = 0
	var best_dist: float = INF
	for i in _path_points.size():
		var dist: float = global_position.distance_to(_path_points[i])
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return best_idx
