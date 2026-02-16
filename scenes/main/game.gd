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
var current_passenger_data: PassengerData = null
var ride_timer: float = 0.0

var _current_state: GamePhaseState = null
var _phase_states: Dictionary = {}
var _active_pickup_marker: PickupMarker = null
var _active_destination_marker: PickupMarker = null

@onready var car_interior: CharacterBody3D = $CarInterior
@onready var speedometer: Label = %Speedometer
@onready var rpm_meter: Label = %RPMMeter
@onready var gear_indicator: Label = %GearIndicator
@onready var gps: Control = $CarInterior/CarMesh/GPSScreen/SubViewport/GPS
@onready var phone: Control = %Phone
@onready var dialogue_box: Control = %DialogueBox
@onready var passenger_manager: Node = $PassengerManager
@onready var fade_overlay: ColorRect = %FadeOverlay
@onready var gps_screen_mesh: MeshInstance3D = $CarInterior/CarMesh/GPSScreen/ScreenMesh
@onready var road_network: RoadNetwork = $TestArea/RoadNetwork
@onready var traffic_manager: TrafficManager = $TrafficManager
@onready var pickup_detector: ProximityDetector = $PickupDetector
@onready var destination_detector: ProximityDetector = $DestinationDetector


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_gps_screen()
	_connect_signals()
	_register_phase_states()
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


func _register_phase_states() -> void:
	_phase_states[GamePhase.SHIFT_START] = PhaseShiftStart.new()
	_phase_states[GamePhase.WAITING_FOR_RIDE] = PhaseWaitingForRide.new()
	_phase_states[GamePhase.RIDE_OFFERED] = PhaseRideOffered.new()
	_phase_states[GamePhase.PICKING_UP] = PhasePickingUp.new()
	_phase_states[GamePhase.IN_RIDE] = PhaseInRide.new()
	_phase_states[GamePhase.DROPPING_OFF] = PhaseDroppingOff.new()
	_phase_states[GamePhase.BETWEEN_RIDES] = PhaseBetweenRides.new()
	_phase_states[GamePhase.ENDING] = PhaseEnding.new()
	for phase: GamePhase in _phase_states:
		var state: GamePhaseState = _phase_states[phase]
		state.game = self


func _process(delta: float) -> void:
	if _current_state:
		_current_state.process(delta)
	_update_speedometer()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("accept_ride") and current_phase == GamePhase.RIDE_OFFERED:
		accept_current_ride()
	elif event.is_action_pressed("refuse_ride") and current_phase == GamePhase.RIDE_OFFERED:
		refuse_current_ride()


func _update_speedometer() -> void:
	var mph: int = roundi(car_interior.get_speed_mph())
	speedometer.text = str(mph) + " MPH"
	var rpm: int = roundi(car_interior.get_rpm())
	rpm_meter.text = str(rpm) + " RPM"
	gear_indicator.text = "GEAR: " + car_interior.get_gear_string()


func _connect_signals() -> void:
	phone.ride_accepted.connect(_on_ride_accepted)
	phone.ride_refused.connect(_on_ride_refused)
	dialogue_box.dialogue_finished.connect(_on_dialogue_finished)
	destination_detector.target_reached.connect(_on_destination_reached)
	gps.destination_reached.connect(_on_gps_arrival)


func transition_to_phase(phase: GamePhase) -> void:
	if _current_state:
		_current_state.exit()
	current_phase = phase
	_current_state = _phase_states.get(phase)
	if _current_state:
		_current_state.enter()


func _start_game() -> void:
	GameState.start_shift()
	transition_to_phase(GamePhase.SHIFT_START)


# -- Public helpers for phase states --

func offer_next_ride() -> void:
	var next := passenger_manager.get_next_passenger() as PassengerData
	if next == null:
		transition_to_phase(GamePhase.ENDING)
		return
	current_passenger_data = next
	GameState.current_passenger_id = next.id
	phone.show_ride_request(next)
	transition_to_phase(GamePhase.RIDE_OFFERED)


func accept_current_ride() -> void:
	if current_passenger_data:
		phone.hide_ride_request()
		transition_to_phase(GamePhase.PICKING_UP)


func refuse_current_ride() -> void:
	if current_passenger_data:
		if not current_passenger_data.is_refusable:
			phone.show_notification("You cannot refuse this ride.")
			return
		GameState.refuse_ride(current_passenger_data.id)
		if not current_passenger_data.refuse_consequence.is_empty():
			EventManager.trigger(current_passenger_data.refuse_consequence)
		phone.hide_ride_request()
		transition_to_phase(GamePhase.WAITING_FOR_RIDE)


func start_passenger_dialogue() -> void:
	if current_passenger_data and current_passenger_data.dialogue_nodes.size() > 0:
		dialogue_box.start_dialogue(current_passenger_data.dialogue_nodes)


func spawn_pickup_marker(pos: Vector3) -> void:
	_active_pickup_marker = PickupMarker.new()
	_active_pickup_marker.marker_color = Color(0.2, 0.8, 0.2)
	add_child(_active_pickup_marker)
	_active_pickup_marker.global_position = pos


func remove_pickup_marker() -> void:
	if _active_pickup_marker:
		_active_pickup_marker.queue_free()
		_active_pickup_marker = null


func spawn_destination_marker(pos: Vector3) -> void:
	_active_destination_marker = PickupMarker.new()
	_active_destination_marker.marker_color = Color(0.3, 0.5, 1.0)
	add_child(_active_destination_marker)
	_active_destination_marker.global_position = pos


func remove_destination_marker() -> void:
	if _active_destination_marker:
		_active_destination_marker.queue_free()
		_active_destination_marker = null


func spawn_passenger_billboard() -> void:
	var billboard := PassengerBillboard.new()
	car_interior.seat_passenger(billboard)


func handle_ending() -> void:
	if GameState.has_flag("refused_all_strange"):
		phone.show_notification("You ended your shift early. Some things are better left unknown.")
	elif GameState.has_flag("followed_gps_home"):
		phone.show_notification("The app shows one final ride request. The pickup is your apartment.")
	else:
		phone.show_notification("Shift complete. You can go home now... if you remember the way.")
	if fade_overlay:
		var tween := create_tween()
		tween.tween_property(fade_overlay, "color:a", 1.0, 3.0)


# -- Signal callbacks --

func _on_ride_accepted(_passenger: PassengerData) -> void:
	accept_current_ride()


func _on_ride_refused(_passenger: PassengerData) -> void:
	refuse_current_ride()


func _on_dialogue_finished() -> void:
	pass


func _on_destination_reached() -> void:
	if current_phase == GamePhase.IN_RIDE:
		remove_destination_marker()
		transition_to_phase(GamePhase.DROPPING_OFF)


func _on_gps_arrival() -> void:
	pass
