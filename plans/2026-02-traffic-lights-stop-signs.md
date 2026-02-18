# Traffic Lights & Stop Signs — Implementation Plan

## Overview

Implement functional traffic regulation for the player vehicle: traffic lights already exist for AI but have no player consequence; stop signs don't exist at all. This plan adds player violation detection for both traffic lights (running a red) and stop signs (rolling through without slowing), plus a flashing UI indicator when violations occur.

## Current State Analysis

- **Traffic lights** fully implemented in `intersection.gd` with GREEN/YELLOW/RED cycling across two road groups. AI vehicles obey them via `_should_stop_for_light()` in `traffic_vehicle.gd`. Procedural visuals (poles + emissive spheres) generated at runtime.
- **Player** can drive through red lights with zero feedback or consequence.
- **Stop signs** do not exist anywhere in the codebase.
- **UI** has a `CanvasLayer` ("UILayer") with Labels for speedometer/RPM/gear, plus Phone, DialogueBox, FadeOverlay, and PauseMenu. No violation indicator exists.
- **Collision layers**: Player car = layer 2, AI traffic = layer 4. Area3D detection zones can mask to layer 2 to detect only the player.

### Key File References
- `scripts/road/intersection.gd` — traffic light state machine + procedural visuals
- `scripts/traffic/traffic_vehicle.gd` — AI driving, light obedience
- `scripts/road/road_network.gd` — adjacency graph, road/intersection queries
- `scripts/road/road_segment.gd` — lane geometry, `road_group` assignment
- `scenes/world/test_area.gd` — procedural 3x3 grid builder
- `scenes/main/game.gd` — game loop, phase management, UI wiring
- `scenes/main/game.tscn` — scene tree with UILayer

## Desired End State

After implementation:
1. Every intersection has either a traffic light (with red/yellow/green cycle) or a stop sign — configurable per intersection via an `IntersectionType` enum.
2. Traffic light intersections display **physically visible 3D light fixtures** — poles, housing boxes, three colored light spheres (red/yellow/green), and an `OmniLight3D` that casts the active color onto the road surface below. The active light changes color as the state cycles.
3. Stop sign intersections display procedural red sign faces on poles with white borders.
4. AI vehicles stop briefly at stop signs (~1.5s) then proceed.
5. When the player drives through a red traffic light, a red "RED LIGHT" indicator flashes at the top-center of the screen for ~3 seconds.
6. When the player drives through a stop sign intersection at >5 mph without slowing sufficiently, a red "STOP SIGN" indicator flashes identically.
7. Four corner intersections in the test area are stop signs; the remaining five keep traffic lights.

### Verification
- Drive through a red light → indicator flashes "RED LIGHT"
- Drive through a green light → no indicator
- Drive through a yellow light → no indicator
- Slow to <5 mph at a stop sign then proceed → no indicator
- Blast through a stop sign at speed → indicator flashes "STOP SIGN"
- AI vehicles stop at stop signs for ~1.5s then continue
- AI vehicles still obey traffic lights as before (no regression)

## What We're NOT Doing

- No scoring, penalty, or fare deduction for violations (visual only per user request)
- No police pursuit or escalation system
- No collision/accident response system
- No violation audio (horn, siren, etc.)
- No new road segments or grid expansion
- No stop line road markings (future enhancement)
- No pedestrian crosswalk logic

## Implementation Approach

Five phases, each independently testable:

1. **Extend Intersection** — Add `IntersectionType` enum, stop sign visuals, and an Area3D detection zone to every intersection.
2. **AI Stop Sign Behavior** — Teach traffic vehicles to stop briefly at stop signs then proceed.
3. **Violation Detection** — New `ViolationDetector` script monitors player entry into intersection zones and checks conditions.
4. **Violation Indicator UI** — Flashing label at screen top-center, triggered by ViolationDetector signal.
5. **Integration & Test Area** — Wire everything into `game.gd`/`game.tscn`, assign stop signs to corner intersections.

---

## Phase 1: Extend Intersection for Stop Signs + Detection Zones

### Overview
Refactor `Intersection` to support both traffic lights and stop signs via an enum. Add procedural stop sign visuals. Add an Area3D detection zone to every intersection (regardless of type) for player violation detection.

### Changes Required:

#### 1. `scripts/road/intersection.gd`

**Remove** the `has_traffic_light` boolean export. **Add** `IntersectionType` enum and detection zone.

**Full replacement of the file** (annotated with changes):

```gdscript
class_name Intersection
extends Node3D
## Manages traffic control at a junction — either a traffic light or a stop sign.

signal light_changed(road_group: int, new_state: LightState)
signal zone_entered(body: Node3D)

enum LightState { GREEN, YELLOW, RED }
enum IntersectionType { NONE, TRAFFIC_LIGHT, STOP_SIGN }

@export var intersection_type: IntersectionType = IntersectionType.TRAFFIC_LIGHT
@export var green_duration: float = 15.0
@export var yellow_duration: float = 3.0
@export var detection_zone_size: float = 12.0  # meters, width/depth of detection area

var _light_states: Dictionary[int, LightState] = {}
var _cycle_timer: float = 0.0
var _current_green_group: int = 0
var _in_yellow: bool = false

# Visual nodes
var _light_meshes: Dictionary[int, Dictionary] = {}
var _cast_lights: Dictionary[int, OmniLight3D] = {}  # group_idx -> OmniLight3D casting color onto road


func _ready() -> void:
	_light_states[0] = LightState.GREEN
	_light_states[1] = LightState.RED

	match intersection_type:
		IntersectionType.TRAFFIC_LIGHT:
			_build_traffic_light_visuals()
			_update_light_visuals()
		IntersectionType.STOP_SIGN:
			_build_stop_sign_visuals()

	_build_detection_zone()


func _process(delta: float) -> void:
	if intersection_type != IntersectionType.TRAFFIC_LIGHT:
		return

	_cycle_timer += delta

	if _in_yellow:
		if _cycle_timer >= yellow_duration:
			_cycle_timer = 0.0
			_in_yellow = false
			_light_states[_current_green_group] = LightState.RED
			_current_green_group = 1 - _current_green_group
			_light_states[_current_green_group] = LightState.GREEN
			light_changed.emit(_current_green_group, LightState.GREEN)
			light_changed.emit(1 - _current_green_group, LightState.RED)
			_update_light_visuals()
	else:
		if _cycle_timer >= green_duration:
			_cycle_timer = 0.0
			_in_yellow = true
			_light_states[_current_green_group] = LightState.YELLOW
			light_changed.emit(_current_green_group, LightState.YELLOW)
			_update_light_visuals()


func get_light_state_for_group(group: int) -> LightState:
	if intersection_type == IntersectionType.STOP_SIGN:
		return LightState.RED
	if intersection_type == IntersectionType.NONE:
		return LightState.GREEN
	if _light_states.has(group):
		return _light_states[group] as LightState
	return LightState.RED


func get_light_state(road: RoadSegment) -> LightState:
	return get_light_state_for_group(road.road_group)


func is_stop_sign() -> bool:
	return intersection_type == IntersectionType.STOP_SIGN


func _build_detection_zone() -> void:
	var area := Area3D.new()
	area.name = "DetectionZone"
	area.collision_layer = 0
	area.collision_mask = 2  # Only detect player car (layer 2)
	area.monitorable = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(detection_zone_size, 2.0, detection_zone_size)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)  # Centered at car height
	area.add_child(shape)
	add_child(area)

	area.body_entered.connect(_on_zone_body_entered)


func _on_zone_body_entered(body: Node3D) -> void:
	zone_entered.emit(body)


func _build_stop_sign_visuals() -> void:
	# Place stop signs at two diagonal corners (matching traffic light pole pattern)
	var offsets: Array[Vector2] = [Vector2(6.0, 6.0), Vector2(-6.0, -6.0)]

	for offset in offsets:
		# Pole
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.06
		pole_mesh.bottom_radius = 0.06
		pole_mesh.height = 3.0
		pole.mesh = pole_mesh
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.3, 0.3, 0.3)
		pole.material_override = pole_mat
		pole.position = Vector3(offset.x, 1.5, offset.y)
		add_child(pole)

		# Sign face — flat red rectangle approximating octagonal stop sign
		var sign_face := MeshInstance3D.new()
		var sign_mesh := BoxMesh.new()
		sign_mesh.size = Vector3(0.65, 0.65, 0.05)
		sign_face.mesh = sign_mesh
		var sign_mat := StandardMaterial3D.new()
		sign_mat.albedo_color = Color(0.85, 0.1, 0.1)
		sign_mat.emission_enabled = true
		sign_mat.emission = Color(0.6, 0.05, 0.05)
		sign_mat.emission_energy_multiplier = 0.5
		sign_face.material_override = sign_mat
		sign_face.position = Vector3(offset.x, 3.2, offset.y)
		add_child(sign_face)

		# White border (slightly larger box behind the red face)
		var border := MeshInstance3D.new()
		var border_mesh := BoxMesh.new()
		border_mesh.size = Vector3(0.75, 0.75, 0.04)
		border.mesh = border_mesh
		var border_mat := StandardMaterial3D.new()
		border_mat.albedo_color = Color(0.9, 0.9, 0.9)
		border.material_override = border_mat
		border.position = Vector3(offset.x, 3.2, offset.y - 0.01 * signf(offset.y))
		add_child(border)


# -- Traffic light visual methods (enhanced with OmniLight3D for road illumination) --

func _build_traffic_light_visuals() -> void:
	for group_idx in 2:
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.08
		pole_mesh.bottom_radius = 0.08
		pole_mesh.height = 4.0
		pole.mesh = pole_mesh
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.2, 0.2, 0.2)
		pole.material_override = pole_mat
		var offset_x: float = 6.0 if group_idx == 0 else -6.0
		var offset_z: float = 6.0 if group_idx == 0 else -6.0
		pole.position = Vector3(offset_x, 2.0, offset_z)
		add_child(pole)

		var housing := MeshInstance3D.new()
		var housing_mesh := BoxMesh.new()
		housing_mesh.size = Vector3(0.4, 1.2, 0.4)
		housing.mesh = housing_mesh
		var housing_mat := StandardMaterial3D.new()
		housing_mat.albedo_color = Color(0.15, 0.15, 0.15)
		housing.material_override = housing_mat
		housing.position = Vector3(offset_x, 4.3, offset_z)
		add_child(housing)

		var light_data: Dictionary = {}
		var light_configs: Array = [
			["red", 0.35, Color(1.0, 0.1, 0.1)],
			["yellow", 0.0, Color(1.0, 0.9, 0.1)],
			["green", -0.35, Color(0.1, 1.0, 0.2)],
		]
		for config in light_configs:
			var light_name: String = config[0]
			var y_off: float = config[1]
			var col: Color = config[2]

			var sphere := MeshInstance3D.new()
			var sphere_mesh := SphereMesh.new()
			sphere_mesh.radius = 0.12
			sphere_mesh.height = 0.24
			sphere.mesh = sphere_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.05, 0.05, 0.05)
			mat.emission_enabled = false
			sphere.material_override = mat
			sphere.position = Vector3(offset_x, 4.3 + y_off, offset_z)
			sphere.set_meta("emission_color", col)
			add_child(sphere)
			light_data[light_name] = sphere

		_light_meshes[group_idx] = light_data

		# Cast light — an OmniLight3D positioned below the housing that casts
		# the active light color onto the road surface. Color updated in _update_light_visuals().
		var cast_light := OmniLight3D.new()
		cast_light.name = "CastLight_%d" % group_idx
		cast_light.position = Vector3(offset_x, 3.5, offset_z)
		cast_light.light_color = Color(0.1, 1.0, 0.2)  # Initial: green (group 0) or red (group 1)
		cast_light.omni_range = 8.0
		cast_light.light_energy = 0.6
		cast_light.shadow_enabled = false
		cast_light.distance_fade_enabled = true
		cast_light.distance_fade_begin = 40.0
		cast_light.distance_fade_length = 10.0
		add_child(cast_light)
		_cast_lights[group_idx] = cast_light


func _update_light_visuals() -> void:
	for group_idx in _light_meshes:
		var meshes: Dictionary = _light_meshes[group_idx]
		var state: LightState = _light_states.get(group_idx, LightState.RED) as LightState
		var active_name: String
		match state:
			LightState.GREEN:
				active_name = "green"
			LightState.YELLOW:
				active_name = "yellow"
			LightState.RED:
				active_name = "red"
			_:
				active_name = "red"

		for light_name: String in meshes:
			var sphere: MeshInstance3D = meshes[light_name]
			var mat: StandardMaterial3D = sphere.material_override as StandardMaterial3D
			if mat == null:
				continue
			if light_name == active_name:
				var col: Color = sphere.get_meta("emission_color") as Color
				mat.albedo_color = col
				mat.emission_enabled = true
				mat.emission = col
				mat.emission_energy_multiplier = 2.0
			else:
				mat.albedo_color = Color(0.05, 0.05, 0.05)
				mat.emission_enabled = false

		# Update the cast light color to match the active state
		if _cast_lights.has(group_idx):
			var cast_light: OmniLight3D = _cast_lights[group_idx]
			match state:
				LightState.GREEN:
					cast_light.light_color = Color(0.1, 1.0, 0.2)
				LightState.YELLOW:
					cast_light.light_color = Color(1.0, 0.9, 0.1)
				LightState.RED:
					cast_light.light_color = Color(1.0, 0.1, 0.1)
```

### Success Criteria:

#### Manual Verification:
- [ ] Traffic lights display physically visible 3D light fixtures (poles, housing, colored spheres)
- [ ] Each traffic light casts colored light onto the road surface via OmniLight3D (green glow when green, red glow when red, yellow glow when yellow)
- [ ] Light color changes in sync with the sphere emission state during cycling
- [ ] Intersections with `STOP_SIGN` type display red sign on pole at two diagonal corners
- [ ] Intersections with `NONE` type display no control signage
- [ ] No console errors or warnings at startup

**Implementation Note**: After completing this phase, pause for manual verification before proceeding.

---

## Phase 2: AI Stop Sign Behavior

### Overview
Teach AI traffic vehicles to stop at stop sign intersections for ~1.5 seconds, then proceed. Currently, `get_light_state()` returns RED for stop signs, so AI will brake — but they'll never resume because the "light" never turns green. This phase adds per-vehicle tracking of cleared stop signs.

### Changes Required:

#### 1. `scripts/traffic/traffic_vehicle.gd`

**Add** new state variables at the top (after existing vars):

```gdscript
var _cleared_intersections: Dictionary = {}  # Intersection -> true (stop signs already stopped at)
```

**Rename** `_should_stop_for_light()` to `_should_stop_at_intersection()` and add stop sign clearing logic:

```gdscript
func _should_stop_at_intersection() -> bool:
	if not _road_network or not _assigned_road:
		return false

	var intersection: Intersection = _road_network.get_road_end_intersection(
		_assigned_road, _assigned_direction
	)
	if not intersection:
		return false

	var to_intersection: Vector3 = intersection.global_position - global_position
	var dist: float = to_intersection.length()

	if dist < STOP_DISTANCE or dist > 15.0:
		return false

	var forward: Vector3 = -transform.basis.z
	if forward.dot(to_intersection.normalized()) < 0.0:
		return false

	# Stop signs: check if already cleared
	if intersection.is_stop_sign():
		return not _cleared_intersections.has(intersection)

	# Traffic lights: stop if not green
	var light_state: Intersection.LightState = intersection.get_light_state(_assigned_road)
	return light_state != Intersection.LightState.GREEN
```

**Update** all references from `_should_stop_for_light()` to `_should_stop_at_intersection()` (3 call sites in `_process_driving`, `_process_braking`, `_process_stopped`).

**Add** stop sign clearing logic to `_process_stopped()` — insert before the existing "can resume" check:

```gdscript
func _process_stopped(delta: float) -> void:
	_stopped_timer += delta

	# Clear stop sign after waiting
	if _stopped_timer > 1.5:
		var intersection: Intersection = _road_network.get_road_end_intersection(
			_assigned_road, _assigned_direction
		)
		if intersection and intersection.is_stop_sign():
			_cleared_intersections[intersection] = true

	# Check if can resume (existing logic)
	var obstacle_clear: bool = true
	if front_ray and front_ray.is_colliding():
		var dist: float = global_position.distance_to(front_ray.get_collision_point())
		if dist < STOP_DISTANCE * 2.5:
			obstacle_clear = false

	if obstacle_clear and not _should_stop_at_intersection():
		_state = State.DRIVING
		_stopped_timer = 0.0
		return

	# Honk logic (existing, unchanged)
	if _stopped_timer > 3.0 and _honk_cooldown <= 0.0:
		if front_ray and front_ray.is_colliding():
			var collider: Object = front_ray.get_collider()
			if collider and collider.is_in_group("car_interior"):
				_honk()
```

**Clear** the dictionary when transitioning to a new road — add to `_try_next_road()`:

```gdscript
func _try_next_road() -> void:
	# ... existing code to find next road ...

	_assigned_road = next_road
	_assigned_direction = next_dir
	_target_speed = next_road.speed_limit * randf_range(0.9, 1.1)
	_path_points = next_road.get_lane_points(0, next_dir, 40)
	_path_index = 0
	_state = State.TURNING
	_cleared_intersections.clear()  # <-- ADD THIS LINE
```

### Success Criteria:

#### Manual Verification:
- [ ] AI vehicles approaching a stop sign intersection brake to a stop
- [ ] After ~1.5 seconds stopped, AI vehicles resume driving through the intersection
- [ ] AI vehicles still obey traffic lights as before (no regression)
- [ ] AI vehicles don't stop at the same stop sign repeatedly when looping back on a different road
- [ ] No vehicles stuck permanently at stop signs

**Implementation Note**: After completing this phase, pause for manual verification before proceeding.

---

## Phase 3: Violation Detection System

### Overview
Create a new `ViolationDetector` node that monitors intersection detection zones and checks whether the player committed a violation (ran a red light or blew through a stop sign).

### Changes Required:

#### 1. New file: `scripts/traffic/violation_detector.gd`

```gdscript
class_name ViolationDetector
extends Node
## Monitors player entry into intersection zones and detects traffic violations.

signal violation_detected(violation_type: String)

const STOP_SPEED_THRESHOLD: float = 2.2  # m/s (~5 mph)
const VIOLATION_COOLDOWN: float = 5.0    # seconds before same intersection can trigger again

var _player: CharacterBody3D = null
var _road_network: RoadNetwork = null
var _cooldowns: Dictionary = {}  # Intersection -> float (remaining cooldown)


func initialize(network: RoadNetwork, player: CharacterBody3D) -> void:
	_road_network = network
	_player = player

	for intersection: Intersection in network.get_intersections():
		intersection.zone_entered.connect(_on_intersection_zone_entered.bind(intersection))


func _physics_process(delta: float) -> void:
	# Tick down cooldowns
	var to_remove: Array[Intersection] = []
	for intersection: Intersection in _cooldowns:
		_cooldowns[intersection] = (_cooldowns[intersection] as float) - delta
		if (_cooldowns[intersection] as float) <= 0.0:
			to_remove.append(intersection)
	for intersection in to_remove:
		_cooldowns.erase(intersection)


func _on_intersection_zone_entered(body: Node3D, intersection: Intersection) -> void:
	if body != _player:
		return

	# Skip if on cooldown for this intersection
	if _cooldowns.has(intersection):
		return

	match intersection.intersection_type:
		Intersection.IntersectionType.TRAFFIC_LIGHT:
			_check_red_light(intersection)
		Intersection.IntersectionType.STOP_SIGN:
			_check_stop_sign(intersection)


func _check_red_light(intersection: Intersection) -> void:
	# Determine which road the player is on
	var player_road: RoadSegment = _road_network.get_nearest_road(_player.global_position)
	if not player_road:
		return

	var light_state: Intersection.LightState = intersection.get_light_state(player_road)
	if light_state == Intersection.LightState.RED:
		_cooldowns[intersection] = VIOLATION_COOLDOWN
		violation_detected.emit("RED LIGHT")


func _check_stop_sign(intersection: Intersection) -> void:
	var speed: float = _player.get_speed()
	if speed > STOP_SPEED_THRESHOLD:
		_cooldowns[intersection] = VIOLATION_COOLDOWN
		violation_detected.emit("STOP SIGN")
```

### Success Criteria:

#### Manual Verification:
- [ ] Driving through a red light prints/signals "RED LIGHT" violation (verify via debugger or temporary print)
- [ ] Driving through a green light does NOT trigger a violation
- [ ] Driving through a yellow light does NOT trigger a violation
- [ ] Rolling through a stop sign at >5 mph triggers "STOP SIGN" violation
- [ ] Slowing to <5 mph at a stop sign then proceeding does NOT trigger violation
- [ ] Same intersection does not re-trigger within 5 seconds (cooldown)

**Implementation Note**: After completing this phase, pause for manual verification before proceeding.

---

## Phase 4: Violation Indicator UI

### Overview
Create a flashing label at the top-center of the screen that displays violation text ("RED LIGHT" or "STOP SIGN") and auto-dismisses after ~3 seconds.

### Changes Required:

#### 1. New file: `scripts/ui/violation_indicator.gd`

```gdscript
class_name ViolationIndicator
extends Label
## Flashing violation indicator shown at top of screen.

var _flash_timer: float = 0.0

const FLASH_DURATION: float = 3.0
const FLASH_SPEED: float = 6.0  # Hz


func _ready() -> void:
	visible = false


func flash(violation_text: String) -> void:
	text = violation_text
	_flash_timer = FLASH_DURATION
	visible = true


func _process(delta: float) -> void:
	if _flash_timer <= 0.0:
		return

	_flash_timer -= delta

	if _flash_timer <= 0.0:
		visible = false
		modulate.a = 1.0
		return

	# Oscillate alpha for flash effect
	var t: float = _flash_timer * FLASH_SPEED * TAU
	modulate.a = 0.4 + 0.6 * absf(sin(t))
```

### Success Criteria:

#### Manual Verification:
- [ ] Calling `flash("TEST")` shows a flashing red label at top-center of screen
- [ ] Label flashes visibly (alpha oscillation) for ~3 seconds
- [ ] Label disappears after the flash duration
- [ ] Calling flash again while already flashing resets the timer and updates text

**Implementation Note**: After completing this phase, pause for manual verification before proceeding.

---

## Phase 5: Game Integration & Test Area Configuration

### Overview
Wire ViolationDetector and ViolationIndicator into the game scene tree. Assign stop signs to the four corner intersections in the test area.

### Changes Required:

#### 1. `scenes/main/game.tscn`

**Add** a ViolationDetector node and ViolationIndicator label:

```
[node name="ViolationDetector" type="Node" parent="."]
script = <violation_detector.gd script resource>

[node name="ViolationIndicator" type="Label" parent="UILayer"]
unique_name_in_owner = true
layout_mode = 3
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -150.0
offset_top = 20.0
offset_right = 150.0
offset_bottom = 65.0
theme_override_colors/font_color = Color(1.0, 0.15, 0.15, 1.0)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 3
theme_override_font_sizes/font_size = 32
horizontal_alignment = 1
text = ""
visible = false
script = <violation_indicator.gd script resource>
```

#### 2. `scenes/main/game.gd`

**Add** `@onready` references and initialization:

```gdscript
# Add to existing @onready declarations:
@onready var violation_detector: ViolationDetector = $ViolationDetector
@onready var violation_indicator: ViolationIndicator = %ViolationIndicator
```

**Add** to `_ready()`, after `traffic_manager.initialize(...)`:

```gdscript
violation_detector.initialize(road_network, car_interior)
```

**Add** to `_connect_signals()`:

```gdscript
violation_detector.violation_detected.connect(_on_violation_detected)
```

**Add** signal callback:

```gdscript
func _on_violation_detected(violation_type: String) -> void:
	violation_indicator.flash(violation_type)
```

#### 3. `scenes/world/test_area.gd`

**Modify** `_build_intersections()` to assign stop signs to corner intersections:

```gdscript
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
```

### Success Criteria:

#### Manual Verification:
- [ ] Game starts without errors
- [ ] 4 corner intersections display stop signs (red rectangles on poles)
- [ ] 5 remaining intersections display traffic lights with cycling colors
- [ ] Driving through a red traffic light → "RED LIGHT" flashes at top-center for ~3 seconds
- [ ] Driving through a green/yellow traffic light → no indicator
- [ ] Rolling through a stop sign at speed → "STOP SIGN" flashes at top-center for ~3 seconds
- [ ] Slowing below ~5 mph at a stop sign then proceeding → no indicator
- [ ] AI vehicles stop at stop signs, wait ~1.5s, then proceed
- [ ] AI vehicles still obey traffic lights correctly
- [ ] No duplicate violations within 5 seconds at the same intersection
- [ ] Indicator is readable against all backgrounds (black outline on red text)

---

## File Summary

| File | Action | Lines Changed (est.) |
|------|--------|---------------------|
| `scripts/road/intersection.gd` | Rewrite | ~220 (was 152) |
| `scripts/traffic/traffic_vehicle.gd` | Modify | ~30 lines changed/added |
| `scripts/traffic/violation_detector.gd` | **New** | ~70 lines |
| `scripts/ui/violation_indicator.gd` | **New** | ~30 lines |
| `scenes/main/game.gd` | Modify | ~10 lines added |
| `scenes/main/game.tscn` | Modify | ~20 lines added |
| `scenes/world/test_area.gd` | Modify | ~10 lines changed |

**Total**: ~390 lines across 7 files (2 new, 5 modified).

## Testing Strategy

### Manual Testing Steps:
1. Launch game, verify all 9 intersections render correctly (5 lights, 4 stop signs)
2. Drive to a traffic light intersection, wait for red, drive through → verify flash
3. Wait for green, drive through → verify no flash
4. Drive to a corner stop sign at full speed → verify flash
5. Drive to a corner stop sign, brake to near-stop, then proceed → verify no flash
6. Observe AI traffic at both intersection types for correct behavior
7. Trigger multiple violations rapidly at the same intersection → verify cooldown prevents spam

## Performance Considerations

- **Area3D detection zones**: 9 zones total, negligible physics overhead. Only monitor collision_mask=2 (single body).
- **ViolationDetector `_physics_process`**: Iterates cooldown dictionary (max 9 entries). Negligible cost.
- **Stop sign visuals**: 4 intersections x 6 meshes each = 24 additional MeshInstance3D nodes. Negligible.
- **Traffic light OmniLight3D nodes**: 10 total (2 per traffic light intersection x 5 intersections). All have `distance_fade_enabled = true` (begin=40m, length=10m) so they cull at distance. Negligible GPU cost.
- **No per-frame distance calculations** for violation detection — event-driven via Area3D signals.

## References

- Current intersection implementation: `scripts/road/intersection.gd:1-152`
- AI light obedience: `scripts/traffic/traffic_vehicle.gd:175-199`
- Test area grid builder: `scenes/world/test_area.gd:72-82`
- UI layer structure: `scenes/main/game.tscn:21-88`
- Previous traffic fixes: `plans/2026-02-traffic-system-fixes.md`
