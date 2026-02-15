class_name ProximityDetector
extends Node
## Detects when the player's car arrives at a target position (stopped and within radius).

signal target_reached

@export var trigger_radius: float = 5.0

var _target_position: Vector3 = Vector3.ZERO
var _is_active: bool = false
var _armed: bool = false


func set_target(world_pos: Vector3) -> void:
	if world_pos == Vector3.ZERO:
		push_warning("ProximityDetector: Target set to origin (0,0,0) — likely uninitialized")
	_target_position = world_pos
	_is_active = true
	_armed = false


func clear_target() -> void:
	_is_active = false


func _physics_process(_delta: float) -> void:
	if not _is_active:
		return

	var car: Node = get_tree().get_first_node_in_group("car_interior")
	if not car:
		return

	var dist: float = car.global_position.distance_to(_target_position)

	# Must leave the trigger radius first before it can fire
	if not _armed:
		if dist > trigger_radius:
			_armed = true
		return

	if dist < trigger_radius:
		# Only trigger if car is nearly stopped
		if car.get_speed() < 2.0:
			_is_active = false
			target_reached.emit()
