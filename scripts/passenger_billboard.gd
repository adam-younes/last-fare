class_name PassengerBillboard
extends MeshInstance3D
## Black billboard quad representing a passenger in the car.


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 1.5)
	mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.02)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material_override = mat
