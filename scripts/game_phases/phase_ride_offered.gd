class_name PhaseRideOffered
extends GamePhaseState


func enter() -> void:
	active = true
	GameState.set_shift_state(GameState.ShiftState.RIDE_OFFERED)
