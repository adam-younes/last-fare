class_name PhasePickingUp
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.PICKING_UP)
	var passenger: PassengerData = game.current_passenger_data
	var pickup_pos: Vector3 = passenger.pickup_world_position
	game.spawn_pickup_marker(pickup_pos)
	game.pickup_detector.set_target(pickup_pos)
	game.phone.show_notification("Drive to pickup: %s" % passenger.pickup_location)
	game.gps.set_destination_position(passenger.pickup_location, pickup_pos)
	await game.pickup_detector.target_reached
	game.remove_pickup_marker()
	game.spawn_passenger_billboard()
	game.phone.show_notification("%s has entered the vehicle." % passenger.display_name)
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(1.0).timeout
	game.transition_to_phase(game.GamePhase.IN_RIDE)
