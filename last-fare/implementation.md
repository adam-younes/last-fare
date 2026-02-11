# Last Fare Implementation Specification and Checklist

This is a document detailing the implementation of the idea description located at ./last-fare.md 

There are a few components of the game that need to be planned out, the document will be structured with emphasis on what needs to be accomplished within the context of a single one of these "systems". Here, a system can be a scene, backend system, or content for the game that is significant enough to span several areas of development (art, sound design, scripting, modelling, etc.) 

## Systems

### Car Interior
The game's main setting and main gameplay will take place in the interior of MC's car.
This should be a driveable car that requires the player to actually control a vehicle in the game that functions closely to a car IRL. 
This will contain a drivers and passenger seat with a glove compartment and a divider in the middle. 
This will also contain the main camera for the game, which will be a first person camera centered in the head area of the driver's seat. 
There should be a steering wheel in front of the player with an instrument panel behind it containing:

- current speed 

- current gas 

- maintenance lights 

- current gear 

- odometer

- rpm 

To the right of the steering wheel and informational instrument panel, there should be a control panel dashboard containing the usual instruments, including: 

- radio with a volume and channel controller 

- cd slot 

- cigarette heater hole 

Above the dashboard will be the windshield, which is where the phone will be mounted for GPS and the rideshare app as well as notifications, this is also where the rearview mirror will be, giving a view into the car rear. 
The outside will also be visible through the side windows (passenger and driver's seat window) giving a view to the side view mirrors
Finally, the divider should contain cup holders and a gear shift, in addition to a center console box. 
Of all of these elements within the interior of the car, the player can interact with the gear shift, steering wheel, divider box, glove box, and radio. 
From within the car interior, the following systems are accessible directly and visible to the player: 

- Car Rear 

- Phone via. Phone Mount on the windshield/dashboard 

- Outside should be visible through the window

- Traffic is interactible via. the steering wheel and driving behavior on the part of the player. 

### Car Rear 

This is where the NPCs will enter the car and reside while the player is completing ride assignments throughout the game. 
This will be visible to the player only through the rearview mirror. 
The outside will also be visible showing what is behind the car through the rear window of the car behind the passenger.
When a passenger enters the car, they will be in the car rear. 

### Phone 

The MC has a phone mounted to the dashboard that acts as somewhat of a control center for the game throughout the main gameplay loop.
The phone will display several different screens including: 

- the rideshare app, where the player can view the current ride, including the customer's profile
- the GPS, which will display the algorithmically "shortest route" that the app determines for the player to follow 
- messages, which can show conversations between the MC and family members/loved ones/friends 
- the phone also has a notification system, which will display banner notifications for events that happen on the phone.

In order to use or interact with the phone, the player's camera is refocused, emphasizing the phone screen and de-emphasizing the road, forcing them to split their attention. 

### Outside 

The outside of the car will be a system on its own that contains the city and environment that the player is giving rides through. 

### Traffic

Traffic is the ambient simulation of other vehicles and pedestrians on the road. It exists to make the city feel alive, to create driving hazards that demand attention, and to provide a backdrop against which the player's choices (running lights, speeding, driving erratically) have consequences. Traffic is not a deep simulation — it needs to be convincing enough that the player feels like they are sharing the road, not driving through a movie set. Traffic laws operate like they do in the United States with traffic signs and stop lights.

#### AI Vehicles

Other cars populate the roads and follow basic traffic behavior:

- They stop at red lights and stop signs
- They drive in lanes at roughly the speed limit
- They signal and turn at intersections
- They slow down and stop for pedestrians
- They honk at the player if cut off, if the player is blocking traffic, or if the player is driving erratically (wrong lane, running a light, stopping in the middle of the road)
- They brake and swerve to avoid collisions with the player

AI vehicle density scales with time of night (as defined in City & World State) — heavier early in the shift, thinning out as the night progresses. Different neighborhoods have different baseline densities (downtown is always busier than the outskirts).

#### Pedestrians

Pedestrians exist on sidewalks and at crosswalks. They cross at intersections when they have a walk signal. Occasionally a pedestrian jaywalks. Pedestrians near the entertainment strip are denser and less predictable (drunk pedestrians stepping into the road). Hitting a pedestrian is a severe consequence — immediate police response, potential game-over depending on narrative context.

#### Traffic Lights & Signs

Intersections have functional traffic lights that cycle through red, yellow, and green. Stop signs exist at smaller intersections. The player must obey these or accept the risk of collision and police attention. Yellow lights create micro-decisions — brake or accelerate through — that add texture to driving without being mechanically complex.

#### Police Vehicles

Police cars are a special AI vehicle type. They patrol certain routes based on police presence levels defined by the City & World State system. Police vehicles observe the player's behavior:

- Running a red light in view of a police car triggers a traffic stop
- Speeding past a police car may trigger a pursuit
- Erratic driving (swerving, wrong-way driving) near police draws attention
- Having visible car damage may increase the chance of being pulled over

A traffic stop is a scripted interaction: the player pulls over, an officer approaches the window, and a brief dialogue exchange occurs. Outcomes range from a warning to a fine to a search of the vehicle (dangerous if the player is carrying evidence or contraband). Police encounters escalate in the late game if the player's actions have drawn suspicion through the narrative system.

#### Collision Consequences

Collisions with AI vehicles or objects produce:

- A physical jolt and impact audio
- Cosmetic damage to the car (body damage, potential windshield crack)
- The other driver honking, yelling, or stopping (depending on severity)
- If police are nearby, a potential traffic stop
- If a passenger is in the car, a reaction based on their behavior vector (fear, anger, commentary)
- No injury simulation for the player — the car absorbs impact and the shift continues

#### Traffic as Attention Demand

Traffic's primary role is to be the thing the player should be watching while all the other systems compete for their attention. A steady stream of cars means the player must actively steer, brake for lights, check mirrors for lane changes, and avoid obstacles. This baseline demand is what makes looking at the phone, the rearview mirror, or engaging with dialogue costly — the road does not pause while the player is distracted.

### Driving & Vehicle Control

The player controls the car in first-person from the driver's seat. Driving should feel grounded and tactile enough to maintain immersion, but mechanical complexity stays low — the car is a vehicle for the story, not a driving sim. The active engagement comes from navigating routes and managing attention, not from wrestling with the car itself.

#### Controls (Keyboard & Mouse)

| Action | Input |
|---|---|
| Steer left / right | A / D |
| Accelerate | W |
| Brake / Reverse | S |
| Shift gear up | E |
| Shift gear down | Q |
| Handbrake | Space |
| Free look | Mouse movement |
| Interact (contextual) | F |
| Turn signal left / right | Z / C |

Acceleration and braking are binary inputs, so the system applies an internal ramp — holding W smoothly increases throttle over ~0.3s rather than snapping to full power. Same for braking. This prevents jerky driving and keeps the feel smooth.

#### Transmission

The gear shift lever is visible in the cabin and the player uses it to shift between Park, Reverse, Neutral, and Drive. Within Drive, forward gears are automatic. The player must shift from Park to Drive to start moving. Shifting is animated — the player's hand moves to the lever, which takes a beat, reinforcing physicality. This is a low-frequency interaction (start of shift, parking, the occasional reverse) rather than a constant demand.

#### Steering

The steering wheel rotates visually in sync with player input. Steering is responsive and forgiving at all speeds — the player should never feel like they are fighting the car. Since A/D are binary, steering uses an internal ramp: tapping produces a small correction, holding sweeps the wheel further over time. Releasing auto-centers the wheel gradually.

#### Acceleration & Braking

The internal throttle ramp provides smooth speed control despite binary keys. Braking feels reliable with reasonable stopping distances. The speedometer on the instrument panel reflects actual speed in real-time.

#### Lane Discipline & Road Interaction

The car has no lane-assist — drifting happens naturally when the player is not actively correcting, which creates the tension with looking at the mirror or phone. Roads have lanes, shoulders, curbs, and oncoming traffic. Collisions with other vehicles or objects produce a jolt and cosmetic damage. Running red lights or stop signs risks collisions from cross traffic and increases police encounter probability.

#### Fuel Consumption

The gas gauge depletes based on distance driven. It depletes slowly enough that refueling is an occasional errand, not a constant pressure. When fuel is critically low, a dashboard light comes on as a warning. Running out of fuel strands the player, ending the shift with a tow fee.

#### Vehicle Degradation — Cosmetic & Atmospheric Only

Degradation from the Car Degradation system affects the look and feel of the car but does not meaningfully alter handling or control:

- Low tire pressure → a dashboard warning light, not a handling change
- Engine issues → a check engine light and occasional audible knocking, not reduced performance
- Cracked windshield → a visual crack overlay that grows over time, partially obscuring vision
- Body damage from collisions → visible dents and scratches that accumulate

Degradation serves as financial pressure and atmosphere — the car looks and sounds worse, repairs cost money, but the player is never punished with worse controls. The cracked windshield is the one exception where degradation has a gameplay impact, since it is visual obstruction competing with the core "eyes on the road" tension.

#### Audio Feedback

Engine hum maps loosely to speed. Braking produces tire squeal at high speed. Turn signals click. Road surface changes (asphalt, gravel, pothole) produce different tire audio. The car's ambient sound — rattles, creaks, AC hum — contributes to atmosphere.

### Camera & Attention

The player's first-person camera is locked to the driver's seat headrest position. The mouse controls free look within the constraints of what a seated driver could realistically turn to see. The central tension of the game lives here — every moment spent looking at the mirror, the phone, or a side window is a moment not watching the road, and the car drifts accordingly.

#### Default View

Looking forward through the windshield. This is the "safe" orientation — the road is visible, the steering wheel and instrument panel are in the lower field of view. The phone mount is visible in the upper-left area of the windshield. The rearview mirror is visible in the upper-right, slightly cut off by the edge of the screen — present in the player's peripheral awareness but not fully readable without glancing toward it.

#### Free Look Zones

Mouse movement rotates the camera within defined zones, each with a gameplay function:

- **Forward (default)** — Road, windshield, instrument panel. The only view where the player has full lane awareness. Phone mount partially visible upper-left, rearview mirror partially visible upper-right.
- **Rearview mirror (up-right)** — A glance toward the upper-right to bring the mirror fully into view. Shows a reflected view of the car rear: the passenger, the back seat, and a slice of the road behind through the rear window. This is the only way the player can observe the passenger. This is where the player reads passenger body language and checks for vehicles following.
- **Phone (up-left, toward mount)** — Looking toward the phone mounted in the upper-left of the windshield. When the player's gaze enters this zone, the phone UI becomes readable and interactable. The road becomes blurred/defocused in the periphery.
- **Driver-side mirror (left)** — A glance out the driver's window to the side mirror. Shows the lane to the left and behind.
- **Passenger-side mirror (far right)** — A glance across to the passenger-side mirror. Shows the lane to the right and behind. This is the most extreme head turn and leaves the player most blind to the road ahead.

The player's camera rotation is clamped so that they can never turn around to look at the back seat directly. The rearview mirror is the sole means of observing the passenger — everything the player knows about what's happening behind them is filtered through that small rectangle. This constraint is non-negotiable and central to the game's tension.

#### Attention Tax — Lane Drift

When the camera is pointed anywhere other than forward, the car begins to drift. The drift is subtle and gradual — not a punishment, but a natural consequence. The longer the player looks away, the further the car wanders. A quick mirror glance is safe. A sustained stare at the phone while driving at speed will carry the car across a lane line. The drift direction is slightly randomized so the player can not predict and pre-compensate.

#### Attention Tax — Missed Turns

If the player is not looking forward when approaching a GPS-indicated turn, there is no audio cue beyond the GPS voice (which can be missed if the radio is loud or the passenger is talking). The player simply drives past the turn and must reroute.

#### Mirror Rendering

The rearview mirror and side mirrors render actual reflected views (via render-to-texture or planar reflection), not static images. The passenger in the back seat is visible in real-time through the rearview mirror — their animations, their fidgeting, their hand movements. This is critical because the mirror is the only way the player can inspect passengers.

### Passenger System

Passengers are the core content of the game. Each passenger is an NPC that the player picks up, drives to a destination, and interacts with through dialogue and observation. The player never sees them directly — only through the rearview mirror. Passengers communicate as much through behavior as through words. Passengers fall into two categories: procedural passengers generated from behavior vectors, and narrative passengers that are hand-authored and advance the story.

#### Passenger Generation

Each ride request on the rideshare app generates a passenger with the following attributes:

- **Name** — displayed on the app
- **Profile photo** — displayed on the app; may or may not match the actual passenger model
- **Rating** — a star rating (1.0–5.0) visible on the app before accepting
- **Pickup location** — a pin on the GPS map
- **Destination** — displayed on the app and routed on the GPS
- **Rider notes** — optional short text from the passenger (e.g., "going to the airport," "two riders," "in a hurry")
- **Behavior vector** — determines personality, body language, and dialogue tendencies
- **Archetype** — optionally assigned based on the behavior vector

#### Behavior Vector

Each passenger is defined by a vector of normalized float values (0.0–1.0), where each axis represents a behavioral dimension:

- **Talkativeness** — 0.0 (silent) to 1.0 (won't stop talking)
- **Nervousness** — 0.0 (calm, relaxed) to 1.0 (fidgety, anxious, checking surroundings)
- **Aggression** — 0.0 (passive, agreeable) to 1.0 (confrontational, demanding, controlling)
- **Threat** — 0.0 (completely benign) to 1.0 (dangerous). Hidden from the player entirely.

The vector drives all downstream systems: body language animation weighting, dialogue pool selection, and escalation curves.

#### Archetypes as Vector Definitions

Archetypes are predefined centroid vectors with a similarity threshold. When a passenger is generated, their behavior vector is compared against all archetype centroids. If the passenger falls within the threshold radius of an archetype, they are assigned that archetype. If they fall within range of two, the nearest centroid wins. If they fall outside all thresholds, they have no archetype — they are just their raw vector.

Archetype assignment grants access to archetype-specific content: unique dialogue lines, specific triggered animations, and narrative hooks that only fire for that archetype. Untyped passengers draw from a general pool.

Example archetype definitions (centroid vectors as `[talkativeness, nervousness, aggression, threat]`):

| Archetype | Centroid | Description |
|---|---|---|
| The Chatterbox | [0.9, 0.3, 0.2, *] | Talks constantly, mostly harmless, may distract at critical moments |
| The Silent Type | [0.1, 0.2, 0.1, *] | Says almost nothing, sits still, ambiguous whether calm or unsettling |
| The Nervous One | [0.3, 0.9, 0.1, *] | Fidgets, checks phone, looks out rear window; anxious or fleeing something |
| The Backseat Driver | [0.7, 0.2, 0.8, *] | Gives route directions, pushy; may be helpful or redirecting you somewhere isolated |
| The Shady Fare | [0.2, 0.5, 0.4, *] | Vague about destination, asks to pull over in odd locations, may leave something behind |
| The Regular | [*, *, *, *] | Special case — a recurring passenger across multiple nights; vector may vary but identity persists |

The `*` on the threat axis means archetypes are defined independent of threat. A Chatterbox can be harmless or dangerous — the archetype determines surface personality, not what is underneath. The Regular is a narrative-driven archetype assigned by the story system rather than by vector proximity.

#### Narrative Passengers

Separate from procedural generation, there is a fixed pool of hand-authored narrative passengers. These are specific characters with scripted dialogue, predetermined behavior vectors, and story consequences. They advance the overarching plot — the recurring stranger who knows your name, the passenger connected to the news reports, the person who leaves something dangerous in your car.

Each narrative passenger has:

- A fixed identity (name, appearance, voice, behavior vector, scripted dialogue and events)
- **Preconditions** — narrative flags or game-state requirements that must be met before this passenger can appear (e.g., "night 5 or later," "player has completed ride with Passenger X," "player heard specific radio broadcast")
- **Consequences** — narrative flags or game-state changes that fire after the ride completes, based on how the player handled the encounter

#### Narrative Status Function

Before each ride is generated, a narrative status function evaluates the current game state and produces a probability distribution across all narrative passengers whose preconditions are currently met. This determines the chance that the next ride is a narrative passenger rather than a procedural one.

The function takes as input:

- Current night number
- Narrative flags (which story beats have occurred, which passengers have appeared, player choices made)
- Number of rides completed this shift
- Time since the last narrative passenger appeared

It outputs:

- A probability for each eligible narrative passenger (0.0–1.0)
- The remaining probability mass is assigned to procedural generation

For example, on night 7, if narrative passengers A, C, and D have their preconditions met, the function might output: `{ A: 0.15, C: 0.05, D: 0.25, procedural: 0.55 }`. There is a 25% chance the next ride is Passenger D, a 15% chance it is A, 5% for C, and 55% chance it is a normal procedural fare.

This allows the narrative to exert increasing pressure as the game progresses — early nights are mostly procedural with occasional story beats, while later nights have a higher concentration of narrative passengers as plot threads converge. The function can also spike a specific passenger's probability in response to recent events (e.g., if the player just heard a radio report about a missing person, the probability of the passenger connected to that storyline jumps).

When a narrative passenger is selected, the ride request on the app looks identical to any other ride — the player does not know in advance that this is a story-critical fare.

#### Boarding & Exiting

When the player arrives at the pickup pin, the passenger approaches the car from outside and enters the rear seat. This is shown via the side window and then the rearview mirror — the player sees the door open, someone get in, the door close. On arrival at the destination, the reverse happens. If the player stops and unlocks the door mid-ride (for ejection or at passenger request), the passenger exits wherever the car is.

#### Body Language System

While seated in the rear, passengers perform idle and triggered animations visible through the rearview mirror. Animation selection and frequency are driven by the behavior vector:

- **Idle behaviors** — weighted by the vector. A high-nervousness passenger fidgets, bounces their knee, checks their phone repeatedly, glances out the rear window. A low-nervousness passenger sits still, looks out the window calmly, or scrolls their phone lazily. High talkativeness produces gesturing and leaning forward to talk. These blend continuously — a passenger at 0.5 nervousness occasionally fidgets but mostly sits still.
- **Escalation behaviors** — triggered by time, route deviation, or story events. The vector determines which escalation animations play and how quickly they ramp up:
  - Glancing repeatedly out the rear window (nervousness-driven)
  - Reaching into a bag or pocket (threat-driven, but also triggered innocently by low-threat passengers retrieving a phone)
  - Leaning forward toward the driver (aggression-driven or urgency)
  - Putting on gloves (threat-driven, but can be innocuous at low threat)
  - Hand moving toward the door handle while the car is moving (nervousness or threat)
  - Shifting weight side to side (nervousness-driven)
- **Archetype-specific behaviors** — if the passenger matches an archetype, they gain access to additional animations unique to that archetype (e.g., The Backseat Driver pointing forward and gesturing at turns).
- **Narrative passenger overrides** — narrative passengers can have scripted animation sequences that override or supplement the vector-driven system at specific story moments.
- **Ambiguity by design** — because threat is independent from the visible axes, the same animation (reaching into a bag) can be driven by threat on one passenger and by nervousness on another. The player builds literacy over many rides but can never be certain from behavior alone.

#### Passenger Visibility

The passenger model is lit by the car interior ambient light and by passing streetlights/headlights from outside, which create shifting shadows across the back seat. In darker conditions, the passenger is harder to read — a face partially in shadow, a hand movement caught only in a flash of passing headlight. This is atmospheric, not a mechanic the player controls.

#### Multiple Passengers

Some rides involve more than one person. When a ride says one passenger but two approach the car, this is a verification mismatch the player must decide how to handle. Multiple passengers have independent behavior vectors — one might be calm while the other is agitated.

### Dialogue System

Dialogue is how the player verbally interacts with passengers during rides. It displays at the bottom of the screen as a traditional dialogue UI — the only HUD element in the game. Dialogue serves three purposes: building atmosphere, providing information the player uses to assess passengers, and acting as a lever for passenger satisfaction and tips. The player must manage conversation while simultaneously driving and watching the mirror.

#### Dialogue UI

A text box at the bottom of the screen. When a passenger speaks, their line appears with their name. When the player has a chance to respond, a set of response options appears for the player to select from. The UI is minimal — no portraits, no elaborate framing. It appears when dialogue is active and disappears when it is not.

#### Dialogue Flow

Conversations are not continuous. Passengers initiate lines based on their behavior vector and ride context, with natural pauses between exchanges. A high-talkativeness passenger starts talking shortly after boarding and keeps initiating throughout the ride. A low-talkativeness passenger might say one thing at boarding and nothing else unless the player initiates or something happens.

Dialogue triggers include:

- **Boarding** — an opening line when the passenger gets in (greeting, destination confirmation, or silence)
- **Time-based** — periodic lines during the ride, frequency scaled by talkativeness
- **Event-based** — triggered by specific gameplay events (player misses a turn, player runs a red light, player looks at the mirror for too long, route deviation, arriving at the destination)
- **Player-initiated** — the player can press a key to initiate conversation at any time, pulling from a contextual pool of things the driver might say
- **Narrative-scripted** — narrative passengers have scripted dialogue sequences that fire at predetermined moments

#### Player Response Options

When the player can respond, 2–4 options appear. These are short and natural — the kind of things a driver would actually say. Options are colored by tone but not labeled as such:

- **Agreeable** — go along with whatever the passenger says
- **Probing** — ask a follow-up question, dig for information
- **Deflecting** — change the subject or give a non-answer
- **Confrontational** — challenge something the passenger said or did

Not all tones are available for every exchange. The available options depend on what the passenger said and the current ride context. Responses are timed — if the player does not select within a few seconds, the moment passes and the driver says nothing (silence is a valid response with its own consequences).

#### Dialogue and the Behavior Vector

The passenger's vector shapes their dialogue:

- **Talkativeness** drives frequency and length of lines
- **Nervousness** colors content — nervous passengers say contradictory things, trail off, change subjects abruptly
- **Aggression** determines how they react to the player's responses — a high-aggression passenger escalates if challenged, a low-aggression one backs down
- **Threat** introduces subtext — high-threat passengers may say things that seem normal but carry double meaning on reflection, or they steer conversation toward topics that serve their hidden agenda

#### Passenger Satisfaction

Dialogue choices affect a hidden passenger satisfaction value. Agreeable responses generally raise it, confrontational responses lower it (unless the passenger respects pushback, which some archetypes do). Satisfaction influences the tip at the end of the ride and the rating the passenger leaves on the app. Consistently tanking satisfaction across rides lowers the player's driver rating, which affects which rides are available.

#### Dialogue as Information Source

Some dialogue lines contain information the player needs to cross-reference against other systems:

- A passenger says "heading to the airport" but the app destination is a residential area
- A passenger mentions a name that matches a missing person on the radio
- A passenger asks about a specific street, revealing familiarity with the area that contradicts their profile
- A passenger's story does not match what a previous passenger said about the same event

The player is never told explicitly that something is a clue. They either catch it or they do not.

#### Attention Cost

Dialogue options appear at the bottom of the screen regardless of where the player is looking. However, reading the options and selecting one requires a moment of cognitive attention even if the player's eyes stay on the road. If dialogue fires during a complex driving moment (merging, turning, heavy traffic), the player feels the squeeze of competing demands. Missing a response window because of driving is a natural consequence.

### Rideshare App & Ride Management

The rideshare app is displayed on the phone mounted in the upper-left of the windshield. It is the player's job dispatch system — the bridge between shifts and passengers. The app presents ride requests with limited information, and the player must decide whether to accept or reject based on what they can glean. Over time, the player learns to read ride requests like documents, picking up on red flags before ever meeting the passenger.

#### Ride Queue

At the start of each shift and after completing or canceling a ride, the app presents a ride request. Ride requests arrive one at a time — the player sees a single request and must accept or reject it. Rejecting cycles to the next request after a short delay. There is no way to browse multiple rides simultaneously. Rejecting too many rides in a row triggers a warning from the app about acceptance rate, which affects the player's standing.

#### Ride Request Display

Each request shows:

- **Passenger name** — first name only
- **Profile photo** — a small thumbnail; may or may not match the actual passenger
- **Passenger rating** — star rating (1.0–5.0)
- **Pickup location** — displayed as an address and a pin on the GPS minimap
- **Destination** — displayed as an address
- **Rider notes** — optional text field from the passenger; can contain anything from "heading to the airport" to "please hurry" to nothing at all
- **Estimated fare** — the payout for the ride before tip

#### Reading the Request

The player learns to cross-reference these fields for risk assessment:

- A low-rated passenger requesting pickup from a known bad area late at night is a different decision than a high-rated passenger from a hotel
- Rider notes that contradict the destination ("going to the airport" but destination is a residential dead-end)
- A very high estimated fare for a short distance may indicate surge pricing from a dangerous area
- Pickup pins in alleys, dead-ends, or isolated areas

None of this is flagged by the app. The player develops their own literacy.

#### Accepting a Ride

When the player accepts, the GPS routes to the pickup location. The passenger's profile remains visible on the app during the ride. Once the player arrives at the pickup pin, the passenger approaches and boards. The app transitions to an active ride view showing:

- Destination address
- GPS route to destination
- Elapsed time on the ride
- Estimated remaining distance

#### Ride Completion

When the player arrives at the destination and stops, the passenger exits. The app shows a ride summary:

- Fare earned
- Tip (if any, determined by passenger satisfaction and ride-specific factors)
- New passenger rating left by the rider (affects the player's driver rating)

After the summary, the cycle restarts — the app begins presenting new ride requests.

#### Ride Cancellation

The player can cancel an active ride at any time through the app. This has consequences:

- Before pickup: minor acceptance rate penalty, no fare earned
- After pickup (passenger in car): the passenger must be let out, significant rating penalty, possible confrontation depending on the passenger's aggression vector

#### Driver Rating

The player has a cumulative driver rating visible on the app. This is the average of all passenger ratings received. A high rating means more ride requests and better-paying fares. A low rating means fewer requests, worse fares, and eventually a deactivation warning from the app — a game-over condition if it drops too low.

#### Surge Pricing

Certain areas at certain times have surge multipliers on fares. The app displays this as a highlighted zone on the GPS. Surge areas are often surge for a reason — high demand because no drivers want to go there. This creates a risk/reward calculation: more money, more danger.

### GPS & Navigation

The GPS is a screen on the phone, accessible by swiping or tabbing on the phone UI. It displays a top-down map of the city with the player's car as a moving marker, a highlighted route to the current destination, and turn-by-turn voice prompts. The GPS is the player's lifeline for navigation but also a source of tension — following it requires looking at the phone, passengers can suggest deviations, and the "shortest route" is not always the safest.

#### Map Display

The GPS shows a simplified top-down map of the local area, oriented with the player's heading at the top (rotation-based, not north-fixed). The current route is drawn as a highlighted line from the player's position to the destination. Upcoming turns are marked. Street names are visible but small — readable only when the player is looking directly at the phone.

#### Turn-by-Turn Voice

The GPS announces upcoming turns with a synthesized voice: "Turn left in 200 feet," "Turn right onto Elm Street," etc. This is the only navigation aid that works without looking at the phone. However, the voice competes with other audio — the radio, the police scanner, the passenger talking. If any of those are loud, the GPS voice can be drowned out. The player can adjust GPS volume through the phone settings, but doing so means interacting with the phone mid-drive.

#### Route Calculation

When the player accepts a ride, the GPS calculates and displays the shortest route to the pickup, then recalculates for the route from pickup to destination once the passenger boards. The route is a suggestion — the player can deviate freely. If the player leaves the route, the GPS recalculates after a short delay, redrawing the path from the player's current position.

#### Route Deviation Detection

The system tracks whether the player is following the GPS route or not. Deviation triggers:

- GPS recalculation and a "Recalculating..." voice prompt
- Passenger reaction based on their behavior vector — a high-aggression passenger may demand to know why you left the route, a high-nervousness passenger may get more anxious, a low-talkativeness passenger may say nothing but their body language shifts
- Narrative passengers may have scripted reactions to specific deviations

#### Passenger Route Manipulation

Some passengers suggest route changes verbally through the dialogue system: "Hey, take a left here, I know a shortcut," or "Can you avoid the highway?" This creates a trust decision:

- Following the passenger's suggestion means leaving the GPS route. It might genuinely be faster — or it might route the player somewhere isolated.
- Refusing the suggestion may upset the passenger (satisfaction hit) but keeps the player on a known route.
- The player has no way to verify the suggestion in advance. The GPS only shows its own calculated route.

For narrative passengers, route suggestions can be scripted to lead to specific story-critical locations. For procedural passengers, route suggestions are generated based on the behavior vector — high-threat passengers are more likely to suggest routes that lead to isolated areas.

#### GPS as Verification Tool

The GPS passively provides information the player can cross-reference:

- The destination address on the app versus where the passenger says they are going
- The pickup pin location versus where the passenger is actually standing
- Whether the route passes through areas the player has learned to recognize as dangerous

### Notification & Messaging System

The phone receives text messages and notifications from sources outside of the rideshare app. These represent the player character's personal life pressing in during work. They serve two functions: narrative worldbuilding (the player has a life, debts, relationships) and attention competition (another thing demanding eyes off the road).

#### Notification Banner

When a new message or notification arrives, a banner slides in at the top of the phone screen. If the player is not looking at the phone, the banner is only visible as a small flash of light from the phone in the upper-left peripheral vision and an audible notification chime. The player must look at the phone to read the banner. Banners auto-dismiss after a few seconds.

#### Message App

A separate screen on the phone from the rideshare app and GPS. The player swipes or tabs to access it. Messages are displayed as a simple chat thread — sender name, message text, timestamp. The player can read messages but cannot reply while driving. This is intentional — the messages are one-way pressure. The player absorbs information and stress from them but cannot resolve anything until the shift is over.

#### Message Sources

- **Landlord** — rent reminders, late notices, threats of eviction. Escalates over the course of the game if the player is not earning enough. Creates financial pressure that makes accepting risky rides more tempting.
- **Family/partner** — asking when the player will be home, expressing worry, referencing events the player is missing. Humanizes the player character and establishes stakes beyond money.
- **Friends** — casual messages that sometimes contain useful information (gossip about the city, warnings about neighborhoods, references to news events).
- **Unknown numbers** — later in the game, messages from unknown senders that tie into narrative threads. A warning, a threat, a cryptic reference to something the player did on a previous shift.

#### Notification Types

- **Text messages** — from the sources above, appear in the message app
- **News alerts** — brief headlines about events in the city. These parallel information from the radio/police scanner but in text form. A news alert about a crime at an address the player just visited hits differently in text than on the radio.
- **App notifications** — from the rideshare app itself: acceptance rate warnings, driver rating changes, promotional surge alerts
- **Missed call notifications** — the phone rings occasionally. The player cannot answer while driving. A missed call notification appears instead, adding to the sense of life slipping away.

#### Timing & Frequency

Notifications are timed to maximize discomfort. They cluster during high-attention driving moments — navigating a tricky intersection, during an intense passenger conversation, or right when the player is trying to read a mirror behavior. Early nights have fewer personal messages. As the game progresses and financial/personal pressure mounts, message frequency increases.

#### Narrative Integration

Specific messages are triggered by narrative flags, the same way narrative passengers are gated by preconditions. A message from an unknown number after a suspicious ride, a family member referencing something the player did two nights ago, a news alert about a passenger the player drove. These are hand-authored and delivered at scripted moments.

### Car Degradation & Maintenance

The car deteriorates over the course of the game. Wear accumulates from normal driving, collisions, and time. Degradation is cosmetic and atmospheric — it does not affect handling — but it costs money to fix and makes the car look and sound progressively worse. The cracked windshield is the sole exception where degradation has a gameplay impact. Maintenance is a financial drain that competes with rent, bills, and the player's need to keep working.

#### Degradation Categories

- **Fuel** — depletes with distance driven. Refueling is done at gas stations on the map. Running out ends the shift with a tow fee. This is a routine expense, not a crisis unless the player is broke.
- **Tires** — wear gradually over many shifts. A dashboard warning light appears when tire pressure is low. No handling impact. If completely ignored over a long period, a flat tire can strand the player (similar to running out of fuel — ends the shift, costs a tow and replacement).
- **Engine** — accumulates wear over many shifts. Manifests as a check engine light and audible knocking/rattling that worsens over time. No performance impact. If completely ignored, the engine can stall and strand the player.
- **Body** — dents and scratches from collisions. Purely cosmetic. Passengers may comment on a visibly damaged car (dialogue trigger), and the player's rating can take minor hits if the car looks bad enough.
- **Windshield** — cracks from collisions or road debris events. A crack starts small and can grow over time if not repaired. Cracks create a visual overlay on the windshield that partially obscures the player's forward view. This is the one degradation category with direct gameplay impact — it competes with the "eyes on the road" tension. A severely cracked windshield makes it harder to see the road, traffic lights, and pedestrians.

#### Maintenance & Repair

The player can visit repair locations on the map (a mechanic, a gas station, a tire shop) between rides or during a shift. Stopping for repairs costs time (fewer rides completed during the shift) and money. Each repair category has a cost:

- Fuel: cheap, frequent
- Tires: moderate cost, infrequent
- Engine: expensive, infrequent
- Body: moderate cost, optional (cosmetic only, but affects passenger perception)
- Windshield: moderate cost, functionally important

The player is never forced to repair anything except by the natural consequences of ignoring it (stranding, visual obstruction, passenger comments). The game creates a slow squeeze: the car gets worse, repairs cost money the player may not have, and the player must choose between fixing the car and paying rent.

#### Degradation Rate

Wear accumulates slowly. The player should not feel like the car is falling apart night to night. Over the course of many shifts, things gradually get worse. Collisions accelerate body and windshield damage. Aggressive driving (hard braking, high speeds) slightly accelerates tire and engine wear. The goal is a background pressure, not a constant emergency.

#### Visual & Audio Indicators

- Dashboard warning lights for tires, engine, and fuel (visible on the instrument panel without looking away from the road)
- Audible engine knocking that increases in volume and frequency as engine wear worsens
- Visible dents, scratches, and paint damage on the car exterior (visible in reflections and when the passenger approaches)
- Windshield crack overlay on the player's forward view
- General car ambient audio gets rougher over time — more rattles, creaks, squeaks

### Economy System

Money is the game's primary pressure lever. The player needs money to pay rent, maintain the car, and buy fuel. Money comes from ride fares and tips. The economy is designed so that playing it safe and ethical barely covers expenses, while taking risks and making morally questionable choices pays significantly better. The player should always feel slightly behind.

#### Income Sources

- **Base fare** — earned for every completed ride. Calculated from distance and time. Displayed on the ride request before accepting.
- **Tips** — awarded after a ride based on passenger satisfaction, ride-specific factors, and moral choices. Tips range from nothing to a significant multiplier on the base fare. Some passengers tip well for compliance with shady requests ("take the weird route," "don't ask questions," "forget what you saw"). Refusing these requests is the ethical choice but costs real money.
- **Surge bonuses** — rides accepted during surge pricing earn a multiplier on the base fare. Surge areas are riskier.
- **Contraband/favor payments** — later in the game, the shadow faction offers cash for holding items, delivering packages, or looking the other way. These payments are substantial and off-the-books (not visible on the app).

#### Expenses

- **Rent** — due at a regular interval (e.g., every 7 in-game nights). A fixed amount that must be paid. Missing rent triggers escalating landlord messages and eventually a game-over condition (eviction). Rent is the baseline pressure that forces the player to keep working.
- **Fuel** — a small, frequent cost. Refueling at gas stations throughout the shift.
- **Car maintenance** — repair costs for tires, engine, body, and windshield. Variable depending on how much damage has accumulated.
- **Tow fees** — incurred when the player runs out of fuel or the car breaks down. A significant one-time cost that punishes neglecting maintenance.
- **Traffic violations** — fines for running red lights or causing accidents when police are present. Not every violation is caught — it depends on police presence in the area.

#### Financial Balance

The economy is tuned so that a player who drives safely, accepts only good-looking rides, and turns down shady requests will earn just barely enough to cover rent and basic maintenance. There is no comfortable surplus. To get ahead — to build a buffer, to repair the car fully, to stop feeling the squeeze — the player must take risks: accept low-rated passengers, drive during surge in bad areas, comply with questionable requests, or take favors from the shadow faction.

#### End-of-Shift Financial Review

The player cannot check their balance during the main gameplay loop. There is no earnings screen accessible while on shift. The player sees individual fare and tip amounts flash on the app after each ride completion, but never a running total or account balance.

At the end of each night, after the player parks outside their house and the shift ends, the phone displays a shift summary and financial overview:

- Total fares earned this shift
- Total tips earned this shift
- Any expenses incurred during the shift (fuel, repairs, tow fees, fines)
- Net earnings for the night
- Current account balance
- Upcoming expenses (rent due in X nights, outstanding maintenance)

This is the only moment the player sees their full financial picture. The effect is that during the shift, the player operates on gut feel and anxiety — they know roughly how the night is going from individual ride payouts, but they do not know exactly where they stand until they get home. A bad night only fully reveals itself in the driveway.

#### No Saving/Banking

Money does not accumulate across some safe account. It is cash on hand. The player earns, spends, and the number goes up or down. There is no investment, no interest, no financial planning beyond "earn enough to cover what is due."

### Verification & Trust Mechanics

As the game progresses, the player is introduced to an escalating series of verification problems — discrepancies between what the app says and what is actually happening. These are the game's equivalent of document inspection in Papers, Please. Each new type of mismatch is a new rule the player must track mentally while also driving, talking, and watching the mirror. The player is never told how to handle mismatches — they develop their own policy through experience and consequences.

#### Profile Photo Mismatch

The person who approaches the car at pickup does not match the profile photo on the app. This could be:

- An outdated photo (harmless — people change their appearance)
- A different person using someone else's account (ambiguous — could be a friend borrowing the account, could be a stolen account)
- A deliberate deception (dangerous)

The player must decide in the moment: let them in or drive away. Driving away from a harmless mismatch costs a cancellation penalty and a potential rating hit. Letting in a dangerous mismatch has worse consequences. The player learns to weigh factors: how different does the person look? What is their rating? What is the pickup location? What time is it?

#### Destination Mismatch

The passenger gets in and immediately says they want to go somewhere different than the app destination. This could be:

- A legitimate change of plans (harmless)
- A test to see if the driver is paying attention (ambiguous)
- An attempt to reroute the driver somewhere dangerous

The player can comply (update the route mentally, follow the passenger's directions), refuse (insist on the app destination), or question it (use dialogue to probe). The passenger's reaction depends on their behavior vector and whether the mismatch is genuine.

#### Passenger Count Mismatch

The app says one rider, but two or more people approach the car. The player must decide whether to let them all in. Extra passengers mean:

- More unpredictable variables in the back seat
- One or more people who are not on the app (no profile, no rating, no accountability)
- Potentially cramped conditions that make mirror observation harder

Refusing extra passengers upsets the group and may result in confrontation depending on the aggression vectors involved.

#### Pattern Recognition

Over multiple nights, the player begins to notice patterns that the game does not explicitly flag:

- Repeat pickup locations — the same address keeps generating rides, possibly with different names
- Familiar faces — a passenger who appeared before under a different name or account
- Correlated events — every time the player picks up from a certain area, something bad happens on the radio the next night
- Route patterns — certain destinations keep coming up in connection with suspicious rides

The game tracks these patterns internally and rewards players who act on them (avoiding a dangerous pickup) or punishes players who ignore them (walking into a trap they should have seen coming). But the game never tells the player "you should have noticed this." The literacy is earned.

#### Player Notes System

The phone has a simple notes app where the player can type short notes using the keyboard. This is the player's personal record — a crude logbook for flagging addresses, names, or observations:

- "123 Elm St — sketchy, two pickups in a row"
- "Marcus — said he was going to airport, went to warehouse district"
- "Blue jacket guy — seen twice, different accounts"

Notes are freeform text. The game does not parse or act on notes — they exist purely as the player's memory aid. Writing notes requires looking at and interacting with the phone, which means time not watching the road or the mirror. The notes persist across shifts.

#### Escalation Over Time

Verification problems are introduced gradually:

- **Early nights** — rides are straightforward. Passengers match their photos, destinations are as stated, one rider per request. The player learns the baseline.
- **Mid-game** — mismatches begin appearing. At first they are rare and usually benign. The player starts developing instincts.
- **Late game** — mismatches are frequent and the stakes are higher. Multiple types of mismatch can occur on the same ride (photo does not match AND they want to change the destination AND there are extra passengers). The player is juggling many rules simultaneously.

#### Consequences Spectrum

Mishandling verification is not binary. There is a spectrum of outcomes:

- **False positive (rejected a harmless mismatch)** — cancellation penalty, rating hit, lost fare. Financially painful but not dangerous.
- **Correct rejection (avoided a real threat)** — no fare earned, but the player stays safe. Sometimes confirmed later via radio or news.
- **Correct acceptance (let in a harmless mismatch)** — ride completes normally, fare and tip earned. The player's tolerance is validated.
- **Missed threat (accepted a dangerous mismatch)** — consequences range from a bad rating to a threatening encounter to something worse, depending on the threat level and the narrative context.

### Inventory & Items Left Behind

Passengers sometimes leave things in the car after exiting. These items create a secondary decision layer — what to do with something that is not yours. Items range from mundane (a phone, a wallet) to incriminating (a bag with something you should not have seen). The player has no dedicated inventory screen; items exist physically in the car — on the back seat, on the floor, in the gap between seats — visible through the rearview mirror or discovered when the player interacts with the car interior between rides.

#### Item Discovery

After a passenger exits, there is a chance an item is left behind based on the passenger's attributes and the ride context. The item appears as a physical object in the car rear. The player may notice it immediately through the rearview mirror, or they may not notice it until later — possibly not until the next passenger comments on it or until the end of the shift. Narrative passengers can leave specific scripted items as part of their story thread.

#### Item Types

- **Mundane items** — a phone, a wallet, a jacket, an umbrella, keys. These have no story significance on their own. They present a simple choice.
- **Valuable items** — a wallet with visible cash, an expensive watch, a designer bag. These tempt the player financially.
- **Information items** — a phone that buzzes with readable messages, a notebook with names and addresses, a printed receipt with a revealing address. These give the player information they were not meant to have, potentially connecting to narrative threads or verification patterns.
- **Evidence items** — something clearly incriminating. A bag with contents that are obviously illegal or dangerous. A phone whose lock screen shows something disturbing. These are dangerous to possess — having them in the car creates risk if the player is pulled over or if the passenger comes looking.
- **Contraband** — not left behind accidentally. A passenger explicitly asks the player to hold something or deliver it somewhere. The player does not know what is inside. Accepting starts a chain: deliver it and get paid, refuse and upset the faction, open it and face what is inside. This is the shadow faction's entry point — small favors that escalate.

#### Item Choices

When the player is aware of an item, they can interact with it between rides (when parked) by looking at the back seat area through the mirror and pressing interact. Options depend on the item type:

- **Return it** — the app has a "lost item" feature. Returning costs time (an extra trip) but may earn a reward or a rating boost. For information/evidence items, returning puts the player in contact with the passenger again, which may be desirable or dangerous.
- **Keep it** — the item stays in the car. Mundane items clutter the back seat. Valuable items can be sold (added to the player's cash at end of shift, but with a moral cost tracked by the narrative system). Information items remain accessible for the player to reference. Evidence items remain a liability.
- **Discard it** — the player tosses it out or leaves it somewhere. The item is gone. No reward, no risk, no information. For evidence items, this may be the safest option — or the passenger may come looking and find out the player disposed of it.
- **Turn it in** — for evidence items specifically, the player can turn it in to authorities. This involves driving to a police station, which costs time and puts the player in contact with police — who may ask uncomfortable questions about where the item came from and what the player knows.

#### Contraband Escalation

The shadow faction's requests escalate gradually:

- First request: hold onto a sealed envelope until your next shift. Easy, harmless-seeming, pays well.
- Later: deliver a package to a specific address. Still sealed, still ambiguous, pays more.
- Later still: pick up something from a location and bring it somewhere else. The player is now running errands.
- Eventually: the requests become clearly illegal or dangerous. By this point, the player is already complicit and refusing has consequences — the faction knows who the player is.

Each step is a choice. The player can refuse at any point, but the financial incentive grows and the faction's patience shrinks.

#### Item Persistence

Items remain in the car until the player deals with them. Multiple items can accumulate. A cluttered back seat with leftover items is visible through the rearview mirror and may affect passenger reactions (dialogue triggers about the mess, lower satisfaction from a dirty car).

### Radio & Police Scanner

The car radio is an interactable on the dashboard. It has two functional modes: music stations and a police scanner frequency. The radio plays continuously while the car is running and serves as the game's primary tool for passive narrative delivery — the player absorbs story information through audio while their eyes and hands are occupied with driving and passenger management. This creates the game's third layer of attention: eyes on road, mirror for passenger, ears for radio.

#### Radio Controls

The player interacts with the radio through the dashboard control panel. Controls are:

- **Volume** — adjustable up and down. Louder radio means harder to hear GPS voice and passenger dialogue. Lower volume means missing scanner information or news segments. Turning it all the way down silences the radio entirely.
- **Channel** — the player can switch between stations. Channels include music stations (genre variety for atmosphere) and the police scanner frequency.

#### Phone Volume

The phone has its own independent volume control, accessible through the phone UI. This governs the loudness of:

- GPS turn-by-turn voice
- Notification chimes
- Phone ringtones for incoming calls

The player can turn the phone volume up to make sure they hear GPS directions over a loud radio or a talkative passenger, or turn it down if the constant notification chimes are distracting. Turning it all the way down silences all phone audio — GPS directions, notifications, and calls become visual-only (requiring looking at the phone to get any information from it).

#### Audio Mix

The radio volume and phone volume are the two player-controlled audio levels. All other audio — engine, road noise, passenger voice — is not player-adjustable. The player's audio management creates its own tension: cranking the radio to catch a scanner dispatch means potentially drowning out a GPS turn. Turning the phone volume high to never miss a direction means notification chimes become intrusive. There is no comfortable setting — only trade-offs.

#### Music Stations

Multiple stations playing different genres appropriate to the setting and time period. Music is atmospheric — it sets the tone of the drive. Stations have DJ chatter between songs that occasionally drops worldbuilding details (local business ads, community event announcements, weather). Music stations are the "safe" default — pleasant background noise that does not demand attention.

#### Police Scanner

A dedicated frequency that plays dispatch audio — officers reporting locations, responding to calls, describing suspects and vehicles. The scanner is the game's primary ambient narrative delivery system. Information comes through as fragmented, jargon-heavy radio chatter that the player must actively parse:

- A missing persons report that matches a passenger from a previous night
- A crime reported at an address the player just dropped someone at
- A suspect vehicle description that sounds like the player's car
- Increased police activity in an area the player is driving through
- An officer responding to a location the player is heading toward

Scanner information is never repeated or highlighted. It plays once in real-time. If the player is not listening — because the volume is low, because the passenger is talking, because they are focused on a difficult merge — they miss it. The information is gone.

#### Narrative Integration

Specific scanner dispatches and news segments are triggered by narrative flags, the same system that gates narrative passengers and messages. After a suspicious ride, a scanner report about that area might play the next night. After a passenger leaves evidence in the car, a report about a missing item or a suspect matching the passenger's description might come through. These are hand-authored audio pieces inserted into the ambient scanner rotation at scripted moments.

#### Audio Layering & Competition

The radio and phone compete with non-adjustable audio sources for the player's ear:

- Passenger dialogue
- Engine and road audio

All sources play simultaneously. The player cannot pause or rewind any of them. If a critical scanner dispatch plays at the same moment a passenger starts talking and the GPS announces a turn, the player catches fragments of each and must piece together what they heard. This is intentional — the cognitive overload mirrors the exhaustion of real night-shift driving. The player's only recourse is managing the two volume knobs they have.

#### Local News Segments

Music stations periodically interrupt for news briefs — short radio news segments that cover city events in a more accessible format than the scanner. These are broader (a fire downtown, a political story, a human interest piece) but occasionally overlap with the game's narrative. A news story about rideshare safety, a report on a missing person, a piece about crime in a neighborhood the player frequents. News segments are less urgent than scanner dispatches but easier to absorb.

### City & World State

The city is the game's open environment — the streets, neighborhoods, landmarks, and locations the player navigates every shift. It is not a massive open world but a contained, dense urban area that the player becomes intimately familiar with through repetition. The city changes over the course of the game in response to narrative events and the passage of time, making familiar streets feel different as the story progresses.

#### City Layout

A fictional city with distinct neighborhoods, each with a different character:

- **Downtown** — dense, well-lit, heavy traffic. Hotels, bars, office buildings. High fare volume, generally safer but chaotic driving. Surge pricing during bar close hours.
- **Residential areas** — suburban streets, quieter, lower traffic. Family homes, apartment complexes. Lower fares, calmer rides. Late-night pickups from residential areas can feel isolated.
- **Industrial district** — warehouses, shipping yards, empty lots. Sparse streetlighting. Low traffic. Pickups here are rare and immediately suspicious. Key locations for contraband drops and narrative events.
- **Entertainment strip** — clubs, restaurants, late-night food spots. Busy early in the shift, chaotic with drunk passengers. High tips, high aggression vectors.
- **Outskirts** — the edge of the map. Long roads, sparse buildings, minimal lighting. Rides heading here are long-distance fares with high pay but isolation. The player is far from help.

The player learns the city through repetition. Street names, landmarks, shortcuts, and dangerous intersections become familiar. This knowledge is never gamified — there is no minimap fog-of-war or discovery percentage. The player just knows the city because they drive it every night.

#### Time of Night

The city changes within a single shift based on the in-game clock:

- **Early shift** — more traffic, more pedestrians, streetlights and storefronts lit. Rides are routine.
- **Mid shift** — traffic thins, bars close, drunk passengers emerge. The entertainment strip peaks and then empties. Police presence shifts.
- **Late shift** — the city is quiet. Fewer cars on the road, most businesses dark. Streetlights and the player's headlights are the primary light sources. Rides are sparse and the ones that come feel more consequential. The isolation amplifies tension.

#### City Evolution Across Nights

The city changes between shifts in response to narrative events and time progression:

- **Police presence** — certain areas gain or lose police patrols based on narrative events. A crime in a neighborhood increases cruisers there for subsequent nights. The player can observe this and factor it into decisions.
- **Cordoned areas** — after major narrative events (a building fire, a crime scene, an accident), certain streets or blocks may be closed off, forcing alternate routes.
- **Visual changes** — a building that burned down stays burned. Graffiti appears or is cleaned up. A storefront closes and its lights go dark. Construction appears. These changes are subtle and the game does not call attention to them — the player notices or they do not.
- **Neighborhood reputation** — areas that the player has had bad experiences in do not change mechanically, but the narrative status function can weight ride generation toward those areas to increase tension. The city feels like it is pulling the player back to places they do not want to go.

#### Points of Interest

Specific locations on the map that the player can visit:

- **Gas stations** — for refueling. Multiple locations spread across the city.
- **Mechanic shop** — for car repairs. Fewer locations, may require a detour.
- **Police station** — for turning in evidence items. Going here voluntarily is a choice with consequences.
- **The player's house** — the start and end point of every shift. The only safe space.

#### Weather & Atmosphere

Weather conditions change between nights and occasionally during a shift:

- **Clear night** — baseline visibility, normal driving.
- **Rain** — wet roads, windshield rain effects, reduced visibility. Headlights reflect off wet pavement. The city looks different in the rain — moodier, more oppressive.
- **Fog** — reduced visibility at distance. Streetlights create halos. Pedestrians and vehicles appear later. Heightens tension during isolated rides.

Weather is atmospheric and affects visibility but does not alter driving handling (consistent with the design principle that the car is not a challenge to control).

### Narrative & Story Progression

The game's story is not told through cutscenes or exposition dumps. It is assembled by the player from fragments delivered across multiple systems: passenger dialogue, radio broadcasts, police scanner dispatches, phone messages, items left behind, and the city itself changing around them. The narrative system is the orchestration layer that decides when and how these fragments are delivered, tracks the player's choices, and steers the story toward its conclusion — the last fare.

#### Narrative State

The game maintains a persistent narrative state — a collection of flags, counters, and values that represent everything that has happened so far:

- Which narrative passengers have appeared and what happened during their rides
- Which dialogue choices the player made with narrative passengers
- Which items the player found, kept, returned, discarded, or turned in
- Whether the player has engaged with the shadow faction and to what degree
- Which radio/scanner dispatches and news segments have played
- Which messages the player has received and read
- The player's financial state (how desperate they are)
- The player's driver rating (how much the app trusts them)
- Which city changes have occurred
- Current night number

This state is the input to the narrative status function (defined in the Passenger System), the message trigger system, the radio dispatch trigger system, and the city evolution system. Every narrative delivery channel reads from the same state.

#### Story Threads

The narrative is organized into parallel threads that run concurrently and can intersect. Each thread is a sequence of beats — narrative events that fire when their preconditions are met. Threads include:

- **The main thread** — the overarching mystery/thriller storyline that builds toward the final ride. This thread has the most beats and the highest-priority preconditions. It is the spine of the game.
- **The shadow faction thread** — the escalating contraband/favor requests. This thread is opt-in — it only progresses if the player engages. But refusing has its own consequences that feed back into the main thread.
- **The personal life thread** — the player's financial pressure, family relationships, and home situation. Delivered primarily through messages and the end-of-shift financial review. This thread provides motivation and stakes.
- **The city thread** — the evolving state of the city itself. Crimes, police activity, neighborhood changes. Delivered through radio, scanner, visual changes, and ride generation patterns.

Threads can reference each other. A shadow faction delivery might connect to the main thread's mystery. A personal life message might reference something from the city thread. The player experiences these as a web of overlapping information, not as labeled storylines.

#### Beat Structure

Each narrative beat consists of:

- **Preconditions** — the narrative state requirements that must be true for this beat to fire (e.g., "night >= 8 AND passenger_x_completed AND item_y_kept")
- **Delivery method** — how this beat reaches the player: a narrative passenger, a radio dispatch, a phone message, a city change, an item, or a combination
- **Player agency** — what choices the beat presents and what the consequences are
- **State changes** — the narrative flags that are set or modified after this beat fires, which unlock future beats

Beats do not fire immediately when preconditions are met. They enter the eligible pool and are delivered through the appropriate system — a narrative passenger through the narrative status function's probability distribution, a radio dispatch through the scanner rotation, a message through the notification system. This means the player cannot predict when a story beat will land.

#### Player Choice & Branching

The story does not have a single linear path. Player choices create divergence:

- Major choices (engaging with the shadow faction, turning in evidence, confronting a narrative passenger) create significant branch points that change which future beats are available.
- Minor choices (dialogue tone, whether to follow a passenger's route suggestion) accumulate into a profile that influences how narrative passengers react to the player and which version of certain beats fires.

The game does not track a simple "good/evil" axis. The player's profile is multidimensional — how compliant they are, how curious they are, how financially desperate they are, how much they trust passengers. Different narrative passengers read this profile differently.

#### The Final Ride

The entire game builds toward a single concluding ride — the last fare. This ride is a narrative passenger selected with certainty (probability 1.0) when the main thread's final beat preconditions are met. The ride request on the app looks like any other ride. The player does not know this is the end until the passenger gets in and says something that recontextualizes the game.

Who the final passenger is, where they want to go, and what happens depends on the player's accumulated choices across all threads. The final ride is not a single scripted event but a set of possible conclusions, each authored for a different combination of major player decisions. The resolution ties together the threads the player engaged with most.

After the final ride concludes, the game ends. There is no post-game free roam. The title pays off — this was the last fare.

### Game Loop & Shift Structure

The game is structured as a series of nightly shifts. Each shift is one gameplay session — the player starts at home, drives for the night, and returns home. Between shifts there is no gameplay — the transition is immediate. The shift structure provides the rhythm of the game: repetition with escalation, the same routine every night but with the world changing around it.

#### Shift Start

Every shift begins with the player in their car, parked outside their house. The car is already running. The player shifts from Park to Drive and pulls out. The rideshare app is open and begins presenting ride requests. The radio is on (whatever station and volume it was left at from the previous shift). The time-of-night clock starts at the beginning of the shift (early evening).

There is no pre-shift scene — no walking through the house, no getting ready. The game starts in the car every time. The car is the game.

#### During the Shift

The player completes rides in a loop:

1. Receive ride request on the app
2. Accept or reject
3. If accepted, drive to pickup
4. Passenger boards
5. Drive to destination (dialogue, mirror observation, navigation, and events occur during this leg)
6. Passenger exits, ride summary displays
7. Deal with any items left behind (optional, can defer)
8. Return to step 1

Between rides, the player can:

- Visit gas stations or mechanics for maintenance
- Check phone messages
- Write notes
- Simply drive freely through the city

There is no requirement to accept rides immediately. The player can idle, drive around, or handle errands. But time passes and rides not taken are money not earned.

#### Shift End Conditions

The shift ends when any of the following occur:

- **Player drives home** — the player can return to their house at any time to end the shift voluntarily. This is the normal end condition. The player decides when they have earned enough or when they have had enough.
- **Fuel runs out** — the car is towed, the shift ends with a tow fee deducted.
- **Car breaks down** — engine failure or flat tire, same as fuel — tow fee, shift over.
- **Narrative event** — certain story beats can force the shift to end (a police encounter, a threatening situation that makes the player flee home, an injury).
- **Deactivation** — if the player's driver rating drops below the threshold during a shift, the app locks them out. The shift ends immediately.

#### End-of-Shift Sequence

When the player arrives home (or is towed home), the shift transitions to the end-of-shift screen. This is the financial review described in the Economy System — the phone displays the shift summary, account balance, and upcoming expenses. This is the only moment of reflection in the game. After the player dismisses the summary, the screen fades and the next shift begins immediately.

#### Night Progression

Each shift represents one night. The game tracks the current night number, which is the primary input for narrative pacing. The game spans roughly 2-4 weeks of in-game time (14-28 shifts), though the exact count depends on how many rides the player completes per shift and how quickly narrative preconditions are met.

Early shifts are short in terms of content density — mostly procedural rides, establishing routine. As the night count increases, shifts become denser: more narrative passengers, more messages, more scanner dispatches, more verification mismatches. The player feels the escalation not as a difficulty curve but as the world closing in.

#### No Day Cycle

The game takes place entirely at night. There is no daytime gameplay, no daytime scenes, no sense of the sun coming up. The player exists in permanent night. This is both a tonal choice (thriller atmosphere) and a practical one (night driving with headlights and streetlights is the game's visual identity). The implication is that the player character sleeps during the day and works at night, but this is never shown — the game is only the shift.

#### Save System

The game saves automatically at the start of each shift. The save captures the full narrative state, financial state, car degradation state, and city state. There is no mid-shift saving — if the player quits during a shift, they restart that shift from the beginning. This prevents save-scumming individual rides and reinforces the commitment of each shift: once you are out driving, you are out until you go home.

