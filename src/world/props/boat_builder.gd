class_name BoatBuilder
extends RefCounted
## Boats for docks, harbours and the ferry routes (BuildingKit-based, thread-safe). Models face
## -Z (bow) with the waterline at y = 0.
##   hull(kit, length, beam, depth, opts)   lofted wooden/hide hull with gunwale and deck
##   rowboat(kit, opts)  sampan(kit, opts)  kayak(kit, opts)
##   ferry(kit, opts)    passenger ferry: hull, deck, nation-styled cabin, mast + sail, lanterns
##   ferry_node(nation) -> Node3D           ready-made ferry for the world scene's ferry routes
##                                          (mesh + deck collision + lights; marker &"deck").

const SECTIONS := 9


## Lofted hull: U sections along the length, pointed bow (-Z) and transom stern (+Z).
## opts: role (hull colour), trim_role (gunwale), rise (bow/stern sheer), deck (bool).
static func hull(kit: BuildingKit, length: float, beam: float, depth: float, opts: Dictionary = {}) -> void:
	var g := kit.g()
	var c_hull := kit.col(opts.get("role", &"wood"))
	var c_low := kit.col(opts.get("bottom_role", &"wood_dark"))
	var rise := float(opts.get("rise", depth * 0.5))
	var free := float(opts.get("freeboard", depth * 0.6))
	var pts := 5        # per half section (keel -> gunwale)
	var rows: Array = []
	for i in SECTIONS + 1:
		var s := float(i) / SECTIONS             # 0 bow .. 1 stern
		var z := lerpf(-length * 0.5, length * 0.5, s)
		var wfac := sin(clampf(s * 1.15, 0.0, 1.0) * PI * 0.5) * (1.0 - 0.25 * pow(s, 4.0))
		if s > 0.85:
			wfac = maxf(wfac, 0.75)
		var hw := beam * 0.5 * maxf(wfac, 0.02)
		var sheer := rise * pow(absf(s - 0.55) / 0.55, 2.0)
		var top := free + sheer
		var keel := -(depth - free) * (0.4 + 0.6 * sin(s * PI))
		var sec: Array = []
		for k in pts * 2 + 1:
			var u := float(k) / (pts * 2) * 2.0 - 1.0          # -1 port gunwale .. 0 keel .. 1 starboard
			var a := absf(u)
			var x := signf(u) * hw * sin(a * PI * 0.5)
			var y := lerpf(keel, top, 1.0 - cos(a * PI * 0.5))
			sec.append(Vector3(x, y, z))
		rows.append(sec)
	var base := g.vertex_count()
	var per := pts * 2 + 1
	for i in rows.size():
		for k in per:
			var p: Vector3 = rows[i][k]
			var n := Vector3(p.x, p.y - 0.2, 0.0).normalized()
			g.vertex(p, n, c_low.lerp(c_hull, clampf((p.y + depth * 0.3) / (depth * 0.8), 0.0, 1.0)))
	for i in rows.size() - 1:
		for k in per - 1:
			var a := base + i * per + k
			var b := base + (i + 1) * per + k
			g.quad(a, a + 1, b + 1, b)
	# transom (stern) cap
	var last: Array = rows[rows.size() - 1]
	for k in per - 2:
		g.flat_tri(last[0], last[k + 1], last[k + 2], c_hull)
	# gunwale rails + deck
	var trim := kit.col(opts.get("trim_role", &"trim"))
	for side: int in [0, per - 1]:
		var line := PackedVector3Array()
		for i in rows.size():
			line.append((rows[i][side] as Vector3) + Vector3(0, 0.04, 0))
		var radii := PackedFloat32Array()
		radii.resize(line.size())
		radii.fill(0.06)
		g.tube(line, radii, 4, trim)
	if opts.get("deck", true):
		var dy := free * 0.75
		for i in rows.size() - 1:
			var p0: Vector3 = rows[i][0]
			var p1: Vector3 = rows[i + 1][0]
			var q0: Vector3 = rows[i][per - 1]
			var q1: Vector3 = rows[i + 1][per - 1]
			var shrink := 0.9
			g.flat_quad(Vector3(p0.x * shrink, dy, p0.z), Vector3(p1.x * shrink, dy, p1.z), Vector3(q1.x * shrink, dy, q1.z), Vector3(q0.x * shrink, dy, q0.z), kit.col(&"floor"))
		kit.collide_box(Vector3(0, dy * 0.5, length * 0.05), Vector3(beam * 0.8, maxf(dy, 0.3), length * 0.8))


static func rowboat(kit: BuildingKit, opts: Dictionary = {}) -> void:
	var l := float(opts.get("length", 4.2))
	hull(kit, l, 1.4, 0.7, {"deck": false, "rise": 0.25})
	for z: float in [-0.5, 0.6]:
		kit.box(Vector3(0, 0.25, z), Vector3(1.15, 0.06, 0.28), &"wood_dark", false)
	for s: float in [-1.0, 1.0]:
		kit.beam(Vector3(s * 0.5, 0.35, 0.1), Vector3(s * 1.6, -0.1, 0.6), 0.06, 0.06, &"wood")


static func sampan(kit: BuildingKit, opts: Dictionary = {}) -> void:
	var l := float(opts.get("length", 6.5))
	hull(kit, l, 1.8, 0.9, {"rise": 0.4})
	# woven canopy
	var ring := PackedVector3Array()
	for k in 9:
		var a := PI * float(k) / 8.0
		ring.append(Vector3(cos(a) * 0.85, 0.55 + sin(a) * 0.95, 0.0))
	for z: float in [-0.8, 0.0, 0.8]:
		for k in 8:
			kit.beam(ring[k] + Vector3(0, 0, z), ring[k + 1] + Vector3(0, 0, z), 0.08, 0.12, &"cloth_alt")
	var g := kit.g()
	for k in 8:
		g.flat_quad(ring[k] + Vector3(0, 0, -0.85), ring[k + 1] + Vector3(0, 0, -0.85), ring[k + 1] + Vector3(0, 0, 0.85), ring[k] + Vector3(0, 0, 0.85), kit.col(&"cloth_alt"))
		g.flat_quad(ring[k + 1] + Vector3(0, 0, -0.85), ring[k] + Vector3(0, 0, -0.85), ring[k] + Vector3(0, 0, 0.85), ring[k + 1] + Vector3(0, 0, 0.85), kit.col(&"wood_dark"))
	kit.beam(Vector3(0, 0.6, l * 0.42), Vector3(0, 1.2, l * 0.65), 0.07, 0.07, &"wood")


static func kayak(kit: BuildingKit, opts: Dictionary = {}) -> void:
	var l := float(opts.get("length", 4.6))
	hull(kit, l, 0.7, 0.45, {"rise": 0.18, "role": &"wall_alt", "bottom_role": &"trim", "trim_role": &"trim"})
	kit.g().cylinder(Vector3(0, 0.25, 0.1), Vector3(0, 0.32, 0.1), 0.3, 0.32, 8, kit.col(&"trim"), 2)
	kit.beam(Vector3(-1.2, 0.4, 0.1), Vector3(1.2, 0.4, 0.1), 0.05, 0.05, &"wood")


## Passenger ferry (~14 m) with a cabin styled by the kit's nation.
static func ferry(kit: BuildingKit, opts: Dictionary = {}) -> void:
	var l := float(opts.get("length", 14.0))
	var beam := float(opts.get("beam", 4.6))
	hull(kit, l, beam, 1.9, {"rise": 0.9})
	var dy := 1.9 * 0.6 * 0.75
	kit.mark(&"deck", Transform3D(Basis(), Vector3(0, dy, 0)))
	# cabin
	var cw := beam * 0.62
	var cd := l * 0.32
	var cz := l * 0.12
	kit.box(Vector3(0, dy + 1.1, cz), Vector3(cw, 2.2, cd), &"wall", true)
	if kit.lod < 2:
		for s: float in [-1.0, 1.0]:
			for k in 3:
				kit.window(Transform3D(Basis(Vector3.UP, s * PI * 0.5), Vector3(s * cw * 0.5, dy + 1.0, cz + (k - 1) * cd * 0.3)), 0.7, 0.6, {"thickness": 0.1})
	match kit.palette.nation:
		&"air_nomads":
			KitRoofs.cone(kit, Vector3(0, dy + 2.2, cz), cd * 0.55, 1.6, {"sides": 10})
		&"water_tribe":
			KitRoofs.flat(kit, Vector3(0, dy + 2.2, cz), cw, cd, {"parapet": false})
		_:
			KitRoofs.hip(kit, Vector3(0, dy + 2.2, cz), cw, cd, 1.0, {"overhang": 0.5, "curve": 0.3, "ornaments": kit.lod == 0})
	# mast + sail (cloth)
	var mz := -l * 0.18
	kit.cylinder(Vector3(0, dy, mz), 7.5, 0.13, &"wood_dark", 6, true, 0.08)
	if kit.lod < 2:
		kit.beam(Vector3(-1.6, dy + 6.8, mz), Vector3(1.6, dy + 6.8, mz), 0.08, 0.08, &"wood")
		kit.banner(Transform3D(Basis(), Vector3(0, dy + 6.75, mz - 0.05)), 3.0, 4.6, {"role": &"cloth_alt", "alt_role": &"cloth", "rod": false, "tail": false})
		kit.railing(PackedVector3Array([Vector3(-beam * 0.42, dy, -l * 0.35), Vector3(-beam * 0.45, dy, l * 0.4)]), 0.8, {"spacing": 1.5, "collide": true})
		kit.railing(PackedVector3Array([Vector3(beam * 0.42, dy, -l * 0.35), Vector3(beam * 0.45, dy, l * 0.4)]), 0.8, {"spacing": 1.5, "collide": true})
		for z: float in [-l * 0.4, l * 0.42]:
			kit.lantern(Vector3(0, dy + 1.4, z), {"style": &"paper", "range": 8.0})


## Ready-made ferry node for the world scene (nation palette). Main thread.
static func ferry_node(nation: StringName, lod: int = 0) -> Node3D:
	NationPalette.prepare_materials()
	var kit := BuildingKit.new(NationPalette.get_palette(nation), lod, ContentHash.hash_name(String(nation)))
	ferry(kit)
	var res := kit.build()
	var n := res.instantiate({"name": "Ferry"})
	n.set_meta(&"deck", res.markers.get(&"deck", Transform3D()))
	return n
