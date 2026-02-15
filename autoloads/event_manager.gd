extends Node
## Manages scare events and scripted sequences.

signal event_triggered(event_id: String)
signal event_completed(event_id: String)

var _event_scripts: Dictionary[String, GDScript] = {}
var _active_event: GameEvent = null


func _ready() -> void:
	# Register event scripts — add more as you build them
	_register_events()


func _register_events() -> void:
	# Events will be registered as their scripts are created.
	# Example:
	# _event_scripts["rear_mirror_face"] = preload("res://events/rear_mirror_face.gd")
	# _event_scripts["gps_hijack"] = preload("res://events/gps_hijack.gd")
	# _event_scripts["passenger_gone"] = preload("res://events/passenger_gone.gd")
	pass


func trigger(event_id: String, params: Dictionary = {}) -> void:
	if _active_event != null:
		push_warning("Event '%s' already running, queuing '%s'" % [_active_event.event_id, event_id])
		return

	if event_id in _event_scripts:
		var script: GDScript = _event_scripts[event_id]
		_active_event = GameEvent.new()
		_active_event.set_script(script)
		_active_event.event_id = event_id
		add_child(_active_event)
		event_triggered.emit(event_id)
		_active_event.execute(params)
		_active_event.completed.connect(_on_event_completed.bind(event_id))
	else:
		# Handle simple flag-based triggers that don't need a full script
		_handle_simple_trigger(event_id, params)


func _on_event_completed(event_id: String) -> void:
	if _active_event:
		_active_event.queue_free()
		_active_event = null
	event_completed.emit(event_id)


func _handle_simple_trigger(event_id: String, params: Dictionary) -> void:
	# Handle common triggers that don't need dedicated scripts
	match event_id:
		"set_flag":
			if params.has("flag"):
				GameState.set_flag(params["flag"])
		"advance_time":
			if params.has("hours"):
				GameState.advance_time(params["hours"])
		_:
			push_warning("Unknown event: %s" % event_id)
	event_triggered.emit(event_id)
	event_completed.emit(event_id)
