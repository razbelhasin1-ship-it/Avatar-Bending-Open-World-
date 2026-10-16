class_name PoiStructures
extends RefCounted
## Structures for WorldData POIs by type, styled by the nation of their region (thread-safe):
##   shrine (per-nation shrine + offerings; marker group &"shrine" = respawn point), ruin (broken
##   walls, toppled columns, rubble, overgrowth), camp (tents around a fire pit, palisade with a
##   gate, crates, weapon rack, banner; &"enemy_spawn" markers for the enemy module), training
##   ground (posts, straw dummies, mats, racks, element props), dock (pier from the port quay to the
##   berth, moored boats, crates, lanterns), vista (overlook platform facing the view, cairn,
##   prayer flags), spirit spot (glowing standing stones / spirit tree, motes), resource
##   (crystal/bone nodes + ResourcePickups), landmark (lighthouse, pass gate, or a carved stele).
## Types handled elsewhere: waterfall/cave/bridge (LandmarkProvider), village (settlements).
##
## build(poi, lod) -> {"kit": KitResult (relative to origin), "origin": Vector3, "extras": [...]}
## extras (main thread, PoiProvider): {"type": &"pickup", "item", "count", "name", "position",
## "mesh_kind"}, {"type": &"marker", "group", "position", "yaw"}, {"type": &"particles", "kind":
## &"motes"|&"steam"|&"smoke"|&"embers", "position"}, {"type": &"sound", "name", "position", "db"}.

const SKIP_TYPES: Array[StringName] = [&"waterfall", &"cave", &"bridge", &"village"]


static func handles(poi: Dictionary) -> bool:
	if SKIP_TYPES.has(poi.get("type", &"")):
		return false
	# POIs inside cities (and, except docks, villages) belong to the settlement builders
	if _in_city(poi["position"], poi.get("type") != &"dock", poi.get("type") == &"landmark"):
		return false
	if poi.get("type") == &"landmark" and _is_feature(String(poi["id"])):
		return false
	return true


## Settlement territory: inside a city's tiers (+15 m; the whole city radius for landmarks such as
## gates) and, except for docks, inside a village footprint.
static func _in_city(p: Vector3, villages: bool = false, full: bool = false) -> bool:
	for c in WorldData.get_cities():
		var rc: Variant = c.get("ring_center")
		var ctr := Vector2((rc as Vector2).x, (rc as Vector2).y) if rc is Vector2 else Vector2((c["center"] as Vector3).x, (c["center"] as Vector3).z)
		var r := float(c.get("radius", 300.0)) + 20.0
		if not full:
			var tiers := 0.0
			for t: Dictionary in c.get("tiers", []):
				tiers = maxf(tiers, float(t.get("r_outer", 0.0)))
			r = (tiers if tiers > 0.0 else float(c.get("radius", 300.0)) * 0.96) + 15.0
		if ctr.distance_to(Vector2(p.x, p.z)) < r:
			return true
	if villages:
		for v in WorldData.get_villages():
			var vc: Vector3 = v["center"]
			if Vector2(vc.x, vc.z).distance_to(Vector2(p.x, p.z)) < float(v.get("radius", 60.0)):
				return true
	return false


## Radius of the structure footprint (vegetation keep-out), 0 when nothing is built.
static func footprint(poi: Dictionary) -> float:
	if not handles(poi):
		return 0.0
	var r := float(poi.get("radius", 20.0))
	match poi.get("type", &""):
		&"shrine": return 7.0
		&"camp": return clampf(r * 0.6, 10.0, 22.0) + 3.0
		&"training_ground": return clampf(r * 0.55, 8.0, 18.0) * 1.1 + 2.0
		&"ruin": return r * 0.55 + 2.0
		&"vista": return 6.0
		&"spirit_spot": return clampf(r * 0.45, 5.0, 14.0) + 2.0
		&"resource": return clampf(r * 0.6, 8.0, 18.0) + 2.0
		&"landmark": return 9.0
	return 0.0


static func _is_feature(id: String) -> bool:
	for a in WorldData.get_arches():
		if String(a["id"]) == id:
			return true
	return id.ends_with("_basin") or id.ends_with("_lake") or id.ends_with("_maze") or id.ends_with("_canyon") \
			or id.ends_with("_flats") or id.ends_with("_maw") or id.ends_with("_throat") or id.ends_with("_cirque") or id.contains("groaning")


## Facing for a POI: its yaw if given, else downhill (vistas) or towards the nearest road.
static func facing(poi: Dictionary) -> float:
	if poi.has("yaw"):
		return float(poi["yaw"])
	var p: Vector3 = poi["position"]
	if poi.get("type") == &"vista":
		var n := WorldData.get_normal(p.x, p.z)
		var down := Vector2(n.x, n.z)
		if down.length() > 0.02:
			return atan2(-down.x, -down.y) + PI
	var best := INF
	var best_p := Vector2.ZERO
	for r in WorldData.get_roads():
		var pts: PackedVector3Array = r["points"]
		for i in range(0, pts.size(), 3):
			var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
			if d < best:
				best = d
				best_p = Vector2(pts[i].x, pts[i].z)
	if best < 250.0 * 250.0:
		var v := best_p - Vector2(p.x, p.z)
		return atan2(-v.x, -v.y)
	return ContentHash.unit(ContentHash.hash_name(String(poi.get("id", "")))) * TAU


static func build(poi: Dictionary, lod: int = 0) -> Dictionary:
	var pos: Vector3 = poi["position"]
	var region: StringName = poi.get("region", WorldData.get_region(pos.x, pos.z))
	var nation := NationPalette.nation_for_region(region)
	var seed := ContentHash.hash_name(String(poi.get("id", "poi")))
	var kit := BuildingKit.new(NationPalette.get_palette(nation), lod, seed)
	var yaw := facing(poi)
	if poi.get("type") == &"landmark" and String(poi.get("id", "")).ends_with("_gate"):
		# a gate straddles the road: centre it on the nearest road point, passage along the road
		var rd := nearest_road(pos, 45.0)
		if not rd.is_empty():
			pos = rd["point"]
			var dv: Vector3 = rd["dir"]
			yaw = atan2(-dv.x, -dv.z)
	var origin := Vector3(pos.x, WorldData.get_height(pos.x, pos.z), pos.z)
	var ctx := {"kit": kit, "origin": origin, "yaw": yaw, "poi": poi, "extras": [], "nation": nation, "rng": ContentHash.rng(seed)}
	kit.push(Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO))
	match poi.get("type", &""):
		&"shrine": _shrine(ctx)
		&"ruin": PoiSites.ruin(ctx)
		&"camp": _camp(ctx)
		&"training_ground": _training(ctx)
		&"dock": PoiSites.dock(ctx)
		&"vista": _vista(ctx)
		&"spirit_spot": _spirit(ctx)
		&"resource": _resource(ctx)
		&"landmark": _landmark(ctx)
	kit.pop()
	return {"kit": kit.build(), "origin": origin, "extras": ctx["extras"], "yaw": yaw}


# --- helpers ------------------------------------------------------------------------------------

## Nearest point on any road polyline within max_dist: {"point": Vector3, "dir": Vector3 (unit,
## along the road)}, or {}.
static func nearest_road(p: Vector3, max_dist: float) -> Dictionary:
	var best := max_dist
	var out := {}
	var q := Vector2(p.x, p.z)
	for r in WorldData.get_roads():
		var pts: PackedVector3Array = r["points"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var c := a + ab * t
			var d := q.distance_to(c)
			if d < best:
				best = d
				out = {"point": Vector3(c.x, 0.0, c.y), "dir": Vector3(ab.x, 0.0, ab.y).normalized()}
	return out


## Local point (in the POI frame) dropped onto the terrain; returns local coordinates.
static func ground(ctx: Dictionary, local: Vector3) -> Vector3:
	var origin: Vector3 = ctx["origin"]
	var w := origin + Basis(Vector3.UP, float(ctx["yaw"])) * local
	return Vector3(local.x, WorldData.get_height(w.x, w.z) - origin.y + local.y, local.z)


## Foundation slab under a footprint so structures sit level on slopes.
static func platform(ctx: Dictionary, w: float, d: float, role: Variant = &"stone") -> void:
	var kit: BuildingKit = ctx["kit"]
	var lo := 0.0
	for k in 9:
		var p := ground(ctx, Vector3((k % 3 - 1) * w * 0.5, 0, (k / 3 - 1) * d * 0.5))
		lo = minf(lo, p.y)
	kit.box(Vector3(0, (lo - 0.6) * 0.5 + 0.1, 0), Vector3(w, absf(lo - 0.6) + 0.2, d), role)


static func extra(ctx: Dictionary, d: Dictionary) -> void:
	var local: Vector3 = d.get("position", Vector3.ZERO)
	d["position"] = (ctx["origin"] as Vector3) + Basis(Vector3.UP, float(ctx["yaw"])) * local
	(ctx["extras"] as Array).append(d)


# --- types ----------------------------------------------------------------------------------------

static func _shrine(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	platform(ctx, 4.4, 4.4)
	BuildingPresets.shrine(kit, Transform3D(Basis(), Vector3(0, 0.1, 0)), {"size": 1.3})
	# offerings: incense, flowers, candles before the shrine
	if kit.lod == 0:
		var front := Vector3(0, 0.75, -1.1)
		kit.box(front, Vector3(1.0, 0.1, 0.4), &"wood_dark", false)
		var gb := kit.g(&"glow")
		gb.uv = Vector2(0, 1)
		for k in 3:
			var p := front + Vector3(-0.3 + k * 0.3, 0.05, 0)
			kit.g().cylinder(p, p + Vector3(0, 0.35, 0), 0.01, 0.01, 3, kit.col(&"wood_dark"), 0)
			kit.g(&"glow").blob(p + Vector3(0, 0.36, 0), 0.025, 0, Color(1.0, 0.5, 0.2))
		for k in 4:
			kit.g().blob(front + Vector3(-0.4 + k * 0.27, 0.12, 0.12), 0.07, 0, kit.col(&"cloth_alt"))
	extra(ctx, {"type": &"marker", "group": &"shrine", "position": Vector3(0, 0.2, -3.4), "yaw": float(ctx["yaw"]) + PI})
	extra(ctx, {"type": &"particles", "kind": &"smoke", "position": Vector3(0, 1.2, -1.1)})


static func _camp(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var r := clampf(float((ctx["poi"] as Dictionary).get("radius", 22.0)) * 0.6, 10.0, 22.0)
	var nation: StringName = ctx["nation"]
	var tent_style: StringName = {&"water_tribe": &"yurt", &"air_nomads": &"tipi"}.get(nation, &"ridge")
	# fire pit: stone ring + fire + light
	var fp := ground(ctx, Vector3.ZERO)
	for k in 9:
		var a := TAU * k / 9.0
		kit.g().blob(fp + Vector3(cos(a) * 0.9, 0.1, sin(a) * 0.9), 0.22, 0, kit.col(&"stone_dark"), rng, 0.2, Vector3(1.2, 0.8, 1.0), Vector3.INF, 0.0, kit.col(&"stone_dark") * 0.8, Vector2.ZERO, true)
	for k in 4:
		var a := TAU * k / 4.0 + 0.3
		kit.beam(fp + Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), fp + Vector3(-cos(a) * 0.1, 0.45, -sin(a) * 0.1), 0.1, 0.1, &"wood_dark")
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 1)
	for k in 3:
		var q := fp + Vector3(rng.randf_range(-0.2, 0.2), 0.15, rng.randf_range(-0.2, 0.2))
		gb.cone(q, q + Vector3(0, 0.55 + 0.2 * k, 0), 0.22, 5, Color(1.0, 0.5, 0.12))
	kit.add_light(fp + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.3), 12.0, 2.2, 2)
	extra(ctx, {"type": &"particles", "kind": &"smoke", "position": fp + Vector3(0, 0.8, 0)})
	# tents on a ring, doors facing the fire
	var tents := 4 + rng.randi() % 3
	for k in tents:
		var a := TAU * float(k) / tents + rng.randf_range(-0.2, 0.2)
		var p := ground(ctx, Vector3(cos(a) * r * 0.55, 0, sin(a) * r * 0.55))
		var face := atan2(cos(a), sin(a))
		BuildingPresets.tent(kit, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p - Vector3(0, 0.1, 0)),
				{"style": tent_style, "w": 3.2, "d": 3.8, "h": 2.5, "role": &"cloth_alt" if k % 2 else &"cloth"})
		extra(ctx, {"type": &"marker", "group": &"enemy_spawn", "position": Vector3(cos(a) * r * 0.4, 0.2, sin(a) * r * 0.4), "yaw": -a})
	# palisade ring with a gate facing the yaw front (-Z)
	if kit.lod < 2:
		var posts := int(TAU * r / 1.1)
		for k in posts:
			var a := TAU * float(k) / posts
			var dir := Vector3(cos(a), 0, sin(a))
			if dir.dot(Vector3(0, 0, -1)) > 0.97:
				continue
			var p := ground(ctx, dir * r)
			var h := rng.randf_range(2.2, 2.8)
			kit.g().cylinder(p - Vector3(0, 0.3, 0), p + Vector3(0, h, 0), 0.16, 0.13, 5, kit.col(&"wood"), 0)
			kit.g().cone(p + Vector3(0, h, 0), p + Vector3(0, h + 0.35, 0), 0.13, 5, kit.col(&"wood_dark"), false)
			kit.collide_box(p + Vector3(0, h * 0.5, 0), Vector3(0.6, h, 0.6))
		for s: float in [-1.0, 1.0]:
			var gp := ground(ctx, Vector3(s * 2.0, 0, -r))
			kit.box(gp + Vector3(0, 1.8, 0), Vector3(0.5, 3.6, 0.5), &"wood_dark", true)
		kit.flag(Transform3D(Basis(), ground(ctx, Vector3(2.8, 0, -r - 0.8))), 5.0, 1.4, 0.9, {"role": &"cloth", "alt_role": &"wood_dark"})
	# crates, barrels, weapon rack
	for k in 5:
		var a := rng.randf() * TAU
		var p := ground(ctx, Vector3(cos(a) * r * 0.8, 0, sin(a) * r * 0.8))
		if k % 2 == 0:
			kit.box(p + Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8), &"wood", true)
			kit.box(p + Vector3(0.1, 1.05, 0.05), Vector3(0.5, 0.5, 0.5), &"wood_dark", true)
		else:
			kit.cylinder(p, 0.9, 0.35, &"wood", 8, true)
	var rack := ground(ctx, Vector3(r * 0.3, 0, r * 0.25))
	kit.beam(rack + Vector3(-1.0, 1.1, 0), rack + Vector3(1.0, 1.1, 0), 0.1, 0.1, &"wood")
	for s: float in [-1.0, 1.0]:
		kit.beam(rack + Vector3(s, 0, 0), rack + Vector3(s, 1.2, 0), 0.1, 0.1, &"wood")
	for k in 4:
		kit.beam(rack + Vector3(-0.7 + k * 0.45, 0.05, 0.25), rack + Vector3(-0.6 + k * 0.45, 1.6, -0.05), 0.04, 0.04, &"metal")
	extra(ctx, {"type": &"marker", "group": &"camp_center", "position": Vector3(0, 0.2, 0), "yaw": 0.0})


static func _training(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var nation: StringName = ctx["nation"]
	var r := clampf(float((ctx["poi"] as Dictionary).get("radius", 25.0)) * 0.55, 8.0, 18.0)
	var top := 0.2
	var half := r * 0.7
	# sparring floor with a stone curb, mats in the middle
	var floor_role: Variant = {&"water_tribe": &"ice", &"fire_nation": &"stone_dark", &"air_nomads": &"stone"}.get(nation, &"floor")
	var prev := kit.default_slot
	if nation == &"water_tribe":
		kit.default_slot = &"ice"
	platform(ctx, half * 2.0, half * 2.0, floor_role)
	kit.default_slot = prev
	for k in 4:
		var t := Transform3D(Basis(Vector3.UP, k * PI * 0.5), Vector3.ZERO)
		kit.box(t * Vector3(0, top + 0.12, half - 0.3), Vector3(half * 2.0 if k % 2 == 0 else 0.6, 0.24, 0.6 if k % 2 == 0 else half * 2.0), &"stone_dark", false)
	if kit.lod == 0:
		# paving joints
		for k in range(1, 6):
			var z := -half + half * 2.0 * k / 6.0
			kit.box(Vector3(0, top + 0.005, z), Vector3(half * 2.0 - 0.8, 0.02, 0.06), &"stone_dark", false)
	kit.box(Vector3(0, top + 0.03, -r * 0.05), Vector3(r * 0.62, 0.06, r * 0.62), &"cloth", false)
	kit.box(Vector3(0, top + 0.05, -r * 0.05), Vector3(r * 0.5, 0.06, r * 0.5), &"cloth_alt", false)
	if kit.lod == 0:
		kit.g().cylinder(Vector3(0, top + 0.08, -r * 0.05), Vector3(0, top + 0.09, -r * 0.05), r * 0.14, r * 0.14, 16, kit.col(&"accent"), 1)
	# entrance gate (front, -Z): two pillars, double crossbeam, banners
	var gz := -half + 0.3
	var gw := 3.2
	for s: float in [-1.0, 1.0]:
		kit.column(Vector3(s * gw, top, gz), 4.4, 0.22, &"wood", &"round", &"stone_dark")
		if kit.lod < 2:
			kit.banner(Transform3D(Basis(), Vector3(s * gw, top + 3.6, gz - 0.3)), 0.6, 2.0)
	kit.beam(Vector3(-gw - 0.8, top + 4.5, gz), Vector3(gw + 0.8, top + 4.5, gz), 0.34, 0.34, &"roof")
	kit.beam(Vector3(-gw, top + 3.85, gz), Vector3(gw, top + 3.85, gz), 0.2, 0.2, &"trim")
	if kit.lod == 0:
		for s: float in [-1.0, 1.0]:
			kit.ornament(Vector3(s * (gw + 0.8), top + 4.7, gz), &"horn", 0.5, &"trim", Vector3(s, 1, 0).normalized())
	# master's pavilion at the back (+Z): raised dais, four columns, nation roof
	var pz := half - 3.6
	var pw := 6.0
	var pd := 4.2
	kit.box(Vector3(0, top + 0.3, pz), Vector3(pw + 0.6, 0.6, pd + 0.6), &"base", true)
	kit.stairs(Vector3(0, top, pz - pd * 0.5 - 1.2), Vector3(0, top + 0.6, pz - pd * 0.5 - 0.3), 2.0, {"role": &"stone"})
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.column(Vector3(sx * (pw * 0.5 - 0.3), top + 0.6, pz + sz * (pd * 0.5 - 0.3)), 2.8, 0.18, &"wood", &"round", &"stone_dark")
	var roof_c := Vector3(0, top + 3.4, pz)
	match nation:
		&"air_nomads":
			KitRoofs.cone(kit, roof_c, pw * 0.62, 2.6, {"sides": 12, "flare": 0.45})
		&"water_tribe":
			KitRoofs.dome(kit, roof_c, pw * 0.48, {"squash": 0.55, "block_lines": true, "slot": &"ice"})
		_:
			KitRoofs.hip(kit, roof_c, pw, pd, 1.8, {"overhang": 0.8, "curve": 0.5, "ornaments": kit.lod == 0})
	if kit.lod == 0:
		kit.box(Vector3(0, top + 1.0, pz + pd * 0.5 - 0.4), Vector3(1.6, 0.8, 0.5), &"wood_dark", true)
		kit.box(Vector3(0, top + 2.3, pz + pd * 0.5 - 0.2), Vector3(2.4, 1.0, 0.06), &"cloth", false)
	# corner posts with banners
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			if sz > 0.0:
				continue
			var p := Vector3(sx * (half - 0.3), top, sz * (half - 0.3))
			kit.column(p, 3.4, 0.16, &"wood", &"round", &"stone_dark")
			if kit.lod < 2:
				kit.flag(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, 0.0, 0)), 5.0, 1.0, 0.6)
	# straw dummies on poles (a row on the left side)
	for k in 4:
		var p := Vector3(-half + 2.2, top, -half * 0.55 + k * 2.4)
		_dummy(kit, p)
		extra(ctx, {"type": &"marker", "group": &"training_dummy", "position": p, "yaw": float(ctx["yaw"]) + PI * 0.5})
	# element-specific props on the right side
	var side_x := half * 0.55
	match nation:
		&"earth_kingdom":
			for k in 5:
				var p := Vector3(side_x + rng.randf_range(-1.0, 1.0), top, -half * 0.5 + k * 2.6)
				var sz := rng.randf_range(0.8, 1.3)
				kit.box(p + Vector3(0, sz * 0.5, 0), Vector3(sz, sz, sz), &"stone", true)
		&"fire_nation":
			for k in 4:
				kit.brazier(Vector3(side_x, top, -half * 0.5 + k * 3.0), {"height": 0.9, "light": k % 2 == 0})
		&"water_tribe":
			kit.default_slot = &"ice"
			for k in 5:
				kit.cylinder(Vector3(side_x + rng.randf_range(-1.0, 1.0), top - 0.1, -half * 0.5 + k * 2.4), rng.randf_range(1.4, 2.8), 0.35, &"ice", 6, true, 0.2)
			kit.default_slot = prev
		&"air_nomads":
			# airball poles: tall poles with small platforms
			for k in 7:
				var h := rng.randf_range(2.0, 4.5)
				var p := Vector3(side_x + (k % 2) * 1.6 - 0.8, top, -half * 0.55 + k * 1.6)
				kit.cylinder(p, h, 0.12, &"wood", 6, true)
				kit.cylinder(p + Vector3(0, h, 0), 0.12, 0.42, &"trim", 10, true)
	# staff rack and bench along the curb
	var rack := Vector3(half - 1.2, top, -half + 2.5)
	kit.beam(rack + Vector3(0, 1.0, -0.9), rack + Vector3(0, 1.0, 0.9), 0.1, 0.1, &"wood")
	for s: float in [-1.0, 1.0]:
		kit.beam(rack + Vector3(0, 0, s * 0.9), rack + Vector3(0, 1.1, s * 0.9), 0.1, 0.1, &"wood")
	if kit.lod == 0:
		for k in 4:
			kit.beam(rack + Vector3(0.15, 0.05, -0.6 + k * 0.4), rack + Vector3(-0.1, 1.7, -0.55 + k * 0.4), 0.04, 0.04, &"wood_dark")
	extra(ctx, {"type": &"marker", "group": &"trainer_spot", "position": Vector3(0, top + 0.6, pz), "yaw": float(ctx["yaw"]) + PI})


## Straw training dummy (pole, cross arms, straw body, sack head).
static func _dummy(kit: BuildingKit, p: Vector3) -> void:
	kit.g().cylinder(p, p + Vector3(0, 1.9, 0), 0.06, 0.06, 5, kit.col(&"wood_dark"), 0)
	kit.beam(p + Vector3(-0.55, 1.35, 0), p + Vector3(0.55, 1.35, 0), 0.07, 0.07, &"wood_dark")
	var straw := Color(0.80, 0.66, 0.36).srgb_to_linear()
	kit.g().blob(p + Vector3(0, 1.15, 0), 0.32, 1 if kit.lod == 0 else 0, straw, kit.rng, 0.12, Vector3(0.9, 1.5, 0.75))
	kit.g().blob(p + Vector3(0, 1.75, 0), 0.2, 1 if kit.lod == 0 else 0, Color(0.72, 0.62, 0.45).srgb_to_linear(), kit.rng, 0.08)
	kit.g().cylinder(p + Vector3(0, 0.95, 0), p + Vector3(0, 1.0, 0), 0.31, 0.31, 8, kit.col(&"cloth"), 3)
	kit.collide_box(p + Vector3(0, 1.0, 0), Vector3(0.6, 2.0, 0.5))


static func _vista(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	# overlook terrace facing the view (-Z): half-round stone platform with a railing
	platform(ctx, 6.0, 5.0, &"stone")
	var rail := PackedVector3Array()
	for k in 9:
		var a := PI + PI * float(k) / 8.0
		rail.append(Vector3(cos(a) * 2.9, 0.2, sin(a) * 2.4 - 0.1))
	kit.railing(rail, 0.9, {"role": &"stone", "post_role": &"stone_dark", "rails": 1, "spacing": 1.0})
	# cairn of stacked stones
	var cp := Vector3(2.2, 0.2, 1.6)
	var y := 0.0
	for k in 5:
		var r := 0.45 - k * 0.07
		kit.g().blob(cp + Vector3(rng.randf_range(-0.05, 0.05), y + r * 0.6, 0), r, 0, kit.col(&"stone") * rng.randf_range(0.85, 1.05), rng, 0.15, Vector3(1.2, 0.6, 1.0), Vector3.INF, 0.0, kit.col(&"stone_dark"), Vector2.ZERO, true)
		y += r * 1.1
	# bench and a pole with prayer flags / pennant
	kit.box(Vector3(-1.6, 0.65, 1.4), Vector3(1.8, 0.1, 0.5), &"wood", true)
	for s: float in [-1.0, 1.0]:
		kit.box(Vector3(-1.6 + s * 0.7, 0.42, 1.4), Vector3(0.12, 0.45, 0.4), &"wood_dark", false)
	kit.flag(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(-2.6, 0.2, 2.0)), 4.5, 1.2, 0.7)
	extra(ctx, {"type": &"marker", "group": &"vista", "position": Vector3(0, 0.3, -1.0), "yaw": float(ctx["yaw"])})


static func _spirit(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var id := String((ctx["poi"] as Dictionary).get("id", ""))
	var r := clampf(float((ctx["poi"] as Dictionary).get("radius", 20.0)) * 0.45, 5.0, 14.0)
	var glow_c := Color(0.45, 0.95, 0.85)
	if id.contains("vent"):
		glow_c = Color(1.0, 0.55, 0.2)
	elif id.contains("koi") or id.contains("oasis"):
		glow_c = Color(0.7, 0.85, 1.0)
	# standing stones circle with glowing runes
	var n := 7
	for k in n:
		var a := TAU * float(k) / n
		var p := ground(ctx, Vector3(cos(a) * r, 0, sin(a) * r))
		var h := rng.randf_range(1.8, 3.2)
		kit.box_t(Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08)), p + Vector3(0, h * 0.5 - 0.3, 0)), Vector3(0.9, h, 0.5), &"stone_dark", true)
		var gb := kit.g(&"glow")
		gb.uv = Vector2(0, 0.25)
		var face := Vector3(-cos(a), 0, -sin(a))
		for j in 3:
			gb.box(Transform3D(Basis(Vector3.UP, -a), p + face * 0.27 + Vector3(0, h * 0.35 + j * 0.42, 0)), Vector3(0.35, 0.08, 0.04), glow_c)
	if id.contains("banyan") or id.contains("tree") or id.contains("ledge"):
		_spirit_tree(kit, ground(ctx, Vector3.ZERO), rng, glow_c)
	else:
		# glowing heart stone
		var c := ground(ctx, Vector3.ZERO)
		kit.g(&"glow").blob(c + Vector3(0, 0.9, 0), 0.7, 1, glow_c, rng, 0.2, Vector3(0.8, 1.3, 0.8))
		kit.g().blob(c + Vector3(0, 0.2, 0), 1.2, 0, kit.col(&"stone_dark"), rng, 0.25, Vector3(1.2, 0.5, 1.2), Vector3.INF, 0.0, kit.col(&"stone_dark"), Vector2.ZERO, true)
	kit.add_light(ground(ctx, Vector3(0, 2.0, 0)), glow_c, 14.0, 1.6, 3)
	extra(ctx, {"type": &"particles", "kind": &"steam" if id.contains("vent") else &"motes", "position": Vector3(0, 1.0, 0)})
	extra(ctx, {"type": &"marker", "group": &"spirit_spot", "position": Vector3(0, 0.3, 0), "yaw": 0.0})
	extra(ctx, {"type": &"pickup", "item": &"spirit_blossom", "count": 1, "name": "Spirit Blossom", "position": ground(ctx, Vector3(r * 0.55, 0.05, r * 0.2)), "mesh_kind": &"blossom"})


## Great twisted tree with glowing leaves and aerial roots (the Whispering Banyan).
static func _spirit_tree(kit: BuildingKit, p: Vector3, rng: RandomNumberGenerator, glow_c: Color) -> void:
	var bark := Color(0.28, 0.24, 0.22).srgb_to_linear()
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf() * 0.4
		var pts := PackedVector3Array([p + Vector3(cos(a) * 1.6, -0.3, sin(a) * 1.6), p + Vector3(cos(a) * 0.7, 3.0, sin(a) * 0.7),
			p + Vector3(cos(a + 0.6) * 0.5, 6.0, sin(a + 0.6) * 0.5), p + Vector3(cos(a + 1.2) * 3.5, 9.5, sin(a + 1.2) * 3.5)])
		kit.g().tube(pts, PackedFloat32Array([1.0, 0.7, 0.55, 0.25]), 7, bark)
	kit.collide_box(p + Vector3(0, 3.0, 0), Vector3(2.4, 6.0, 2.4))
	var leaf := Color(0.22, 0.55, 0.42).srgb_to_linear()
	for k in 9:
		var a := TAU * k / 9.0
		var c := p + Vector3(cos(a) * rng.randf_range(2.5, 6.0), rng.randf_range(8.5, 11.0), sin(a) * rng.randf_range(2.5, 6.0))
		kit.g().blob(c, rng.randf_range(2.2, 3.2), 1, leaf, rng, 0.2, Vector3(1.0, 0.6, 1.0), p + Vector3(0, 8, 0), 0.6, leaf * 0.6)
		var gb := kit.g(&"glow")
		gb.uv = Vector2(0, 0.3)
		for j in 3:
			gb.blob(c + Vector3(rng.randf_range(-2, 2), rng.randf_range(-1.2, 0.2), rng.randf_range(-2, 2)), 0.25, 0, glow_c)
	for k in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.0, 6.0)
		var top := p + Vector3(cos(a) * d, rng.randf_range(7.5, 9.0), sin(a) * d)
		kit.g().cylinder(Vector3(top.x, p.y - 0.2, top.z), top, 0.07, 0.05, 4, bark * 1.2, 0)


static func _resource(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var id := String((ctx["poi"] as Dictionary).get("id", ""))
	var r := clampf(float((ctx["poi"] as Dictionary).get("radius", 25.0)) * 0.6, 8.0, 18.0)
	var kind: StringName = &"jade" if id.contains("jade") else (&"bone" if id.contains("whale") else &"ore")
	var item: StringName = {&"jade": &"jade_shard", &"bone": &"whale_bone"}.get(kind, &"iron_ore")
	var nm: String = {&"jade": "Jade Shard", &"bone": "Whale Bone"}.get(kind, "Iron Ore")
	if kind == &"bone":
		_whale_skeleton(ctx, rng)
	else:
		# outcrops studded with crystals (jade) or dark ore rock, cut blocks and a hoist
		for k in 6:
			var a := TAU * float(k) / 6.0 + rng.randf_range(-0.3, 0.3)
			var d := rng.randf_range(0.35, 0.9) * r
			var p := ground(ctx, Vector3(cos(a) * d, 0, sin(a) * d))
			var rr := rng.randf_range(1.8, 3.0)
			var rock := kit.col(&"stone") if kind == &"jade" else kit.col(&"stone_dark")
			kit.g().blob(p, rr, 1, rock, rng, 0.3, Vector3(1.2, 0.75, 1.0), Vector3.INF, 0.0, rock * 0.7, Vector2.ZERO, true)
			kit.collide_box(p + Vector3(0, rr * 0.35, 0), Vector3(rr * 1.8, rr * 1.2, rr * 1.6))
			var gb := kit.g(&"glow")
			gb.uv = Vector2(0, 0.1)
			var cc := Color(0.22, 0.85, 0.48) if kind == &"jade" else Color(0.95, 0.6, 0.3)
			for j in (5 if kind == &"jade" else 3):
				var dir := Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)).normalized()
				var q := p + Vector3(rng.randf_range(-0.6, 0.6) * rr, rr * 0.45, rng.randf_range(-0.6, 0.6) * rr)
				var ln := rng.randf_range(1.0, 2.6) if kind == &"jade" else rng.randf_range(0.4, 0.8)
				gb.cylinder(q - dir * 0.3, q + dir * ln, rng.randf_range(0.22, 0.42), 0.03, 6, cc, 1, false)
			if k % 2 == 0:
				extra(ctx, {"type": &"pickup", "item": item, "count": 1, "name": nm,
					"position": ground(ctx, Vector3(cos(a) * (d + rr + 0.8), 0.05, sin(a) * (d + rr + 0.8))), "mesh_kind": kind})
		# stacks of cut blocks
		for k in 3:
			var c := ground(ctx, Vector3(-r * 0.4 + k * 2.6, 0, r * 0.55))
			for j in 3 - k % 2:
				kit.box(c + Vector3(rng.randf_range(-0.2, 0.2), 0.45 + j * 0.9, rng.randf_range(-0.2, 0.2)), Vector3(1.6, 0.9, 1.1), &"stone", true)
		# wooden hoist with a rope and a hanging block
		var hp := ground(ctx, Vector3(r * 0.5, 0, r * 0.3))
		for s2: float in [-1.0, 1.0]:
			kit.beam(hp + Vector3(s2 * 1.6, 0, -0.8), hp + Vector3(0, 5.0, 0), 0.18, 0.18, &"wood", false)
			kit.beam(hp + Vector3(s2 * 1.6, 0, 0.8), hp + Vector3(0, 5.0, 0), 0.18, 0.18, &"wood", false)
		kit.beam(hp + Vector3(0, 5.0, 0), hp + Vector3(0, 4.6, -3.2), 0.16, 0.16, &"wood_dark", false)
		kit.g().cylinder(hp + Vector3(0, 4.6, -3.1), hp + Vector3(0, 2.2, -3.1), 0.03, 0.03, 3, kit.col(&"wood_dark"), 0)
		kit.box(hp + Vector3(0, 1.8, -3.1), Vector3(0.9, 0.8, 0.9), &"stone", false)
		kit.collide_box(hp + Vector3(0, 2.0, 0), Vector3(3.0, 4.0, 1.8))
	# a worker's lean-to
	var lp := ground(ctx, Vector3(-r * 0.75, 0, -r * 0.55))
	BuildingPresets.tent(kit, Transform3D(Basis(Vector3.UP, 0.4), lp), {"style": &"ridge", "w": 2.6, "d": 3.0, "h": 2.0, "role": &"cloth_alt"})


## A beached whale skeleton: skull, a spine of vertebrae, two rows of arching ribs, flipper
## bones and scattered fragments (Whalefall Skerries); bones are the gatherable resource.
static func _whale_skeleton(ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var kit: BuildingKit = ctx["kit"]
	var bone := Color(0.90, 0.86, 0.76).srgb_to_linear()
	var old := Color(0.70, 0.66, 0.58).srgb_to_linear()
	var length := 26.0
	var n := 13
	var spine := PackedVector3Array()
	for i in n:
		var t := float(i) / (n - 1)
		var z := lerpf(-length * 0.5, length * 0.5, t)
		var g := ground(ctx, Vector3(sin(t * 3.0) * 1.2, 0, z))
		spine.append(Vector3(g.x, g.y + 0.6 + sin(t * PI) * 1.8, g.z))
	for i in n:
		var p := spine[i]
		var t := float(i) / (n - 1)
		kit.g().blob(p, 0.45 - t * 0.2, 0, bone.lerp(old, rng.randf()), rng, 0.15, Vector3(1.2, 1.0, 0.8))
		# ribs over the front two thirds, arching up and out like a hull
		if t > 0.12 and t < 0.7:
			var span := sin((t - 0.12) / 0.58 * PI) * 4.2 + 1.5
			for s: float in [-1.0, 1.0]:
				var g0 := ground(ctx, Vector3(p.x + s * span, 0, p.z))
				var tip := Vector3(p.x + s * span, g0.y + rng.randf_range(-0.2, 0.6), p.z + rng.randf_range(-0.5, 0.5))
				var mid := Vector3(p.x + s * span * 0.75, p.y + 2.2 + span * 0.25, p.z)
				if rng.randf() < 0.15:
					tip = mid.lerp(tip, 0.5)          # a broken rib
				kit.g().tube(PackedVector3Array([p, mid, tip]), PackedFloat32Array([0.24, 0.2, 0.12]), 6, bone, old)
				kit.collide_box((p + tip) * 0.5, Vector3(0.6, absf(p.y - tip.y) + 0.6, 0.6))
	# skull at the head end
	var head := spine[0] + Vector3(0, -0.2, -2.6)
	kit.g().blob(head, 2.0, 1, bone, rng, 0.12, Vector3(1.3, 0.75, 2.0), Vector3.INF, 0.0, old, Vector2.ZERO, true)
	kit.g().blob(head + Vector3(0, -0.3, -2.6), 1.0, 0, old, rng, 0.1, Vector3(1.6, 0.5, 2.0))
	kit.collide_box(head, Vector3(4.6, 2.6, 7.0))
	# flipper bones and fragments
	for s: float in [-1.0, 1.0]:
		var f0 := spine[3] + Vector3(s * 4.5, -1.2, 0)
		f0.y = ground(ctx, f0).y + 0.25
		kit.g().tube(PackedVector3Array([f0, f0 + Vector3(s * 1.4, 0.1, 1.6), f0 + Vector3(s * 2.2, 0.0, 3.6)]), PackedFloat32Array([0.2, 0.16, 0.08]), 5, old)
	for k in 9:
		var a := rng.randf() * TAU
		var d := rng.randf_range(6.0, 14.0)
		var p := ground(ctx, Vector3(cos(a) * d, 0.15, sin(a) * d))
		var dir := Vector3(cos(a * 3.0), 0.15, sin(a * 3.0))
		kit.g().tube(PackedVector3Array([p, p + dir * 1.2, p + dir * 2.0 + Vector3(0, 0.3, 0)]), PackedFloat32Array([0.16, 0.13, 0.08]), 5, bone.lerp(old, 0.5))
		if k % 3 == 0:
			extra(ctx, {"type": &"pickup", "item": &"whale_bone", "count": 1, "name": "Whale Bone", "position": p + Vector3(0, 0.1, 0), "mesh_kind": &"bone"})


static func _landmark(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var id := String((ctx["poi"] as Dictionary).get("id", ""))
	if id.contains("lantern_isle") or id.contains("lighthouse"):
		platform(ctx, 7.0, 7.0)
		kit.cylinder(Vector3(0, 0.1, 0), 14.0, 2.4, &"wall", 14, true, 1.8)
		for band: float in [3.0, 7.0, 11.0]:
			kit.cylinder(Vector3(0, band, 0), 0.6, 2.45 - band * 0.045, &"cloth", 14, false)
		kit.cylinder(Vector3(0, 14.1, 0), 0.4, 2.6, &"stone_dark", 14, true)
		var gb := kit.g(&"glow")
		gb.uv = Vector2(0, 0.3)
		gb.cylinder(Vector3(0, 14.5, 0), Vector3(0, 16.3, 0), 1.3, 1.3, 10, Color(1.0, 0.85, 0.5), 0)
		KitRoofs.cone(kit, Vector3(0, 16.4, 0), 2.0, 2.4, {"sides": 12})
		kit.add_light(Vector3(0, 15.5, 0), Color(1.0, 0.85, 0.55), 40.0, 3.0, 5)
		kit.door(Transform3D(Basis(), Vector3(0, 0.1, -2.35)), 1.2, 2.2)
		return
	if id.contains("pass_gate") or id.ends_with("_gate"):
		BuildingPresets.gatehouse(kit, Transform3D(Basis(), ground(ctx, Vector3.ZERO) - Vector3(0, 0.3, 0)), {"width": 8.5, "height": 6.0, "depth": 4.0})
		return
	# carved stele on a plinth with two lanterns
	platform(ctx, 4.0, 3.0)
	kit.box(Vector3(0, 0.4, 0), Vector3(2.6, 0.6, 1.4), &"stone_dark", true)
	kit.box(Vector3(0, 2.0, 0), Vector3(1.6, 2.6, 0.45), &"stone", true)
	if kit.lod == 0:
		for j in 5:
			kit.box(Vector3(0, 1.3 + j * 0.32, -0.24), Vector3(1.0 - (j % 2) * 0.3, 0.08, 0.03), &"stone_dark", false)
	kit.box(Vector3(0, 3.4, 0), Vector3(1.9, 0.25, 0.7), &"trim", false)
	for s: float in [-1.0, 1.0]:
		kit.lantern(Vector3(s * 1.8, 0.1, -0.9), {"style": &"stone", "height": 1.3, "light": s > 0.0})
