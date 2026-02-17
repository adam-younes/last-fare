extends Control
## GPS display — the primary scare delivery system.
## Players must look at it, making it the ideal vector for horror.

signal destination_reached
signal message_displayed(text: String)

enum GPSState {
	NORMAL,
	GLITCHING,
	WRONG_DESTINATION,
	NO_SIGNAL,
	DIRECTING_SOMEWHERE_ELSE,
	SHOWING_MESSAGE,
}

var current_state: GPSState = GPSState.NORMAL
var displayed_destination: String = ""
var actual_destination: String = ""
var _glitch_timer: float = 0.0
var _target_world_position: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _car_node: Node = null

@onready var destination_label: Label = %DestinationLabel
@onready var eta_label: Label = %ETALabel
@onready var status_label: Label = %StatusLabel
@onready var glitch_overlay: ColorRect = %GlitchOverlay
@onready var route_line: Control = %RouteLine


func _ready() -> void:
	add_to_group("gps")
	glitch_overlay.visible = false
	set_state(GPSState.NORMAL)


func _process(delta: float) -> void:
	if current_state == GPSState.GLITCHING:
		_glitch_timer += delta
		_update_glitch_effect()

	if _has_target and current_state == GPSState.NORMAL:
		if _car_node == null:
			_car_node = get_tree().get_first_node_in_group("car_interior")
		if _car_node:
			var dist: float = _car_node.global_position.distance_to(_target_world_position)
			var dist_display: String = "%.0fm" % dist if dist < 1000.0 else "%.1fkm" % (dist / 1000.0)
			eta_label.text = dist_display


func set_destination(dest: String) -> void:
	actual_destination = dest
	displayed_destination = dest
	destination_label.text = dest
	status_label.text = "Navigating..."
	eta_label.text = _generate_eta()
	_has_target = false


func set_destination_position(dest_name: String, world_pos: Vector3) -> void:
	set_destination(dest_name)
	_target_world_position = world_pos
	_has_target = true


func set_state(new_state: GPSState, data: Dictionary = {}) -> void:
	current_state = new_state
	match new_state:
		GPSState.NORMAL:
			glitch_overlay.visible = false
			destination_label.text = displayed_destination
			status_label.text = "Navigating..."
			eta_label.visible = true
		GPSState.GLITCHING:
			glitch_overlay.visible = true
			_glitch_timer = 0.0
		GPSState.WRONG_DESTINATION:
			glitch_overlay.visible = false
			var fake: String = data.get("fake_destination", "???")
			destination_label.text = fake
			status_label.text = "Arriving at destination"
			# Player sees a destination they didn't input
		GPSState.NO_SIGNAL:
			glitch_overlay.visible = false
			destination_label.text = "---"
			status_label.text = "No Signal"
			eta_label.text = ""
		GPSState.DIRECTING_SOMEWHERE_ELSE:
			glitch_overlay.visible = false
			var redirect: String = data.get("redirect_destination", "UNKNOWN")
			destination_label.text = redirect
			status_label.text = "Rerouting..."
			# GPS is taking you somewhere you didn't choose
		GPSState.SHOWING_MESSAGE:
			glitch_overlay.visible = false
			var msg: String = data.get("message", "")
			destination_label.text = msg
			status_label.text = ""
			eta_label.text = ""
			message_displayed.emit(msg)


func arrive() -> void:
	status_label.text = "You have arrived"
	eta_label.text = ""
	_has_target = false
	destination_reached.emit()


func _generate_eta() -> String:
	return "%d min" % randi_range(5, 25)


func _update_glitch_effect() -> void:
	# Rapid text corruption
	if fmod(_glitch_timer, 0.15) < 0.075:
		var corrupted := ""
		for i in displayed_destination.length():
			if randf() > 0.6:
				corrupted += char(randi_range(33, 126))
			else:
				corrupted += displayed_destination[i]
		destination_label.text = corrupted
	else:
		destination_label.text = displayed_destination

	# Flicker the overlay opacity
	glitch_overlay.modulate.a = randf_range(0.05, 0.3)
