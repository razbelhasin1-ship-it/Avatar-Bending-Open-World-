class_name EkVillages
extends RefCounted
## Earth Kingdom village and harbour structures (BuildingKit recipes, thread-safe; origin on the
## ground / deck, -Z front or seaward):
##   ek_pier        wooden pier along -Z (spec L, W, depth to the sea floor, head), piles, bollards,
##                  a lantern post at the end, rope rail
##   harbor_quay    the quay platform under a terrace edge: origin at the terrace top edge, the
##                  deck H - 2 m lower towards -Z (spec L along x, D, H, bottom), masonry face,
##                  a stair from the deck up to the terrace, bollards, cargo, lanterns
##   boathouse      timber shed on piles with a gable roof and an open water bay
##   fish_rack      drying racks heavy with fish
##   warehouse      long timber-and-plaster store with big doors (spec v)
##   lighthouse     stone watchtower with a lantern room (spec h)
##   shrine         roadside shrine (BuildingPresets.shrine, Earth Kingdom style)
##   lumber_pile    stacked cedar logs; sawmill: open shed with a saw frame and logs
## pier() is also the Ba Sing Se lake pier (lake_pier).

const KINDS: Array[StringName] = [&"ek_pier", &"harbor_quay", &"boathouse", &"fish_rack", &"warehouse", &"lighthouse", &"shrine",
	&"lumber_pile", &"sawmill"]


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	match kind:
		&"ek_pier": pier(kit, spec)
		&"harbor_quay": harbor_quay(kit, spec)
		&"boathouse": boathouse(kit, v)
		&"fish_rack": fish_rack(kit, v)
		&"warehouse": warehouse(kit, v)
		&"lighthouse": lighthouse(kit, spec)
		&"shrine": BuildingPresets.shrine(kit, Transform3D(), {"size": 1.0})
		&"lumber_pile": lumber_pile(kit, v)
		&"sawmill": sawmill(kit, v)


static func pier(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 20.0))
	var W := float(spec.get("W", 3.0))
	var dep := float(spec.get("depth", 6.0))
	var head := float(spec.get("head", 0.0))
	var wood := EkStyle.timber(EkStyle.FARM)
	var dark := EkStyle.timber(EkStyle.LOWER)
	if kit.lod == 0:
		var planks := int(L / 0.5)
		for i in planks:
			var z := -L * (i + 0.5) / planks
			kit.box(Vector3(0, -0.07, z), Vector3(W + kit.rng.randf_range(-0.08, 0.08), 0.14, 0.45), wood if i % 5 else dark, false)
	else:
		kit.box(Vector3(0, -0.07, -L * 0.5), Vector3(W, 0.14, L), wood, false)
	kit.collide_box(Vector3(0, -0.2, -L * 0.5), Vector3(W, 0.4, L))
	kit.box(Vector3(0, -0.35, -L * 0.5), Vector3(W - 0.3, 0.4, L), dark, false)
	var np := maxi(int(L / 4.0), 2)
	for i in np + 1:
		var z := -L * i / np
		for sx: float in [-1.0, 1.0]:
			kit.cylinder(Vector3(sx * (W * 0.5 - 0.15), -dep, z), dep - 0.2, 0.18, dark, 6, i > 0, 0.16)
			if kit.lod == 0 and i > 0 and i % 2 == 0:
				kit.cylinder(Vector3(sx * (W * 0.5 + 0.05), 0.0, z), 0.7, 0.1, dark, 6, true)
	if head > 0.0:
		var hz := -L - 1.8
		kit.box(Vector3(0, -0.08, hz), Vector3(head, 0.16, 3.6), wood, true)
		for sx: float in [-1.0, 1.0]:
			kit.cylinder(Vector3(sx * (head * 0.5 - 0.2), -dep, hz), dep + 0.8, 0.2, dark, 6, true, 0.18)
	if kit.lod < 2:
		kit.push(Transform3D(Basis(), Vector3(W * 0.5 - 0.3, 0.0, -L + 0.5)))
		EkProps.lamp_post(kit, 0, true)
		kit.pop()
		if kit.lod == 0:
			kit.railing(PackedVector3Array([Vector3(-W * 0.5 + 0.08, 0, -1.0), Vector3(-W * 0.5 + 0.08, 0, -L * 0.6)]), 0.9, {"role": dark, "spacing": 2.0})


static func harbor_quay(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 36.0))
	var D := float(spec.get("D", 10.0))
	var H := float(spec.get("H", 14.0))
	var bottom := float(spec.get("bottom", -24.0))
	var hl := L * 0.5
	var deck := -H + 2.0
	var s1 := EkStyle.stone(2, 0)
	var s2 := EkStyle.stone(2, 1)
	var sd := EkStyle.stone(2, 2)
	# deck platform on a masonry base down to the sea floor
	kit.box(Vector3(0, (deck + bottom) * 0.5, -D * 0.5), Vector3(L, deck - bottom, D), s2)
	kit.box(Vector3(0, deck + 0.05, -D * 0.5), Vector3(L - 0.2, 0.1, D - 0.2), s1, false)
	# masonry face under the terrace edge (covers the cut terrain)
	kit.box(Vector3(0, (deck + 0.0) * 0.5, 1.5), Vector3(L + 0.4, -deck, 3.0), s1)
	kit.box(Vector3(0, 0.5, 0.5), Vector3(L + 0.4, 1.0, 0.8), s2, true)
	# stair from the deck up to the terrace along the face (at +x)
	var run := (-deck) / 0.58
	kit.stairs(Vector3(hl - 1.0 - run, deck, -2.2), Vector3(hl - 1.0, 0.0, -2.2), 3.2, {"role": s1, "rise": 0.2})
	kit.box(Vector3(hl - 1.0 - run * 0.5, deck * 0.5, -3.95), Vector3(run, -deck, 0.3), s2, false)
	kit.beam(Vector3(hl - 1.0 - run, deck + 0.5, -3.95), Vector3(hl - 1.0, 0.5, -3.95), 0.35, 1.0, s2, true)
	kit.box(Vector3(hl - 1.0 + 1.6, -0.25, -2.2), Vector3(3.2, 0.5, 3.4), s1, true)
	if kit.lod >= 2:
		return
	kit.box(Vector3(0, deck + 0.25, -D + 0.2), Vector3(L, 0.5, 0.4), sd, false)
	for k in maxi(int(L / 7.0), 1):
		var x := -hl + (k + 0.5) * L / maxi(int(L / 7.0), 1)
		kit.cylinder(Vector3(x, deck, -D + 0.7), 0.7, 0.22, sd, 8, true, 0.18)
		if kit.lod == 0 and k % 2 == 0:
			kit.push(Transform3D(Basis(Vector3.UP, x), Vector3(x + 1.5, deck, -D * 0.45)))
			EkProps.crates(kit, k % 3)
			kit.pop()
	for k in 3:
		KitX.lantern(kit, Vector3(lerpf(-hl + 3.0, hl - 8.0, k / 2.0), deck, -1.0), {"style": &"post", "height": 2.6, "light": k == 1, "range": 11.0})


static func boathouse(kit: BuildingKit, v: int) -> void:
	var wood := EkStyle.timber(EkStyle.FARM)
	var w := 7.0
	var d := 10.0
	for sx: float in [-1.0, 1.0]:
		for k in 4:
			kit.cylinder(Vector3(sx * w * 0.5, -5.0, -d * 0.5 + k * d / 3.0), 5.0, 0.18, &"wood_dark", 6, false)
	kit.box(Vector3(-w * 0.5 + 0.8, 1.6, 0), Vector3(1.6, 3.2, d), EkStyle.wall(EkStyle.FARM, v))
	kit.box(Vector3(0, 1.6, d * 0.5 - 0.2), Vector3(w, 3.2, 0.4), EkStyle.wall(EkStyle.FARM, v))
	kit.box(Vector3(-w * 0.5 + 0.8, -0.1, 0), Vector3(1.6, 0.2, d), wood, true)
	RoofsLite.gable(kit, Vector3(0, 3.2, 0), w, d, 2.0, EkStyle.roof_opts(EkStyle.FARM, v, {"overhang": 0.6}))
	if kit.lod == 0:
		for sx: float in [-1.0, 1.0]:
			kit.beam(Vector3(sx * w * 0.5, 0, -d * 0.5), Vector3(sx * w * 0.5, 3.2, -d * 0.5), 0.2, 0.2, wood)


static func fish_rack(kit: BuildingKit, v: int) -> void:
	var wood := EkStyle.timber(EkStyle.FARM)
	for sx: float in [-1.0, 1.0]:
		kit.beam(Vector3(sx * 2.0, 0, 0), Vector3(sx * 2.0, 2.2, 0), 0.12, 0.12, wood, true)
	kit.beam(Vector3(-2.1, 2.1, 0), Vector3(2.1, 2.1, 0), 0.08, 0.08, wood)
	kit.beam(Vector3(-2.1, 1.4, 0), Vector3(2.1, 1.4, 0), 0.06, 0.06, wood)
	if kit.lod > 0:
		return
	var fish := Color(0.62, 0.64, 0.66).srgb_to_linear()
	for row: float in [2.05, 1.35]:
		for k in 9:
			var x := -1.8 + k * 0.45
			kit.g().cone(Vector3(x, row - 0.05, 0), Vector3(x, row - 0.55 - (k + v) % 2 * 0.1, 0), 0.08, 4, kit.col(fish))


static func warehouse(kit: BuildingKit, v: int) -> void:
	var w := 14.0 + (v % 2) * 3.0
	var d := 9.0
	var tim := EkStyle.timber(EkStyle.LOWER)
	kit.box(Vector3(0, 0.25, 0), Vector3(w + 0.3, 0.5, d + 0.3), EkStyle.base(EkStyle.LOWER))
	kit.box(Vector3(0, 0.5 + 2.4, 0), Vector3(w, 4.8, d), EkStyle.wall(EkStyle.LOWER, v + 1))
	RoofsLite.gable(kit, Vector3(0, 5.3, 0), w, d, 2.6, EkStyle.roof_opts(EkStyle.LOWER, v, {"overhang": 0.8, "gable_role": EkStyle.wall(EkStyle.LOWER, v + 1)}))
	if kit.lod >= 2:
		return
	EkHomes.frame_face(kit, -w * 0.5, w * 0.5, 0.5, 4.8, -d * 0.5, 1, tim)
	for k in 2:
		var x := (k - 0.5) * w * 0.45
		kit.box(Vector3(x, 0.5 + 1.7, -d * 0.5 - 0.03), Vector3(3.0, 3.4, 0.06), &"window", false)
		if kit.lod == 0:
			kit.box_t(Transform3D(Basis(Vector3.UP, 0.9), Vector3(x - 1.5, 0.5 + 1.7, -d * 0.5 - 0.7)), Vector3(1.5, 3.4, 0.1), &"door", false)
	if kit.lod == 0:
		kit.push(Transform3D(Basis(), Vector3(w * 0.3, 0, -d * 0.5 - 1.6)))
		EkProps.crates(kit, v % 3)
		kit.pop()
		kit.box(Vector3(0, 4.9, -d * 0.5 - 0.1), Vector3(3.0, 0.6, 0.08), EkStyle.AWNINGS[v % 5], false)


static func lighthouse(kit: BuildingKit, spec: Dictionary) -> void:
	var h := float(spec.get("h", 14.0))
	var s1 := EkStyle.stone(2, 0)
	var s2 := EkStyle.stone(2, 1)
	kit.box(Vector3(0, 0.6, 0), Vector3(6.4, 1.2, 6.4), s2)
	kit.cylinder(Vector3(0, 1.2, 0), h, 2.6, s1, 10, true, 2.0)
	if kit.lod < 2:
		for k in 3:
			kit.g().cylinder(Vector3(0, 1.2 + h * (k + 1) / 4.0, 0), Vector3(0, 1.4 + h * (k + 1) / 4.0, 0), 2.6 - 0.6 * (k + 1) / 4.0 + 0.08,
					2.6 - 0.6 * (k + 1) / 4.0 + 0.08, 10, kit.col(s2), 0)
		EkHomes.door(kit, Vector3(0, 1.2, -2.55), 1.1, 2.1, EkStyle.timber(EkStyle.LOWER))
	var top := 1.2 + h
	kit.cylinder(Vector3(0, top, 0), 0.4, 2.8, s2, 10, true)
	for k in 6:
		var a := TAU * k / 6.0
		kit.beam(Vector3(cos(a) * 1.6, top + 0.4, sin(a) * 1.6), Vector3(cos(a) * 1.6, top + 2.6, sin(a) * 1.6), 0.18, 0.18, EkStyle.timber(EkStyle.LOWER))
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 0.6)
	gb.cylinder(Vector3(0, top + 0.6, 0), Vector3(0, top + 2.2, 0), 1.0, 1.0, 8, Color(1.0, 0.78, 0.45), 3)
	kit.add_light(Vector3(0, top + 1.4, 0), Color(1.0, 0.8, 0.5), 24.0, 2.6, 3)
	KitRoofs.cone(kit, Vector3(0, top + 2.6, 0), 2.4, 2.0, {"sides": 10, "role": EkStyle.roof(EkStyle.MIDDLE, 0), "trim_role": EkStyle.COPING, "finial": true,
		"finial_role": EkStyle.GOLD})
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, top + 4.6, 0)))


static func lumber_pile(kit: BuildingKit, v: int) -> void:
	var bark := Color(0.40, 0.28, 0.18).srgb_to_linear()
	var cut := Color(0.78, 0.62, 0.42).srgb_to_linear()
	var rows := 3 + v % 2
	for r in rows:
		var n := rows - r + 1
		for k in n:
			var x := (k - (n - 1) * 0.5) * 0.62
			var y := 0.3 + r * 0.54
			kit.g().cylinder(Vector3(x, y, -2.2), Vector3(x, y, 2.2), 0.3, 0.3, 7 if kit.lod == 0 else 5, kit.col(bark), 0, true, Color(-1, 0, 0))
			if kit.lod == 0:
				for sz: float in [-1.0, 1.0]:
					kit.g().cylinder(Vector3(x, y, sz * 2.2), Vector3(x, y, sz * 2.21), 0.29, 0.29, 7, kit.col(cut), 2)
	kit.collide_box(Vector3(0, rows * 0.27 + 0.3, 0), Vector3((rows + 1) * 0.62, rows * 0.54 + 0.3, 4.4))
	for sx: float in [-1.0, 1.0]:
		kit.beam(Vector3(sx * (rows + 1) * 0.36, 0, 0), Vector3(sx * (rows + 1) * 0.36, rows * 0.6, 0), 0.12, 0.12, &"wood_dark")


static func sawmill(kit: BuildingKit, v: int) -> void:
	var wood := EkStyle.timber(EkStyle.FARM)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.beam(Vector3(sx * 4.0, 0, sz * 3.0), Vector3(sx * 4.0, 3.4, sz * 3.0), 0.22, 0.22, wood, true)
	RoofsLite.gable(kit, Vector3(0, 3.4, 0), 8.0, 6.0, 2.0, EkStyle.roof_opts(EkStyle.FARM, v, {"overhang": 0.6}))
	kit.box(Vector3(0, 0.45, 0), Vector3(5.0, 0.9, 1.2), wood, true)
	if kit.lod < 2:
		kit.g().cylinder(Vector3(-2.4, 1.15, 0), Vector3(2.4, 1.15, 0), 0.3, 0.3, 7, kit.col(Color(0.40, 0.28, 0.18).srgb_to_linear()), 3)
		kit.beam(Vector3(0, 0.9, 0), Vector3(0, 2.8, 0), 0.1, 0.1, &"wood_dark")
		kit.box(Vector3(0, 1.8, 0), Vector3(0.04, 1.4, 1.0), Color(0.72, 0.74, 0.76).srgb_to_linear(), false)
		kit.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(6.4, 0, 0)))
		lumber_pile(kit, v)
		kit.pop()


static func extras(_piece: Dictionary) -> Array:
	return []


static func glows(piece: Dictionary) -> Array:
	var out: Array = []
	var spec: Dictionary = piece["spec"]
	match piece["kind"]:
		&"lighthouse":
			out.append([SettlementBuilder.at(piece, Vector3(0, float(spec.get("h", 14.0)) + 2.6, 0)), SettlementFx.GLOW_LAMP, 2.6])
		&"ek_pier":
			out.append([SettlementBuilder.at(piece, Vector3(float(spec.get("W", 3.0)) * 0.5 - 0.3 + 0.72, 2.75, -float(spec.get("L", 20.0)) + 0.5)),
				SettlementFx.GLOW_LAMP, 0.9])
		&"harbor_quay":
			var hl := float(spec.get("L", 36.0)) * 0.5
			out.append([SettlementBuilder.at(piece, Vector3(lerpf(-hl + 3.0, hl - 8.0, 0.5), -float(spec.get("H", 14.0)) + 2.0 + 2.2, -1.0)), SettlementFx.GLOW_LAMP, 1.0])
	return out
