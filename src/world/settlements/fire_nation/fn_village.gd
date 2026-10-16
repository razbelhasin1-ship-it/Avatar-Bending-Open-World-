class_name FnVillage
extends RefCounted
## Fire Nation village structures (BuildingKit recipes, thread-safe; origin on the ground, -Z
## front):
##   tea_rows     a terrace of clipped tea hedges (spec L along x, n rows towards +Z, gap)
##   tea_shed     open drying shed: red posts, a black roof, racks of flat baskets of leaves
##   fire_shrine  roadside fire shrine: basalt steps, red posts, a black roof, an eternal flame
##   cabana       resort beach pavilion: red posts, a thatched cone roof, mats and cushions
##   hot_spring   volcanic hot-spring pool ringed with dark rocks and a red bench (steam:
##                FnBuilder extras)
##   salt_pans    a grid of shallow evaporation pans (spec w, d, nx, nz): low basalt dikes, brine
##                and white salt crust, heaps of salt with rakes along the front
##   lawn         a round clipped lawn with a sand border (spec r): the resort court's ground

const KINDS: Array[StringName] = [&"tea_rows", &"tea_shed", &"fire_shrine", &"cabana", &"hot_spring", &"salt_pans", &"lawn"]
const LAWN := Color(0.30, 0.46, 0.18)
const SAND := Color(0.80, 0.72, 0.54)
const SALT := Color(0.93, 0.92, 0.88)
const BRINE := Color(0.62, 0.72, 0.74)
const TEA := Color(0.16, 0.34, 0.12)
const TEA_TOP := Color(0.24, 0.44, 0.16)
const THATCH := Color(0.62, 0.5, 0.3)


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	match kind:
		&"tea_rows": tea_rows(kit, spec)
		&"tea_shed": tea_shed(kit, v)
		&"fire_shrine": fire_shrine(kit, v)
		&"cabana": cabana(kit, v)
		&"hot_spring": hot_spring(kit, spec)
		&"salt_pans": salt_pans(kit, spec)
		&"lawn": lawn(kit, float(spec.get("r", 40.0)))


static func lawn(kit: BuildingKit, r: float) -> void:
	var sides := 40 if kit.lod == 0 else 20
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in sides:
		var a := TAU * i / sides
		outer.append(Vector2(cos(a), sin(a)) * r)
		inner.append(Vector2(cos(a), sin(a)) * (r - 2.5))
	kit.slab(outer, 0.0, 0.03, SAND.srgb_to_linear(), false)
	kit.slab(inner, 0.0, 0.05, LAWN.srgb_to_linear(), false)


static func salt_pans(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 20.0))
	var d := float(spec.get("d", 12.0))
	var nx := int(spec.get("nx", 3))
	var nz := int(spec.get("nz", 2))
	kit.box(Vector3(0, 0.06, 0), Vector3(w, 0.12, d), FnStyle.BASALT_2, true)
	var pw := w / nx
	var pd := d / nz
	for i in nx:
		for j in nz:
			var c := Vector3(-w * 0.5 + (i + 0.5) * pw, 0.13, -d * 0.5 + (j + 0.5) * pd)
			var crust := (i + j) % 3 != 0
			kit.box(c, Vector3(pw - 0.7, 0.04, pd - 0.7), (SALT if crust else BRINE).srgb_to_linear(), false, &"solid" if crust else &"ice")
	if kit.lod >= 2:
		return
	# dikes between the pans
	for i in nx + 1:
		kit.box(Vector3(-w * 0.5 + i * pw, 0.2, 0), Vector3(0.35, 0.2, d), FnStyle.BASALT, false)
	for j in nz + 1:
		kit.box(Vector3(0, 0.2, -d * 0.5 + j * pd), Vector3(w, 0.2, 0.35), FnStyle.BASALT, false)
	# salt heaps and rakes along the front
	for k in nx:
		var p := Vector3(-w * 0.5 + (k + 0.5) * pw, 0.1, -d * 0.5 - 1.4)
		kit.g().cone(p, p + Vector3(0, 0.9 + (k % 2) * 0.3, 0), 0.9, 7 if kit.lod == 0 else 5, kit.col(SALT.srgb_to_linear()))
		if kit.lod == 0 and k % 2 == 0:
			kit.beam(p + Vector3(0.9, 0.0, 0.2), p + Vector3(1.3, 1.5, 0.5), 0.05, 0.05, &"wood")
	kit.collide_box(Vector3(0, 0.3, -d * 0.5 - 1.4), Vector3(w, 0.6, 1.6))


static func tea_rows(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 20.0))
	var n := int(spec.get("n", 4))
	var gap := float(spec.get("gap", 1.9))
	var tea := TEA.srgb_to_linear()
	var top := TEA_TOP.srgb_to_linear()
	kit.box(Vector3(0, 0.03, (n - 1) * gap * 0.5), Vector3(L + 1.0, 0.06, n * gap + 0.6), EkStyle.FIELD_DIRT, false)
	for i in n:
		var z := i * gap
		kit.box(Vector3(0, 0.45, z), Vector3(L, 0.9, 1.15), tea, false)
		if kit.lod < 2:
			kit.box(Vector3(0, 0.98, z), Vector3(L - 0.3, 0.2, 0.8), top, false)
			if kit.lod == 0:
				# a few bulges so the hedge does not read as a box
				var nb := int(L / 2.6)
				for k in nb:
					var x := lerpf(-L * 0.5 + 1.2, L * 0.5 - 1.2, (k + 0.5) / nb)
					kit.g().blob(Vector3(x, 0.92, z), 0.62, 0, kit.col(top), kit.rng, 0.15, Vector3(1.5, 0.55, 1.0))


static func tea_shed(kit: BuildingKit, v: int) -> void:
	var w := 9.0
	var d := 6.0
	kit.box(Vector3(0, 0.15, 0), Vector3(w + 0.6, 0.3, d + 0.6), FnStyle.BASALT_DARK)
	for sx: float in [-1.0, 1.0]:
		for k in 3:
			var x := sx * w * 0.5 if k != 1 else sx * w * 0.5
			var z := lerpf(-d * 0.5, d * 0.5, k / 2.0)
			kit.column(Vector3(x, 0.3, z), 3.0, 0.14, FnStyle.RED, &"square", FnStyle.BASALT_DARK)
	RoofsLite.gable(kit, Vector3(0, 3.3, 0), w, d, 1.8, FnStyle.roof_opts(FnStyle.VILLAGE, v, {"overhang": 0.9}))
	if kit.lod >= 2:
		return
	var leaf := Color(0.3, 0.38, 0.14).srgb_to_linear()
	for tier in 3:
		var y := 0.8 + tier * 0.7
		kit.box(Vector3(0, y, 0), Vector3(w - 1.2, 0.05, d - 1.6), &"wood", false)
		if kit.lod == 0:
			for k in 4:
				var x := lerpf(-w * 0.5 + 1.6, w * 0.5 - 1.6, k / 3.0)
				kit.g().cylinder(Vector3(x, y + 0.03, 0), Vector3(x, y + 0.12, 0), 0.75, 0.8, 8, kit.col(EkStyle.STRAW), 1)
				kit.g().cylinder(Vector3(x, y + 0.12, 0), Vector3(x, y + 0.15, 0), 0.68, 0.68, 8, kit.col(leaf), 0)


static func fire_shrine(kit: BuildingKit, v: int) -> void:
	kit.box(Vector3(0, 0.25, 0), Vector3(4.0, 0.5, 4.0), FnStyle.BASALT_DARK)
	kit.box(Vector3(0, 0.65, 0), Vector3(3.0, 0.3, 3.0), FnStyle.BASALT)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.column(Vector3(sx * 1.2, 0.8, sz * 1.2), 2.4, 0.12, FnStyle.RED, &"round", FnStyle.BASALT_DARK)
	RoofsLite.hip(kit, Vector3(0, 3.2, 0), 3.0, 3.0, 1.4, FnStyle.roof_opts(FnStyle.NOBLE, v, {"overhang": 0.8, "curve": 0.9}))
	FnStyle.flame_finial(kit, Vector3(0, 4.6, 0), 0.7)
	kit.push(Transform3D(Basis(), Vector3(0, 0.8, 0)))
	kit.cylinder(Vector3.ZERO, 0.6, 0.4, FnStyle.BASALT_2, 8, false, 0.3)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 1)
	gb.cone(Vector3(0, 0.6, 0), Vector3(0, 1.4, 0), 0.25, 5, Color(1.0, 0.6, 0.25))
	kit.add_light(Vector3(0, 1.3, 0), Color(1.0, 0.55, 0.25), 8.0, 1.6, 1)
	kit.pop()
	if kit.lod < 2:
		kit.stairs(Vector3(0, 0, -3.2), Vector3(0, 0.5, -2.0), 2.0, {"role": FnStyle.BASALT_2})


static func cabana(kit: BuildingKit, v: int) -> void:
	var r := 3.0
	kit.box(Vector3(0, 0.1, 0), Vector3(r * 2.0, 0.2, r * 2.0), &"wood", true)
	for k in 6:
		var a := TAU * k / 6.0
		kit.column(Vector3(cos(a) * r * 0.85, 0.2, sin(a) * r * 0.85), 2.6, 0.1, FnStyle.RED, &"round")
	KitRoofs.cone(kit, Vector3(0, 2.8, 0), r * 1.2, 1.8, {"sides": 6, "flare": 0.4, "role": THATCH.srgb_to_linear(), "alt_role": (THATCH * 0.85).srgb_to_linear(),
		"trim_role": FnStyle.RED, "finial": true, "finial_role": FnStyle.GOLD})
	if kit.lod >= 2:
		return
	var mats: Array[Color] = [FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, Color(0.85, 0.82, 0.74).srgb_to_linear()]
	for k in 2:
		var x := (k - 0.5) * 2.2
		kit.box(Vector3(x, 0.32, 0.2), Vector3(1.0, 0.16, 2.0), mats[(k + v) % 3], false)
		kit.box(Vector3(x, 0.45, 1.0), Vector3(0.8, 0.18, 0.4), mats[(k + v + 1) % 3], false)


static func hot_spring(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 5.0))
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a), sin(a)) * r * (1.0 + 0.1 * sin(a * 3.0)))
	kit.g().extrude(pts, -0.2, 0.25, kit.col(FnStyle.BASALT_DARK), 2)
	kit.collide_box(Vector3(0, 0.0, 0), Vector3(r * 2.0, 0.5, r * 2.0))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.86)
	kit.g(&"ice").extrude(inner, 0.1, 0.29, kit.col(Color(0.36, 0.6, 0.62).srgb_to_linear(), false), 2)
	if kit.lod >= 2:
		return
	for i in 12:
		var a := TAU * i / 12.0 + 0.2
		var s := kit.rng.randf_range(0.5, 0.9)
		var p := Vector3(cos(a), 0, sin(a)) * r * 0.98
		kit.g().blob(p + Vector3(0, 0.3, 0), s, 0, kit.col(FnStyle.BASALT if i % 2 == 0 else FnStyle.BASALT_2), kit.rng, 0.3, Vector3(1.2, 0.8, 1.0))
	kit.box(Vector3(0, 0.45, -r - 1.2), Vector3(3.0, 0.15, 0.6), FnStyle.RED_DARK, true)
