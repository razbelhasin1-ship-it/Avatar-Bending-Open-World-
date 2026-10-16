class_name EkProps
extends RefCounted
## Earth Kingdom street furniture (BuildingKit recipes, thread-safe, archetypes by variant):
##   lamp_post    lacquered post with a hanging paper lantern (v 0) or a stone lantern (v 1);
##                spec.light: a budgeted light (otherwise a night glow only)
##   stall        market stall: counter, goods by trade, cloth awning on poles
##   crates       stacked crates / sacks / barrels
##   cart         two-wheeled hand cart
##   bench        stone or wooden bench
##   well         stone well with a windlass roof
##   banner_pole  tall pole with a green-gold Earth Kingdom banner
##   statue       a badgermole (v 0) or an earthbender master (v 1) on a plinth
##   planter      raised stone planter with a shrub
##   haystack     cone of straw on a frame
##   scarecrow    straw figure on a cross
##   noticeboard  roofed board with posters

const GOODS := ["vegetables", "pottery", "cloth", "tea", "cabbages", "tools"]


static func build(kit: BuildingKit, kind: StringName, v: int, spec: Dictionary) -> void:
	match kind:
		&"lamp_post": lamp_post(kit, v, bool(spec.get("light", false)))
		&"stall": stall(kit, v)
		&"crates": crates(kit, v)
		&"cart": cart(kit, Vector3.ZERO, 0.0)
		&"bench": bench(kit, v)
		&"well": well(kit)
		&"banner_pole": banner_pole(kit, v)
		&"statue": statue(kit, v)
		&"planter": planter(kit, v)
		&"haystack": haystack(kit, v)
		&"scarecrow": scarecrow(kit, v)
		&"noticeboard": noticeboard(kit)


static func lamp_post(kit: BuildingKit, v: int, light: bool) -> void:
	if v % 2 == 1:
		KitX.lantern(kit, Vector3.ZERO, {"style": &"stone", "height": 1.8, "light": light, "range": 10.0, "role": EkStyle.base(EkStyle.MIDDLE)})
		return
	var post := EkStyle.LACQUER if v % 4 == 0 else EkStyle.timber(EkStyle.LOWER)
	kit.box(Vector3(0, 0.12, 0), Vector3(0.6, 0.24, 0.6), EkStyle.base(EkStyle.MIDDLE), false)
	kit.cylinder(Vector3(0, 0.2, 0), 3.4, 0.09, post, 6, true, 0.07)
	if kit.lod < 2:
		kit.beam(Vector3(0, 3.35, 0), Vector3(0.75, 3.35, 0), 0.09, 0.12, post)
		kit.box(Vector3(0, 3.6, 0), Vector3(0.24, 0.12, 0.24), EkStyle.COPING, false)
	var col := Color(1.0, 0.66, 0.32)
	KitX.lantern(kit, Vector3(0.72, 2.75, 0), {"style": &"paper", "light": light, "range": 10.0, "energy": 1.6, "color": col})


static func stall(kit: BuildingKit, v: int) -> void:
	var w := 3.0
	var d := 1.8
	var tim := EkStyle.timber(EkStyle.LOWER)
	kit.box(Vector3(0, 0.45, 0), Vector3(w, 0.9, d * 0.55), tim, true)
	if kit.lod < 2:
		kit.box(Vector3(0, 0.92, 0), Vector3(w + 0.1, 0.06, d * 0.6), EkStyle.timber(EkStyle.FARM), false)
		EkHomes.goods(kit, Vector3(0, 0.95, 0), w - 0.4, v)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * (w * 0.5 - 0.05), 0, sz * (d * 0.5 - 0.05))
			kit.beam(p, p + Vector3(0, 2.3 + (0.25 if sz > 0.0 else 0.0), 0), 0.08, 0.08, tim)
	var aw: Color = EkStyle.AWNINGS[v % EkStyle.AWNINGS.size()]
	if kit.lod < 2:
		EkHomes.awning(kit, Vector3(0, 2.55, d * 0.5), w + 0.5, d + 0.6, 0.45, aw)
	else:
		kit.box(Vector3(0, 2.35, 0), Vector3(w + 0.4, 0.1, d + 0.4), aw, false)
	if kit.lod == 0:
		# baskets on the ground, a sign
		for k in 2:
			kit.g().cylinder(Vector3(-w * 0.3 + k * 0.6, 0, -d * 0.55), Vector3(-w * 0.3 + k * 0.6, 0.35, -d * 0.55), 0.24, 0.28, 7, kit.col(EkStyle.STRAW), 2)
		kit.box(Vector3(w * 0.5 + 0.1, 1.7, -d * 0.5), Vector3(0.06, 0.9, 0.5), EkStyle.AWNINGS[(v + 2) % 5], false)


static func crates(kit: BuildingKit, v: int) -> void:
	var wood := kit.col(&"wood")
	var n := 2 + v % 3
	for i in n:
		var s := 0.7 + (i % 2) * 0.15
		var p := Vector3((i % 2) * 0.85 - 0.4, (i / 2) * s + s * 0.5, (i % 3) * 0.12)
		kit.box(p, Vector3(s, s, s), wood * (0.9 + 0.08 * i), i < 2)
		if kit.lod == 0:
			kit.box(p + Vector3(0, 0, -s * 0.5 - 0.01), Vector3(s * 0.9, 0.08, 0.02), &"wood_dark", false)
	if kit.lod == 0:
		kit.g().cylinder(Vector3(1.1, 0, 0.3), Vector3(1.1, 0.9, 0.3), 0.36, 0.36, 8, kit.col(&"wood_dark"), 2)
		kit.g().blob(Vector3(-1.2, 0.3, 0.2), 0.36, 0, kit.col(EkStyle.STRAW), null, 0.0, Vector3(1.0, 0.8, 0.9))
		kit.collide_box(Vector3(1.1, 0.45, 0.3), Vector3(0.7, 0.9, 0.7))


## Hand cart at local p, yawed (thread-safe; used by farmsteads too).
static func cart(kit: BuildingKit, p: Vector3, yaw: float) -> void:
	kit.push(Transform3D(Basis(Vector3.UP, yaw), p))
	var wood := EkStyle.timber(EkStyle.FARM)
	kit.box(Vector3(0, 0.85, 0), Vector3(1.4, 0.12, 2.2), wood, true)
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			kit.box(Vector3(sx * 0.68, 1.1, 0), Vector3(0.08, 0.4, 2.2), wood, false)
			kit.g().cylinder(Vector3(sx * 0.82, 0.55, 0.2), Vector3(sx * 0.95, 0.55, 0.2), 0.55, 0.55, 10, kit.col(&"wood_dark"), 3)
		kit.beam(Vector3(-0.4, 0.8, -1.1), Vector3(-0.4, 0.4, -2.6), 0.08, 0.08, wood)
		kit.beam(Vector3(0.4, 0.8, -1.1), Vector3(0.4, 0.4, -2.6), 0.08, 0.08, wood)
		if kit.lod == 0:
			kit.g().blob(Vector3(0, 1.15, 0.2), 0.5, 0, kit.col(Color(0.86, 0.80, 0.52).srgb_to_linear()), null, 0.0, Vector3(1.1, 0.6, 1.6))
	kit.pop()


static func bench(kit: BuildingKit, v: int) -> void:
	if v % 2 == 0:
		kit.box(Vector3(0, 0.42, 0), Vector3(2.0, 0.14, 0.55), EkStyle.base(EkStyle.MIDDLE), true)
		for sx: float in [-0.75, 0.75]:
			kit.box(Vector3(sx, 0.2, 0), Vector3(0.3, 0.4, 0.5), EkStyle.base(EkStyle.MIDDLE), false)
	else:
		var tim := EkStyle.timber(EkStyle.MIDDLE)
		kit.box(Vector3(0, 0.44, 0), Vector3(1.9, 0.08, 0.5), tim, true)
		kit.box(Vector3(0, 0.8, 0.22), Vector3(1.9, 0.5, 0.06), tim, false)
		for sx: float in [-0.8, 0.8]:
			kit.box(Vector3(sx, 0.22, 0), Vector3(0.08, 0.44, 0.45), tim, false)


static func well(kit: BuildingKit) -> void:
	kit.cylinder(Vector3.ZERO, 0.85, 0.95, EkStyle.base(EkStyle.LOWER), 10, true)
	if kit.lod < 2:
		kit.g().cylinder(Vector3(0, 0.84, 0), Vector3(0, 0.86, 0), 0.75, 0.75, 10, kit.col(Color(0.06, 0.08, 0.1)), 2)
		var tim := EkStyle.timber(EkStyle.LOWER)
		for sx: float in [-1.0, 1.0]:
			kit.beam(Vector3(sx * 0.9, 0.85, 0), Vector3(sx * 0.9, 2.3, 0), 0.1, 0.1, tim)
		kit.beam(Vector3(-1.0, 1.7, 0), Vector3(1.0, 1.7, 0), 0.12, 0.12, tim)
		RoofsLite.gable(kit, Vector3(0, 2.3, 0), 2.0, 1.4, 0.7, EkStyle.roof_opts(EkStyle.LOWER, 1, {"overhang": 0.3, "collide": false}))
		if kit.lod == 0:
			kit.g().cylinder(Vector3(0.3, 1.2, 0), Vector3(0.3, 1.55, 0), 0.18, 0.2, 6, kit.col(&"wood"), 2)


static func banner_pole(kit: BuildingKit, v: int) -> void:
	var h := 7.0 + (v % 3)
	kit.box(Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.9), EkStyle.base(EkStyle.MIDDLE), true)
	kit.cylinder(Vector3(0, 0.6, 0), h, 0.1, EkStyle.LACQUER, 6, true, 0.08)
	if kit.lod < 2:
		kit.beam(Vector3(-0.8, h + 0.3, 0), Vector3(0.8, h + 0.3, 0), 0.1, 0.1, EkStyle.LACQUER)
		kit.ornament(Vector3(0, h + 0.55, 0), &"finial", 0.6, EkStyle.GOLD)
		KitX.banner(kit, Transform3D(Basis(), Vector3(0, h + 0.25, -0.12)), 1.3, h * 0.55, EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth")


static func statue(kit: BuildingKit, v: int) -> void:
	var stone := EkStyle.base(EkStyle.UPPER)
	kit.box(Vector3(0, 0.6, 0), Vector3(3.2, 1.2, 3.2), EkStyle.base(EkStyle.MIDDLE), true)
	kit.box(Vector3(0, 1.3, 0), Vector3(2.6, 0.2, 2.6), EkStyle.COPING, false)
	var g := kit.g()
	var c := kit.col(stone)
	if v % 2 == 0:
		# badgermole: low heavy body, big digging claws, small head
		g.blob(Vector3(0, 2.4, 0.2), 1.1, 1 if kit.lod == 0 else 0, c, null, 0.0, Vector3(1.0, 0.75, 1.35))
		g.blob(Vector3(0, 2.6, -1.1), 0.6, 0, c, null, 0.0, Vector3(1.0, 0.8, 1.1))
		if kit.lod < 2:
			for sx: float in [-1.0, 1.0]:
				g.blob(Vector3(sx * 0.9, 1.75, -0.8), 0.38, 0, c, null, 0.0, Vector3(0.8, 0.6, 1.2))
				for k in 3:
					g.cone(Vector3(sx * (0.75 + k * 0.14), 1.6, -1.15), Vector3(sx * (0.75 + k * 0.14), 1.45, -1.55), 0.07, 4, c)
	else:
		# earthbender master in a horse stance, fists forward
		g.cylinder(Vector3(0, 1.4, 0), Vector3(0, 3.6, 0), 0.55, 0.5, 8, c, 2)
		g.blob(Vector3(0, 4.1, 0), 0.38, 0, c)
		if kit.lod < 2:
			for sx: float in [-1.0, 1.0]:
				g.cylinder(Vector3(sx * 0.4, 3.3, 0), Vector3(sx * 0.35, 3.1, -0.9), 0.17, 0.15, 6, c, 2)
				g.blob(Vector3(sx * 0.35, 3.1, -1.0), 0.2, 0, c)
				g.cylinder(Vector3(sx * 0.3, 1.4, 0), Vector3(sx * 0.9, 1.4, -0.3), 0.22, 0.2, 6, c, 0)
	kit.collide_box(Vector3(0, 2.6, 0), Vector3(2.4, 2.8, 2.4))


static func planter(kit: BuildingKit, v: int) -> void:
	kit.box(Vector3(0, 0.35, 0), Vector3(1.8, 0.7, 1.8), EkStyle.base(EkStyle.MIDDLE), true)
	if kit.lod < 2:
		kit.box(Vector3(0, 0.71, 0), Vector3(1.5, 0.04, 1.5), EkStyle.FIELD_DIRT, false)
		kit.g().blob(Vector3(0, 1.3, 0), 0.75, 1 if kit.lod == 0 else 0, kit.col(Color(0.22, 0.44, 0.18).srgb_to_linear()), kit.rng, 0.2, Vector3(1.0, 0.8, 1.0))
		if kit.lod == 0 and v % 2 == 0:
			for k in 5:
				var a := TAU * k / 5.0
				kit.g().blob(Vector3(cos(a) * 0.5, 1.5 + (k % 2) * 0.2, sin(a) * 0.5), 0.12, 0, kit.col(Color(0.95, 0.62, 0.70).srgb_to_linear()))


static func haystack(kit: BuildingKit, v: int) -> void:
	var r := 1.2 + (v % 2) * 0.3
	kit.g().cylinder(Vector3.ZERO, Vector3(0, 1.4, 0), r, r * 0.9, 8 if kit.lod == 0 else 5, kit.col(EkStyle.STRAW), 0)
	kit.g().cone(Vector3(0, 1.4, 0), Vector3(0, 2.7, 0), r * 0.95, 8 if kit.lod == 0 else 5, kit.col(EkStyle.STRAW * 0.92))
	if kit.lod == 0:
		kit.g().cylinder(Vector3(0, 2.6, 0), Vector3(0, 3.1, 0), 0.05, 0.03, 4, kit.col(&"wood_dark"), 0)
	kit.collide_box(Vector3(0, 1.2, 0), Vector3(r * 1.7, 2.4, r * 1.7))


static func scarecrow(kit: BuildingKit, v: int) -> void:
	var wood := kit.col(&"wood_dark")
	kit.g().cylinder(Vector3.ZERO, Vector3(0, 2.4, 0), 0.06, 0.05, 5, wood, 0)
	if kit.lod >= 2:
		return
	kit.beam(Vector3(-0.9, 1.75, 0), Vector3(0.9, 1.75, 0), 0.06, 0.06, wood)
	kit.g().cylinder(Vector3(0, 1.1, 0), Vector3(0, 1.85, 0), 0.24, 0.3, 6, kit.col(EkStyle.AWNINGS[v % 5]), 0)
	kit.g().blob(Vector3(0, 2.15, 0), 0.2, 0, kit.col(EkStyle.STRAW))
	kit.g().cone(Vector3(0, 2.3, 0), Vector3(0, 2.62, 0), 0.42, 7, kit.col(EkStyle.STRAW * 0.85))
	for sx: float in [-1.0, 1.0]:
		kit.g().cylinder(Vector3(sx * 0.25, 1.75, 0), Vector3(sx * 0.85, 1.7, 0), 0.1, 0.07, 5, kit.col(EkStyle.AWNINGS[(v + 1) % 5]), 0)


static func noticeboard(kit: BuildingKit) -> void:
	var tim := EkStyle.timber(EkStyle.LOWER)
	for sx: float in [-0.9, 0.9]:
		kit.beam(Vector3(sx, 0, 0), Vector3(sx, 2.4, 0), 0.12, 0.12, tim, true)
	kit.box(Vector3(0, 1.5, 0), Vector3(1.8, 1.1, 0.08), tim, false)
	if kit.lod == 0:
		for k in 4:
			kit.box(Vector3(-0.6 + k * 0.4, 1.5 + (k % 2) * 0.15, -0.05), Vector3(0.3, 0.42, 0.02), Color(0.92, 0.86, 0.72), false)
	RoofsLite.gable(kit, Vector3(0, 2.4, 0), 2.0, 0.5, 0.4, EkStyle.roof_opts(EkStyle.LOWER, 0, {"overhang": 0.25, "collide": false, "horns": false}))
