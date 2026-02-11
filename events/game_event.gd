class_name GameEvent
extends Node
## Base class for scripted scare/event sequences.

signal completed

var event_id: String = ""


## Override this in event scripts to define the sequence.
func execute(_params: Dictionary = {}) -> void:
	completed.emit()


## Helper: wait for a duration (use in event scripts for timing).
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Helper: trigger a flag through GameState.
func set_flag(flag_name: String) -> void:
	GameState.set_flag(flag_name)


## Helper: change GPS state — call on the GPS node found in the scene tree.
func get_gps() -> Node:
	return get_tree().get_first_node_in_group("gps")


## Helper: get the car interior scene.
func get_car() -> Node:
	return get_tree().get_first_node_in_group("car_interior")
