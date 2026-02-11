extends Control
## Phone UI — ride requests, messages from the app, and notifications.

signal ride_accepted(passenger_data: PassengerData)
signal ride_refused(passenger_data: PassengerData)

var _current_offer: PassengerData = null
var _notification_queue: Array[Dictionary] = []

@onready var ride_request_panel: PanelContainer = %RideRequestPanel
@onready var rider_name_label: Label = %RiderNameLabel
@onready var pickup_label: Label = %PickupLabel
@onready var destination_label: Label = %PhoneDestLabel
@onready var accept_button: Button = %AcceptButton
@onready var refuse_button: Button = %RefuseButton
@onready var notification_label: Label = %NotificationLabel
@onready var shift_info_label: Label = %ShiftInfoLabel


func _ready() -> void:
	add_to_group("phone")
	ride_request_panel.visible = false
	notification_label.text = ""
	accept_button.pressed.connect(_on_accept)
	refuse_button.pressed.connect(_on_refuse)
	_update_shift_info()


func _process(_delta: float) -> void:
	_update_shift_info()


func show_ride_request(passenger: PassengerData) -> void:
	_current_offer = passenger
	rider_name_label.text = passenger.display_name
	pickup_label.text = passenger.pickup_location
	destination_label.text = passenger.destination

	refuse_button.visible = passenger.is_refusable
	ride_request_panel.visible = true


func hide_ride_request() -> void:
	ride_request_panel.visible = false
	_current_offer = null


func show_notification(text: String, duration: float = 3.0) -> void:
	notification_label.text = text
	notification_label.visible = true
	await get_tree().create_timer(duration).timeout
	notification_label.visible = false


func _on_accept() -> void:
	if _current_offer:
		ride_accepted.emit(_current_offer)
		hide_ride_request()


func _on_refuse() -> void:
	if _current_offer:
		ride_refused.emit(_current_offer)
		hide_ride_request()


func _update_shift_info() -> void:
	var rides_done := GameState.current_ride_number
	var rides_total := GameState.total_rides_required
	var time_str := GameState.get_display_time()
	shift_info_label.text = "Rides: %d/%d | %s" % [rides_done, rides_total, time_str]
