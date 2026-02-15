class_name PhaseInRide
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.IN_RIDE)
	game.ride_timer = 0.0
	var passenger: PassengerData = game.current_passenger_data
	var dest_pos: Vector3 = passenger.destination_world_position
	game.spawn_destination_marker(dest_pos)
	game.destination_detector.set_target(dest_pos)
	game.gps.set_destination_position(passenger.destination, dest_pos)

	if not passenger.destination_exists:
		var tree: SceneTree = game.get_tree()
		await tree.create_timer(5.0).timeout
		game.gps.set_state(game.gps.GPSState.GLITCHING)
		await tree.create_timer(2.0).timeout
		game.gps.set_state(game.gps.GPSState.NO_SIGNAL, {"message": "Destination not found"})

	if passenger.ambient_override >= 0:
		AudioManager.set_ambience(passenger.ambient_override as AudioManager.AmbienceState)

	game.start_passenger_dialogue()

	if not passenger.triggers_event.is_empty():
		EventManager.trigger(passenger.triggers_event)


func process(delta: float) -> void:
	game.ride_timer += delta
	GameState.advance_time(delta * 0.033)
