class_name PhaseRideOffered
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.RIDE_OFFERED)
