class_name TrafficVehicle
extends CharacterBody3D
## AI vehicle that follows road paths, obeys traffic lights, and reacts to obstacles.

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
	if not is_on_floor():
		velocity.y -= 9.8 * delta
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
	if _should_stop_for_light():
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

	if obstacle_clear and not _should_stop_for_light():
		_state = State.DRIVING


func _process_stopped(delta: float) -> void:
	_stopped_timer += delta

	# Check if can resume
	var obstacle_clear: bool = true
	if front_ray and front_ray.is_colliding():
		var dist: float = global_position.distance_to(front_ray.get_collision_point())
		if dist < STOP_DISTANCE * 2.5:
			obstacle_clear = false

	if obstacle_clear and not _should_stop_for_light():
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


func _should_stop_for_light() -> bool:
	if not _road_network or not _assigned_road:
		return false

	# Check if approaching an intersection
	var look_ahead: float = 15.0
	if _path_index < _path_points.size():
		var current_pos: Vector3 = global_position
		var intersection: Intersection = _road_network.get_intersection_at(current_pos, look_ahead)
		if intersection:
			var dist: float = current_pos.distance_to(intersection.global_position)
			# Only stop if we're approaching (not already in intersection)
			if dist > STOP_DISTANCE and dist < look_ahead:
				var light_state: Intersection.LightState = intersection.get_light_state(_assigned_road)
				if light_state != Intersection.LightState.GREEN:
					return true
	return false


func _try_next_road() -> void:
	if not _road_network:
		queue_free()
		return

	# Find intersection at end of current road
	var end_pos: Vector3 = _path_points[_path_points.size() - 1]
	var intersection: Intersection = _road_network.get_intersection_at(end_pos, 10.0)

	if not intersection:
		queue_free()
		return

	# Pick a random connected road (different from current)
	var roads: Array[RoadSegment] = _road_network.get_roads()
	var candidates: Array[RoadSegment] = []
	for road in roads:
		if road != _assigned_road:
			# Check if this road passes near the intersection
			var road_start: Vector3 = road.global_transform * road.curve.get_point_position(0)
			var road_end: Vector3 = road.global_transform * road.curve.get_point_position(road.curve.point_count - 1)
			if road_start.distance_to(intersection.global_position) < 10.0 or road_end.distance_to(intersection.global_position) < 10.0:
				candidates.append(road)

	if candidates.is_empty():
		queue_free()
		return

	var next_road: RoadSegment = candidates[randi() % candidates.size()]

	# Determine direction based on which end of the road is near the intersection
	var start_pos: Vector3 = next_road.global_transform * next_road.curve.get_point_position(0)
	var next_dir: int = 1 if start_pos.distance_to(intersection.global_position) < 10.0 else -1

	_assigned_road = next_road
	_assigned_direction = next_dir
	_target_speed = next_road.speed_limit * randf_range(0.9, 1.1)
	_path_points = next_road.get_lane_points(0, next_dir, 40)
	_path_index = 0
	_state = State.TURNING


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
