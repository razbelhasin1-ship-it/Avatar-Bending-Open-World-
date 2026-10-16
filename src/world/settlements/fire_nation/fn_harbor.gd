class_name FnHarbor
extends RefCounted
## Crimson Harbor's navy and docks (BuildingKit recipes, thread-safe):
##   warship      Fire Navy ironclad (origin at the waterline amidships, bow towards -Z; spec v,
##                L): riveted dark steel hull with a ram bow and a red sheer stripe, a deck house
##                and a tall command tower with red bands, two black smokestacks, the flame emblem,
##                a deck catapult, railings
##   fn_quay      quay wall chord along the water (spec L, H water depth below the quay, D): basalt
##                face with iron mooring rings, bollards, a red kerb
##   fn_pier      stone pier along -Z (spec L, W, depth): basalt deck on piers, bollards, lamps
##   crane        iron dock crane on a basalt plinth (static jib over the water, hook block)
##   coal_pile    heaped coal with shovels and a hopper
##   fn_warehouse sooty dockside warehouse with red doors (spec v)
##   watchtower   basalt tower with a black-roofed lantern room (spec h)

static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	match kind:
		&"warship": warship(kit, spec)
		&"fn_quay": quay(kit, spec)
		&"fn_pier": pier(kit, spec)
		&"crane": crane(kit, v)
		&"coal_pile": coal_pile(kit, v)
		&"fn_warehouse": warehouse(kit, v)
		&"watchtower": watchtower(kit, spec)


## Hull half-width at z (bow at -L/2) for a ship of length L and beam B.
static func _hull_w(z: float, L: float, B: float) -> float:
	var t := (z + L * 0.5) / L            # 0 bow .. 1 stern
	if t < 0.3:
		return B * 0.5 * pow(t / 0.3, 0.6)
	if t > 0.9:
		return B * 0.5 * lerpf(1.0, 0.82, (t - 0.9) / 0.1)
	return B * 0.5


static func warship(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 56.0))
	var B := L * 0.18
	var v := int(spec.get("v", 0))
	var steel := FnStyle.STEEL if v % 2 == 0 else FnStyle.STEEL_DARK
	var deck := 3.2
	var keel := -3.6
	var n := 14 if kit.lod == 0 else (8 if kit.lod == 1 else 5)
	var g := kit.g()
	var cs := kit.col(steel)
	var cr := kit.col(FnStyle.RED)
	var cd := kit.col(FnStyle.STEEL_DARK)
	# hull: sections from bow to stern, sides flaring out above the waterline
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_lk := Vector3.ZERO
	var prev_rk := Vector3.ZERO
	for i in n + 1:
		var z := lerpf(-L * 0.5, L * 0.5, float(i) / n)
		var hw := _hull_w(z, L, B)
		var sheer := deck + (1.4 if i == 0 else 0.0) * 0.6 + 0.6 * pow(1.0 - float(i) / n, 3.0)
		var l := Vector3(-hw, sheer, z)
		var r := Vector3(hw, sheer, z)
		var lk := Vector3(-hw * 0.55, keel, z)
		var rk := Vector3(hw * 0.55, keel, z)
		if i > 0:
			# sides (upper steel, lower dark), counter-clockwise from outside
			g.flat_quad(prev_lk, lk, l, prev_l, cd)
			g.flat_quad(rk, prev_rk, prev_r, r, cd)
			g.flat_quad(prev_lk, prev_rk, rk, lk, cd)
			if kit.lod < 2:
				var band := Vector3(0, -0.9, 0)
				g.flat_quad(prev_l + band, l + band, l + Vector3(0, -0.35, 0), prev_l + Vector3(0, -0.35, 0), cr)
				g.flat_quad(r + band, prev_r + band, prev_r + Vector3(0, -0.35, 0), r + Vector3(0, -0.35, 0), cr)
			# deck
			g.flat_quad(prev_l + Vector3(0.15, -0.2, 0), l + Vector3(0.15, -0.2, 0), r + Vector3(-0.15, -0.2, 0), prev_r + Vector3(-0.15, -0.2, 0), cs)
		prev_l = l
		prev_r = r
		prev_lk = lk
		prev_rk = rk
	# stern transom
	g.flat_quad(prev_lk, prev_rk, prev_r, prev_l, cd)
	# the ram at the bow
	g.cone(Vector3(0, 0.0, -L * 0.5 + 1.0), Vector3(0, -0.2, -L * 0.5 - 3.0), 1.1, 5, cd)
	kit.collide_box(Vector3(0, (deck + keel) * 0.5, 0), Vector3(B * 0.9, deck - keel, L * 0.8))
	kit.collide_box(Vector3(0, deck - 0.3, 0), Vector3(B * 0.85, 0.4, L * 0.9))
	# superstructure: deck house, command tower, smokestacks
	var dh := Vector3(0, deck - 0.2, L * 0.08)
	kit.box(dh + Vector3(0, 1.4, 0), Vector3(B * 0.6, 2.8, L * 0.3), steel)
	var tw := Vector3(0, deck + 2.6, L * 0.02)
	kit.box(tw + Vector3(0, 3.0, 0), Vector3(B * 0.36, 6.0, B * 0.42), steel)
	kit.box(tw + Vector3(0, 6.4, 0), Vector3(B * 0.5, 0.8, B * 0.56), FnStyle.RED)
	kit.box(tw + Vector3(0, 7.2, 0), Vector3(B * 0.42, 1.0, B * 0.48), steel)
	for k in 2:
		var sp := Vector3(0, deck + 2.6, L * (0.16 + k * 0.1))
		kit.g().cylinder(sp, sp + Vector3(0, 7.0, 0), 1.1, 1.0, 10 if kit.lod == 0 else 6, kit.col(FnStyle.BLACK), 2)
		if kit.lod < 2:
			kit.g().cylinder(sp + Vector3(0, 5.6, 0), sp + Vector3(0, 6.3, 0), 1.08, 1.08, 10, cr, 0)
	if kit.lod < 2:
		# bridge windows, the flame emblem on the tower, railings, a deck catapult, anchor
		for sx: float in [-1.0, 1.0]:
			kit.box(tw + Vector3(sx * B * 0.18 + sx * 0.02, 4.6, 0), Vector3(0.06, 0.7, B * 0.3), &"window", false)
		kit.box(tw + Vector3(0, 4.6, -B * 0.21 - 0.02), Vector3(B * 0.3, 0.7, 0.06), &"window", false)
		KitX.emblem_fire(kit, tw + Vector3(0, 2.4, -B * 0.21 - 0.02), 2.0, FnStyle.RED, 0.05)
		var cat := Vector3(0, deck - 0.2, -L * 0.28)
		kit.cylinder(cat, 0.8, 1.2, FnStyle.STEEL_DARK, 8, true)
		kit.beam(cat + Vector3(0, 1.0, 1.2), cat + Vector3(0, 3.4, -2.6), 0.3, 0.3, FnStyle.STEEL_DARK)
		kit.g().cylinder(cat + Vector3(-0.5, 3.3, -2.6), cat + Vector3(0.5, 3.3, -2.6), 0.4, 0.4, 6, kit.col(FnStyle.BLACK), 3)
		if kit.lod == 0:
			for sx: float in [-1.0, 1.0]:
				var pts := PackedVector3Array()
				for i in 7:
					var z := lerpf(-L * 0.36, L * 0.44, i / 6.0)
					pts.append(Vector3(sx * (_hull_w(z, L, B) - 0.25), deck - 0.2, z))
				kit.railing(pts, 0.9, {"role": FnStyle.STEEL_DARK, "spacing": 2.4, "rails": 1, "collide": false})
				# rivet lines along the hull
				for i in 10:
					var z := lerpf(-L * 0.3, L * 0.42, i / 9.0)
					kit.box(Vector3(sx * (_hull_w(z, L, B) + 0.02), deck - 1.6, z), Vector3(0.06, 0.12, 0.12), FnStyle.STEEL_DARK, false)
			kit.g().cylinder(Vector3(B * 0.32, deck - 1.2, -L * 0.42), Vector3(B * 0.32, deck - 2.6, -L * 0.42), 0.35, 0.2, 5, kit.col(FnStyle.BLACK), 2)
			kit.flag(Transform3D(Basis(), tw + Vector3(0, 7.7, 0)), 4.0, 2.2, 1.3, {"role": FnStyle.CLOTH_RED, "alt_role": FnStyle.CLOTH_GOLD})
		kit.lantern(tw + Vector3(0, 7.9, -B * 0.25), {"style": &"wall", "light": true, "range": 14.0, "color": Color(1.0, 0.6, 0.3)})
	kit.mark(&"deck", Transform3D(Basis(), Vector3(0, deck, 0)))


static func quay(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec["L"])
	var H := float(spec.get("H", 10.0))
	var D := float(spec.get("D", 6.0))
	var hl := L * 0.5
	kit.box(Vector3(0, -H * 0.5, D * 0.5), Vector3(L + 0.06, H, D), FnStyle.BASALT)
	kit.box(Vector3(0, 0.0, D * 0.5), Vector3(L + 0.06, 0.12, D), FnStyle.PAVING_DARK, false)
	if kit.lod >= 2:
		return
	kit.box(Vector3(0, 0.15, 0.25), Vector3(L, 0.3, 0.5), FnStyle.RED_DARK, false)
	kit.box(Vector3(0, -H + 1.0, -0.12), Vector3(L, 2.0, 0.25), FnStyle.BASALT_DARK, false)
	var nb := maxi(int(L / 7.0), 1)
	for k in nb:
		var x := -hl + (k + 0.5) * L / nb
		kit.cylinder(Vector3(x, 0.0, 0.8), 0.7, 0.22, FnStyle.STEEL_DARK, 8, true, 0.18)
		if kit.lod == 0:
			var ring := PackedVector3Array()
			for j in 9:
				var a := TAU * j / 8.0
				ring.append(Vector3(x, -1.2 + sin(a) * 0.25, -0.15 + cos(a) * 0.05))
			var rr := PackedFloat32Array()
			rr.resize(ring.size())
			rr.fill(0.035)
			kit.g().tube(ring, rr, 3, kit.col(FnStyle.STEEL))
	if kit.lod == 0:
		KitX.joints(kit, -hl, hl, -H + 2.0, -0.3, 0.0, 1.4, -1.0, FnStyle.BASALT_DARK)


static func pier(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 30.0))
	var W := float(spec.get("W", 7.0))
	var dep := float(spec.get("depth", 10.0))
	kit.box(Vector3(0, -0.3, -L * 0.5), Vector3(W, 0.6, L), FnStyle.BASALT_2)
	kit.box(Vector3(0, 0.02, -L * 0.5), Vector3(W - 0.4, 0.04, L - 0.4), FnStyle.PAVING, false)
	var np := maxi(int(L / 8.0), 2)
	for i in np + 1:
		var z := -L * i / np
		kit.box(Vector3(0, (-0.6 - dep) * 0.5, z), Vector3(W - 0.6, dep - 0.6, 1.6), FnStyle.BASALT, i > 0)
	if kit.lod >= 2:
		return
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (W * 0.5 - 0.15), 0.15, -L * 0.5), Vector3(0.3, 0.3, L), FnStyle.RED_DARK, false)
		for k in maxi(int(L / 8.0), 1):
			kit.cylinder(Vector3(sx * (W * 0.5 - 0.6), 0.0, -4.0 - k * 8.0), 0.7, 0.2, FnStyle.STEEL_DARK, 8, true, 0.16)
	kit.push(Transform3D(Basis(), Vector3(W * 0.5 - 0.6, 0.0, -L + 0.6)))
	FnCivic.lamp(kit, 0, true)
	kit.pop()


static func crane(kit: BuildingKit, v: int) -> void:
	kit.box(Vector3(0, 0.6, 0), Vector3(4.0, 1.2, 4.0), FnStyle.BASALT_DARK)
	var steel := FnStyle.STEEL_DARK
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.beam(Vector3(sx * 1.4, 1.2, sz * 1.4), Vector3(sx * 0.5, 11.0, sz * 0.5), 0.3, 0.3, steel, true)
	if kit.lod < 2:
		for k in 4:
			var y := 3.0 + k * 2.0
			var s := lerpf(1.3, 0.6, (y - 1.2) / 9.8)
			for sx: float in [-1.0, 1.0]:
				kit.beam(Vector3(sx * s, y, -s), Vector3(sx * s, y, s), 0.14, 0.14, steel)
				kit.beam(Vector3(-s, y, sx * s), Vector3(s, y, sx * s), 0.14, 0.14, steel)
	kit.box(Vector3(0, 11.4, 0), Vector3(2.6, 1.6, 2.6), FnStyle.RED)
	kit.beam(Vector3(0, 12.2, 3.0), Vector3(0, 13.5, -14.0), 0.6, 0.6, steel)
	kit.beam(Vector3(0, 12.6, 3.0), Vector3(0, 11.4, 4.6), 0.4, 0.4, steel)
	kit.box(Vector3(0, 11.0, 4.8), Vector3(1.6, 1.6, 1.6), FnStyle.BASALT_DARK, false)
	if kit.lod < 2:
		kit.beam(Vector3(0, 13.4, -13.5), Vector3(0, 6.0 + (v % 3) * 1.5, -13.5), 0.05, 0.05, FnStyle.BLACK)
		kit.box(Vector3(0, 5.6 + (v % 3) * 1.5, -13.5), Vector3(0.6, 0.8, 0.6), FnStyle.STEEL, false)
		if kit.lod == 0 and v % 2 == 0:
			kit.box(Vector3(0, 4.0 + (v % 3) * 1.5, -13.5), Vector3(1.6, 1.6, 1.6), &"wood", false)


static func coal_pile(kit: BuildingKit, v: int) -> void:
	var coal := Color(0.06, 0.06, 0.07).srgb_to_linear()
	kit.g().blob(Vector3(0, 0.4, 0), 2.6 + (v % 2) * 0.6, 1 if kit.lod == 0 else 0, kit.col(coal), kit.rng, 0.25, Vector3(1.4, 0.55, 1.0))
	kit.collide_box(Vector3(0, 0.7, 0), Vector3(6.0, 1.4, 4.4))
	if kit.lod == 0:
		kit.box(Vector3(3.6, 0.5, 1.6), Vector3(1.4, 1.0, 1.4), &"wood_dark", true)
		kit.beam(Vector3(-2.6, 0, 1.8), Vector3(-2.2, 1.4, 2.4), 0.05, 0.05, &"wood")


static func warehouse(kit: BuildingKit, v: int) -> void:
	var w := 18.0 + (v % 2) * 4.0
	var d := 11.0
	var sooty := FnStyle.wall(FnStyle.HARBOR, v)
	kit.box(Vector3(0, 0.3, 0), Vector3(w + 0.4, 0.6, d + 0.4), FnStyle.BASALT_DARK)
	kit.box(Vector3(0, 0.6 + 3.0, 0), Vector3(w, 6.0, d), sooty)
	RoofsLite.gable(kit, Vector3(0, 6.6, 0), w, d, 3.0, FnStyle.roof_opts(FnStyle.HARBOR, v, {"overhang": 0.8, "gable_role": sooty}))
	if kit.lod >= 2:
		return
	FnHomes.posts(kit, -w * 0.5, w * 0.5, 0.6, 6.0, -d * 0.5, 3, FnStyle.RED_DARK)
	for k in 2:
		var x := (k - 0.5) * w * 0.45
		kit.box(Vector3(x, 0.6 + 2.0, -d * 0.5 - 0.03), Vector3(3.6, 4.0, 0.06), &"window", false)
		kit.box_t(Transform3D(Basis(Vector3.UP, 1.2), Vector3(x - 1.8, 0.6 + 2.0, -d * 0.5 - 0.9)), Vector3(1.8, 4.0, 0.12), FnStyle.RED, false)
	if kit.lod == 0:
		KitX.emblem_fire(kit, Vector3(0, 5.3, -d * 0.5 - 0.04), 1.4, FnStyle.RED, 0.04)
		kit.push(Transform3D(Basis(), Vector3(w * 0.36, 0, -d * 0.5 - 2.0)))
		EkProps.crates(kit, v % 3)
		kit.pop()


static func watchtower(kit: BuildingKit, spec: Dictionary) -> void:
	var h := float(spec.get("h", 16.0))
	kit.box(Vector3(0, 0.5, 0), Vector3(6.0, 1.0, 6.0), FnStyle.BASALT_DARK)
	kit.box(Vector3(0, 1.0 + h * 0.5, 0), Vector3(4.4, h, 4.4), FnStyle.BASALT)
	if kit.lod < 2:
		kit.box(Vector3(0, 1.0 + h - 0.6, 0), Vector3(4.8, 0.8, 4.8), FnStyle.RED, false)
		EkHomes.door(kit, Vector3(0, 1.0, -2.22), 1.1, 2.1, FnStyle.RED_DARK, FnStyle.RED)
		KitX.window(kit, Vector3(0, 1.0 + h * 0.6, -2.22), 0.6, 1.2, FnStyle.GOLD, 0.04, false)
	var top := 1.0 + h
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.column(Vector3(sx * 1.8, top, sz * 1.8), 2.6, 0.18, FnStyle.RED, &"round", FnStyle.BASALT_DARK)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 0.6)
	gb.box(Transform3D(Basis(), Vector3(0, top + 1.2, 0)), Vector3(1.4, 1.4, 1.4), Color(1.0, 0.55, 0.2))
	kit.add_light(Vector3(0, top + 1.3, 0), Color(1.0, 0.55, 0.25), 22.0, 2.4, 3)
	RoofsLite.hip(kit, Vector3(0, top + 2.6, 0), 3.8, 3.8, 2.6, FnStyle.roof_opts(FnStyle.NOBLE, 0, {"overhang": 1.0, "curve": 0.9, "ridge": 0.2}))
	FnStyle.flame_finial(kit, Vector3(0, top + 5.2, 0), 1.2)
