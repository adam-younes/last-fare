class_name PhasePickingUp
extends GamePhaseState

signal _npc_arrived

const NPC_WALK_SPEED: float = 1.8  ## m/s (~4 mph walking pace)
const NPC_ARRIVE_DISTANCE: float = 1.5  ## meters from car door to trigger entry

var _sidewalk_npc: Node3D = null
var _npc_approaching: bool = false


func enter() -> void:
	active = true
	_npc_approaching = false
	GameState.set_shift_state(GameState.ShiftState.PICKING_UP)
	var passenger: PassengerData = game.current_passenger_data
	var pickup_pos: Vector3 = passenger.pickup_world_position

	# Spawn pickup marker and sidewalk NPC
	game.spawn_pickup_marker(pickup_pos)
	_spawn_sidewalk_npc(pickup_pos)
	game.pickup_detector.set_target(pickup_pos)
	game.phone.show_notification("Drive to pickup: %s" % passenger.pickup_location)
	game.gps.set_destination_position(passenger.pickup_location, pickup_pos)

	# Wait for player to arrive at pickup
	await game.pickup_detector.target_reached
	if not active:
		return

	# Player arrived -- NPC begins approaching the car
	game.remove_pickup_marker()
	game.phone.show_notification("%s is approaching..." % passenger.display_name)
	_npc_approaching = true

	# Wait for NPC to reach the car door
	await _npc_arrived
	if not active:
		return

	# NPC enters the car
	_remove_sidewalk_npc()
	game.spawn_passenger_billboard()
	game.phone.show_notification("%s has entered the vehicle." % passenger.display_name)

	var tree: SceneTree = game.get_tree()
	await tree.create_timer(1.0).timeout
	if not active:
		return
	game.transition_to_phase(game.GamePhase.IN_RIDE)


func process(delta: float) -> void:
	if not _npc_approaching or not _sidewalk_npc:
		return
	# Move NPC toward the car's passenger door each frame
	var door_pos: Vector3 = _get_car_door_position()
	var to_door: Vector3 = door_pos - _sidewalk_npc.global_position
	to_door.y = 0.0  # Keep movement horizontal
	if to_door.length() < NPC_ARRIVE_DISTANCE:
		_npc_approaching = false
		_npc_arrived.emit()
		return
	_sidewalk_npc.global_position += to_door.normalized() * NPC_WALK_SPEED * delta


func exit() -> void:
	active = false
	_npc_approaching = false
	_remove_sidewalk_npc()


func _spawn_sidewalk_npc(pickup_pos: Vector3) -> void:
	var sidewalk_pos: Vector3 = game.road_network.get_sidewalk_position(pickup_pos)
	# Place billboard center at half-height above ground so the bottom touches the ground
	sidewalk_pos.y = pickup_pos.y + 0.75
	_sidewalk_npc = PassengerBillboard.new()
	game.add_child(_sidewalk_npc)
	_sidewalk_npc.global_position = sidewalk_pos


func _remove_sidewalk_npc() -> void:
	if _sidewalk_npc:
		_sidewalk_npc.queue_free()
		_sidewalk_npc = null


func _get_car_door_position() -> Vector3:
	var car: CharacterBody3D = game.car_interior as CharacterBody3D
	# Passenger door is on the right side (+X in car's local space), offset ~1.5m from center
	var right: Vector3 = car.global_transform.basis.x.normalized()
	return car.global_position + right * 1.5
