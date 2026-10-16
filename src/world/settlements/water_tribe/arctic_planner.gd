class_name ArcticPlanner
extends RefCounted
## Igloo villages and fishing camps of the arctic wilds (Water Tribe nation, built with
## NwtBuilder recipes). Sites were picked on flat snow away from roads and POIs (offline scan of
## the heightmap) and are re-validated against WorldData at runtime; each becomes a district with
## its own NPC anchors (homes, fire, fishers, guards, a quest giver).
##   igloo village   igloos in a loose ring around a fire pit, hide tents, drying racks, a
##                   banner pole, ice lanterns; the lake village cuts ice-fishing holes
##   fishing camp    hide tents and igloos facing the shore, fish racks, canoes pulled up on the
##                   beach, a short pier where the water is deep enough
##   warden camp     the Strait Wardens' lookout tower, igloos, tents, kayaks (village record)

const ID := &"arctic_villages"
## [id, name, kind, x, z]
const SITES := [
	[&"frostmere", "Frostmere", &"igloo_village", -2080.0, -3020.0],
	[&"whitecrest", "Whitecrest", &"igloo_village", 1040.0, -2820.0],
	[&"eastwind", "Eastwind", &"igloo_village", 2900.0, -2740.0],
	[&"saltwind", "Saltwind Fishing Camp", &"fishing_camp", -2680.0, -2780.0],
	[&"driftfin", "Driftfin Fishing Camp", &"fishing_camp", -3140.0, -2740.0],
]

var plan: SettlementPlan
var rng: RandomNumberGenerator


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"water_tribe")
	plan.display_name = "Arctic Villages"
	plan.y_range = Vector2(0.0, 30.0)
	if not WorldData.has_world_data():
		return plan
	rng = ContentHash.rng(ContentHash.hash_name("arctic"))
	var exclusions: Array = []
	for s: Array in SITES:
		var c := Vector3(float(s[3]), 0.0, float(s[4]))
		if not _valid(c, 26.0):
			continue
		c.y = WorldData.get_height(c.x, c.z)
		plan.add_district(s[0], s[1], c, 45.0)
		match s[2]:
			&"igloo_village": _igloo_village(c, s[0])
			&"fishing_camp": _fishing_camp(c, s[0])
		exclusions.append([c, 46.0, ContentExclusions.TAG_TREES | ContentExclusions.TAG_ROCKS | ContentExclusions.TAG_PROPS])
	for v in WorldData.get_villages():
		if v.get("kind") == &"camp" and v.get("region") == &"wilds":
			var c: Vector3 = v["center"]
			c.y = WorldData.get_height(c.x, c.z)
			plan.add_district(StringName(v["id"]), String(v.get("name", "Wardens' Camp")), c, float(v.get("radius", 45.0)))
			_warden_camp(c, StringName(v["id"]), float(v.get("radius", 45.0)))
			exclusions.append([c, float(v.get("radius", 45.0)) + 4.0, ContentExclusions.TAG_TREES | ContentExclusions.TAG_ROCKS | ContentExclusions.TAG_PROPS])
	plan.data["exclusions"] = exclusions
	if not plan.districts.is_empty():
		var sum := Vector3.ZERO
		for d in plan.districts:
			sum += d["center"]
		plan.center = sum / plan.districts.size()
		plan.radius = 0.0
	return plan


## Flat, dry ground: height above sea level and < ~3.5 m relief within r.
func _valid(c: Vector3, r: float) -> bool:
	var lo := INF
	var hi := -INF
	for k in 9:
		var a := TAU * k / 8.0
		var p := c + Vector3(cos(a), 0, sin(a)) * (r if k < 8 else 0.0)
		var y := WorldData.get_height(p.x, p.z)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return lo > 1.0 and hi - lo < 4.5


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, WorldData.get_height(p.x, p.z), p.z)


func _place(kind: StringName, p: Vector3, yaw: float, v: int, r: float, lod: int = 1) -> Dictionary:
	var g := _ground(p)
	if not plan.is_free(g.x, g.z, r):
		return {}
	plan.reserve(g.x, g.z, r)
	return plan.add(kind, g, yaw, {"v": v}, lod, "%s:%d" % [kind, v], r)


func _fire(c: Vector3, district: StringName) -> void:
	_place(&"fire_pit", c, 0.0, 0, 2.2)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var p := _ground(c + Vector3(cos(a), 0, sin(a)) * 3.2)
		plan.anchor(&"idle", p, NwtPlanner.yaw_dir(Vector2(c.x - p.x, c.z - p.z)), {"tags": ["fire", String(district)]})


func _igloo_village(c: Vector3, district: StringName) -> void:
	_fire(c, district)
	var n := 6 + rng.randi() % 3
	for k in n:
		var a := TAU * (k + rng.randf_range(-0.2, 0.2)) / n
		var rr := rng.randf_range(12.0, 18.0)
		var p := c + Vector3(cos(a), 0, sin(a)) * rr
		var yaw := NwtPlanner.yaw_dir(Vector2(c.x - p.x, c.z - p.z))
		var pc := _place(&"igloo", p, yaw, k % 3, 4.0)
		if not pc.is_empty():
			var door := NwtDistricts.world(pc["pos"], yaw, Vector3(0, 0, -5.0))
			plan.anchor(&"home", door, yaw + PI, {"tags": [String(district), "igloo"], "building": &"igloo", "capacity": 2 + k % 3})
			if k == 0:
				plan.anchor(&"quest_giver", door + Vector3(1.0, 0, 0), yaw + PI, {"tags": [String(district), "elder"]})
	for k in 2:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(22.0, 27.0)
		var yaw := NwtPlanner.yaw_dir(Vector2(c.x - p.x, c.z - p.z))
		var pc := _place(&"hide_tent", p, yaw, k, 3.2)
		if not pc.is_empty():
			plan.anchor(&"home", NwtDistricts.world(pc["pos"], yaw, Vector3(0, 0, -3.0)), yaw + PI, {"tags": [String(district), "tent"]})
	for k in 2:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(7.0, 9.0)
		var pc := _place(&"fish_rack", p, a, k, 2.6)
		if not pc.is_empty():
			plan.anchor(&"fisher", pc["pos"] + Vector3(0, 0, 1.5), a, {"tags": [String(district)]})
	_place(&"banner_pole", c + Vector3(5.0, 0, -4.0), 0.0, 1, 1.0, 2)
	for k in 3:
		var a := TAU * k / 3.0 + 1.1
		_place(&"lamp_post", c + Vector3(cos(a), 0, sin(a)) * 9.0, 0.0, k % 2, 0.8)
	_place(&"crates", c + Vector3(-6.0, 0, 5.0), 0.3, 2, 1.6, 0)
	# a frozen lake nearby: ice-fishing holes on the ice
	for lk in WorldData.get_lakes():
		if not lk.get("frozen", false):
			continue
		var lc: Vector3 = lk["center"]
		var to_lake := Vector2(lc.x - c.x, lc.z - c.z)
		var dist := to_lake.length() - float(lk["radius"]) * 0.8
		if dist > 140.0:
			continue
		var dir := to_lake.normalized()
		for k in 4:
			var q := Vector2(c.x, c.z) + dir * (dist + 30.0 + k * 9.0) + Vector2(-dir.y, dir.x) * rng.randf_range(-14.0, 14.0)
			var p := Vector3(q.x, float(lk["level"]), q.y)
			if WorldData.get_height(q.x, q.y) > float(lk["level"]) + 0.5:
				continue
			var pc := _place(&"ice_hole", p, rng.randf() * TAU, k % 2, 2.0, 0)
			if not pc.is_empty():
				plan.anchor(&"fisher", p + Vector3(1.0, 0, 0), 0.0, {"tags": [String(district), "ice_fishing"]})
		break


## Direction (x/z) towards the nearest sea from c (sampled ring), Vector2.ZERO if none.
func _coast_dir(c: Vector3) -> Vector2:
	for r in range(30, 200, 10):
		var best := INF
		var bd := Vector2.ZERO
		for k in 24:
			var a := TAU * k / 24.0
			var d := Vector2(cos(a), sin(a))
			var y := WorldData.get_height(c.x + d.x * r, c.z + d.y * r)
			if y < best:
				best = y
				bd = d
		if best < 0.0:
			return bd
	return Vector2.ZERO


func _fishing_camp(c: Vector3, district: StringName) -> void:
	var sea := _coast_dir(c)
	if sea == Vector2.ZERO:
		sea = Vector2(0, 1)
	var side := Vector2(-sea.y, sea.x)
	_fire(c, district)
	var face := NwtPlanner.yaw_dir(sea)
	for k in 5:
		var off := side * (k - 2) * 7.5 - sea * rng.randf_range(4.0, 9.0)
		var p := c + Vector3(off.x, 0, off.y)
		var kind: StringName = &"hide_tent" if k % 2 == 0 else &"igloo"
		var pc := _place(kind, p, face, k % 3, 3.6)
		if not pc.is_empty():
			plan.anchor(&"home", NwtDistricts.world(pc["pos"], face, Vector3(0, 0, -3.5)), face + PI, {"tags": [String(district), String(kind)]})
			if k == 2:
				plan.anchor(&"quest_giver", NwtDistricts.world(pc["pos"], face, Vector3(1.2, 0, -3.5)), face + PI, {"tags": [String(district), "fisher_chief"]})
	for k in 3:
		var off := side * (k - 1) * 8.0 + sea * 9.0
		var pc := _place(&"fish_rack", c + Vector3(off.x, 0, off.y), face + PI * 0.5, k % 2, 2.6)
		if not pc.is_empty():
			plan.anchor(&"fisher", pc["pos"] + Vector3(sea.x, 0, sea.y) * 1.5, face + PI, {"tags": [String(district), "rack"]})
	_place(&"banner_pole", c + Vector3(side.x, 0, side.y) * 4.0, face, 0, 1.0, 2)
	# the shore: canoes pulled up on the beach, a short pier where the water deepens
	var shore := Vector2.INF
	var deep := Vector2.INF
	for d in range(10, 200, 2):
		var q := Vector2(c.x, c.z) + sea * d
		var y := WorldData.get_height(q.x, q.y)
		if shore == Vector2.INF and y < 1.4:
			shore = q
		if y < -2.5:
			deep = q
			break
	if shore != Vector2.INF:
		for k in 4:
			var q := shore - sea * 2.5 + side * (k - 1.5) * 3.2
			var pc := _place(&"canoe", Vector3(q.x, 0, q.y), NwtPlanner.yaw_dir(sea), k % 3, 1.3, 1)
			if not pc.is_empty():
				# rest on the beach, not floating
				pc["pos"] = Vector3(q.x, maxf(WorldData.get_height(q.x, q.y), 0.0) + 0.25, q.y)
				plan.anchor(&"boat", pc["pos"], NwtPlanner.yaw_dir(sea), {"tags": [String(district), "beached"]})
		if deep != Vector2.INF and shore.distance_to(deep) < 40.0:
			var length := shore.distance_to(deep) + 4.0
			var base := shore - sea * 1.0
			var y := maxf(WorldData.get_height(base.x, base.y), 0.6) + 0.3
			plan.add(&"pier", Vector3(base.x, y, base.y), NwtPlanner.yaw_dir(sea), {"L": length, "W": 3.2, "depth": y + 4.0, "head": 0.0}, 1, "", length * 0.5)
			plan.anchor(&"fisher", Vector3(deep.x, y, deep.y), NwtPlanner.yaw_dir(sea), {"tags": [String(district), "pier"]})


func _warden_camp(c: Vector3, district: StringName, radius: float) -> void:
	_fire(c, district)
	var tower := _ground(c + Vector3(radius * 0.45, 0, -radius * 0.2))
	if plan.is_free(tower.x, tower.z, 4.0):
		plan.reserve(tower.x, tower.z, 4.5)
		plan.add(&"city_tower", tower, 0.0, {"r": 3.0, "h": 13.0, "spire": 7.0, "base": -1.5}, 2, "city_tower:30:13:7:-15", 4.0)
		plan.anchor(&"guard_post", tower + Vector3(0, 0, -4.0), PI, {"tags": [String(district), "lookout"]})
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		var p := c + Vector3(cos(a), 0, sin(a)) * radius * 0.42
		var yaw := NwtPlanner.yaw_dir(Vector2(c.x - p.x, c.z - p.z))
		var kind: StringName = &"igloo" if k % 2 == 0 else &"hide_tent"
		var pc := _place(kind, p, yaw, k % 3, 3.6)
		if not pc.is_empty():
			plan.anchor(&"home", NwtDistricts.world(pc["pos"], yaw, Vector3(0, 0, -3.5)), yaw + PI, {"tags": [String(district), "warden"]})
	_place(&"banner_pole", c + Vector3(-3.0, 0, 3.0), 0.0, 2, 1.0, 2)
	_place(&"crates", c + Vector3(-7.0, 0, -6.0), 0.2, 1, 1.6, 0)
	_place(&"fish_rack", c + Vector3(6.0, 0, 8.0), 0.7, 1, 2.6)
	plan.anchor(&"quest_giver", c + Vector3(2.5, 0, 2.0), 0.0, {"tags": [String(district), "warden_captain"]})
	var ring := PackedVector3Array()
	for k in 9:
		var a := TAU * k / 8.0
		ring.append(_ground(c + Vector3(cos(a), 0, sin(a)) * radius * 0.8))
	plan.anchor(&"patrol", ring[0], 0.0, {"points": ring, "loop": true, "tags": [String(district)]})
