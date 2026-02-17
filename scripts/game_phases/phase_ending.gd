class_name PhaseEnding
extends GamePhaseState


func enter() -> void:
	active = true
	GameState.set_shift_state(GameState.ShiftState.SHIFT_ENDING)
	game.handle_ending()
