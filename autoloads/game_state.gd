extends Node
## Manages shift progress, passenger history, flags, and game state.

signal flag_set(flag_name: String)
signal flag_removed(flag_name: String)
signal ride_completed(ride_number: int)
signal shift_state_changed(new_state: ShiftState)

enum ShiftState {
	NOT_STARTED,
	WAITING_FOR_RIDE,
	RIDE_OFFERED,
	PICKING_UP,
	IN_RIDE,
	DROPPING_OFF,
	BETWEEN_RIDES,
	SHIFT_ENDING,
	SHIFT_OVER,
}

# Player profile — passengers reference these to "know things about you"
var player_name: String = "Alex"
var player_hometown: String = "Cedar Falls"
var player_car_color: String = "silver"
var player_years_driving: int = 3

# Shift tracking
var current_shift_state: ShiftState = ShiftState.NOT_STARTED
var current_ride_number: int = 0
var total_rides_required: int = 3
var current_time_hours: float = 23.0  # Start at 11 PM, 24hr format
var time_speed_multiplier: float = 1.0
var current_night: int = 1
var last_narrative_ride_number: int = 0
var rides_completed: int = 0

# Flags — the backbone of narrative branching
var flags: Dictionary = {}

# History
var completed_passenger_ids: Array[String] = []
var refused_passenger_ids: Array[String] = []

# Current ride
var current_passenger_id: String = ""


func _ready() -> void:
	pass


func start_shift() -> void:
	current_shift_state = ShiftState.WAITING_FOR_RIDE
	current_ride_number = 0
	current_time_hours = 23.0
	flags.clear()
	completed_passenger_ids.clear()
	refused_passenger_ids.clear()
	shift_state_changed.emit(current_shift_state)


func set_shift_state(new_state: ShiftState) -> void:
	current_shift_state = new_state
	shift_state_changed.emit(new_state)


func advance_time(hours: float) -> void:
	current_time_hours += hours * time_speed_multiplier
	if current_time_hours >= 24.0:
		current_time_hours -= 24.0


func get_display_time() -> String:
	var h := int(current_time_hours) % 12
	if h == 0:
		h = 12
	var m := int(fmod(current_time_hours, 1.0) * 60)
	var ampm := "AM" if current_time_hours >= 0.0 and current_time_hours < 12.0 else "PM"
	return "%d:%02d %s" % [h, m, ampm]


# --- Flag system ---

func set_flag(flag_name: String) -> void:
	if not flags.has(flag_name):
		flags[flag_name] = true
		flag_set.emit(flag_name)


func remove_flag(flag_name: String) -> void:
	if flags.has(flag_name):
		flags.erase(flag_name)
		flag_removed.emit(flag_name)


func has_flag(flag_name: String) -> bool:
	return flags.has(flag_name)


func evaluate_condition(condition: String) -> bool:
	if condition.is_empty():
		return true

	# Simple flag expression parser: "has:flag_a AND NOT has:flag_b"
	var parts := condition.split(" AND ")
	for part in parts:
		part = part.strip_edges()
		if part.begins_with("NOT "):
			var flag_expr := part.substr(4).strip_edges()
			if flag_expr.begins_with("has:"):
				if has_flag(flag_expr.substr(4)):
					return false
		elif part.begins_with("has:"):
			if not has_flag(part.substr(4)):
				return false

	return true


# --- Ride tracking ---

func complete_ride(passenger_id: String, is_narrative: bool = false) -> void:
	completed_passenger_ids.append(passenger_id)
	current_ride_number += 1
	rides_completed += 1
	current_passenger_id = ""
	if is_narrative:
		last_narrative_ride_number = rides_completed
	ride_completed.emit(current_ride_number)


func refuse_ride(passenger_id: String) -> void:
	refused_passenger_ids.append(passenger_id)
	current_passenger_id = ""


func has_completed_passenger(passenger_id: String) -> bool:
	return passenger_id in completed_passenger_ids


func has_refused_passenger(passenger_id: String) -> bool:
	return passenger_id in refused_passenger_ids


func is_shift_complete() -> bool:
	return current_ride_number >= total_rides_required
