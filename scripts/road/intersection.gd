class_name Intersection
extends Node3D
## Manages traffic light state for connected roads at a junction.

signal light_changed(road_group: int, new_state: LightState)

enum LightState { GREEN, YELLOW, RED }

@export var connected_roads: Array[NodePath] = []
@export var has_traffic_light: bool = true
@export var green_duration: float = 15.0
@export var yellow_duration: float = 3.0

var _light_states: Dictionary = {}  # int group -> LightState
var _cycle_timer: float = 0.0
var _current_green_group: int = 0
var _in_yellow: bool = false

# Visual nodes
var _light_meshes: Dictionary = {}  # int group -> { green: MeshInstance3D, yellow: MeshInstance3D, red: MeshInstance3D }


func _ready() -> void:
	_light_states[0] = LightState.GREEN
	_light_states[1] = LightState.RED

	if has_traffic_light:
		_build_traffic_light_visuals()
		_update_light_visuals()


func _process(delta: float) -> void:
	if not has_traffic_light:
		return

	_cycle_timer += delta

	if _in_yellow:
		if _cycle_timer >= yellow_duration:
			_cycle_timer = 0.0
			_in_yellow = false
			# Switch: yellow group goes red, other goes green
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
	if _light_states.has(group):
		return _light_states[group] as LightState
	return LightState.RED


func get_light_state(road: RoadSegment) -> LightState:
	return get_light_state_for_group(road.road_group)


func _build_traffic_light_visuals() -> void:
	for group_idx in 2:
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.08
		pole_mesh.bottom_radius = 0.08
		pole_mesh.height = 4.0
		pole.mesh = pole_mesh
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.2, 0.2, 0.2)
		pole.material_override = pole_mat
		var offset_x: float = 6.0 if group_idx == 0 else -6.0
		var offset_z: float = 6.0 if group_idx == 0 else -6.0
		pole.position = Vector3(offset_x, 2.0, offset_z)
		add_child(pole)

		# Housing box
		var housing := MeshInstance3D.new()
		var housing_mesh := BoxMesh.new()
		housing_mesh.size = Vector3(0.4, 1.2, 0.4)
		housing.mesh = housing_mesh
		var housing_mat := StandardMaterial3D.new()
		housing_mat.albedo_color = Color(0.15, 0.15, 0.15)
		housing.material_override = housing_mat
		housing.position = Vector3(offset_x, 4.3, offset_z)
		add_child(housing)

		# Light spheres (top=red, middle=yellow, bottom=green)
		var light_data: Dictionary = {}
		var light_configs: Array[Array] = [
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
			sphere.position = Vector3(offset_x, 4.3 + y_off, offset_z)
			sphere.set_meta("emission_color", col)
			add_child(sphere)
			light_data[light_name] = sphere

		_light_meshes[group_idx] = light_data


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

		for light_name in meshes:
			var sphere: MeshInstance3D = meshes[light_name]
			var mat: StandardMaterial3D = sphere.material_override as StandardMaterial3D
			if light_name == active_name:
				var col: Color = sphere.get_meta("emission_color") as Color
				mat.albedo_color = col
				mat.emission_enabled = true
				mat.emission = col
				mat.emission_energy_multiplier = 2.0
			else:
				mat.albedo_color = Color(0.05, 0.05, 0.05)
				mat.emission_enabled = false
