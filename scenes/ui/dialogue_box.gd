extends Control
## Dialogue display and choice selection system.

signal dialogue_finished
signal choice_made(choice_index: int)

var _current_nodes: Array = []  # Array of DialogueNode
var _current_index: int = -1
var _node_map: Dictionary = {}  # id -> DialogueNode
var _waiting_for_choice: bool = false
var _auto_advance_timer: float = 0.0

@onready var panel: PanelContainer = %DialoguePanel
@onready var speaker_label: Label = %SpeakerLabel
@onready var text_label: RichTextLabel = %TextLabel
@onready var choices_container: VBoxContainer = %ChoicesContainer
@onready var continue_indicator: Label = %ContinueIndicator


func _ready() -> void:
	add_to_group("dialogue_box")
	panel.visible = false


func _process(delta: float) -> void:
	if _auto_advance_timer > 0.0:
		_auto_advance_timer -= delta
		if _auto_advance_timer <= 0.0:
			advance()

	# Blink the continue indicator
	if panel.visible and not _waiting_for_choice and _auto_advance_timer <= 0.0:
		continue_indicator.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	else:
		continue_indicator.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if _waiting_for_choice:
		return
	if event.is_action_pressed("advance_dialogue"):
		advance()
		get_viewport().set_input_as_handled()


## Start a dialogue sequence from an array of DialogueNode resources.
func start_dialogue(nodes: Array) -> void:
	_current_nodes = nodes
	_current_index = -1
	_node_map.clear()
	for node in nodes:
		if node is DialogueNode:
			_node_map[node.id] = node
	panel.visible = true
	advance()


## Advance to the next line or follow a branch.
func advance(target_id: String = "") -> void:
	# Clear choices
	_clear_choices()
	_waiting_for_choice = false
	_auto_advance_timer = 0.0

	var next_node: DialogueNode = null

	if not target_id.is_empty():
		next_node = _node_map.get(target_id)
	else:
		# Try current node's next_node first
		if _current_index >= 0 and _current_index < _current_nodes.size():
			var current: DialogueNode = _current_nodes[_current_index] as DialogueNode
			if current and not current.next_node.is_empty():
				next_node = _node_map.get(current.next_node)

		# Otherwise advance sequentially
		if next_node == null:
			_current_index += 1
			if _current_index < _current_nodes.size():
				next_node = _current_nodes[_current_index] as DialogueNode

	if next_node == null:
		_end_dialogue()
		return

	# Update index to match this node
	for i in _current_nodes.size():
		if _current_nodes[i] == next_node:
			_current_index = i
			break

	# Check condition
	if not GameState.evaluate_condition(next_node.condition):
		# Skip this node, try next
		advance()
		return

	# Fire triggers
	_fire_triggers(next_node.triggers)

	# Handle pre-delay
	if next_node.pre_delay > 0.0:
		await get_tree().create_timer(next_node.pre_delay).timeout

	# Display
	_display_node(next_node)


func _display_node(node: DialogueNode) -> void:
	speaker_label.text = _format_speaker(node.speaker)
	text_label.text = _substitute_variables(node.text)

	# Color the speaker label based on who's talking
	match node.speaker:
		"PASSENGER":
			speaker_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		"DRIVER", "PLAYER":
			speaker_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		"GPS":
			speaker_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		"PHONE":
			speaker_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
		"INTERNAL", "NARRATOR":
			speaker_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	# Show choices if any
	var valid_choices: Array = []
	for choice in node.choices:
		if choice is DialogueChoice:
			if GameState.evaluate_condition(choice.condition):
				valid_choices.append(choice)

	if valid_choices.size() > 0:
		_show_choices(valid_choices)
	elif node.auto_advance > 0.0:
		_auto_advance_timer = node.auto_advance


func _show_choices(choices: Array) -> void:
	_waiting_for_choice = true
	for i in choices.size():
		var choice: DialogueChoice = choices[i]
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, choice.text]
		button.pressed.connect(_on_choice_selected.bind(choice))
		choices_container.add_child(button)


func _on_choice_selected(choice: DialogueChoice) -> void:
	_waiting_for_choice = false

	if not choice.sets_flag.is_empty():
		GameState.set_flag(choice.sets_flag)

	_fire_triggers(choice.triggers)
	choice_made.emit(choices_container.get_children().find(
		func(c): return c is Button and c.text.ends_with(choice.text)
	))

	if not choice.next_node.is_empty():
		advance(choice.next_node)
	else:
		advance()


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()


func _end_dialogue() -> void:
	panel.visible = false
	_current_nodes.clear()
	_node_map.clear()
	_current_index = -1
	dialogue_finished.emit()


func _format_speaker(speaker: String) -> String:
	match speaker:
		"PASSENGER":
			return "Passenger"
		"DRIVER", "PLAYER":
			return GameState.player_name
		"GPS":
			return "GPS"
		"PHONE":
			return "FareShare App"
		"INTERNAL":
			return "(Thinking)"
		"NARRATOR":
			return ""
		_:
			return speaker


func _substitute_variables(text: String) -> String:
	# Replace placeholders with player profile data
	text = text.replace("{player_name}", GameState.player_name)
	text = text.replace("{player_hometown}", GameState.player_hometown)
	text = text.replace("{car_color}", GameState.player_car_color)
	text = text.replace("{years_driving}", str(GameState.player_years_driving))
	text = text.replace("{current_time}", GameState.get_display_time())
	return text


func _fire_triggers(triggers: Array) -> void:
	for trigger: String in triggers:
		var parts := trigger.split(":", true, 1)
		var action := parts[0]
		var param := parts[1] if parts.size() > 1 else ""

		match action:
			"set_flag":
				GameState.set_flag(param)
			"remove_flag":
				GameState.remove_flag(param)
			"gps":
				var gps := get_tree().get_first_node_in_group("gps")
				if gps and gps.has_method("set_state"):
					match param:
						"glitch":
							gps.set_state(1)  # GPSState.GLITCHING
						"no_signal":
							gps.set_state(3)  # GPSState.NO_SIGNAL
						"normal":
							gps.set_state(0)  # GPSState.NORMAL
			"event":
				EventManager.trigger(param)
			"ambience":
				match param:
					"tension":
						AudioManager.set_ambience(AudioManager.AmbienceState.TENSION)
					"silence":
						AudioManager.set_ambience(AudioManager.AmbienceState.SILENCE)
					"wrong":
						AudioManager.set_ambience(AudioManager.AmbienceState.WRONG)
					"normal":
						AudioManager.set_ambience(AudioManager.AmbienceState.NORMAL_DRIVING)
