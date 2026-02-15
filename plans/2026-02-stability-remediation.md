# Last Fare Stability Remediation Plan

## Overview

Remediate all crash bugs, type safety violations, silent failures, and structural issues identified in the foundational audit. Also refactor `game.gd` into a proper state machine and add the missing pause menu.

## Current State Analysis

The game has solid architectural bones (signal-based coupling, data-driven dialogue, flag-based narrative branching) but contains:
- **4 crash-level bugs** that will surface during playtesting
- **~12 type safety violations** that conflict with the warnings-as-errors policy
- **~8 silent failure paths** that will make debugging painful
- **1 monolithic state controller** (`game.gd:_transition_to()`) that will resist scaling
- **1 missing feature** (pause menu) where the input mapping exists but no handler does

### Key Discoveries:
- `dialogue_box.gd:211-213` — trigger split on `":"` assumes index `[1]` exists
- `dialogue_box.gd:95-98` — recursive `advance()` on condition failure, unbounded depth
- `audio_manager.gd:108` — typed loop over `Dictionary.values()` (returns Variant array)
- `intersection.gd:141` — `as StandardMaterial3D` with no null guard
- `dialogue_node.gd:16` — `Array[Resource]` instead of `Array[DialogueChoice]`
- `procedural_passenger_generator.gd:93-94` — returns `Array[Resource]` instead of `Array[DialogueNode]`
- `game.gd:91-176` — 85-line match statement managing all phase transitions
- `game.gd:23` — 5-level deep `@onready` path to GPS node
- `road_network.gd:44-61` — returns untyped Dictionary, callers need unsafe casts

## Desired End State

After this plan:
1. Zero crash paths in dialogue, audio, or intersection systems
2. All variables, parameters, and return types have explicit annotations compatible with warnings-as-errors
3. All failure paths log warnings instead of silently continuing
4. `game.gd` uses a state machine with discrete phase classes
5. `RoadNetwork` returns typed inner classes instead of Dictionaries
6. A functional pause menu exists
7. All `@onready` node references use `%UniqueNodeName` or groups instead of deep paths

### Verification:
- Open the project in Godot 4.5 with no warnings/errors in the Output panel
- Run the game, complete a full ride cycle (offer -> pickup -> ride -> dropoff)
- Trigger dialogue with choices, verify no crash on trigger parsing
- Press Escape to pause and resume
- Look at rearview mirror during a ride (tests camera drift + lane wander)

## What We're NOT Doing

- Spatial indexing for RoadNetwork (grid is small enough for now)
- Save/load system
- GPS turn-by-turn pathfinding
- Passenger visual variety (portraits/models)
- Pickup/destination reachability validation

## Implementation Approach

Six phases, ordered by dependency:
1. **Crash fixes** — immediate safety, no structural changes
2. **Type safety** — annotation fixes across all files
3. **Error handling** — add logging to silent failure paths
4. **RoadNetwork data classes** — replace Dictionary returns with typed inner classes
5. **Game state machine** — refactor game.gd into phase state objects
6. **Pause menu** — add the missing pause overlay

---

## Phase 1: Critical Crash Fixes

### Overview
Fix 4 bugs that will crash during normal gameplay.

### Changes Required:

#### 1. ~~Fix trigger parsing crash~~ [x]
**File**: `scenes/ui/dialogue_box.gd`
**Lines**: 209-213

The current code splits on `":"` and directly accesses `parts[1]`. A trigger string like `"gps"` with no colon will index out of bounds. The code already handles this on line 213 with a ternary, but the `split` with `max_split=1` means this is actually safe for the split itself — however, triggers with no parameter (e.g. a bare action) still need the empty-string fallback to be reliable. The real risk is if `parts` is empty (empty string input).

```gdscript
# Replace lines 209-213:
func _fire_triggers(triggers: Array) -> void:
	for trigger: String in triggers:
		if trigger.is_empty():
			continue
		var parts := trigger.split(":", true, 1)
		var action := parts[0]
		var param := parts[1] if parts.size() > 1 else ""
```

#### 2. ~~Fix recursive advance() stack overflow~~ [x]
**File**: `scenes/ui/dialogue_box.gd`
**Lines**: 94-98

Replace recursion with a loop. When a conditional node is skipped, the current code calls `advance()` recursively. A chain of N failing conditional nodes = N stack frames.

```gdscript
# Replace the advance() method (lines 61-108) — the condition-skip logic becomes a loop:
func advance(target_id: String = "") -> void:
	_clear_choices()
	_waiting_for_choice = false
	_auto_advance_timer = 0.0

	var next_node: DialogueNode = null
	var max_skips: int = 100  # Safety limit

	while max_skips > 0:
		max_skips -= 1
		next_node = null

		if not target_id.is_empty():
			next_node = _node_map.get(target_id)
			target_id = ""  # Only use target_id on first iteration
		else:
			# Try current node's next_node first
			if _current_index >= 0 and _current_index < _current_nodes.size():
				var current: DialogueNode = _current_nodes[_current_index] as DialogueNode
				if current and not current.next_node.is_empty():
					next_node = _node_map.get(current.next_node)

			# Otherwise advance sequentially
			if next_node == null:
				_current_index += 1
				if _current_index < _current_nodes.size():
					next_node = _current_nodes[_current_index] as DialogueNode

		if next_node == null:
			_end_dialogue()
			return

		# Update index to match this node
		for i in _current_nodes.size():
			if _current_nodes[i] == next_node:
				_current_index = i
				break

		# Check condition — if fails, loop to skip this node
		if not GameState.evaluate_condition(next_node.condition):
			continue

		# Node passes condition — display it
		break

	if next_node == null:
		push_warning("DialogueBox: Exhausted skip limit, ending dialogue")
		_end_dialogue()
		return

	# Fire triggers
	_fire_triggers(next_node.triggers)

	# Handle pre-delay
	if next_node.pre_delay > 0.0:
		await get_tree().create_timer(next_node.pre_delay).timeout

	# Display
	_display_node(next_node)
```

#### 3. ~~Fix unsafe typed loop in AudioManager.stop_all()~~ [x]
**File**: `autoloads/audio_manager.gd`
**Line**: 108

`Dictionary.values()` returns an untyped Array. The typed for loop will error if the engine can't guarantee the type.

```gdscript
# Replace line 108:
	for key: String in _ambient_players:
		var player: AudioStreamPlayer = _ambient_players[key]
```

#### 4. ~~Fix null material_override in Intersection~~ [x]
**File**: `scripts/road/intersection.gd`
**Lines**: 139-150

Add null guard after the `as` cast.

```gdscript
# Replace lines 139-150:
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
```

### Success Criteria:

#### Manual Verification:
- [ ] Open project in Godot 4.5, no errors in Output panel
- [ ] Play through a full ride with dialogue choices — no crash
- [ ] Trigger a dialogue that has `"gps:glitch"` and `"ambience:tension"` triggers — both fire correctly
- [ ] Audio fades work when stopping all layers

---

## Phase 2: Type Safety Pass

### Overview
Fix all type annotations to comply with warnings-as-errors. Every variable, parameter, return type, and collection must be explicitly typed.

### Changes Required:

#### 1. Fix DialogueNode.choices type
**File**: `resources/dialogue_node.gd`
**Line**: 16

```gdscript
# Change:
@export var choices: Array[Resource]  ## Array of DialogueChoice
# To:
@export var choices: Array[DialogueChoice]
```

#### 2. Fix ProceduralPassengerGenerator return type
**File**: `scripts/procedural_passenger_generator.gd`
**Lines**: 93-94

```gdscript
# Change:
func _generate_minimal_dialogue(p: PassengerData) -> Array[Resource]:
	var nodes: Array[Resource] = []
# To:
func _generate_minimal_dialogue(p: PassengerData) -> Array[DialogueChoice]:
	var nodes: Array[DialogueNode] = []
```

**NOTE**: This also requires updating `PassengerData.dialogue_nodes` to match. Check its current type — if it's `Array[Resource]`, change it to `Array[DialogueNode]`.

#### 3. Fix AudioManager._ambient_players typing
**File**: `autoloads/audio_manager.gd`
**Line**: 7

```gdscript
# Change:
var _ambient_players: Dictionary = {}
# To:
var _ambient_players: Dictionary[String, AudioStreamPlayer] = {}
```

Also fix `_fade_layer` line 75 which accesses the dictionary:
```gdscript
# Line 75 — the Dictionary is now typed, so this is safe:
var player: AudioStreamPlayer = _ambient_players[layer_name]
```

#### 4. Fix DialogueBox collection types
**File**: `scenes/ui/dialogue_box.gd`
**Lines**: 7, 9

```gdscript
# Change:
var _current_nodes: Array = []  # Array of DialogueNode
var _node_map: Dictionary = {}  # id -> DialogueNode
# To:
var _current_nodes: Array[DialogueNode] = []
var _node_map: Dictionary[String, DialogueNode] = {}
```

Also update `start_dialogue` parameter (line 49):
```gdscript
# Change:
func start_dialogue(nodes: Array) -> void:
# To:
func start_dialogue(nodes: Array[DialogueNode]) -> void:
```

And `_display_node` valid_choices (line 129):
```gdscript
# Change:
var valid_choices: Array = []
# To:
var valid_choices: Array[DialogueChoice] = []
```

And `_show_choices` parameter (line 141):
```gdscript
# Change:
func _show_choices(choices: Array) -> void:
# To:
func _show_choices(choices: Array[DialogueChoice]) -> void:
```

#### 5. Fix Intersection dictionary types
**File**: `scripts/road/intersection.gd`
**Lines**: 14, 20

```gdscript
# Change:
var _light_states: Dictionary = {}
var _light_meshes: Dictionary = {}
# To:
var _light_states: Dictionary[int, LightState] = {}
var _light_meshes: Dictionary[int, Dictionary] = {}
```

Note: `_light_meshes` inner dict maps String -> MeshInstance3D. Godot 4.5 supports `Dictionary[int, Dictionary[String, MeshInstance3D]]` — use that if the engine accepts it, otherwise keep inner as untyped `Dictionary`.

#### 6. Fix EventManager dictionary type
**File**: `autoloads/event_manager.gd`
**Line**: 7

```gdscript
# Change:
var _event_scripts: Dictionary = {}
# To:
var _event_scripts: Dictionary[String, GDScript] = {}
```

#### 7. Fix GameState.flags dictionary type
**File**: `autoloads/game_state.gd`
**Line**: 38

```gdscript
# Change:
var flags: Dictionary = {}
# To:
var flags: Dictionary[String, bool] = {}
```

#### 8. Fix intersection light_configs typed Array
**File**: `scripts/road/intersection.gd`
**Line**: 97

```gdscript
# The inner arrays are heterogeneous [String, float, Color], which can't be typed.
# Change from Array[Array] to just Array to avoid misleading type annotation:
var light_configs: Array = [
```

#### 9. Fix RoadSegment.pick_random() Variant return
**File**: `scripts/passenger_manager.gd`
**Line**: 88

```gdscript
# Change:
return candidates[randi() % candidates.size()]
# To (explicit type since Array.pick_random and index access on typed arrays should be fine,
# but randi() % size() returns via index which is typed — this line is actually safe on a
# typed Array[PassengerData]. Verify no warning is emitted.)
```

### Success Criteria:

#### Manual Verification:
- [ ] Open project in Godot 4.5 — zero type warnings in Output panel
- [ ] Run the game, verify dialogue still works with typed arrays
- [ ] Verify procedural passengers generate correctly

---

## Phase 3: Error Handling & Logging

### Overview
Replace silent failures with `push_warning()` calls. Add input validation on public-facing methods.

### Changes Required:

#### 1. EventManager — validate params before access
**File**: `autoloads/event_manager.gd`
**Lines**: 51-63

The `_handle_simple_trigger` already checks `params.has()` — this is correct. But `trigger()` line 27 references `_active_event.event_id` which may not exist on a bare `GameEvent.new()` before `set_script()` runs. Move the warning to use the passed `event_id` param:

```gdscript
# Line 27 — already uses event_id param, this is fine. No change needed.
```

Actually, the event_id assignment on line 34 happens BEFORE execute on line 37, so this is safe. No change here.

#### 2. TrafficManager — log spawn failures
**File**: `scripts/traffic/traffic_manager.gd`
**Lines**: 56-93

Add a debug log after the spawn loop exhausts attempts:

```gdscript
# After the for loop (after line 93), add:
	# All 5 attempts failed — this is normal at high density, only log at debug level
	pass  # Spawn attempt failed, will retry next interval
```

Actually, this is a normal condition (high density means spawns fail). A push_warning here would spam the console. The current silent behavior is acceptable for spawn attempts. **Skip this change.**

#### 3. TrafficVehicle — log when queue_free'd due to no next road
**File**: `scripts/traffic/traffic_vehicle.gd`
**Lines**: 185-211

The `queue_free()` calls on lines 187, 195, 210 are normal lifecycle — vehicles despawning at road ends is expected. **Skip logging here too.**

#### 4. DialogueBox — validate GPS group lookup
**File**: `scenes/ui/dialogue_box.gd`
**Lines**: 221-229

The current code already does `if gps and gps.has_method("set_state")` — this is defensive enough. But add a warning if GPS is not found when a trigger expects it:

```gdscript
# Replace lines 220-229:
			"gps":
				var gps_node := get_tree().get_first_node_in_group("gps")
				if gps_node == null:
					push_warning("DialogueBox: GPS node not found in group 'gps' for trigger '%s'" % trigger)
				elif gps_node.has_method("set_state"):
					match param:
						"glitch":
							gps_node.set_state(1)  # GPSState.GLITCHING
						"no_signal":
							gps_node.set_state(3)  # GPSState.NO_SIGNAL
						"normal":
							gps_node.set_state(0)  # GPSState.NORMAL
						_:
							push_warning("DialogueBox: Unknown GPS trigger param '%s'" % param)
```

#### 5. DialogueBox — warn on unknown trigger action
**File**: `scenes/ui/dialogue_box.gd`
**Lines**: 215-241

Add a default case to the match:

```gdscript
# After the "ambience" match block (after line 241), add:
			_:
				push_warning("DialogueBox: Unknown trigger action '%s' in '%s'" % [action, trigger])
```

#### 6. PassengerManager — warn when no road network and procedural needed
**File**: `scripts/passenger_manager.gd`
**Lines**: 56-57

```gdscript
# Replace lines 55-57:
	# 3. Otherwise, generate procedural (needs road network)
	if _road_network:
		return _procedural_generator.generate(_road_network)
	else:
		push_warning("PassengerManager: No road network, cannot generate procedural passenger")
```

#### 7. ProximityDetector — validate target position
**File**: `scripts/proximity_detector.gd`
**Lines**: 14-17

```gdscript
# Replace set_target:
func set_target(world_pos: Vector3) -> void:
	if world_pos == Vector3.ZERO:
		push_warning("ProximityDetector: Target set to origin (0,0,0) — likely uninitialized")
	_target_position = world_pos
	_is_active = true
	_armed = false
```

### Success Criteria:

#### Manual Verification:
- [ ] Trigger a dialogue with a GPS trigger — verify warning NOT printed (GPS exists)
- [ ] Trigger an unknown action like `"foo:bar"` (add temporarily to a test dialogue) — verify warning IS printed
- [ ] Open Output panel, no unexpected warnings during normal gameplay

---

## Phase 4: RoadNetwork Data Classes

### Overview
Replace Dictionary return values from `RoadNetwork` with typed inner classes. This eliminates unsafe Dictionary key access throughout the codebase.

### Changes Required:

#### 1. Define inner classes in RoadNetwork
**File**: `scripts/road/road_network.gd`

Add at the top of the file (after the class_name line):

```gdscript
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
```

#### 2. Update get_nearest_lane_position()
**File**: `scripts/road/road_network.gd`
**Lines**: 44-61

```gdscript
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
```

#### 3. Update get_random_road_position()
**File**: `scripts/road/road_network.gd`
**Lines**: 64-83

```gdscript
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
```

#### 4. Update all callers

**File**: `scripts/passenger_manager.gd` (lines 110-115)
```gdscript
func _assign_world_positions(passenger: PassengerData) -> void:
	if not _road_network:
		return
	if passenger.pickup_world_position == Vector3.ZERO:
		var pickup: RoadNetwork.RoadPosition = _road_network.get_random_road_position()
		passenger.pickup_world_position = pickup.position
	if passenger.destination_world_position == Vector3.ZERO and passenger.destination_exists:
		var destination: RoadNetwork.RoadPosition = _road_network.get_random_road_position()
		passenger.destination_world_position = destination.position
```

**File**: `scripts/procedural_passenger_generator.gd` (lines 49-63)
```gdscript
	var pickup: RoadNetwork.RoadPosition = road_network.get_random_road_position()
	var destination: RoadNetwork.RoadPosition = road_network.get_random_road_position()
	var attempts: int = 0
	while destination.road == pickup.road and attempts < 10:
		destination = road_network.get_random_road_position()
		attempts += 1

	p.pickup_location = pickup.road.road_name if pickup.road else "Unknown"
	p.destination = destination.road.road_name if destination.road else "Unknown"
	p.pickup_world_position = pickup.position
	p.destination_world_position = destination.position
```

**File**: `scripts/traffic/traffic_manager.gd` — `_try_spawn()` doesn't use these methods (it accesses `road.curve` directly), so no change needed there.

### Success Criteria:

#### Manual Verification:
- [ ] Open project — no errors
- [ ] Procedural passengers get valid pickup/destination positions
- [ ] GPS shows distance updating during a ride
- [ ] Traffic vehicles spawn correctly

---

## Phase 5: Game State Machine Refactor

### Overview
Replace the monolithic `_transition_to()` match statement in `game.gd` with a proper state machine. Each phase becomes its own class with `enter()`, `exit()`, and `process()` methods.

### Changes Required:

#### 1. Create base GamePhaseState class
**File**: `scripts/game_phases/game_phase_state.gd` (NEW)

```gdscript
class_name GamePhaseState
extends RefCounted
## Base class for game phase states.

var game: Node = null  # Reference to the Game node


func enter() -> void:
	pass


func exit() -> void:
	pass


func process(_delta: float) -> void:
	pass
```

#### 2. Create phase state classes
**Directory**: `scripts/game_phases/` (NEW)

Each file implements one phase. Here are the ones with meaningful logic:

**File**: `scripts/game_phases/phase_shift_start.gd` (NEW)
```gdscript
class_name PhaseShiftStart
extends GamePhaseState


func enter() -> void:
	game.phone.show_notification("Shift started. Complete all rides to end your shift.")
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(2.0).timeout
	game.transition_to_phase(game.GamePhase.WAITING_FOR_RIDE)
```

**File**: `scripts/game_phases/phase_waiting_for_ride.gd` (NEW)
```gdscript
class_name PhaseWaitingForRide
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.WAITING_FOR_RIDE)
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(1.5).timeout
	game.offer_next_ride()
```

**File**: `scripts/game_phases/phase_ride_offered.gd` (NEW)
```gdscript
class_name PhaseRideOffered
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.RIDE_OFFERED)
```

**File**: `scripts/game_phases/phase_picking_up.gd` (NEW)
```gdscript
class_name PhasePicking Up
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.PICKING_UP)
	var passenger: PassengerData = game.current_passenger_data
	var pickup_pos: Vector3 = passenger.pickup_world_position
	game.spawn_pickup_marker(pickup_pos)
	game.pickup_detector.set_target(pickup_pos)
	game.phone.show_notification("Drive to pickup: %s" % passenger.pickup_location)
	game.gps.set_destination_position(passenger.pickup_location, pickup_pos)
	await game.pickup_detector.target_reached
	game.remove_pickup_marker()
	game.spawn_passenger_billboard()
	game.phone.show_notification("%s has entered the vehicle." % passenger.display_name)
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(1.0).timeout
	game.transition_to_phase(game.GamePhase.IN_RIDE)
```

**File**: `scripts/game_phases/phase_in_ride.gd` (NEW)
```gdscript
class_name PhaseInRide
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.IN_RIDE)
	game.ride_timer = 0.0
	var passenger: PassengerData = game.current_passenger_data
	var dest_pos: Vector3 = passenger.destination_world_position
	game.spawn_destination_marker(dest_pos)
	game.destination_detector.set_target(dest_pos)
	game.gps.set_destination_position(passenger.destination, dest_pos)

	if not passenger.destination_exists:
		var tree: SceneTree = game.get_tree()
		await tree.create_timer(5.0).timeout
		game.gps.set_state(game.gps.GPSState.GLITCHING)
		await tree.create_timer(2.0).timeout
		game.gps.set_state(game.gps.GPSState.NO_SIGNAL, {"message": "Destination not found"})

	if passenger.ambient_override >= 0:
		AudioManager.set_ambience(passenger.ambient_override as AudioManager.AmbienceState)

	game.start_passenger_dialogue()

	if not passenger.triggers_event.is_empty():
		EventManager.trigger(passenger.triggers_event)


func process(delta: float) -> void:
	game.ride_timer += delta
	GameState.advance_time(delta * 0.033)
```

**File**: `scripts/game_phases/phase_dropping_off.gd` (NEW)
```gdscript
class_name PhaseDroppingOff
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.DROPPING_OFF)
	game.gps.arrive()
	var passenger: PassengerData = game.current_passenger_data

	for flag: String in passenger.sets_flags:
		GameState.set_flag(flag)

	var is_narrative: bool = not passenger.is_procedural
	GameState.complete_ride(passenger.id, is_narrative)
	game.car_interior.remove_passenger()
	game.phone.show_notification("Ride complete.")
	GameState.advance_time(randf_range(0.75, 1.5))

	var tree: SceneTree = game.get_tree()
	await tree.create_timer(2.0).timeout

	if GameState.is_shift_complete():
		game.transition_to_phase(game.GamePhase.ENDING)
	else:
		game.transition_to_phase(game.GamePhase.BETWEEN_RIDES)
```

**File**: `scripts/game_phases/phase_between_rides.gd` (NEW)
```gdscript
class_name PhaseBetweenRides
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.BETWEEN_RIDES)
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(3.0).timeout
	game.transition_to_phase(game.GamePhase.WAITING_FOR_RIDE)


func process(delta: float) -> void:
	GameState.advance_time(delta * 0.05)
```

**File**: `scripts/game_phases/phase_ending.gd` (NEW)
```gdscript
class_name PhaseEnding
extends GamePhaseState


func enter() -> void:
	GameState.set_shift_state(GameState.ShiftState.SHIFT_ENDING)
	game.handle_ending()
```

#### 3. Refactor game.gd to use state machine
**File**: `scenes/main/game.gd`

Major restructuring. The new game.gd:
- Registers phase states in a Dictionary
- `transition_to_phase()` calls `exit()` on old state, `enter()` on new
- `_process()` delegates to current state's `process()`
- Helper methods (spawn markers, start dialogue, handle ending) become public so phase states can call them
- Remove the `_transition_to()` monolith

```gdscript
extends Node
## Root game scene — manages the ride loop and game flow.

enum GamePhase {
	TITLE,
	SHIFT_START,
	WAITING_FOR_RIDE,
	RIDE_OFFERED,
	PICKING_UP,
	IN_RIDE,
	DROPPING_OFF,
	BETWEEN_RIDES,
	ENDING,
}

var current_phase: GamePhase = GamePhase.TITLE
var current_passenger_data: PassengerData = null
var ride_timer: float = 0.0

var _current_state: GamePhaseState = null
var _phase_states: Dictionary[GamePhase, GamePhaseState] = {}
var _active_pickup_marker: PickupMarker = null
var _active_destination_marker: PickupMarker = null

@onready var car_interior: CharacterBody3D = $CarInterior
@onready var gps: Control = %GPS
@onready var phone: Control = %Phone
@onready var dialogue_box: Control = %DialogueBox
@onready var passenger_manager: Node = $PassengerManager
@onready var fade_overlay: ColorRect = %FadeOverlay
@onready var gps_screen_mesh: MeshInstance3D = $CarInterior/CarMesh/GPSScreen/ScreenMesh
@onready var road_network: RoadNetwork = $TestArea/RoadNetwork
@onready var traffic_manager: TrafficManager = $TrafficManager
@onready var pickup_detector: ProximityDetector = $PickupDetector
@onready var destination_detector: ProximityDetector = $DestinationDetector


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_gps_screen()
	_connect_signals()
	_register_phase_states()
	traffic_manager.initialize(road_network, car_interior)
	passenger_manager.initialize(road_network)
	_start_game()


func _register_phase_states() -> void:
	_phase_states[GamePhase.SHIFT_START] = PhaseShiftStart.new()
	_phase_states[GamePhase.WAITING_FOR_RIDE] = PhaseWaitingForRide.new()
	_phase_states[GamePhase.RIDE_OFFERED] = PhaseRideOffered.new()
	_phase_states[GamePhase.PICKING_UP] = PhasePickingUp.new()
	_phase_states[GamePhase.IN_RIDE] = PhaseInRide.new()
	_phase_states[GamePhase.DROPPING_OFF] = PhaseDroppingOff.new()
	_phase_states[GamePhase.BETWEEN_RIDES] = PhaseBetweenRides.new()
	_phase_states[GamePhase.ENDING] = PhaseEnding.new()
	for state: GamePhaseState in _phase_states.values():
		state.game = self

# ... (keep _setup_gps_screen, _connect_signals, _unhandled_input as-is)

func _process(delta: float) -> void:
	if _current_state:
		_current_state.process(delta)


func transition_to_phase(phase: GamePhase) -> void:
	if _current_state:
		_current_state.exit()
	current_phase = phase
	_current_state = _phase_states.get(phase)
	if _current_state:
		_current_state.enter()


func _start_game() -> void:
	GameState.start_shift()
	transition_to_phase(GamePhase.SHIFT_START)


# -- Public helpers for phase states --

func offer_next_ride() -> void:
	var next := passenger_manager.get_next_passenger() as PassengerData
	if next == null:
		transition_to_phase(GamePhase.ENDING)
		return
	current_passenger_data = next
	GameState.current_passenger_id = next.id
	phone.show_ride_request(next)
	transition_to_phase(GamePhase.RIDE_OFFERED)


func accept_current_ride() -> void:
	if current_passenger_data:
		phone.hide_ride_request()
		transition_to_phase(GamePhase.PICKING_UP)


func refuse_current_ride() -> void:
	if current_passenger_data:
		if not current_passenger_data.is_refusable:
			phone.show_notification("You cannot refuse this ride.")
			return
		GameState.refuse_ride(current_passenger_data.id)
		if not current_passenger_data.refuse_consequence.is_empty():
			EventManager.trigger(current_passenger_data.refuse_consequence)
		phone.hide_ride_request()
		transition_to_phase(GamePhase.WAITING_FOR_RIDE)


func start_passenger_dialogue() -> void:
	if current_passenger_data and current_passenger_data.dialogue_nodes.size() > 0:
		dialogue_box.start_dialogue(current_passenger_data.dialogue_nodes)


func spawn_pickup_marker(pos: Vector3) -> void:
	_active_pickup_marker = PickupMarker.new()
	_active_pickup_marker.marker_color = Color(0.2, 0.8, 0.2)
	add_child(_active_pickup_marker)
	_active_pickup_marker.global_position = pos


func remove_pickup_marker() -> void:
	if _active_pickup_marker:
		_active_pickup_marker.queue_free()
		_active_pickup_marker = null


func spawn_destination_marker(pos: Vector3) -> void:
	_active_destination_marker = PickupMarker.new()
	_active_destination_marker.marker_color = Color(0.3, 0.5, 1.0)
	add_child(_active_destination_marker)
	_active_destination_marker.global_position = pos


func remove_destination_marker() -> void:
	if _active_destination_marker:
		_active_destination_marker.queue_free()
		_active_destination_marker = null


func spawn_passenger_billboard() -> void:
	var billboard := PassengerBillboard.new()
	car_interior.seat_passenger(billboard)


func handle_ending() -> void:
	if GameState.has_flag("refused_all_strange"):
		phone.show_notification("You ended your shift early. Some things are better left unknown.")
	elif GameState.has_flag("followed_gps_home"):
		phone.show_notification("The app shows one final ride request. The pickup is your apartment.")
	else:
		phone.show_notification("Shift complete. You can go home now... if you remember the way.")
	if fade_overlay:
		var tween := create_tween()
		tween.tween_property(fade_overlay, "color:a", 1.0, 3.0)
```

#### 4. Update scene file for unique node names
**File**: `scenes/main/game.tscn`

Nodes that `game.gd` references via `%` need the `unique_name_in_owner = true` property set in the scene file. The following nodes need this:
- `GPS` (in SubViewport)
- `Phone` (in UILayer)
- `DialogueBox` (in UILayer)
- `FadeOverlay` (in UILayer)

This must be done in the Godot editor (set "Access as Unique Name" in the inspector for each node) or by editing the `.tscn` file to add `unique_name_in_owner = true` to each node's properties.

**NOTE**: The `@onready var gps` reference changes from the deep path `$CarInterior/CarMesh/GPSScreen/SubViewport/GPS` to `%GPS`. The other UI nodes already use short paths but should be migrated to `%` for consistency.

### Success Criteria:

#### Manual Verification:
- [ ] Full ride cycle works: offer -> accept -> pickup -> ride -> destination -> dropoff -> next ride
- [ ] Refusing a ride works and triggers consequence
- [ ] Ending triggers after completing required rides
- [ ] Time advances during IN_RIDE and BETWEEN_RIDES phases
- [ ] No behavioral change from pre-refactor

---

## Phase 6: Pause Menu

### Overview
Add a basic pause overlay. The `pause` input action (Escape) is already mapped but only toggles mouse capture mode.

### Changes Required:

#### 1. Create pause menu scene
**File**: `scenes/ui/pause_menu.tscn` (NEW)

A simple centered panel with "PAUSED" text and Resume/Quit buttons.

#### 2. Create pause menu script
**File**: `scenes/ui/pause_menu.gd` (NEW)

```gdscript
extends Control
## Pause overlay — freezes the game tree and shows resume/quit options.

signal resumed
signal quit_requested

@onready var resume_button: Button = %ResumeButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	visible = false
	# This node must NOT be paused so it can receive input
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(_on_resume)
	quit_button.pressed.connect(_on_quit)


func show_pause() -> void:
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func hide_pause() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			hide_pause()
			resumed.emit()
		else:
			show_pause()
		get_viewport().set_input_as_handled()


func _on_resume() -> void:
	hide_pause()
	resumed.emit()


func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()
```

#### 3. Add pause menu to game scene
**File**: `scenes/main/game.tscn`

Add a PauseMenu instance to the UILayer (alongside Phone and DialogueBox).

#### 4. Remove old pause toggle from game.gd
**File**: `scenes/main/game.gd`
**Lines**: 65-70

Remove the `_unhandled_input` pause handling since PauseMenu now owns it:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("accept_ride") and current_phase == GamePhase.RIDE_OFFERED:
		accept_current_ride()
	elif event.is_action_pressed("refuse_ride") and current_phase == GamePhase.RIDE_OFFERED:
		refuse_current_ride()
```

### Success Criteria:

#### Manual Verification:
- [ ] Press Escape during gameplay — game freezes, mouse becomes visible, "PAUSED" overlay appears
- [ ] Press Escape again or click Resume — game resumes, mouse re-captured
- [ ] Click Quit — application closes
- [ ] Pause works during all phases (waiting, riding, dialogue)
- [ ] Dialogue does not advance while paused
- [ ] Traffic vehicles freeze while paused

---

## Testing Strategy

### Manual Testing Steps:
1. Launch game, verify shift starts with notification
2. Accept first ride, drive to pickup marker, verify passenger boards
3. During ride, trigger dialogue with choices — select each branch
4. Arrive at destination, verify ride completes
5. After required rides, verify ending triggers
6. Refuse a ride, verify consequence fires
7. Press Escape during each phase — verify pause works
8. Check Godot Output panel — zero warnings during full playthrough

### Edge Cases to Test Manually:
- Rapidly press Space during dialogue auto-advance
- Press Y/N when no ride is offered
- Look at rearview mirror during the entire ride (camera drift test)
- Let procedural passenger dialogue play through with auto-advance

## Performance Considerations

- Phase state objects are `RefCounted`, not `Node` — no scene tree overhead
- RoadNetwork data classes are `RefCounted` — GC'd when no longer referenced
- No new per-frame allocations introduced
- Pause uses `SceneTree.paused` which is the standard Godot mechanism

## References

- Audit findings: conversation context (2026-02-14)
- `dialogue_box.gd:211-213` — trigger crash
- `dialogue_box.gd:95-98` — recursive advance
- `audio_manager.gd:108` — typed loop crash
- `intersection.gd:141` — null material crash
- `game.gd:91-176` — monolithic transition
- `road_network.gd:44-83` — untyped Dictionary returns
