class_name Intersection
extends Node3D
## Manages traffic control at a junction — either a traffic light or a stop sign.

signal light_changed(road_group: int, new_state: LightState)
signal zone_entered(body: Node3D)

enum LightState { GREEN, YELLOW, RED }
enum IntersectionType { NONE, TRAFFIC_LIGHT, STOP_SIGN }

@export var intersection_type: IntersectionType = IntersectionType.TRAFFIC_LIGHT
@export var green_duration: float = 15.0
@export var yellow_duration: float = 3.0
@export var detection_zone_size: float = 12.0  # meters, width/depth of detection area

var _light_states: Dictionary[int, LightState] = {}
var _cycle_timer: float = 0.0
var _current_green_group: int = 0
var _in_yellow: bool = false

# Visual nodes
var _light_meshes: Dictionary[int, Dictionary] = {}
var _cast_lights: Dictionary[int, OmniLight3D] = {}  # group_idx -> OmniLight3D casting color onto road


func _ready() -> void:
	_light_states[0] = LightState.GREEN
	_light_states[1] = LightState.RED

	match intersection_type:
		IntersectionType.TRAFFIC_LIGHT:
			_build_traffic_light_visuals()
			_update_light_visuals()
		IntersectionType.STOP_SIGN:
			_build_stop_sign_visuals()

	_build_detection_zone()


func _process(delta: float) -> void:
	if intersection_type != IntersectionType.TRAFFIC_LIGHT:
		return

	_cycle_timer += delta

	if _in_yellow:
		if _cycle_timer >= yellow_duration:
			_cycle_timer = 0.0
			_in_yellow = false
			_light_states[_current_green_group] = LightState.RED
			_current_green_group = 1 - _current_green_group
			_light_states[_current_green_group] = LightState.GREEN
			light_changed.emit(_current_green_group, LightState.GREEN)
			light_changed.emit(1 - _current_green_group, LightState.RED)
			_update_light_visuals()
	else:
		if _cycle_timer >= green_duration:
			_cycle_timer = 0.0
			_in_yellow = true
			_light_states[_current_green_group] = LightState.YELLOW
			light_changed.emit(_current_green_group, LightState.YELLOW)
			_update_light_visuals()


func get_light_state_for_group(group: int) -> LightState:
	if intersection_type == IntersectionType.STOP_SIGN:
		return LightState.RED
	if intersection_type == IntersectionType.NONE:
		return LightState.GREEN
	if _light_states.has(group):
		return _light_states[group] as LightState
	return LightState.RED


func get_light_state(road: RoadSegment) -> LightState:
	return get_light_state_for_group(road.road_group)


func is_stop_sign() -> bool:
	return intersection_type == IntersectionType.STOP_SIGN


func _build_detection_zone() -> void:
	var area := Area3D.new()
	area.name = "DetectionZone"
	area.collision_layer = 0
	area.collision_mask = 2  # Only detect player car (layer 2)
	area.monitorable = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(detection_zone_size, 2.0, detection_zone_size)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)  # Centered at car height
	area.add_child(shape)
	add_child(area)

	area.body_entered.connect(_on_zone_body_entered)


func _on_zone_body_entered(body: Node3D) -> void:
	zone_entered.emit(body)


func _build_stop_sign_visuals() -> void:
	# Place stop signs at two diagonal corners (matching traffic light pole pattern)
	var offsets: Array[Vector2] = [Vector2(6.0, 6.0), Vector2(-6.0, -6.0)]

	for offset in offsets:
		# Pole
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.06
		pole_mesh.bottom_radius = 0.06
		pole_mesh.height = 3.0
		pole.mesh = pole_mesh
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.3, 0.3, 0.3)
		pole.material_override = pole_mat
		pole.position = Vector3(offset.x, 1.5, offset.y)
		add_child(pole)

		# Sign face — flat red rectangle approximating octagonal stop sign
		var sign_face := MeshInstance3D.new()
		var sign_mesh := BoxMesh.new()
		sign_mesh.size = Vector3(0.65, 0.65, 0.05)
		sign_face.mesh = sign_mesh
		var sign_mat := StandardMaterial3D.new()
		sign_mat.albedo_color = Color(0.85, 0.1, 0.1)
		sign_mat.emission_enabled = true
		sign_mat.emission = Color(0.6, 0.05, 0.05)
		sign_mat.emission_energy_multiplier = 0.5
		sign_face.material_override = sign_mat
		sign_face.position = Vector3(offset.x, 3.2, offset.y)
		add_child(sign_face)

		# White border (slightly larger box behind the red face)
		var border := MeshInstance3D.new()
		var border_mesh := BoxMesh.new()
		border_mesh.size = Vector3(0.75, 0.75, 0.04)
		border.mesh = border_mesh
		var border_mat := StandardMaterial3D.new()
		border_mat.albedo_color = Color(0.9, 0.9, 0.9)
		border.material_override = border_mat
		border.position = Vector3(offset.x, 3.2, offset.y - 0.01 * signf(offset.y))
		add_child(border)


# -- Traffic light visual methods (enhanced with OmniLight3D for road illumination) --

func _build_traffic_light_visuals() -> void:
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.2, 0.2, 0.2)
	var housing_mat := StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.15, 0.15, 0.15)

	for group_idx in 2:
		# Per-group positions: pole base, arm end / housing, cast light
		var pole_pos: Vector3
		var housing_pos: Vector3
		var cast_pos: Vector3
		var arm_rotation: Vector3  # Euler rotation for the arm cylinder

		if group_idx == 0:
			# Group 0 controls horizontal road — pole on north side, arm extends south
			pole_pos = Vector3(5.0, 2.75, 8.5)
			housing_pos = Vector3(5.0, 5.0, 2.0)
			cast_pos = Vector3(5.0, 3.5, 2.0)
			arm_rotation = Vector3(PI / 2.0, 0.0, 0.0)  # Rotate to extend along Z
		else:
			# Group 1 controls vertical road — pole on west side, arm extends east
			pole_pos = Vector3(-8.5, 2.75, -5.0)
			housing_pos = Vector3(-2.0, 5.0, -5.0)
			cast_pos = Vector3(-2.0, 3.5, -5.0)
			arm_rotation = Vector3(0.0, 0.0, PI / 2.0)  # Rotate to extend along X

		# --- Vertical pole ---
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.08
		pole_mesh.bottom_radius = 0.08
		pole_mesh.height = 5.5
		pole.mesh = pole_mesh
		pole.material_override = dark_mat
		pole.position = pole_pos
		add_child(pole)

		# --- Horizontal arm (thin cylinder from pole top to above the road) ---
		var arm := MeshInstance3D.new()
		var arm_mesh := CylinderMesh.new()
		arm_mesh.top_radius = 0.05
		arm_mesh.bottom_radius = 0.05
		# Arm length = distance from pole top to housing along the extending axis
		var arm_length: float = abs(pole_pos.z - housing_pos.z) if group_idx == 0 else abs(pole_pos.x - housing_pos.x)
		arm_mesh.height = arm_length
		arm.mesh = arm_mesh
		arm.material_override = dark_mat
		# Center the arm between pole top and housing position
		var arm_center: Vector3
		if group_idx == 0:
			arm_center = Vector3(pole_pos.x, 5.5, (pole_pos.z + housing_pos.z) / 2.0)
		else:
			arm_center = Vector3((pole_pos.x + housing_pos.x) / 2.0, 5.5, pole_pos.z)
		arm.position = arm_center
		arm.rotation = arm_rotation
		add_child(arm)

		# --- Signal housing ---
		var housing := MeshInstance3D.new()
		var housing_mesh := BoxMesh.new()
		housing_mesh.size = Vector3(0.4, 1.2, 0.4)
		housing.mesh = housing_mesh
		housing.material_override = housing_mat
		housing.position = housing_pos
		add_child(housing)

		# --- Signal spheres ---
		var light_data: Dictionary = {}
		var light_configs: Array = [
			["red", 0.35, Color(1.0, 0.1, 0.1)],
			["yellow", 0.0, Color(1.0, 0.9, 0.1)],
			["green", -0.35, Color(0.1, 1.0, 0.2)],
		]
		for config in light_configs:
			var light_name: String = config[0]
			var y_off: float = config[1]
			var col: Color = config[2]

			var sphere := MeshInstance3D.new()
			var sphere_mesh := SphereMesh.new()
			sphere_mesh.radius = 0.12
			sphere_mesh.height = 0.24
			sphere.mesh = sphere_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.05, 0.05, 0.05)
			mat.emission_enabled = false
			sphere.material_override = mat
			sphere.position = Vector3(housing_pos.x, housing_pos.y + y_off, housing_pos.z)
			sphere.set_meta("emission_color", col)
			add_child(sphere)
			light_data[light_name] = sphere

		_light_meshes[group_idx] = light_data

		# --- Cast light (illuminates road below housing) ---
		var cast_light := OmniLight3D.new()
		cast_light.name = "CastLight_%d" % group_idx
		cast_light.position = cast_pos
		cast_light.light_color = Color(0.1, 1.0, 0.2)
		cast_light.omni_range = 8.0
		cast_light.light_energy = 0.6
		cast_light.shadow_enabled = false
		cast_light.distance_fade_enabled = true
		cast_light.distance_fade_begin = 40.0
		cast_light.distance_fade_length = 10.0
		add_child(cast_light)
		_cast_lights[group_idx] = cast_light


func _update_light_visuals() -> void:
	for group_idx in _light_meshes:
		var meshes: Dictionary = _light_meshes[group_idx]
		var state: LightState = _light_states.get(group_idx, LightState.RED) as LightState
		var active_name: String
		match state:
			LightState.GREEN:
				active_name = "green"
			LightState.YELLOW:
				active_name = "yellow"
			LightState.RED:
				active_name = "red"
			_:
				active_name = "red"

		for light_name: String in meshes:
			var sphere: MeshInstance3D = meshes[light_name]
			var mat: StandardMaterial3D = sphere.material_override as StandardMaterial3D
			if mat == null:
				continue
			if light_name == active_name:
				var col: Color = sphere.get_meta("emission_color") as Color
				mat.albedo_color = col
				mat.emission_enabled = true
				mat.emission = col
				mat.emission_energy_multiplier = 2.0
			else:
				mat.albedo_color = Color(0.05, 0.05, 0.05)
				mat.emission_enabled = false

		# Update the cast light color to match the active state
		if _cast_lights.has(group_idx):
			var cast_light: OmniLight3D = _cast_lights[group_idx]
			match state:
				LightState.GREEN:
					cast_light.light_color = Color(0.1, 1.0, 0.2)
				LightState.YELLOW:
					cast_light.light_color = Color(1.0, 0.9, 0.1)
				LightState.RED:
					cast_light.light_color = Color(1.0, 0.1, 0.1)
