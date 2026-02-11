# Rideshare Driving & NPC System Implementation Plan

## Overview

Replace the on-rails driving prototype with a real player-controlled vehicle, a navigable road network, traffic AI, a camera/attention system, and procedural passenger generation. The goal is to transform the current narrative prototype into a playable driving game that matches the vision in `implementation.md`.

## Current State Analysis

The existing codebase is a **narrative-focused prototype** with 13 GDScript files:

- **Driving** (`car_interior.gd`): On-rails. The car doesn't move — the environment scrolls backward. Steering is cosmetic. `start_driving(route_length)` / `stop_driving()` simulate travel by incrementing a progress float.
- **Game Loop** (`game.gd`): Phase state machine (8 states) manages ride flow. Relies on `car_interior.destination_reached` signal which fires when on-rails progress hits 100%.
- **Passengers** (`passenger_manager.gd`, `passenger_data.gd`): Hand-authored `.tres` resource files loaded from `resources/passengers/`. Conditional appearance via flags, ride number, and time windows. No procedural generation.
- **Dialogue** (`dialogue_box.gd`): Fully functional branching dialogue tree with conditions, triggers, choices, and variable substitution.
- **GPS** (`gps.gd`): Text-based display with glitch effects. Shows destination string, ETA, and status. No actual navigation/routing.
- **Phone** (`phone.gd`): Ride request display, notifications, shift info. Functional.
- **Audio** (`audio_manager.gd`): 5-layer ambient system with state crossfading. Functional.
- **Events** (`event_manager.gd`, `game_event.gd`): Framework exists but no events registered. Simple triggers work.
- **State** (`game_state.gd`): Flag system, time, ride tracking, condition parser. Functional.

### Key Discoveries
- `car_interior.tscn` root is `Node3D` — must become `CharacterBody3D` for physics
- `car_interior.gd` signals (`destination_reached`, `passenger_entered`, `passenger_exited`) are used by `game.gd` — must preserve interface
- `game.gd:100-108` awaits `car_interior.destination_reached` synchronously — must change to proximity-based detection
- Input map in `project.godot` lacks accelerate/brake/handbrake actions
- No 3D world geometry exists — only placeholder car interior meshes
- `EnvironmentMover` node in `car_interior.tscn` was used for on-rails scrolling — will be removed

## Desired End State

After this plan is complete:

1. The player can drive a car with WASD through a small city test area (4-6 blocks)
2. The car has throttle ramps, steering ramps, forward/reverse, handbrake, and collision
3. A Path3D-based road network defines lanes, intersections, and traffic lights
4. AI traffic vehicles follow road paths, obey traffic lights, and react to the player
5. A hybrid camera system lets the player snap between look zones (hotkeys) and fine-adjust (mouse), with lane drift when not looking forward
6. Procedural passengers are generated with behavior vectors and archetype matching
7. Passengers are picked up and dropped off at physical road locations
8. The existing narrative passenger and dialogue systems continue to work
9. The full ride loop works: app request → drive to pickup → passenger boards → drive to destination → passenger exits

### Verification
- Run the game, accept a ride, drive to pickup, pick up passenger, drive to destination, drop off, receive next ride
- AI traffic is visible on roads, stopping at red lights, honking when blocked
- Camera zones work with hotkeys and mouse, lane drift is felt when looking away
- Both procedural and narrative passengers appear correctly

## What We're NOT Doing

- Full city with all neighborhoods (downtown, industrial, entertainment, outskirts) — only a tiny test area
- Passenger body language or animation system — passengers are black billboard quads
- Real mirror rendering (SubViewport cameras) — placeholder textured planes only
- Police vehicles with pursuit/traffic stop logic
- Pedestrians
- Fuel system, car degradation, or maintenance
- Economy system (fares, tips, rent)
- Inventory / items left behind
- Radio / police scanner audio
- Notification / messaging system
- Weather effects
- Save system
- Any 3D art assets beyond basic primitives

## Implementation Approach

Six phases, each producing a testable increment. The existing game loop will be temporarily simplified during Phases 1-5 and fully rewired in Phase 6.

---

## Phase 1: Vehicle Controller

### Overview
Replace the on-rails `car_interior.gd` with a `CharacterBody3D`-based vehicle that responds to player input. The car will be driveable on a flat ground plane.

### Changes Required

#### 1. Input Actions ✅
**File**: `project.godot`
**Changes**: Add new input actions, remap interact from E to F

New actions to add:
| Action | Keys |
|---|---|
| `accelerate` | W, Up Arrow |
| `brake` | S, Down Arrow |
| `handbrake` | Space |
| `shift_forward` | E |
| `shift_reverse` | Q |
| `interact` | F (change from E) |

Modify existing:
- Remove Space from `advance_dialogue` (keep Mouse Click and add Enter)
- Change `interact` from E key to F key

#### 2. Vehicle Controller Script ✅
**File**: `scenes/main/car_interior.gd`
**Changes**: Complete rewrite. Replace on-rails system with CharacterBody3D physics.

Core architecture:
```gdscript
extends CharacterBody3D

signal passenger_entered
signal passenger_exited
signal destination_reached

# -- Throttle --
var _throttle_input: float = 0.0  # 0→1, ramped
var _brake_input: float = 0.0     # 0→1, ramped
var _current_speed: float = 0.0   # m/s, signed (negative = reverse)

const THROTTLE_RAMP := 3.3    # reaches 1.0 in ~0.3s
const BRAKE_RAMP := 5.0
const MAX_FORWARD_SPEED := 25.0   # m/s (~56 mph)
const MAX_REVERSE_SPEED := 8.0    # m/s (~18 mph)
const ACCELERATION := 12.0        # m/s²
const BRAKE_DECEL := 20.0         # m/s²
const FRICTION_DECEL := 5.0       # natural slowdown m/s²
const HANDBRAKE_DECEL := 30.0     # m/s²

# -- Steering --
var _steer_input: float = 0.0   # -1 to 1, ramped
var _steer_angle: float = 0.0   # current effective angle in degrees
var drift_steer: float = 0.0    # injected by camera/attention system

const STEER_RAMP := 2.5         # ramp speed when key held
const STEER_RETURN := 3.0       # auto-center speed when key released
const MAX_STEER_ANGLE := 35.0   # degrees

# -- Gear --
enum Gear { FORWARD, REVERSE }
var current_gear: Gear = Gear.FORWARD

# -- State --
var _is_handbraking: bool = false
var _has_passenger: bool = false
```

Key methods and their behavior:

**`_physics_process(delta)`**: Calls `_read_input()`, `_update_speed()`, `_update_steering()`, `_apply_movement()`, `_update_visuals()` in sequence.

**`_read_input(delta)`**:
- Throttle: `move_toward(_throttle_input, 1.0 if pressed else 0.0, THROTTLE_RAMP * delta)`
- Brake: same pattern with `BRAKE_RAMP`
- Steer: `Input.get_axis("steer_left", "steer_right")` → ramp toward raw input at `STEER_RAMP`, ramp toward 0 at `STEER_RETURN` when released
- Handbrake: direct boolean from `Input.is_action_pressed("handbrake")`
- Gear: `is_action_just_pressed("shift_forward")` / `"shift_reverse"`

**`_update_speed(delta)`**:
- Determine max speed and direction sign from `current_gear`
- Throttle: `move_toward(_current_speed, max_speed * direction, ACCELERATION * _throttle_input * delta)`
- Brake: `move_toward(_current_speed, 0.0, BRAKE_DECEL * _brake_input * delta)`
- Handbrake: `move_toward(_current_speed, 0.0, HANDBRAKE_DECEL * delta)`
- Friction (when no throttle and no handbrake): `move_toward(_current_speed, 0.0, FRICTION_DECEL * delta)`

**`_update_steering(delta)`**:
- Combine player steer and drift: `total_steer = clamp(_steer_input + drift_steer, -1.0, 1.0)`
- Convert to angle: `_steer_angle = total_steer * MAX_STEER_ANGLE`
- Apply rotation only when moving: `if abs(_current_speed) > 0.5` → `rotation.y -= deg_to_rad(_steer_angle * (_current_speed / MAX_FORWARD_SPEED) * 2.0) * delta`
- Turning radius scales with speed — slow = tight turns, fast = wide turns

**`_apply_movement(delta)`**:
- Forward vector: `-transform.basis.z`
- `velocity = forward * _current_speed`
- Apply gravity: `velocity.y -= 9.8 * delta` (if not on floor)
- `move_and_slide()`

**`_update_visuals()`**:
- Steering wheel mesh rotation: `steering_wheel.rotation.y = deg_to_rad(-_steer_angle * 3.0)` (visual amplification so the wheel turns more than the actual steer angle)

**Public API** (preserving interface for game.gd):
```gdscript
func get_speed() -> float           # abs speed in m/s
func get_speed_mph() -> float       # for speedometer
func get_rpm() -> float             # fake RPM: remap speed 0→max to 800→6000
func get_gear_string() -> String    # "D" or "R"
func seat_passenger(node: Node3D)   # reparent to PassengerSeat, emit signal
func remove_passenger()             # queue_free children of seat, emit signal
func has_passenger() -> bool
```

Remove these methods (no longer applicable):
- `start_driving()`
- `stop_driving()`
- `get_drive_progress()`

Remove these variables:
- `drive_speed`, `max_steering_offset` exports
- `_driving`, `_drive_progress`, `_route_length`

#### 3. Car Interior Scene ✅
**File**: `scenes/main/car_interior.tscn`
**Changes**:
- Change root node type from `Node3D` to `CharacterBody3D`
- Add `CollisionShape3D` child with `BoxShape3D` (size ~Vector3(2.0, 1.2, 4.5) for car body)
- Remove `EnvironmentMover` node (no longer needed for on-rails)
- Keep all CarMesh children (DashboardCamera, PassengerSeat, RearviewMirror, DashboardLight, GPSScreen, SteeringWheel, InstrumentPanel, CenterConsole, GearShift)

#### 4. Ground Plane ✅
**File**: `scenes/main/game.tscn`
**Changes**: Add a temporary ground plane for Phase 1 testing
- Add `StaticBody3D` child of Game root with:
  - `CollisionShape3D` using `WorldBoundaryShape3D` (infinite flat plane at y=0)
  - `MeshInstance3D` with a large `PlaneMesh` (size 500x500) for visual ground
  - Basic `StandardMaterial3D` with dark gray albedo

#### 5. Game Script Adaptation ✅
**File**: `scenes/main/game.gd`
**Changes**: Temporarily simplify the ride loop so the game runs without on-rails driving.

Key changes:
- Remove calls to `car_interior.start_driving()` and `car_interior.stop_driving()`
- In `PICKING_UP` phase: instead of `await car_interior.destination_reached`, use a timer or manual trigger (press Y to simulate arrival) as a temporary placeholder until Phase 6 wires up proximity detection
- In `IN_RIDE` phase: same — remove `car_interior.start_driving(80.0)`, the player is now driving themselves
- Keep all other phase logic intact (dialogue, GPS, flags, endings)

Temporary approach for destination arrival:
```gdscript
# In PICKING_UP phase, replace:
#   car_interior.start_driving(30.0)
#   await car_interior.destination_reached
# With:
#   phone.show_notification("Drive to pickup location. Press Y when arrived.")
#   # arrival will be detected by input until Phase 6 adds proximity

# In IN_RIDE phase, replace:
#   car_interior.start_driving(80.0)
# With:
#   # Player drives themselves, destination_reached handled by proximity (Phase 6)
```

Add temporary input handling in `_unhandled_input`:
```gdscript
if event.is_action_pressed("accept_ride"):
	if current_phase == GamePhase.PICKING_UP:
		_on_destination_reached()  # manual trigger for testing
	elif current_phase == GamePhase.IN_RIDE:
		_on_destination_reached()  # manual trigger for testing
```

### Success Criteria

#### Manual Verification
- [ ] Game launches without errors
- [ ] WASD drives the car on the flat ground plane
- [ ] Throttle ramps smoothly (no instant snap to full speed)
- [ ] Steering ramps smoothly (tap = small correction, hold = wider turn)
- [ ] Steering auto-centers when A/D released
- [ ] Car cannot turn when stationary
- [ ] E/Q switches between forward and reverse
- [ ] Space applies handbrake (car stops faster)
- [ ] Car collides with ground (doesn't fall through)
- [ ] Steering wheel mesh rotates visually with input
- [ ] Pressing Y during ride phases advances the game loop (temporary)
- [ ] Dialogue, GPS, phone, and audio systems still work

---

## Phase 2: Road Network & Test Area

### Overview
Build a Path3D-based road system and a tiny 4-6 block test area with intersections and traffic lights. The player will drive on actual roads instead of a flat plane.

### Changes Required

#### 1. Road Segment Script ✅
**File**: `scripts/road/road_segment.gd` (new)
**Changes**: Define a road segment with lane metadata

```gdscript
class_name RoadSegment
extends Path3D

@export var lane_count: int = 1          # lanes per direction
@export var lane_width: float = 3.5      # meters
@export var speed_limit: float = 13.4    # m/s (~30 mph)
@export var road_name: String = ""

# Returns world-space points along a specific lane
# lane_index: 0 = innermost lane, increasing outward
# direction: 1 = forward along path, -1 = reverse (oncoming)
func get_lane_points(lane_index: int, direction: int, point_count: int = 20) -> PackedVector3Array:
    var points: PackedVector3Array = []
    var offset := (lane_index + 0.5) * lane_width * direction
    for i in point_count:
        var t := float(i) / float(point_count - 1)
        var pos := curve.sample_baked(t * curve.get_baked_length())
        var forward_vec := curve.sample_baked(min(t + 0.01, 1.0) * curve.get_baked_length()) - pos
        if forward_vec.length() < 0.001:
            continue
        var right := forward_vec.normalized().cross(Vector3.UP).normalized()
        points.append(global_transform * (pos + right * offset))
    return points

func get_length() -> float:
    return curve.get_baked_length()
```

#### 2. Intersection Script ✅
**File**: `scripts/road/intersection.gd` (new)
**Changes**: Intersection node that manages traffic light state for connected roads

```gdscript
class_name Intersection
extends Node3D

signal light_changed(road_index: int, new_state: LightState)

enum LightState { GREEN, YELLOW, RED }

@export var connected_roads: Array[NodePath] = []
@export var has_traffic_light: bool = true
@export var green_duration: float = 15.0
@export var yellow_duration: float = 3.0

var _light_states: Dictionary = {}   # int road_group_index -> LightState
var _cycle_timer: float = 0.0
var _current_green_group: int = 0    # which group of roads is green
var _num_groups: int = 2             # opposing roads share a group
```

Traffic light cycle logic:
- Roads are grouped into 2 groups (opposing directions share a group)
- Group 0 starts GREEN, group 1 starts RED
- After `green_duration`, GREEN group goes YELLOW
- After `yellow_duration`, YELLOW group goes RED, other group goes GREEN
- `get_light_state(road: RoadSegment) -> LightState` for AI queries

Visual representation:
- Child `MeshInstance3D` nodes for the light housing (box) and colored light indicators (spheres with emissive materials)
- Material changes on state transitions (green/yellow/red emissive colors)

#### 3. Road Network Manager ✅
**File**: `scripts/road/road_network.gd` (new)
**Changes**: Manages all roads and intersections, provides queries for AI and GPS

```gdscript
class_name RoadNetwork
extends Node

var _roads: Array[RoadSegment] = []
var _intersections: Array[Intersection] = []

func _ready() -> void:
    # Discover all RoadSegment and Intersection children recursively
    _roads = _find_children_of_type("RoadSegment")
    _intersections = _find_children_of_type("Intersection")

func get_nearest_road(world_pos: Vector3) -> RoadSegment
func get_nearest_lane_position(world_pos: Vector3) -> Dictionary
    # Returns { road: RoadSegment, lane: int, direction: int, position: Vector3, t: float }

func get_random_road_position() -> Dictionary
    # Returns a random point on any road lane — used for passenger pickup/destination generation

func get_intersection_at(world_pos: Vector3, radius: float = 5.0) -> Intersection
```

#### 4. Road Mesh Generator ✅
**File**: `scripts/road/road_mesh_generator.gd` (new)
**Changes**: Generates visual road geometry from Path3D curves at runtime or as a tool script

Approach:
- For each `RoadSegment`, generate a flat ribbon mesh following the curve
- Total road width = `lane_count * 2 * lane_width` + shoulder width
- Use `SurfaceTool` to build the mesh from curve sample points
- Apply a dark asphalt `StandardMaterial3D` (dark gray, slight roughness)
- Generate lane line meshes (dashed white for lane dividers, solid yellow for center line)
- Lane lines are thin quads slightly above the road surface (y offset ~0.01)

#### 5. Test Area Scene ✅
**File**: `scenes/world/test_area.tscn` (new)
**Changes**: A small 2x3 grid of city blocks

Layout (approximately):
```
     V1     V2     V3
      |      |      |
H1 ---+------+------+---
      |  B1  |  B2  |
H2 ---+------+------+---
      |  B3  |  B4  |
H3 ---+------+------+---
```

Dimensions:
- Block size: ~60m x 60m
- Road width: ~14m (2 lanes each direction at 3.5m)
- Total area: ~220m x 200m

Scene structure:
```
TestArea (Node3D)
├── RoadNetwork (road_network.gd)
│   ├── H1 (RoadSegment - horizontal, Path3D)
│   ├── H2 (RoadSegment - horizontal, Path3D)
│   ├── H3 (RoadSegment - horizontal, Path3D)
│   ├── V1 (RoadSegment - vertical, Path3D)
│   ├── V2 (RoadSegment - vertical, Path3D)
│   ├── V3 (RoadSegment - vertical, Path3D)
│   ├── Intersection_H1V1 (Intersection)
│   ├── Intersection_H1V2 (Intersection)
│   ├── Intersection_H1V3 (Intersection)
│   ├── Intersection_H2V1 (Intersection)
│   ├── Intersection_H2V2 (Intersection)
│   ├── Intersection_H2V3 (Intersection)
│   ├── Intersection_H3V1 (Intersection)
│   ├── Intersection_H3V2 (Intersection)
│   └── Intersection_H3V3 (Intersection)
├── RoadMeshes (Node3D - generated road surfaces)
├── Buildings (Node3D)
│   ├── Block1 (CSGBox3D or MeshInstance3D - simple colored boxes)
│   ├── Block2
│   ├── Block3
│   └── Block4
├── Sidewalks (Node3D - thin raised planes along road edges)
├── Lighting (Node3D)
│   ├── DirectionalLight3D (moonlight)
│   └── StreetLights (OmniLight3D instances at intersections and mid-block)
└── Ground (StaticBody3D + MeshInstance3D - base ground beneath roads)
```

Building blocks are simple CSGBox3D or BoxMesh primitives with varied heights (10-30m) and muted colors. They exist to fill the blocks and provide visual reference, not to be detailed.

Street lights: OmniLight3D nodes at intersections and mid-block along roads. Warm yellow/orange color, range ~15m, energy ~0.8. Creates pools of light with dark gaps between — matches the nighttime atmosphere.

#### 6. Integrate Test Area into Game Scene ✅
**File**: `scenes/main/game.tscn`
**Changes**:
- Remove the temporary flat ground plane from Phase 1
- Instance `test_area.tscn` as a child of the Game root
- Position the car at a starting location on one of the roads

**File**: `scenes/main/game.gd`
**Changes**:
- Add `@onready var road_network: RoadNetwork` reference
- No functional changes yet (road network used by later phases)

#### 7. Road Collision ✅
Each road segment needs `StaticBody3D` + `CollisionShape3D` for the car to drive on. Options:
- Generate collision from the same mesh (trimesh collision) — simplest
- Use `CollisionPolygon3D` along the path — more precise

Use trimesh collision generated from the road mesh. The `road_mesh_generator.gd` creates both the visual mesh and a corresponding `StaticBody3D` with `CollisionShape3D` using `create_trimesh_collision()` on the `MeshInstance3D`.

Buildings and sidewalks also get `StaticBody3D` collision so the car can't drive through them. Sidewalk curbs are raised ~0.15m to prevent easy mounting.

### Success Criteria

#### Manual Verification
- [ ] Test area loads with visible roads, intersections, buildings, and street lights
- [ ] Roads have visible lane markings (white dashes, yellow center)
- [ ] Car drives on the roads and is constrained by sidewalk curbs
- [ ] Car can navigate around all blocks following the road layout
- [ ] Traffic lights at intersections cycle through green/yellow/red visually
- [ ] Night atmosphere: dark sky, pools of streetlight, moonlight shadows
- [ ] No z-fighting between road surface and lane markings
- [ ] Performance: steady 60fps with the test area loaded

---

## Phase 3: Camera & Attention System

### Overview
Replace the fixed camera with a hybrid free-look system. Hotkeys snap to predefined zones (rearview, phone, side mirrors). Mouse provides fine adjustment within each zone. When the player is not looking forward, the car drifts via injected steering input.

### Changes Required

#### 1. Camera Controller Script ✅
**File**: `scripts/camera_controller.gd` (new)

```gdscript
class_name CameraController
extends Node3D

enum Zone { FORWARD, REARVIEW, PHONE, LEFT_MIRROR, RIGHT_MIRROR }

signal zone_changed(new_zone: Zone)

var current_zone: Zone = Zone.FORWARD
var _mouse_offset: Vector2 = Vector2.ZERO  # radians offset within zone

# Zone target rotations (pitch, yaw) in radians
const ZONE_TARGETS := {
	Zone.FORWARD:      Vector2(0.0, 0.0),
	Zone.REARVIEW:     Vector2(deg_to_rad(-12), deg_to_rad(25)),
	Zone.PHONE:        Vector2(deg_to_rad(-10), deg_to_rad(-20)),
	Zone.LEFT_MIRROR:  Vector2(0.0, deg_to_rad(-55)),
	Zone.RIGHT_MIRROR: Vector2(0.0, deg_to_rad(65)),
}

const MOUSE_SENSITIVITY := 0.002
const MOUSE_CLAMP := deg_to_rad(12)  # max mouse offset from zone center
const SNAP_SPEED := 8.0              # lerp speed for zone transitions
```

**Zone behavior**:
- `FORWARD` is default. Camera centers on the road ahead.
- `REARVIEW`: hold R. Camera snaps up-right toward rearview mirror. Release R returns to FORWARD.
- `PHONE`: hold T. Camera snaps up-left toward phone mount. Release T returns to FORWARD.
- `LEFT_MIRROR`: mouse moved far left (past threshold) while in FORWARD zone. Returns when mouse moves back.
- `RIGHT_MIRROR`: mouse moved far right (past threshold) while in FORWARD zone. Returns when mouse moves back.

**Mouse within zone**:
- While in any zone, mouse movement adds offset (clamped to `MOUSE_CLAMP` radius) from the zone's center target
- This lets the player fine-adjust their view within a zone (e.g., look slightly higher to read mirror text, or pan around within the rearview zone)

**Implementation in `_process(delta)`**:
- Read zone hotkey state (R held, T held)
- Determine target zone
- Lerp camera rotation toward `ZONE_TARGETS[current_zone] + _mouse_offset` at `SNAP_SPEED`
- Emit `zone_changed` when zone changes

**`_unhandled_input(event)`**:
- Mouse motion: accumulate `_mouse_offset`, clamp magnitude to `MOUSE_CLAMP`
- Reset `_mouse_offset` to zero when zone changes

#### 2. Input Actions ✅
**File**: `project.godot`
**Changes**: Add `look_phone` action mapped to T key.

`look_mirror` already exists mapped to R.

#### 3. Lane Drift System ✅
**File**: `scripts/camera_controller.gd` (integrated into camera controller)

When `current_zone != Zone.FORWARD`, the camera controller injects `drift_steer` into the car:

```gdscript
var _drift_direction: float = 0.0    # current drift steer value
var _drift_timer: float = 0.0
const DRIFT_CHANGE_INTERVAL := 3.0   # seconds between drift direction changes
const DRIFT_RAMP_SPEED := 0.3        # how fast drift builds
const DRIFT_MAX := 0.15              # max drift steer magnitude

func _update_drift(delta: float, car: CharacterBody3D) -> void:
    if current_zone == Zone.FORWARD:
        # Gradually remove drift
        _drift_direction = move_toward(_drift_direction, 0.0, DRIFT_RAMP_SPEED * 2.0 * delta)
    else:
        # Build drift
        _drift_timer += delta
        if _drift_timer >= DRIFT_CHANGE_INTERVAL:
            _drift_timer = 0.0
            # Pick new random drift direction (slight bias, never zero)
            _drift_direction = randf_range(-DRIFT_MAX, DRIFT_MAX)
            if abs(_drift_direction) < 0.03:
                _drift_direction = 0.05 * sign(randf() - 0.5)

    car.drift_steer = _drift_direction
```

The drift direction changes every ~3 seconds to a new random value so the player cannot predict and pre-compensate. The drift ramps gradually (not instant), producing a natural "hands relaxing on the wheel" feel.

#### 4. Integrate Camera Controller ✅
**File**: `scenes/main/car_interior.tscn`
**Changes**:
- Replace `DashboardCamera` (Camera3D) with a `CameraController` node (Node3D) that has a Camera3D child
- The CameraController is positioned at the driver's head position (same as current DashboardCamera transform)
- Camera3D is a child that inherits the CameraController's rotation

Scene structure change:
```
CarMesh/
  DashboardCamera (Camera3D)       → REMOVE
  CameraController (Node3D)        → NEW (scripts/camera_controller.gd)
    Camera3D                        → NEW (the actual camera)
```

**File**: `scenes/main/car_interior.gd`
**Changes**:
- Remove `look_at_mirror()` method (replaced by camera controller)
- Add reference to camera controller: `@onready var camera_controller: CameraController = $CarMesh/CameraController`

**File**: `scenes/main/game.gd`
**Changes**:
- Remove `look_mirror` input handling from `_unhandled_input` (camera controller handles it internally)
- Capture mouse for free look: `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)` in `_ready()`
- Add ESC to toggle mouse capture / pause

### Success Criteria

#### Manual Verification
- [ ] Default view looks forward through the windshield
- [ ] Holding R snaps camera to rearview mirror zone (up-right)
- [ ] Releasing R returns camera to forward
- [ ] Holding T snaps camera to phone zone (up-left)
- [ ] Moving mouse far left/right from forward reaches side mirror zones
- [ ] Mouse provides fine adjustment within each zone (subtle pan)
- [ ] Camera transitions are smooth (lerped, not instant)
- [ ] When looking at rearview (holding R) while driving, car gradually drifts
- [ ] Drift direction changes periodically (not constant one direction)
- [ ] Returning to forward view stops the drift
- [ ] Quick mirror glance (~0.5s) produces minimal drift
- [ ] Sustained mirror stare (~3s+) produces noticeable lane departure
- [ ] Mouse is captured (cursor not visible), ESC frees it

---

## Phase 4: Traffic System

### Overview
Add AI vehicles that follow road paths, obey traffic lights, and react to the player. A TrafficManager spawns and despawns vehicles around the player.

### Changes Required

#### 1. Traffic Vehicle Script ✅
**File**: `scripts/traffic/traffic_vehicle.gd` (new)

```gdscript
class_name TrafficVehicle
extends CharacterBody3D

enum State { DRIVING, BRAKING, STOPPED, TURNING }

var _state: State = State.DRIVING
var _current_speed: float = 0.0
var _target_speed: float = 13.4     # road speed limit
var _path_points: PackedVector3Array # lane points to follow
var _path_index: int = 0            # current target point
var _assigned_road: RoadSegment = null

const ACCELERATION := 6.0
const BRAKE_DECEL := 12.0
const STOP_DISTANCE := 3.0          # distance to stop before obstacle
const HONK_COOLDOWN := 5.0          # seconds between honks
```

**Node structure** (per vehicle):
```
TrafficVehicle (CharacterBody3D)
├── CollisionShape3D (BoxShape3D, car-sized)
├── CarMesh (MeshInstance3D - simple box with car-like proportions)
│   ├── Headlights (2x SpotLight3D - white, forward-facing)
│   └── Taillights (2x OmniLight3D - red, small range, rear)
├── FrontRay (RayCast3D - forward, detects obstacles/player)
├── TrafficLightRay (RayCast3D - longer range, detects approaching intersection)
└── HornAudio (AudioStreamPlayer3D)
```

**AI behavior state machine**:

`DRIVING`:
- Follow path points: steer toward `_path_points[_path_index]`, advance index when close enough
- Maintain `_target_speed` (road speed limit with slight random variation ±10%)
- Transition to `BRAKING` if `FrontRay` detects obstacle within `STOP_DISTANCE * 2`
- Transition to `BRAKING` if approaching intersection with red/yellow light

`BRAKING`:
- Decelerate toward 0
- Transition to `STOPPED` when speed < 0.1
- Transition to `DRIVING` if obstacle clears or light turns green

`STOPPED`:
- Wait. Check each frame if path is clear and light is green
- Transition to `DRIVING` when clear
- If stopped behind player for > 3 seconds, honk (play HornAudio)

`TURNING`:
- Active during intersection traversal
- Follow turn path points through the intersection
- Reduced speed (5 m/s)
- Transition to `DRIVING` when through intersection and on next road

**Steering logic**:
- Direction to next path point: `(target_point - global_position).normalized()`
- Rotate toward that direction using `lerp_angle` on `rotation.y`
- `velocity = -transform.basis.z * _current_speed`
- `move_and_slide()`

**Player detection and reaction**:
- `FrontRay` hits player car → brake and eventually stop
- If stopped behind player > 3s → honk
- If player cuts off (detected by sudden FrontRay hit at close range) → honk immediately

#### 2. Traffic Manager Script ✅
**File**: `scripts/traffic/traffic_manager.gd` (new)

```gdscript
class_name TrafficManager
extends Node

@export var max_vehicles: int = 12
@export var spawn_radius: float = 120.0     # spawn this far from player
@export var despawn_radius: float = 160.0   # despawn when this far from player
@export var spawn_interval: float = 2.0     # seconds between spawn attempts

var _active_vehicles: Array[TrafficVehicle] = []
var _spawn_timer: float = 0.0
var _vehicle_scene: PackedScene  # preloaded traffic vehicle scene
var _road_network: RoadNetwork
var _player_car: CharacterBody3D
```

**Spawn logic**:
- Every `spawn_interval` seconds, if `_active_vehicles.size() < max_vehicles`:
  - Pick a random road segment
  - Pick a random lane and position on that road
  - Check position is within `spawn_radius` of player but not within 30m (don't spawn on top of player)
  - Check no other vehicle within 10m of spawn point (prevent overlap)
  - Instance vehicle, assign lane path points, add to scene

**Despawn logic**:
- Every frame, check each active vehicle
- If distance to player > `despawn_radius`, queue_free and remove from array

**Road assignment**:
- When spawning, assign the vehicle a road and lane
- Generate path points for that lane using `road.get_lane_points()`
- When vehicle reaches end of road, query `RoadNetwork` for connected roads at the intersection and assign a new road (random turn or straight)

#### 3. Traffic Vehicle Scene ✅
**File**: `scenes/traffic/traffic_vehicle.tscn` (new)
**Changes**: PackedScene for the traffic vehicle

Car visual: A simple elongated box mesh (~4.5m x 1.5m x 2.0m) with:
- Random color from a pool of muted colors (dark blue, dark green, dark red, gray, black, white)
- 2 SpotLight3D headlights (white, cone forward, 15m range)
- 2 small OmniLight3D taillights (red, 2m range)
- BoxShape3D collision slightly smaller than visual

#### 4. Integrate Traffic into Game ✅
**File**: `scenes/main/game.tscn`
**Changes**: Add TrafficManager as a child of Game root

**File**: `scenes/main/game.gd`
**Changes**:
- `@onready var traffic_manager: TrafficManager = $TrafficManager`
- In `_ready()`, pass references: `traffic_manager.initialize(road_network, car_interior)`
- No other changes needed — traffic is autonomous

#### 5. Traffic Light Visuals ✅
**File**: `scripts/road/intersection.gd`
**Changes**: Add visual light meshes that change color on state transitions

Each intersection with `has_traffic_light == true` creates child nodes:
- A vertical pole (thin CylinderMesh)
- A light housing (BoxMesh, dark gray)
- 3 sphere indicators (green/yellow/red) using emissive materials
- Only the active state's sphere has emission enabled; others are dark

### Success Criteria

#### Manual Verification
- [ ] AI vehicles appear on roads as the player drives around
- [ ] AI vehicles drive in lanes at approximately the speed limit
- [ ] AI vehicles stop at red traffic lights
- [ ] AI vehicles proceed on green
- [ ] AI vehicles brake when approaching another stopped vehicle
- [ ] AI vehicles brake when the player's car is in front of them
- [ ] AI vehicles honk after being stuck behind the player for ~3 seconds
- [ ] Vehicles spawn around the player and despawn when far away (no pop-in too close)
- [ ] No vehicles spawn on top of the player or each other
- [ ] Vehicles have headlights and taillights visible at night
- [ ] Performance: steady 60fps with 10-12 active AI vehicles
- [ ] Vehicles navigate through intersections (turn or go straight)
- [ ] No vehicles driving through buildings or off roads

---

## Phase 5: Passenger System Overhaul

### Overview
Add procedural passenger generation with behavior vectors and archetype matching. Passengers are picked up and dropped off at physical locations on the road network. Passenger visuals are black billboard quads. Procedural passengers have minimal dialogue (greeting + destination confirmation only). Narrative passengers continue to work as before.

### Changes Required

#### 1. Behavior Vector and Archetype Data ✅
**File**: `resources/passenger_data.gd`
**Changes**: Add behavior vector fields and archetype

Add these exports to the existing resource:
```gdscript
# -- Behavior Vector --
@export_group("Behavior Vector")
@export_range(0.0, 1.0) var talkativeness: float = 0.5
@export_range(0.0, 1.0) var nervousness: float = 0.3
@export_range(0.0, 1.0) var aggression: float = 0.2
@export_range(0.0, 1.0) var threat: float = 0.0   # hidden from player

# -- Archetype --
@export_group("Archetype")
@export var archetype: String = ""  # empty = no archetype (raw vector)
@export var is_procedural: bool = false

# -- Physical Locations --
@export_group("Locations")
@export var pickup_world_position: Vector3 = Vector3.ZERO
@export var destination_world_position: Vector3 = Vector3.ZERO
```

#### 2. Archetype Definitions ✅
**File**: `scripts/archetype_registry.gd` (new)

```gdscript
class_name ArchetypeRegistry
extends RefCounted

# Centroid format: [talkativeness, nervousness, aggression]
# Threat is independent of archetypes
const ARCHETYPES := {
	"chatterbox":       { "centroid": Vector3(0.9, 0.3, 0.2), "threshold": 0.25 },
	"silent_type":      { "centroid": Vector3(0.1, 0.2, 0.1), "threshold": 0.2 },
	"nervous_one":      { "centroid": Vector3(0.3, 0.9, 0.1), "threshold": 0.25 },
	"backseat_driver":  { "centroid": Vector3(0.7, 0.2, 0.8), "threshold": 0.25 },
	"shady_fare":       { "centroid": Vector3(0.2, 0.5, 0.4), "threshold": 0.2 },
}

static func match_archetype(talk: float, nerv: float, aggr: float) -> String:
	var best_match := ""
	var best_distance := INF
	for archetype_name in ARCHETYPES:
		var data: Dictionary = ARCHETYPES[archetype_name]
		var centroid: Vector3 = data["centroid"]
		var threshold: float = data["threshold"]
		var vec := Vector3(talk, nerv, aggr)
		var dist := vec.distance_to(centroid)
		if dist <= threshold and dist < best_distance:
			best_distance = dist
			best_match = archetype_name
	return best_match  # empty string if no match
```

#### 3. Procedural Passenger Generator ✅
**File**: `scripts/procedural_passenger_generator.gd` (new)

```gdscript
class_name ProceduralPassengerGenerator
extends RefCounted

const FIRST_NAMES := [
	"Marcus", "Elena", "DeShawn", "Rachel", "Carlos",
	"Megan", "Andre", "Lisa", "Jordan", "Kim",
	"Trevor", "Aisha", "Brandon", "Sarah", "Diego",
	"Nicole", "Jamal", "Katie", "Tyler", "Maria"
]

var _road_network: RoadNetwork
var _used_names: Array[String] = []

func generate(road_network: RoadNetwork) -> PassengerData:
	_road_network = road_network
	var p := PassengerData.new()

	# Identity
	p.id = "proc_%s" % str(randi())
	p.display_name = _pick_name()
	p.is_procedural = true

	# Behavior vector — random with slight clustering
	p.talkativeness = clampf(randfn(0.5, 0.25), 0.0, 1.0)
	p.nervousness = clampf(randfn(0.4, 0.25), 0.0, 1.0)
	p.aggression = clampf(randfn(0.3, 0.2), 0.0, 1.0)
	p.threat = clampf(randfn(0.15, 0.15), 0.0, 1.0)  # most passengers are low-threat

	# Archetype matching
	p.archetype = ArchetypeRegistry.match_archetype(
		p.talkativeness, p.nervousness, p.aggression
	)

	# Physical locations — random road positions
	var pickup := road_network.get_random_road_position()
	var destination := road_network.get_random_road_position()
	# Ensure pickup and destination are different roads
	while destination["road"] == pickup["road"]:
		destination = road_network.get_random_road_position()

	p.pickup_location = pickup["road"].road_name + " & " + _nearest_cross_street(pickup)
	p.destination = destination["road"].road_name + " & " + _nearest_cross_street(destination)
	p.pickup_world_position = pickup["position"]
	p.destination_world_position = destination["position"]
	p.destination_exists = true

	# Dialogue — minimal for procedural
	p.dialogue_nodes = _generate_minimal_dialogue(p)

	# Procedural passengers are always refusable
	p.is_refusable = true
	p.is_mandatory = false

	return p
```

**Minimal dialogue generation** (`_generate_minimal_dialogue`):
Creates 2 dialogue nodes:
1. Greeting on boarding: "Hey." / "Thanks for coming." / "Hi." (randomly selected, weighted by talkativeness — talkative passengers say more)
2. Destination confirmation: "{destination}, right?" / silent (low talkativeness passengers skip this)

#### 4. Update Passenger Manager ✅
**File**: `scripts/passenger_manager.gd`
**Changes**: Integrate narrative status function and procedural generation

```gdscript
var _procedural_generator: ProceduralPassengerGenerator
var _road_network: RoadNetwork

func initialize(road_network: RoadNetwork) -> void:
	_road_network = road_network
	_procedural_generator = ProceduralPassengerGenerator.new()

func get_next_passenger() -> PassengerData:
	# 1. Evaluate narrative status function
	var narrative_probability := _calculate_narrative_probability()
	var roll := randf()

	# 2. If roll lands in narrative range, try to get a narrative passenger
	if roll < narrative_probability:
		var narrative := _get_eligible_narrative_passenger()
		if narrative:
			_assign_world_positions(narrative)
			return narrative

	# 3. Otherwise, generate procedural
	return _procedural_generator.generate(_road_network)
```

**Narrative status function** (`_calculate_narrative_probability`):
```gdscript
func _calculate_narrative_probability() -> float:
	var night := GameState.current_night
	var rides := GameState.rides_completed
	var since_last_narrative := rides - GameState.last_narrative_ride_number

	# Base probability increases with night progression
	var base := remap(float(night), 1.0, 14.0, 0.1, 0.5)

	# Increase if it's been a while since last narrative passenger
    var urgency := clampf(float(since_last_narrative) / 5.0, 0.0, 0.3)

    return clampf(base + urgency, 0.0, 0.8)
```

**`_assign_world_positions(passenger: PassengerData)`**: For narrative passengers that have text-based locations but no world positions, pick random road positions and assign them.

#### 5. GameState Additions ✅
**File**: `autoloads/game_state.gd`
**Changes**: Add fields needed by narrative status function

```gdscript
var current_night: int = 1
var last_narrative_ride_number: int = 0
```

Update `complete_ride()` to track whether the ride was narrative:
```gdscript
func complete_ride(passenger_id: String, is_narrative: bool = false) -> void:
    # existing logic...
    if is_narrative:
        last_narrative_ride_number = rides_completed
```

#### 6. Passenger Billboard Visual ✅
**File**: `scripts/passenger_billboard.gd` (new)

```gdscript
class_name PassengerBillboard
extends MeshInstance3D

func _ready() -> void:
    # Create a simple quad mesh
    var quad := QuadMesh.new()
    quad.size = Vector2(0.6, 1.5)  # roughly person-shaped proportions
    mesh = quad

    # Black material
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.02, 0.02, 0.02)  # near-black
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material_override = mat

    # Billboard mode — always faces camera
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
```

#### 7. Pickup/Dropoff Markers ✅
**File**: `scripts/pickup_marker.gd` (new)

A simple visual indicator placed at pickup/destination world positions so the player can find them:

```gdscript
class_name PickupMarker
extends Node3D

@export var marker_color: Color = Color(0.2, 0.8, 0.2)  # green for pickup
var _billboard: PassengerBillboard  # only at pickup, not at destination

func _ready() -> void:
    # Glowing ground circle
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
```

Pickup marker: green circle + passenger billboard standing nearby
Destination marker: blue circle only (passenger exits here)

### Success Criteria

#### Manual Verification
- [ ] Procedural passengers are generated with random names and behavior vectors
- [ ] Archetype matching works (a passenger with talkativeness=0.9, nervousness=0.3, aggression=0.2 gets "chatterbox")
- [ ] Passengers with vectors outside all archetype thresholds have no archetype (empty string)
- [ ] Ride requests show procedural passenger info (name, pickup, destination)
- [ ] Narrative passengers still appear based on conditions and flags
- [ ] Narrative probability increases over game progression
- [ ] Pickup location shows a green circle marker and black billboard quad
- [ ] Destination shows a blue circle marker
- [ ] Billboard passenger faces the camera (billboard mode)
- [ ] Procedural passengers say a minimal greeting when ride starts
- [ ] Existing narrative passenger dialogue still works correctly

---

## Phase 6: Integration & Game Loop

### Overview
Wire all systems together into a complete ride loop: ride request → drive to physical pickup → proximity triggers boarding → drive to destination → proximity triggers dropoff. Replace all temporary stubs from Phase 1.

### Changes Required

#### 1. Proximity Detection System ✅
**File**: `scripts/proximity_detector.gd` (new)

```gdscript
class_name ProximityDetector
extends Area3D

signal target_reached

@export var trigger_radius: float = 5.0

var _target_position: Vector3 = Vector3.ZERO
var _is_active: bool = false

func set_target(world_pos: Vector3) -> void:
    _target_position = world_pos
    global_position = world_pos
    _is_active = true

func clear_target() -> void:
    _is_active = false
```

Uses `Area3D` with a `CollisionShape3D` (SphereShape3D, radius = `trigger_radius`). When the player's car enters the area, `target_reached` emits.

Alternatively, a simpler distance check in `_physics_process`:
```gdscript
func _physics_process(_delta: float) -> void:
	if not _is_active:
		return
	var car := get_tree().get_first_node_in_group("car_interior")
	if car and car.global_position.distance_to(_target_position) < trigger_radius:
		# Only trigger if car is nearly stopped (speed < 2 m/s)
		if car.get_speed() < 2.0:
			_is_active = false
			target_reached.emit()
```

The speed check ensures the player actually stops at the pickup/destination rather than driving through at full speed.

#### 2. Game Script Overhaul ✅
**File**: `scenes/main/game.gd`
**Changes**: Replace temporary Phase 1 stubs with real proximity-based flow

Remove temporary Y-key arrival triggering from `_unhandled_input`.

Add proximity detectors:
```gdscript
@onready var pickup_detector: ProximityDetector = $PickupDetector
@onready var destination_detector: ProximityDetector = $DestinationDetector
```

Updated phase transitions:

**PICKING_UP**:
```gdscript
GamePhase.PICKING_UP:
	GameState.set_shift_state(GameState.ShiftState.PICKING_UP)
	# Place pickup marker and detector at passenger's world position
    var pickup_pos: Vector3 = _current_passenger_data.pickup_world_position
    _spawn_pickup_marker(pickup_pos)
    pickup_detector.set_target(pickup_pos)
    phone.show_notification("Drive to pickup: %s" % _current_passenger_data.pickup_location)
    # GPS shows direction to pickup
    gps.set_destination(_current_passenger_data.pickup_location)
    # Wait for player to arrive (proximity)
    await pickup_detector.target_reached
    _remove_pickup_marker()
    # Passenger boards
    _spawn_passenger_billboard()
    phone.show_notification("%s has entered the vehicle." % _current_passenger_data.display_name)
    await get_tree().create_timer(1.0).timeout
    _transition_to(GamePhase.IN_RIDE)
```

**IN_RIDE**:
```gdscript
GamePhase.IN_RIDE:
    GameState.set_shift_state(GameState.ShiftState.IN_RIDE)
    _ride_timer = 0.0
    # Place destination marker and detector
    var dest_pos: Vector3 = _current_passenger_data.destination_world_position
    _spawn_destination_marker(dest_pos)
    destination_detector.set_target(dest_pos)
    # GPS shows direction to destination
    gps.set_destination(_current_passenger_data.destination)
    # Start dialogue
    _start_passenger_dialogue()
    # Destination arrival is detected by proximity_detector signal
    # (connected in _connect_signals)
```

**Signal connections** update:
```gdscript
func _connect_signals() -> void:
    phone.ride_accepted.connect(_on_ride_accepted)
    phone.ride_refused.connect(_on_ride_refused)
    dialogue_box.dialogue_finished.connect(_on_dialogue_finished)
    destination_detector.target_reached.connect(_on_destination_reached)
    gps.destination_reached.connect(_on_gps_arrival)
    # Remove: car_interior.destination_reached connection (no longer exists)
```

**`_on_destination_reached`** now handles the IN_RIDE→DROPPING_OFF transition only:
```gdscript
func _on_destination_reached() -> void:
    if current_phase == GamePhase.IN_RIDE:
        _remove_destination_marker()
        _transition_to(GamePhase.DROPPING_OFF)
```

#### 3. Marker Spawning Helpers ✅
**File**: `scenes/main/game.gd`
**Changes**: Add methods to spawn/remove pickup and destination markers

```gdscript
var _active_pickup_marker: PickupMarker = null
var _active_destination_marker: PickupMarker = null
var _active_passenger_billboard: PassengerBillboard = null

func _spawn_pickup_marker(pos: Vector3) -> void:
    _active_pickup_marker = PickupMarker.new()
    _active_pickup_marker.marker_color = Color(0.2, 0.8, 0.2)  # green
    add_child(_active_pickup_marker)
    _active_pickup_marker.global_position = pos

func _remove_pickup_marker() -> void:
    if _active_pickup_marker:
        _active_pickup_marker.queue_free()
        _active_pickup_marker = null

func _spawn_destination_marker(pos: Vector3) -> void:
    _active_destination_marker = PickupMarker.new()
    _active_destination_marker.marker_color = Color(0.3, 0.5, 1.0)  # blue
    add_child(_active_destination_marker)
    _active_destination_marker.global_position = pos

func _remove_destination_marker() -> void:
    if _active_destination_marker:
        _active_destination_marker.queue_free()
        _active_destination_marker = null

func _spawn_passenger_billboard() -> void:
    _active_passenger_billboard = PassengerBillboard.new()
    car_interior.seat_passenger(_active_passenger_billboard)
```

#### 4. GPS Integration ✅
**File**: `scenes/ui/gps.gd`
**Changes**: Add ability to show distance and direction to a world position

```gdscript
var _target_world_position: Vector3 = Vector3.ZERO
var _has_target: bool = false

func set_destination_position(dest_name: String, world_pos: Vector3) -> void:
    set_destination(dest_name)
    _target_world_position = world_pos
    _has_target = true

func _process(delta: float) -> void:
    # existing glitch logic...
    if _has_target and _current_state == GPSState.NORMAL:
        var car := get_tree().get_first_node_in_group("car_interior")
        if car:
            var dist := car.global_position.distance_to(_target_world_position)
            var dist_display := "%.0fm" % dist if dist < 1000 else "%.1fkm" % (dist / 1000.0)
            _eta_label.text = dist_display
```

This updates the ETA label to show real distance to the destination instead of a random fake ETA.

#### 5. Passenger Manager Initialization ✅
**File**: `scenes/main/game.gd`
**Changes**: Pass road network reference to passenger manager

```gdscript
func _ready() -> void:
    _setup_gps_screen()
    _connect_signals()
    passenger_manager.initialize($TestArea/RoadNetwork)
    _start_game()
```

#### 6. Game Scene Updates ✅
**File**: `scenes/main/game.tscn`
**Changes**:
- Add `PickupDetector` (ProximityDetector) as child of Game
- Add `DestinationDetector` (ProximityDetector) as child of Game
- Ensure CarInterior starting position is on a road in the test area

#### 7. Dropping Off Cleanup ✅
**File**: `scenes/main/game.gd`
**Changes**: Update DROPPING_OFF phase to handle billboard cleanup

```gdscript
GamePhase.DROPPING_OFF:
    GameState.set_shift_state(GameState.ShiftState.DROPPING_OFF)
    gps.arrive()

    # Apply flags from this passenger
    for flag in _current_passenger_data.sets_flags:
        GameState.set_flag(flag)

    var is_narrative := not _current_passenger_data.is_procedural
    GameState.complete_ride(_current_passenger_data.id, is_narrative)
    car_interior.remove_passenger()  # removes billboard
    phone.show_notification("Ride complete.")

    GameState.advance_time(randf_range(0.75, 1.5))

    await get_tree().create_timer(2.0).timeout

    if GameState.is_shift_complete():
        _transition_to(GamePhase.ENDING)
    else:
        _transition_to(GamePhase.BETWEEN_RIDES)
```

### Success Criteria

#### Manual Verification
- [ ] Accept a ride → green pickup marker appears in the world
- [ ] GPS shows distance to pickup that decreases as you drive toward it
- [ ] Arriving at pickup (within 5m, nearly stopped) triggers passenger boarding
- [ ] Black billboard quad appears in the passenger seat
- [ ] Pickup marker disappears, blue destination marker appears
- [ ] GPS switches to showing distance to destination
- [ ] Dialogue plays during the ride (narrative passengers)
- [ ] Arriving at destination triggers dropoff
- [ ] Billboard disappears, destination marker disappears
- [ ] Ride complete notification shows
- [ ] Next ride request appears after cooldown
- [ ] Full loop works: accept → drive → pickup → drive → dropoff → repeat
- [ ] Both procedural and narrative passengers work in the loop
- [ ] Shift ends correctly after completing required rides
- [ ] Traffic AI continues working during ride loop
- [ ] Camera/attention system works during ride loop (drift still applies)
- [ ] No errors in the output console during a full ride cycle

---

## Testing Strategy

### Per-Phase Manual Testing

Each phase has its own success criteria above. After each phase, run the game and verify all criteria before moving to the next phase.

### Full Integration Test (after Phase 6)

Complete ride loop test:
1. Launch game
2. Receive ride request on phone
3. Accept ride
4. Drive through test area to green pickup marker
5. Stop at pickup — passenger billboard boards
6. Drive to blue destination marker while dialogue plays
7. Stop at destination — passenger exits
8. Receive next ride request
9. Repeat for 3 rides until shift ends
10. Verify ending screen appears

Traffic interaction test:
1. During a ride, encounter AI traffic at an intersection
2. Wait at a red light, observe AI also stopped
3. When green, proceed through intersection
4. Cut off an AI vehicle, verify it honks
5. Stop in a lane, verify AI behind you stops and eventually honks

Camera/attention test:
1. While driving at speed, hold R to look at rearview mirror
2. Observe car gradually drifting from lane
3. Release R, correct steering
4. Hold T to look at phone, observe drift in different direction
5. Quick glance at mirror (~0.5s) — verify minimal drift

## Performance Considerations

- **Traffic vehicles**: Max 12 active at once, spawned/despawned based on distance. Each is a simple box mesh with 2 lights. Should be well within budget.
- **Road mesh**: Generated once at scene load, not every frame. Static geometry.
- **Camera zones**: Simple rotation lerp, no render target overhead (mirrors are placeholder).
- **Proximity detection**: Simple distance checks, not physics queries. Runs only when a target is active.
- **Passenger generation**: Happens once per ride request. Negligible cost.

## File Summary

### New Files (16)
| File | Purpose |
|---|---|
| `scripts/road/road_segment.gd` | Path3D-based road with lane metadata |
| `scripts/road/intersection.gd` | Traffic light cycling at road junctions |
| `scripts/road/road_network.gd` | Manages all roads, provides queries |
| `scripts/road/road_mesh_generator.gd` | Generates road surface meshes from paths |
| `scripts/traffic/traffic_vehicle.gd` | AI vehicle with path-following and state machine |
| `scripts/traffic/traffic_manager.gd` | Spawns/despawns AI vehicles around player |
| `scripts/camera_controller.gd` | Hybrid zone-based camera with mouse fine-adjust |
| `scripts/archetype_registry.gd` | Behavior vector archetype centroid matching |
| `scripts/procedural_passenger_generator.gd` | Generates random passengers with vectors |
| `scripts/passenger_billboard.gd` | Black billboard quad for passenger visual |
| `scripts/pickup_marker.gd` | Glowing ground circle for pickup/destination |
| `scripts/proximity_detector.gd` | Detects when car arrives at a target position |
| `scenes/world/test_area.tscn` | 4-block road network with buildings and lights |
| `scenes/traffic/traffic_vehicle.tscn` | Traffic vehicle packed scene |
| `scenes/world/pickup_marker.tscn` | Pickup marker packed scene (optional, can be code-only) |
| `scenes/world/destination_marker.tscn` | Destination marker packed scene (optional) |

### Modified Files (7)
| File | Changes |
|---|---|
| `project.godot` | Add input actions (accelerate, brake, handbrake, shift_forward, shift_reverse, look_phone), remap interact to F |
| `scenes/main/car_interior.gd` | Complete rewrite: CharacterBody3D vehicle controller |
| `scenes/main/car_interior.tscn` | Change root to CharacterBody3D, add collision, remove EnvironmentMover, replace camera with CameraController |
| `scenes/main/game.gd` | Proximity-based ride loop, marker spawning, remove on-rails references, add road network and traffic manager refs |
| `scenes/main/game.tscn` | Add TestArea, TrafficManager, ProximityDetectors, remove temp ground plane |
| `scenes/ui/gps.gd` | Add real distance display from world position |
| `scripts/passenger_manager.gd` | Add procedural generation, narrative status function, road network integration |
| `resources/passenger_data.gd` | Add behavior vector, archetype, is_procedural, world position fields |
| `autoloads/game_state.gd` | Add current_night, last_narrative_ride_number, update complete_ride |

## References

- Game design document: `last-fare/last-fare.md`
- Implementation specification: `last-fare/implementation.md`
- Existing game script: `scenes/main/game.gd`
- Existing car controller: `scenes/main/car_interior.gd`
- Existing passenger data: `resources/passenger_data.gd`
- Existing passenger manager: `scripts/passenger_manager.gd`
