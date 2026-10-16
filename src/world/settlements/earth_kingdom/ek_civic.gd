class_name EkCivic
extends RefCounted
## Earth Kingdom civic spaces (BuildingKit recipes, thread-safe; origin on the ground, -Z front):
##   plaza       paved disc with a dark border ring, the Earth Kingdom seal inlaid, a centre
##               feature by variant (v 0 tiered fountain, v 1 bronze incense burner, v 2 open)
##   garden      walled-less park (spec w x d): lawn, an irregular pond with a zig-zag bridge, a
##               pavilion, rockery, stepping-stone path, stone lanterns, benches (trees, bamboo,
##               shrubs and flowers are VegetationLibrary plants: EkBuilder.garden_plants)
##   pavilion    open hexagonal pavilion with a curved roof and benches
##   teahouse    two-storey teahouse: open ground floor with tables, balcony, hanging lanterns,
##               a cloth sign (the enterable tea shop is EkPlaces.tea_shop)
##   footbridge  arched stone footbridge along local Z (spec span, width)
##   canal       irrigation channel segment along local Z (spec L, W, depth): stone lining, water

static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"plaza": plaza(kit, spec)
		&"garden": garden(kit, spec)
		&"pavilion": pavilion(kit, spec)
		&"teahouse": teahouse(kit, spec)
		&"footbridge": footbridge(kit, spec)
		&"canal": canal(kit, spec)


static func _ring(r: float, sides: int, c: Vector2 = Vector2.ZERO, wob: float = 0.0, seed: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * i / sides
		var rr := r * (1.0 + wob * sin(a * 3.0 + seed) + wob * 0.5 * sin(a * 5.0 + seed * 2.0))
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


static func plaza(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 12.0))
	var v := int(spec.get("v", 0))
	var sides := 32 if kit.lod == 0 else 16
	kit.slab(_ring(r, sides), -0.4, 0.08, EkStyle.PAVING_DARK, true)
	if kit.lod >= 2:
		return
	kit.slab(_ring(r - 0.8, sides), 0.0, 0.1, EkStyle.PAVING, false)
	if kit.lod == 0:
		# radiating joints and the seal: a ring around a square
		for i in 24:
			var a := TAU * i / 24.0
			kit.beam(Vector3(cos(a), 0, sin(a)) * (r * 0.5) + Vector3(0, 0.105, 0), Vector3(cos(a), 0, sin(a)) * (r - 0.8) + Vector3(0, 0.105, 0), 0.07, 0.02, EkStyle.PAVING_DARK)
		var ring := PackedVector3Array()
		var ws := PackedFloat32Array()
		for i in 33:
			var a := TAU * i / 32.0
			ring.append(Vector3(cos(a), 0, sin(a)) * (r * 0.42) + Vector3(0, 0.11, 0))
			ws.append(r * 0.06)
		KitX.ribbon(kit, ring, ws, kit.col(EkStyle.COPING, false))
	match v % 3:
		0:
			# tiered fountain
			kit.cylinder(Vector3(0, 0.1, 0), 0.7, r * 0.3, EkStyle.base(EkStyle.MIDDLE), 16, true)
			kit.g(&"ice").cylinder(Vector3(0, 0.7, 0), Vector3(0, 0.78, 0), r * 0.27, r * 0.27, 16, kit.col(EkStyle.WATER, false), 2)
			kit.cylinder(Vector3(0, 0.78, 0), 1.6, 0.5, EkStyle.base(EkStyle.UPPER), 8, true)
			kit.cylinder(Vector3(0, 2.3, 0), 0.25, 1.4, EkStyle.base(EkStyle.MIDDLE), 12, true)
			kit.g(&"ice").cylinder(Vector3(0, 2.5, 0), Vector3(0, 2.56, 0), 1.25, 1.25, 12, kit.col(EkStyle.WATER, false), 2)
			if kit.lod == 0:
				kit.g(&"ice").cone(Vector3(0, 2.55, 0), Vector3(0, 3.4, 0), 0.25, 6, kit.col(EkStyle.WATER.lightened(0.3), false))
		1:
			# bronze incense burner on legs
			kit.box(Vector3(0, 0.3, 0), Vector3(2.2, 0.4, 2.2), EkStyle.base(EkStyle.UPPER), true)
			for k in 3:
				var a := TAU * k / 3.0
				kit.beam(Vector3(cos(a) * 0.6, 0.5, sin(a) * 0.6), Vector3(cos(a) * 0.45, 1.2, sin(a) * 0.45), 0.14, 0.14, EkStyle.GOLD)
			kit.g().cylinder(Vector3(0, 1.1, 0), Vector3(0, 1.8, 0), 0.6, 0.75, 10, kit.col(EkStyle.GOLD * 0.8), 1)
			if kit.lod == 0:
				RoofsLite.hip(kit, Vector3(0, 2.1, 0), 0.9, 0.9, 0.7, {"role": EkStyle.GOLD * 0.75, "ridge_role": EkStyle.GOLD, "overhang": 0.2, "collide": false, "horns": false})
				kit.g().blob(Vector3(0, 2.9, 0), 0.16, 0, kit.col(EkStyle.GOLD))


static func garden(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 30.0))
	var d := float(spec.get("d", 24.0))
	var v := int(spec.get("v", 0))
	var lawn := Color(0.26, 0.42, 0.16).srgb_to_linear()
	kit.box(Vector3(0, 0.05, 0), Vector3(w, 0.1, d), lawn, true)
	if kit.lod >= 2:
		return
	# border curb
	for sz: float in [-1.0, 1.0]:
		kit.box(Vector3(0, 0.15, sz * d * 0.5), Vector3(w, 0.3, 0.4), EkStyle.base(EkStyle.MIDDLE), false)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * w * 0.5, 0.15, 0), Vector3(0.4, 0.3, d), EkStyle.base(EkStyle.MIDDLE), false)
	# pond
	var pc := Vector2(w * (0.12 if v % 2 == 0 else -0.12), d * 0.08)
	var pr := minf(w, d) * 0.26
	var pond := _ring(pr, 14 if kit.lod == 0 else 8, pc, 0.12, float(v))
	kit.g().extrude(pond, 0.0, 0.18, kit.col(EkStyle.base(EkStyle.MIDDLE)), 2)
	var inner := PackedVector2Array()
	for p in pond:
		inner.append(pc + (p - pc) * 0.88)
	kit.g(&"ice").extrude(inner, 0.1, 0.2, kit.col(EkStyle.WATER, false), 2)
	# zig-zag bridge across the pond
	var tim := EkStyle.LACQUER
	var b0 := Vector3(pc.x - pr * 1.05, 0.25, pc.y - pr * 0.2)
	var b1 := Vector3(pc.x, 0.45, pc.y + pr * 0.25)
	var b2 := Vector3(pc.x + pr * 1.05, 0.25, pc.y - pr * 0.15)
	for seg: Array in [[b0, b1], [b1, b2]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		kit.beam(a, b, 1.6, 0.18, EkStyle.timber(EkStyle.MIDDLE), true)
		if kit.lod == 0:
			var side := (b - a).cross(Vector3.UP).normalized() * 0.75
			for s: float in [-1.0, 1.0]:
				kit.beam(a + side * s + Vector3(0, 0.6, 0), b + side * s + Vector3(0, 0.6, 0), 0.06, 0.06, tim)
	# pavilion
	var pv := Vector3(-pc.x * 1.6, 0.0, -d * 0.24)
	kit.push(Transform3D(Basis(), pv))
	pavilion(kit, {"v": v, "r": 2.2})
	kit.pop()
	# rockery + stepping stones + lanterns + benches
	if kit.lod == 0:
		for k in 6:
			var a := float(k) * 1.1 + float(v)
			var rp := Vector3(pc.x + cos(a) * (pr + 1.0), 0.1, pc.y + sin(a) * (pr + 0.9))
			var s := kit.rng.randf_range(0.4, 0.9)
			kit.g().blob(rp + Vector3(0, s * 0.5, 0), s, 0, kit.col(EkStyle.base(EkStyle.LOWER)), kit.rng, 0.3, Vector3(1.0, 1.3, 0.9))
		var path_n := 9
		for k in path_n:
			var t := float(k) / (path_n - 1)
			var sp := Vector3(lerpf(-w * 0.45, pv.x, t), 0.11, lerpf(d * 0.4, pv.z + 2.6, t) + sin(t * 5.0) * 0.8)
			kit.g().cylinder(sp, sp + Vector3(0, 0.05, 0), 0.38, 0.38, 6, kit.col(EkStyle.PAVING), 2)
	for sx: float in [-1.0, 1.0]:
		KitX.lantern(kit, Vector3(sx * w * 0.38, 0.1, d * 0.36), {"style": &"stone", "height": 1.6, "light": sx > 0.0 and v % 2 == 0, "range": 9.0})
		kit.push(Transform3D(Basis(Vector3.UP, PI), Vector3(sx * w * 0.3, 0.1, -d * 0.42)))
		EkProps.bench(kit, 0)
		kit.pop()


static func pavilion(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 2.6))
	var v := int(spec.get("v", 0))
	var lac := EkStyle.LACQUER
	kit.cylinder(Vector3.ZERO, 0.4, r + 0.5, EkStyle.base(EkStyle.UPPER), 6, true)
	var h := 2.7
	for k in 6:
		var a := TAU * k / 6.0
		kit.column(Vector3(cos(a) * r, 0.4, sin(a) * r), h, 0.13, lac, &"round", EkStyle.base(EkStyle.UPPER))
	if kit.lod < 2:
		for k in 6:
			var a0 := TAU * k / 6.0
			var a1 := TAU * (k + 1) / 6.0
			kit.beam(Vector3(cos(a0) * r, 0.4 + h - 0.15, sin(a0) * r), Vector3(cos(a1) * r, 0.4 + h - 0.15, sin(a1) * r), 0.16, 0.2, EkStyle.COPING)
			if kit.lod == 0 and k != 1:
				kit.beam(Vector3(cos(a0) * r, 0.85, sin(a0) * r), Vector3(cos(a1) * r, 0.85, sin(a1) * r), 0.32, 0.08, EkStyle.timber(EkStyle.MIDDLE))
	KitRoofs.cone(kit, Vector3(0, 0.4 + h, 0), r + 1.0, 2.2, {"sides": 6, "flare": 0.9, "role": EkStyle.roof(EkStyle.UPPER, v), "alt_role": EkStyle.roof(EkStyle.UPPER, v + 1),
		"trim_role": EkStyle.COPING, "finial": true, "finial_role": EkStyle.GOLD})


static func teahouse(kit: BuildingKit, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	var style := int(spec.get("style", EkStyle.MIDDLE))
	var fp := EkHomes.footprint(&"teahouse", v)
	var w := fp.x
	var d := fp.y
	var tim := EkStyle.timber(style)
	var wall_c := EkStyle.wall(style, v)
	var ro := EkStyle.roof_opts(style, v, {"overhang": 1.1, "curve": 0.7, "horns": true})
	var fh := 3.6
	kit.box(Vector3(0, 0.25, 0), Vector3(w + 0.6, 0.5, d + 0.6), EkStyle.base(style))
	# ground floor: back + side walls, open front with posts
	var zf := -d * 0.5
	kit.box(Vector3(0, 0.5 + fh * 0.5, d * 0.5 - 0.2), Vector3(w, fh, 0.4), wall_c)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (w * 0.5 - 0.2), 0.5 + fh * 0.5, 0.0), Vector3(0.4, fh, d), wall_c)
	kit.box(Vector3(0, 0.5 + fh + 0.1, 0), Vector3(w, 0.2, d), tim)
	for i in 5:
		kit.column(Vector3(lerpf(-w * 0.5 + 0.2, w * 0.5 - 0.2, i / 4.0), 0.5, zf + 0.2), fh, 0.16, tim, &"round", EkStyle.base(style))
	# upper floor + balcony
	kit.box(Vector3(0, 0.7 + fh + fh * 0.5, 0.6), Vector3(w - 0.8, fh, d - 1.2), wall_c)
	kit.box(Vector3(0, 0.7 + fh, zf + 0.2), Vector3(w, 0.14, 1.6), tim, true)
	RoofsLite.pent(kit, Vector3(0, 0.6 + fh, zf + 0.6), w + 0.6, 1.5, 0.5, ro)
	RoofsLite.hip(kit, Vector3(0, 0.7 + fh * 2.0, 0.6), w - 0.8, d - 1.2, 3.2, ro)
	if kit.lod >= 2:
		return
	kit.box(Vector3(0, 0.5 + fh * 0.5, d * 0.5 - 0.45), Vector3(w - 1.0, fh - 0.4, 0.06), &"interior", false)
	if kit.lod == 0:
		kit.railing(PackedVector3Array([Vector3(-w * 0.5, 0.78 + fh, zf - 0.55), Vector3(w * 0.5, 0.78 + fh, zf - 0.55)]), 0.9, {"role": tim, "spacing": 0.5, "collide": false})
		# tables + stools inside the open front
		for k in 3:
			var tp := Vector3(lerpf(-w * 0.3, w * 0.3, k / 2.0), 0.5, -d * 0.12)
			kit.cylinder(tp, 0.75, 0.55, tim, 8, true)
			for s in 3:
				var a := TAU * s / 3.0 + k
				kit.cylinder(tp + Vector3(cos(a) * 0.9, 0, sin(a) * 0.9), 0.45, 0.2, tim, 6, false)
		for k in 4:
			KitX.lantern(kit, Vector3(lerpf(-w * 0.4, w * 0.4, k / 3.0), 0.5 + fh - 0.5, zf - 0.2), {"style": &"paper", "light": k == 1 or k == 2,
				"range": 9.0, "color": Color(1.0, 0.55, 0.28)})
	for k in 3:
		KitX.window(kit, Vector3(lerpf(-w * 0.3, w * 0.3, k / 2.0), 0.7 + fh + 1.7, zf + 1.2 - 0.02), 1.3, 1.2, tim, 0.04, (v + k) % 2 == 0)
	# the tea sign: a vertical cloth banner
	KitX.banner(kit, Transform3D(Basis(), Vector3(w * 0.5 + 0.1, 0.5 + fh - 0.1, zf - 0.3)), 0.8, 2.4, EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"none")


static func footbridge(kit: BuildingKit, spec: Dictionary) -> void:
	var span := float(spec.get("span", 5.0))
	var w := float(spec.get("width", 3.0))
	var hump := float(spec.get("hump", 0.6))
	var total := span + 3.0
	var n := 6 if kit.lod == 0 else 3
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a := Vector3(0, hump * sin(t0 * PI), lerpf(-total * 0.5, total * 0.5, t0))
		var b := Vector3(0, hump * sin(t1 * PI), lerpf(-total * 0.5, total * 0.5, t1))
		kit.beam(a - Vector3(0, 0.25, 0), b - Vector3(0, 0.25, 0), w, 0.5, EkStyle.base(EkStyle.MIDDLE))
		kit.collide_quad(Vector3(-w * 0.5, a.y, a.z), Vector3(w * 0.5, a.y, a.z), Vector3(w * 0.5, b.y, b.z), Vector3(-w * 0.5, b.y, b.z))
		for sx: float in [-1.0, 1.0]:
			kit.beam(Vector3(sx * (w * 0.5 - 0.15), a.y + 0.45, a.z), Vector3(sx * (w * 0.5 - 0.15), b.y + 0.45, b.z), 0.3, 0.9, EkStyle.base(EkStyle.UPPER), true)


static func canal(kit: BuildingKit, spec: Dictionary) -> void:
	# a raised stone channel (the terrain is not carved): walls 0.8 m tall, water at 0.62 m
	var L := float(spec.get("L", 16.0))
	var W := float(spec.get("W", 3.0))
	var hl := L * 0.5
	var stone := EkStyle.base(EkStyle.LOWER)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (W * 0.5 + 0.25), 0.3, 0), Vector3(0.5, 1.2, L + 0.05), stone, true)
	kit.box(Vector3(0, 0.0, 0), Vector3(W, 0.4, L), EkStyle.FIELD_DIRT, false)
	kit.g(&"ice").box(Transform3D(Basis(), Vector3(0, 0.6, 0)), Vector3(W, 0.04, L + 0.04), kit.col(EkStyle.WATER, false), 4 | 16 | 32 | 1 | 2)
	if kit.lod == 0:
		for k in int(L / 4.0):
			var z := -hl + (k + 0.5) * L / int(L / 4.0)
			for sx: float in [-1.0, 1.0]:
				kit.box(Vector3(sx * (W * 0.5 + 0.25), 0.91, z), Vector3(0.52, 0.02, 0.06), EkStyle.PAVING_DARK, false)
