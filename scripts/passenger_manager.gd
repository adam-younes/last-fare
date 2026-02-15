class_name PassengerManager
extends Node
## Selects the next passenger — narrative or procedural — based on game state.

const PASSENGER_DIR := "res://resources/passengers/"

@export var all_passengers: Array[PassengerData]

## Passengers that must appear regardless of random selection.
@export var mandatory_encounter_ids: Array[String]

var _procedural_generator: ProceduralPassengerGenerator
var _road_network: RoadNetwork = null


func _ready() -> void:
	if all_passengers.is_empty():
		_load_passengers_from_directory()
	_procedural_generator = ProceduralPassengerGenerator.new()


func initialize(road_network: RoadNetwork) -> void:
	_road_network = road_network


func _load_passengers_from_directory() -> void:
	var dir := DirAccess.open(PASSENGER_DIR)
	if dir == null:
		push_warning("PassengerManager: Could not open %s" % PASSENGER_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res := load(PASSENGER_DIR + file_name)
			if res is PassengerData:
				all_passengers.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	print("PassengerManager: Loaded %d passengers" % all_passengers.size())


func get_next_passenger() -> PassengerData:
	# 1. Evaluate narrative probability
	var narrative_probability: float = _calculate_narrative_probability()
	var roll: float = randf()

	# 2. If roll lands in narrative range, try to get a narrative passenger
	if roll < narrative_probability:
		var narrative: PassengerData = _get_eligible_narrative_passenger()
		if narrative:
			_assign_world_positions(narrative)
			return narrative

	# 3. Otherwise, generate procedural (needs road network)
	if _road_network:
		return _procedural_generator.generate(_road_network)
	else:
		push_warning("PassengerManager: No road network, cannot generate procedural passenger")

	# 4. Fallback: try narrative anyway
	var fallback: PassengerData = _get_eligible_narrative_passenger()
	if fallback:
		_assign_world_positions(fallback)
		return fallback

	return null


func _get_eligible_narrative_passenger() -> PassengerData:
	var candidates: Array[PassengerData] = []

	for p in all_passengers:
		if GameState.has_completed_passenger(p.id):
			continue
		if GameState.has_refused_passenger(p.id):
			continue
		if p.meets_conditions(GameState.flags, GameState.current_ride_number, GameState.current_time_hours):
			candidates.append(p)

	if candidates.is_empty():
		return null

	# Mandatory encounters take priority
	for candidate in candidates:
		if candidate.is_mandatory or candidate.id in mandatory_encounter_ids:
			return candidate

	# Otherwise pick randomly
	return candidates[randi() % candidates.size()]


func _calculate_narrative_probability() -> float:
	var night: float = float(GameState.current_night)
	var since_last: float = float(GameState.rides_completed - GameState.last_narrative_ride_number)

	# Base probability increases with night progression
	var base: float = remap(night, 1.0, 14.0, 0.1, 0.5)

	# Increase if it's been a while since last narrative passenger
	var urgency: float = clampf(since_last / 5.0, 0.0, 0.3)

	return clampf(base + urgency, 0.0, 0.8)


func _assign_world_positions(passenger: PassengerData) -> void:
	if not _road_network:
		return

	# Only assign if positions are default (zero)
	if passenger.pickup_world_position == Vector3.ZERO:
		var pickup: RoadNetwork.RoadPosition = _road_network.get_random_road_position()
		passenger.pickup_world_position = pickup.position

	if passenger.destination_world_position == Vector3.ZERO and passenger.destination_exists:
		var destination: RoadNetwork.RoadPosition = _road_network.get_random_road_position()
		passenger.destination_world_position = destination.position


func get_available_count() -> int:
	# With procedural generation, there's always passengers available
	if _road_network:
		return 99

	var count: int = 0
	for p in all_passengers:
		if GameState.has_completed_passenger(p.id):
			continue
		if GameState.has_refused_passenger(p.id):
			continue
		if p.meets_conditions(GameState.flags, GameState.current_ride_number, GameState.current_time_hours):
			count += 1
	return count
