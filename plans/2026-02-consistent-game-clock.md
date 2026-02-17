# Consistent Game Clock Implementation Plan

## Overview

Replace the current fragmented time system — where game time advances at different rates in different phases, freezes in others, and jumps randomly at drop-off — with a single, always-ticking clock driven from `game.gd._process()`. The clock uses a fixed rate of ~0.4 game-minutes per real-second (6 game-hours in ~15 real-minutes).

## Current State Analysis

Time currently advances through three disconnected mechanisms:

1. **`PhaseInRide.process()`** (`phase_in_ride.gd:37`) — `delta * 0.033` (~2 game-min/real-sec)
2. **`PhaseBetweenRides.process()`** (`phase_between_rides.gd:16`) — `delta * 0.05` (~3 game-min/real-sec)
3. **`PhaseDroppingOff.enter()`** (`phase_dropping_off.gd:18`) — `randf_range(0.75, 1.5)` hours instant jump

Time is **frozen** in 5 of 8 phases: SHIFT_START, WAITING_FOR_RIDE, RIDE_OFFERED, PICKING_UP, ENDING. The phone clock UI only updates during IN_RIDE and BETWEEN_RIDES (`phone.gd:34-35`).

### Key Discoveries:
- `GameState.advance_time()` at `game_state.gd:67-70` applies `time_speed_multiplier` and wraps at 24.0
- `GameState.current_time_hours` starts at 23.0 (11 PM) via `start_shift()` at `game_state.gd:55`
- Passenger time windows (`passenger_data.gd:62-84`) gate on `current_time_hours` — consistent ticking makes these more predictable
- `EventManager` can also trigger `advance_time` events (`event_manager.gd:57-59`) — this remains unaffected
- `game.ride_timer` (`game.gd:18`) accumulates real seconds during rides but is never read — will be removed

## Desired End State

After this plan is complete:
- Game time advances at a **single constant rate** in every phase where the game is active (all phases except ENDING)
- The rate is `6.0 / 900.0` hours per real-second (~0.00667 hrs/s), producing 6 game-hours over 15 real-minutes
- The phone clock is **always visible and always updating** throughout the shift
- No phase-specific time logic exists — all `advance_time` calls in phase states are removed
- `ride_timer` variable is removed from `game.gd`
- `time_speed_multiplier` is preserved in `GameState` for future use (debug, narrative events)

### Verification:
- Start a shift, observe clock reads 11:00 PM
- During any phase (picking up, waiting, in ride), the clock visibly ticks at the same rate
- No time jumps occur at drop-off
- After ~15 minutes of real play, clock reads ~5:00 AM
- Passenger time windows still gate correctly based on the now-predictable clock

## What We're NOT Doing

- Not changing `is_shift_complete()` — shifts still end by ride count, not time
- Not adding a day/night visual cycle (lighting changes) — just the clock value
- Not changing the `EventManager.advance_time` event action — events can still jump time if needed
- Not modifying passenger time window logic — it already works with `current_time_hours`
- Not adding pause/resume for the clock (out of scope)

## Implementation Approach

The change is surgical: add one line to `game.gd._process()`, remove three lines from phase states, and update the phone UI filter. Total: ~10 lines changed across 5 files.

---

## Phase 1: Centralize the Clock

### Overview
Move time advancement from individual phase states into the main game loop. Define the tick rate as a constant.

### Changes Required:

#### 1. Add clock constant and tick to `game.gd`

**File**: `scenes/main/game.gd`

Add a constant for the tick rate and call `advance_time` every frame in `_process()`:

```gdscript
# Add near the top with other constants/vars
## 6 game-hours over 15 real-minutes (900 seconds)
const GAME_TIME_RATE: float = 6.0 / 900.0

# Remove this line:
var ride_timer: float = 0.0
```

Update `_process`:
```gdscript
func _process(delta: float) -> void:
    if _current_state:
        _current_state.process(delta)
    GameState.advance_time(delta * GAME_TIME_RATE)
    _update_speedometer()
```

Note: Time should tick even during ENDING since `_process` runs unconditionally, but `advance_time` wraps at 24.0 so this is harmless. If desired, the ENDING phase sets a flag that could gate this, but it's unnecessary — the shift is over and the clock display is irrelevant during fade-out.

#### 2. Remove time advancement from `PhaseInRide`

**File**: `scripts/game_phases/phase_in_ride.gd`

Remove the entire `process()` override (both `ride_timer` accumulation and `advance_time` call):

```gdscript
# DELETE these lines (35-37):
func process(delta: float) -> void:
    game.ride_timer += delta
    GameState.advance_time(delta * 0.033)
```

#### 3. Remove time advancement from `PhaseBetweenRides`

**File**: `scripts/game_phases/phase_between_rides.gd`

Remove the entire `process()` override:

```gdscript
# DELETE these lines (15-16):
func process(delta: float) -> void:
    GameState.advance_time(delta * 0.05)
```

#### 4. Remove time jump from `PhaseDroppingOff`

**File**: `scripts/game_phases/phase_dropping_off.gd`

Remove the random time advancement on drop-off:

```gdscript
# DELETE this line (18):
GameState.advance_time(randf_range(0.75, 1.5))
```

---

## Phase 2: Always-Visible Clock UI

### Overview
Update the phone to display and update the clock during all shift phases, not just IN_RIDE and BETWEEN_RIDES.

### Changes Required:

#### 1. Update phone `_process` to always update clock

**File**: `scenes/ui/phone.gd`

Replace the phase-gated clock update with an unconditional one (still throttled to 1Hz for performance):

```gdscript
func _process(delta: float) -> void:
    _time_update_timer += delta
    if _time_update_timer >= 1.0:
        _time_update_timer = 0.0
        _update_shift_info()
```

This removes the `if GameState.current_shift_state == ...` guard entirely.

### Success Criteria:

#### Manual Verification:
- [ ] Start a new shift — clock shows 11:00 PM and begins ticking immediately
- [ ] During WAITING_FOR_RIDE and RIDE_OFFERED phases, clock continues to tick
- [ ] During PICKING_UP (driving to passenger), clock ticks at the same visible rate
- [ ] During IN_RIDE, clock ticks at the same rate as during pickup
- [ ] At drop-off, no time jump occurs — clock smoothly continues
- [ ] During BETWEEN_RIDES, clock ticks at the same rate as all other phases
- [ ] After ~15 minutes of play, clock reads approximately 5:00 AM
- [ ] Passenger time windows still work (e.g., child_3am appears at appropriate times)

## References

- `game_state.gd:67-70` — `advance_time()` function (unchanged)
- `game_state.gd:31` — `current_time_hours` variable (unchanged)
- `passenger_data.gd:62-84` — time window gating (unchanged)
- `event_manager.gd:57-59` — event-driven time advancement (unchanged)
