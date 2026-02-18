# Passenger Sidewalk Pickup + Rearview Mirror Implementation Plan

## Overview

Augment the passenger pickup system so the NPC is visible standing on the sidewalk at the pickup location, walks toward the car when the player arrives, and teleports to the backseat. Implement a functional rearview mirror that renders the backseat and rear view of the car via a SubViewport camera mapped onto a box mesh.

## Current State Analysis

- **PhasePickingUp** (`scripts/game_phases/phase_picking_up.gd`): Spawns a ground marker and GPS route. When the player arrives (proximity detector triggers at speed < 2.0 m/s), instantly spawns a `PassengerBillboard` directly into the car's `PassengerSeat` marker. No NPC visible beforehand.
- **PassengerBillboard** (`scripts/passenger_billboard.gd`): A 0.6x1.5 black unshaded `QuadMesh` with `BILLBOARD_ENABLED`. Used as the in-car passenger representation.
- **PassengerSeat** (`car_interior.tscn`): `Marker3D` at `(0.6, 0.8, -0.5)` relative to `CarMesh` -- this is effectively the **front passenger seat** position (Z=-0.5 is forward of car center since -Z is the car's forward direction).
- **RearviewMirror** (`car_interior.tscn`): Empty `Node3D` placeholder at `(0, 1.4, 0.5)` with no children, mesh, camera, or functionality.
- **CameraController** (`scripts/camera_controller.gd`): Has `Zone.REARVIEW` with `look_mirror` input, but this only rotates the driver's head -- no actual mirror rendering exists.
- **Pickup positions** are computed by `RoadNetwork.get_random_road_position()` which returns positions on the road surface, offset by half a lane width from the centerline. No sidewalk offset is computed.

### Key Discoveries:
- Car coordinate system: forward = -Z (`car_interior.gd:249`), so +Z = backward
- CameraController at `(0, 1.1, 0.2)` = driver's eyes, slightly behind center
- PassengerSeat at `(0.6, 0.8, -0.5)` = front-right seat (needs to move to backseat)
- GPS screen uses SubViewport pattern in `game.gd:53-62` -- we follow this for rearview
- Billboard mode is evaluated per-rendering-camera in Godot 4, so the NPC will correctly face both the main camera and the rearview camera in their respective render passes
- Phase states access game via `game: Node` (dynamically typed) -- existing pattern used throughout

## Desired End State

1. When a ride is accepted and the player enters the PICKING_UP phase, a black billboard NPC stands on the sidewalk near the pickup marker, visible as the player drives toward the location.
2. When the player arrives and stops, the NPC walks from the sidewalk to the car's right (passenger) side at walking speed (~1.8 m/s).
3. Upon reaching the car door, the sidewalk NPC is removed and a PassengerBillboard appears in the backseat.
4. A rearview mirror (small rectangular box mesh at the top of the windshield area) displays a SubViewport camera feed showing the backseat and the road behind the car.
5. The seated NPC is visible in the rearview mirror.

### Verification:
- NPC visible on sidewalk before player arrives at pickup
- NPC walks to car after player stops, then teleports to backseat
- Rearview mirror renders backseat + road behind in real-time
- NPC visible in rearview after seating

## What We're NOT Doing

- No NPC 3D models or walk animations (keeping billboard quads)
- No side mirrors (left/right mirror rendering)
- No door open/close animations or sounds
- No changes to the CameraController's REARVIEW zone behavior (still head-turn)
- No changes to proximity detector, phone UI, or GPS system
- No changes to the passenger billboard visual style

## Implementation Approach

Two independent phases. Phase 1 (rearview) builds the rendering infrastructure and moves the passenger to the backseat. Phase 2 (sidewalk NPC) augments the pickup flow. Phase 1 is done first because it's independent and testable with the existing instant-seat system.

---

## Phase 1: Rearview Mirror System

### Overview
Move the PassengerSeat to the backseat. Build the rearview mirror rendering pipeline: SubViewport with shared World3D, Camera3D positioned at the mirror looking backward, BoxMesh with viewport texture.

### Changes Required:

#### 1. Car Interior Scene -- Move PassengerSeat + Add Rearview Nodes
**File**: `scenes/main/car_interior.tscn`

- [x] **Change 1a**: Update `load_steps` from `10` to `11` (adding one BoxMesh sub_resource for the mirror).

- [x] **Change 1b**: Add mirror BoxMesh sub_resource after the existing sub_resources:
```
[sub_resource type="BoxMesh" id="BoxMesh_mirror"]
size = Vector3(0.22, 0.07, 0.015)
```

- [x] **Change 1c**: Move PassengerSeat to the backseat. Change transform from:
```
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.6, 0.8, -0.5)
```
to:
```
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.3, 0.8, 1.0)
```
This places the passenger slightly right of center (X=0.3), at seat height (Y=0.8), behind the driver (Z=1.0, which is backward since +Z = backward in car space).

- [x] **Change 1d**: Add child nodes under the existing `RearviewMirror` node:
```
[node name="MirrorMesh" type="MeshInstance3D" parent="CarMesh/RearviewMirror"]
mesh = SubResource("BoxMesh_mirror")

[node name="RearviewViewport" type="SubViewport" parent="CarMesh/RearviewMirror"]
gui_disable_input = true
size = Vector2i(200, 100)
render_target_update_mode = 4

[node name="RearviewCamera" type="Camera3D" parent="CarMesh/RearviewMirror/RearviewViewport"]
fov = 60.0
```

The `RearviewCamera` inside the `RearviewViewport` will automatically become the current camera for that SubViewport. `render_target_update_mode = 4` (ALWAYS) keeps the mirror updating every frame. `gui_disable_input = true` prevents the SubViewport from intercepting mouse input.

#### 2. Car Interior Script -- Rearview Setup and Per-Frame Update
**File**: `scenes/main/car_interior.gd`

- [x] **Change 2a**: Add `@onready` references after the existing ones (after line 70):
```gdscript
@onready var _rearview_viewport: SubViewport = $CarMesh/RearviewMirror/RearviewViewport
@onready var _rearview_camera: Camera3D = $CarMesh/RearviewMirror/RearviewViewport/RearviewCamera
@onready var _mirror_mesh: MeshInstance3D = $CarMesh/RearviewMirror/MirrorMesh
```

- [x] **Change 2b**: In `_ready()`, add rearview setup call after the existing code:
```gdscript
func _ready() -> void:
	add_to_group("car_interior")
	if steering_wheel:
		_steering_base_transform = steering_wheel.transform
	_setup_rearview()
```

- [x] **Change 2c**: Add `_setup_rearview()` method:
```gdscript
func _setup_rearview() -> void:
	## Share the main viewport's World3D so the rearview camera sees the game scene.
	_rearview_viewport.world_3d = get_viewport().world_3d
	## Apply viewport texture to mirror mesh (same pattern as GPS screen in game.gd).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.4
	var vp_tex: ViewportTexture = _rearview_viewport.get_texture()
	mat.albedo_texture = vp_tex
	mat.emission_texture = vp_tex
	_mirror_mesh.material_override = mat
```

- [x] **Change 2d**: Add `_update_rearview()` call in `_physics_process()`:
```gdscript
func _physics_process(delta: float) -> void:
	_read_input(delta)
	_update_transmission(delta)
	_update_speed(delta)
	_update_rpm(delta)
	_update_steering(delta)
	_apply_movement(delta)
	_update_visuals()
	_update_rearview()
```

- [x] **Change 2e**: Add `_update_rearview()` method:
```gdscript
func _update_rearview() -> void:
	if not _rearview_camera:
		return
	## Position the camera at the mirror location in world space, looking backward.
	## The Camera3D is inside the SubViewport so its global_transform is in the
	## shared World3D coordinate space -- we update it manually each frame.
	var cam_pos: Vector3 = car_mesh.global_transform * Vector3(0.0, 1.4, 0.48)
	_rearview_camera.global_position = cam_pos
	## Look backward (+Z in car space) and slightly down to see passenger + road behind.
	var look_target: Vector3 = car_mesh.global_transform * Vector3(0.0, 1.0, 10.0)
	_rearview_camera.look_at(look_target, Vector3.UP)
```

Explanation of the look target: `Vector3(0.0, 1.0, 10.0)` in car local space is far behind the car (Z=10.0 = backward) and slightly below the camera (Y=1.0 vs camera Y=1.4). This tilts the view down just enough to include the passenger at `(0.3, 0.8, 1.0)` in the lower portion of the mirror, while the road behind fills the upper portion.

### Success Criteria:

#### Manual Verification:
- [ ] A small rectangular mirror mesh is visible at the top-center of the car interior
- [ ] The mirror displays a live camera feed (not black/blank)
- [ ] The mirror shows the road/environment behind the car, updating as the car moves and turns
- [ ] When a passenger is seated (instant-spawn still works at this phase), the passenger billboard is visible in the mirror
- [ ] The mirror does not flicker or cause visual artifacts
- [ ] No noticeable frame rate drop from the extra SubViewport render pass

**Implementation Note**: After completing this phase and all verification passes, pause here for manual confirmation that the rearview mirror renders correctly before proceeding to Phase 2.

---

## Phase 2: Sidewalk NPC + Walk-to-Car Animation

### Overview
Spawn the passenger billboard on the sidewalk at the pickup location when the PICKING_UP phase begins. After the player arrives, animate the NPC walking toward the car's passenger door. Upon arrival, remove the sidewalk NPC and seat them in the backseat.

### Changes Required:

#### 1. Add Sidewalk Position Helper to RoadNetwork
**File**: `scripts/road/road_network.gd`

- [x] Add after the existing `_closest_point_on_road()` method (after line 215):

```gdscript
func get_sidewalk_position(world_pos: Vector3, offset_distance: float = 3.5) -> Vector3:
	## Returns a position further from the road centerline, simulating a sidewalk.
	## Takes a world position on or near a road and extends it away from the centerline
	## by offset_distance meters.
	var road: RoadSegment = get_nearest_road(world_pos)
	if not road:
		return world_pos
	var centerline_pos: Vector3 = _closest_point_on_road(road, world_pos)
	var away_from_road: Vector3 = world_pos - centerline_pos
	away_from_road.y = 0.0
	if away_from_road.length() < 0.01:
		return world_pos
	return centerline_pos + away_from_road.normalized() * (away_from_road.length() + offset_distance)
```

This works by:
1. Finding the nearest road to the pickup position
2. Finding the closest point on that road's centerline
3. Computing the vector from centerline to the pickup position (perpendicular to the road)
4. Extending that vector further by `offset_distance` (3.5m) to place the NPC on the sidewalk

#### 2. Rework PhasePickingUp for Sidewalk NPC + Walk Animation
**File**: `scripts/game_phases/phase_picking_up.gd`

- [x] Replace the entire file content:

```gdscript
class_name PhasePickingUp
extends GamePhaseState

signal _npc_arrived

const NPC_WALK_SPEED: float = 1.8  ## m/s (~4 mph walking pace)
const NPC_ARRIVE_DISTANCE: float = 1.5  ## meters from car door to trigger entry

var _sidewalk_npc: Node3D = null
var _npc_approaching: bool = false


func enter() -> void:
	active = true
	_npc_approaching = false
	GameState.set_shift_state(GameState.ShiftState.PICKING_UP)
	var passenger: PassengerData = game.current_passenger_data
	var pickup_pos: Vector3 = passenger.pickup_world_position

	# Spawn pickup marker and sidewalk NPC
	game.spawn_pickup_marker(pickup_pos)
	_spawn_sidewalk_npc(pickup_pos)
	game.pickup_detector.set_target(pickup_pos)
	game.phone.show_notification("Drive to pickup: %s" % passenger.pickup_location)
	game.gps.set_destination_position(passenger.pickup_location, pickup_pos)

	# Wait for player to arrive at pickup
	await game.pickup_detector.target_reached
	if not active:
		return

	# Player arrived -- NPC begins approaching the car
	game.remove_pickup_marker()
	game.phone.show_notification("%s is approaching..." % passenger.display_name)
	_npc_approaching = true

	# Wait for NPC to reach the car door
	await _npc_arrived
	if not active:
		return

	# NPC enters the car
	_remove_sidewalk_npc()
	game.spawn_passenger_billboard()
	game.phone.show_notification("%s has entered the vehicle." % passenger.display_name)

	var tree: SceneTree = game.get_tree()
	await tree.create_timer(1.0).timeout
	if not active:
		return
	game.transition_to_phase(game.GamePhase.IN_RIDE)


func process(delta: float) -> void:
	if not _npc_approaching or not _sidewalk_npc:
		return
	# Move NPC toward the car's passenger door each frame
	var door_pos: Vector3 = _get_car_door_position()
	var to_door: Vector3 = door_pos - _sidewalk_npc.global_position
	to_door.y = 0.0  # Keep movement horizontal
	if to_door.length() < NPC_ARRIVE_DISTANCE:
		_npc_approaching = false
		_npc_arrived.emit()
		return
	_sidewalk_npc.global_position += to_door.normalized() * NPC_WALK_SPEED * delta


func exit() -> void:
	active = false
	_npc_approaching = false
	_remove_sidewalk_npc()


func _spawn_sidewalk_npc(pickup_pos: Vector3) -> void:
	var sidewalk_pos: Vector3 = game.road_network.get_sidewalk_position(pickup_pos)
	# Place billboard center at half-height above ground so the bottom touches the ground
	sidewalk_pos.y = pickup_pos.y + 0.75
	_sidewalk_npc = PassengerBillboard.new()
	game.add_child(_sidewalk_npc)
	_sidewalk_npc.global_position = sidewalk_pos


func _remove_sidewalk_npc() -> void:
	if _sidewalk_npc:
		_sidewalk_npc.queue_free()
		_sidewalk_npc = null


func _get_car_door_position() -> Vector3:
	var car: CharacterBody3D = game.car_interior as CharacterBody3D
	# Passenger door is on the right side (+X in car's local space), offset ~1.5m from center
	var right: Vector3 = car.global_transform.basis.x.normalized()
	return car.global_position + right * 1.5
```

Key design decisions:
- **process() for walk animation**: Uses the phase state's `process(delta)` (called every frame by `game.gd:80-81`) to move the NPC toward the car. This is more robust than a Tween because it tracks the car's current position each frame.
- **_npc_arrived signal**: Used with `await` to pause the `enter()` coroutine until the NPC reaches the car. This keeps the sequential flow readable.
- **exit() cleanup**: If the phase is exited early (e.g., game ending), the sidewalk NPC is cleaned up and the approach state is reset.
- **Horizontal movement**: `to_door.y = 0.0` prevents the NPC from floating up/down toward the car's Y position during the walk.
- **Car door position**: Computed from the car's current global transform so the NPC always walks toward the car even if it drifts slightly.

### Success Criteria:

#### Manual Verification:
- [ ] When a ride is accepted and the player enters PICKING_UP, a black billboard NPC is visible on the sidewalk near the pickup marker
- [ ] The NPC is visibly offset from the road surface, standing to the side
- [ ] When the player arrives and stops at the pickup spot, the NPC begins walking toward the car's right side
- [ ] The NPC walk takes approximately 2-4 seconds depending on distance
- [ ] After reaching the car door, the NPC disappears from the sidewalk and appears in the backseat (visible in rearview mirror from Phase 1)
- [ ] Notification flow shows "Drive to pickup" -> "[name] is approaching..." -> "[name] has entered the vehicle"
- [ ] If the player drives away during NPC approach (before NPC arrives), the NPC continues walking but phase cleanup handles it on phase exit
- [ ] The rearview mirror shows the NPC approaching from behind the car (the sidewalk NPC is in the shared world, so the rearview camera picks it up)
- [ ] Multiple sequential rides work correctly (no leftover NPCs)

**Implementation Note**: After completing this phase, test at least 3 consecutive ride cycles to verify no state leaks or cleanup issues.

---

## Testing Strategy

### Manual Testing Steps:
1. Start the game, accept a ride request
2. Drive toward the pickup location -- verify the NPC billboard is visible on the sidewalk before arriving
3. Glance at the rearview mirror while approaching -- the NPC may be visible behind/beside the car
4. Stop at the pickup marker -- verify the NPC walks toward the right side of the car
5. Watch the rearview mirror as the NPC approaches from behind
6. After the NPC enters -- verify they appear in the backseat position (visible in rearview)
7. Complete the ride (drive to destination) -- verify NPC is removed from backseat on drop-off
8. Accept another ride -- repeat steps 2-7 to verify no stale NPCs
9. Accept a ride and then refuse it (if refusable) -- verify no sidewalk NPC lingers
10. Accept a ride, drive near the pickup, then drive away before fully stopping -- verify cleanup

### Edge Cases:
- Player drives away after triggering proximity but before NPC reaches car
- Phase transition during NPC approach (e.g., game ending triggers)
- Pickup position very close to road centerline (minimal perpendicular offset)
- Multiple rapid ride accept/refuse cycles

---

## Performance Considerations

- **SubViewport overhead**: The rearview mirror adds one extra 3D render pass at 200x100 resolution. This is small (~1/50th of a 1080p frame) and should have negligible performance impact. If performance becomes an issue, `render_target_update_mode` can be changed from `4` (ALWAYS) to `2` (ONCE) with manual `queue_update()` calls at a lower rate.
- **Camera cull mask**: The rearview camera uses the default cull mask (all visual layers). This can be restricted if only specific objects need to be visible in the mirror.
- **Billboard rendering**: The PassengerBillboard uses `BILLBOARD_ENABLED` which is evaluated per-camera, so it correctly faces both the main camera and the rearview camera independently. No additional cost.

---

## File Change Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `scenes/main/car_interior.tscn` | Modified | Move PassengerSeat to backseat, add mirror BoxMesh + SubViewport + Camera3D |
| `scenes/main/car_interior.gd` | Modified | Add rearview setup, per-frame camera update, new @onready vars |
| `scripts/road/road_network.gd` | Modified | Add `get_sidewalk_position()` helper method |
| `scripts/game_phases/phase_picking_up.gd` | Rewritten | Sidewalk NPC spawn, walk animation, signal-based entry flow |

No new files are created. All changes modify existing files.

---

## References

- Current pickup flow: `scripts/game_phases/phase_picking_up.gd`
- Car scene structure: `scenes/main/car_interior.tscn`
- GPS SubViewport pattern (material setup): `scenes/main/game.gd:53-62`
- Road position API: `scripts/road/road_network.gd:101-119`
- PassengerBillboard visual: `scripts/passenger_billboard.gd`
- Car movement direction: `scenes/main/car_interior.gd:249` (`forward = -transform.basis.z`)
- Phase state lifecycle: `scripts/game_phases/game_phase_state.gd`
