class_name WorldContentDefaults
extends RefCounted
## Registers the standard providers of the open world on a WorldContent node and the default
## exclusion zones (cities, villages, POI footprints) that scatter providers respect.


static func register_all(content: WorldContent) -> void:
	add_world_exclusions(content)
	# one-time setup while the scene loads: terrain pattern data (GPU readback) + species meshes
	TerrainPatterns.load_data()
	VegetationLibrary.build_async()
	content.register_provider(VegetationProvider.new())
	content.register_provider(ForestFarProvider.new())
	content.register_provider(GroundCoverProvider.new())


## Keep-out areas derived from WorldData: city/village footprints (trees, rocks, props; grass is
## avoided by the settlement paving hint instead) and POI footprints.
static func add_world_exclusions(content: WorldContent) -> void:
	if not WorldData.has_world_data():
		return
	var T := ContentExclusions
	var hard := T.TAG_TREES | T.TAG_ROCKS | T.TAG_PROPS
	for c in WorldData.get_cities():
		var ctr: Vector3 = c["center"]
		var rc: Variant = c.get("ring_center")
		if rc is Vector2:
			ctr = Vector3(rc.x, 0.0, rc.y)
		# built-up tiers are excluded; farm tiers (Ba Sing Se's agrarian ring) keep their fields
		# and trees, with the wall between them kept clear
		var built := 0.0
		var farm_outer := 0.0
		for t: Dictionary in c.get("tiers", []):
			if String(t.get("id", "")) == "agrarian":
				farm_outer = maxf(farm_outer, float(t.get("r_outer", 0.0)))
			else:
				built = maxf(built, float(t.get("r_outer", 0.0)))
		if built <= 0.0:
			built = float(c.get("radius", 200.0)) * 0.96
		content.add_exclusion(ctr, built + 18.0, hard, 25.0)
		if farm_outer > 0.0:
			content.add_exclusion_ring(ctr, farm_outer - 24.0, farm_outer + 24.0, hard, 12.0)
	for v in WorldData.get_villages():
		var ctr: Vector3 = v["center"]
		content.add_exclusion(ctr, float(v.get("radius", 60.0)) * 0.7, T.TAG_TREES | T.TAG_ROCKS | T.TAG_PROPS, 20.0)
