class_name EkHomes
extends RefCounted
## Earth Kingdom dwellings (BuildingKit recipes, thread-safe). Origin = ground centre of the
## footprint, -Z = front (door, street side). Every kind has 8-12 variants (`v`) and a district
## style (EkStyle: lower / middle / upper / farm / Omashu), all archetypes:
##   row_house    attached Lower Ring house: earthen walls, timber frame, 1-2 floors, some shop
##                fronts with cloth awnings and goods, balconies, lit windows
##   tenement     three-storey Lower Ring block with galleries
##   shack        lean-to hut of the poorest lanes
##   town_house   Middle Ring two-storey house: white plaster, dark timber, balcony, grey-green tiles
##   court_house  Middle Ring courtyard compound: tiled wall, roofed gate, main hall, two wings
##   mansion      Upper Ring compound: tiled wall, grand gate, double-eave hall on a podium with a
##                lacquered porch, side halls, a pond and a garden pavilion
##   farmhouse    farmstead: mud-walled house, straw-brown roof, storehouse, yard wall, haystack

## Footprint (width along the street, depth) of a kind and variant.
static func footprint(kind: StringName, v: int) -> Vector2:
	match kind:
		&"row_house":
			return Vector2([6.0, 7.0, 8.0, 9.0][v % 4], [9.0, 10.0, 11.0][v % 3])
		&"tenement":
			return Vector2(12.0 + (v % 2) * 2.0, 11.0)
		&"shack":
			return Vector2(5.0, 5.5)
		&"town_house":
			return Vector2([9.0, 10.0, 11.0][v % 3], [11.0, 12.0][v % 2])
		&"court_house":
			return Vector2([18.0, 20.0, 22.0][v % 3], [19.0, 21.0][v % 2])
		&"mansion":
			return Vector2([30.0, 32.0, 34.0][v % 3], [27.0, 30.0][v % 2])
		&"farmhouse":
			return Vector2([16.0, 18.0][v % 2], [13.0, 14.0, 15.0][v % 3])
		&"teahouse":
			return Vector2(14.0 + (v % 2) * 2.0, 12.0)
	return Vector2(8.0, 8.0)


## Height (m above the ground) of the highest part (arrival clearance checks).
static func height(kind: StringName, v: int) -> float:
	match kind:
		&"row_house": return 6.5 if _floors(v) == 1 else 9.5
		&"tenement": return 13.5
		&"shack": return 3.4
		&"town_house": return 10.0
		&"court_house": return 8.0
		&"mansion": return 14.0
		&"farmhouse": return 7.5
		&"teahouse": return 11.0
	return 8.0


static func build(kit: BuildingKit, kind: StringName, v: int, style: int) -> void:
	match kind:
		&"row_house": row_house(kit, v, style)
		&"tenement": tenement(kit, v, style)
		&"shack": shack(kit, v, style)
		&"town_house": town_house(kit, v, style)
		&"court_house": court_house(kit, v, style)
		&"mansion": mansion(kit, v, style)
		&"farmhouse": farmhouse(kit, v, style)


static func _floors(v: int) -> int:
	return 2 if v % 3 == 1 or v % 5 == 4 else 1


# --- shared parts ----------------------------------------------------------------------------------

## Wooden double door on a face facing -Z at local `c` (bottom centre): dark opening, frame,
## leaves ajar (LOD0), a stone step.
static func door(kit: BuildingKit, c: Vector3, w: float, h: float, frame: Variant, leaf: Variant = &"door") -> void:
	kit.box(c + Vector3(0, h * 0.5, -0.03), Vector3(w, h, 0.06), &"window", false)
	if kit.lod >= 2:
		return
	kit.box(c + Vector3(0, h + 0.1, -0.08), Vector3(w + 0.5, 0.22, 0.18), frame, false)
	for sx: float in [-1.0, 1.0]:
		kit.box(c + Vector3(sx * (w * 0.5 + 0.1), h * 0.5, -0.08), Vector3(0.18, h, 0.18), frame, false)
	if kit.lod == 0:
		for sx: float in [-1.0, 1.0]:
			kit.box_t(Transform3D(Basis(Vector3.UP, sx * 0.5), c + Vector3(sx * w * 0.36, h * 0.48, -0.25)), Vector3(w * 0.46, h * 0.95, 0.07), leaf, false)
		kit.box(c + Vector3(0, 0.07, -0.45), Vector3(w + 0.6, 0.14, 0.8), &"stone", false)


## Lattice window (dark pane + frame, or lit amber with mullions) on a face facing -Z.
static func window(kit: BuildingKit, c: Vector3, w: float, h: float, frame: Variant, lit: bool) -> void:
	KitX.window(kit, c, w, h, frame, 0.04, lit)
	if kit.lod == 0 and not lit:
		kit.box(c + Vector3(0, 0, -0.07), Vector3(0.05, h, 0.04), frame, false)
		kit.box(c + Vector3(0, 0, -0.07), Vector3(w, 0.05, 0.04), frame, false)


## Timber frame on a box wall face (posts at the corners + a floor beam): face facing -Z at z,
## from x0..x1, height h, floor lines `floors`.
static func frame_face(kit: BuildingKit, x0: float, x1: float, y0: float, h: float, z: float, floors: int, col: Color) -> void:
	if kit.lod >= 2:
		return
	for x: float in [x0, x1]:
		kit.box(Vector3(x, y0 + h * 0.5, z - 0.06), Vector3(0.24, h, 0.14), col, false)
	for f in range(1, floors + 1):
		var y := y0 + h * f / floors - (0.12 if f == floors else 0.0)
		kit.box(Vector3((x0 + x1) * 0.5, y, z - 0.06), Vector3(x1 - x0, 0.2, 0.14), col, false)


## Decorative lattice openings ("leak windows") along a compound wall from a to b (both faces).
static func _leak_windows(kit: BuildingKit, a: Vector3, b: Vector3, wh: float, frame: Variant) -> void:
	var length := a.distance_to(b)
	var n := int(length / 3.6)
	if n < 1:
		return
	var dir := (b - a) / length
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized())
	for k in n:
		var p := a + dir * (length * (k + 0.5) / n) + Vector3(0, wh * 0.62, 0)
		kit.box_t(Transform3D(basis, p), Vector3(0.95, 0.75, 0.5), &"window", false)
		kit.box_t(Transform3D(basis, p), Vector3(0.95, 0.07, 0.54), frame, false)
		for sx: float in [-0.17, 0.17]:
			kit.box_t(Transform3D(basis, p + dir * sx), Vector3(0.07, 0.75, 0.54), frame, false)
		for sy: float in [-1.0, 1.0]:
			kit.box_t(Transform3D(basis, p + Vector3(0, sy * 0.42, 0)), Vector3(1.2, 0.1, 0.58), frame, false)
		for sx: float in [-1.0, 1.0]:
			kit.box_t(Transform3D(basis, p + dir * sx * 0.52), Vector3(0.1, 0.94, 0.58), frame, false)


## Cloth awning over a shop front (cloth slot, ripples), sloping down towards -Z.
static func awning(kit: BuildingKit, c: Vector3, w: float, depth: float, drop: float, col: Color) -> void:
	if kit.lod >= 2:
		return
	var cb := kit.g(&"cloth")
	var nx := 4 if kit.lod == 0 else 1
	var base := cb.vertex_count()
	for j in 3:
		var t := j / 2.0
		for i in nx + 1:
			var u := float(i) / nx
			var stripe := col if (i % 2 == 0 or kit.lod > 0) else col.lightened(0.35)
			cb.vertex(c + Vector3((u - 0.5) * w, -drop * t - sin(t * PI) * 0.12, -depth * t), Vector3(0, 0.9, -0.4).normalized(), stripe, Vector2(t, u))
	for j in 2:
		for i in nx:
			var k := base + j * (nx + 1) + i
			cb.quad(k, k + nx + 1, k + nx + 2, k + 1)
	for sx: float in [-1.0, 1.0]:
		kit.beam(c + Vector3(sx * w * 0.5, -drop, -depth), c + Vector3(sx * w * 0.5, -drop - 1.9, -depth), 0.08, 0.08, &"wood_dark")


## Goods on a shop counter (pots, baskets, bolts of cloth) by variant.
static func goods(kit: BuildingKit, c: Vector3, w: float, v: int) -> void:
	if kit.lod > 0:
		return
	var n := maxi(int(w / 0.7), 2)
	for i in n:
		var x := (i + 0.5) / n * w - w * 0.5
		var p := c + Vector3(x, 0, 0)
		match (v + i) % 4:
			0: kit.g().cylinder(p, p + Vector3(0, 0.34, 0), 0.16, 0.12, 6, kit.col(Color(0.62, 0.36, 0.20).srgb_to_linear()), 2)
			1: kit.g().cylinder(p, p + Vector3(0, 0.22, 0), 0.22, 0.25, 6, kit.col(EkStyle.STRAW), 2)
			2: kit.box(p + Vector3(0, 0.1, 0), Vector3(0.5, 0.2, 0.32), EkStyle.AWNINGS[(v + i) % 5], false)
			_: kit.g().blob(p + Vector3(0, 0.14, 0), 0.15, 0, kit.col(Color(0.80, 0.52, 0.20).srgb_to_linear()))


# --- Lower Ring ----------------------------------------------------------------------------------

static func row_house(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"row_house", v)
	var w := fp.x
	var d := fp.y
	var floors := _floors(v)
	var fh := 3.0
	var bh := 0.3
	var wall_c := EkStyle.wall(style, v)
	var tim := EkStyle.timber(style)
	var hh := floors * fh
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 0.2, bh, d + 0.2), EkStyle.base(style))
	kit.box(Vector3(0, bh + hh * 0.5, 0), Vector3(w, hh, d), wall_c)
	var shop := v % 4 == 0 and style == EkStyle.LOWER
	var zf := -d * 0.5
	var ro := EkStyle.roof_opts(style, v + 1)
	if v % 2 == 0:
		RoofsLite.gable(kit, Vector3(0, bh + hh, 0), w, d, minf(d * 0.3, 3.2), ro.merged({"overhang": 0.55, "gable_role": wall_c}, true))
	else:
		RoofsLite.hip(kit, Vector3(0, bh + hh, 0), w, d, minf(d * 0.28, 3.0), ro.merged({"overhang": 0.6}, true))
	if kit.lod >= 2:
		return
	frame_face(kit, -w * 0.5, w * 0.5, bh, hh, zf, floors, tim)
	if shop:
		# open shop front: dark recess, counter with goods, cloth awning
		kit.box(Vector3(0, bh + 1.25, zf - 0.02), Vector3(w - 1.0, 2.5, 0.06), &"window", false)
		kit.box(Vector3(0, bh + 0.45, zf - 0.45), Vector3(w - 1.2, 0.9, 0.7), tim, true)
		goods(kit, Vector3(0, bh + 0.9, zf - 0.45), w - 1.6, v)
		awning(kit, Vector3(0, bh + 2.9, zf - 0.1), w - 0.4, 1.6, 0.5, EkStyle.AWNINGS[v % 5])
	else:
		var dx := -w * 0.22 if w > 7.0 else 0.0
		door(kit, Vector3(dx, bh, zf), 1.2, 2.2, tim)
		if w > 7.0:
			window(kit, Vector3(w * 0.25, bh + 1.6, zf), 1.0, 0.9, tim, v % 3 == 0)
	if floors > 1:
		for k in (2 if w > 7.5 else 1):
			var x := (k - 0.5) * w * 0.42 if w > 7.5 else 0.0
			window(kit, Vector3(x, bh + fh + 1.4, zf), 0.9, 0.9, tim, (v + k) % 3 == 1)
		if v % 4 == 1 and kit.lod == 0:
			# little balcony
			kit.box(Vector3(0, bh + fh + 0.05, zf - 0.45), Vector3(w * 0.6, 0.12, 0.9), tim, false)
			kit.railing(PackedVector3Array([Vector3(-w * 0.3, bh + fh + 0.1, zf - 0.88), Vector3(w * 0.3, bh + fh + 0.1, zf - 0.88)]), 0.8,
					{"role": tim, "collide": false, "spacing": 0.6})
	if kit.lod == 0:
		# eave lantern / sign board / chimney pot
		if v % 3 == 2:
			KitX.lantern(kit, Vector3(w * 0.38, bh + 2.5, zf - 0.5), {"style": &"paper", "light": false, "color": Color(1.0, 0.62, 0.3)})
		if v % 5 == 1:
			kit.box(Vector3(0, bh + 2.75, zf - 0.08), Vector3(minf(w - 1.0, 2.6), 0.5, 0.06), EkStyle.AWNINGS[(v + 2) % 5], false)
		if v % 4 == 3:
			kit.g().cylinder(Vector3(w * 0.3, bh + hh + 0.6, d * 0.2), Vector3(w * 0.3, bh + hh + 2.2, d * 0.2), 0.3, 0.26, 6, kit.col(EkStyle.base(style)), 2)
		# side and back windows (dark), side posts (the gable ends seen from the lanes)
		kit.box(Vector3(0, bh + 1.8, d * 0.5 + 0.03), Vector3(0.9, 0.8, 0.06), &"window", false)
		for sx: float in [-1.0, 1.0]:
			for zz: float in [0.0, d * 0.5 - 0.1]:
				kit.box(Vector3(sx * (w * 0.5 + 0.04), bh + hh * 0.5, zz), Vector3(0.1, hh, 0.22), tim, false)
			kit.box(Vector3(sx * (w * 0.5 + 0.04), bh + hh - 0.15, 0), Vector3(0.1, 0.2, d), tim, false)
		kit.box(Vector3(w * 0.5 + 0.03, bh + 1.9, d * 0.2), Vector3(0.06, 0.7, 0.8), &"window", false)
		kit.box(Vector3(-w * 0.5 - 0.03, bh + 1.9, -d * 0.2), Vector3(0.06, 0.7, 0.8), &"window", false)


static func tenement(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"tenement", v)
	var w := fp.x
	var d := fp.y
	var fh := 3.1
	var floors := 3
	var hh := fh * floors
	var tim := EkStyle.timber(style)
	var wall_c := EkStyle.wall(style, v + 1)
	kit.box(Vector3(0, 0.2, 0), Vector3(w + 0.3, 0.4, d + 0.3), EkStyle.base(style))
	kit.box(Vector3(0, 0.4 + hh * 0.5, 0.4), Vector3(w, hh, d - 0.8), wall_c)
	RoofsLite.hip(kit, Vector3(0, 0.4 + hh, 0.2), w, d - 0.4, 3.2, EkStyle.roof_opts(style, v, {"overhang": 0.8}))
	if kit.lod >= 2:
		return
	var zf := -d * 0.5 + 0.8
	frame_face(kit, -w * 0.5, w * 0.5, 0.4, hh, zf, floors, tim)
	# galleries on the upper floors with railings and pent roofs
	for f in range(1, floors):
		var y := 0.4 + fh * f
		kit.box(Vector3(0, y, zf - 0.55), Vector3(w, 0.16, 1.1), tim, true)
		if kit.lod == 0:
			kit.railing(PackedVector3Array([Vector3(-w * 0.5, y + 0.08, zf - 1.05), Vector3(w * 0.5, y + 0.08, zf - 1.05)]), 0.85, {"role": tim, "spacing": 1.2, "collide": false})
		for k in 3:
			window(kit, Vector3(lerpf(-w * 0.32, w * 0.32, k / 2.0), y + 1.4, zf), 0.9, 1.0, tim, (v + k + f) % 4 == 0)
	RoofsLite.pent(kit, Vector3(0, 0.4 + fh * 2.0 - 0.1, zf), w + 0.4, 1.4, 0.5, EkStyle.roof_opts(style, v + 2))
	door(kit, Vector3(-w * 0.25, 0.4, zf), 1.4, 2.3, tim)
	door(kit, Vector3(w * 0.25, 0.4, zf), 1.4, 2.3, tim)
	if kit.lod == 0:
		# washing line between the gallery posts
		KitX.flag_string(kit, Vector3(-w * 0.45, 0.4 + fh * 2 + 2.0, zf - 1.0), Vector3(w * 0.45, 0.4 + fh * 2 + 2.0, zf - 1.0), 0.3,
				[EkStyle.AWNINGS[0], EkStyle.AWNINGS[3], EkStyle.AWNINGS[4]], 0.45)


static func shack(kit: BuildingKit, v: int, style: int) -> void:
	var w := 5.0
	var d := 5.5
	var h := 2.6
	var tim := EkStyle.timber(style)
	kit.box(Vector3(0, h * 0.5, 0.2), Vector3(w, h, d - 0.4), EkStyle.wall(style, v + 2))
	RoofsLite.pent(kit, Vector3(0, h + 0.6, d * 0.5), w + 0.6, d + 0.4, 1.0, {"role": EkStyle.roof(style, v), "fascia_role": tim})
	kit.collide_box(Vector3(0, h + 0.2, 0), Vector3(w + 0.6, 0.6, d + 0.4))
	if kit.lod >= 2:
		return
	door(kit, Vector3(-0.8, 0.0, -d * 0.5 + 0.2), 1.0, 1.9, tim)
	if kit.lod == 0:
		kit.box(Vector3(1.4, 0.4, -d * 0.5 - 0.3), Vector3(1.0, 0.8, 0.6), &"wood", true)
		kit.g().cylinder(Vector3(1.6, 0, -d * 0.5 - 1.1), Vector3(1.6, 0.6, -d * 0.5 - 1.1), 0.28, 0.32, 6, kit.col(Color(0.55, 0.34, 0.20).srgb_to_linear()), 2)


# --- Middle Ring ---------------------------------------------------------------------------------

static func town_house(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"town_house", v)
	var w := fp.x
	var d := fp.y
	var fh := 3.3
	var bh := 0.5
	var tim := EkStyle.timber(style)
	var wall_c := EkStyle.wall(style, v)
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 0.4, bh, d + 0.4), EkStyle.base(style))
	kit.box(Vector3(0, bh + fh * 0.5, 0.3), Vector3(w, fh, d - 0.6), wall_c)
	kit.box(Vector3(0, bh + fh * 1.5, 0.5), Vector3(w - 0.6, fh, d - 1.4), wall_c)
	var ro := EkStyle.roof_opts(style, v, {"overhang": 0.9})
	RoofsLite.pent(kit, Vector3(0, bh + fh + 0.35, -d * 0.5 + 0.6 + 0.2), w + 0.4, 1.4, 0.55, ro)
	RoofsLite.hip(kit, Vector3(0, bh + fh * 2.0, 0.5), w - 0.6, d - 1.4, 2.8, ro)
	if kit.lod >= 2:
		return
	var zf := -d * 0.5 + 0.6
	frame_face(kit, -w * 0.5, w * 0.5, bh, fh, zf, 1, tim)
	frame_face(kit, -w * 0.5 + 0.3, w * 0.5 - 0.3, bh + fh, fh, zf + 0.4, 1, tim)
	door(kit, Vector3(0, bh, zf), 1.5, 2.4, tim)
	for sx: float in [-1.0, 1.0]:
		window(kit, Vector3(sx * w * 0.3, bh + 1.7, zf), 1.2, 1.1, tim, v % 3 == 0 and sx > 0.0)
	# balcony with railing on the upper floor
	kit.box(Vector3(0, bh + fh + 0.05, zf - 0.25), Vector3(w - 1.0, 0.14, 1.3), tim, true)
	if kit.lod == 0:
		kit.railing(PackedVector3Array([Vector3(-w * 0.5 + 0.6, bh + fh + 0.12, zf - 0.85), Vector3(w * 0.5 - 0.6, bh + fh + 0.12, zf - 0.85)]), 0.85,
				{"role": tim, "spacing": 0.5, "collide": false})
	for k in 2:
		window(kit, Vector3((k - 0.5) * w * 0.4, bh + fh + 1.5, zf + 0.4), 1.1, 1.2, tim, (v + k) % 3 == 1)
	if kit.lod == 0 and v % 2 == 1:
		KitX.lantern(kit, Vector3(w * 0.5 - 0.5, bh + fh - 0.4, zf - 0.7), {"style": &"paper", "light": v % 4 == 1, "range": 7.0})


static func court_house(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"court_house", v)
	var w := fp.x
	var d := fp.y
	var tim := EkStyle.timber(style)
	var wall_c := EkStyle.wall(style, v)
	var ro := EkStyle.roof_opts(style, v)
	var hw := w * 0.5
	var hd := d * 0.5
	var wh := 2.5
	# courtyard paving
	kit.box(Vector3(0, 0.08, 0), Vector3(w - 0.6, 0.16, d - 0.6), EkStyle.PAVING, true)
	# compound wall with tile coping, gap for the gate
	var gw := 3.6
	var segs := [[Vector3(-hw, 0, -hd), Vector3(-gw * 0.5, 0, -hd)], [Vector3(gw * 0.5, 0, -hd), Vector3(hw, 0, -hd)],
		[Vector3(hw, 0, -hd), Vector3(hw, 0, hd)], [Vector3(hw, 0, hd), Vector3(-hw, 0, hd)], [Vector3(-hw, 0, hd), Vector3(-hw, 0, -hd)]]
	for sg: Array in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		kit.wall(a, b, wh, 0.45, {"role": wall_c, "cap": false, "base_role": EkStyle.base(style)})
		if kit.lod < 2:
			var dir := (b - a).normalized()
			var mid := (a + b) * 0.5
			var t := Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), mid + Vector3(0, wh, 0))
			kit.push(t)
			RoofsLite.gable(kit, Vector3.ZERO, a.distance_to(b) + 0.3, 0.5, 0.45, ro.merged({"overhang": 0.25, "horns": false, "collide": false}, true))
			kit.pop()
			if kit.lod == 0:
				_leak_windows(kit, a, b, wh, tim)
	# roofed gate
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (gw * 0.5 + 0.3), 1.7, -hd), Vector3(0.6, 3.4, 0.8), wall_c)
	kit.box(Vector3(0, 3.25, -hd), Vector3(gw + 1.2, 0.5, 1.0), tim, false)
	RoofsLite.hip(kit, Vector3(0, 3.5, -hd), gw + 1.0, 1.4, 1.2, ro.merged({"overhang": 0.6}, true))
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			kit.box_t(Transform3D(Basis(Vector3.UP, sx * 1.2), Vector3(sx * gw * 0.42, 1.4, -hd + 0.55)), Vector3(gw * 0.48, 2.8, 0.08), &"door", false)
	# main hall at the back
	var mh := 3.8
	var md := 7.0
	var mz := hd - md * 0.5 - 0.6
	kit.box(Vector3(0, 0.3, mz), Vector3(w - 2.4, 0.6, md + 0.8), EkStyle.base(style))
	kit.box(Vector3(0, 0.6 + mh * 0.5, mz + 0.4), Vector3(w - 3.4, mh, md - 0.8), wall_c)
	RoofsLite.hip(kit, Vector3(0, 0.6 + mh, mz + 0.2), w - 3.4, md - 0.4, 2.9, ro.merged({"overhang": 1.1}, true))
	# side wings
	var ww := 4.6
	var wd := d - md - 6.5
	if wd > 3.0:
		for sx: float in [-1.0, 1.0]:
			var x: float = sx * (hw - ww * 0.5 - 0.6)
			var z := -hd + 2.6 + wd * 0.5 + 0.4
			kit.box(Vector3(x, 0.3 + 1.6, z), Vector3(ww, 3.2, wd), wall_c)
			RoofsLite.gable(kit, Vector3(x, 3.5, z), ww, wd, 1.7, ro.merged({"overhang": 0.6, "gable_role": wall_c}, true))
			if kit.lod < 2:
				var face_x: float = x - sx * (ww * 0.5 + 0.03)
				kit.push(Transform3D(Basis(Vector3.UP, sx * PI * 0.5), Vector3(face_x, 0.3, z)))
				door(kit, Vector3.ZERO, 1.1, 2.1, tim)
				kit.pop()
	if kit.lod >= 2:
		return
	var zf := mz - md * 0.5 + 0.8
	frame_face(kit, -(w - 3.4) * 0.5, (w - 3.4) * 0.5, 0.6, mh, zf, 1, tim)
	door(kit, Vector3(0, 0.6, zf), 1.8, 2.6, tim)
	for sx: float in [-1.0, 1.0]:
		window(kit, Vector3(sx * (w - 3.4) * 0.3, 2.3, zf), 1.4, 1.2, tim, v % 2 == 0)
	# porch columns
	for i in 4:
		var x := lerpf(-(w - 3.4) * 0.5 + 0.4, (w - 3.4) * 0.5 - 0.4, i / 3.0)
		kit.column(Vector3(x, 0.6, zf - 0.7), mh - 0.2, 0.16, tim, &"round", EkStyle.base(style))
	if kit.lod == 0:
		# courtyard: a planter with a small tree, a stone lantern, a water jar
		var pc := Vector3(w * 0.12, 0.16, -hd * 0.1)
		kit.box(pc + Vector3(0, 0.3, 0), Vector3(1.4, 0.6, 1.4), EkStyle.base(style), true)
		kit.g().cylinder(pc + Vector3(0, 0.6, 0), pc + Vector3(0, 2.0, 0), 0.08, 0.06, 5, kit.col(&"wood_dark"), 0)
		kit.g().blob(pc + Vector3(0, 2.4, 0), 0.9, 1, kit.col(Color(0.24, 0.46, 0.20).srgb_to_linear()), kit.rng, 0.2, Vector3(1.0, 0.75, 1.0))
		KitX.lantern(kit, Vector3(-w * 0.2, 0.16, -hd * 0.25), {"style": &"stone", "height": 1.4, "light": v % 3 == 0, "range": 7.0})
		kit.g().cylinder(Vector3(-w * 0.28, 0.16, hd * 0.05), Vector3(-w * 0.28, 0.8, hd * 0.05), 0.4, 0.34, 8, kit.col(Color(0.36, 0.30, 0.26).srgb_to_linear()), 2)
		KitX.lantern(kit, Vector3(gw * 0.5 + 0.2, 2.6, -hd - 0.6), {"style": &"paper", "light": false, "color": Color(1.0, 0.62, 0.3)})


# --- Upper Ring ----------------------------------------------------------------------------------

static func mansion(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"mansion", v)
	var w := fp.x
	var d := fp.y
	var hw := w * 0.5
	var hd := d * 0.5
	var lac := EkStyle.timber(EkStyle.UPPER)
	var wall_c := EkStyle.wall(style, v)
	var ro := EkStyle.roof_opts(EkStyle.UPPER, v)
	var wh := 3.2
	kit.box(Vector3(0, 0.08, 0), Vector3(w - 0.8, 0.16, d - 0.8), EkStyle.PAVING, true)
	# compound wall with a grand gate
	var gw := 5.0
	var segs := [[Vector3(-hw, 0, -hd), Vector3(-gw * 0.5 - 1.0, 0, -hd)], [Vector3(gw * 0.5 + 1.0, 0, -hd), Vector3(hw, 0, -hd)],
		[Vector3(hw, 0, -hd), Vector3(hw, 0, hd)], [Vector3(hw, 0, hd), Vector3(-hw, 0, hd)], [Vector3(-hw, 0, hd), Vector3(-hw, 0, -hd)]]
	for sg: Array in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		kit.wall(a, b, wh, 0.55, {"role": wall_c, "cap": false, "base_role": EkStyle.base(EkStyle.UPPER)})
		if kit.lod < 2:
			var dir := (b - a).normalized()
			kit.push(Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), (a + b) * 0.5 + Vector3(0, wh, 0)))
			RoofsLite.gable(kit, Vector3.ZERO, a.distance_to(b) + 0.4, 0.6, 0.5, ro.merged({"overhang": 0.3, "horns": false, "collide": false}, true))
			kit.pop()
			if kit.lod == 0:
				_leak_windows(kit, a, b, wh, EkStyle.COPING)
	# gate house: piers, lacquered posts, a hip roof with gold ridge
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (gw * 0.5 + 0.5), 2.2, -hd), Vector3(1.0, 4.4, 1.4), wall_c)
		kit.column(Vector3(sx * gw * 0.42, 0.0, -hd - 1.0), 4.0, 0.24, lac, &"round", EkStyle.base(EkStyle.UPPER))
	kit.box(Vector3(0, 4.2, -hd - 0.3), Vector3(gw + 2.4, 0.6, 2.4), EkStyle.COPING, false)
	RoofsLite.hip(kit, Vector3(0, 4.5, -hd - 0.3), gw + 2.2, 2.4, 1.8, ro.merged({"overhang": 0.9, "curve": 0.7}, true))
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			kit.box_t(Transform3D(Basis(Vector3.UP, sx * 1.3), Vector3(sx * gw * 0.4, 1.7, -hd + 0.75)), Vector3(gw * 0.48, 3.4, 0.1), EkStyle.LACQUER, false)
		if kit.lod == 0:
			for sx: float in [-1.0, 1.0]:
				_lion(kit, Vector3(sx * (gw * 0.5 + 1.8), 0.0, -hd - 1.6))
				KitX.lantern(kit, Vector3(sx * (gw * 0.5 + 0.6), 3.5, -hd - 1.2), {"style": &"paper", "light": sx > 0.0, "range": 9.0})
	# main hall on a podium: double eaves, porch of lacquered columns
	var mw := w - 8.0
	var md := 10.0
	var mz := hd - md * 0.5 - 2.0
	var ph := 1.0
	var mh := 4.4
	kit.box(Vector3(0, ph * 0.5, mz), Vector3(mw + 3.0, ph, md + 3.0), EkStyle.base(EkStyle.UPPER))
	kit.box(Vector3(0, ph + mh * 0.5, mz + 0.6), Vector3(mw, mh, md - 1.2), wall_c)
	var y1 := ph + mh
	RoofsLite.hip(kit, Vector3(0, y1, mz), mw + 1.2, md + 1.0, 1.4, ro.merged({"overhang": 1.3, "curve": 0.6, "horns": false}, true))
	kit.box(Vector3(0, y1 + 1.0 + 0.9, mz + 0.2), Vector3(mw * 0.74, 1.8, md * 0.66), EkStyle.wall(EkStyle.UPPER, v + 1))
	RoofsLite.hip(kit, Vector3(0, y1 + 2.8, mz + 0.2), mw * 0.74, md * 0.66, 3.4, ro.merged({"overhang": 1.3, "curve": 0.9}, true))
	if kit.lod < 2:
		var zf := mz - md * 0.5 + 0.6
		for i in 6:
			var x := lerpf(-mw * 0.5, mw * 0.5, i / 5.0)
			kit.column(Vector3(x, ph, zf - 1.0), mh - 0.1, 0.24, lac, &"round", EkStyle.base(EkStyle.UPPER))
		kit.beam(Vector3(-mw * 0.5, ph + mh - 0.25, zf - 1.0), Vector3(mw * 0.5, ph + mh - 0.25, zf - 1.0), 0.35, 0.4, EkStyle.COPING)
		kit.stairs(Vector3(0, 0, zf - 2.9), Vector3(0, ph, zf - 1.5), 3.2, {"role": EkStyle.base(EkStyle.UPPER)})
		door(kit, Vector3(0, ph, zf), 2.0, 3.0, lac, EkStyle.LACQUER)
		for sx: float in [-1.0, 1.0]:
			for k in 2:
				window(kit, Vector3(sx * mw * (0.2 + k * 0.17), ph + 2.2, zf), 1.3, 1.5, lac, (v + k) % 2 == 0)
		if kit.lod == 0:
			KitX.banner(kit, Transform3D(Basis(), Vector3(0, ph + mh - 0.5, zf - 1.05)), 1.4, 2.4, EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth")
	# side hall
	var sx2 := -1.0 if v % 2 == 0 else 1.0
	var sw := 6.0
	var sd := d - md - 9.0
	if sd > 4.0:
		var x := sx2 * (hw - sw * 0.5 - 1.0)
		var z := -hd + 3.2 + sd * 0.5
		kit.box(Vector3(x, 0.4 + 1.8, z), Vector3(sw, 3.6, sd), wall_c)
		RoofsLite.hip(kit, Vector3(x, 4.0, z), sw, sd, 2.0, ro.merged({"overhang": 0.8}, true))
		if kit.lod < 2:
			kit.push(Transform3D(Basis(Vector3.UP, sx2 * PI * 0.5), Vector3(x - sx2 * (sw * 0.5 + 0.03), 0.4, z)))
			door(kit, Vector3.ZERO, 1.3, 2.3, lac)
			window(kit, Vector3(sd * 0.25, 1.8, 0), 1.0, 1.0, lac, v % 3 == 1)
			kit.pop()
	# garden pond with a small pavilion on the other side
	var gx := -sx2 * (hw * 0.45)
	var gz := -hd * 0.25
	var pond := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pond.append(Vector2(gx + cos(a) * 3.6 * (1.0 + 0.15 * sin(a * 3.0)), gz + sin(a) * 2.6))
	kit.slab(pond, 0.0, 0.2, EkStyle.base(EkStyle.UPPER), true)
	if kit.lod < 2:
		var inner := PackedVector2Array()
		for p in pond:
			inner.append(Vector2(gx, gz) + (p - Vector2(gx, gz)) * 0.86)
		kit.g(&"ice").extrude(inner, 0.12, 0.22, kit.col(EkStyle.WATER, false), 2)
		var px := gx - sx2 * 0.5
		var pz := gz + 4.4
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				kit.column(Vector3(px + cx * 1.3, 0.16, pz + cz * 1.3), 2.6, 0.12, lac, &"round", EkStyle.base(EkStyle.UPPER))
		RoofsLite.hip(kit, Vector3(px, 2.75, pz), 2.6, 2.6, 1.5, ro.merged({"overhang": 0.7, "curve": 0.8}, true))
		if kit.lod == 0:
			for k in 3:
				var rp := Vector3(gx + kit.rng.randf_range(-2.4, 2.4), 0.2, gz + kit.rng.randf_range(-1.6, 1.6) - 2.9)
				kit.g().blob(rp + Vector3(0, 0.3, 0), kit.rng.randf_range(0.4, 0.7), 0, kit.col(&"stone"), kit.rng, 0.25)
			KitX.lantern(kit, Vector3(gx + 3.4, 0.16, gz - 1.6), {"style": &"stone", "height": 1.5, "light": v % 2 == 1, "range": 8.0})


## A guardian lion on a plinth (gate statues).
static func _lion(kit: BuildingKit, p: Vector3) -> void:
	var s := kit.col(EkStyle.base(EkStyle.UPPER))
	kit.box(p + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 1.4), EkStyle.base(EkStyle.UPPER), true)
	var g := kit.g()
	g.blob(p + Vector3(0, 1.35, 0.15), 0.42, 0, s, null, 0.0, Vector3(0.8, 0.9, 1.1))
	g.blob(p + Vector3(0, 1.85, -0.25), 0.36, 0, s, null, 0.0, Vector3(1.1, 1.0, 1.0))
	g.blob(p + Vector3(0, 2.05, -0.3), 0.28, 0, kit.col(EkStyle.GOLD), null, 0.0, Vector3(1.3, 0.7, 0.8))


# --- farmsteads ------------------------------------------------------------------------------------

static func farmhouse(kit: BuildingKit, v: int, style: int) -> void:
	var fp := footprint(&"farmhouse", v)
	var w := fp.x
	var d := fp.y
	var hw := w * 0.5
	var hd := d * 0.5
	var tim := EkStyle.timber(EkStyle.FARM)
	var mud := EkStyle.wall(EkStyle.FARM, v)
	var ro := EkStyle.roof_opts(EkStyle.FARM, v, {"overhang": 0.8, "curve": 0.25})
	# yard (packed earth) + low mud wall around three sides
	kit.box(Vector3(0, 0.04, 0), Vector3(w - 0.4, 0.08, d - 0.4), EkStyle.FIELD_DIRT, false)
	if kit.lod < 2:
		var pts := [[Vector3(-hw, 0, -hd + 3.0), Vector3(-hw, 0, hd)], [Vector3(-hw, 0, hd), Vector3(hw, 0, hd)], [Vector3(hw, 0, hd), Vector3(hw, 0, -hd + 3.0)],
			[Vector3(-hw, 0, -hd), Vector3(-hw + 3.0, 0, -hd)]]
		for sg: Array in pts:
			kit.wall(sg[0], sg[1], 1.4, 0.4, {"role": mud, "cap_role": EkStyle.roof(EkStyle.FARM, v)})
	# main house (back of the yard, facing -Z)
	var mw := w * 0.62
	var md := 6.0
	var mz := hd - md * 0.5 - 0.5
	var mx := -hw + mw * 0.5 + 0.6
	kit.box(Vector3(mx, 0.2, mz), Vector3(mw + 0.3, 0.4, md + 0.3), EkStyle.base(EkStyle.FARM))
	kit.box(Vector3(mx, 0.4 + 1.5, mz), Vector3(mw, 3.0, md), mud)
	if v % 2 == 0:
		RoofsLite.gable(kit, Vector3(mx, 3.4, mz), mw, md, 2.4, ro.merged({"gable_role": mud}, true))
	else:
		RoofsLite.hip(kit, Vector3(mx, 3.4, mz), mw, md, 2.3, ro)
	# storehouse / barn
	var bw := w - mw - 2.2
	var bd := 4.6
	var bx := hw - bw * 0.5 - 0.4
	var bz := hd - bd * 0.5 - 0.6
	kit.box(Vector3(bx, 1.3, bz), Vector3(bw, 2.6, bd), EkStyle.wall(EkStyle.FARM, v + 1))
	RoofsLite.gable(kit, Vector3(bx, 2.6, bz), bw, bd, 1.6, ro.merged({"gable_role": EkStyle.timber(EkStyle.FARM)}, true))
	if kit.lod >= 2:
		return
	var zf := mz - md * 0.5
	frame_face(kit, mx - mw * 0.5, mx + mw * 0.5, 0.4, 3.0, zf, 1, tim)
	door(kit, Vector3(mx - mw * 0.15, 0.4, zf), 1.2, 2.1, tim)
	window(kit, Vector3(mx + mw * 0.25, 2.0, zf), 1.0, 0.8, tim, v % 3 == 0)
	kit.box(Vector3(bx, 1.1, bz - bd * 0.5 - 0.02), Vector3(bw * 0.6, 2.2, 0.06), &"window", false)
	if kit.lod == 0:
		# haystack, cart, well / grain jars, firewood
		var hx := -hw + 2.4
		var hz := -hd + 4.2
		kit.g().cylinder(Vector3(hx, 0, hz), Vector3(hx, 1.6, hz), 1.3, 1.1, 8, kit.col(EkStyle.STRAW), 0)
		kit.g().cone(Vector3(hx, 1.6, hz), Vector3(hx, 2.8, hz), 1.15, 8, kit.col(EkStyle.STRAW))
		kit.collide_box(Vector3(hx, 1.2, hz), Vector3(2.2, 2.4, 2.2))
		EkProps.cart(kit, Vector3(hw - 2.6, 0, -hd + 2.6), 0.5 + v * 0.3)
		for k in 3:
			kit.g().cylinder(Vector3(mx + mw * 0.45 - k * 0.7, 0.4, zf - 0.6), Vector3(mx + mw * 0.45 - k * 0.7, 1.1, zf - 0.6), 0.28, 0.24, 7,
					kit.col(Color(0.48, 0.30, 0.18).srgb_to_linear()), 2)
		kit.box(Vector3(bx + bw * 0.5 + 0.35, 0.5, bz), Vector3(0.6, 1.0, bd * 0.8), &"wood_dark", true)
		KitX.lantern(kit, Vector3(mx + mw * 0.45, 2.7, zf - 0.4), {"style": &"paper", "light": false, "color": Color(1.0, 0.6, 0.28)})
