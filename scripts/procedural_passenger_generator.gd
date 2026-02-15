class_name ProceduralPassengerGenerator
extends RefCounted
## Generates random passengers with behavior vectors, archetypes, and minimal dialogue.

const FIRST_NAMES: PackedStringArray = [
	"Marcus", "Elena", "DeShawn", "Rachel", "Carlos",
	"Megan", "Andre", "Lisa", "Jordan", "Kim",
	"Trevor", "Aisha", "Brandon", "Sarah", "Diego",
	"Nicole", "Jamal", "Katie", "Tyler", "Maria",
]

const GREETINGS_TALKATIVE: PackedStringArray = [
	"Hey, thanks for coming!",
	"Finally! I've been waiting forever.",
	"Oh awesome, you're here. Let's go!",
	"Hey! How's your night going?",
]

const GREETINGS_QUIET: PackedStringArray = [
	"Hey.",
	"Hi.",
	"Thanks.",
	"...",
]

var _used_names: Array[String] = []


func generate(road_network: RoadNetwork) -> PassengerData:
	var p := PassengerData.new()

	# Identity
	p.id = "proc_%d" % randi()
	p.display_name = _pick_name()
	p.is_procedural = true

	# Behavior vector
	p.talkativeness = clampf(randfn(0.5, 0.25), 0.0, 1.0)
	p.nervousness = clampf(randfn(0.4, 0.25), 0.0, 1.0)
	p.aggression = clampf(randfn(0.3, 0.2), 0.0, 1.0)
	p.threat = clampf(randfn(0.15, 0.15), 0.0, 1.0)

	# Archetype matching
	p.archetype = ArchetypeRegistry.match_archetype(
		p.talkativeness, p.nervousness, p.aggression
	)

	# Physical locations
	var pickup: RoadNetwork.RoadPosition = road_network.get_random_road_position()
	var destination: RoadNetwork.RoadPosition = road_network.get_random_road_position()
	# Ensure pickup and destination are different roads
	var attempts: int = 0
	while destination.road == pickup.road and attempts < 10:
		destination = road_network.get_random_road_position()
		attempts += 1

	p.pickup_location = pickup.road.road_name if pickup.road else "Unknown"
	p.destination = destination.road.road_name if destination.road else "Unknown"
	p.pickup_world_position = pickup.position
	p.destination_world_position = destination.position
	p.destination_exists = true

	# Minimal dialogue
	p.dialogue_nodes = _generate_minimal_dialogue(p)

	# Procedural passengers are always refusable
	p.is_refusable = true
	p.is_mandatory = false

	return p


func _pick_name() -> String:
	# Try to avoid repeating names
	var available: PackedStringArray = []
	for n in FIRST_NAMES:
		if n not in _used_names:
			available.append(n)

	if available.is_empty():
		_used_names.clear()
		available = FIRST_NAMES

	var idx: int = randi() % available.size()
	var name: String = available[idx]
	_used_names.append(name)
	return name


func _generate_minimal_dialogue(p: PassengerData) -> Array[DialogueNode]:
	var nodes: Array[DialogueNode] = []

	# Greeting
	var greeting := DialogueNode.new()
	greeting.id = "greeting"
	greeting.speaker = "PASSENGER"
	if p.talkativeness > 0.5:
		greeting.text = GREETINGS_TALKATIVE[randi() % GREETINGS_TALKATIVE.size()]
	else:
		greeting.text = GREETINGS_QUIET[randi() % GREETINGS_QUIET.size()]
	greeting.auto_advance = 3.0
	greeting.next_node = "dest_confirm"
	nodes.append(greeting)

	# Destination confirmation (only for talkative passengers)
	if p.talkativeness > 0.4:
		var confirm := DialogueNode.new()
		confirm.id = "dest_confirm"
		confirm.speaker = "PASSENGER"
		confirm.text = "%s, right?" % p.destination
		confirm.auto_advance = 3.0
		confirm.pre_delay = 2.0
		nodes.append(confirm)

	return nodes
