class_name DialogueNode
extends Resource
## A single node in a dialogue tree — one line of text with optional branching.

@export var id: String

## Who is speaking: "PASSENGER", "DRIVER", "GPS", "PHONE", "NARRATOR", "INTERNAL"
@export var speaker: String = "PASSENGER"

@export_multiline var text: String

## Flag expression for conditional display: "has:flag_a AND NOT has:flag_b"
@export var condition: String = ""

## Branching choices (if empty, dialogue advances to next_node)
@export var choices: Array[Resource]  ## Array of DialogueChoice

## Next node ID if no choices
@export var next_node: String = ""

## Triggers fired when this node is displayed
## Format: "action:parameter" e.g. "set_flag:woman_warned", "play_sfx:static", "gps:glitch"
@export var triggers: Array[String]

## Pause before displaying this line (seconds) — for dramatic timing
@export var pre_delay: float = 0.0

## Auto-advance after this many seconds (0 = wait for player input)
@export var auto_advance: float = 0.0
