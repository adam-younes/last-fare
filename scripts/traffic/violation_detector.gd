class_name ViolationDetector
extends Node
## Monitors player entry into intersection zones and detects traffic violations.

signal violation_detected(violation_type: String)

const STOP_SPEED_THRESHOLD: float = 2.2  # m/s (~5 mph)
const VIOLATION_COOLDOWN: float = 5.0    # seconds before same intersection can trigger again

var _player: CharacterBody3D = null
var _road_network: RoadNetwork = null
var _cooldowns: Dictionary = {}  # Intersection -> float (remaining cooldown)


func initialize(network: RoadNetwork, player: CharacterBody3D) -> void:
	_road_network = network
	_player = player

	for intersection: Intersection in network.get_intersections():
		intersection.zone_entered.connect(_on_intersection_zone_entered.bind(intersection))


func _physics_process(delta: float) -> void:
	# Tick down cooldowns
	var to_remove: Array[Intersection] = []
	for intersection: Intersection in _cooldowns:
		_cooldowns[intersection] = (_cooldowns[intersection] as float) - delta
		if (_cooldowns[intersection] as float) <= 0.0:
			to_remove.append(intersection)
	for intersection in to_remove:
		_cooldowns.erase(intersection)


func _on_intersection_zone_entered(body: Node3D, intersection: Intersection) -> void:
	if body != _player:
		return

	# Skip if on cooldown for this intersection
	if _cooldowns.has(intersection):
		return

	match intersection.intersection_type:
		Intersection.IntersectionType.TRAFFIC_LIGHT:
			_check_red_light(intersection)
		Intersection.IntersectionType.STOP_SIGN:
			_check_stop_sign(intersection)


func _check_red_light(intersection: Intersection) -> void:
	# Determine which road the player is on
	var player_road: RoadSegment = _road_network.get_nearest_road(_player.global_position)
	if not player_road:
		return

	var light_state: Intersection.LightState = intersection.get_light_state(player_road)
	if light_state == Intersection.LightState.RED:
		_cooldowns[intersection] = VIOLATION_COOLDOWN
		violation_detected.emit("RED LIGHT")


func _check_stop_sign(intersection: Intersection) -> void:
	var speed: float = _player.get_speed()
	if speed > STOP_SPEED_THRESHOLD:
		_cooldowns[intersection] = VIOLATION_COOLDOWN
		violation_detected.emit("STOP SIGN")
