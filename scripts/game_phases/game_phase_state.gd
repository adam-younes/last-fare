class_name GamePhaseState
extends RefCounted
## Base class for game phase states.

var game: Node = null


func enter() -> void:
	pass


func exit() -> void:
	pass


func process(_delta: float) -> void:
	pass
