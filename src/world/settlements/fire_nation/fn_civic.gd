class_name FnCivic
extends RefCounted
## Fire Nation civic spaces and street furniture (BuildingKit recipes, thread-safe):
##   fn_plaza       dark paving with a red ring and the flame emblem inlaid in gold; centre by
##                  variant: v 0 a great brazier, v 1 a dragon statue, v 2 open
##   sun_monument   the Plaza of the Sun: a gold sun disc with flame rays on a basalt column in a
##                  ring of great braziers on a stepped dais
##   kata_grounds   the scorched-black drill courtyard (spec w, d): soot-dark flagstones, a red
##                  border, braziers at the corners, wooden practice posts, banners, a master's dais
##   fn_garden      garden (spec w, d, v): lawn, a turtle-duck pond with a red bridge, a black-roofed
##                  pavilion, rockery, stone lanterns (plants: FnBuilder.garden_plants)
##   fn_stall       market stall with a red / gold awning
##   fn_lamp        iron lamp post with a red paper lantern (v 0) or a basalt stone lantern (v 1)
##   fn_statue      v 0 a coiled dragon, v 1 a firebending master, on a basalt plinth
##   fn_temple      the kit's Fire Nation temple (BuildingPresets.fn_temple)
##   lantern_string red paper lanterns on a sagging wire between two iron poles (spec L, h, n, light)

static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	match kind:
		&"fn_plaza": plaza(kit, spec)
		&"sun_monument": sun_monument(kit, spec)
		&"kata_grounds": kata_grounds(kit, spec)
		&"fn_garden": garden(kit, spec)
		&"fn_stall": stall(kit, v)
		&"fn_lamp": lamp(kit, v, bool(spec.get("light", false)))
		&"lantern_string": lantern_string(kit, spec)
		&"fn_statue": statue(kit, v)
		&"fn_temple": BuildingPresets.fn_temple(kit, Transform3D(), {"w": float(spec.get("w", 11.0)), "d": float(spec.get("d", 9.0))})


static func _ring(r: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * i / sides
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


## A flat flame emblem inlay (gold ribbons) on the ground at local c, `size` across, the tip -Z.
static func flame_inlay(kit: BuildingKit, c: Vector3, size: float, col: Color) -> void:
	var cc := kit.col(col, false)
	var segs := 10 if kit.lod == 0 else 5
	for k in 3:
		var side := float(k - 1)
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		var hgt := size * (0.9 if k == 1 else 0.55)
		for i in segs + 1:
			var t := float(i) / segs
			var x := side * size * (0.16 + 0.1 * sin(t * PI)) - side * size * 0.12 * t * t
			pts.append(c + Vector3(x, 0.0, size * 0.36 - t * hgt))
			ws.append(size * (0.2 if k == 1 else 0.12) * (1.0 - t * 0.9) + 0.02)
		KitX.ribbon(kit, pts, ws, cc)
	var disc := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		disc.append(Vector2(c.x + cos(a) * size * 0.16, c.z + size * 0.32 + sin(a) * size * 0.16))
	kit.g().extrude(disc, c.y, c.y + 0.005, cc, 2)


static func plaza(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 12.0))
	var v := int(spec.get("v", 0))
	var sides := 32 if kit.lod == 0 else 16
	kit.slab(_ring(r, sides), -0.4, 0.08, FnStyle.PAVING_DARK, true)
	if kit.lod >= 2:
		return
	kit.slab(_ring(r - 0.8, sides), 0.0, 0.1, FnStyle.PAVING, false)
	var ring := PackedVector3Array()
	var ws := PackedFloat32Array()
	for i in 33:
		var a := TAU * i / 32.0
		ring.append(Vector3(cos(a), 0, sin(a)) * (r - 1.6) + Vector3(0, 0.11, 0))
		ws.append(0.5)
	KitX.ribbon(kit, ring, ws, kit.col(FnStyle.RED, false))
	if kit.lod == 0 and v != 0:
		flame_inlay(kit, Vector3(0, 0.112, 0), r * 0.6, FnStyle.GOLD * 0.78)
	match v % 3:
		0:
			kit.push(Transform3D())
			FnWalls.brazier(kit, 1)
			kit.pop()
			kit.cylinder(Vector3(0, 0.1, 0), 0.35, 2.4, FnStyle.BASALT_DARK, 12, true)
		1:
			kit.push(Transform3D(Basis(), Vector3(0, 0, r * 0.25)))
			statue(kit, 0)
			kit.pop()


static func sun_monument(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 22.0))
	var sides := 40 if kit.lod == 0 else 20
	kit.slab(_ring(r, sides), -0.4, 0.1, FnStyle.PAVING_DARK, true)
	kit.slab(_ring(r * 0.42, sides), 0.0, 0.6, FnStyle.BASALT, true)
	kit.slab(_ring(r * 0.3, sides), 0.0, 1.2, FnStyle.BASALT_2, true)
	if kit.lod < 2:
		kit.slab(_ring(r - 0.9, sides), 0.0, 0.12, FnStyle.PAVING, false)
		# radiating flame rays in red and gold
		for i in 16:
			var a := TAU * i / 16.0
			var pts := PackedVector3Array([Vector3(cos(a), 0, sin(a)) * (r * 0.45) + Vector3(0, 0.13, 0), Vector3(cos(a), 0, sin(a)) * (r - 1.8) + Vector3(0, 0.13, 0)])
			KitX.ribbon(kit, pts, PackedFloat32Array([1.4, 0.2]), kit.col(FnStyle.RED if i % 2 == 0 else FnStyle.GOLD, false))
	# the sun: a gold disc with flame rays on a column
	var h := 9.0
	kit.cylinder(Vector3(0, 1.2, 0), h, 0.9, FnStyle.BASALT_DARK, 10, true, 0.7)
	var sc := Vector3(0, 1.2 + h + 2.4, 0)
	kit.g().cylinder(sc + Vector3(0, 0, -0.25), sc + Vector3(0, 0, 0.25), 2.2, 2.2, 20 if kit.lod == 0 else 10, kit.col(FnStyle.GOLD), 3)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 0.3)
	gb.cylinder(sc + Vector3(0, 0, -0.3), sc + Vector3(0, 0, -0.26), 1.4, 1.4, 16 if kit.lod == 0 else 8, Color(1.0, 0.6, 0.2), 3)
	gb.cylinder(sc + Vector3(0, 0, 0.26), sc + Vector3(0, 0, 0.3), 1.4, 1.4, 16 if kit.lod == 0 else 8, Color(1.0, 0.6, 0.2), 3)
	if kit.lod < 2:
		for i in 12:
			var a := TAU * i / 12.0
			var d := Vector3(cos(a), sin(a), 0)
			kit.g().cone(sc + d * 2.0, sc + d * (3.4 + (i % 2) * 0.8), 0.45, 4, kit.col(FnStyle.GOLD))
	kit.add_light(sc, Color(1.0, 0.6, 0.25), 18.0, 2.0, 3)
	# ring of great braziers
	if kit.lod < 2:
		for i in 8:
			var a := TAU * (i + 0.5) / 8.0
			kit.push(Transform3D(Basis(), Vector3(cos(a), 0, sin(a)) * (r * 0.72)))
			FnWalls.brazier(kit, 1)
			kit.pop()


static func kata_grounds(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 40.0))
	var d := float(spec.get("d", 34.0))
	var hw := w * 0.5
	var hd := d * 0.5
	kit.box(Vector3(0, 0.05, 0), Vector3(w, 0.1, d), FnStyle.SCORCH, true)
	if kit.lod >= 2:
		return
	for sz: float in [-1.0, 1.0]:
		kit.box(Vector3(0, 0.12, sz * (hd - 0.4)), Vector3(w, 0.1, 0.8), FnStyle.RED_DARK, false)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (hw - 0.4), 0.12, 0), Vector3(0.8, 0.1, d), FnStyle.RED_DARK, false)
	if kit.lod == 0:
		# soot marks and cracked flagstones
		for i in 18:
			var p := Vector3(kit.rng.randf_range(-hw + 3.0, hw - 3.0), 0.105, kit.rng.randf_range(-hd + 3.0, hd - 3.0))
			var disc := PackedVector2Array()
			var rr := kit.rng.randf_range(0.8, 2.2)
			for k in 7:
				var a := TAU * k / 7.0
				disc.append(Vector2(p.x + cos(a) * rr * kit.rng.randf_range(0.7, 1.2), p.z + sin(a) * rr * kit.rng.randf_range(0.7, 1.2)))
			kit.g().extrude(disc, 0.1, 0.106, kit.col(FnStyle.BLACK), 2)
		flame_inlay(kit, Vector3(0, 0.11, 0), 7.0, FnStyle.RED)
	# braziers at the corners, practice posts, banners, a master's dais
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.push(Transform3D(Basis(), Vector3(sx * (hw - 2.0), 0.1, sz * (hd - 2.0))))
			FnWalls.brazier(kit, 1)
			kit.pop()
	for k in 5:
		var p := Vector3(lerpf(-hw + 6.0, hw - 6.0, k / 4.0), 0.1, -hd + 4.0)
		kit.cylinder(p, 1.8, 0.16, &"wood_dark", 6, true)
		if kit.lod == 0:
			kit.beam(p + Vector3(-0.5, 1.3, 0), p + Vector3(0.5, 1.3, 0), 0.1, 0.1, &"wood")
			kit.g().blob(p + Vector3(0, 1.9, 0), 0.22, 0, kit.col(EkStyle.STRAW))
	var dz := hd - 3.0
	kit.box(Vector3(0, 0.4, dz), Vector3(8.0, 0.8, 3.0), FnStyle.BASALT, true)
	kit.stairs(Vector3(0, 0.1, dz - 2.6), Vector3(0, 0.8, dz - 1.5), 3.0, {"role": FnStyle.BASALT_2})
	for sx: float in [-1.0, 1.0]:
		var bp := Vector3(sx * 5.4, 0.1, dz + 0.8)
		kit.cylinder(bp, 6.0, 0.12, FnStyle.BASALT_DARK, 6, true)
		KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI), Vector3(bp.x, 5.8, bp.z + 0.1)), 1.4, 4.2, FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire", 2)


static func garden(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 24.0))
	var d := float(spec.get("d", 20.0))
	var v := int(spec.get("v", 0))
	var lawn := Color(0.22, 0.36, 0.14).srgb_to_linear()
	kit.box(Vector3(0, 0.05, 0), Vector3(w, 0.1, d), lawn, true)
	if kit.lod >= 2:
		return
	for sz: float in [-1.0, 1.0]:
		kit.box(Vector3(0, 0.15, sz * d * 0.5), Vector3(w, 0.3, 0.4), FnStyle.BASALT_2, false)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * w * 0.5, 0.15, 0), Vector3(0.4, 0.3, d), FnStyle.BASALT_2, false)
	var pc := Vector2(w * (0.14 if v % 2 == 0 else -0.14), d * 0.06)
	var pr := minf(w, d) * 0.25
	var pond := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pond.append(pc + Vector2(cos(a), sin(a)) * pr * (1.0 + 0.12 * sin(a * 3.0 + v)))
	kit.g().extrude(pond, 0.0, 0.18, kit.col(FnStyle.BASALT_2), 2)
	var inner := PackedVector2Array()
	for p in pond:
		inner.append(pc + (p - pc) * 0.88)
	kit.g(&"ice").extrude(inner, 0.1, 0.2, kit.col(FnStyle.WATER, false), 2)
	# arched red bridge
	var b0 := Vector3(pc.x - pr * 1.1, 0.25, pc.y)
	var b1 := Vector3(pc.x, 0.9, pc.y)
	var b2 := Vector3(pc.x + pr * 1.1, 0.25, pc.y)
	for seg: Array in [[b0, b1], [b1, b2]]:
		kit.beam(seg[0], seg[1], 1.6, 0.16, FnStyle.RED, true)
		if kit.lod == 0:
			for sz: float in [-1.0, 1.0]:
				kit.beam((seg[0] as Vector3) + Vector3(0, 0.6, sz * 0.75), (seg[1] as Vector3) + Vector3(0, 0.6, sz * 0.75), 0.06, 0.06, FnStyle.RED)
	# black-roofed pavilion
	var pv := Vector3(-pc.x * 1.6, 0.0, -d * 0.26)
	kit.cylinder(pv, 0.4, 2.8, FnStyle.BASALT, 6, true)
	for k in 6:
		var a := TAU * k / 6.0
		kit.column(pv + Vector3(cos(a) * 2.2, 0.4, sin(a) * 2.2), 2.6, 0.12, FnStyle.RED, &"round", FnStyle.BASALT_DARK)
	KitRoofs.cone(kit, pv + Vector3(0, 3.0, 0), 3.2, 2.0, {"sides": 6, "flare": 0.9, "role": FnStyle.roof(FnStyle.NOBLE, 0), "alt_role": FnStyle.roof(FnStyle.NOBLE, 1),
		"trim_role": FnStyle.GOLD, "finial": true, "finial_role": FnStyle.GOLD})
	if kit.lod == 0:
		for k in 5:
			var a := float(k) * 1.2 + float(v)
			var rp := Vector3(pc.x + cos(a) * (pr + 1.0), 0.1, pc.y + sin(a) * (pr + 0.9))
			var s := kit.rng.randf_range(0.4, 0.8)
			kit.g().blob(rp + Vector3(0, s * 0.5, 0), s, 0, kit.col(FnStyle.BASALT_2), kit.rng, 0.3, Vector3(1.0, 1.3, 0.9))
	for sx: float in [-1.0, 1.0]:
		KitX.lantern(kit, Vector3(sx * w * 0.38, 0.1, d * 0.36), {"style": &"stone", "height": 1.5, "light": sx > 0.0 and v % 2 == 0, "range": 9.0,
			"role": FnStyle.BASALT_2, "color": Color(1.0, 0.55, 0.25)})


## A string of red paper lanterns sagging between two iron poles across a street (spec L, h, n,
## light: the middle lantern lights the street).
static func lantern_string(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 8.0))
	var hh := float(spec.get("h", 4.8))
	var n := int(spec.get("n", 5))
	for sx: float in [-1.0, 1.0]:
		kit.cylinder(Vector3(sx * L * 0.5, 0, 0), hh, 0.08, FnStyle.BLACK, 6, true, 0.06)
		if kit.lod < 2:
			FnStyle.flame_finial(kit, Vector3(sx * L * 0.5, hh, 0), 0.35)
	if kit.lod >= 2:
		return
	var sag := L * 0.08
	var pts := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in 9:
		var t := i / 8.0
		pts.append(Vector3(lerpf(-L * 0.5, L * 0.5, t), hh - 0.15 - sag * 4.0 * t * (1.0 - t), 0))
		rr.append(0.02)
	kit.g().tube(pts, rr, 3, kit.col(FnStyle.BLACK))
	for i in n:
		var t := (i + 1.0) / (n + 1.0)
		var p := Vector3(lerpf(-L * 0.5, L * 0.5, t), hh - 0.15 - sag * 4.0 * t * (1.0 - t) - 0.5, 0)
		KitX.lantern(kit, p, {"style": &"paper", "light": bool(spec.get("light", false)) and i == n / 2, "range": 9.0, "energy": 1.4,
			"color": Color(0.9, 0.16, 0.06)})


static func stall(kit: BuildingKit, v: int) -> void:
	var w := 3.0
	var d := 1.8
	var tim := FnStyle.RED_DARK
	kit.box(Vector3(0, 0.45, 0), Vector3(w, 0.9, d * 0.55), tim, true)
	if kit.lod < 2:
		kit.box(Vector3(0, 0.92, 0), Vector3(w + 0.1, 0.06, d * 0.6), FnStyle.BASALT_DARK, false)
		EkHomes.goods(kit, Vector3(0, 0.95, 0), w - 0.4, v)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * (w * 0.5 - 0.05), 0, sz * (d * 0.5 - 0.05))
			kit.beam(p, p + Vector3(0, 2.4 + (0.25 if sz > 0.0 else 0.0), 0), 0.08, 0.08, FnStyle.BLACK)
	var aw: Color = FnStyle.AWNINGS[v % FnStyle.AWNINGS.size()]
	if kit.lod < 2:
		EkHomes.awning(kit, Vector3(0, 2.65, d * 0.5), w + 0.4, d + 0.2, 0.4, aw)
	else:
		kit.box(Vector3(0, 2.4, 0), Vector3(w + 0.4, 0.1, d + 0.2), aw, false)


static func lamp(kit: BuildingKit, v: int, light: bool) -> void:
	if v % 2 == 1:
		KitX.lantern(kit, Vector3.ZERO, {"style": &"stone", "height": 1.8, "light": light, "range": 10.0, "role": FnStyle.BASALT_2,
			"color": Color(1.0, 0.55, 0.25)})
		return
	kit.box(Vector3(0, 0.12, 0), Vector3(0.6, 0.24, 0.6), FnStyle.BASALT_DARK, false)
	kit.cylinder(Vector3(0, 0.2, 0), 3.6, 0.08, FnStyle.BLACK, 6, true, 0.06)
	if kit.lod < 2:
		kit.beam(Vector3(0, 3.55, 0), Vector3(0.8, 3.75, 0), 0.08, 0.1, FnStyle.BLACK)
		FnStyle.flame_finial(kit, Vector3(0, 3.8, 0), 0.4)
	KitX.lantern(kit, Vector3(0.78, 2.95, 0), {"style": &"paper", "light": light, "range": 10.0, "energy": 1.6, "color": Color(1.0, 0.42, 0.18)})


static func statue(kit: BuildingKit, v: int) -> void:
	kit.box(Vector3(0, 0.7, 0), Vector3(3.4, 1.4, 3.4), FnStyle.BASALT, true)
	kit.box(Vector3(0, 1.48, 0), Vector3(3.0, 0.16, 3.0), FnStyle.GOLD, false)
	var g := kit.g()
	var c := kit.col(FnStyle.BASALT_2 if v % 2 == 0 else FnStyle.GOLD * 0.85)
	if v % 2 == 0:
		# a coiled dragon rearing up, head forward (-Z)
		var body := PackedVector3Array()
		var radii := PackedFloat32Array()
		var segs := 14 if kit.lod == 0 else 7
		for i in segs + 1:
			var t := float(i) / segs
			var a := t * TAU * 1.1
			body.append(Vector3(cos(a) * 1.0 * (1.0 - t * 0.5), 1.8 + t * 3.2, sin(a) * 1.0 * (1.0 - t * 0.5) - t * 0.6))
			radii.append(0.42 * (1.0 - t * 0.45))
		g.tube(body, radii, 7 if kit.lod == 0 else 5, c)
		var head := body[body.size() - 1]
		g.blob(head + Vector3(0, 0.1, -0.4), 0.48, 0, c, null, 0.0, Vector3(0.9, 0.8, 1.4))
		if kit.lod < 2:
			for sx: float in [-1.0, 1.0]:
				g.cone(head + Vector3(sx * 0.25, 0.4, 0.0), head + Vector3(sx * 0.45, 1.0, 0.5), 0.1, 4, kit.col(FnStyle.GOLD))
			g.cone(head + Vector3(0, 0.0, -0.9), head + Vector3(0, -0.1, -1.3), 0.2, 5, kit.col(FnStyle.GOLD))
	else:
		g.cylinder(Vector3(0, 1.56, 0), Vector3(0, 3.6, 0), 0.6, 0.5, 8, c, 2)
		g.blob(Vector3(0, 4.05, 0), 0.36, 0, c)
		if kit.lod < 2:
			g.cylinder(Vector3(0.35, 3.3, 0), Vector3(0.6, 3.6, -0.8), 0.15, 0.14, 6, c, 2)
			var gb := kit.g(&"glow")
			gb.uv = Vector2(0, 1)
			gb.cone(Vector3(0.6, 3.6, -0.9), Vector3(0.62, 4.4, -1.1), 0.25, 5, Color(1.0, 0.55, 0.2))
	kit.collide_box(Vector3(0, 3.0, 0), Vector3(2.4, 3.2, 2.4))
