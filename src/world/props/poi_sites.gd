class_name PoiSites
extends RefCounted
## Ruins and waterfront POI structures for PoiStructures (thread-safe, BuildingKit-based):
##   ruin(ctx)       broken enclosure walls, columns, rubble and overgrowth, with a focal piece by
##                   id: a slanted broken tower ("tower"), a stepped temple with a broken colonnade
##                   ("temple") or a fallen gate arch
##   dock(ctx)       pier from the nearest shoreline (find_shore) into the water with a T-head
##                   berth, piles, lanterns, cargo, moored boats (BoatBuilder) and a boat shed
##   boat_shed(ctx)  shore shed (igloo in the Water Tribe) with a kayak rack
## ctx is the build context of PoiStructures.build ({"kit", "origin", "yaw", "poi", "extras",
## "nation", "rng"}); coordinates are in the POI frame (-Z = front).


static func ruin(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var r := float((ctx["poi"] as Dictionary).get("radius", 20.0)) * 0.55
	# broken enclosure: wall segments of uneven height with gaps
	var n := 10
	var moss := Color(0.30, 0.42, 0.18).srgb_to_linear()
	for k in n:
		if rng.randf() < 0.3:
			continue
		var a0 := TAU * float(k) / n
		var a1 := TAU * float(k + 1) / n
		var p0 := PoiStructures.ground(ctx, Vector3(cos(a0) * r, 0, sin(a0) * r))
		var p1 := PoiStructures.ground(ctx, Vector3(cos(a1) * r, 0, sin(a1) * r))
		var h := rng.randf_range(0.8, 4.2)
		var base := minf(p0.y, p1.y) - 0.4
		kit.wall(Vector3(p0.x, base, p0.z), Vector3(p1.x, base, p1.z), h, 0.8, {"role": &"stone", "cap": false})
		if kit.lod == 0 and rng.randf() < 0.6:
			var m := (p0 + p1) * 0.5
			kit.g().blob(Vector3(m.x, base + h + 0.1, m.z), 0.9, 0, moss, rng, 0.3, Vector3(1.5, 0.35, 0.8))
	# toppled and standing columns
	for k in 6:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.2, 0.8) * r
		var p := PoiStructures.ground(ctx, Vector3(cos(a) * d, 0, sin(a) * d))
		if rng.randf() < 0.5:
			kit.column(p - Vector3(0, 0.2, 0), rng.randf_range(1.5, 4.5), 0.4, &"stone", &"round", &"stone_dark")
		else:
			var dir := Vector3(cos(a + 1.2), 0, sin(a + 1.2))
			kit.g().cylinder(p + Vector3(0, 0.35, 0), p + Vector3(0, 0.35, 0) + dir * rng.randf_range(2.5, 4.0), 0.4, 0.4, 8, kit.col(&"stone"), 3)
			kit.collide_box(p + dir * 1.5 + Vector3(0, 0.35, 0), Vector3(1.0, 0.7, 1.0))
	# rubble
	for k in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 1.1) * r
		var p := PoiStructures.ground(ctx, Vector3(cos(a) * d, 0, sin(a) * d))
		kit.g().blob(p, rng.randf_range(0.3, 0.8), 0, kit.col(&"stone_dark"), rng, 0.3, Vector3(1.2, 0.7, 1.0), Vector3.INF, 0.0, kit.col(&"stone_dark") * 0.8, Vector2.ZERO, true)
	var id := String((ctx["poi"] as Dictionary).get("id", ""))
	if id.contains("tower"):
		_broken_tower(ctx, rng, moss)
	elif id.contains("temple"):
		_ruined_temple(ctx, rng, moss, r)
	else:
		# a fallen arch / gate frame as the focal point
		var g0 := PoiStructures.ground(ctx, Vector3(-2.5, 0, -r * 0.3))
		var g1 := PoiStructures.ground(ctx, Vector3(2.5, 0, -r * 0.3))
		kit.arch(Vector3(g0.x, minf(g0.y, g1.y) - 0.3, g0.z), Vector3(g1.x, minf(g0.y, g1.y) - 0.3, g1.z), 3.2, 0.9, 1.0, &"stone")
	PoiStructures.extra(ctx, {"type": &"marker", "group": &"ruin_loot", "position": Vector3(0, 0.2, 0), "yaw": 0.0})


## Hollow round tower broken off at a slant, with a doorway and fallen masonry.
static func _broken_tower(ctx: Dictionary, rng: RandomNumberGenerator, moss: Color) -> void:
	var kit: BuildingKit = ctx["kit"]
	var c := PoiStructures.ground(ctx, Vector3.ZERO) - Vector3(0, 0.5, 0)
	var radius := 3.2
	var n := 12
	for k in n:
		var a0 := TAU * float(k) / n
		var a1 := TAU * float(k + 1) / n
		var h := 6.0 + 7.0 * (0.5 + 0.5 * cos(a0 - 0.6)) + rng.randf_range(-1.2, 1.2)
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * radius
		var opts := {"role": &"stone", "cap": false}
		if k == 9:
			opts["openings"] = [{"t": 0.5, "width": 1.3, "height": 2.4, "kind": &"door", "leaf": &"none", "round": true}]
		elif k % 3 == 1 and h > 7.0:
			opts["openings"] = [{"t": 0.5, "width": 0.6, "height": 1.0, "sill": h - 3.0, "kind": &"window", "round": true}]
		kit.wall(p0, p1, h, 0.7, opts)
		if kit.lod == 0 and rng.randf() < 0.5:
			kit.g().blob((p0 + p1) * 0.5 + Vector3(0, h + 0.05, 0), 0.6, 0, moss, rng, 0.3, Vector3(1.4, 0.3, 0.9))
	if kit.lod == 0:
		for k in 6:
			kit.box(c + Vector3(0, 2.5 + k * 1.8, 0) + Vector3(cos(k * 1.7), 0, sin(k * 1.7)) * (radius - 0.9),
					Vector3(1.4, 0.2, 0.9), &"wood_dark", false)
	for k in 8:
		var a := rng.randf_range(-0.9, 0.9) + 0.6 + PI
		var d := radius + rng.randf_range(1.0, 6.0)
		var p := PoiStructures.ground(ctx, Vector3(cos(a) * d, 0, sin(a) * d))
		kit.g().blob(p, rng.randf_range(0.5, 1.1), 0, kit.col(&"stone"), rng, 0.25, Vector3(1.3, 0.7, 1.0), Vector3.INF, 0.0, kit.col(&"stone_dark"), Vector2.ZERO, true)


## Stepped temple platform with a broken colonnade and a toppled roof section.
static func _ruined_temple(ctx: Dictionary, rng: RandomNumberGenerator, moss: Color, r: float) -> void:
	var kit: BuildingKit = ctx["kit"]
	var w := clampf(r * 1.1, 10.0, 16.0)
	var d := w * 0.75
	var y := 0.0
	PoiStructures.platform(ctx, w + 3.0, d + 3.0, &"stone_dark")
	for step in 3:
		var sw := w - step * 2.2
		var sd := d - step * 1.8
		kit.box(Vector3(0, 0.2 + y + 0.35, 0), Vector3(sw, 0.7, sd), &"stone" if step % 2 == 0 else &"base", true)
		y += 0.7
	kit.stairs(Vector3(0, 0.2, -d * 0.5 - 1.6), Vector3(0, 0.2 + y, -(d - 4.4) * 0.5), 3.0, {"role": &"stone"})
	var top := 0.2 + y
	var cw := w - 5.4
	var cd := d - 4.6
	for k in 8:
		var t := float(k) / 7.0
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(lerpf(-cw * 0.5, cw * 0.5, t), top, sz * cd * 0.5)
			var h := 4.6 if rng.randf() < 0.35 else rng.randf_range(0.6, 3.2)
			kit.column(p, h, 0.38, &"stone", &"round", &"stone_dark")
			if kit.lod == 0 and h < 4.0 and rng.randf() < 0.6:
				kit.g().blob(p + Vector3(0, h, 0), 0.45, 0, moss, rng, 0.3, Vector3(1.2, 0.4, 1.2))
	# toppled roof slab and a lintel beam
	kit.box_t(Transform3D(Basis(Vector3.FORWARD, 0.35) * Basis(Vector3.UP, 0.2), Vector3(cw * 0.25, top + 1.1, 0)), Vector3(cw * 0.6, 0.5, cd * 0.7), &"roof", true)
	kit.beam(Vector3(-cw * 0.5, top + 4.75, -cd * 0.5), Vector3(-cw * 0.5 + 4.0, top + 4.75, -cd * 0.5), 0.8, 0.5, &"stone", true)
	# overgrowth: vines draped over the platform edges
	if kit.lod == 0:
		var vine := Color(0.20, 0.42, 0.16).srgb_to_linear()
		for k in 10:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a) * w * 0.48, top - rng.randf_range(0.0, 1.6), sin(a) * d * 0.48)
			kit.g().blob(p, rng.randf_range(0.7, 1.4), 0, vine, rng, 0.35, Vector3(1.3, 0.6, 1.3))


## Nearest shoreline from `origin`: [dry shore point, unit direction into the water, water level],
## or [] when there is no water within 150 m. `hint` (unit, may be zero) is tried first.
static func find_shore(origin: Vector3, hint: Vector3) -> Array:
	var best: Array = []
	var best_d := INF
	var dirs: Array[Vector3] = []
	if hint.length() > 0.1:
		dirs.append(Vector3(hint.x, 0, hint.z).normalized())
	for k in 16:
		dirs.append(Vector3(sin(TAU * k / 16.0), 0, cos(TAU * k / 16.0)))
	for i in dirs.size():
		var d := dirs[i]
		var last := origin
		var s := 0.0
		while s < 150.0:
			var p := origin + d * s
			var g := WorldData.get_height(p.x, p.z)
			var wh := WorldData.get_water_height(p.x, p.z)
			if wh > -INF and wh - g > 1.0:
				# prefer the hint direction unless another shore is much nearer
				var score := s * (0.6 if i == 0 and hint.length() > 0.1 else 1.0)
				if score < best_d:
					best_d = score
					best = [Vector3(last.x, WorldData.get_height(last.x, last.z), last.z), d, wh]
				break
			if wh <= -INF or wh < g:
				last = p
			s += 2.0
	return best


static func dock(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var origin: Vector3 = ctx["origin"]
	var basis := Basis(Vector3.UP, float(ctx["yaw"]))
	var inv := basis.inverse()
	var hint := Vector3.ZERO
	for port in WorldData.get_ports():
		var q: Vector3 = port["quay"]
		if Vector2(q.x - origin.x, q.z - origin.z).length() < 200.0:
			hint = (port["berth"] as Vector3) - q
	var shore := find_shore(origin, hint)
	if shore.is_empty():
		boat_shed(ctx, Vector3.ZERO)
		return
	var water_y: float = shore[2]
	var a := inv * ((shore[0] as Vector3) - origin)
	var dir := (inv * (shore[1] as Vector3)).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var deck_y := water_y + 1.1 - origin.y
	var length := 26.0 if kit.lod > 0 or rng.randf() < 0.5 else 34.0
	var start := a - dir * 3.0
	var w := 3.0
	var seg := 2.5
	var n := int(length / seg)
	for i in n:
		var c := start + dir * (i * seg)
		var c1 := c + dir * seg
		var wp := origin + basis * c
		var ground := WorldData.get_height(wp.x, wp.z) - origin.y
		var top := maxf(deck_y, ground + 0.25)
		kit.beam(Vector3(c.x, top - 0.12, c.z), Vector3(c1.x, top - 0.12, c1.z), w, 0.24, &"wood" if i % 2 else &"wood_dark")
		var hw := side * w * 0.5
		kit.collide_quad(Vector3(c.x, top, c.z) - hw, Vector3(c.x, top, c.z) + hw, Vector3(c1.x, top, c1.z) + hw, Vector3(c1.x, top, c1.z) - hw)
		if i % 2 == 0:
			for sg: float in [-1.0, 1.0]:
				var pile := c + side * sg * (w * 0.5 - 0.12)
				var bot := minf(ground, water_y - origin.y - 2.0)
				kit.g().cylinder(Vector3(pile.x, bot, pile.z), Vector3(pile.x, top + 0.6, pile.z), 0.15, 0.14, 6, kit.col(&"wood_dark"), 2)
				kit.collide_box(Vector3(pile.x, top + 0.3, pile.z), Vector3(0.3, 0.6, 0.3))
	var end := start + dir * (n * seg)
	# T-head berth at the end
	kit.beam(Vector3(end.x, deck_y - 0.12, end.z) - side * 5.0, Vector3(end.x, deck_y - 0.12, end.z) + side * 5.0, 3.0, 0.24, &"wood")
	var hw2 := dir * 1.5
	kit.collide_quad(Vector3(end.x, deck_y, end.z) - side * 5.0 - hw2, Vector3(end.x, deck_y, end.z) - side * 5.0 + hw2,
			Vector3(end.x, deck_y, end.z) + side * 5.0 + hw2, Vector3(end.x, deck_y, end.z) + side * 5.0 - hw2)
	for sg: float in [-1.0, 1.0]:
		var pc := end + side * sg * 4.8
		kit.g().cylinder(Vector3(pc.x, water_y - origin.y - 2.0, pc.z), Vector3(pc.x, deck_y + 0.6, pc.z), 0.16, 0.15, 6, kit.col(&"wood_dark"), 2)
		kit.lantern(Vector3(pc.x, deck_y, pc.z) + dir * 1.2, {"style": &"post", "height": 1.6, "range": 9.0, "light": sg > 0.0})
	# cargo on the pier: crates, barrels, a coil of rope
	for k in 4:
		var c := start + dir * rng.randf_range(4.0, length - 3.0) + side * rng.randf_range(-0.9, 0.9)
		if k % 2 == 0:
			kit.box(Vector3(c.x, deck_y + 0.35, c.z), Vector3(0.7, 0.7, 0.7), &"wood", true)
		else:
			kit.cylinder(Vector3(c.x, deck_y, c.z), 0.8, 0.3, &"wood_dark", 8, true)
	# moored boats alongside the T-head and the pier
	var yaw_b := atan2(-dir.x, -dir.z)
	for k in 2:
		var bc := end + side * (k * 2 - 1) * 2.2 + dir * 3.2
		kit.push(Transform3D(Basis(Vector3.UP, yaw_b + PI * 0.5 + rng.randf_range(-0.1, 0.1)), Vector3(bc.x, water_y - origin.y - 0.15, bc.z)))
		match ctx["nation"]:
			&"water_tribe": BoatBuilder.kayak(kit)
			&"earth_kingdom", &"fire_nation":
				if k == 0:
					BoatBuilder.sampan(kit)
				else:
					BoatBuilder.rowboat(kit)
			_: BoatBuilder.rowboat(kit)
		kit.pop()
	# boat shed on the shore
	boat_shed(ctx, a - dir * 7.0 + side * 5.0, yaw_b)
	PoiStructures.extra(ctx, {"type": &"marker", "group": &"dock_berth", "position": Vector3(end.x, deck_y + 0.1, end.z), "yaw": float(ctx["yaw"]) + yaw_b})


## Small shed with a gable roof, a kayak/net rack and crates (shore side of docks, landings).
static func boat_shed(ctx: Dictionary, local: Vector3, yaw: float = 0.0) -> void:
	var kit: BuildingKit = ctx["kit"]
	var p := PoiStructures.ground(ctx, local)
	kit.push(Transform3D(Basis(Vector3.UP, yaw), p - Vector3(0, 0.2, 0)))
	var water := kit.palette.nation == &"water_tribe"
	if water:
		kit.cylinder(Vector3.ZERO, 2.0, 2.0, &"wall", 12, true)
		KitRoofs.dome(kit, Vector3(0, 2.0, 0), 2.0, {"squash": 0.6, "role": &"wall_alt", "block_lines": true})
		kit.box(Vector3(0, 0.9, -1.95), Vector3(1.0, 1.8, 0.2), &"door", false)
	else:
		kit.box(Vector3(0, 1.3, 0), Vector3(4.0, 2.6, 3.2), &"wall", true)
		KitRoofs.gable(kit, Vector3(0, 2.6, 0), 4.0, 3.2, 1.4, {"overhang": 0.5})
		kit.door(Transform3D(Basis(), Vector3(0, 0, -1.62)), 1.4, 2.0)
	# rack with a kayak / nets
	kit.beam(Vector3(2.6, 1.0, -1.0), Vector3(2.6, 1.0, 1.0), 0.1, 0.1, &"wood")
	for s: float in [-1.0, 1.0]:
		kit.beam(Vector3(2.6, 0, s), Vector3(2.6, 1.1, s), 0.1, 0.1, &"wood")
	kit.push(Transform3D(Basis(Vector3.UP, 0.0), Vector3(2.6, 1.15, 0)))
	BoatBuilder.kayak(kit, {"length": 3.4})
	kit.pop()
	kit.pop()
