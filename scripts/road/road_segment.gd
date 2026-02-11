class_name RoadSegment
extends Path3D
## A road segment defined by a Path3D curve with lane metadata.

@export var lane_count: int = 1          # lanes per direction
@export var lane_width: float = 3.5      # meters
@export var speed_limit: float = 13.4    # m/s (~30 mph)
@export var road_name: String = ""
@export var road_group: int = 0          # traffic light group (0 or 1)


func get_lane_points(lane_index: int, direction: int, point_count: int = 20) -> PackedVector3Array:
	var points: PackedVector3Array = []
	var offset: float = (lane_index + 0.5) * lane_width * direction
	var baked_length: float = curve.get_baked_length()
	if baked_length < 0.01:
		return points

	for i in point_count:
		var t: float = float(i) / float(point_count - 1)
		var pos: Vector3 = curve.sample_baked(t * baked_length)
		var next_t: float = minf(t + 0.01, 1.0)
		var next_pos: Vector3 = curve.sample_baked(next_t * baked_length)
		var forward_vec: Vector3 = next_pos - pos
		if forward_vec.length() < 0.001:
			if points.size() > 0:
				points.append(points[points.size() - 1])
			continue
		var right: Vector3 = forward_vec.normalized().cross(Vector3.UP).normalized()
		points.append(global_transform * (pos + right * offset))

	# Reverse for oncoming direction
	if direction == -1:
		points.reverse()

	return points


func get_total_width() -> float:
	return lane_count * 2.0 * lane_width


func get_length() -> float:
	return curve.get_baked_length()
