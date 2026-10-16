class_name WorldContentDefaults
extends RefCounted
## Registers the standard providers of the open world on a WorldContent node and the default
## exclusion zones (cities, villages, POI footprints) that scatter providers respect.


static func register_all(content: WorldContent, opts: Dictionary = {}) -> void:
	add_world_exclusions(content)
	add_feature_exclusions(content)
	# one-time setup while the scene loads: terrain pattern data (GPU readback) + species meshes
	TerrainPatterns.load_data()
	VegetationLibrary.build_async()
	NationPalette.prepare_materials()
	if opts.get("vegetation", true):
		content.register_provider(VegetationProvider.new())
		content.register_provider(ForestFarProvider.new())
		content.register_provider(GroundCoverProvider.new())
	if opts.get("structures", true):
		content.register_provider(LandmarkProvider.new())
		content.register_provider(PoiProvider.new())
		content.register_provider(RoadDressingProvider.new())


## Keep-out areas around the structures of LandmarkProvider / PoiProvider so trees and rocks
## do not grow through them: POI footprints, waterfall fall lines, bridge ends, arch feet and
## cave mouths (cave mouths and bridges also block grass).
static func add_feature_exclusions(content: WorldContent) -> void:
	if not WorldData.has_world_data():
		return
	var T := ContentExclusions
	var hard := T.TAG_TREES | T.TAG_ROCKS | T.TAG_PROPS
	for poi in WorldData.get_pois():
		var r := PoiStructures.footprint(poi)
		if r > 0.0:
			content.add_exclusion(poi["position"], r, hard, 6.0)
			# a clearing around it so the structure reads from a distance
			content.add_exclusion(poi["position"], r + 8.0, T.TAG_TREES, 10.0)
	for w in WorldData.get_waterfalls():
		var top: Vector3 = w["top"]
		var bottom: Vector3 = w["bottom"]
		content.add_exclusion_capsule(Vector2(top.x, top.z), Vector2(bottom.x, bottom.z), float(w.get("width", 8.0)) * 0.8 + 4.0, hard, 6.0)
	for b in WorldData.get_bridges():
		var a: Vector3 = b["a"]
		var c: Vector3 = b["b"]
		var dir := Vector2(c.x - a.x, c.z - a.z).normalized()
		content.add_exclusion_capsule(Vector2(a.x, a.z) - dir * 6.0, Vector2(c.x, c.z) + dir * 6.0, float(b.get("width", 4.0)) * 0.5 + 3.0, T.TAG_ALL, 4.0)
	for ar in WorldData.get_arches():
		for k: String in ["a", "b"]:
			content.add_exclusion(ar[k], float(ar.get("width", 9.0)) * 0.9, hard, 4.0)
	for poi in WorldData.get_pois():
		if poi["type"] != &"cave":
			continue
		var yaw := float(poi.get("yaw", 0.0))
		var out := Vector2(-sin(yaw), -cos(yaw))
		var e: Vector3 = poi["position"]
		var tunnel := PackedVector3Array([e])
		if poi.has("tunnel"):
			tunnel = CaveBuilder.dig(CaveBuilder.anchor(poi["tunnel"], Vector3(out.x, 0.0, out.y)))
			e = tunnel[0]
		var e2 := Vector2(e.x, e.z)
		content.add_exclusion_capsule(e2 + out * 9.0, e2 - out * 6.0, 7.0, T.TAG_ALL, 4.0)
		# nothing grows where the hill surface runs through the tube (shallow first metres)
		for i in range(1, tunnel.size()):
			var q := tunnel[i]
			if WorldData.get_height(q.x, q.z) - q.y > CaveBuilder.HEIGHT + 1.0:
				break
			content.add_exclusion_capsule(Vector2(tunnel[i - 1].x, tunnel[i - 1].z), Vector2(q.x, q.z), CaveBuilder.WIDTH * 0.6 + 0.5, T.TAG_ALL, 1.0)


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
