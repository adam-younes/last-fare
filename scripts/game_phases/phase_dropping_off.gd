class_name PhaseDroppingOff
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.DROPPING_OFF)
	game.gps.arrive()
	var passenger: PassengerData = game.current_passenger_data

	for flag: String in passenger.sets_flags:
		GameState.set_flag(flag)

	var is_narrative: bool = not passenger.is_procedural
	GameState.complete_ride(passenger.id, is_narrative)
	game.car_interior.remove_passenger()
	game.phone.show_notification("Ride complete.")
	GameState.advance_time(randf_range(0.75, 1.5))

	var tree: SceneTree = game.get_tree()
	await tree.create_timer(2.0).timeout

	if GameState.is_shift_complete():
		game.transition_to_phase(game.GamePhase.ENDING)
	else:
		game.transition_to_phase(game.GamePhase.BETWEEN_RIDES)
