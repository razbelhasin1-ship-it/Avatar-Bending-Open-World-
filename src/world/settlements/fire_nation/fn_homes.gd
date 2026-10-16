class_name FnHomes
extends RefCounted
## Fire Nation dwellings (BuildingKit recipes, thread-safe; origin = ground centre, -Z = front).
## Archetypes by kind + variant + district style (FnStyle):
##   fn_house      lower-city house: cream plaster between red-lacquered posts on a dark stone
##                 base, charcoal tiles with upturned corners, red doors, lattice windows, shop
##                 fronts with red awnings, roof-top braziers on some
##   fn_townhouse  two / three storeys, red walls, a balcony with a red railing, black roofs
##   noble_house   noble compound: red wall with black tile coping, a gate with red pillars and a
##                 gold flame, the main hall on a basalt podium (black double roof, gold ridges),
##                 a side hall, a turtle-duck pond with a red bridge, stone lanterns
##   fn_villa      resort villa: white walls, red pillars and veranda, orange-red roof
##   fisher_hut    weathered timber hut on a low stone base, nets drying
##   tea_house_fn  tea farmer's house with a deep porch

static func footprint(kind: StringName, v: int) -> Vector2:
	match kind:
		&"fn_house": return Vector2([7.0, 8.0, 9.0, 10.0][v % 4], [9.0, 10.0, 11.0][v % 3])
		&"fn_townhouse": return Vector2([9.0, 10.0, 12.0][v % 3], [11.0, 12.0][v % 2])
		&"noble_house": return Vector2([26.0, 28.0, 30.0][v % 3], [24.0, 26.0][v % 2])
		&"fn_villa": return Vector2([14.0, 16.0][v % 2], [12.0, 13.0][v % 2])
		&"fisher_hut": return Vector2(6.0, 6.5)
		&"tea_house_fn": return Vector2(11.0, 9.0)
	return Vector2(8.0, 8.0)


static func height(kind: StringName, v: int) -> float:
	match kind:
		&"fn_house": return 7.0 if v % 3 != 1 else 10.0
		&"fn_townhouse": return 12.5
		&"noble_house": return 13.0
		&"fn_villa": return 8.0
		&"fisher_hut": return 4.5
		&"tea_house_fn": return 6.5
	return 8.0


static func build(kit: BuildingKit, kind: StringName, v: int, style: int) -> void:
	match kind:
		&"fn_house": house(kit, v, style)
		&"fn_townhouse": townhouse(kit, v, style)
		&"noble_house": noble_house(kit, v, style)
		&"fn_villa": villa(kit, v)
		&"fisher_hut": fisher_hut(kit, v)
		&"tea_house_fn": tea_house(kit, v)


## Posts at the corners and between bays of a front face (red lacquer), facing -Z at z.
static func posts(kit: BuildingKit, x0: float, x1: float, y0: float, h: float, z: float, bays: int, col: Color) -> void:
	if kit.lod >= 2:
		return
	for i in bays + 1:
		var x := lerpf(x0, x1, float(i) / bays)
		kit.box(Vector3(x, y0 + h * 0.5, z - 0.08), Vector3(0.26, h, 0.18), col, false)
	kit.box(Vector3((x0 + x1) * 0.5, y0 + h - 0.12, z - 0.08), Vector3(x1 - x0 + 0.2, 0.24, 0.18), col, false)


static func house(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"fn_house", v)
	var w := fp.x
	var d := fp.y
	var floors := 2 if v % 3 == 1 else 1
	var fh := 3.0
	var bh := 0.5
	var hh := floors * fh
	var wall_c := FnStyle.wall(style, v)
	var pil := FnStyle.pillar(style)
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 0.3, bh, d + 0.3), FnStyle.base(style))
	kit.box(Vector3(0, bh + hh * 0.5, 0), Vector3(w, hh, d), wall_c)
	var ro := FnStyle.roof_opts(style, v)
	if v % 2 == 0:
		RoofsLite.hip(kit, Vector3(0, bh + hh, 0), w, d, minf(d * 0.3, 3.0), ro.merged({"overhang": 0.8}, true))
	else:
		RoofsLite.gable(kit, Vector3(0, bh + hh, 0), w, d, minf(d * 0.32, 3.2), ro.merged({"overhang": 0.7, "gable_role": wall_c}, true))
	if kit.lod >= 2:
		return
	var zf := -d * 0.5
	posts(kit, -w * 0.5, w * 0.5, bh, hh, zf, 2 if w > 8.0 else 1, pil)
	if v % 4 == 0 and style == FnStyle.LOWER:
		kit.box(Vector3(0, bh + 1.2, zf - 0.02), Vector3(w - 1.0, 2.4, 0.06), &"window", false)
		kit.box(Vector3(0, bh + 0.45, zf - 0.45), Vector3(w - 1.2, 0.9, 0.7), FnStyle.RED_DARK, true)
		EkHomes.goods(kit, Vector3(0, bh + 0.9, zf - 0.45), w - 1.6, v)
		EkHomes.awning(kit, Vector3(0, bh + 2.9, zf - 0.1), w - 0.4, 1.5, 0.5, FnStyle.AWNINGS[v % 5])
	else:
		EkHomes.door(kit, Vector3(-w * 0.2 if w > 8.0 else 0.0, bh, zf), 1.2, 2.2, pil, FnStyle.RED)
		if w > 8.0:
			EkHomes.window(kit, Vector3(w * 0.25, bh + 1.6, zf), 1.1, 0.9, pil, v % 3 == 0)
	if floors > 1:
		for k in 2:
			EkHomes.window(kit, Vector3((k - 0.5) * w * 0.42, bh + fh + 1.4, zf), 0.9, 0.9, pil, (v + k) % 3 == 1)
	if kit.lod == 0:
		if v % 5 == 2:
			KitX.lantern(kit, Vector3(w * 0.4, bh + 2.5, zf - 0.5), {"style": &"paper", "light": false, "color": Color(1.0, 0.45, 0.2)})
		# side posts (seen from the lanes)
		for sx: float in [-1.0, 1.0]:
			kit.box(Vector3(sx * (w * 0.5 + 0.04), bh + hh * 0.5, d * 0.5 - 0.1), Vector3(0.1, hh, 0.22), pil, false)
			kit.box(Vector3(sx * (w * 0.5 + 0.04), bh + hh - 0.15, 0), Vector3(0.1, 0.22, d), pil, false)
		kit.box(Vector3(w * 0.5 + 0.03, bh + 1.8, d * 0.15), Vector3(0.06, 0.7, 0.8), &"window", false)


static func townhouse(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"fn_townhouse", v)
	var w := fp.x
	var d := fp.y
	var fh := 3.3
	var floors := 2 + v % 2
	var bh := 0.6
	var wall_c := FnStyle.wall(style, v)
	var pil := FnStyle.pillar(style)
	var ro := FnStyle.roof_opts(style, v)
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 0.4, bh, d + 0.4), FnStyle.base(style))
	kit.box(Vector3(0, bh + fh * floors * 0.5, 0.3), Vector3(w, fh * floors, d - 0.6), wall_c)
	for f in range(1, floors):
		RoofsLite.pent(kit, Vector3(0, bh + fh * f + 0.3, -d * 0.5 + 0.6 + 0.1), w + 0.5, 1.1, 0.45, ro)
	RoofsLite.hip(kit, Vector3(0, bh + fh * floors, 0.3), w, d - 0.6, 3.0, ro.merged({"overhang": 1.0, "curve": 0.8}, true))
	if kit.lod >= 2:
		return
	var zf := -d * 0.5 + 0.6
	posts(kit, -w * 0.5, w * 0.5, bh, fh * floors, zf, 3, pil)
	EkHomes.door(kit, Vector3(0, bh, zf), 1.5, 2.5, FnStyle.GOLD if style == FnStyle.NOBLE else pil, FnStyle.RED)
	for sx: float in [-1.0, 1.0]:
		EkHomes.window(kit, Vector3(sx * w * 0.3, bh + 1.7, zf), 1.2, 1.1, pil, v % 3 == 0 and sx > 0.0)
	for f in range(1, floors):
		var y := bh + fh * f
		for k in 3:
			EkHomes.window(kit, Vector3((k - 1) * w * 0.3, y + 1.5, zf), 1.0, 1.1, pil, (v + k + f) % 3 == 0)
		if kit.lod == 0 and f == 1:
			kit.box(Vector3(0, y + 0.05, zf - 0.5), Vector3(w - 0.8, 0.12, 1.0), pil, false)
			kit.railing(PackedVector3Array([Vector3(-w * 0.5 + 0.4, y + 0.1, zf - 0.95), Vector3(w * 0.5 - 0.4, y + 0.1, zf - 0.95)]), 0.85,
					{"role": FnStyle.RED, "spacing": 0.45, "collide": false})
	if kit.lod == 0 and v % 2 == 1:
		KitX.banner(kit, Transform3D(Basis(), Vector3(w * 0.5 - 0.6, bh + fh * floors - 0.4, zf - 0.25)), 0.8, 2.6, FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire")


static func noble_house(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"noble_house", v)
	var w := fp.x
	var d := fp.y
	var hw := w * 0.5
	var hd := d * 0.5
	var red := FnStyle.wall(FnStyle.NOBLE, v)
	var pil := FnStyle.pillar(FnStyle.NOBLE)
	var ro := FnStyle.roof_opts(FnStyle.NOBLE, v)
	var wh := 3.0
	kit.box(Vector3(0, 0.08, 0), Vector3(w - 0.8, 0.16, d - 0.8), FnStyle.PAVING, true)
	var gw := 4.4
	var segs := [[Vector3(-hw, 0, -hd), Vector3(-gw * 0.5 - 0.8, 0, -hd)], [Vector3(gw * 0.5 + 0.8, 0, -hd), Vector3(hw, 0, -hd)],
		[Vector3(hw, 0, -hd), Vector3(hw, 0, hd)], [Vector3(hw, 0, hd), Vector3(-hw, 0, hd)], [Vector3(-hw, 0, hd), Vector3(-hw, 0, -hd)]]
	for sg: Array in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		kit.wall(a, b, wh, 0.55, {"role": red, "cap": false, "base_role": FnStyle.BASALT_DARK})
		if kit.lod < 2:
			var dir := (b - a).normalized()
			kit.push(Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), (a + b) * 0.5 + Vector3(0, wh, 0)))
			RoofsLite.gable(kit, Vector3.ZERO, a.distance_to(b) + 0.4, 0.6, 0.5, ro.merged({"overhang": 0.3, "horns": false, "collide": false}, true))
			kit.pop()
	# gate
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (gw * 0.5 + 0.4), 2.1, -hd), Vector3(0.8, 4.2, 1.3), FnStyle.BASALT)
		kit.column(Vector3(sx * gw * 0.4, 0.0, -hd - 0.9), 3.8, 0.24, pil, &"round", FnStyle.BASALT_DARK)
	kit.box(Vector3(0, 4.0, -hd - 0.3), Vector3(gw + 2.2, 0.5, 2.2), FnStyle.RED_DARK, false)
	RoofsLite.hip(kit, Vector3(0, 4.25, -hd - 0.3), gw + 2.0, 2.2, 1.6, ro.merged({"overhang": 0.9, "curve": 0.9}, true))
	if kit.lod < 2:
		FnStyle.flame_finial(kit, Vector3(0, 5.9, -hd - 0.3), 0.8)
		for sx: float in [-1.0, 1.0]:
			kit.box_t(Transform3D(Basis(Vector3.UP, sx * 1.3), Vector3(sx * gw * 0.4, 1.6, -hd + 0.7)), Vector3(gw * 0.48, 3.2, 0.1), FnStyle.RED_DARK, false)
	# main hall on a basalt podium
	var mw := w - 7.0
	var md := 9.0
	var mz := hd - md * 0.5 - 2.0
	var ph := 1.0
	var mh := 4.2
	kit.box(Vector3(0, ph * 0.5, mz), Vector3(mw + 2.4, ph, md + 2.4), FnStyle.BASALT)
	kit.box(Vector3(0, ph + mh * 0.5, mz + 0.5), Vector3(mw, mh, md - 1.0), red)
	RoofsLite.hip(kit, Vector3(0, ph + mh, mz), mw + 1.0, md + 0.8, 1.3, ro.merged({"overhang": 1.2, "horns": false}, true))
	kit.box(Vector3(0, ph + mh + 0.9 + 0.8, mz + 0.2), Vector3(mw * 0.72, 1.6, md * 0.62), FnStyle.wall(FnStyle.NOBLE, v + 1))
	RoofsLite.hip(kit, Vector3(0, ph + mh + 2.5, mz + 0.2), mw * 0.72, md * 0.62, 3.0, ro.merged({"overhang": 1.2, "curve": 1.0}, true))
	if kit.lod < 2:
		FnStyle.flame_finial(kit, Vector3(0, ph + mh + 5.6, mz + 0.2), 1.0)
		var zf := mz - md * 0.5 + 0.5
		for i in 6:
			kit.column(Vector3(lerpf(-mw * 0.5, mw * 0.5, i / 5.0), ph, zf - 0.9), mh - 0.1, 0.22, pil, &"round", FnStyle.BASALT_DARK)
		kit.beam(Vector3(-mw * 0.5, ph + mh - 0.25, zf - 0.9), Vector3(mw * 0.5, ph + mh - 0.25, zf - 0.9), 0.32, 0.4, FnStyle.GOLD)
		kit.stairs(Vector3(0, 0, zf - 2.6), Vector3(0, ph, zf - 1.3), 3.0, {"role": FnStyle.BASALT_2})
		EkHomes.door(kit, Vector3(0, ph, zf), 2.0, 3.0, FnStyle.GOLD, FnStyle.RED_DARK)
		for sx: float in [-1.0, 1.0]:
			EkHomes.window(kit, Vector3(sx * mw * 0.3, ph + 2.1, zf), 1.3, 1.4, FnStyle.GOLD, (v + int(sx > 0.0)) % 2 == 0)
	# side hall
	var sx2 := -1.0 if v % 2 == 0 else 1.0
	var sw := 6.0
	var sd := d - md - 9.0
	if sd > 4.0:
		var x := sx2 * (hw - sw * 0.5 - 1.0)
		var z := -hd + 3.0 + sd * 0.5
		kit.box(Vector3(x, 0.4 + 1.7, z), Vector3(sw, 3.4, sd), red)
		RoofsLite.hip(kit, Vector3(x, 3.8, z), sw, sd, 1.9, ro)
		if kit.lod < 2:
			kit.push(Transform3D(Basis(Vector3.UP, sx2 * PI * 0.5), Vector3(x - sx2 * (sw * 0.5 + 0.03), 0.4, z)))
			EkHomes.door(kit, Vector3.ZERO, 1.3, 2.3, pil, FnStyle.RED_DARK)
			kit.pop()
	# turtle-duck pond with a red bridge, lanterns
	var gx := -sx2 * (hw * 0.42)
	var gz := -hd * 0.22
	var pond := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pond.append(Vector2(gx + cos(a) * 3.4 * (1.0 + 0.12 * sin(a * 3.0)), gz + sin(a) * 2.5))
	kit.slab(pond, 0.0, 0.2, FnStyle.BASALT_2, true)
	if kit.lod < 2:
		var inner := PackedVector2Array()
		for p in pond:
			inner.append(Vector2(gx, gz) + (p - Vector2(gx, gz)) * 0.86)
		kit.g(&"ice").extrude(inner, 0.12, 0.22, kit.col(FnStyle.WATER, false), 2)
		kit.beam(Vector3(gx - 3.6, 0.3, gz), Vector3(gx, 0.7, gz), 1.2, 0.14, FnStyle.RED, true)
		kit.beam(Vector3(gx, 0.7, gz), Vector3(gx + 3.6, 0.3, gz), 1.2, 0.14, FnStyle.RED, true)
		if kit.lod == 0:
			for sz: float in [-1.0, 1.0]:
				kit.beam(Vector3(gx - 3.6, 0.9, gz + sz * 0.55), Vector3(gx, 1.3, gz + sz * 0.55), 0.05, 0.05, FnStyle.RED)
				kit.beam(Vector3(gx, 1.3, gz + sz * 0.55), Vector3(gx + 3.6, 0.9, gz + sz * 0.55), 0.05, 0.05, FnStyle.RED)
			KitX.lantern(kit, Vector3(gx + 4.2, 0.16, gz + 2.2), {"style": &"stone", "height": 1.4, "light": v % 2 == 0, "range": 8.0,
				"role": FnStyle.BASALT_2, "color": Color(1.0, 0.55, 0.25)})
			KitX.lantern(kit, Vector3(sx2 * 2.0, 2.9, -hd - 0.9), {"style": &"paper", "light": false, "color": Color(1.0, 0.45, 0.2)})


## Courtyard trees of a noble_house variant: [[species, local position], ...] on the pond side,
## clear of the halls, the pond and the gate (planted by the planners as tree_row pieces).
static func noble_trees(v: int) -> Array:
	var fp := footprint(&"noble_house", v)
	var hw := fp.x * 0.5
	var hd := fp.y * 0.5
	var side := 1.0 if v % 2 == 0 else -1.0      # opposite the side hall
	var sp: Array[StringName] = [&"maple", &"blossom", &"palm", &"cypress"]
	return [[sp[v % 4], Vector3(side * (hw - 1.9), 0.1, -hd + 2.3)], [sp[(v + 1) % 4], Vector3(side * (hw - 1.9), 0.1, -hd * 0.22)]]


static func villa(kit: BuildingKit, v: int) -> void:
	var fp := footprint(&"fn_villa", v)
	var w := fp.x
	var d := fp.y
	var white := FnStyle.wall(FnStyle.RESORT, v)
	var pil := FnStyle.pillar(FnStyle.RESORT)
	var ro := FnStyle.roof_opts(FnStyle.RESORT, v)
	kit.box(Vector3(0, 0.4, 0), Vector3(w + 2.0, 0.8, d + 2.0), FnStyle.base(FnStyle.RESORT))
	kit.box(Vector3(0, 0.8 + 1.7, 1.0), Vector3(w - 2.0, 3.4, d - 2.0), white)
	for i in 5:
		kit.column(Vector3(lerpf(-w * 0.5 + 0.4, w * 0.5 - 0.4, i / 4.0), 0.8, -d * 0.5 + 0.4), 3.4, 0.2, pil, &"round", FnStyle.base(FnStyle.RESORT))
	RoofsLite.hip(kit, Vector3(0, 4.2, 0.2), w, d, 2.8, ro.merged({"overhang": 1.2, "curve": 0.8}, true))
	if kit.lod >= 2:
		return
	kit.stairs(Vector3(0, 0, -d * 0.5 - 2.2), Vector3(0, 0.8, -d * 0.5 - 1.0), 3.0, {"role": FnStyle.base(FnStyle.RESORT)})
	EkHomes.door(kit, Vector3(0, 0.8, -d * 0.5 + 2.0), 1.8, 2.6, FnStyle.GOLD, FnStyle.RED)
	for sx: float in [-1.0, 1.0]:
		EkHomes.window(kit, Vector3(sx * (w * 0.5 - 3.0), 2.4, -d * 0.5 + 2.0), 1.6, 1.4, FnStyle.RED, v % 2 == 0)
	if kit.lod == 0:
		kit.railing(PackedVector3Array([Vector3(-w * 0.5 + 0.4, 0.8, -d * 0.5 + 0.4), Vector3(-1.5, 0.8, -d * 0.5 + 0.4)]), 0.9, {"role": FnStyle.RED, "spacing": 0.6, "collide": false})
		kit.railing(PackedVector3Array([Vector3(1.5, 0.8, -d * 0.5 + 0.4), Vector3(w * 0.5 - 0.4, 0.8, -d * 0.5 + 0.4)]), 0.9, {"role": FnStyle.RED, "spacing": 0.6, "collide": false})
		for sx: float in [-1.0, 1.0]:
			KitX.lantern(kit, Vector3(sx * 2.4, 3.6, -d * 0.5 + 0.2), {"style": &"paper", "light": sx > 0.0, "range": 8.0, "color": Color(1.0, 0.55, 0.28)})


static func fisher_hut(kit: BuildingKit, v: int) -> void:
	var wood := FnStyle.wall(FnStyle.VILLAGE, v)
	kit.box(Vector3(0, 0.3, 0), Vector3(6.4, 0.6, 6.9), FnStyle.base(FnStyle.VILLAGE))
	kit.box(Vector3(0, 0.6 + 1.3, 0.2), Vector3(5.6, 2.6, 5.8), wood)
	RoofsLite.gable(kit, Vector3(0, 3.2, 0.2), 5.6, 5.8, 1.6, FnStyle.roof_opts(FnStyle.VILLAGE, v, {"overhang": 0.7, "gable_role": wood}))
	if kit.lod >= 2:
		return
	EkHomes.door(kit, Vector3(-0.8, 0.6, -2.72), 1.1, 2.0, FnStyle.pillar(FnStyle.VILLAGE), FnStyle.RED_DARK)
	EkHomes.window(kit, Vector3(1.5, 1.9, -2.72), 0.8, 0.7, FnStyle.pillar(FnStyle.VILLAGE), v % 2 == 0)
	if kit.lod == 0:
		# nets drying on a frame
		var net := Color(0.52, 0.48, 0.40).srgb_to_linear()
		kit.beam(Vector3(3.6, 0, -1.5), Vector3(3.6, 2.2, -1.5), 0.08, 0.08, &"wood_dark")
		kit.beam(Vector3(3.6, 0, 1.5), Vector3(3.6, 2.2, 1.5), 0.08, 0.08, &"wood_dark")
		kit.g(&"cloth").flat_quad(Vector3(3.6, 0.5, -1.5), Vector3(3.6, 0.5, 1.5), Vector3(3.6, 2.15, 1.5), Vector3(3.6, 2.15, -1.5), net)
		kit.g(&"cloth").flat_quad(Vector3(3.6, 0.5, 1.5), Vector3(3.6, 0.5, -1.5), Vector3(3.6, 2.15, -1.5), Vector3(3.6, 2.15, 1.5), net)


static func tea_house(kit: BuildingKit, v: int) -> void:
	var w := 11.0
	var d := 9.0
	var wall_c := FnStyle.wall(FnStyle.VILLAGE, v + 1)
	var pil := FnStyle.pillar(FnStyle.VILLAGE)
	kit.box(Vector3(0, 0.3, 0), Vector3(w + 0.4, 0.6, d + 0.4), FnStyle.base(FnStyle.VILLAGE))
	kit.box(Vector3(0, 0.6 + 1.5, 1.2), Vector3(w, 3.0, d - 2.4), wall_c)
	for i in 4:
		kit.column(Vector3(lerpf(-w * 0.5 + 0.3, w * 0.5 - 0.3, i / 3.0), 0.6, -d * 0.5 + 0.4), 3.0, 0.16, pil, &"round", FnStyle.base(FnStyle.VILLAGE))
	RoofsLite.hip(kit, Vector3(0, 3.6, 0.3), w, d, 2.6, FnStyle.roof_opts(FnStyle.VILLAGE, v, {"overhang": 1.0}))
	if kit.lod >= 2:
		return
	EkHomes.door(kit, Vector3(0, 0.6, -d * 0.5 + 2.4), 1.4, 2.3, pil, FnStyle.RED_DARK)
	for sx: float in [-1.0, 1.0]:
		EkHomes.window(kit, Vector3(sx * w * 0.3, 2.0, -d * 0.5 + 2.4), 1.0, 0.9, pil, v % 2 == 0)
	if kit.lod == 0:
		for k in 3:
			kit.g().cylinder(Vector3(-w * 0.3 + k * 0.7, 0.6, -d * 0.5 + 1.2), Vector3(-w * 0.3 + k * 0.7, 1.0, -d * 0.5 + 1.2), 0.28, 0.32, 7,
					kit.col(EkStyle.STRAW), 2)
