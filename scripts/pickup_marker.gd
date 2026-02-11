class_name PickupMarker
extends Node3D
## Visual indicator at pickup/destination locations — glowing ground circle.

@export var marker_color: Color = Color(0.2, 0.8, 0.2)


func _ready() -> void:
	var circle := MeshInstance3D.new()
	var circle_mesh := CylinderMesh.new()
	circle_mesh.top_radius = 2.0
	circle_mesh.bottom_radius = 2.0
	circle_mesh.height = 0.05
	circle.mesh = circle_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = marker_color
	mat.emission_enabled = true
	mat.emission = marker_color
	mat.emission_energy_multiplier = 0.5
	circle.material_override = mat
	add_child(circle)
