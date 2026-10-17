class_name NwtProps
extends RefCounted
## Water Tribe street furniture, market goods, sculptures and boats (BuildingKit recipes,
## thread-safe; origin on the ground / waterline, -Z = front).
##   stall        market stall: posts, striped cloth canopy, counter with goods (fish, pots, furs)
##   fish_rack    drying rack with hanging fish
##   crates       stack of crates, barrels and baskets
##   lamp_post    ice lantern pillar (glow; real light when spec.light)
##   brazier      fire bowl on an ice plinth (light)
##   banner_pole  tall pole with a long blue banner and a moon finial
##   sculpture    ice sculpture on a plinth: 0 wave crest, 1 moon disc, 2 whale tail, 3 polar
##                bear dog, 4 spiral column
##   bench        ice bench
##   canoe        Water Tribe canoe (hide + wood, blue trim)
##   ship         two-masted Water Tribe ship with blue sails (moored)
##   mooring      mooring posts with rope
##   fire_pit     stone ring with burning logs and a cooking tripod (light)
##   ice_hole     ice-fishing hole: dark water disc, chipped rim, line stand, bucket


static func build(kit: BuildingKit, kind: StringName, v: int, spec: Dictionary = {}) -> void:
	match kind:
		&"stall": stall(kit, v)
		&"fish_rack": fish_rack(kit, v)
		&"crates": crates(kit, v)
		&"lamp_post": lamp_post(kit, v, spec.get("light", false))
		&"brazier": brazier(kit, v)
		&"banner_pole": banner_pole(kit, v)
		&"sculpture": sculpture(kit, v)
		&"bench": bench(kit, v)
		&"canoe": canoe(kit, v)
		&"ship": ship(kit, v)
		&"mooring": mooring(kit, v)
		&"fire_pit": fire_pit(kit, v)
		&"ice_hole": ice_hole(kit, v)


static func _rng(kind: StringName, v: int) -> RandomNumberGenerator:
	return ContentHash.rng(ContentHash.hash4(ContentHash.hash_name(String(kind)), v, 57))


## Market stall (3.2 x 2.4 m): four posts, sloped striped canopy, counter and goods.
static func stall(kit: BuildingKit, v: int) -> void:
	var rng := _rng(&"stall", v)
	var w := 3.2
	var d := 2.4
	var c0: StringName = [&"cloth", &"cloth_alt"][v % 2]
	var c1: StringName = [&"cloth_alt", &"accent"][v % 2]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var hgt := 2.5 if sz < 0.0 else 2.1
			kit.beam(Vector3(sx * w * 0.5, 0, sz * d * 0.5), Vector3(sx * w * 0.5, hgt, sz * d * 0.5), 0.12, 0.12, &"wood", true)
	# canopy: striped cloth quads (two-sided cloth slot), front higher than the back
	var g := kit.g(&"cloth")
	var stripes := 6 if kit.lod == 0 else 2
	for i in stripes:
		var x0 := -w * 0.5 - 0.25 + (w + 0.5) * i / stripes
		var x1 := -w * 0.5 - 0.25 + (w + 0.5) * (i + 1) / stripes
		var col := kit.col(c0 if i % 2 == 0 else c1, false)
		var a := Vector3(x0, 2.55, -d * 0.5 - 0.5)
		var b := Vector3(x1, 2.55, -d * 0.5 - 0.5)
		var c := Vector3(x1, 2.15, d * 0.5 + 0.2)
		var e := Vector3(x0, 2.15, d * 0.5 + 0.2)
		var base := g.vertex_count()
		g.vertex(a, Vector3.UP, col, Vector2(0, (x0 + w) / (w * 2.0)))
		g.vertex(b, Vector3.UP, col, Vector2(0, (x1 + w) / (w * 2.0)))
		g.vertex(c, Vector3.UP, col, Vector2(1, (x1 + w) / (w * 2.0)))
		g.vertex(e, Vector3.UP, col, Vector2(1, (x0 + w) / (w * 2.0)))
		g.quad(base, base + 3, base + 2, base + 1)
	kit.collide_quad(Vector3(-w * 0.5 - 0.25, 2.55, -d * 0.5 - 0.5), Vector3(w * 0.5 + 0.25, 2.55, -d * 0.5 - 0.5),
			Vector3(w * 0.5 + 0.25, 2.15, d * 0.5 + 0.2), Vector3(-w * 0.5 - 0.25, 2.15, d * 0.5 + 0.2))
	# counter
	kit.box(Vector3(0, 0.5, -d * 0.5 + 0.35), Vector3(w - 0.2, 1.0, 0.6), &"wood", true)
	if kit.lod == 0:
		kit.box(Vector3(0, 1.02, -d * 0.5 + 0.35), Vector3(w, 0.06, 0.75), &"wood_dark", false)
		var fish := Color(0.62, 0.70, 0.78).srgb_to_linear()
		match v % 4:
			0:
				for i in 6:
					var p := Vector3(-w * 0.4 + i * w * 0.16, 1.1, -d * 0.5 + 0.35 + rng.randf_range(-0.15, 0.15))
					kit.g().blob(p, 0.16, 0, fish, null, 0.0, Vector3(2.4, 0.5, 0.8))
			1:
				for i in 4:
					var p := Vector3(-w * 0.35 + i * w * 0.23, 1.05, -d * 0.5 + 0.35)
					kit.g().cylinder(p, p + Vector3(0, 0.35, 0), 0.16, 0.11, 7, kit.col(&"stone_dark"), 2)
			2:
				kit.box(Vector3(0, 1.15, -d * 0.5 + 0.35), Vector3(w * 0.8, 0.2, 0.55), Color(0.85, 0.82, 0.74).srgb_to_linear(), false)
				kit.box(Vector3(0.3, 1.3, -d * 0.5 + 0.35), Vector3(w * 0.5, 0.12, 0.45), Color(0.45, 0.36, 0.28).srgb_to_linear(), false)
			_:
				for i in 5:
					var p := Vector3(-w * 0.38 + i * w * 0.19, 1.12, -d * 0.5 + 0.35)
					kit.g().blob(p, 0.14, 0, kit.col(&"accent" if i % 2 == 0 else &"ice"), null, 0.0, Vector3(1, 0.8, 1))
		# back shelf + hanging goods
		kit.box(Vector3(0, 0.9, d * 0.5 - 0.2), Vector3(w - 0.3, 0.08, 0.4), &"wood", false)
		for i in 3:
			var p := Vector3(-w * 0.3 + i * w * 0.3, 1.6, -d * 0.5 + 0.1)
			kit.g().cylinder(p + Vector3(0, 0.6, 0), p, 0.01, 0.01, 3, kit.col(&"wood_dark"), 0)
			kit.g().blob(p - Vector3(0, 0.15, 0), 0.12, 0, fish, null, 0.0, Vector3(0.6, 2.2, 0.5))
		KitX.lantern(kit, Vector3(w * 0.5 - 0.3, 2.1, -d * 0.5 - 0.3), {"style": &"paper", "light": false})


static func fish_rack(kit: BuildingKit, v: int) -> void:
	var w := 3.6 + (v % 2) * 1.2
	for sx: float in [-1.0, 1.0]:
		kit.beam(Vector3(sx * w * 0.5, 0, -0.5), Vector3(sx * w * 0.5, 2.0, 0), 0.1, 0.1, &"wood", true)
		kit.beam(Vector3(sx * w * 0.5, 0, 0.5), Vector3(sx * w * 0.5, 2.0, 0), 0.1, 0.1, &"wood")
	kit.beam(Vector3(-w * 0.5 - 0.2, 1.95, 0), Vector3(w * 0.5 + 0.2, 1.95, 0), 0.08, 0.08, &"wood_dark")
	if kit.lod == 0:
		var fish := Color(0.66, 0.70, 0.74).srgb_to_linear()
		var n := int(w / 0.32)
		for i in n:
			var p := Vector3(-w * 0.5 + 0.2 + i * (w - 0.4) / maxf(n - 1, 1), 1.45, 0.0)
			kit.g().cylinder(p + Vector3(0, 0.5, 0), p + Vector3(0, 0.2, 0), 0.01, 0.01, 3, kit.col(&"wood_dark"), 0)
			kit.g().blob(p, 0.2, 0, fish if i % 3 else Color(0.82, 0.55, 0.45).srgb_to_linear(), null, 0.0, Vector3(0.55, 2.2, 0.3))
			kit.g().cone(p - Vector3(0, 0.38, 0), p - Vector3(0, 0.6, 0), 0.09, 4, fish * 0.9)
		# a hide stretched on the rack end
		kit.box(Vector3(w * 0.5 + 0.05, 1.2, 0.1), Vector3(0.05, 1.3, 0.9), Color(0.70, 0.58, 0.44).srgb_to_linear(), false)


static func crates(kit: BuildingKit, v: int) -> void:
	var rng := _rng(&"crates", v)
	var n := 2 + v % 3
	for i in n:
		var s := rng.randf_range(0.6, 0.95)
		var p := Vector3(rng.randf_range(-0.8, 0.8), s * 0.5, rng.randf_range(-0.6, 0.6))
		kit.box_t(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), p), Vector3(s, s, s), &"wood" if i % 2 == 0 else &"wood_dark", i == 0)
		if kit.lod == 0 and rng.randf() < 0.4:
			kit.box_t(Transform3D(Basis(Vector3.UP, rng.randf()), p + Vector3(0, s * 0.5 + 0.25, 0)), Vector3(0.5, 0.5, 0.5), &"wood", false)
	if kit.lod == 0:
		for i in 1 + v % 2:
			var p := Vector3(1.1 + i * 0.6, 0, rng.randf_range(-0.4, 0.4))
			kit.g().cylinder(p, p + Vector3(0, 0.9, 0), 0.3, 0.3, 8, kit.col(&"wood"), 2)
			kit.g().cylinder(p + Vector3(0, 0.2, 0), p + Vector3(0, 0.28, 0), 0.32, 0.32, 8, kit.col(&"metal"), 0)
			kit.g().cylinder(p + Vector3(0, 0.62, 0), p + Vector3(0, 0.7, 0), 0.32, 0.32, 8, kit.col(&"metal"), 0)


## Ice lantern pillar: a faceted ice post with a glowing heart.
static func lamp_post(kit: BuildingKit, v: int, light: bool) -> void:
	var h := 2.2 + (v % 2) * 0.6
	kit.box(Vector3(0, 0.2, 0), Vector3(0.7, 0.4, 0.7), &"stone_dark", false)
	kit.cylinder(Vector3(0, 0.4, 0), h * 0.62, 0.22, &"ice", 6, false, 0.17, &"ice")
	var lc := Vector3(0, 0.4 + h * 0.62 + 0.3, 0)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 0.5)
	gb.blob(lc, 0.24, 1 if kit.lod == 0 else 0, Color(1.0, 0.86, 0.62), null, 0.0, Vector3(0.9, 1.3, 0.9))
	if kit.lod < 2:
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			kit.beam(lc + Vector3(cos(a) * 0.3, -0.35, sin(a) * 0.3), lc + Vector3(cos(a) * 0.22, 0.4, sin(a) * 0.22), 0.07, 0.07, &"ice")
		kit.g(&"ice").cone(lc + Vector3(0, 0.35, 0), lc + Vector3(0, 0.95, 0), 0.32, 6, kit.col(&"ice"))
	kit.collide_box(Vector3(0, h * 0.5, 0), Vector3(0.45, h, 0.45))
	if light:
		kit.add_light(lc, Color(1.0, 0.82, 0.55), 10.0, 1.6, 1)


static func brazier(kit: BuildingKit, v: int) -> void:
	kit.box(Vector3(0, 0.35, 0), Vector3(1.3, 0.7, 1.3), &"stone_dark", true)
	if kit.lod < 2:
		kit.box(Vector3(0, 0.72, 0), Vector3(1.45, 0.08, 1.45), &"trim", false)
	kit.brazier(Vector3(0, 0.7, 0), {"height": 0.5, "radius": 0.5 + (v % 2) * 0.1, "range": 12.0, "energy": 2.4, "light": true})


static func banner_pole(kit: BuildingKit, v: int) -> void:
	var h := 7.0 + (v % 3) * 1.5
	kit.box(Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.9), &"stone_dark", true)
	kit.cylinder(Vector3(0, 0.6, 0), h, 0.1, &"wood_dark", 6, true, 0.07)
	if kit.lod < 2:
		kit.beam(Vector3(-0.8, h - 0.1, 0), Vector3(0.8, h - 0.1, 0), 0.08, 0.08, &"wood_dark")
		KitX.banner(kit, Transform3D(Basis(), Vector3(0, h - 0.15, -0.05)), 1.3, h * 0.55)
		# moon finial
		var top := Vector3(0, h + 0.8, 0)
		var moon := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 9:
			var a := lerpf(PI * 0.2, PI * 1.8, i / 8.0) + PI * 0.5
			moon.append(top + Vector3(cos(a) * 0.35, sin(a) * 0.35, 0))
			radii.append(0.07 * sin(i / 8.0 * PI) + 0.01)
		kit.g().tube(moon, radii, 4, kit.col(&"metal"))


## Ice sculptures on a stepped plinth.
static func sculpture(kit: BuildingKit, v: int) -> void:
	kit.box(Vector3(0, 0.3, 0), Vector3(2.6, 0.6, 2.6), &"stone_dark", true)
	kit.box(Vector3(0, 0.75, 0), Vector3(2.0, 0.3, 2.0), &"trim", true)
	var b := Vector3(0, 0.9, 0)
	var ig := kit.g(&"ice")
	var ice := kit.col(&"ice", false)
	var ice2 := kit.col(&"wall_alt", false)
	match v % 5:
		0:
			# rising wave crest
			var line := PackedVector3Array()
			var radii := PackedFloat32Array()
			for i in 10:
				var t := i / 9.0
				line.append(b + Vector3(lerpf(-0.8, 0.5, t), sin(t * PI * 0.9) * 3.0, -cos(t * PI) * 0.4))
				radii.append(lerpf(0.55, 0.12, t))
			ig.tube(line, radii, 7, ice, ice2)
			ig.blob(line[9] + Vector3(-0.2, -0.1, 0), 0.35, 0, ice, null, 0.0, Vector3(1.4, 0.6, 1.0))
		1:
			# moon disc on a column
			ig.cylinder(b, b + Vector3(0, 2.2, 0), 0.25, 0.2, 6, ice)
			ig.cylinder(b + Vector3(0, 3.1, -0.1), b + Vector3(0, 3.1, 0.1), 0.95, 0.95, 16, ice, 3)
			KitX.emblem_water(kit, b + Vector3(0, 3.1, 0.0), 1.2, &"trim", 0.12)
		2:
			# whale tail rising from the plinth
			ig.cylinder(b, b + Vector3(0, 2.0, 0), 0.4, 0.22, 7, ice)
			for sx: float in [-1.0, 1.0]:
				var fl := PackedVector3Array([b + Vector3(0, 2.0, 0), b + Vector3(sx * 0.8, 2.5, 0), b + Vector3(sx * 1.5, 3.1, 0.1)])
				ig.tube(fl, PackedFloat32Array([0.25, 0.22, 0.05]), 5, ice, ice2)
		3:
			# seated polar bear dog
			ig.blob(b + Vector3(0, 0.8, 0.2), 0.9, 1, ice, null, 0.0, Vector3(0.9, 1.0, 1.2))
			ig.blob(b + Vector3(0, 1.8, -0.5), 0.5, 1, ice, null, 0.0, Vector3(0.9, 0.9, 1.1))
			ig.blob(b + Vector3(0, 1.65, -0.95), 0.22, 0, ice2, null, 0.0, Vector3(1.0, 0.8, 1.3))
			for sx: float in [-1.0, 1.0]:
				ig.cone(b + Vector3(sx * 0.28, 2.15, -0.45), b + Vector3(sx * 0.3, 2.45, -0.45), 0.1, 4, ice)
				ig.cylinder(b + Vector3(sx * 0.4, 0.0, -0.4), b + Vector3(sx * 0.35, 1.0, -0.55), 0.18, 0.15, 6, ice)
		_:
			# twisted spiral column
			var line2 := PackedVector3Array()
			var r2 := PackedFloat32Array()
			for i in 14:
				var t := i / 13.0
				line2.append(b + Vector3(cos(t * TAU * 1.5) * 0.35, t * 3.6, sin(t * TAU * 1.5) * 0.35))
				r2.append(lerpf(0.4, 0.1, t))
			ig.tube(line2, r2, 6, ice, ice2)
			ig.blob(b + Vector3(0, 3.8, 0), 0.3, 1, ice)
	kit.collide_box(Vector3(0, 2.2, 0), Vector3(1.4, 2.8, 1.4))


static func bench(kit: BuildingKit, v: int) -> void:
	var w := 2.2 + (v % 2) * 0.8
	kit.box(Vector3(0, 0.42, 0), Vector3(w, 0.14, 0.6), &"wall_alt", true)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (w * 0.5 - 0.25), 0.18, 0), Vector3(0.3, 0.36, 0.55), &"stone_dark", false)
	if kit.lod == 0:
		kit.box(Vector3(0, 0.5, 0.05), Vector3(w * 0.6, 0.05, 0.45), Color(0.66, 0.60, 0.52).srgb_to_linear(), false)


## Canoe (~5 m): hide hull with blue trim, paddles; waterline at y = 0.
static func canoe(kit: BuildingKit, v: int) -> void:
	var hide := Color(0.62, 0.52, 0.40).srgb_to_linear()
	BoatBuilder.hull(kit, 4.6 + (v % 2) * 0.8, 0.85, 0.5, {"deck": false, "rise": 0.35, "role": hide, "bottom_role": &"wood_dark", "trim_role": &"trim"})
	if kit.lod == 0:
		for z in [-0.6, 0.7]:
			kit.box(Vector3(0, 0.15, z), Vector3(0.7, 0.05, 0.25), &"wood", false)
		kit.beam(Vector3(-0.3, 0.3, 0.2), Vector3(0.6, 0.05, 1.6), 0.05, 0.05, &"wood")
		kit.box(Vector3(0.6, 0.05, 1.7), Vector3(0.18, 0.04, 0.45), &"wood", false)
		if v % 3 == 0:
			kit.box(Vector3(0, 0.25, -0.1), Vector3(0.5, 0.25, 0.6), Color(0.85, 0.82, 0.74).srgb_to_linear(), false)


## Two-masted Water Tribe ship (~22 m) moored at the waterline (y = 0).
static func ship(kit: BuildingKit, v: int) -> void:
	var l := 20.0 + (v % 2) * 4.0
	var beam := 6.0
	BoatBuilder.hull(kit, l, beam, 2.6, {"rise": 1.4, "role": &"wood", "bottom_role": &"wood_dark", "trim_role": &"trim"})
	var dy := 2.6 * 0.6 * 0.75
	# deck house (stern) with a blue band and a small dome
	var cz := l * 0.26
	kit.box(Vector3(0, dy + 1.2, cz), Vector3(beam * 0.6, 2.4, l * 0.2), &"wall", true)
	if kit.lod < 2:
		kit.box(Vector3(0, dy + 2.3, cz), Vector3(beam * 0.62, 0.25, l * 0.2 + 0.05), &"trim", false)
		KitRoofs.dome(kit, Vector3(0, dy + 2.4, cz), beam * 0.22, {"squash": 0.7, "role": &"roof", "slot": &"ice", "finial": false, "ribs": kit.lod == 0})
		for sx: float in [-1.0, 1.0]:
			kit.push(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), Vector3(sx * beam * 0.3, dy + 1.3, cz)))
			KitX.window(kit, Vector3.ZERO, 0.5, 0.6, &"trim", 0.0, true)
			kit.pop()
	# masts and sails
	for m in 2:
		var mz := -l * 0.28 + m * l * 0.3
		var mh := 13.0 - m * 2.5
		kit.cylinder(Vector3(0, dy, mz), mh, 0.18, &"wood_dark", 6, true, 0.1)
		if kit.lod < 2:
			var sw := 7.0 - m * 1.2
			kit.beam(Vector3(-sw * 0.55, dy + mh - 0.6, mz), Vector3(sw * 0.55, dy + mh - 0.6, mz), 0.12, 0.12, &"wood")
			kit.beam(Vector3(-sw * 0.5, dy + mh * 0.38, mz), Vector3(sw * 0.5, dy + mh * 0.38, mz), 0.1, 0.1, &"wood")
			kit.banner(Transform3D(Basis(), Vector3(0, dy + mh - 0.65, mz - 0.12)), sw, mh * 0.58,
					{"role": &"cloth_alt" if m == 0 else &"cloth", "alt_role": &"cloth" if m == 0 else &"cloth_alt", "rod": false, "tail": false})
			if kit.lod == 0:
				kit.flag(Transform3D(Basis(), Vector3(0, dy + mh, mz)), 1.2, 1.2, 0.5, {"role": &"cloth", "alt_role": &"cloth_alt"})
	if kit.lod == 0:
		kit.railing(PackedVector3Array([Vector3(-beam * 0.4, dy, -l * 0.38), Vector3(-beam * 0.44, dy, l * 0.42)]), 0.9, {"spacing": 1.4, "collide": true})
		kit.railing(PackedVector3Array([Vector3(beam * 0.4, dy, -l * 0.38), Vector3(beam * 0.44, dy, l * 0.42)]), 0.9, {"spacing": 1.4, "collide": true})
		KitX.lantern(kit, Vector3(0, dy + 3.0, l * 0.4), {"style": &"paper", "range": 8.0, "light": false})
		# bowsprit + figurehead curl
		kit.beam(Vector3(0, dy + 0.9, -l * 0.5), Vector3(0, dy + 2.2, -l * 0.5 - 3.0), 0.16, 0.16, &"wood_dark")
		KitX.emblem_water(kit, Vector3(0, dy + 0.4, -l * 0.5 + 0.3), 1.4, &"trim", 0.0)
	kit.mark(&"deck", Transform3D(Basis(), Vector3(0, dy, 0)))


static func mooring(kit: BuildingKit, v: int) -> void:
	for k in 2 + v % 2:
		var p := Vector3(k * 1.6, 0, 0)
		kit.cylinder(p, 0.9, 0.16, &"wood_dark", 6, true, 0.13)
		if kit.lod == 0:
			kit.g().cylinder(p + Vector3(0, 0.55, 0), p + Vector3(0, 0.65, 0), 0.19, 0.19, 6, kit.col(&"wood"), 0)


static func fire_pit(kit: BuildingKit, v: int) -> void:
	var stone := kit.col(&"stone_dark")
	for k in 10:
		var a := TAU * k / 10.0
		kit.g().blob(Vector3(cos(a) * 0.95, 0.12, sin(a) * 0.95), 0.24, 0, stone, null, 0.0, Vector3(1.1, 0.7, 1.0))
	if kit.lod < 2:
		for k in 3:
			var a := TAU * k / 3.0 + 0.3
			kit.beam(Vector3(cos(a) * 0.6, 0.12, sin(a) * 0.6), Vector3(-cos(a) * 0.2, 0.35, -sin(a) * 0.2), 0.14, 0.14, &"wood_dark")
		var gb := kit.g(&"glow")
		gb.uv = Vector2(0, 1)
		var fire := Color(1.0, 0.55, 0.18)
		gb.cone(Vector3(0, 0.2, 0), Vector3(0, 1.2, 0), 0.45, 6, fire)
		gb.cone(Vector3(0.2, 0.2, 0.1), Vector3(0.25, 0.9, 0.1), 0.25, 5, fire * 1.1)
		gb.cone(Vector3(-0.2, 0.2, -0.1), Vector3(-0.25, 0.85, -0.1), 0.25, 5, fire * 1.1)
		if kit.lod == 0:
			kit.add_fire(Vector3(0, 0.2, 0), &"campfire", 0.55)
		if kit.lod == 0 and v % 2 == 0:
			for k in 3:
				var a := TAU * k / 3.0
				kit.beam(Vector3(cos(a) * 0.9, 0.0, sin(a) * 0.9), Vector3(0, 1.9, 0), 0.05, 0.05, &"wood")
			kit.g().cylinder(Vector3(0, 1.25, 0), Vector3(0, 1.55, 0), 0.22, 0.26, 8, kit.col(&"metal"), 1)
	kit.add_light(Vector3(0, 1.3, 0), Color(1.0, 0.62, 0.3), 13.0, 2.6, 2)
	kit.collide_box(Vector3(0, 0.25, 0), Vector3(2.0, 0.5, 2.0))


static func ice_hole(kit: BuildingKit, v: int) -> void:
	kit.g().cylinder(Vector3(0, 0.0, 0), Vector3(0, 0.03, 0), 0.65, 0.65, 12, kit.col(&"window", false) * 1.4, 2)
	var ice := kit.col(&"ice")
	for k in 8:
		var a := TAU * k / 8.0
		kit.g(&"ice").blob(Vector3(cos(a) * 0.8, 0.06, sin(a) * 0.8), 0.18, 0, ice, null, 0.0, Vector3(1.2, 0.5, 1.0))
	if kit.lod == 0:
		kit.beam(Vector3(1.1, 0, 0.2), Vector3(0.9, 0.9, 0.0), 0.05, 0.05, &"wood")
		kit.beam(Vector3(0.9, 0.9, 0.0), Vector3(0.1, 1.1, 0.0), 0.03, 0.03, &"wood")
		kit.g().cylinder(Vector3(0.1, 1.1, 0.0), Vector3(0.1, 0.0, 0.0), 0.006, 0.006, 3, kit.col(&"wood_dark"), 0)
		kit.g().cylinder(Vector3(-1.1, 0, 0.6), Vector3(-1.1, 0.45, 0.6), 0.22, 0.25, 8, kit.col(&"wood"), 1)
		if v % 2 == 0:
			kit.g().blob(Vector3(-1.1, 0.5, 0.6), 0.12, 0, Color(0.66, 0.70, 0.74).srgb_to_linear(), null, 0.0, Vector3(2.0, 0.5, 0.7))
