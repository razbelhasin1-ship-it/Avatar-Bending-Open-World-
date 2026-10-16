class_name WorldContentDefaults
extends RefCounted
## Registers the standard providers of the open world on a WorldContent node and the default
## exclusion zones (cities, villages, POI footprints) that scatter providers respect.


static func register_all(content: WorldContent) -> void:
	add_world_exclusions(content)


## Keep-out areas derived from WorldData: city/village footprints (trees, rocks, props; grass is
## avoided by the settlement paving hint instead) and POI footprints.
static func add_world_exclusions(content: WorldContent) -> void:
	if not WorldData.has_world_data():
		return
	var T := ContentExclusions
	for c in WorldData.get_cities():
		var ctr: Vector3 = c["center"]
		content.add_exclusion(ctr, float(c.get("radius", 200.0)) * 0.96, T.TAG_TREES | T.TAG_ROCKS | T.TAG_PROPS, 30.0)
	for v in WorldData.get_villages():
		var ctr: Vector3 = v["center"]
		content.add_exclusion(ctr, float(v.get("radius", 60.0)) * 0.7, T.TAG_TREES | T.TAG_ROCKS | T.TAG_PROPS, 20.0)
