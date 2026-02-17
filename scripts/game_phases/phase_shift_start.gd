class_name PhaseShiftStart
extends GamePhaseState


func enter() -> void:
	active = true
	game.phone.show_notification("Shift started. Complete all rides to end your shift.")
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(2.0).timeout
	if not active:
		return
	game.transition_to_phase(game.GamePhase.WAITING_FOR_RIDE)
