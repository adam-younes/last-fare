extends Node3D
## Builds the test area at runtime: roads, intersections, buildings, sidewalks, lights.

const BLOCK_SIZE := 60.0
const ROAD_WIDTH := 14.0  # 2 lanes each direction at 3.5m
const HALF_ROAD := 7.0
const GRID_COLS := 3  # vertical roads
const GRID_ROWS := 3  # horizontal roads

var _road_network: RoadNetwork
var _road_mesh_gen: RoadMeshGenerator


func _ready() -> void:
	_road_network = $RoadNetwork
	_road_mesh_gen = RoadMeshGenerator.new()
	add_child(_road_mesh_gen)

	_build_roads()
	_build_intersections()
	_road_network.discover()
	_build_buildings()
	_build_sidewalks()
	_build_lighting()
	_build_ground()

	call_deferred("_generate_road_meshes")


func _generate_road_meshes() -> void:
	for road in _road_network.get_roads():
		_road_mesh_gen.generate_for_road(road)


func _get_h_z(row: int) -> float:
	return -row * (BLOCK_SIZE + ROAD_WIDTH)


func _get_v_x(col: int) -> float:
	return col * (BLOCK_SIZE + ROAD_WIDTH)


func _build_roads() -> void:
	var road_names_h: PackedStringArray = ["1st Street", "2nd Street", "3rd Street"]
	var road_names_v: PackedStringArray = ["Main Ave", "Oak Ave", "Elm Ave"]

	for row in GRID_ROWS:
		var z: float = _get_h_z(row)
		var road := RoadSegment.new()
		road.name = "H%d" % (row + 1)
		road.road_name = road_names_h[row]
		road.lane_count = 1
		road.road_group = 0
		road.curve = Curve3D.new()
		road.curve.add_point(Vector3(-HALF_ROAD, 0.0, z))
		road.curve.add_point(Vector3(_get_v_x(GRID_COLS - 1) + HALF_ROAD, 0.0, z))
		_road_network.add_child(road)

	for col in GRID_COLS:
		var x: float = _get_v_x(col)
		var road := RoadSegment.new()
		road.name = "V%d" % (col + 1)
		road.road_name = road_names_v[col]
		road.lane_count = 1
		road.road_group = 1
		road.curve = Curve3D.new()
		road.curve.add_point(Vector3(x, 0.0, HALF_ROAD))
		road.curve.add_point(Vector3(x, 0.0, _get_h_z(GRID_ROWS - 1) - HALF_ROAD))
		_road_network.add_child(road)


func _build_intersections() -> void:
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var x: float = _get_v_x(col)
			var z: float = _get_h_z(row)
			var intersection := Intersection.new()
			intersection.name = "Int_H%dV%d" % [row + 1, col + 1]
			intersection.position = Vector3(x, 0.0, z)

			# Corner intersections get stop signs, others get traffic lights
			var is_corner: bool = (row == 0 or row == GRID_ROWS - 1) and (col == 0 or col == GRID_COLS - 1)
			if is_corner:
				intersection.intersection_type = Intersection.IntersectionType.STOP_SIGN
			else:
				intersection.intersection_type = Intersection.IntersectionType.TRAFFIC_LIGHT
				intersection.green_duration = 12.0 + randf() * 6.0

			_road_network.add_child(intersection)


func _build_buildings() -> void:
	var buildings_node := Node3D.new()
	buildings_node.name = "Buildings"
	add_child(buildings_node)

	var block_colors: Array[Color] = [
		Color(0.25, 0.22, 0.2),
		Color(0.2, 0.22, 0.25),
		Color(0.22, 0.2, 0.22),
		Color(0.28, 0.25, 0.2),
		Color(0.2, 0.25, 0.22),
		Color(0.22, 0.22, 0.28),
	]

	var block_idx: int = 0
	for row in GRID_ROWS - 1:
		for col in GRID_COLS - 1:
			var min_x: float = _get_v_x(col) + HALF_ROAD + 1.5
			var max_x: float = _get_v_x(col + 1) - HALF_ROAD - 1.5
			var min_z: float = _get_h_z(row + 1) + HALF_ROAD + 1.5
			var max_z: float = _get_h_z(row) - HALF_ROAD - 1.5

			var center_x: float = (min_x + max_x) / 2.0
			var center_z: float = (min_z + max_z) / 2.0
			var block_w: float = max_x - min_x
			var block_d: float = max_z - min_z

			var num_buildings: int = randi_range(1, 3)
			for b in num_buildings:
				var height: float = randf_range(10.0, 30.0)
				var w: float = randf_range(block_w * 0.3, block_w * 0.8)
				var d: float = randf_range(block_d * 0.3, block_d * 0.8)
				var offset_x: float = randf_range(-block_w * 0.15, block_w * 0.15)
				var offset_z: float = randf_range(-block_d * 0.15, block_d * 0.15)

				var building: StaticBody3D = _create_building(
					Vector3(w, height, d),
					Vector3(center_x + offset_x, height / 2.0, center_z + offset_z),
					block_colors[block_idx % block_colors.size()]
				)
				buildings_node.add_child(building)

			block_idx += 1


func _create_building(bsize: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = bsize
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = bsize
	col_shape.shape = box_shape
	body.add_child(col_shape)

	return body


func _build_sidewalks() -> void:
	var sidewalks_node := Node3D.new()
	sidewalks_node.name = "Sidewalks"
	add_child(sidewalks_node)

	var curb_height: float = 0.15
	var sidewalk_width: float = 1.5

	# Horizontal road sidewalks — create segments with gaps at vertical road crossings
	for row in GRID_ROWS:
		var z: float = _get_h_z(row)
		for side in [-1, 1]:
			var sz: float = z + (HALF_ROAD + sidewalk_width / 2.0) * side
			var full_start: float = -HALF_ROAD - sidewalk_width
			var full_end: float = _get_v_x(GRID_COLS - 1) + HALF_ROAD + sidewalk_width

			var seg_start: float = full_start
			for col in GRID_COLS:
				var gap_start: float = _get_v_x(col) - HALF_ROAD
				var gap_end: float = _get_v_x(col) + HALF_ROAD
				if gap_start > seg_start:
					var seg_len: float = gap_start - seg_start
					var cx: float = seg_start + seg_len / 2.0
					_add_sidewalk_segment(sidewalks_node, Vector3(cx, curb_height / 2.0, sz), Vector3(seg_len, curb_height, sidewalk_width))
				seg_start = gap_end
			if full_end > seg_start:
				var seg_len: float = full_end - seg_start
				var cx: float = seg_start + seg_len / 2.0
				_add_sidewalk_segment(sidewalks_node, Vector3(cx, curb_height / 2.0, sz), Vector3(seg_len, curb_height, sidewalk_width))

	# Vertical road sidewalks — create segments with gaps at horizontal road crossings
	for col in GRID_COLS:
		var x: float = _get_v_x(col)
		for side in [-1, 1]:
			var sx: float = x + (HALF_ROAD + sidewalk_width / 2.0) * side
			var full_start: float = HALF_ROAD + sidewalk_width
			var full_end: float = _get_h_z(GRID_ROWS - 1) - HALF_ROAD - sidewalk_width

			var seg_start: float = full_start
			for row in GRID_ROWS:
				var gap_top: float = _get_h_z(row) + HALF_ROAD
				var gap_bottom: float = _get_h_z(row) - HALF_ROAD
				if gap_top < seg_start:
					var seg_len: float = seg_start - gap_top
					var cz: float = gap_top + seg_len / 2.0
					_add_sidewalk_segment(sidewalks_node, Vector3(sx, curb_height / 2.0, cz), Vector3(sidewalk_width, curb_height, seg_len))
				seg_start = gap_bottom
			if seg_start > full_end:
				var seg_len: float = seg_start - full_end
				var cz: float = full_end + seg_len / 2.0
				_add_sidewalk_segment(sidewalks_node, Vector3(sx, curb_height / 2.0, cz), Vector3(sidewalk_width, curb_height, seg_len))


func _add_sidewalk_segment(parent: Node3D, pos: Vector3, bsize: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = bsize
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.3)
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = bsize
	col_shape.shape = box_shape
	body.add_child(col_shape)

	parent.add_child(body)


func _build_lighting() -> void:
	var lighting_node := Node3D.new()
	lighting_node.name = "Lighting"
	add_child(lighting_node)

	for row in GRID_ROWS:
		for col in GRID_COLS:
			var x: float = _get_v_x(col)
			var z: float = _get_h_z(row)
			_add_street_light(lighting_node, Vector3(x + 8.0, 5.0, z + 8.0))
			_add_street_light(lighting_node, Vector3(x - 8.0, 5.0, z - 8.0))

	for row in GRID_ROWS:
		var z: float = _get_h_z(row)
		for col in GRID_COLS - 1:
			var mid_x: float = (_get_v_x(col) + _get_v_x(col + 1)) / 2.0
			_add_street_light(lighting_node, Vector3(mid_x, 5.0, z + 9.0))

	for col in GRID_COLS:
		var x: float = _get_v_x(col)
		for row in GRID_ROWS - 1:
			var mid_z: float = (_get_h_z(row) + _get_h_z(row + 1)) / 2.0
			_add_street_light(lighting_node, Vector3(x + 9.0, 5.0, mid_z))


func _add_street_light(parent: Node3D, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color(1.0, 0.85, 0.6)
	light.omni_range = 15.0
	light.light_energy = 0.8
	light.shadow_enabled = false
	parent.add_child(light)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = pos.y
	pole.mesh = pole_mesh
	pole.position = Vector3(pos.x, pos.y / 2.0, pos.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	pole.material_override = mat
	parent.add_child(pole)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)

	var col_shape := CollisionShape3D.new()
	var boundary := WorldBoundaryShape3D.new()
	col_shape.shape = boundary
	col_shape.position = Vector3(0, -0.05, 0)
	ground.add_child(col_shape)

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mesh_inst.mesh = plane
	mesh_inst.position = Vector3(_get_v_x(1), -0.05, _get_h_z(1))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.1, 0.06)
	mesh_inst.material_override = mat
	ground.add_child(mesh_inst)
