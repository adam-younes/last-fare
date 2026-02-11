extends Node
## Root game scene — manages the ride loop and game flow.

enum GamePhase {
	TITLE,
	SHIFT_START,
	WAITING_FOR_RIDE,
	RIDE_OFFERED,
	PICKING_UP,
	IN_RIDE,
	DROPPING_OFF,
	BETWEEN_RIDES,
	ENDING,
}

var current_phase: GamePhase = GamePhase.TITLE
var _current_passenger_data: PassengerData = null
var _ride_timer: float = 0.0
var _active_pickup_marker: PickupMarker = null
var _active_destination_marker: PickupMarker = null

@onready var car_interior: CharacterBody3D = $CarInterior
@onready var gps: Control = $CarInterior/CarMesh/GPSScreen/SubViewport/GPS
@onready var phone: Control = $UILayer/Phone
@onready var dialogue_box: Control = $UILayer/DialogueBox
@onready var passenger_manager: Node = $PassengerManager
@onready var fade_overlay: ColorRect = $UILayer/FadeOverlay
@onready var gps_screen_mesh: MeshInstance3D = $CarInterior/CarMesh/GPSScreen/ScreenMesh
@onready var road_network: RoadNetwork = $TestArea/RoadNetwork
@onready var traffic_manager: TrafficManager = $TrafficManager
@onready var pickup_detector: ProximityDetector = $PickupDetector
@onready var destination_detector: ProximityDetector = $DestinationDetector


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_gps_screen()
	_connect_signals()
	traffic_manager.initialize(road_network, car_interior)
	passenger_manager.initialize(road_network)
	_start_game()


func _setup_gps_screen() -> void:
	var vp: SubViewport = $CarInterior/CarMesh/GPSScreen/SubViewport
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.6
	var vp_tex := vp.get_texture()
	mat.albedo_texture = vp_tex
	mat.emission_texture = vp_tex
	gps_screen_mesh.material_override = mat


func _process(delta: float) -> void:
	match current_phase:
		GamePhase.IN_RIDE:
			_ride_timer += delta
			GameState.advance_time(delta * 0.033)
		GamePhase.BETWEEN_RIDES:
			GameState.advance_time(delta * 0.05)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("accept_ride") and current_phase == GamePhase.RIDE_OFFERED:
		_accept_current_ride()
	elif event.is_action_pressed("refuse_ride") and current_phase == GamePhase.RIDE_OFFERED:
		_refuse_current_ride()


func _connect_signals() -> void:
	phone.ride_accepted.connect(_on_ride_accepted)
	phone.ride_refused.connect(_on_ride_refused)
	dialogue_box.dialogue_finished.connect(_on_dialogue_finished)
	destination_detector.target_reached.connect(_on_destination_reached)
	gps.destination_reached.connect(_on_gps_arrival)


func _start_game() -> void:
	GameState.start_shift()
	_transition_to(GamePhase.SHIFT_START)


func _transition_to(phase: GamePhase) -> void:
	current_phase = phase
	match phase:
		GamePhase.SHIFT_START:
			phone.show_notification("Shift started. Complete all rides to end your shift.")
			await get_tree().create_timer(2.0).timeout
			_transition_to(GamePhase.WAITING_FOR_RIDE)

		GamePhase.WAITING_FOR_RIDE:
			GameState.set_shift_state(GameState.ShiftState.WAITING_FOR_RIDE)
			await get_tree().create_timer(1.5).timeout
			_offer_next_ride()

		GamePhase.RIDE_OFFERED:
			GameState.set_shift_state(GameState.ShiftState.RIDE_OFFERED)

		GamePhase.PICKING_UP:
			GameState.set_shift_state(GameState.ShiftState.PICKING_UP)
			var pickup_pos: Vector3 = _current_passenger_data.pickup_world_position
			_spawn_pickup_marker(pickup_pos)
			pickup_detector.set_target(pickup_pos)
			phone.show_notification("Drive to pickup: %s" % _current_passenger_data.pickup_location)
			gps.set_destination_position(_current_passenger_data.pickup_location, pickup_pos)
			# Wait for player to arrive
			await pickup_detector.target_reached
			_remove_pickup_marker()
			# Passenger boards
			_spawn_passenger_billboard()
			phone.show_notification("%s has entered the vehicle." % _current_passenger_data.display_name)
			await get_tree().create_timer(1.0).timeout
			_transition_to(GamePhase.IN_RIDE)

		GamePhase.IN_RIDE:
			GameState.set_shift_state(GameState.ShiftState.IN_RIDE)
			_ride_timer = 0.0
			# Place destination marker and detector
			var dest_pos: Vector3 = _current_passenger_data.destination_world_position
			_spawn_destination_marker(dest_pos)
			destination_detector.set_target(dest_pos)
			# GPS shows direction to destination
			gps.set_destination_position(_current_passenger_data.destination, dest_pos)

			if not _current_passenger_data.destination_exists:
				await get_tree().create_timer(5.0).timeout
				gps.set_state(gps.GPSState.GLITCHING)
				await get_tree().create_timer(2.0).timeout
				gps.set_state(gps.GPSState.NO_SIGNAL, {"message": "Destination not found"})

			if _current_passenger_data.ambient_override >= 0:
				AudioManager.set_ambience(_current_passenger_data.ambient_override as AudioManager.AmbienceState)

			_start_passenger_dialogue()

			if not _current_passenger_data.triggers_event.is_empty():
				EventManager.trigger(_current_passenger_data.triggers_event)

		GamePhase.DROPPING_OFF:
			GameState.set_shift_state(GameState.ShiftState.DROPPING_OFF)
			gps.arrive()

			for flag in _current_passenger_data.sets_flags:
				GameState.set_flag(flag)

			var is_narrative: bool = not _current_passenger_data.is_procedural
			GameState.complete_ride(_current_passenger_data.id, is_narrative)
			car_interior.remove_passenger()
			phone.show_notification("Ride complete.")

			GameState.advance_time(randf_range(0.75, 1.5))

			await get_tree().create_timer(2.0).timeout

			if GameState.is_shift_complete():
				_transition_to(GamePhase.ENDING)
			else:
				_transition_to(GamePhase.BETWEEN_RIDES)

		GamePhase.BETWEEN_RIDES:
			GameState.set_shift_state(GameState.ShiftState.BETWEEN_RIDES)
			await get_tree().create_timer(3.0).timeout
			_transition_to(GamePhase.WAITING_FOR_RIDE)

		GamePhase.ENDING:
			GameState.set_shift_state(GameState.ShiftState.SHIFT_ENDING)
			_handle_ending()


func _offer_next_ride() -> void:
	var next := passenger_manager.get_next_passenger() as PassengerData
	if next == null:
		_transition_to(GamePhase.ENDING)
		return

	_current_passenger_data = next
	GameState.current_passenger_id = next.id
	phone.show_ride_request(next)
	_transition_to(GamePhase.RIDE_OFFERED)


func _accept_current_ride() -> void:
	if _current_passenger_data:
		phone.hide_ride_request()
		_transition_to(GamePhase.PICKING_UP)


func _refuse_current_ride() -> void:
	if _current_passenger_data:
		if not _current_passenger_data.is_refusable:
			phone.show_notification("You cannot refuse this ride.")
			return

		GameState.refuse_ride(_current_passenger_data.id)

		if not _current_passenger_data.refuse_consequence.is_empty():
			EventManager.trigger(_current_passenger_data.refuse_consequence)

		phone.hide_ride_request()
		_transition_to(GamePhase.WAITING_FOR_RIDE)


func _on_ride_accepted(passenger: PassengerData) -> void:
	_accept_current_ride()


func _on_ride_refused(passenger: PassengerData) -> void:
	_refuse_current_ride()


func _start_passenger_dialogue() -> void:
	if _current_passenger_data and _current_passenger_data.dialogue_nodes.size() > 0:
		dialogue_box.start_dialogue(_current_passenger_data.dialogue_nodes)


func _on_dialogue_finished() -> void:
	pass


func _on_destination_reached() -> void:
	if current_phase == GamePhase.IN_RIDE:
		_remove_destination_marker()
		_transition_to(GamePhase.DROPPING_OFF)


func _on_gps_arrival() -> void:
	pass


# -- Marker helpers --

func _spawn_pickup_marker(pos: Vector3) -> void:
	_active_pickup_marker = PickupMarker.new()
	_active_pickup_marker.marker_color = Color(0.2, 0.8, 0.2)
	add_child(_active_pickup_marker)
	_active_pickup_marker.global_position = pos


func _remove_pickup_marker() -> void:
	if _active_pickup_marker:
		_active_pickup_marker.queue_free()
		_active_pickup_marker = null


func _spawn_destination_marker(pos: Vector3) -> void:
	_active_destination_marker = PickupMarker.new()
	_active_destination_marker.marker_color = Color(0.3, 0.5, 1.0)
	add_child(_active_destination_marker)
	_active_destination_marker.global_position = pos


func _remove_destination_marker() -> void:
	if _active_destination_marker:
		_active_destination_marker.queue_free()
		_active_destination_marker = null


func _spawn_passenger_billboard() -> void:
	var billboard := PassengerBillboard.new()
	car_interior.seat_passenger(billboard)


# -- Ending --

func _handle_ending() -> void:
	if GameState.has_flag("refused_all_strange"):
		phone.show_notification("You ended your shift early. Some things are better left unknown.")
	elif GameState.has_flag("followed_gps_home"):
		phone.show_notification("The app shows one final ride request. The pickup is your apartment.")
	else:
		phone.show_notification("Shift complete. You can go home now... if you remember the way.")

	if fade_overlay:
		var tween := create_tween()
		tween.tween_property(fade_overlay, "color:a", 1.0, 3.0)
