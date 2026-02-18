class_name ViolationIndicator
extends Label
## Flashing violation indicator shown at top of screen.

var _flash_timer: float = 0.0

const FLASH_DURATION: float = 3.0
const FLASH_SPEED: float = 6.0  # Hz


func _ready() -> void:
	visible = false


func flash(violation_text: String) -> void:
	text = violation_text
	_flash_timer = FLASH_DURATION
	visible = true


func _process(delta: float) -> void:
	if _flash_timer <= 0.0:
		return

	_flash_timer -= delta

	if _flash_timer <= 0.0:
		visible = false
		modulate.a = 1.0
		return

	# Oscillate alpha for flash effect
	var t: float = _flash_timer * FLASH_SPEED * TAU
	modulate.a = 0.4 + 0.6 * absf(sin(t))
