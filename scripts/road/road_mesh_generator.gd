class_name RoadMeshGenerator
extends Node3D
## Generates road surface meshes, lane markings, and collision from RoadSegment paths.

const ROAD_COLOR := Color(0.18, 0.18, 0.18)
const SHOULDER_WIDTH := 1.0
const LANE_LINE_WIDTH := 0.12
const LANE_LINE_Y_OFFSET := 0.02
const CENTER_LINE_COLOR := Color(0.7, 0.6, 0.1)  # yellow
const LANE_LINE_COLOR := Color(0.8, 0.8, 0.8)     # white
const DASH_LENGTH := 3.0
const GAP_LENGTH := 3.0
const SAMPLE_COUNT := 40


func generate_for_road(road: RoadSegment) -> void:
	var baked_length: float = road.curve.get_baked_length()
	if baked_length < 0.1:
		return

	var half_width: float = road.get_total_width() / 2.0 + SHOULDER_WIDTH

	# Build road surface mesh
	var road_mesh: MeshInstance3D = _build_road_surface(road, half_width)
	road.add_child(road_mesh)

	# Build lane markings
	_build_lane_markings(road)


func _build_road_surface(road: RoadSegment, half_width: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var baked_length: float = road.curve.get_baked_length()
	var points: Array[Dictionary] = []

	for i in SAMPLE_COUNT:
		var t: float = float(i) / float(SAMPLE_COUNT - 1)
		var pos: Vector3 = road.curve.sample_baked(t * baked_length)
		var next_t: float = minf(t + 0.005, 1.0)
		var next_pos: Vector3 = road.curve.sample_baked(next_t * baked_length)
		var forward: Vector3 = next_pos - pos
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
		var right: Vector3 = forward.normalized().cross(Vector3.UP).normalized()
		points.append({ "pos": pos, "right": right })

	# Generate quads between sample points
	for i in points.size() - 1:
		var p0: Dictionary = points[i]
		var p1: Dictionary = points[i + 1]

		var p0_pos: Vector3 = p0["pos"]
		var p0_right: Vector3 = p0["right"]
		var p1_pos: Vector3 = p1["pos"]
		var p1_right: Vector3 = p1["right"]

		var bl: Vector3 = p0_pos - p0_right * half_width
		var br: Vector3 = p0_pos + p0_right * half_width
		var tl: Vector3 = p1_pos - p1_right * half_width
		var tr: Vector3 = p1_pos + p1_right * half_width

		# Slight Y offset to sit above ground
		bl.y += 0.01
		br.y += 0.01
		tl.y += 0.01
		tr.y += 0.01

		st.set_normal(Vector3.UP)

		st.add_vertex(bl)
		st.add_vertex(tl)
		st.add_vertex(br)

		st.add_vertex(br)
		st.add_vertex(tl)
		st.add_vertex(tr)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROAD_COLOR
	mesh_instance.material_override = mat

	return mesh_instance


func _build_lane_markings(road: RoadSegment) -> void:
	# Center line (solid yellow)
	_build_line_strip(road, 0.0, CENTER_LINE_COLOR, true)

	# Lane dividers (dashed white) — only if more than 1 lane per direction
	if road.lane_count > 1:
		for lane_idx in range(1, road.lane_count):
			var offset: float = lane_idx * road.lane_width
			_build_line_strip(road, offset, LANE_LINE_COLOR, false)
			_build_line_strip(road, -offset, LANE_LINE_COLOR, false)


func _build_line_strip(road: RoadSegment, lateral_offset: float, color: Color, solid: bool) -> void:
	var baked_length: float = road.curve.get_baked_length()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var fine_count: int = SAMPLE_COUNT * 3
	var cumulative_dist: float = 0.0
	var prev_pos: Vector3 = Vector3.ZERO
	var in_dash: bool = true

	var prev_center: Vector3 = Vector3.ZERO
	var prev_right: Vector3 = Vector3.RIGHT
	var has_prev: bool = false

	for i in fine_count:
		var t: float = float(i) / float(fine_count - 1)
		var pos: Vector3 = road.curve.sample_baked(t * baked_length)
		var next_t: float = minf(t + 0.003, 1.0)
		var next_pos: Vector3 = road.curve.sample_baked(next_t * baked_length)
		var forward: Vector3 = next_pos - pos
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
		var right: Vector3 = forward.normalized().cross(Vector3.UP).normalized()

		var center: Vector3 = pos + right * lateral_offset
		center.y += LANE_LINE_Y_OFFSET

		if i > 0:
			cumulative_dist += pos.distance_to(prev_pos)

		if not solid:
			var cycle: float = fmod(cumulative_dist, DASH_LENGTH + GAP_LENGTH)
			in_dash = cycle < DASH_LENGTH

		prev_pos = pos

		if has_prev and in_dash:
			var hw: float = LANE_LINE_WIDTH / 2.0
			var bl: Vector3 = prev_center - prev_right * hw
			var br: Vector3 = prev_center + prev_right * hw
			var tl: Vector3 = center - right * hw
			var tr: Vector3 = center + right * hw

			st.set_normal(Vector3.UP)
			st.add_vertex(bl)
			st.add_vertex(tl)
			st.add_vertex(br)
			st.add_vertex(br)
			st.add_vertex(tl)
			st.add_vertex(tr)

		prev_center = center
		prev_right = right
		has_prev = true

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.3
	mesh_instance.material_override = mat

	road.add_child(mesh_instance)
