class_name ArchetypeRegistry
extends RefCounted
## Maps behavior vectors to named archetypes via centroid distance matching.

# Centroid format: Vector3(talkativeness, nervousness, aggression)
# Threat is independent of archetypes.
const ARCHETYPES: Dictionary = {
	"chatterbox":      { "centroid": Vector3(0.9, 0.3, 0.2), "threshold": 0.25 },
	"silent_type":     { "centroid": Vector3(0.1, 0.2, 0.1), "threshold": 0.2 },
	"nervous_one":     { "centroid": Vector3(0.3, 0.9, 0.1), "threshold": 0.25 },
	"backseat_driver": { "centroid": Vector3(0.7, 0.2, 0.8), "threshold": 0.25 },
	"shady_fare":      { "centroid": Vector3(0.2, 0.5, 0.4), "threshold": 0.2 },
}


static func match_archetype(talk: float, nerv: float, aggr: float) -> String:
	var best_match: String = ""
	var best_distance: float = INF
	var vec := Vector3(talk, nerv, aggr)

	for archetype_name: String in ARCHETYPES:
		var data: Dictionary = ARCHETYPES[archetype_name]
		var centroid: Vector3 = data["centroid"]
		var threshold: float = data["threshold"]
		var dist: float = vec.distance_to(centroid)
		if dist <= threshold and dist < best_distance:
			best_distance = dist
			best_match = archetype_name

	return best_match
