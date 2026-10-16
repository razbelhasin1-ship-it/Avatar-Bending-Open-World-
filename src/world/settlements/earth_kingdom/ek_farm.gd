class_name EkFarm
extends RefCounted
## The Agrarian Zone's farm architecture (BuildingKit recipes, thread-safe; origin on the
## ground, -Z front). The rotating parts (windmill sails, water wheels) are main-thread nodes
## (EkFarm.spinner, created by EkBuilder.piece_extras); the kit draws them only in the far LOD.
##   windmill    tapered timber tower on a stone base with a cap; sails face -Z (static at LOD2)
##   water_wheel stone sluice piers and an axle frame beside an irrigation canal (wheel = spinner)
##   granary     storehouse raised on stilts, plank walls, straw-brown roof, ladder
##   field_hut   open shelter on four posts (farmers rest in the shade)

const SAIL_HUB := Vector3(0, 11.2, -1.55)
const WHEEL_HUB := Vector3(0, 2.3, 0)

static var _sail_res: Dictionary = {}


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	match kind:
		&"windmill": windmill(kit, v)
		&"water_wheel": water_wheel(kit, v)
		&"granary": granary(kit, v)
		&"field_hut": field_hut(kit, v)


static func windmill(kit: BuildingKit, v: int) -> void:
	var tim := EkStyle.timber(EkStyle.FARM)
	kit.box(Vector3(0, 0.6, 0), Vector3(4.6, 1.2, 4.6), EkStyle.base(EkStyle.FARM))
	# tapered octagonal timber tower
	kit.cylinder(Vector3(0, 1.2, 0), 9.0, 2.0, EkStyle.wall(EkStyle.FARM, v + 1), 8, true, 1.25)
	if kit.lod < 2:
		for k in 3:
			var y := 1.2 + 2.6 + k * 2.6
			var r := lerpf(2.0, 1.25, (y - 1.2) / 9.0) + 0.06
			kit.g().cylinder(Vector3(0, y, 0), Vector3(0, y + 0.18, 0), r, r, 8, kit.col(tim), 0)
		EkHomes.door(kit, Vector3(0, 1.2, -1.95), 1.0, 1.9, tim)
		EkHomes.window(kit, Vector3(0, 6.2, -1.62), 0.6, 0.7, tim, v % 2 == 0)
	# cap
	kit.cylinder(Vector3(0, 10.2, 0), 0.5, 1.6, tim, 8, true, 1.5)
	RoofsLite.hip(kit, Vector3(0, 10.7, 0.2), 2.4, 3.4, 1.4, EkStyle.roof_opts(EkStyle.FARM, v, {"overhang": 0.4, "horns": false}))
	kit.box(SAIL_HUB + Vector3(0, 0, 0.5), Vector3(0.5, 0.5, 1.4), tim, false)
	if kit.lod >= 2:
		sails(kit, SAIL_HUB, 0.3)


## The four sails around a hub (local XY plane at `hub`, facing -Z), rotated by `angle`.
static func sails(kit: BuildingKit, hub: Vector3, angle: float) -> void:
	var tim := EkStyle.timber(EkStyle.FARM)
	var cloth := Color(0.88, 0.82, 0.66).srgb_to_linear()
	for k in 4:
		var a := angle + TAU * k / 4.0
		var dir := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		kit.beam(hub, hub + dir * 7.2, 0.18, 0.18, tim)
		var g := kit.g(&"cloth") if kit.lod < 2 else kit.g()
		var p0 := hub + dir * 1.6
		var p1 := hub + dir * 7.0
		var s0 := side * 0.15
		var s1 := side * 1.35
		var n := Vector3(0, 0, -1)
		var i := g.vertex(p0 + s0, n, cloth, Vector2(0, 0))
		g.vertex(p1 + s0, n, cloth, Vector2(1, 0))
		g.vertex(p1 + s1, n, cloth, Vector2(1, 1))
		g.vertex(p0 + s1, n, cloth, Vector2(0, 1))
		g.quad(i, i + 1, i + 2, i + 3)
		g.quad(i, i + 3, i + 2, i + 1)
		if kit.lod == 0:
			kit.beam(p0 + s1, p1 + s1, 0.06, 0.06, tim)


static func water_wheel(kit: BuildingKit, v: int) -> void:
	var stone := EkStyle.base(EkStyle.LOWER)
	var tim := EkStyle.timber(EkStyle.FARM)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * 1.25, 1.35, 0), Vector3(0.6, 2.7, 1.4), stone, true)
		kit.beam(Vector3(sx * 1.25, 2.7, 0), Vector3(sx * 1.25, 3.1, 0), 0.4, 0.4, tim)
	kit.beam(Vector3(-1.6, WHEEL_HUB.y, 0), Vector3(1.6, WHEEL_HUB.y, 0), 0.22, 0.22, tim)
	# little mill house beside the wheel
	kit.box(Vector3(4.4, 1.5, 0), Vector3(4.0, 3.0, 4.0), EkStyle.wall(EkStyle.FARM, v))
	RoofsLite.gable(kit, Vector3(4.4, 3.0, 0), 4.0, 4.0, 1.6, EkStyle.roof_opts(EkStyle.FARM, v, {"overhang": 0.5}))
	if kit.lod < 2:
		EkHomes.door(kit, Vector3(4.4, 0.0, -2.0), 1.1, 2.0, tim)
	if kit.lod >= 2:
		wheel(kit, WHEEL_HUB, 0.0)


## The water wheel itself (local YZ plane, axle along X), rotated by `angle`.
static func wheel(kit: BuildingKit, hub: Vector3, angle: float) -> void:
	var tim := EkStyle.timber(EkStyle.FARM)
	var r := 1.9
	var n := 10 if kit.lod == 0 else 6
	for sx: float in [-0.5, 0.5]:
		for k in n:
			var a0 := angle + TAU * k / n
			var a1 := angle + TAU * (k + 1) / n
			kit.beam(hub + Vector3(sx, cos(a0) * r, sin(a0) * r), hub + Vector3(sx, cos(a1) * r, sin(a1) * r), 0.14, 0.14, tim)
	for k in n:
		var a := angle + TAU * k / n
		var p := hub + Vector3(0, cos(a) * r, sin(a) * r)
		kit.beam(hub, p, 0.08, 0.08, tim)
		kit.box_t(Transform3D(Basis(Vector3.RIGHT, -a), p), Vector3(1.0, 0.06, 0.5), tim, false)


static func granary(kit: BuildingKit, v: int) -> void:
	var tim := EkStyle.timber(EkStyle.FARM)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.cylinder(Vector3(sx * 1.6, 0, sz * 1.4), 1.6, 0.16, tim, 6, true)
			if kit.lod == 0:
				kit.g().cylinder(Vector3(sx * 1.6, 1.4, sz * 1.4), Vector3(sx * 1.6, 1.6, sz * 1.4), 0.36, 0.36, 8, kit.col(EkStyle.base(EkStyle.FARM)), 3)
	kit.box(Vector3(0, 1.7, 0), Vector3(3.8, 0.2, 3.4), tim, true)
	kit.box(Vector3(0, 2.9, 0), Vector3(3.4, 2.2, 3.0), EkStyle.wall(EkStyle.FARM, v + 2))
	RoofsLite.hip(kit, Vector3(0, 4.0, 0), 3.4, 3.0, 1.8, EkStyle.roof_opts(EkStyle.FARM, v + 1, {"overhang": 0.7}))
	if kit.lod < 2:
		kit.box(Vector3(0, 2.6, -1.52), Vector3(1.0, 1.4, 0.05), &"window", false)
		kit.beam(Vector3(0.2, 0, -2.5), Vector3(0.2, 1.75, -1.7), 0.08, 0.08, tim)
		kit.beam(Vector3(-0.2, 0, -2.5), Vector3(-0.2, 1.75, -1.7), 0.08, 0.08, tim)


static func field_hut(kit: BuildingKit, v: int) -> void:
	var tim := EkStyle.timber(EkStyle.FARM)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.beam(Vector3(sx * 1.4, 0, sz * 1.1), Vector3(sx * 1.4, 2.3, sz * 1.1), 0.12, 0.12, tim, true)
	RoofsLite.hip(kit, Vector3(0, 2.3, 0), 2.8, 2.2, 1.3, EkStyle.roof_opts(EkStyle.FARM, v, {"overhang": 0.5, "horns": false}))
	if kit.lod == 0:
		kit.box(Vector3(0, 0.4, 0.6), Vector3(2.2, 0.08, 0.6), tim, true)
		kit.g().cylinder(Vector3(-0.8, 0, -0.5), Vector3(-0.8, 0.5, -0.5), 0.25, 0.3, 7, kit.col(EkStyle.STRAW), 2)


# --- rotating parts (main thread) ---------------------------------------------------------------

## A spinning node for a windmill's sails (`kind` &"sails") or a water wheel (&"wheel") at
## `world` (the hub) with the piece yaw. Meshes are built once per kind (main thread).
static func spinner(kind: StringName, world: Vector3, yaw: float, origin: Vector3, seed: int) -> Node3D:
	if not _sail_res.has(kind):
		var kit := BuildingKit.new(NationPalette.get_palette(&"earth_kingdom"), 0, 7)
		if kind == &"sails":
			sails(kit, Vector3.ZERO, 0.0)
		else:
			wheel(kit, Vector3.ZERO, 0.0)
		_sail_res[kind] = kit.build()
	var res: KitResult = _sail_res[kind]
	var cfg := SettlementSettings.current()
	var root := EkSpinner.new()
	root.name = "Sails" if kind == &"sails" else "Wheel"
	root.axis = Vector3(0, 0, 1) if kind == &"sails" else Vector3(1, 0, 0)
	var rng := ContentHash.rng(seed)
	root.speed = rng.randf_range(0.35, 0.6) if kind == &"sails" else -rng.randf_range(0.8, 1.2)
	root.position = world - origin
	root.rotation.y = yaw
	var inst := res.instantiate({"name": "Mesh", "vis_end": float(cfg["lod1_end"]), "collision": false, "lights": false})
	root.add_child(inst)
	inst.rotation = Vector3(0, 0, rng.randf() * TAU) if kind == &"sails" else Vector3(rng.randf() * TAU, 0, 0)
	root.spin = inst
	return root
