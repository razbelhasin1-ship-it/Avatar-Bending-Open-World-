class_name EkPalace
extends RefCounted
## Royal Earth Kingdom architecture (BuildingKit recipes, thread-safe; origin on the ground,
## -Z = front). Jade-green tiles, gold ridges and finials, lacquered colonnades, marble podiums.
##   palace_podium  terraced marble platform (spec w, d, h) with balustrades and a grand stair
##                  on the front, bronze cauldrons at its foot
##   throne_hall    the great hall (spec w, d): lacquered colonnade, gold-studded doors, three
##                  stacked roofs crowned with a gold finial, the Earth Kingdom seal
##   palace_hall    side / rear hall (spec w, d, v) with double eaves
##   palace_gate    gate pavilion with three openings and a two-tier roof (spec w, d)
##   pagoda         tiered tower (spec tiers, w) on a stone base

static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"palace_podium": podium(kit, spec)
		&"throne_hall": throne_hall(kit, spec)
		&"palace_hall": palace_hall(kit, spec)
		&"palace_gate": palace_gate(kit, spec)
		&"pagoda": pagoda(kit, spec)


static func _ro(v: int, extra: Dictionary = {}) -> Dictionary:
	var o := EkStyle.roof_opts(EkStyle.PALACE, v, {"alt_role": EkStyle.roof(EkStyle.PALACE, v + 1), "curve": 1.0, "ornaments": true})
	o.merge(extra, true)
	return o


## Marble balustrade along a polyline (local), with posts and a gold rail.
static func balustrade(kit: BuildingKit, pts: PackedVector3Array, h: float = 1.1) -> void:
	var marble := EkStyle.wall(EkStyle.UPPER, 2)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		kit.beam(a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.3, 0.16, marble, false)
		kit.beam(a + Vector3(0, 0.12, 0), b + Vector3(0, 0.12, 0), 0.3, 0.24, marble, false)
		var seg := a.distance_to(b)
		var n := maxi(int(seg / 2.0), 1)
		for k in n:
			var p := a.lerp(b, float(k) / n)
			kit.box(p + Vector3(0, h * 0.5, 0), Vector3(0.28, h, 0.28), marble, false)
			if kit.lod == 0:
				kit.ornament(p + Vector3(0, h + 0.1, 0), &"orb", 0.24, EkStyle.GOLD)
		var mid := (a + b) * 0.5 + Vector3(0, h * 0.5, 0)
		var dir := (b - a).normalized()
		var xz := Vector3(dir.x, 0, dir.z).normalized()
		if xz.length_squared() > 0.0:
			kit.boxes.append([kit.xform * Transform3D(Basis(xz.cross(Vector3.UP).normalized(), Vector3.UP, xz).orthonormalized(), mid), Vector3(0.3, h + 0.2, seg)])


static func podium(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 60.0))
	var d := float(spec.get("d", 46.0))
	var h := float(spec.get("h", 4.0))
	var marble := EkStyle.wall(EkStyle.UPPER, 2)
	var dark := EkStyle.base(EkStyle.UPPER)
	# two terraces: lower plinth + the platform
	kit.box(Vector3(0, h * 0.25, 0), Vector3(w + 6.0, h * 0.5, d + 6.0), dark)
	kit.box(Vector3(0, h * 0.75, 0), Vector3(w, h * 0.5, d), marble)
	if kit.lod < 2:
		kit.box(Vector3(0, h + 0.03, 0), Vector3(w - 0.4, 0.06, d - 0.4), EkStyle.PAVING, false)
		kit.box(Vector3(0, h * 0.5 + 0.06, 0), Vector3(w + 6.1, 0.12, d + 6.1), EkStyle.GOLD, false)
	# grand stair on the front (both terraces) with gold-railed cheeks
	var sw := 14.0
	var run := h * 2.4
	kit.stairs(Vector3(0, 0, -d * 0.5 - 3.0 - run), Vector3(0, h, -d * 0.5), sw, {"role": marble, "rise": 0.18, "sides": true, "side_role": dark})
	# side stairs on the lower terrace
	for sx: float in [-1.0, 1.0]:
		kit.stairs(Vector3(sx * (w * 0.5 + 3.0 + h * 1.2), 0, 0), Vector3(sx * (w * 0.5 + 3.0), h * 0.5, 0), 6.0, {"role": marble})
	if kit.lod >= 2:
		return
	# balustrades around the platform (gap at the stair)
	var hw := w * 0.5
	var hd := d * 0.5
	balustrade(kit, PackedVector3Array([Vector3(-sw * 0.5 - 0.4, h, -hd + 0.3), Vector3(-hw + 0.3, h, -hd + 0.3), Vector3(-hw + 0.3, h, hd - 0.3),
		Vector3(hw - 0.3, h, hd - 0.3), Vector3(hw - 0.3, h, -hd + 0.3), Vector3(sw * 0.5 + 0.4, h, -hd + 0.3)]))
	if kit.lod == 0:
		# the seal inlaid in the stair landing, bronze cauldrons + lanterns at the foot
		var ring := PackedVector3Array()
		var ws := PackedFloat32Array()
		for i in 33:
			var a := TAU * i / 32.0
			ring.append(Vector3(cos(a) * 4.0, h + 0.07, -hd + 6.0 + sin(a) * 4.0))
			ws.append(0.5)
		KitX.ribbon(kit, ring, ws, kit.col(EkStyle.GOLD, false))
		kit.box(Vector3(0, h + 0.08, -hd + 6.0), Vector3(3.2, 0.04, 3.2), EkStyle.COPING, false)
		for sx: float in [-1.0, 1.0]:
			var cp := Vector3(sx * (sw * 0.5 + 4.0), 0, -d * 0.5 - 3.0 - run + 1.5)
			kit.box(cp + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 2.4), dark, true)
			kit.g().cylinder(cp + Vector3(0, 0.8, 0), cp + Vector3(0, 2.2, 0), 0.8, 1.1, 10, kit.col(EkStyle.GOLD * 0.7), 1)
			kit.g().cylinder(cp + Vector3(0, 2.2, 0), cp + Vector3(0, 2.4, 0), 1.15, 1.15, 10, kit.col(EkStyle.GOLD), 2)
			kit.brazier(cp + Vector3(0, 2.1, 0), {"height": 0.1, "radius": 0.9, "range": 14.0, "energy": 2.4})
			for k in 3:
				KitX.lantern(kit, Vector3(sx * (hw - 4.0 - k * 12.0), h, -hd + 1.2), {"style": &"stone", "height": 2.0, "light": k == 0, "range": 11.0})


static func throne_hall(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 36.0))
	var d := float(spec.get("d", 20.0))
	var hw := w * 0.5
	var hd := d * 0.5
	var lac := EkStyle.LACQUER
	var wall_c := EkStyle.wall(EkStyle.PALACE, 0)
	var bh := 1.6
	var h := 9.0
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 6.0, bh, d + 6.0), EkStyle.wall(EkStyle.UPPER, 2))
	kit.stairs(Vector3(0, 0, -hd - 3.0 - 4.0), Vector3(0, bh, -hd - 3.0), 10.0, {"role": EkStyle.wall(EkStyle.UPPER, 2), "sides": true, "side_role": EkStyle.GOLD})
	kit.box(Vector3(0, bh + h * 0.5, 0.5), Vector3(w - 4.0, h, d - 4.0), wall_c)
	# colonnade all around
	var nc := 10
	for i in nc:
		var x := lerpf(-hw + 0.5, hw - 0.5, float(i) / (nc - 1))
		for sz: float in [-1.0, 1.0]:
			kit.column(Vector3(x, bh, sz * (hd - 0.5)), h, 0.55, lac, &"round", EkStyle.base(EkStyle.UPPER))
	for k in 3:
		var z := lerpf(-hd + 0.5, hd - 0.5, (k + 1) / 4.0)
		for sx: float in [-1.0, 1.0]:
			kit.column(Vector3(sx * (hw - 0.5), bh, z), h, 0.55, lac, &"round", EkStyle.base(EkStyle.UPPER))
	var y1 := bh + h
	kit.box(Vector3(0, y1 - 0.5, 0), Vector3(w + 0.4, 1.0, d + 0.4), EkStyle.COPING, false)
	if kit.lod < 2:
		kit.box(Vector3(0, y1 - 1.15, -hd + 0.5), Vector3(w, 0.3, 0.7), EkStyle.GOLD, false)
		# doors: gold-studded leaves between the front columns
		for k in 3:
			var dx := (k - 1) * 7.0
			kit.box(Vector3(dx, bh + 3.0, -hd + 2.0 - 0.05), Vector3(4.0, 6.0, 0.12), EkStyle.LACQUER * 0.8, false)
			if kit.lod == 0:
				for row in 4:
					for col in 3:
						kit.ornament(Vector3(dx - 1.2 + col * 1.2, bh + 1.2 + row * 1.4, -hd + 1.9), &"orb", 0.18, EkStyle.GOLD)
		KitX.emblem_earth(kit, Vector3(0, y1 + 3.0, -hd * 0.62 - 0.3), 3.2, EkStyle.GOLD, 0.2)
	# three stacked roofs
	var ro := _ro(0)
	if kit.lod < 2:
		KitRoofs.hip(kit, Vector3(0, y1, 0), w, d, 2.6, ro.merged({"overhang": 2.6, "ridge": 1.0, "ornaments": false}, true))
	else:
		RoofsLite.hip(kit, Vector3(0, y1, 0), w, d, 2.6, ro.merged({"overhang": 2.6}, true))
	var dw := w * 0.78
	var dd := d * 0.62
	kit.box(Vector3(0, y1 + 2.0 + 2.0, 0), Vector3(dw, 4.0, dd), wall_c)
	if kit.lod == 0:
		for i in 9:
			var x := lerpf(-dw * 0.5 + 1.0, dw * 0.5 - 1.0, i / 8.0)
			KitX.window(kit, Vector3(x, y1 + 4.2, -dd * 0.5 - 0.02), 1.4, 1.6, EkStyle.COPING, 0.04, i % 2 == 0)
	var y2 := y1 + 6.0
	if kit.lod < 2:
		KitRoofs.hip(kit, Vector3(0, y2, 0), dw, dd, 3.0, ro.merged({"overhang": 2.2, "ornaments": false}, true))
	else:
		RoofsLite.hip(kit, Vector3(0, y2, 0), dw, dd, 3.0, ro.merged({"overhang": 2.2}, true))
	var tw := dw * 0.6
	var td := dd * 0.62
	kit.box(Vector3(0, y2 + 2.2 + 1.5, 0), Vector3(tw, 3.0, td), wall_c)
	var y3 := y2 + 5.2
	if kit.lod < 2:
		KitRoofs.hip(kit, Vector3(0, y3, 0), tw, td, 5.4, ro.merged({"overhang": 2.0, "finial": true}, true))
		kit.ornament(Vector3(0, y3 + 5.5, 0), &"finial", 3.0, EkStyle.GOLD)
	else:
		RoofsLite.hip(kit, Vector3(0, y3, 0), tw, td, 5.4, ro.merged({"overhang": 2.0}, true))
		kit.g().cone(Vector3(0, y3 + 5.0, 0), Vector3(0, y3 + 8.0, 0), 0.5, 5, kit.col(EkStyle.GOLD))
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, y3 + 8.0, 0)))
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 6.0, y1 - 1.4, -hd - 0.2)), 2.4, 6.5, EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth")
			for k in 2:
				kit.lantern(Vector3(sx * (3.5 + k * 9.0), y1 - 2.2, -hd - 0.4), {"style": &"paper", "light": k == 0, "range": 12.0, "energy": 1.8})


static func palace_hall(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 20.0))
	var d := float(spec.get("d", 12.0))
	var v := int(spec.get("v", 0))
	var hw := w * 0.5
	var hd := d * 0.5
	var lac := EkStyle.LACQUER
	var bh := 1.0
	var h := 6.0
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 3.0, bh, d + 3.0), EkStyle.wall(EkStyle.UPPER, 2))
	kit.box(Vector3(0, bh + h * 0.5, 0.4), Vector3(w - 2.0, h, d - 2.4), EkStyle.wall(EkStyle.PALACE, v))
	for i in 6:
		var x := lerpf(-hw + 0.5, hw - 0.5, i / 5.0)
		kit.column(Vector3(x, bh, -hd + 0.4), h, 0.38, lac, &"round", EkStyle.base(EkStyle.UPPER))
	var ro := _ro(v)
	RoofsLite.hip(kit, Vector3(0, bh + h, 0), w, d, 1.6, ro.merged({"overhang": 1.6, "horns": false}, true))
	kit.box(Vector3(0, bh + h + 1.2 + 1.2, 0.2), Vector3(w * 0.72, 2.4, d * 0.6), EkStyle.wall(EkStyle.PALACE, v + 1))
	RoofsLite.hip(kit, Vector3(0, bh + h + 3.6, 0.2), w * 0.72, d * 0.6, 3.2, ro.merged({"overhang": 1.5}, true))
	if kit.lod >= 2:
		return
	kit.stairs(Vector3(0, 0, -hd - 1.5 - 2.2), Vector3(0, bh, -hd - 1.5), 5.0, {"role": EkStyle.wall(EkStyle.UPPER, 2)})
	kit.beam(Vector3(-hw, bh + h - 0.3, -hd + 0.4), Vector3(hw, bh + h - 0.3, -hd + 0.4), 0.45, 0.5, EkStyle.COPING)
	EkHomes.door(kit, Vector3(0, bh, -hd + 1.2 - 0.02), 2.4, 3.4, EkStyle.GOLD, EkStyle.LACQUER)
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			KitX.window(kit, Vector3(sx * (3.0 + k * 3.6), bh + 3.0, -hd + 1.2 - 0.02), 1.6, 1.8, EkStyle.COPING, 0.04, (k + v) % 2 == 0)
		if kit.lod == 0:
			kit.lantern(Vector3(sx * 2.2, bh + h - 1.0, -hd - 0.2), {"style": &"paper", "light": sx > 0.0, "range": 10.0})


static func palace_gate(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 26.0))
	var d := float(spec.get("d", 10.0))
	var hw := w * 0.5
	var hd := d * 0.5
	var h := 8.0
	var wall_c := EkStyle.wall(EkStyle.PALACE, 1)
	# solid piers between three openings
	var openings := [[-hw * 0.6, 3.6], [0.0, 5.2], [hw * 0.6, 3.6]]
	var edges := [-hw]
	for o: Array in openings:
		edges.append(float(o[0]) - float(o[1]) * 0.5)
		edges.append(float(o[0]) + float(o[1]) * 0.5)
	edges.append(hw)
	for i in range(0, edges.size(), 2):
		var a := float(edges[i])
		var b := float(edges[i + 1])
		kit.box(Vector3((a + b) * 0.5, h * 0.5, 0), Vector3(b - a, h, d), wall_c)
	for o: Array in openings:
		var ow := float(o[1])
		var oh := 5.0 if ow > 4.0 else 4.0
		kit.box(Vector3(float(o[0]), (oh + h) * 0.5, 0), Vector3(ow, h - oh, d), wall_c)
		if kit.lod < 2:
			kit.box(Vector3(float(o[0]), oh + 0.3, -hd - 0.1), Vector3(ow + 0.8, 0.6, 0.4), EkStyle.GOLD, false)
			for sx: float in [-1.0, 1.0]:
				kit.box_t(Transform3D(Basis(Vector3.UP, sx * 1.35), Vector3(float(o[0]) + sx * ow * 0.42, oh * 0.5, hd - 0.2)), Vector3(ow * 0.48, oh, 0.12), EkStyle.LACQUER, false)
	kit.box(Vector3(0, 0.25, 0), Vector3(w + 1.0, 0.5, d + 1.0), EkStyle.wall(EkStyle.UPPER, 2), false)
	kit.box(Vector3(0, h + 0.4, 0), Vector3(w + 0.6, 0.8, d + 0.6), EkStyle.COPING)
	var ro := _ro(0)
	RoofsLite.hip(kit, Vector3(0, h + 0.8, 0), w, d, 1.8, ro.merged({"overhang": 1.8, "horns": false}, true))
	kit.box(Vector3(0, h + 2.4 + 1.6, 0), Vector3(w * 0.6, 3.2, d * 0.6), wall_c)
	RoofsLite.hip(kit, Vector3(0, h + 5.6, 0), w * 0.6, d * 0.6, 3.4, ro.merged({"overhang": 1.6}, true))
	if kit.lod < 2:
		kit.ornament(Vector3(0, h + 9.1, 0), &"finial", 1.6, EkStyle.GOLD)
		KitX.emblem_earth(kit, Vector3(0, h + 4.0, -d * 0.3 - 0.1), 2.0, EkStyle.GOLD, 0.1)
		for sx: float in [-1.0, 1.0]:
			kit.lantern(Vector3(sx * hw * 0.3, h - 0.6, -hd - 0.5), {"style": &"paper", "light": true, "range": 11.0})
			EkHomes._lion(kit, Vector3(sx * (hw * 0.3), 0.0, -hd - 3.0))


static func pagoda(kit: BuildingKit, spec: Dictionary) -> void:
	var tiers := int(spec.get("tiers", 5))
	var w := float(spec.get("w", 10.0))
	kit.box(Vector3(0, 0.8, 0), Vector3(w + 4.0, 1.6, w + 4.0), EkStyle.wall(EkStyle.UPPER, 2))
	kit.box(Vector3(0, 1.6 + 2.0, 0), Vector3(w, 4.0, w), EkStyle.wall(EkStyle.PALACE, 0))
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				kit.column(Vector3(sx * (w * 0.5 + 0.6), 1.6, sz * (w * 0.5 + 0.6)), 4.0, 0.3, EkStyle.LACQUER, &"round", EkStyle.base(EkStyle.UPPER))
		EkHomes.door(kit, Vector3(0, 1.6, -w * 0.5 - 0.02), 1.8, 2.8, EkStyle.GOLD, EkStyle.LACQUER)
	var ro := _ro(1)
	var y := 5.6
	var cw := w
	for t in tiers:
		var last := t == tiers - 1
		var rh := 2.4 if not last else 4.2
		RoofsLite.hip(kit, Vector3(0, y, 0), cw, cw, rh, ro.merged({"overhang": 1.6 - t * 0.12, "ridge": 0.4 if last else 1.0}, true))
		if last:
			y += rh
			break
		var nw := cw * 0.84
		kit.box(Vector3(0, y + 1.0 + 1.1, 0), Vector3(nw, 2.2, nw), EkStyle.wall(EkStyle.PALACE, t % 2))
		if kit.lod == 0:
			for k in 2:
				KitX.window(kit, Vector3((k - 0.5) * nw * 0.4, y + 2.2, -nw * 0.5 - 0.02), 0.8, 1.0, EkStyle.COPING, 0.04, (t + k) % 2 == 0)
		y += 3.2
		cw = nw
	if kit.lod < 2:
		kit.g().cylinder(Vector3(0, y - 0.2, 0), Vector3(0, y + 4.0, 0), 0.22, 0.12, 8, kit.col(EkStyle.GOLD), 2)
		for k in 4:
			kit.g().cylinder(Vector3(0, y + 0.6 + k * 0.8, 0), Vector3(0, y + 0.8 + k * 0.8, 0), 0.5 - k * 0.08, 0.5 - k * 0.08, 8, kit.col(EkStyle.GOLD), 3)
	else:
		kit.g().cone(Vector3(0, y - 0.2, 0), Vector3(0, y + 4.0, 0), 0.4, 5, kit.col(EkStyle.GOLD))
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, y + 4.0, 0)))


## Highest point of a pagoda above its base (planner clearance).
static func pagoda_height(tiers: int) -> float:
	return 5.6 + (tiers - 1) * 3.2 + 4.2 + 4.0
