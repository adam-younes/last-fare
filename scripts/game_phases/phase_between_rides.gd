class_name PhaseBetweenRides
extends GamePhaseState


func enter() -> void:
	active = true
	GameState.set_shift_state(GameState.ShiftState.BETWEEN_RIDES)
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(3.0).timeout
	if not active:
		return
	game.transition_to_phase(game.GamePhase.WAITING_FOR_RIDE)
