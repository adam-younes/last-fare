class_name RoadNetwork
extends Node
## Manages all roads and intersections. Provides queries for AI, GPS, and passenger generation.


class LanePosition:
	var road: RoadSegment
	var lane: int
	var direction: int
	var position: Vector3
	var t: float

	func _init(p_road: RoadSegment = null, p_lane: int = 0, p_direction: int = 1, p_position: Vector3 = Vector3.ZERO, p_t: float = 0.0) -> void:
		road = p_road
		lane = p_lane
		direction = p_direction
		position = p_position
		t = p_t


class RoadPosition:
	var road: RoadSegment
	var position: Vector3
	var t: float
	var direction: int

	func _init(p_road: RoadSegment = null, p_position: Vector3 = Vector3.ZERO, p_t: float = 0.0, p_direction: int = 1) -> void:
		road = p_road
		position = p_position
		t = p_t
		direction = p_direction


var _roads: Array[RoadSegment] = []
var _intersections: Array[Intersection] = []

# Maps RoadSegment -> { "start": Intersection or null, "end": Intersection or null }
var _road_endpoints: Dictionary = {}

# Maps Intersection -> Array of { "road": RoadSegment, "enters_forward": bool }
# enters_forward=true means a vehicle entering from this intersection travels direction=1
var _intersection_connections: Dictionary = {}


func discover() -> void:
	_roads.clear()
	_intersections.clear()
	_discover_children(self)
	_build_adjacency()


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


func get_nearest_lane_position(world_pos: Vector3) -> LanePosition:
	var best := LanePosition.new()
	var best_dist: float = INF

	for road in _roads:
		for dir in [1, -1]:
			for lane_idx in road.lane_count:
				var points: PackedVector3Array = road.get_lane_points(lane_idx, dir)
				for i in points.size():
					var dist: float = world_pos.distance_to(points[i])
					if dist < best_dist:
						best_dist = dist
						best.road = road
						best.lane = lane_idx
						best.direction = dir
						best.position = points[i]
						best.t = float(i) / float(maxi(points.size() - 1, 1))
	return best


func get_random_road_position() -> RoadPosition:
	if _roads.is_empty():
		return RoadPosition.new()

	var road: RoadSegment = _roads.pick_random()
	var t: float = randf()
	var baked_length: float = road.curve.get_baked_length()
	var pos: Vector3 = road.curve.sample_baked(t * baked_length)
	var dir: int = 1 if randf() > 0.5 else -1
	var next_t: float = minf(t + 0.01, 1.0)
	var next_pos: Vector3 = road.curve.sample_baked(next_t * baked_length)
	var forward: Vector3 = next_pos - pos
	if forward.length() > 0.001:
		var right: Vector3 = forward.normalized().cross(Vector3.UP).normalized()
		var offset: float = 0.5 * road.lane_width * dir
		pos += right * offset

	var world_pos: Vector3 = road.global_transform * pos
	return RoadPosition.new(road, world_pos, t, dir)


func get_intersection_at(world_pos: Vector3, radius: float = 5.0) -> Intersection:
	for intersection in _intersections:
		if intersection.global_position.distance_to(world_pos) < radius:
			return intersection
	return null


const ENDPOINT_THRESHOLD := 10.0  # meters — match existing proximity checks


func _build_adjacency() -> void:
	_road_endpoints.clear()
	_intersection_connections.clear()

	for road in _roads:
		var curve_start: Vector3 = road.global_transform * road.curve.get_point_position(0)
		var curve_end: Vector3 = road.global_transform * road.curve.get_point_position(road.curve.point_count - 1)

		var start_intersection: Intersection = null
		var end_intersection: Intersection = null

		for intersection in _intersections:
			var ipos: Vector3 = intersection.global_position
			if curve_start.distance_to(ipos) < ENDPOINT_THRESHOLD:
				start_intersection = intersection
			if curve_end.distance_to(ipos) < ENDPOINT_THRESHOLD:
				end_intersection = intersection

		_road_endpoints[road] = {
			"start": start_intersection,
			"end": end_intersection,
		}

		# Register road with each intersection it touches
		if start_intersection:
			if not _intersection_connections.has(start_intersection):
				_intersection_connections[start_intersection] = []
			_intersection_connections[start_intersection].append({
				"road": road,
				"enters_forward": true,  # entering from curve start -> travel direction=1
			})

		if end_intersection:
			if not _intersection_connections.has(end_intersection):
				_intersection_connections[end_intersection] = []
			_intersection_connections[end_intersection].append({
				"road": road,
				"enters_forward": false,  # entering from curve end -> travel direction=-1
			})


## Returns the intersection at the destination end of a road for a given travel direction.
## direction=1 -> vehicle heading toward curve end; direction=-1 -> heading toward curve start.
func get_road_end_intersection(road: RoadSegment, direction: int) -> Intersection:
	var endpoints: Dictionary = _road_endpoints.get(road, {})
	if endpoints.is_empty():
		return null
	if direction == 1:
		return endpoints["end"] as Intersection
	else:
		return endpoints["start"] as Intersection


## Returns roads connected to an intersection, excluding a given road.
## Each entry: { "road": RoadSegment, "direction": int }
## direction is the travel direction for a vehicle entering from this intersection.
func get_connected_roads(intersection: Intersection, exclude: RoadSegment = null) -> Array[Dictionary]:
	var connections: Array = _intersection_connections.get(intersection, [])
	var result: Array[Dictionary] = []
	for conn: Dictionary in connections:
		var road: RoadSegment = conn["road"] as RoadSegment
		if road == exclude:
			continue
		var dir: int = 1 if conn["enters_forward"] else -1
		result.append({ "road": road, "direction": dir })
	return result


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
