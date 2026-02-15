class_name PassengerData
extends Resource
## Data resource defining a passenger: who they are, when they appear, and what happens.

@export_group("Identity")
@export var id: String
@export var display_name: String  ## What shows on the ride request
@export var pickup_location: String
@export var destination: String
@export var destination_exists: bool = true  ## false = GPS breaks

@export_group("Appearance")
@export var portrait: Texture2D  ## 2D portrait for dialogue
@export var silhouette_color: Color = Color(0.1, 0.1, 0.1, 0.9)

@export_group("Dialogue")
@export var dialogue_nodes: Array[DialogueNode]

@export_group("Conditions")
## Flags that must be set for this passenger to appear
@export var required_flags: Array[String]
## Flags that prevent this passenger from appearing
@export var excluded_flags: Array[String]
@export var min_ride_number: int = 0
@export var max_ride_number: int = 99
## 24hr time window (x=start, y=end) e.g. (23, 3) = 11PM to 3AM
@export var time_window: Vector2 = Vector2(0, 24)

@export_group("Consequences")
## Flags set when this ride is completed
@export var sets_flags: Array[String]
## Event triggered during/after this ride
@export var triggers_event: String
## Can the player refuse this ride?
@export var is_refusable: bool = true
## Event triggered if player refuses
@export var refuse_consequence: String
## Is this a mandatory story encounter?
@export var is_mandatory: bool = false

@export_group("Behavior Vector")
@export_range(0.0, 1.0) var talkativeness: float = 0.5
@export_range(0.0, 1.0) var nervousness: float = 0.3
@export_range(0.0, 1.0) var aggression: float = 0.2
@export_range(0.0, 1.0) var threat: float = 0.0

@export_group("Archetype")
@export var archetype: String = ""
@export var is_procedural: bool = false

@export_group("Locations")
@export var pickup_world_position: Vector3 = Vector3.ZERO
@export var destination_world_position: Vector3 = Vector3.ZERO

@export_group("Ambience")
## Override ambient state while this passenger is in the car
@export var ambient_override: int = -1  ## -1 = no override, otherwise AmbienceState enum value
## Additional one-shot sounds during ride
@export var ride_sounds: Array[AudioStream]


func meets_conditions(current_flags: Dictionary[String, bool], ride_number: int, current_time: float) -> bool:
	# Check ride number
	if ride_number < min_ride_number or ride_number > max_ride_number:
		return false

	# Check required flags
	for flag in required_flags:
		if not current_flags.has(flag):
			return false

	# Check excluded flags
	for flag in excluded_flags:
		if current_flags.has(flag):
			return false

	# Check time window
	if time_window.x < time_window.y:
		# Normal range (e.g., 2 to 5)
		if current_time < time_window.x or current_time > time_window.y:
			return false
	else:
		# Wrapping range (e.g., 23 to 3)
		if current_time < time_window.x and current_time > time_window.y:
			return false

	return true
