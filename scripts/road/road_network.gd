class_name RoadNetwork
extends Node
## Manages all roads and intersections. Provides queries for AI, GPS, and passenger generation.

var _roads: Array[RoadSegment] = []
var _intersections: Array[Intersection] = []


func discover() -> void:
	_roads.clear()
	_intersections.clear()
	_discover_children(self)


func _discover_children(node: Node) -> void:
	for child in node.get_children():
		if child is RoadSegment:
			_roads.append(child)
		elif child is Intersection:
			_intersections.append(child)
		_discover_children(child)


func get_roads() -> Array[RoadSegment]:
	return _roads


func get_intersections() -> Array[Intersection]:
	return _intersections


func get_nearest_road(world_pos: Vector3) -> RoadSegment:
	var best_road: RoadSegment = null
	var best_dist: float = INF
	for road in _roads:
		var closest: Vector3 = _closest_point_on_road(road, world_pos)
		var dist: float = world_pos.distance_to(closest)
		if dist < best_dist:
			best_dist = dist
			best_road = road
	return best_road


func get_nearest_lane_position(world_pos: Vector3) -> Dictionary:
	var best: Dictionary = { "road": null, "lane": 0, "direction": 1, "position": Vector3.ZERO, "t": 0.0 }
	var best_dist: float = INF

	for road in _roads:
		for dir in [1, -1]:
			for lane_idx in road.lane_count:
				var points: PackedVector3Array = road.get_lane_points(lane_idx, dir)
				for i in points.size():
					var dist: float = world_pos.distance_to(points[i])
					if dist < best_dist:
						best_dist = dist
						best["road"] = road
						best["lane"] = lane_idx
						best["direction"] = dir
						best["position"] = points[i]
						best["t"] = float(i) / float(maxi(points.size() - 1, 1))
	return best


func get_random_road_position() -> Dictionary:
	if _roads.is_empty():
		return { "road": null, "position": Vector3.ZERO }

	var road: RoadSegment = _roads.pick_random()
	var t: float = randf()
	var baked_length: float = road.curve.get_baked_length()
	var pos: Vector3 = road.curve.sample_baked(t * baked_length)
	# Offset to a random lane side
	var dir: int = 1 if randf() > 0.5 else -1
	var next_t: float = minf(t + 0.01, 1.0)
	var next_pos: Vector3 = road.curve.sample_baked(next_t * baked_length)
	var forward: Vector3 = next_pos - pos
	if forward.length() > 0.001:
		var right: Vector3 = forward.normalized().cross(Vector3.UP).normalized()
		var offset: float = 0.5 * road.lane_width * dir
		pos += right * offset

	var world_pos: Vector3 = road.global_transform * pos
	return { "road": road, "position": world_pos, "t": t, "direction": dir }


func get_intersection_at(world_pos: Vector3, radius: float = 5.0) -> Intersection:
	for intersection in _intersections:
		if intersection.global_position.distance_to(world_pos) < radius:
			return intersection
	return null


func _closest_point_on_road(road: RoadSegment, world_pos: Vector3) -> Vector3:
	var baked_length: float = road.curve.get_baked_length()
	if baked_length < 0.01:
		return road.global_position

	var best_pos: Vector3 = road.global_position
	var best_dist: float = INF
	var steps: int = 20
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var p: Vector3 = road.global_transform * road.curve.sample_baked(t * baked_length)
		var d: float = world_pos.distance_to(p)
		if d < best_dist:
			best_dist = d
			best_pos = p
	return best_pos
