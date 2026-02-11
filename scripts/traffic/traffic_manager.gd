class_name TrafficManager
extends Node
## Spawns and despawns AI traffic vehicles around the player.

@export var max_vehicles: int = 12
@export var spawn_radius: float = 120.0
@export var despawn_radius: float = 160.0
@export var spawn_interval: float = 2.0
@export var min_spawn_distance: float = 30.0  # don't spawn on top of player

var _active_vehicles: Array[TrafficVehicle] = []
var _spawn_timer: float = 0.0
var _vehicle_scene: PackedScene
var _road_network: RoadNetwork = null
var _player_car: CharacterBody3D = null

const VEHICLE_COLORS: Array[Color] = [
	Color(0.15, 0.15, 0.25),  # dark blue
	Color(0.12, 0.2, 0.12),   # dark green
	Color(0.3, 0.1, 0.1),     # dark red
	Color(0.25, 0.25, 0.25),  # gray
	Color(0.08, 0.08, 0.08),  # black
	Color(0.7, 0.7, 0.7),     # white
	Color(0.3, 0.25, 0.15),   # brown
	Color(0.2, 0.2, 0.3),     # slate
]


func initialize(road_network: RoadNetwork, player_car: CharacterBody3D) -> void:
	_road_network = road_network
	_player_car = player_car
	_vehicle_scene = preload("res://scenes/traffic/traffic_vehicle.tscn")


func _process(delta: float) -> void:
	if not _road_network or not _player_car:
		return

	_despawn_far_vehicles()

	_spawn_timer += delta
	if _spawn_timer >= spawn_interval:
		_spawn_timer = 0.0
		_try_spawn()


func _try_spawn() -> void:
	if _active_vehicles.size() >= max_vehicles:
		return

	var roads: Array[RoadSegment] = _road_network.get_roads()
	if roads.is_empty():
		return

	# Try a few times to find a valid spawn position
	for _attempt in 5:
		var road: RoadSegment = roads[randi() % roads.size()]
		var direction: int = 1 if randf() > 0.5 else -1
		var t: float = randf()
		var baked_length: float = road.curve.get_baked_length()
		var local_pos: Vector3 = road.curve.sample_baked(t * baked_length)

		# Calculate lane offset
		var next_t: float = minf(t + 0.01, 1.0)
		var next_pos: Vector3 = road.curve.sample_baked(next_t * baked_length)
		var forward: Vector3 = next_pos - local_pos
		if forward.length() < 0.001:
			continue

		var right: Vector3 = forward.normalized().cross(Vector3.UP).normalized()
		var offset: float = (0.5) * road.lane_width * direction
		local_pos += right * offset

		var spawn_pos: Vector3 = road.global_transform * local_pos
		spawn_pos.y = 0.6  # Raise to car height

		# Distance checks
		var player_dist: float = _player_car.global_position.distance_to(spawn_pos)
		if player_dist < min_spawn_distance or player_dist > spawn_radius:
			continue

		# Check overlap with existing vehicles
		var too_close: bool = false
		for vehicle in _active_vehicles:
			if is_instance_valid(vehicle) and vehicle.global_position.distance_to(spawn_pos) < 10.0:
				too_close = true
				break
		if too_close:
			continue

		# Spawn the vehicle
		_spawn_vehicle(road, direction, spawn_pos, forward)
		return


func _spawn_vehicle(road: RoadSegment, direction: int, pos: Vector3, forward: Vector3) -> void:
	var vehicle: TrafficVehicle = _vehicle_scene.instantiate() as TrafficVehicle
	add_child(vehicle)

	vehicle.global_position = pos

	# Face the correct direction
	var face_dir: Vector3 = forward.normalized() * direction
	if face_dir.length() > 0.001:
		var target_angle: float = atan2(-face_dir.x, -face_dir.z)
		vehicle.rotation.y = target_angle

	# Randomize color
	var car_mesh: MeshInstance3D = vehicle.get_node("CarMesh") as MeshInstance3D
	if car_mesh and car_mesh.material_override:
		var mat: StandardMaterial3D = car_mesh.material_override.duplicate() as StandardMaterial3D
		mat.albedo_color = VEHICLE_COLORS[randi() % VEHICLE_COLORS.size()]
		car_mesh.material_override = mat

	vehicle.initialize(road, direction, _road_network)
	_active_vehicles.append(vehicle)


func _despawn_far_vehicles() -> void:
	var i: int = _active_vehicles.size() - 1
	while i >= 0:
		var vehicle: TrafficVehicle = _active_vehicles[i]
		if not is_instance_valid(vehicle):
			_active_vehicles.remove_at(i)
		elif _player_car.global_position.distance_to(vehicle.global_position) > despawn_radius:
			vehicle.queue_free()
			_active_vehicles.remove_at(i)
		i -= 1
