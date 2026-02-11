class_name DialogueChoice
extends Resource
## A player choice within a dialogue node.

@export var text: String
@export var next_node: String
@export var condition: String = ""  ## Only show this choice if condition met
@export var sets_flag: String = ""  ## Set a flag when chosen
@export var triggers: Array[String]  ## Triggers fired on selection
