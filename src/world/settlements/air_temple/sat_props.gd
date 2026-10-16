class_name SatProps
extends RefCounted
## Air Temple street furniture (BuildingKit recipes, thread-safe; origin on the ground, -Z =
## front):
##   flag_line     two poles with a sagging line of prayer flags between them (spec L along X)
##   chime_post    tall post with a little teal roof and a crossbar of wind chimes
##   lantern       stone lantern (budgeted light when spec.light)
##   bench         stone bench
##   gong          bronze gong in a wooden frame with a little roof
##   prayer_wheels row of turning prayer wheels under a teal canopy (spec n)
##   planter       round stone planter (a shrub / blossom from the builder extras)
##   hay           hay bales and a cart for the bison landing


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	match kind:
		&"flag_line": flag_line(kit, spec)
		&"chime_post": chime_post(kit, v)
		&"lantern": kit.lantern(Vector3.ZERO, {"style": &"stone", "height": 1.6 + (v % 2) * 0.4, "light": spec.get("light", false),
			"range": 10.0, "energy": 1.5})
		&"bench": bench(kit, v)
		&"gong": gong(kit, v)
		&"prayer_wheels": prayer_wheels(kit, spec)
		&"planter": planter(kit, v)
		&"hay": hay(kit, v)


const FLAGS := [Color(0.92, 0.55, 0.16), Color(0.98, 0.80, 0.30), Color(0.42, 0.70, 0.86), Color(0.96, 0.95, 0.90), Color(0.78, 0.26, 0.18)]


static func flag_roles() -> Array:
	var out: Array = []
	for c: Color in FLAGS:
		out.append(c.srgb_to_linear())
	return out


static func flag_line(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 10.0))
	var h := float(spec.get("h", 4.5))
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * L * 0.5, 0, 0)
		kit.box(p + Vector3(0, 0.2, 0), Vector3(0.5, 0.4, 0.5), SatStyle.masonry(1), false)
		kit.cylinder(p, h, 0.08, &"wood_dark", 6, true, 0.06)
		if kit.lod < 2:
			kit.ornament(p + Vector3(0, h + 0.05, 0), &"orb", 0.22, SatStyle.gold())
	if kit.lod == 0:
		KitX.flag_string(kit, Vector3(-L * 0.5, h - 0.15, 0), Vector3(L * 0.5, h - 0.15, 0), float(spec.get("sag", L * 0.08)), flag_roles(), 0.34)
		if L > 6.0:
			KitX.flag_string(kit, Vector3(-L * 0.5, h - 1.1, 0), Vector3(L * 0.5, h - 1.1, 0), float(spec.get("sag", L * 0.08)) * 0.8, flag_roles(), 0.3)
	elif kit.lod == 1:
		kit.g(&"cloth").flat_quad(Vector3(-L * 0.5, h - 0.15, 0), Vector3(L * 0.5, h - 0.15, 0), Vector3(L * 0.5, h - 0.45, 0),
				Vector3(-L * 0.5, h - 0.45, 0), kit.col(SatStyle.orange()))


static func chime_post(kit: BuildingKit, v: int) -> void:
	var h := 3.4 + (v % 2) * 0.6
	kit.box(Vector3(0, 0.15, 0), Vector3(0.6, 0.3, 0.6), SatStyle.masonry(1), false)
	kit.cylinder(Vector3(0, 0.3, 0), h, 0.09, &"wood_dark", 6, true, 0.08)
	kit.beam(Vector3(-0.8, h, 0), Vector3(0.8, h, 0), 0.1, 0.1, &"wood")
	KitRoofs.cone(kit, Vector3(0, h + 0.3, 0), 0.75, 0.75, SatStyle.cone_opts(v, 8, 0.6))
	if kit.lod == 0:
		for sx: float in [-0.65, 0.0, 0.65]:
			SatPlaces._chime(kit, Vector3(sx, h - 0.05, 0), 0.7)


static func bench(kit: BuildingKit, v: int) -> void:
	var w := 2.4 + (v % 2) * 0.8
	kit.box(Vector3(0, 0.44, 0), Vector3(w, 0.14, 0.62), SatStyle.wall(1), true)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (w * 0.5 - 0.3), 0.19, 0), Vector3(0.34, 0.38, 0.56), SatStyle.masonry(0), false)
	if kit.lod == 0:
		kit.box(Vector3(0, 0.53, 0.04), Vector3(w * 0.5, 0.05, 0.4), SatStyle.orange(), false)


static func gong(kit: BuildingKit, _v: int) -> void:
	for sx: float in [-1.0, 1.0]:
		kit.cylinder(Vector3(sx * 1.4, 0, 0), 3.6, 0.13, &"wood_dark", 8, true)
	kit.beam(Vector3(-1.75, 3.5, 0), Vector3(1.75, 3.5, 0), 0.22, 0.26, &"wood")
	kit.box(Vector3(0, 0.15, 0), Vector3(3.6, 0.3, 1.0), SatStyle.masonry(1), false)
	KitRoofs.hip(kit, Vector3(0, 3.7, 0), 3.4, 0.9, 0.9, {"role": SatStyle.roof(1), "alt_role": SatStyle.roof_stripe(1), "ridge_role": SatStyle.gold(),
		"curve": 0.5, "overhang": 0.4, "ornaments": false})
	kit.g().cylinder(Vector3(0, 2.0, -0.08), Vector3(0, 2.0, 0.08), 1.05, 1.05, 20 if kit.lod == 0 else 10, kit.col(SatStyle.gold()) * 0.85, 2)
	if kit.lod < 2:
		kit.g().cylinder(Vector3(0, 2.0, -0.1), Vector3(0, 2.0, -0.12), 0.45, 0.45, 14, kit.col(SatStyle.gold()) * 1.1, 2)
		if kit.lod == 0:
			for sx: float in [-0.5, 0.5]:
				kit.g().cylinder(Vector3(sx, 3.4, 0), Vector3(sx * 0.9, 2.95, 0), 0.015, 0.015, 3, kit.col(&"wood_dark"), 0)
			kit.beam(Vector3(1.1, 0.0, -0.6), Vector3(0.9, 1.6, -0.5), 0.08, 0.08, &"wood")


static func prayer_wheels(kit: BuildingKit, spec: Dictionary) -> void:
	var n := int(spec.get("n", 6))
	var w := n * 0.9 + 0.8
	kit.box(Vector3(0, 0.2, 0), Vector3(w, 0.4, 1.4), SatStyle.masonry(1), true)
	kit.box(Vector3(0, 1.3, 0.5), Vector3(w, 2.2, 0.3), SatStyle.wall(0), true)
	for sx: float in [-1.0, 1.0]:
		kit.cylinder(Vector3(sx * w * 0.5, 0.4, -0.5), 2.4, 0.1, &"wood_dark", 6, true)
	_hip_small(kit, Vector3(0, 2.8, 0), w, 1.4)
	for k in n:
		var x := -w * 0.5 + 0.8 + k * 0.9
		kit.g().cylinder(Vector3(x, 0.9, -0.1), Vector3(x, 1.6, -0.1), 0.32, 0.32, 10 if kit.lod == 0 else 6, kit.col(SatStyle.gold() if k % 2 == 0 else SatStyle.orange()), 2)
		if kit.lod == 0:
			kit.g().cylinder(Vector3(x, 1.2, -0.1), Vector3(x, 1.3, -0.1), 0.335, 0.335, 10, kit.col(SatStyle.sky()), 0)
			kit.g().cylinder(Vector3(x, 0.4, -0.1), Vector3(x, 2.4, -0.1), 0.03, 0.03, 4, kit.col(&"wood_dark"), 0)


static func _hip_small(kit: BuildingKit, c: Vector3, w: float, d: float) -> void:
	KitRoofs.hip(kit, c, w, d, 1.0, {"role": SatStyle.roof(2), "alt_role": SatStyle.roof_stripe(2), "ridge_role": SatStyle.gold(),
		"curve": 0.6, "overhang": 0.45, "ornaments": kit.lod == 0})


static func planter(kit: BuildingKit, v: int) -> void:
	var r := 0.9 + (v % 2) * 0.35
	kit.cylinder(Vector3(0, 0, 0), 0.8, r, SatStyle.wall(1), 12, true, r * 1.1)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, 0.7, 0), 0.12, r * 1.12, SatStyle.orange(), 12, false)
		kit.g().cylinder(Vector3(0, 0.75, 0), Vector3(0, 0.8, 0), r, r, 12, kit.col(SatStyle.lin(SatStyle.SOIL)), 2)


static func hay(kit: BuildingKit, v: int) -> void:
	var rng := ContentHash.rng(ContentHash.hash4(v, 31, 4))
	var hay_c := SatStyle.lin(SatStyle.HAY)
	for k in 3 + v % 3:
		var p := Vector3(rng.randf_range(-1.6, 1.6), 0.5, rng.randf_range(-1.0, 1.0))
		kit.box_t(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)), p), Vector3(1.4, 1.0, 0.9), hay_c * rng.randf_range(0.9, 1.05), k == 0)
		if kit.lod == 0:
			for sx: float in [-0.35, 0.35]:
				kit.box_t(Transform3D(Basis(Vector3.UP, 0.0), p + Vector3(sx, 0, 0)), Vector3(0.05, 1.02, 0.92), &"wood_dark", false)
	if kit.lod < 2 and v % 2 == 0:
		kit.g().blob(Vector3(2.4, 0.6, 0.4), 1.1, 1 if kit.lod == 0 else 0, hay_c, kit.rng, 0.15, Vector3(1.3, 0.6, 1.0))
