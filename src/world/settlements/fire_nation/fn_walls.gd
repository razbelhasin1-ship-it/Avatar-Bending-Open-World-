class_name FnWalls
extends RefCounted
## Fire Nation masonry (BuildingKit recipes, thread-safe). Frames as in EkWalls: x along the wall,
## the face at z = 0 looking -Z towards the lower side, y = 0 on the lower ground.
##   fn_tier_wall  retaining wall of a tier step (spec L, H, P, depth, bottom, style, v, end, banner):
##                 basalt face, a red frieze with gold edges, flame-tipped merlons (&"crenel") or a
##                 red-and-gold balustrade (&"balustrade"), brazier niches, red flame banners
##   fn_stair      grand stair over a tier ramp (spec H, R, W, half): basalt cheeks, red-gold
##                 copings, brazier pillars at the foot and the top
##   fn_gate       gate arch over a street (spec span, height): two basalt pillars, a red beam with
##                 the flame emblem and a black tiled roof with gold flame finials
##   gate_fort     the gatehouse of a road (spec W opening, Wt tower width, D depth, H wall
##                 height, Ho opening height, bottom): twin towers with black hip roofs, the
##                 lintel with the flame emblem, open iron-studded leaves, red banners, braziers
##   fn_curtain    a free-standing curtain wall chord (spec L, H, T, bottom, v) with flame merlons
##   fn_brazier    tall basalt pedestal with a great fire bowl (spec v: 0 street, 1 grand)

static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"fn_tier_wall": tier_wall(kit, spec)
		&"fn_stair": stair(kit, spec)
		&"fn_gate": gate(kit, spec)
		&"gate_fort": gate_fort(kit, spec)
		&"fn_curtain": curtain(kit, spec)
		&"fn_brazier": brazier(kit, int(spec.get("v", 0)))


## A row of flame-tipped merlons on top of a wall from x0 to x1 at height y, centred at z.
static func flame_merlons(kit: BuildingKit, x0: float, x1: float, y: float, z: float, thick: float, mw: float = 1.3, gap: float = 1.0) -> void:
	var length := x1 - x0
	var n := maxi(int(floor((length + gap) / (mw + gap))), 1)
	var start := (length - (n * mw + (n - 1) * gap)) * 0.5
	for i in n:
		var cx := x0 + start + i * (mw + gap) + mw * 0.5
		kit.box(Vector3(cx, y + 0.45, z), Vector3(mw, 0.9, thick), FnStyle.BASALT_2, false)
		if kit.lod == 0:
			kit.g().cone(Vector3(cx, y + 0.9, z), Vector3(cx, y + 1.6, z), mw * 0.42, 4, kit.col(FnStyle.BASALT_2))
			kit.box(Vector3(cx, y + 0.92, z), Vector3(mw + 0.1, 0.08, thick + 0.1), FnStyle.GOLD, false)


static func tier_wall(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec["L"])
	var H := float(spec["H"])
	var P := float(spec.get("P", 2.2))
	var depth := float(spec.get("depth", 5.0))
	var bottom := float(spec.get("bottom", -1.5))
	var style: StringName = spec.get("style", &"crenel")
	var v := int(spec.get("v", 0))
	var hl := L * 0.5
	kit.box(Vector3(0, (H + bottom) * 0.5, depth * 0.5), Vector3(L + 0.06, H - bottom, depth), FnStyle.BASALT if v % 2 == 0 else FnStyle.BASALT_2)
	if kit.lod >= 2:
		if H > 4.0:
			kit.box(Vector3(0, H - 1.0, -0.06), Vector3(L, 0.9, 0.12), FnStyle.RED, false)
		return
	# plinth, red frieze with gold edges
	kit.box(Vector3(0, (bottom + 1.4) * 0.5, -0.15), Vector3(L, 1.4 - bottom, 0.3), FnStyle.BASALT_DARK, false)
	if H > 3.0:
		kit.box(Vector3(0, H - 1.1, -0.1), Vector3(L, 1.2, 0.22), FnStyle.RED, false)
		kit.box(Vector3(0, H - 0.45, -0.14), Vector3(L, 0.12, 0.28), FnStyle.GOLD, false)
		kit.box(Vector3(0, H - 1.75, -0.14), Vector3(L, 0.12, 0.28), FnStyle.GOLD, false)
	if spec.get("end", true):
		kit.box(Vector3(-hl, (H + bottom) * 0.5, -0.35), Vector3(1.4, H - bottom, 0.7), FnStyle.BASALT_DARK, false)
		if kit.lod == 0 and H > 3.0:
			FnStyle.flame_finial(kit, Vector3(-hl, H + 0.1, -0.35), 1.0)
	if kit.lod == 0 and H > 3.0:
		KitX.joints(kit, -hl + 0.7, hl, 1.4, H - 1.9, 0.0, 1.8, -1.0, FnStyle.BASALT_DARK)
		if H > 9.0 and v % 3 == 1:
			# a brazier niche in the face
			kit.box(Vector3(hl * 0.3, 2.6, -0.02), Vector3(2.2, 3.0, 0.06), &"window", false)
			kit.box(Vector3(hl * 0.3, 4.2, -0.2), Vector3(2.8, 0.3, 0.5), FnStyle.GOLD, false)
			kit.brazier(Vector3(hl * 0.3, 0.0, -0.9), {"height": 1.1, "radius": 0.55, "light": v % 6 == 1, "range": 10.0})
	match style:
		&"crenel":
			kit.box(Vector3(0, H + (P - 0.9) * 0.5, 0.4), Vector3(L, P - 0.9, 0.8), FnStyle.BASALT_2, false)
			kit.collide_box(Vector3(0, H + P * 0.5, 0.4), Vector3(L, P, 0.8))
			flame_merlons(kit, -hl, hl, H + P - 0.9, 0.4, 0.8)
		&"palace":
			# the palace enclosure: red plaster wall with a gold band under black tile coping
			kit.box(Vector3(0, H + (P - 0.4) * 0.5, 0.5), Vector3(L, P - 0.4, 1.0), FnStyle.RED)
			kit.box(Vector3(0, H + P - 0.75, 0.5), Vector3(L + 0.04, 0.3, 1.06), FnStyle.GOLD, false)
			RoofsLite.gable(kit, Vector3(0, H + P - 0.4, 0.5), L, 1.0, 0.55, FnStyle.roof_opts(FnStyle.PALACE, v, {"overhang": 0.35, "curve": 0.3,
				"horns": false, "gable_role": FnStyle.RED}))
		&"balustrade":
			kit.box(Vector3(0, H + 0.12, 0.35), Vector3(L, 0.24, 0.7), FnStyle.BASALT_DARK, false)
			kit.box(Vector3(0, H + 1.0, 0.35), Vector3(L, 0.14, 0.45), FnStyle.RED, false)
			kit.collide_box(Vector3(0, H + 0.6, 0.35), Vector3(L, 1.2, 0.6))
			var np := maxi(int(L / 2.0), 1)
			for i in np + 1:
				var x := -hl + L * float(i) / np
				kit.box(Vector3(x, H + 0.55, 0.35), Vector3(0.26, 0.9, 0.26), FnStyle.RED_DARK, false)
				if kit.lod == 0 and i % 2 == 0:
					kit.ornament(Vector3(x, H + 1.1, 0.35), &"orb", 0.22, FnStyle.GOLD)
		_:
			kit.box(Vector3(0, H + 0.5, 0.4), Vector3(L, 1.0, 0.8), FnStyle.BASALT_2, true)
	if spec.get("banner", false) and H > 6.0:
		KitX.banner(kit, Transform3D(Basis(), Vector3(-hl * 0.2, H - 0.3, -0.3)), 2.0, minf(H * 0.7, 11.0), FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire", 2)


static func stair(kit: BuildingKit, spec: Dictionary) -> void:
	var H := float(spec["H"])
	var R := float(spec["R"])
	var W := float(spec.get("W", 18.0))
	var half := float(spec.get("half", R * 0.5))
	var sw := W - 4.0
	if spec.get("steps", true):
		kit.stairs(Vector3(0, 0, 0), Vector3(0, H, -R), sw, {"role": FnStyle.PAVING, "rise": 0.19})
	# a landing beyond the top over uneven ground (spec landing: its length)
	var landing := float(spec.get("landing", 0.0))
	if landing > 0.0:
		kit.box(Vector3(0, H - 2.0, -R - landing * 0.5), Vector3(sw + 4.0, 4.0, landing), FnStyle.BASALT_2)
		if kit.lod < 2:
			kit.box(Vector3(0, H + 0.01, -R - landing * 0.5), Vector3(sw, 0.02, landing - 0.4), FnStyle.PAVING, false)
	var nseg := maxi(int(R / 6.0), 2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (sw * 0.5 + 1.0)
		for k in nseg:
			var z0 := -R * k / nseg
			var z1 := -R * (k + 1) / nseg
			var ry0 := H * k / nseg
			var ry1 := H * (k + 1) / nseg
			var outside := 0.0 if -z1 <= half else H
			var top := maxf(ry1, outside)
			kit.box(Vector3(x, (top - 1.5) * 0.5, (z0 + z1) * 0.5), Vector3(2.0, top + 1.5, absf(z1 - z0) + 0.02), FnStyle.BASALT)
			if outside < ry1 + 0.01 or -z0 < half:
				kit.beam(Vector3(x, ry0 + 0.55, z0), Vector3(x, ry1 + 0.55, z1), 1.4, 1.1, FnStyle.BASALT_2, true)
		if kit.lod < 2:
			kit.beam(Vector3(x, 1.12, 0.0), Vector3(x, H + 1.12, -R), 1.6, 0.18, FnStyle.RED)
			if kit.lod == 0:
				kit.beam(Vector3(x, 1.22, 0.0), Vector3(x, H + 1.22, -R), 1.7, 0.05, FnStyle.GOLD)
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			for zz: float in [1.6, -R - 1.6]:
				var y := 0.0 if zz > 0.0 else H
				var p := Vector3(sx * (sw * 0.5 + 1.0), y, zz)
				kit.push(Transform3D(Basis(), p))
				brazier(kit, 1 if zz > 0.0 else 0)
				kit.pop()


static func gate(kit: BuildingKit, spec: Dictionary) -> void:
	var span := float(spec.get("span", 10.0))
	var h := float(spec.get("height", 8.0))
	var pw := 1.6
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (span * 0.5 + pw * 0.5)
		kit.box(Vector3(x, h * 0.5, 0), Vector3(pw, h, pw), FnStyle.BASALT, true)
		if kit.lod < 2:
			kit.box(Vector3(x, 0.5, 0), Vector3(pw + 0.5, 1.0, pw + 0.5), FnStyle.BASALT_DARK, false)
			kit.box(Vector3(x, h * 0.62, 0), Vector3(pw + 0.12, 0.3, pw + 0.12), FnStyle.GOLD, false)
			if kit.lod == 0:
				KitX.banner(kit, Transform3D(Basis(), Vector3(x, h * 0.58, -pw * 0.5 - 0.05)), 1.1, h * 0.42, FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire")
	kit.box(Vector3(0, h + 0.6, 0), Vector3(span + pw * 2.0 + 1.0, 1.2, pw * 0.8), FnStyle.RED, true)
	if kit.lod < 2:
		kit.box(Vector3(0, h + 0.05, 0), Vector3(span + pw * 2.0 + 0.6, 0.1, pw * 0.85), FnStyle.GOLD, false)
		KitX.emblem_fire(kit, Vector3(0, h + 0.6, -pw * 0.4 - 0.02), 1.0, FnStyle.GOLD, 0.05)
	RoofsLite.hip(kit, Vector3(0, h + 1.2, 0), span + pw * 2.0 + 1.6, pw * 1.6, 1.6, FnStyle.roof_opts(FnStyle.NOBLE, 0, {"overhang": 0.9, "curve": 0.9}))
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			FnStyle.flame_finial(kit, Vector3(sx * (span * 0.5 + pw + 0.9), h + 1.6, 0), 0.9)
		FnStyle.flame_finial(kit, Vector3(0, h + 2.8, 0), 1.2)


static func gate_fort(kit: BuildingKit, spec: Dictionary) -> void:
	var W := float(spec.get("W", 14.0))
	var Wt := float(spec.get("Wt", 12.0))
	var D := float(spec.get("D", 16.0))
	var H := float(spec.get("H", 20.0))
	var Ho := float(spec.get("Ho", 12.0))
	var bottom := float(spec.get("bottom", -4.0))
	var hw := W * 0.5
	var hd := D * 0.5
	var Ht := H + 6.0
	for sx: float in [-1.0, 1.0]:
		var xa := sx * hw
		var xb := sx * (hw + Wt)
		var x0 := minf(xa, xb)
		var x1 := maxf(xa, xb)
		var cx := (x0 + x1) * 0.5
		var bat := Ht * 0.05
		KitX.prism_x(kit, x0, x1, PackedVector2Array([Vector2(-hd - bat, bottom), Vector2(hd + bat, bottom), Vector2(hd, Ht), Vector2(-hd, Ht)]), FnStyle.BASALT)
		kit.collide_box(Vector3(cx, (Ht + bottom) * 0.5, 0), Vector3(x1 - x0, Ht - bottom, D))
		if kit.lod < 2:
			kit.box(Vector3(cx, Ht - 1.0, 0), Vector3(x1 - x0 + 0.6, 1.2, D + 0.6), FnStyle.RED, false)
			kit.box(Vector3(cx, Ht - 0.35, 0), Vector3(x1 - x0 + 0.7, 0.14, D + 0.7), FnStyle.GOLD, false)
			flame_merlons(kit, x0 - 0.3, x1 + 0.3, Ht, -hd - 0.1, 0.8)
			flame_merlons(kit, x0 - 0.3, x1 + 0.3, Ht, hd + 0.1, 0.8)
			var tilt := asin(bat / (Ht - bottom))
			KitX.banner(kit, Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(cx, Ht - 2.0, -hd - 0.3 - bat * 2.0 / (Ht - bottom))), Wt * 0.5, minf(Ht * 0.6, 18.0),
					FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire", 3)
		# a black-roofed watch pavilion on each tower
		var pw := Wt - 3.0
		var pd := D - 5.0
		if kit.lod < 2:
			for px: float in [-1.0, 1.0]:
				for pz: float in [-1.0, 1.0]:
					kit.column(Vector3(cx + px * pw * 0.5, Ht, pz * pd * 0.5), 3.4, 0.3, FnStyle.RED, &"round", FnStyle.BASALT_DARK)
			kit.lantern(Vector3(cx, Ht + 2.6, 0), {"style": &"paper", "range": 12.0, "color": Color(1.0, 0.5, 0.2)})
		else:
			kit.box(Vector3(cx, Ht + 1.7, 0), Vector3(pw, 3.4, pd), FnStyle.RED_DARK, false)
		RoofsLite.hip(kit, Vector3(cx, Ht + 3.4, 0), pw, pd, 3.0, FnStyle.roof_opts(FnStyle.NOBLE, 0, {"overhang": 1.4, "curve": 0.9}))
		FnStyle.flame_finial(kit, Vector3(cx, Ht + 6.4, 0), 1.6)
	# lintel with the flame emblem, iron-studded leaves swung open
	kit.box(Vector3(0, (Ho + H) * 0.5, 0), Vector3(W + 0.2, H - Ho, D - 0.6), FnStyle.BASALT_2)
	if kit.lod < 2:
		kit.box(Vector3(0, H - 0.6, 0), Vector3(W + 0.4, 1.2, D), FnStyle.RED, false)
		flame_merlons(kit, -hw, hw, H, -hd + 0.4, 0.8)
		for sz: float in [-1.0, 1.0]:
			kit.box(Vector3(0, Ho + 0.6, sz * (hd - 0.1)), Vector3(W + 2.0, 1.2, 0.9), FnStyle.BASALT_DARK, false)
			for sx: float in [-1.0, 1.0]:
				kit.box(Vector3(sx * (hw + 0.5), Ho * 0.5, sz * (hd - 0.1)), Vector3(1.0, Ho, 0.9), FnStyle.BASALT_DARK, false)
		KitX.emblem_fire(kit, Vector3(0, (Ho + H) * 0.5 + 0.3, -hd - 0.05), minf(H - Ho - 1.5, 5.0), FnStyle.GOLD, 0.25)
		for sx: float in [-1.0, 1.0]:
			var lz := hd - 1.5 - hw * 0.5
			kit.box(Vector3(sx * (hw - 0.4), Ho * 0.48, lz), Vector3(0.6, Ho * 0.96, hw), FnStyle.STEEL_DARK, false)
			if kit.lod == 0:
				for row in 4:
					kit.box(Vector3(sx * (hw - 0.75), Ho * (0.15 + row * 0.22), lz), Vector3(0.1, 0.3, hw - 0.4), FnStyle.STEEL, false)
			kit.push(Transform3D(Basis(), Vector3(sx * (hw + 2.4), 0.0, -hd - 3.0)))
			brazier(kit, 1)
			kit.pop()


static func curtain(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec["L"])
	var H := float(spec["H"])
	var T := float(spec.get("T", 4.0))
	var bottom := float(spec.get("bottom", -3.0))
	var hl := L * 0.5
	kit.box(Vector3(0, (H + bottom) * 0.5, 0), Vector3(L + 0.08, H - bottom, T), FnStyle.BASALT if int(spec.get("v", 0)) % 2 == 0 else FnStyle.BASALT_2)
	if kit.lod >= 2:
		return
	kit.box(Vector3(0, H - 1.0, -T * 0.5 - 0.08), Vector3(L, 1.0, 0.18), FnStyle.RED, false)
	kit.box(Vector3(0, H - 1.0, T * 0.5 + 0.08), Vector3(L, 1.0, 0.18), FnStyle.RED, false)
	kit.box(Vector3(0, H + 0.6, -T * 0.5 + 0.4), Vector3(L, 1.2, 0.8), FnStyle.BASALT_2, true)
	flame_merlons(kit, -hl, hl, H + 1.2, -T * 0.5 + 0.4, 0.8)


static func brazier(kit: BuildingKit, v: int) -> void:
	var h := 1.6 if v == 0 else 2.4
	var r := 0.6 if v == 0 else 0.95
	kit.box(Vector3(0, 0.2, 0), Vector3(r * 2.4, 0.4, r * 2.4), FnStyle.BASALT_DARK, true)
	kit.cylinder(Vector3(0, 0.4, 0), h - 0.4, r * 0.45, FnStyle.BASALT, 8, true, r * 0.6)
	if kit.lod < 2:
		kit.g().cylinder(Vector3(0, h * 0.55, 0), Vector3(0, h * 0.55 + 0.12, 0), r * 0.6, r * 0.6, 8, kit.col(FnStyle.GOLD), 0)
	kit.g().cylinder(Vector3(0, h, 0), Vector3(0, h + r * 0.55, 0), r * 0.55, r, 10 if kit.lod == 0 else 6, kit.col(FnStyle.BASALT_DARK), 1)
	if kit.lod < 2:
		kit.g().cylinder(Vector3(0, h + r * 0.55, 0), Vector3(0, h + r * 0.62, 0), r + 0.06, r + 0.06, 10, kit.col(FnStyle.GOLD), 0)
	# deep orange-red flames (the glow shader's day emission otherwise washes them to cream)
	var fire := Color(0.9, 0.2, 0.03)
	var core := Color(1.0, 0.4, 0.06)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 1)
	gb.cylinder(Vector3(0, h + r * 0.5, 0), Vector3(0, h + r * 0.58, 0), r * 0.92, r * 0.92, 8, Color(0.8, 0.2, 0.03), 2)
	if kit.lod == 0:
		for k in 4:
			var a := TAU * k / 4.0 + 0.3
			var b := Vector3(cos(a) * r * 0.32, h + r * 0.56, sin(a) * r * 0.32)
			gb.cone(b, b + Vector3(0, r * (0.9 + 0.3 * (k % 2)), 0), r * 0.34, 5, fire)
		gb.cone(Vector3(0, h + r * 0.56, 0), Vector3(0, h + r * 1.9, 0), r * 0.45, 6, core)
	elif kit.lod == 1:
		gb.cone(Vector3(0, h + r * 0.56, 0), Vector3(0, h + r * 1.6, 0), r * 0.7, 5, fire)
	kit.add_light(Vector3(0, h + r * 1.4, 0), Color(1.0, 0.5, 0.18), 12.0 if v == 0 else 15.0, 2.2 if v == 0 else 2.8, 1 + v)
