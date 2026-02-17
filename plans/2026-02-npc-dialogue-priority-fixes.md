# NPC & Dialogue System Priority Fixes

## Overview

Fix correctness bugs, decouple architecture bottlenecks, and apply low-hanging optimizations to the NPC/dialogue system based on the comprehensive audit. These changes make the system correct, extensible, and efficient without adding new features.

## Current State Analysis

The NPC/dialogue system works for the current 3-passenger demo but has:
- 4 correctness bugs (wrong signal types, broken refusal consequences, resource mutation, notification races)
- Architecture coupling that blocks future expansion (triggers hardcoded in UI, stringly-typed speakers)
- Per-frame waste (string formatting, group lookups every frame)

### Key Discoveries:
- `dialogue_box.gd:169` — `Array.find()` returns element, not index. Signal typed as `int`.
- `phone.gd:8` — `_notification_queue` declared but never used. `show_notification` has overlapping `await`.
- `game.gd:146` — `refuse_consequence` passes strings like `"flag_refused_woman"` to EventManager, which only recognizes `"set_flag"` with a `params["flag"]` dict key — so all refusals silently fail.
- `passenger_manager.gd:113` — `passenger.pickup_world_position = pickup.position` mutates the loaded Resource.
- `dialogue_box.gd:220-260` — All trigger logic (GPS, ambience, flags) lives inside a UI Control.
- `dialogue_node.gd:8` — Speaker is a raw `String`, matched in 3 separate places with no validation.
- `gps.gd:43` — `get_first_node_in_group("car_interior")` called every frame.

## Desired End State

After this plan:
1. All dialogue choice signals emit correct integer indices
2. Phone notifications queue properly without overlap
3. Refusing a passenger correctly sets the consequence flag
4. Narrative passenger Resources are not mutated by world position assignment
5. Trigger dispatch is signal-based — DialogueBox emits, game layer handles
6. Speaker is an enum with a NAMED variant that shows passenger display_name
7. Phase coroutines are guarded against stale execution on rapid transitions
8. Phone shift info updates only on state change, not every frame
9. GPS caches car reference instead of per-frame group lookup

Verification: Run the game, complete a full shift (accept and refuse rides), confirm dialogue choices work, notifications don't overlap, refusal flags are set, and no Godot warnings appear in output.

## What We're NOT Doing

- Adding new dialogue features (reactive dialogue, mid-ride pacing, archetype-driven dialogue)
- Expanding the event system (no new GameEvent subclasses)
- Adding dialogue localization or external editor support
- Refactoring game.gd into smaller controllers (separate effort)
- Adding new procedural dialogue templates
- Changing the dialogue data model (DialogueNode/DialogueChoice Resources stay as-is)

## Implementation Approach

Three phases, each independently testable. Phase 1 fixes bugs that affect current gameplay. Phase 2 restructures for extensibility. Phase 3 applies optimizations.

---

## Phase 1: Fix Correctness Bugs

### Overview
Fix 4 bugs that cause incorrect behavior in the current build.

### Changes Required:

#### 1. Fix `choice_made` signal — wrong emission type
**File**: `scenes/ui/dialogue_box.gd`
**Lines**: 169-171

**Problem**: `Array.find()` with a Callable returns the matching **element** (a Button), not its **index**. The signal is typed `choice_made(choice_index: int)`.

**Fix**: Replace with a simple index lookup.

```gdscript
# BEFORE (broken):
choice_made.emit(choices_container.get_children().find(
    func(c): return c is Button and c.text.ends_with(choice.text)
))

# AFTER (correct):
var choice_buttons: Array[Node] = choices_container.get_children()
var idx: int = -1
for i in choice_buttons.size():
    if choice_buttons[i] is Button and choice_buttons[i].text.ends_with(choice.text):
        idx = i
        break
choice_made.emit(idx)
```

#### 2. Implement notification queue
**File**: `scenes/ui/phone.gd`
**Lines**: 8, 48-52

**Problem**: `_notification_queue` is declared but unused. Overlapping `show_notification()` calls race — the first `await` hides the label while the second is still showing.

**Fix**: Use the queue. Track active notification with a generation counter to prevent stale hides.

```gdscript
# Replace the existing show_notification method and add a counter:
var _notification_counter: int = 0

func show_notification(text: String, duration: float = 3.0) -> void:
    _notification_counter += 1
    var my_id: int = _notification_counter
    notification_label.text = text
    notification_label.visible = true
    await get_tree().create_timer(duration).timeout
    # Only hide if no newer notification has taken over
    if _notification_counter == my_id:
        notification_label.visible = false
```

Remove the unused `_notification_queue` field (line 8) since the counter approach is simpler and sufficient.

#### 3. Fix refuse_consequence — flags never set
**File**: `scenes/main/game.gd`
**Lines**: 145-146

**Problem**: `refuse_consequence` values in .tres files are strings like `"flag_refused_woman"`. These are passed to `EventManager.trigger("flag_refused_woman")`, which doesn't recognize them. The EventManager's `_handle_simple_trigger` only handles `"set_flag"` with a `params` dict containing key `"flag"`.

**Fix**: Treat `refuse_consequence` as a flag name directly, since all current values are flag names. Set the flag in GameState instead of routing through EventManager.

```gdscript
# BEFORE:
if not current_passenger_data.refuse_consequence.is_empty():
    EventManager.trigger(current_passenger_data.refuse_consequence)

# AFTER:
if not current_passenger_data.refuse_consequence.is_empty():
    GameState.set_flag(current_passenger_data.refuse_consequence)
```

This matches the intent of the .tres data: `refuse_consequence: "flag_refused_woman"` means "set this flag when refused."

#### 4. Fix Resource mutation in _assign_world_positions
**File**: `scripts/passenger_manager.gd`
**Lines**: 106-117

**Problem**: Setting `passenger.pickup_world_position` directly on a loaded `.tres` Resource mutates the shared instance. On session restart (without process restart), the Resource retains stale random positions.

**Fix**: Duplicate narrative passenger resources before mutating them. Procedural passengers are already `.new()` so they're fine.

```gdscript
# In get_next_passenger(), duplicate narrative passengers before returning:

# BEFORE:
if roll < narrative_probability:
    var narrative: PassengerData = _get_eligible_narrative_passenger()
    if narrative:
        _assign_world_positions(narrative)
        return narrative

# ... fallback ...
var fallback: PassengerData = _get_eligible_narrative_passenger()
if fallback:
    _assign_world_positions(fallback)
    return fallback

# AFTER:
if roll < narrative_probability:
    var narrative: PassengerData = _get_eligible_narrative_passenger()
    if narrative:
        var instance: PassengerData = narrative.duplicate(true) as PassengerData
        _assign_world_positions(instance)
        return instance

# ... fallback ...
var fallback: PassengerData = _get_eligible_narrative_passenger()
if fallback:
    var instance: PassengerData = fallback.duplicate(true) as PassengerData
    _assign_world_positions(instance)
    return instance
```

`duplicate(true)` deep-copies sub-resources (DialogueNode, DialogueChoice arrays), so the original .tres is never touched.

### Success Criteria:

#### Manual Verification:
- [ ] Start a shift, accept a ride with choices. Click a choice — no error in output, dialogue advances correctly
- [ ] Refuse a ride for a narrative passenger (e.g., woman_remembers). Check `GameState.flags` contains the refuse flag (use debugger or print)
- [ ] Trigger two notifications rapidly (e.g., refuse then immediately get new offer). Second notification displays fully without being cut short
- [ ] Play through a full shift, restart the game (scene reload). Pickup positions for narrative passengers should be re-randomized, not stuck at previous positions

**Implementation Note**: After completing this phase, pause for manual verification before proceeding to Phase 2.

---

## Phase 2: Decouple Architecture

### Overview
Move trigger dispatch out of DialogueBox via signals, convert speaker to an enum with NAMED support, and guard phase coroutines against stale execution.

### Changes Required:

#### 1. Add Speaker enum to DialogueNode
**File**: `resources/dialogue_node.gd`

**Replace** the stringly-typed speaker with an enum. Add a `speaker_name` field for the NAMED variant.

```gdscript
class_name DialogueNode
extends Resource
## A single node in a dialogue tree — one line of text with optional branching.

enum Speaker {
    PASSENGER,
    DRIVER,
    GPS,
    PHONE,
    NARRATOR,
    INTERNAL,
    NAMED,  ## Uses speaker_name field for display
}

@export var id: String

@export var speaker: Speaker = Speaker.PASSENGER

## Custom speaker name — only used when speaker == NAMED
@export var speaker_name: String = ""

@export_multiline var text: String

@export var condition: String = ""
@export var choices: Array[DialogueChoice]
@export var next_node: String = ""
@export var triggers: Array[String]
@export var pre_delay: float = 0.0
@export var auto_advance: float = 0.0
```

#### 2. Update DialogueBox to use Speaker enum
**File**: `scenes/ui/dialogue_box.gd`

Update `_display_node()` and `_format_speaker()` to use the enum instead of string matching.

```gdscript
func _display_node(node: DialogueNode) -> void:
    speaker_label.text = _format_speaker(node)
    text_label.text = _substitute_variables(node.text)

    # Color the speaker label based on who's talking
    match node.speaker:
        DialogueNode.Speaker.PASSENGER, DialogueNode.Speaker.NAMED:
            speaker_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
        DialogueNode.Speaker.DRIVER:
            speaker_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
        DialogueNode.Speaker.GPS:
            speaker_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
        DialogueNode.Speaker.PHONE:
            speaker_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
        DialogueNode.Speaker.INTERNAL, DialogueNode.Speaker.NARRATOR:
            speaker_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

    # Show choices if any
    var valid_choices: Array[DialogueChoice] = []
    for choice in node.choices:
        if choice is DialogueChoice:
            if GameState.evaluate_condition(choice.condition):
                valid_choices.append(choice)

    if valid_choices.size() > 0:
        _show_choices(valid_choices)
    elif node.auto_advance > 0.0:
        _auto_advance_timer = node.auto_advance


func _format_speaker(node: DialogueNode) -> String:
    match node.speaker:
        DialogueNode.Speaker.PASSENGER:
            return "Passenger"
        DialogueNode.Speaker.NAMED:
            return node.speaker_name if not node.speaker_name.is_empty() else "Passenger"
        DialogueNode.Speaker.DRIVER:
            return GameState.player_name
        DialogueNode.Speaker.GPS:
            return "GPS"
        DialogueNode.Speaker.PHONE:
            return "FareShare App"
        DialogueNode.Speaker.INTERNAL:
            return "(Thinking)"
        DialogueNode.Speaker.NARRATOR:
            return ""
        _:
            return "???"
```

#### 3. Update .tres files for enum speaker values
**Files**: `resources/passengers/woman_remembers.tres`, `man_who_knows.tres`, `child_3am.tres`

Godot stores enum exports as integers in .tres files. The Speaker enum order is:
- 0 = PASSENGER
- 1 = DRIVER
- 2 = GPS
- 3 = PHONE
- 4 = NARRATOR
- 5 = INTERNAL
- 6 = NAMED

Current .tres files use string values like `speaker = "PASSENGER"`. After the enum change, Godot will need these as integers: `speaker = 0`. The .tres files must be updated to use integer values matching the enum.

For any dialogue node where the passenger should show their actual name, change `speaker` to `6` (NAMED) and set `speaker_name` to the passenger's name.

**Note**: Since .tres SubResource format may need careful editing, the safest approach is to:
1. Make the code changes first
2. Open each .tres in the Godot editor (it will auto-migrate string → int or show errors)
3. Re-save from the editor

If the editor can't auto-migrate (likely since string→enum isn't automatic), we'll need to manually update each SubResource's `speaker` field from the string value to the corresponding integer.

#### 4. Signal-based trigger dispatch
**File**: `scenes/ui/dialogue_box.gd`

Add a new signal and replace `_fire_triggers()` internals with signal emission.

```gdscript
signal trigger_fired(action: String, param: String)
```

Replace the body of `_fire_triggers()`:

```gdscript
func _fire_triggers(triggers: Array) -> void:
    for trigger: String in triggers:
        if trigger.is_empty():
            continue
        var parts := trigger.split(":", true, 1)
        var action := parts[0]
        var param := parts[1] if parts.size() > 1 else ""
        trigger_fired.emit(action, param)
```

**File**: `scenes/main/game.gd`

Add a new method that handles trigger dispatch, and connect it in `_connect_signals()`.

```gdscript
# In _connect_signals():
dialogue_box.trigger_fired.connect(_on_dialogue_trigger)

# New method:
func _on_dialogue_trigger(action: String, param: String) -> void:
    match action:
        "set_flag":
            GameState.set_flag(param)
        "remove_flag":
            GameState.remove_flag(param)
        "gps":
            match param:
                "glitch":
                    gps.set_state(gps.GPSState.GLITCHING)
                "no_signal":
                    gps.set_state(gps.GPSState.NO_SIGNAL)
                "normal":
                    gps.set_state(gps.GPSState.NORMAL)
                _:
                    push_warning("Game: Unknown GPS trigger param '%s'" % param)
        "event":
            EventManager.trigger(param)
        "ambience":
            match param:
                "tension":
                    AudioManager.set_ambience(AudioManager.AmbienceState.TENSION)
                "silence":
                    AudioManager.set_ambience(AudioManager.AmbienceState.SILENCE)
                "wrong":
                    AudioManager.set_ambience(AudioManager.AmbienceState.WRONG)
                "normal":
                    AudioManager.set_ambience(AudioManager.AmbienceState.NORMAL_DRIVING)
        _:
            push_warning("Game: Unknown trigger action '%s:%s'" % [action, param])
```

This moves all game-system knowledge out of the UI layer. DialogueBox becomes a pure presentation component that emits structured events.

#### 5. Guard phase coroutines against stale execution
**File**: `scripts/game_phases/game_phase_state.gd`

Add an `active` flag that `exit()` sets to false, so long-running coroutines can check if they've been superseded.

```gdscript
class_name GamePhaseState
extends RefCounted
## Base class for game phase states.

var game: Node = null
var active: bool = false


func enter() -> void:
    active = true


func exit() -> void:
    active = false


func process(_delta: float) -> void:
    pass
```

**File**: `scripts/game_phases/phase_in_ride.gd`

Guard the GPS glitch sequence with `active` checks:

```gdscript
func enter() -> void:
    active = true
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
        if not active:
            return
        game.gps.set_state(game.gps.GPSState.GLITCHING)
        await tree.create_timer(2.0).timeout
        if not active:
            return
        game.gps.set_state(game.gps.GPSState.NO_SIGNAL, {"message": "Destination not found"})

    if passenger.ambient_override >= 0:
        AudioManager.set_ambience(passenger.ambient_override as AudioManager.AmbienceState)

    game.start_passenger_dialogue()

    if not passenger.triggers_event.is_empty():
        EventManager.trigger(passenger.triggers_event)
```

**Apply same pattern** to all phase files with `await`:
- `phase_shift_start.gd` — guard after the 2s timer
- `phase_waiting_for_ride.gd` — guard after the 1.5s timer
- `phase_picking_up.gd` — guard after `target_reached` and the 1s timer
- `phase_dropping_off.gd` — guard after the 2s timer
- `phase_between_rides.gd` — guard after the 3s timer

Each follows the same pattern: call `active = true` at the start of `enter()`, and check `if not active: return` after every `await`.

### Success Criteria:

#### Manual Verification:
- [ ] Dialogue speaker labels show correctly — "Passenger" for generic, actual name for NAMED nodes
- [ ] All trigger types still work: test a ride with `set_flag`, `gps:glitch`, and `ambience:tension` triggers (child_3am covers all of these)
- [ ] No warnings in output about unknown trigger actions
- [ ] Rapidly accepting/refusing rides doesn't cause stale GPS state changes or phase errors
- [ ] Speaker label colors match: orange for passenger/named, blue for driver, green for GPS, gray for narrator

**Implementation Note**: After completing this phase, pause for manual verification before proceeding to Phase 3.

---

## Phase 3: Low-Hanging Optimizations

### Overview
Remove per-frame waste in phone and GPS systems.

### Changes Required:

#### 1. Event-driven shift info updates
**File**: `scenes/ui/phone.gd`

Replace the per-frame `_process` update with signal-driven updates.

```gdscript
# Remove the _process method entirely.

# In _ready(), connect to GameState signals:
func _ready() -> void:
    add_to_group("phone")
    ride_request_panel.visible = false
    notification_label.text = ""
    accept_button.pressed.connect(_on_accept)
    refuse_button.pressed.connect(_on_refuse)
    GameState.ride_completed.connect(_on_state_changed)
    GameState.shift_state_changed.connect(_on_shift_state_changed)
    _update_shift_info()


func _on_state_changed(_ride_number: int) -> void:
    _update_shift_info()


func _on_shift_state_changed(_new_state: GameState.ShiftState) -> void:
    _update_shift_info()
```

For time display updates (which change continuously during rides), add a throttled timer approach only during active ride phases:

```gdscript
var _time_update_timer: float = 0.0

func _process(delta: float) -> void:
    # Only update time display during active phases, throttled to 1Hz
    if GameState.current_shift_state == GameState.ShiftState.IN_RIDE \
        or GameState.current_shift_state == GameState.ShiftState.BETWEEN_RIDES:
        _time_update_timer += delta
        if _time_update_timer >= 1.0:
            _time_update_timer = 0.0
            _update_shift_info()
```

This reduces shift info updates from ~60/sec to ~1/sec during rides, and 0/sec otherwise.

#### 2. Cache car reference in GPS
**File**: `scenes/ui/gps.gd`

Cache the car node instead of looking it up every frame.

```gdscript
# Add a cached reference:
var _car_node: Node = null

# In _process, use the cache:
func _process(delta: float) -> void:
    if current_state == GPSState.GLITCHING:
        _glitch_timer += delta
        _update_glitch_effect()

    if _has_target and current_state == GPSState.NORMAL:
        if _car_node == null:
            _car_node = get_tree().get_first_node_in_group("car_interior")
        if _car_node:
            var dist: float = _car_node.global_position.distance_to(_target_world_position)
            var dist_display: String = "%.0fm" % dist if dist < 1000.0 else "%.1fkm" % (dist / 1000.0)
            eta_label.text = dist_display
```

#### 3. Early-return in DialogueBox _process when hidden
**File**: `scenes/ui/dialogue_box.gd`

Add an early return at the top of `_process` when the panel isn't visible:

```gdscript
func _process(delta: float) -> void:
    if not panel.visible:
        return

    if _auto_advance_timer > 0.0:
        _auto_advance_timer -= delta
        if _auto_advance_timer <= 0.0:
            advance()

    # Blink the continue indicator
    if not _waiting_for_choice and _auto_advance_timer <= 0.0:
        continue_indicator.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
    else:
        continue_indicator.visible = false
```

### Success Criteria:

#### Manual Verification:
- [ ] Shift info label still updates correctly when rides complete and time passes
- [ ] GPS distance display still works during rides
- [ ] Dialogue auto-advance and continue indicator still function
- [ ] No visible behavioral difference from the player's perspective — purely internal optimization

---

## Testing Strategy

### Manual Testing Playthrough:
1. Start a new shift
2. Accept the first ride (procedural) — verify dialogue shows, choices work if present
3. Refuse the second ride — verify `refuse_consequence` flag appears in output/debugger
4. Accept a narrative ride (woman_remembers) — verify:
   - Speaker labels show correct names/colors
   - Choices advance dialogue correctly
   - Triggers fire (ambience changes, flags set)
5. Trigger rapid notifications (refuse → immediately get new offer)
6. Play the child_3am encounter — verify GPS glitch sequence, then destination arrival doesn't cause stale state
7. Complete the shift — verify ending text shows based on flags

### Edge Cases:
- Accept/refuse ride rapidly before phone UI fully shows
- Arrive at destination while dialogue is still playing
- Multiple passengers in sequence — verify pickup positions are different each run

## Performance Considerations

- Phase 3 changes reduce per-frame string allocations from ~3 (phone + GPS + dialogue) to ~1 (GPS distance only, during rides)
- `duplicate(true)` in Phase 1 adds a one-time allocation per narrative passenger (~7 sub-resources). Negligible compared to the alternative of resource corruption.
- Signal connections in Phase 2/3 add no measurable overhead vs direct calls

## Migration Notes

- The Speaker enum change (Phase 2) will break existing `.tres` files that use string `speaker` values. These must be re-saved from the Godot editor after the code change, or manually updated to use integer enum indices.
- No save/load system exists yet, so no migration of persisted data is needed.
- All changes are backwards-compatible at the API level — no callers outside the modified files need updating except for the .tres re-save.
