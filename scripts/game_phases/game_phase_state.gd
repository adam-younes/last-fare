class_name GamePhaseState
extends RefCounted
## Base class for game phase states.

var game: Node = null
var active: bool = false


func enter() -> void:
	active = true


func exit() -> void:
	active = false


func process(_delta: float) -> void:
	pass
