extends Control
## Pause overlay — freezes the game tree and shows resume/quit options.

signal resumed
signal quit_requested

@onready var resume_button: Button = %ResumeButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(_on_resume)
	quit_button.pressed.connect(_on_quit)


func show_pause() -> void:
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func hide_pause() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			hide_pause()
			resumed.emit()
		else:
			show_pause()
		get_viewport().set_input_as_handled()


func _on_resume() -> void:
	hide_pause()
	resumed.emit()


func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()
