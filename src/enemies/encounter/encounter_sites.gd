class_name EncounterSites
extends RefCounted
## Builds the world's encounter sites from WorldData + this table (deterministic):
##
## * CAMPS     hostile WorldData camp POIs (the camp structure itself is built by the
##             worldcontent PoiProvider); members stand inside the palisade around the fire.
## * OUTPOSTS  authored camps near the home regions (structure by EncounterProvider);
##             the anchor is snapped to flat, dry, open ground nearby (find_flat).
## * PATROLS   groups walking back and forth along a stretch of a road.
## * DENS      wild beasts around a lair.
##
## Rosters are archetype ids (EnemyArchetypes); the first entry leads.

const CAMPS := {
	&"ek_dustwind_camp": {"faction": &"earth_rogues", "level": 2, "respawn": 600.0,
		"roster": [&"earth_chief", &"earth_rogue", &"bandit_brawler", &"bandit_brawler", &"bandit_archer", &"bandit_skirmisher"]},
}

const OUTPOSTS := [
	{"id": &"wt_fire_navy_landing", "name": "Fire Navy Landing", "region": &"water_tribe", "faction": &"fire_nation", "style": &"fire_nation",
		"anchor": Vector2(824, -2802), "search": 220.0, "biomes": [2, 3, 4], "level": 2, "respawn": 600.0,
		"roster": [&"fire_captain", &"fire_soldier", &"fire_soldier", &"fire_shieldbearer", &"fire_archer"]},
	{"id": &"ek_fire_scout_camp", "name": "Fire Nation Scout Camp", "region": &"earth_kingdom", "faction": &"fire_nation", "style": &"fire_nation",
		"anchor": Vector2(1155, -192), "search": 220.0, "biomes": [5, 6, 7], "level": 1, "respawn": 480.0,
		"roster": [&"fire_soldier", &"fire_shieldbearer", &"fire_soldier", &"fire_archer"]},
	{"id": &"fn_smugglers_cove", "name": "Smugglers' Cove", "region": &"fire_nation", "faction": &"pirates", "style": &"pirates",
		"anchor": Vector2(-2264, 1500), "search": 260.0, "biomes": [1, 5, 6, 10, 11], "level": 2, "respawn": 540.0,
		"roster": [&"water_pirate", &"pirate_cutlass", &"pirate_cutlass", &"pirate_archer"]},
	{"id": &"at_fire_scouting_party", "name": "Fire Nation Scouting Party", "region": &"earth_kingdom", "faction": &"fire_nation", "style": &"fire_nation",
		"anchor": Vector2(1900, 2350), "search": 220.0, "biomes": [5, 6, 8], "level": 1, "respawn": 480.0,
		"roster": [&"fire_soldier", &"fire_archer", &"fire_shieldbearer"]},
]

const PATROLS := [
	{"id": &"ek_omashu_road_patrol", "name": "Fire Nation Patrol", "road": &"bss_omashu", "from": 0.3, "to": 0.42, "faction": &"fire_nation",
		"level": 1, "respawn": 360.0, "roster": [&"fire_shieldbearer", &"fire_soldier", &"fire_archer"]},
	{"id": &"ek_dai_li_patrol", "name": "Dai Li Patrol", "road": &"bss_full_moon_bay", "from": 0.12, "to": 0.22, "faction": &"dai_li",
		"level": 2, "respawn": 420.0, "roster": [&"dai_li_agent", &"dai_li_agent"]},
	{"id": &"fn_saltspark_road_pirates", "name": "Pirate Raiders", "road": &"fn_harbor_saltspark", "from": 0.45, "to": 0.58, "faction": &"pirates",
		"level": 1, "respawn": 360.0, "roster": [&"pirate_cutlass", &"pirate_cutlass", &"pirate_archer"]},
	{"id": &"wl_north_road_bandits", "name": "Road Bandits", "road": &"bss_north", "from": 0.55, "to": 0.65, "faction": &"bandits",
		"level": 1, "respawn": 360.0, "roster": [&"air_renegade", &"bandit_brawler", &"bandit_skirmisher", &"bandit_archer"]},
]

const DENS := [
	{"id": &"fn_cinder_flats_den", "name": "Komodo Rhino Grounds", "region": &"fire_nation", "faction": &"wild", "anchor": Vector2(-3294, 3120),
		"search": 200.0, "biomes": [5, 6, 10, 11], "level": 2, "respawn": 600.0, "roster": [&"komodo_rhino", &"komodo_rhino"]},
	{"id": &"ek_red_mesa_den", "name": "Mesa Komodo Lair", "region": &"earth_kingdom", "faction": &"wild", "anchor": Vector2(-694, 640),
		"search": 200.0, "biomes": [5, 6, 8], "level": 1, "respawn": 600.0, "roster": [&"komodo_rhino"]},
]

## Radius of an authored outpost (structures + members).
const OUTPOST_RADIUS := 16.0


static func build_all() -> Array[EncounterSite]:
	var out: Array[EncounterSite] = []
	if not WorldData.has_world_data():
		return out
	for poi in WorldData.get_pois():
		if poi.get("type", &"") == &"camp" and CAMPS.has(StringName(poi.get("id", ""))):
			out.append(camp_site(poi, CAMPS[StringName(poi["id"])]))
	for o: Dictionary in OUTPOSTS:
		var s := outpost_site(o, &"outpost")
		if s != null:
			out.append(s)
	for p: Dictionary in PATROLS:
		var s2 := patrol_site(p)
		if s2 != null:
			out.append(s2)
	for d: Dictionary in DENS:
		var s3 := outpost_site(d, &"den")
		if s3 != null:
			out.append(s3)
	return out


## Members inside a POI camp's palisade, around the fire (the leader by the fire).
static func camp_site(poi: Dictionary, cfg: Dictionary) -> EncounterSite:
	var s := EncounterSite.new()
	s.id = StringName(poi["id"])
	s.poi_id = s.id
	s.display_name = String(poi.get("name", s.id))
	s.kind = &"camp"
	s.faction = cfg.get("faction", &"bandits")
	s.region = StringName(poi.get("region", ""))
	s.center = to_vec3(poi["position"])
	s.yaw = float(poi.get("yaw", 0.0))
	var r := clampf(float(poi.get("radius", 22.0)) * 0.6, 10.0, 22.0)
	s.radius = r + 4.0
	s.level = int(cfg.get("level", 1))
	s.respawn_time = float(cfg.get("respawn", 480.0))
	s.leash = r + 26.0
	_place_ring(s, cfg.get("roster", []), r * 0.3, hash(s.id))
	return s


## Authored outpost / den: anchor snapped to flat open ground.
static func outpost_site(o: Dictionary, kind: StringName) -> EncounterSite:
	var a: Vector2 = o["anchor"]
	var spot := find_flat(a, float(o.get("search", 200.0)), o.get("biomes", []), OUTPOST_RADIUS)
	if not spot.is_finite():
		push_warning("EncounterSites: no ground found for %s" % o.get("id", &"?"))
		return null
	var s := EncounterSite.new()
	s.id = o["id"]
	s.display_name = String(o.get("name", s.id))
	s.kind = kind
	s.faction = o.get("faction", &"bandits")
	s.region = o.get("region", WorldData.get_region(spot.x, spot.z))
	s.style = o.get("style", &"")
	s.center = spot
	s.radius = OUTPOST_RADIUS
	s.level = int(o.get("level", 1))
	s.respawn_time = float(o.get("respawn", 480.0))
	s.leash = OUTPOST_RADIUS + 26.0
	# Face the gate toward the nearest road (or the world centre).
	s.yaw = _gate_yaw(spot)
	_place_ring(s, o.get("roster", []), 4.6 if kind == &"outpost" else 4.0, hash(s.id))
	return s


static func patrol_site(p: Dictionary) -> EncounterSite:
	var road := _road(StringName(p.get("road", &"")))
	if road.is_empty():
		return null
	var pts := sub_polyline(road.get("points", []), float(p.get("from", 0.3)), float(p.get("to", 0.4)), 10.0)
	if pts.size() < 2:
		return null
	var s := EncounterSite.new()
	s.id = p["id"]
	s.display_name = String(p.get("name", s.id))
	s.kind = &"patrol"
	s.faction = p.get("faction", &"bandits")
	s.route = pts
	s.center = pts[pts.size() / 2]
	s.region = WorldData.get_region(s.center.x, s.center.z)
	s.radius = 6.0
	s.level = int(p.get("level", 1))
	s.respawn_time = float(p.get("respawn", 360.0))
	s.leash = 30.0
	var i := 0
	for id: StringName in p.get("roster", []):
		s.add_member(id, pts[0], _yaw_toward(pts[0], pts[1]), hash(s.id) + i * 7919)
		i += 1
	return s


static func _place_ring(s: EncounterSite, roster: Array, r: float, seed_v: int) -> void:
	var n := roster.size()
	for i in n:
		var id: StringName = roster[i]
		var pos := s.center
		var yaw := s.yaw
		if i > 0 or n == 1:
			var a := s.yaw + TAU * float(i) / float(maxi(n, 1)) + 0.4
			pos = s.center + Vector3(cos(a), 0.0, sin(a)) * r
			yaw = _yaw_toward(s.center, pos)   # facing outward, watching the surroundings
		else:
			pos = s.center + Vector3(sin(s.yaw), 0, cos(s.yaw)) * -1.6
		pos.y = WorldData.get_height(pos.x, pos.z)
		s.add_member(id, pos, yaw, seed_v + i * 7919)


## Gate direction of an outpost at `spot`: toward the nearest road within 120 m (the way
## visitors arrive), else toward the world centre.
static func _gate_yaw(spot: Vector3) -> float:
	for r: float in [30.0, 50.0, 75.0, 100.0, 120.0]:
		var best := -1.0
		var best_a := 0.0
		for k in 24:
			var a := TAU * k / 24.0
			var rd := WorldData.get_road(spot.x + r * cos(a), spot.z + r * sin(a))
			if rd > best:
				best = rd
				best_a = a
		if best > 0.2:
			return _yaw_toward(spot, spot + Vector3(cos(best_a), 0.0, sin(best_a)))
	return _yaw_toward(spot, Vector3.ZERO)


## Yaw (rotation about +Y of a -Z forward body) facing from `from` toward `to`.
static func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var d := to - from
	d.y = 0.0
	if d.length_squared() < 1e-4:
		return 0.0
	return atan2(-d.x, -d.z)


static func _road(id: StringName) -> Dictionary:
	for r in WorldData.get_roads():
		if StringName(r.get("id", "")) == id:
			return r
	return {}


## The part of a polyline ([[x,y,z],...]) between arc-length fractions t0..t1,
## resampled every `step` m, heights from WorldData.
static func sub_polyline(points: Variant, t0: float, t1: float, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var pts: Array[Vector3] = []
	for q: Variant in points:
		pts.append(to_vec3(q))
	if pts.size() < 2:
		return out
	var cum: Array[float] = [0.0]
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := cum[cum.size() - 1]
	var a := clampf(t0, 0.0, 1.0) * total
	var b := clampf(t1, 0.0, 1.0) * total
	var d := a
	var seg := 0
	while d <= b + 0.01:
		while seg < pts.size() - 2 and cum[seg + 1] < d:
			seg += 1
		var l := cum[seg + 1] - cum[seg]
		var u := (d - cum[seg]) / l if l > 1e-4 else 0.0
		var p := pts[seg].lerp(pts[seg + 1], clampf(u, 0.0, 1.0))
		p.y = WorldData.get_height(p.x, p.z)
		out.append(p)
		d += step
	return out


## Vector3 from a WorldData value (Vector3 or [x, y, z]).
static func to_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


## Nearest flat, dry, open spot to `anchor` within `search` m (spiral, 12 m steps):
## height spread < 1.6 m over a `radius` disc, above water, not a road / city / village.
## Returns Vector3.INF when nothing fits.
static func find_flat(anchor: Vector2, search: float, biomes: Array = [], radius: float = 14.0) -> Vector3:
	var rr := 0.0
	while rr <= search:
		var steps := maxi(1, int(TAU * rr / 12.0))
		for k in steps:
			var ang := TAU * float(k) / float(steps)
			var x := anchor.x + rr * cos(ang)
			var z := anchor.y + rr * sin(ang)
			if _good(x, z, biomes, radius):
				return Vector3(x, WorldData.get_height(x, z), z)
		rr += 12.0
	return Vector3.INF


static func _good(x: float, z: float, biomes: Array, radius: float) -> bool:
	var b := WorldData.get_biome(x, z)
	if b == WorldData.Biome.OCEAN or b == WorldData.Biome.CITY:
		return false
	if not biomes.is_empty() and not biomes.has(b):
		return false
	var c := WorldData.get_height(x, z)
	if c < 1.5 or WorldData.get_road(x, z) > 0.05:
		return false
	var wh := WorldData.get_water_height(x, z)
	if is_finite(wh) and wh > c - 0.3:
		return false
	if not _open_ground(x, z):
		return false
	# Level over the camp disc, and no road / field / town paving inside it or right
	# outside the barricades (a camp astride a road or in a wheat field reads wrong).
	for rr: float in [radius * 0.5, radius, radius + 6.0]:
		for k in 10:
			var a := TAU * k / 10.0
			var px := x + rr * cos(a)
			var pz := z + rr * sin(a)
			if rr <= radius and absf(WorldData.get_height(px, pz) - c) > 1.6:
				return false
			if WorldData.get_road(px, pz) > 0.05 or not _open_ground(px, pz):
				return false
	return true


## No town paving, paved road or farmland at (x, z).
static func _open_ground(x: float, z: float) -> bool:
	var hints := WorldData.get_ground_hints(x, z)
	return hints.r < 0.1 and hints.g < 0.15 and hints.b < 0.15
