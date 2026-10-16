class_name WildlifeProvider
extends ContentProvider
## WorldContent provider of wildlife spawn records (docs/modules/quests_npcs.md "Wildlife").
## Each 128 m cell is scanned on a worker for spots that suit a species (biome, region, water,
## roads, away from towns and beast dens) and yields at most one herd per species plus a bird
## flock where it fits; the WildlifeDirector spawns the nearest herds within its budget.
##
## Herd record: {key, species, pos, yaw, count, radius, scale, swim (water level or -INF)}
## Flock record: {key, flock: &"gull"|&"crow"|&"hawk", pos, count, radius, altitude}

const CELL := 128.0
const B := WorldData.Biome

## species -> rule. chance per cell, biomes, regions, herd size, radius, scale.
const RULES := {
	&"otter_penguin": {"chance": 0.55, "biomes": [B.SNOW, B.ICE, B.BEACH, B.TUNDRA], "regions": [&"water_tribe", &"wilds"], "coast": true, "count": [3, 6], "radius": 9.0, "scale": [0.9, 1.1]},
	&"turtle_duck": {"chance": 0.8, "lake": true, "count": [3, 5], "radius": 6.0, "scale": [0.55, 1.0]},
	&"ostrich_horse": {"chance": 0.3, "biomes": [B.GRASSLAND, B.FARMLAND], "regions": [&"earth_kingdom"], "road": true, "count": [2, 3], "radius": 12.0, "scale": [0.95, 1.05]},
	&"komodo_rhino": {"chance": 0.22, "biomes": [B.GRASSLAND, B.VOLCANIC, B.ASH, B.FOREST], "regions": [&"fire_nation"], "count": [1, 2], "radius": 10.0, "scale": [0.75, 0.9], "avoid_dens": true},
}

var director: Node = null
var _bison_spots: Array[Dictionary] = []
var _towns: Array = []        # [[Vector2 center, radius]]
var _dens: Array[Vector2] = []
var _ready_data := false


func _init(p_director: Node = null) -> void:
	id = &"wildlife"
	cell_size = CELL
	priority = 0
	unload_margin = 60.0
	director = p_director


func configure() -> bool:
	range_m = float(WildlifeDirector.budgets()["range"]) + 40.0
	if not _ready_data:
		_ready_data = true
		for c in WorldData.get_cities():
			var cc := QuestTargets.to_vec3(c.get("center"))
			_towns.append([Vector2(cc.x, cc.z), float(c.get("radius", 300.0)) + 30.0])
		for v in WorldData.get_villages():
			var vc := QuestTargets.to_vec3(v.get("center"))
			_towns.append([Vector2(vc.x, vc.z), float(v.get("radius", 80.0)) + 20.0])
		for d: Dictionary in EncounterSites.DENS:
			_dens.append(d["anchor"])
		var i := 0
		for a in Settlements.get_anchors(Settlements.AIR_TEMPLE, &"bison_stall"):
			_bison_spots.append({"key": StringName("bison_%d" % i), "species": &"sky_bison", "pos": a["position"], "yaw": float(a.get("yaw", 0.0)),
				"count": 1, "radius": 0.0, "scale": 1.0, "swim": -INF, "rest": true})
			i += 1
	return false


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var recs: Array[Dictionary] = []
	var rng := cell.rng()
	for sp: StringName in RULES:
		var rule: Dictionary = RULES[sp]
		if rng.randf() > float(rule["chance"]):
			continue
		var spot := _find_spot(cell, rng, sp, rule)
		if not spot.is_finite():
			continue
		var cnt := rng.randi_range(int(rule["count"][0]), int(rule["count"][1]))
		var swim := WorldData.get_water_height(spot.x, spot.z) if rule.has("lake") else -INF
		recs.append({"key": StringName("%s_%d_%d" % [sp, cell.coord.x, cell.coord.y]), "species": sp, "pos": spot,
			"yaw": rng.randf() * TAU, "count": cnt, "radius": float(rule["radius"]), "scale": rule["scale"], "swim": swim, "rest": false,
			"seed": cell.seed})
	for b in _bison_spots:
		if cell.rect.has_point(Vector2((b["pos"] as Vector3).x, (b["pos"] as Vector3).z)):
			recs.append(b)
	var flock := _flock_for(cell, rng)
	if not flock.is_empty():
		recs.append(flock)
	p.data["wildlife"] = recs
	var coord := cell.coord
	var dir := director
	p.add_call(func(_c: ContentCell) -> void:
		if dir != null and is_instance_valid(dir):
			dir.call("add_records", coord, recs))
	cell.payload = p


func release_cell(cell: ContentCell) -> void:
	if director != null and is_instance_valid(director):
		director.call("remove_records", cell.coord)


func _in_town(x: float, z: float) -> bool:
	var q := Vector2(x, z)
	for t: Array in _towns:
		if q.distance_to(t[0]) < float(t[1]):
			return true
	return false


func _find_spot(cell: ContentCell, rng: RandomNumberGenerator, sp: StringName, rule: Dictionary) -> Vector3:
	for attempt in 8:
		var x := cell.rect.position.x + rng.randf_range(10.0, CELL - 10.0)
		var z := cell.rect.position.y + rng.randf_range(10.0, CELL - 10.0)
		if _in_town(x, z) or WorldData.get_slope_deg(x, z) > 22.0:
			continue
		var h := WorldData.get_height(x, z)
		if rule.has("lake"):
			var wl := WorldData.get_water_height(x, z)
			if wl == -INF or wl < 2.0 or wl - h > 6.0:
				continue      # a lake / pond / canal surface, not the open sea
			return Vector3(x, wl, z)
		if WorldData.get_water_height(x, z) > -INF:
			continue
		if not (rule["biomes"] as Array).has(WorldData.get_biome(x, z)):
			continue
		if rule.has("regions") and not (rule["regions"] as Array).has(WorldData.get_region(x, z)):
			continue
		if bool(rule.get("coast", false)) and not _near_sea(x, z, 40.0):
			continue
		if bool(rule.get("road", false)) and WorldData.get_road(x, z) > 0.15:
			continue      # beside the road, never on it
		if bool(rule.get("avoid_dens", false)):
			var far := true
			for d in _dens:
				if d.distance_to(Vector2(x, z)) < 260.0:
					far = false
			if not far:
				continue
		return Vector3(x, h, z)
	return Vector3.INF


func _near_sea(x: float, z: float, r: float) -> bool:
	for k in 8:
		var a := TAU * k / 8.0
		if WorldData.get_height(x + cos(a) * r, z + sin(a) * r) < -0.5:
			return true
	return false


func _flock_for(cell: ContentCell, rng: RandomNumberGenerator) -> Dictionary:
	var c := cell.rect.get_center()
	if (absi(cell.coord.x) + absi(cell.coord.y) * 3) % 3 != 0:
		return {}
	var biome := WorldData.get_biome(c.x, c.y)
	var region := WorldData.get_region(c.x, c.y)
	var kind := &""
	if biome == B.BEACH or biome == B.OCEAN or _near_sea(c.x, c.y, 60.0):
		kind = &"gull"
	elif biome == B.MOUNTAIN or biome == B.ROCK or region == &"air_temple":
		kind = &"hawk"
	elif biome == B.FARMLAND or biome == B.GRASSLAND or biome == B.FOREST or biome == B.CITY:
		kind = &"crow"
	if kind == &"":
		return {}
	var gy := maxf(WorldData.get_height(c.x, c.y), 0.0)
	return {"key": StringName("flock_%d_%d" % [cell.coord.x, cell.coord.y]), "flock": kind, "pos": Vector3(c.x, gy, c.y),
		"count": rng.randi_range(6, 12) if kind != &"hawk" else rng.randi_range(2, 3), "radius": 45.0 if kind != &"hawk" else 70.0,
		"altitude": 26.0 if kind != &"hawk" else 55.0}
