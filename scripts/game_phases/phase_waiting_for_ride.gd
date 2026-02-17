class_name PhaseWaitingForRide
extends GamePhaseState


func enter() -> void:
	active = true
	GameState.set_shift_state(GameState.ShiftState.WAITING_FOR_RIDE)
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(1.5).timeout
	if not active:
		return
	game.offer_next_ride()
