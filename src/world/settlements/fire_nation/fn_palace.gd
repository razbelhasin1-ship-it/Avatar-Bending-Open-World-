class_name FnPalace
extends RefCounted
## The Fire Lord's palace (BuildingKit recipes, thread-safe; origin on the ground, -Z = front):
##   fn_podium      stacked basalt terraces (spec w, d, levels, lh) with red bands, gold trims, red
##                  balustrades and a grand stair through every level on the front
##   fn_throne_hall the throne hall (spec w, d): red walls between black pilasters, a deep porch of
##                  red columns, gold doors, three steep black roofs with gold ridges and flame
##                  finials, the flame emblem on the front, two flanking spire towers
##   fn_hall        side hall (spec w, d, v) with a double black roof
##   fn_palace_gate gate pavilion with three openings and a double black roof (spec w, d)
##   flame_pillar   a tall basalt column carrying a great fire bowl (the courtyard lights)

static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"fn_podium": podium(kit, spec)
		&"fn_throne_hall": throne_hall(kit, spec)
		&"fn_hall": hall(kit, spec)
		&"fn_palace_gate": palace_gate(kit, spec)
		&"flame_pillar": flame_pillar(kit, spec)


static func _ro(v: int, extra: Dictionary = {}) -> Dictionary:
	var o := FnStyle.roof_opts(FnStyle.PALACE, v, {"curve": 1.2, "concave": 0.55, "ornaments": false})
	o.merge(extra, true)
	return o


static func balustrade(kit: BuildingKit, pts: PackedVector3Array) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		kit.beam(a + Vector3(0, 0.95, 0), b + Vector3(0, 0.95, 0), 0.26, 0.14, FnStyle.RED, false)
		kit.beam(a + Vector3(0, 0.1, 0), b + Vector3(0, 0.1, 0), 0.3, 0.2, FnStyle.BASALT_DARK, false)
		var n := maxi(int(a.distance_to(b) / 1.8), 1)
		for k in n:
			var p := a.lerp(b, float(k) / n)
			kit.box(p + Vector3(0, 0.5, 0), Vector3(0.24, 1.0, 0.24), FnStyle.RED_DARK, false)
			if kit.lod == 0 and k % 2 == 0:
				kit.ornament(p + Vector3(0, 1.1, 0), &"orb", 0.2, FnStyle.GOLD)
		var dir := (b - a).normalized()
		var xz := Vector3(dir.x, 0, dir.z).normalized()
		if xz.length_squared() > 0.0:
			kit.boxes.append([kit.xform * Transform3D(Basis(xz.cross(Vector3.UP).normalized(), Vector3.UP, xz).orthonormalized(),
				(a + b) * 0.5 + Vector3(0, 0.6, 0)), Vector3(0.3, 1.2, a.distance_to(b))])


static func podium(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 70.0))
	var d := float(spec.get("d", 56.0))
	var levels := int(spec.get("levels", 3))
	var lh := float(spec.get("lh", 2.6))
	var inset := float(spec.get("inset", 8.0))
	var bottom := float(spec.get("bottom", 0.0))
	var sw := 14.0
	for k in levels:
		var ww := w - k * inset
		var dd := d - k * inset
		var zc := k * 2.0
		var y := k * lh
		var y0 := bottom if k == 0 else y
		kit.box(Vector3(0, (y0 + y + lh) * 0.5, zc), Vector3(ww, y + lh - y0, dd), FnStyle.BASALT if k % 2 == 0 else FnStyle.BASALT_2)
		if kit.lod < 2:
			kit.box(Vector3(0, y + lh - 0.5, zc), Vector3(ww + 0.12, 0.6, dd + 0.12), FnStyle.RED, false)
			kit.box(Vector3(0, y + lh - 0.15, zc), Vector3(ww + 0.18, 0.1, dd + 0.18), FnStyle.GOLD, false)
			var hw := ww * 0.5
			var hd := dd * 0.5
			var top := y + lh
			balustrade(kit, PackedVector3Array([Vector3(-sw * 0.5 - 0.5, top, zc - hd + 0.3), Vector3(-hw + 0.3, top, zc - hd + 0.3),
				Vector3(-hw + 0.3, top, zc + hd - 0.3), Vector3(hw - 0.3, top, zc + hd - 0.3), Vector3(hw - 0.3, top, zc - hd + 0.3),
				Vector3(sw * 0.5 + 0.5, top, zc - hd + 0.3)]))
		# the stair through this level
		var z_front := zc - dd * 0.5
		var run := lh * 2.2
		kit.stairs(Vector3(0, y, z_front - run), Vector3(0, y + lh, z_front), sw - k * 1.0, {"role": FnStyle.PAVING, "rise": 0.18, "sides": true,
			"side_role": FnStyle.RED_DARK})
		if k < levels - 1:
			# landing in front of the next level
			kit.box(Vector3(0, y + lh - 0.1, z_front + 2.0), Vector3(sw + 2.0, 0.2, 4.0), FnStyle.PAVING, false)
	if kit.lod < 2:
		# flame pillars at the foot of the grand stair
		for sx: float in [-1.0, 1.0]:
			kit.push(Transform3D(Basis(), Vector3(sx * (sw * 0.5 + 3.0), 0, -d * 0.5 - lh * 2.2 - 1.5)))
			flame_pillar(kit, {"h": 5.0})
			kit.pop()


static func throne_hall(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 40.0))
	var d := float(spec.get("d", 24.0))
	# the spire towers reach this far below the hall floor (they rise out of the podium)
	var plinth := float(spec.get("plinth", -1.2))
	var hw := w * 0.5
	var hd := d * 0.5
	var h := 11.0
	var red := FnStyle.wall(FnStyle.PALACE, 0)
	kit.box(Vector3(0, 0.6, 0), Vector3(w + 4.0, 1.2, d + 4.0), FnStyle.BASALT_DARK)
	kit.box(Vector3(0, 1.2 + h * 0.5, 1.5), Vector3(w - 4.0, h, d - 3.0), red)
	# porch columns + black pilasters
	var nc := 10
	for i in nc:
		var x := lerpf(-hw + 1.0, hw - 1.0, float(i) / (nc - 1))
		kit.column(Vector3(x, 1.2, -hd + 1.2), h, 0.6, FnStyle.RED, &"round", FnStyle.BASALT_DARK)
	var y1 := 1.2 + h
	kit.box(Vector3(0, y1 - 0.6, -hd + 1.2), Vector3(w, 1.2, 1.6), FnStyle.BLACK, false)
	if kit.lod < 2:
		kit.box(Vector3(0, y1 - 1.3, -hd + 0.4), Vector3(w, 0.2, 0.2), FnStyle.GOLD, false)
		for i in 7:
			var x := lerpf(-hw + 3.0, hw - 3.0, i / 6.0)
			kit.box(Vector3(x, 1.2 + h * 0.5, -hd + 2.95), Vector3(0.8, h, 0.2), FnStyle.BLACK, false)
		for k in 3:
			var dx := (k - 1) * 8.0
			kit.box(Vector3(dx, 1.2 + 3.6, -hd + 2.9), Vector3(4.4, 7.2, 0.14), FnStyle.GOLD * 0.75, false)
			if kit.lod == 0:
				kit.box(Vector3(dx, 1.2 + 3.6, -hd + 2.8), Vector3(0.1, 7.2, 0.06), FnStyle.BLACK, false)
				KitX.emblem_fire(kit, Vector3(dx, 1.2 + 5.6, -hd + 2.75), 1.4, FnStyle.RED, 0.05)
		kit.stairs(Vector3(0, 0, -hd - 2.0 - 3.0), Vector3(0, 1.2, -hd - 2.0), 12.0, {"role": FnStyle.PAVING, "sides": true, "side_role": FnStyle.RED_DARK})
	# three stacked roofs
	var ro := _ro(0)
	var use_full := kit.lod < 2
	if use_full:
		KitRoofs.hip(kit, Vector3(0, y1, 0), w, d, 3.0, ro.merged({"overhang": 3.0, "ridge": 1.0}, true))
	else:
		RoofsLite.hip(kit, Vector3(0, y1, 0), w, d, 3.0, ro.merged({"overhang": 3.0}, true))
	var dw := w * 0.76
	var dd := d * 0.64
	kit.box(Vector3(0, y1 + 2.6 + 2.2, 0), Vector3(dw, 4.4, dd), red)
	if kit.lod == 0:
		for i in 9:
			KitX.window(kit, Vector3(lerpf(-dw * 0.5 + 1.2, dw * 0.5 - 1.2, i / 8.0), y1 + 5.0, -dd * 0.5 - 0.02), 1.2, 1.8, FnStyle.GOLD, 0.04, i % 2 == 0)
	var y2 := y1 + 7.0
	if use_full:
		KitRoofs.hip(kit, Vector3(0, y2, 0), dw, dd, 3.2, ro.merged({"overhang": 2.4}, true))
	else:
		RoofsLite.hip(kit, Vector3(0, y2, 0), dw, dd, 3.2, ro.merged({"overhang": 2.4}, true))
	var tw := dw * 0.58
	var td := dd * 0.62
	kit.box(Vector3(0, y2 + 2.6 + 1.6, 0), Vector3(tw, 3.2, td), red)
	var y3 := y2 + 5.8
	if use_full:
		KitRoofs.hip(kit, Vector3(0, y3, 0), tw, td, 6.0, ro.merged({"overhang": 2.2, "ridge": 0.8}, true))
	else:
		RoofsLite.hip(kit, Vector3(0, y3, 0), tw, td, 6.0, ro.merged({"overhang": 2.2}, true))
	var ridge_half := maxf((tw + 4.4 - (td + 4.4)) * 0.5 * 0.8, 0.0)
	FnStyle.flame_finial(kit, Vector3(0, y3 + 6.1, 0), 3.2)
	for sx: float in [-1.0, 1.0]:
		FnStyle.flame_finial(kit, Vector3(sx * (ridge_half + 0.2), y3 + 6.0, 0), 1.8)
	if kit.lod < 2:
		KitX.emblem_fire(kit, Vector3(0, y1 + 4.6, -dd * 0.5 - 0.3), 3.0, FnStyle.GOLD, 0.2)
		for sx: float in [-1.0, 1.0]:
			KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 7.0, y1 - 1.6, -hd + 0.25)), 2.6, 8.0, FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire", 3)
			for k in 2:
				kit.lantern(Vector3(sx * (4.0 + k * 10.0), y1 - 2.6, -hd + 0.5), {"style": &"paper", "light": k == 0, "range": 12.0, "energy": 1.8,
					"color": Color(1.0, 0.45, 0.2)})
	# flanking spire towers
	for sx: float in [-1.0, 1.0]:
		var tx: float = sx * (hw + 3.0)
		var tz := hd - 4.0
		kit.box(Vector3(tx, (19.2 - plinth) * 0.5, tz), Vector3(6.0, 19.2 + plinth, 6.0), FnStyle.wall(FnStyle.PALACE, 1))
		if kit.lod < 2:
			kit.box(Vector3(tx, 1.2 + 17.0, tz), Vector3(6.3, 0.6, 6.3), FnStyle.GOLD, false)
			KitX.window(kit, Vector3(tx, 1.2 + 14.0, tz - 3.02), 1.2, 1.8, FnStyle.GOLD, 0.04, true)
		var py := 1.2 + 18.0
		RoofsLite.hip(kit, Vector3(tx, py, tz), 6.0, 6.0, 2.4, _ro(1, {"overhang": 1.6}))
		kit.box(Vector3(tx, py + 2.2 + 1.4, tz), Vector3(4.0, 2.8, 4.0), FnStyle.RED)
		RoofsLite.hip(kit, Vector3(tx, py + 5.0, tz), 4.0, 4.0, 4.6, _ro(1, {"overhang": 1.4, "ridge": 0.2}))
		FnStyle.flame_finial(kit, Vector3(tx, py + 9.5, tz), 2.0)
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, y3 + 9.3, 0)))


static func hall(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 20.0))
	var d := float(spec.get("d", 12.0))
	var v := int(spec.get("v", 0))
	var hw := w * 0.5
	var hd := d * 0.5
	var h := 6.0
	kit.box(Vector3(0, 0.5, 0), Vector3(w + 3.0, 1.0, d + 3.0), FnStyle.BASALT_DARK)
	kit.box(Vector3(0, 1.0 + h * 0.5, 0.5), Vector3(w - 2.0, h, d - 2.2), FnStyle.wall(FnStyle.PALACE, v))
	for i in 6:
		kit.column(Vector3(lerpf(-hw + 0.5, hw - 0.5, i / 5.0), 1.0, -hd + 0.5), h, 0.36, FnStyle.RED, &"round", FnStyle.BASALT_DARK)
	var ro := _ro(v)
	RoofsLite.hip(kit, Vector3(0, 1.0 + h, 0), w, d, 1.6, ro.merged({"overhang": 1.6, "horns": false}, true))
	kit.box(Vector3(0, 1.0 + h + 1.2 + 1.2, 0.2), Vector3(w * 0.7, 2.4, d * 0.6), FnStyle.wall(FnStyle.PALACE, v + 1))
	RoofsLite.hip(kit, Vector3(0, 1.0 + h + 3.6, 0.2), w * 0.7, d * 0.6, 3.4, ro.merged({"overhang": 1.5, "curve": 1.3}, true))
	FnStyle.flame_finial(kit, Vector3(0, 1.0 + h + 7.1, 0.2), 1.2)
	if kit.lod >= 2:
		return
	kit.stairs(Vector3(0, 0, -hd - 1.5 - 2.0), Vector3(0, 1.0, -hd - 1.5), 5.0, {"role": FnStyle.PAVING})
	kit.beam(Vector3(-hw, 1.0 + h - 0.3, -hd + 0.5), Vector3(hw, 1.0 + h - 0.3, -hd + 0.5), 0.45, 0.5, FnStyle.BLACK)
	EkHomes.door(kit, Vector3(0, 1.0, -hd + 1.1 - 0.02), 2.4, 3.6, FnStyle.GOLD, FnStyle.RED_DARK)
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			KitX.window(kit, Vector3(sx * (3.2 + k * 3.6), 1.0 + 3.2, -hd + 1.1 - 0.02), 1.5, 1.8, FnStyle.GOLD, 0.04, (k + v) % 2 == 0)
		if kit.lod == 0:
			kit.lantern(Vector3(sx * 2.4, 1.0 + h - 1.0, -hd - 0.2), {"style": &"paper", "light": sx > 0.0, "range": 10.0, "color": Color(1.0, 0.45, 0.2)})


static func palace_gate(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 30.0))
	var d := float(spec.get("d", 10.0))
	var hw := w * 0.5
	var hd := d * 0.5
	var h := 9.0
	var red := FnStyle.wall(FnStyle.PALACE, 1)
	var openings := [[-hw * 0.6, 4.0], [0.0, 6.0], [hw * 0.6, 4.0]]
	var edges := [-hw]
	for o: Array in openings:
		edges.append(float(o[0]) - float(o[1]) * 0.5)
		edges.append(float(o[0]) + float(o[1]) * 0.5)
	edges.append(hw)
	for i in range(0, edges.size(), 2):
		var a := float(edges[i])
		var b := float(edges[i + 1])
		kit.box(Vector3((a + b) * 0.5, h * 0.5, 0), Vector3(b - a, h, d), red)
	for o: Array in openings:
		var ow := float(o[1])
		var oh := 6.0 if ow > 5.0 else 4.6
		kit.box(Vector3(float(o[0]), (oh + h) * 0.5, 0), Vector3(ow, h - oh, d), red)
		if kit.lod < 2:
			kit.box(Vector3(float(o[0]), oh + 0.3, -hd - 0.1), Vector3(ow + 0.8, 0.6, 0.4), FnStyle.GOLD, false)
			for sx: float in [-1.0, 1.0]:
				kit.box_t(Transform3D(Basis(Vector3.UP, sx * 1.35), Vector3(float(o[0]) + sx * ow * 0.42, oh * 0.5, hd - 0.2)), Vector3(ow * 0.48, oh, 0.12),
						FnStyle.RED_DARK, false)
	kit.box(Vector3(0, 0.3, 0), Vector3(w + 1.0, 0.6, d + 1.0), FnStyle.BASALT_DARK, false)
	kit.box(Vector3(0, h + 0.4, 0), Vector3(w + 0.6, 0.8, d + 0.6), FnStyle.BLACK)
	var ro := _ro(0)
	RoofsLite.hip(kit, Vector3(0, h + 0.8, 0), w, d, 2.0, ro.merged({"overhang": 2.0, "horns": false}, true))
	kit.box(Vector3(0, h + 2.6 + 1.7, 0), Vector3(w * 0.6, 3.4, d * 0.6), red)
	RoofsLite.hip(kit, Vector3(0, h + 6.0, 0), w * 0.6, d * 0.6, 3.8, ro.merged({"overhang": 1.8, "curve": 1.3}, true))
	FnStyle.flame_finial(kit, Vector3(0, h + 9.9, 0), 2.0)
	if kit.lod < 2:
		KitX.emblem_fire(kit, Vector3(0, h + 4.4, -d * 0.3 - 0.1), 2.2, FnStyle.GOLD, 0.1)
		for sx: float in [-1.0, 1.0]:
			kit.lantern(Vector3(sx * hw * 0.3, h - 0.6, -hd - 0.5), {"style": &"paper", "light": true, "range": 11.0, "color": Color(1.0, 0.45, 0.2)})
			kit.push(Transform3D(Basis(), Vector3(sx * (hw * 0.3), 0.0, -hd - 3.4)))
			FnCivic.statue(kit, 0)
			kit.pop()


static func flame_pillar(kit: BuildingKit, spec: Dictionary) -> void:
	var h := float(spec.get("h", 6.0))
	kit.box(Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 2.4), FnStyle.BASALT_DARK, true)
	kit.cylinder(Vector3(0, 0.8, 0), h, 0.7, FnStyle.BASALT, 8, true, 0.55)
	if kit.lod < 2:
		for k in 3:
			kit.g().cylinder(Vector3(0, 0.8 + h * (k + 1) / 4.0, 0), Vector3(0, 1.0 + h * (k + 1) / 4.0, 0), 0.68 - k * 0.04, 0.68 - k * 0.04, 8,
					kit.col(FnStyle.RED if k != 1 else FnStyle.GOLD), 0)
	kit.push(Transform3D(Basis(), Vector3(0, 0.8 + h - 1.6, 0)))
	FnWalls.brazier(kit, 1)
	kit.pop()
