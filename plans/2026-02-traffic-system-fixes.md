# Traffic System & AI Driving Fixes — Implementation Plan

## Overview

Fix the highest-priority technical, optimization, and scalability issues in the traffic and AI driving systems. The core problems: intersection connectivity is broken (roads are never wired to intersections), traffic light checks ignore vehicle direction, collision layers are unconfigured, vehicle physics have a gravity bug, and 48 dynamic lights create unnecessary GPU cost.

## Current State Analysis

### Intersection Connectivity (T-1, T-2, O-2)
- `Intersection.connected_roads` (`intersection.gd:9`) is an `Array[NodePath]` that is **never populated** — `test_area.gd:77-82` creates intersections but never sets this field.
- `TrafficVehicle._try_next_road()` (`traffic_vehicle.gd:185-224`) **ignores** `connected_roads` entirely. Instead it iterates ALL roads in the network, computing `global_transform * curve.get_point_position()` twice per road and checking proximity to the intersection. This is O(total_roads) instead of O(1) and can select geometrically-close but logically-disconnected roads.
- `RoadNetwork` has no concept of road-to-intersection adjacency — it stores flat lists of roads and intersections with no relational structure.

### Traffic Light Direction (T-4, O-1)
- `_should_stop_for_light()` (`traffic_vehicle.gd:166-182`) calls `get_intersection_at(current_pos, 15.0)`, which linearly scans ALL intersections. It finds any intersection within 15m regardless of whether the vehicle is approaching or departing it.
- A vehicle that just passed through an intersection and is 4-14m past it will still see it, check the light, and potentially stop mid-road if the light has since turned red.

### Collision Layers (T-5)
- The traffic vehicle scene (`traffic_vehicle.tscn`) sets no collision layer or mask — defaults to layer 1, mask 1.
- Player car (`car_interior.gd`) also uses defaults.
- All physics bodies (traffic, player, buildings, sidewalks, ground) are on layer 1 and collide with everything.
- `FrontRay` (RayCast3D) also defaults to mask 1, meaning it detects buildings and sidewalks as obstacles, causing false braking near structures.

### Gravity Bug (T-8)
- `traffic_vehicle.gd:55-58` sets `velocity = forward * _current_speed` then subtracts `9.8 * delta` from `velocity.y`. But velocity is rebuilt from scratch each frame, so gravity never accumulates — the vehicle falls at a constant `9.8 * delta` m/s instead of accelerating.
- Compare with the correct pattern in `car_interior.gd:252-258` which uses a persistent `_vertical_velocity` variable.

### Self-Destruct Notification (T-9)
- When `_try_next_road()` fails (no intersection or no candidates), the vehicle calls `queue_free()` directly (`traffic_vehicle.gd:187,211`). The `TrafficManager` isn't notified — the vehicle just becomes an invalid reference in `_active_vehicles`. The count stays wrong until the next `_despawn_far_vehicles()` loop happens to check `is_instance_valid()`. During that window, the manager may refuse to spawn replacements because it thinks it's at capacity.

### Dynamic Lights (O-7)
- Each traffic vehicle has 4 lights: 2x `SpotLight3D` headlights (15m range) + 2x `OmniLight3D` taillights (2m range).
- With 12 vehicles: 48 dynamic lights in the scene. No distance-based fading is configured.

## Desired End State

After this plan is complete:

1. **RoadNetwork maintains a road-intersection adjacency graph** built during `discover()`. Given any road and a travel direction, the network can return the intersection at that road's destination end and all other roads connected to that intersection, with correct travel directions — all in O(1).
2. **Traffic vehicles select their next road** from the adjacency graph, never iterating all roads. No more illogical turns to disconnected roads.
3. **Traffic vehicles only stop for lights ahead of them**, verified via dot-product of the vehicle's forward vector against the direction to the intersection. No more mid-road stops for intersections behind them. No more per-frame linear scans of all intersections.
4. **Collision layers** are properly configured: environment, player, traffic, and sensors each have distinct layers. FrontRay only detects player and traffic vehicles.
5. **Gravity accumulates correctly** on traffic vehicles using the same pattern as the player car.
6. **Self-destructing vehicles notify TrafficManager** via signal so the active count stays accurate.
7. **Traffic vehicle lights have distance fade** enabled, culling at 50m from camera.

### How to Verify

- Run the game and observe traffic vehicles navigating intersections — they should never take illogical turns to disconnected roads.
- Park at an intersection and watch: vehicles should stop for red lights only when approaching, never when past.
- Drive into a traffic vehicle — collision should work. Drive near a building — FrontRay should not cause traffic to brake.
- Push a traffic vehicle off a ledge (if possible) — it should fall at realistic speed, not float.
- Monitor the remote debugger's scene tree — `TrafficManager._active_vehicles` count should always match the actual number of `TrafficVehicle` nodes in the tree.

## What We're NOT Doing

- **Multi-lane traffic** (GD-4, GD-5): Vehicles will still use lane 0 only. Lane changing and multi-lane selection is a separate feature.
- **AI personality** (GD-2): No aggressive/slow driver variance beyond existing 90-110% speed.
- **Vehicle variety** (GD-1): No new vehicle types or meshes.
- **Spatial indexing** (S-1): We'll optimize hot paths with cached adjacency data, not build a general spatial hash grid.
- **Object pooling** (S-4): Vehicles will still be instantiated/freed. Pooling is a future optimization.
- **Spawn visibility** (GD-7): No fade-in or off-screen spawning changes.
- **Turn signal logic** (GD-6 partial): Road selection will be correct (connected roads only), but no weighted preference to prevent U-turns. That's a game-feel tuning pass.

## Implementation Approach

Phases are ordered by dependency:
1. **Phase 1** builds the adjacency graph — everything else depends on this data.
2. **Phase 2** uses the adjacency to fix traffic light checks and road selection.
3. **Phase 3** is independent physics/collision work.
4. **Phase 4** is independent visual optimization.

Phases 3 and 4 are independent of each other and could be done in either order.

---

## Phase 1: Build Road-Intersection Adjacency Graph

### Overview
Add relational data to `RoadNetwork` that maps each road to its endpoint intersections, and each intersection to its connected roads with travel directions. Build this during `discover()`. Expose query methods that `TrafficVehicle` will use in Phase 2.

### Changes Required

#### 1. RoadNetwork — Add adjacency data and build step
**File**: `scripts/road/road_network.gd`

Add new member variables after `_intersections`:

```gdscript
# Maps RoadSegment -> { "start": Intersection or null, "end": Intersection or null }
var _road_endpoints: Dictionary = {}

# Maps Intersection -> Array of { "road": RoadSegment, "enters_forward": bool }
# enters_forward=true means a vehicle entering from this intersection travels direction=1
var _intersection_connections: Dictionary = {}
```

Add a `_build_adjacency()` method called at the end of `discover()`:

```gdscript
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
                "enters_forward": true,  # entering from curve start → travel direction=1
            })

        if end_intersection:
            if not _intersection_connections.has(end_intersection):
                _intersection_connections[end_intersection] = []
            _intersection_connections[end_intersection].append({
                "road": road,
                "enters_forward": false,  # entering from curve end → travel direction=-1
            })
```

Update `discover()` to call it:

```gdscript
func discover() -> void:
    _roads.clear()
    _intersections.clear()
    _discover_children(self)
    _build_adjacency()
```

Add query methods:

```gdscript
## Returns the intersection at the destination end of a road for a given travel direction.
## direction=1 → vehicle heading toward curve end; direction=-1 → heading toward curve start.
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
```

#### 2. Intersection — Remove unused `connected_roads` export
**File**: `scripts/road/intersection.gd`

Remove the unused export that was never populated:

```gdscript
# DELETE this line:
@export var connected_roads: Array[NodePath] = []
```

This field was never set by `test_area.gd` and never read by any system. Removing it prevents confusion about where connectivity data lives (answer: `RoadNetwork`).

### Success Criteria

#### Manual Verification:
- [ ] Game starts without errors — `discover()` completes and `_road_endpoints` / `_intersection_connections` are populated.
- [ ] Add a temporary `print()` in `_build_adjacency()` to confirm each road has 2 endpoint intersections and each intersection has the expected number of connected roads (horizontal roads: 3 intersections, vertical roads: 3 intersections; each intersection: 2 roads).
- [ ] No behavioral change yet — traffic vehicles still use the old `_try_next_road()`. This phase only adds data; Phase 2 consumes it.

---

## Phase 2: Fix Road Selection and Traffic Light Direction

### Overview
Rewrite `_try_next_road()` to use the adjacency graph. Rewrite `_should_stop_for_light()` to use O(1) adjacency lookup + dot-product direction check. This fixes T-1, T-4, O-1, and O-2 simultaneously.

### Changes Required

#### 1. TrafficVehicle — Rewrite `_try_next_road()`
**File**: `scripts/traffic/traffic_vehicle.gd`

Replace the existing `_try_next_road()` (lines 185-224) entirely:

```gdscript
func _try_next_road() -> void:
    if not _road_network:
        _self_despawn()
        return

    # Get the intersection at the end of our current road (in our travel direction)
    var intersection: Intersection = _road_network.get_road_end_intersection(
        _assigned_road, _assigned_direction
    )
    if not intersection:
        _self_despawn()
        return

    # Get all connected roads at this intersection, excluding our current road
    var candidates: Array[Dictionary] = _road_network.get_connected_roads(
        intersection, _assigned_road
    )
    if candidates.is_empty():
        _self_despawn()
        return

    # Pick a random connected road
    var choice: Dictionary = candidates[randi() % candidates.size()]
    var next_road: RoadSegment = choice["road"] as RoadSegment
    var next_dir: int = choice["direction"] as int

    _assigned_road = next_road
    _assigned_direction = next_dir
    _target_speed = next_road.speed_limit * randf_range(0.9, 1.1)
    _path_points = next_road.get_lane_points(0, next_dir, 40)
    _path_index = 0
    _state = State.TURNING
```

Add the `_self_despawn()` helper (for T-9, replaces raw `queue_free()` calls):

```gdscript
signal vehicle_despawning

func _self_despawn() -> void:
    vehicle_despawning.emit()
    queue_free()
```

#### 2. TrafficVehicle — Rewrite `_should_stop_for_light()`
**File**: `scripts/traffic/traffic_vehicle.gd`

Replace the existing `_should_stop_for_light()` (lines 166-182):

```gdscript
func _should_stop_for_light() -> bool:
    if not _road_network or not _assigned_road:
        return false

    # O(1) lookup: get the intersection ahead of us
    var intersection: Intersection = _road_network.get_road_end_intersection(
        _assigned_road, _assigned_direction
    )
    if not intersection:
        return false

    var to_intersection: Vector3 = intersection.global_position - global_position
    var dist: float = to_intersection.length()

    # Only consider intersections within stopping range, not ones we're already past
    if dist < STOP_DISTANCE or dist > 15.0:
        return false

    # Dot-product: only stop if the intersection is ahead of us
    var forward: Vector3 = -transform.basis.z
    if forward.dot(to_intersection.normalized()) < 0.0:
        return false

    var light_state: Intersection.LightState = intersection.get_light_state(_assigned_road)
    return light_state != Intersection.LightState.GREEN
```

#### 3. TrafficManager — Connect despawn signal
**File**: `scripts/traffic/traffic_manager.gd`

In `_spawn_vehicle()`, connect the signal after instantiation:

```gdscript
func _spawn_vehicle(road: RoadSegment, direction: int, pos: Vector3, forward: Vector3) -> void:
    var vehicle: TrafficVehicle = _vehicle_scene.instantiate() as TrafficVehicle
    add_child(vehicle)

    vehicle.global_position = pos

    # Face the correct direction
    var face_dir: Vector3 = forward.normalized() * direction
    if face_dir.length() > 0.001:
        var target_angle: float = atan2(-face_dir.x, -face_dir.z)
        vehicle.rotation.y = target_angle

    # Randomize color
    var car_mesh: MeshInstance3D = vehicle.get_node("CarMesh") as MeshInstance3D
    if car_mesh and car_mesh.material_override:
        var mat: StandardMaterial3D = car_mesh.material_override.duplicate() as StandardMaterial3D
        mat.albedo_color = VEHICLE_COLORS[randi() % VEHICLE_COLORS.size()]
        car_mesh.material_override = mat

    # Connect despawn signal so we track count accurately (T-9)
    vehicle.vehicle_despawning.connect(_on_vehicle_despawning.bind(vehicle))

    vehicle.initialize(road, direction, _road_network)
    _active_vehicles.append(vehicle)


func _on_vehicle_despawning(vehicle: TrafficVehicle) -> void:
    _active_vehicles.erase(vehicle)
```

### Success Criteria

#### Manual Verification:
- [ ] Traffic vehicles navigate intersections correctly — they turn onto connected roads only, never teleporting or picking disconnected roads.
- [ ] Park the player car at an intersection and watch the light cycle. Vehicles approaching a red light stop before the intersection. Vehicles that just passed through do NOT stop mid-road when the light behind them turns red.
- [ ] Drive around for 2+ minutes — no vehicles disappear unexpectedly (unless they hit a dead-end, which shouldn't happen in the 3x3 grid since all roads connect).
- [ ] Check remote debugger: `TrafficManager._active_vehicles.size()` should match the actual count of `TrafficVehicle` nodes at all times.

---

## Phase 3: Collision Layers and Physics Fixes

### Overview
Configure proper collision layers so physics bodies and raycasts interact correctly. Fix the gravity accumulation bug in traffic vehicles.

### Changes Required

#### 1. Define collision layer scheme

| Layer | Name           | Used By                              |
|-------|----------------|--------------------------------------|
| 1     | Environment    | Buildings, sidewalks, ground         |
| 2     | Player Vehicle | CarInterior (CharacterBody3D)        |
| 3     | Traffic        | TrafficVehicle (CharacterBody3D)     |

Layer assignments:
- **Player car**: Layer = 2, Mask = 1 + 3 (collides with environment and traffic)
- **Traffic vehicle**: Layer = 3, Mask = 1 + 2 + 3 (collides with environment, player, and other traffic)
- **FrontRay** (traffic): Mask = 2 + 3 (detects player and traffic only, NOT buildings/sidewalks)
- **Buildings/sidewalks/ground**: Layer = 1, Mask = 1 (remain on default; they don't need to detect anything)

#### 2. Traffic vehicle scene — Set layers
**File**: `scenes/traffic/traffic_vehicle.tscn`

On the root `TrafficVehicle` (CharacterBody3D) node:
- `collision_layer = 4` (layer 3, which is bit 2^2 = 4)
- `collision_mask = 7` (layers 1+2+3 = bits 1+2+4 = 7)

On the `FrontRay` (RayCast3D) node:
- `collision_mask = 6` (layers 2+3 = bits 2+4 = 6)

These should be set in the .tscn file directly.

#### 3. Player car scene — Set layers
**File**: `scenes/main/car_interior.tscn`

On the root `CarInterior` (CharacterBody3D) node:
- `collision_layer = 2` (layer 2, bit 2^1 = 2)
- `collision_mask = 5` (layers 1+3 = bits 1+4 = 5)

#### 4. TrafficVehicle — Fix gravity accumulation
**File**: `scripts/traffic/traffic_vehicle.gd`

Add a member variable:

```gdscript
var _vertical_velocity: float = 0.0
```

In `_physics_process()`, replace the velocity/gravity/move block (lines 54-59):

```gdscript
    # Apply movement
    var forward: Vector3 = -transform.basis.z
    velocity = forward * _current_speed

    # Gravity — accumulate like car_interior.gd for realistic falling
    if is_on_floor():
        _vertical_velocity = 0.0
    else:
        _vertical_velocity -= 9.8 * delta

    velocity.y = _vertical_velocity
    move_and_slide()
```

### Success Criteria

#### Manual Verification:
- [ ] Traffic vehicles collide with the player car — driving into one produces a physical collision response.
- [ ] Traffic vehicles collide with each other (they don't pass through one another).
- [ ] Traffic vehicles do NOT falsely brake near buildings or sidewalks — the FrontRay ignores environment objects.
- [ ] If a traffic vehicle somehow ends up airborne (e.g., collision launch), it falls at realistic speed, not floating slowly.
- [ ] The player car can still collide with buildings, sidewalks, and ground normally.

---

## Phase 4: Traffic Vehicle Light Optimization

### Overview
Add distance-based fading to all traffic vehicle lights so they don't render when far from the camera. Reduces GPU cost from 48 to ~8-16 active dynamic lights (only vehicles within 50m).

### Changes Required

#### 1. Traffic vehicle scene — Enable distance fade on all lights
**File**: `scenes/traffic/traffic_vehicle.tscn`

On `HeadlightL` and `HeadlightR` (SpotLight3D):
- `distance_fade_enabled = true`
- `distance_fade_begin = 40.0`
- `distance_fade_length = 10.0`

On `TaillightL` and `TaillightR` (OmniLight3D):
- `distance_fade_enabled = true`
- `distance_fade_begin = 30.0`
- `distance_fade_length = 10.0`

Taillights get a shorter range (30m) since they're dimmer (energy 0.4, range 2.0) and not visible from far away anyway.

This uses Godot's built-in distance fade, which measures from the active camera. No code changes needed — the engine handles culling automatically.

### Success Criteria

#### Manual Verification:
- [ ] Lights on nearby traffic vehicles (< 30m) are fully visible — headlights and taillights render normally.
- [ ] Lights on distant traffic vehicles (> 50m) are not visible.
- [ ] No pop-in artifacts — lights fade smoothly as vehicles approach/recede.
- [ ] Performance: use Godot's debugger performance monitor to confirm the active light count drops when vehicles are far away.

---

## Testing Strategy

### Integration Testing (Manual):
1. Start the game and let traffic run for 3+ minutes. Watch for:
   - Vehicles navigating all intersections in the 3x3 grid
   - No vehicles stuck permanently (blocked at intersections, unable to find next road)
   - No vehicles stopping mid-road after passing an intersection
2. Drive into traffic — collisions should work. Drive near buildings — traffic should not falsely brake.
3. Park at a busy intersection and watch 5+ light cycles. Count how many vehicles correctly stop vs. run reds. Zero red-light running expected.
4. Check the scene tree in the remote debugger periodically — `_active_vehicles` count should match reality.

### Edge Cases to Watch:
- Vehicle reaching the end of an edge road (road with only one intersection at one end) — should `_self_despawn()` cleanly
- Two vehicles approaching the same intersection from opposite directions on the same road — should both see the correct light state
- A vehicle spawned very close to an intersection — should not immediately brake for a red light behind it

## Performance Considerations

- **Phase 1 adds ~0.1ms one-time cost** during `discover()` for building adjacency (6 roads x 9 intersections = 54 distance checks). Negligible.
- **Phase 2 eliminates per-frame O(n) scans**: `_should_stop_for_light()` drops from O(intersections) to O(1). `_try_next_road()` drops from O(roads) to O(connected_roads_at_intersection), typically 2-3.
- **Phase 3 reduces collision broadphase work**: Separating layers means the engine's broadphase can skip many pair checks.
- **Phase 4 reduces GPU draw calls**: Distance-faded lights don't contribute to lighting passes. With 3-4 vehicles typically within 40m, active light count drops from 48 to ~12-16.

## References

- Audit that identified these issues: conversation context above
- Player car gravity pattern to match: `scenes/main/car_interior.gd:252-258`
- Existing intersection proximity threshold (10m): `traffic_vehicle.gd:206`
- Godot Light3D distance fade docs: built-in properties on SpotLight3D and OmniLight3D
