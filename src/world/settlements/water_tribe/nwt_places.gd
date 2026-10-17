class_name NwtPlaces
extends RefCounted
## Enterable interiors and special places of the Water Tribe (BuildingKit recipes, thread-safe;
## origin = ground centre, -Z = entrance). Interiors have real door openings, floors, furniture
## and interior-flagged lights (they shine by day).
##   healer_hut     domed healing house: ring of ice walls, healing pool, cots, herb shelves
##   training_hall  waterbending hall: columns, sparring circle, water basins, master's dais
##   family_home    snow-block family house: fire pit, sleeping furs, table, shelves, tools
##   oasis          the Spirit Oasis enclosure: circular wall with a gate, lawn, pond rim,
##                  stepping-stone path, stone lanterns (plants, koi, light: builder extras)
##   canal_fall     frame of a canal waterfall through a tier wall: pylons, lip sill, wet chute
##                  (the animated water sheets are added by NwtBuilder.piece_payload)

const OASIS_GREEN := Color(0.27, 0.50, 0.22)


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"healer_hut": healer_hut(kit, spec)
		&"training_hall": training_hall(kit, spec)
		&"family_home": family_home(kit, spec)
		&"oasis": oasis(kit, spec)
		&"canal_fall": canal_fall(kit, spec)


static func _interior_light(kit: BuildingKit, pos: Vector3, color: Color, range_m: float, energy: float) -> void:
	kit.lights.append({"position": kit.xform * pos, "color": color, "range": range_m, "energy": energy, "priority": 3, "interior": true})


## Ring of wall segments (n-gon, radius r) with an opening on the segment facing -Z.
static func _ring_walls(kit: BuildingKit, r: float, h: float, th: float, n: int, y: float, door: Dictionary, opts: Dictionary) -> void:
	for i in n:
		var a0 := -PI * 0.5 + TAU * (i - 0.5) / n
		var a1 := -PI * 0.5 + TAU * (i + 0.5) / n
		var p0 := Vector3(cos(a0) * r, y, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, y, sin(a1) * r)
		var o := opts.duplicate()
		if i == 0 and not door.is_empty():
			o["openings"] = [door]
		elif i % 3 == 1 and opts.get("windows", false):
			o["openings"] = [{"t": 0.5, "width": 0.7, "height": 0.9, "kind": &"window", "sill": 1.4}]
		# walls run p1 -> p0 so the outside faces outward
		kit.wall(p1, p0, h, th, o)


static func healer_hut(kit: BuildingKit, _spec: Dictionary) -> void:
	var r := 6.5
	var h := 4.0
	var y := 0.3
	# foundation drum: its top stays under the floor slab (coplanar tops z-fight)
	kit.cylinder(Vector3(0, -1.2, 0), 1.44, r + 0.9, &"base", 18, false)
	var floor_ring := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18.0
		floor_ring.append(Vector2(cos(a), sin(a)) * (r + 0.8))
	kit.slab(floor_ring, -0.2, y, &"base", true, &"floor")
	var door := {"t": 0.5, "width": 1.8, "height": 2.6, "kind": &"door", "leaf": &"none", "frame_role": &"trim"}
	_ring_walls(kit, r, h, 0.6, 14, y, door, {"role": &"wall", "cap": false, "windows": true, "base_role": &"wall_alt"})
	kit.cylinder(Vector3(0, y + h - 0.35, 0), 0.35, r + 0.35, &"trim", 18, false)
	KitRoofs.dome(kit, Vector3(0, y + h, 0), r + 0.3, {"squash": 0.78, "role": NwtStyle.dome(0), "rib_role": &"wall_alt", "slot": &"ice",
		"block_lines": true, "finial": true, "finial_role": &"trim"})
	# the dome seen from inside (the roof is single-sided): an inner shell in the interior colour
	if kit.lod < 2:
		KitX.inner_dome(kit, Vector3(0, y + h - 0.3, 0), r - 0.25, 0.74, kit.col(&"interior").lerp(NwtStyle.dome(0), 0.35))
	# entrance vestibule
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * 1.45, y + 1.4, -r - 0.9), Vector3(0.5, 2.8, 2.0), &"wall")
	kit.box(Vector3(0, y + 3.0, -r - 0.9), Vector3(3.4, 0.5, 2.2), &"wall_alt")
	if kit.lod < 2:
		kit.box(Vector3(0, y + 2.7, -r - 1.95), Vector3(3.2, 0.25, 0.3), NwtStyle.navy(), false)
		KitX.banner(kit, Transform3D(Basis(), Vector3(0, y + 3.25, -r - 2.08)), 1.1, 1.2, &"cloth_alt", &"cloth", &"moon")
		KitX.lantern(kit, Vector3(1.9, y, -r - 2.4), {"style": &"ice", "height": 1.5, "range": 7.0})
	if kit.lod == 0:
		# healing pool: a ring of ice blocks around softly glowing water
		for k in 16:
			var a := TAU * k / 16.0
			kit.box_t(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 1.85, y + 0.22, sin(a) * 1.85)), Vector3(0.42, 0.44, 0.78), &"wall_alt", true)
		var gw := kit.g(&"glow")
		gw.uv = Vector2(0, 0.15)
		gw.cylinder(Vector3(0, y + 0.18, 0), Vector3(0, y + 0.24, 0), 1.72, 1.72, 18, Color(0.40, 0.78, 1.0) * 0.7, 2)
		# a hanging lamp over the pool
		kit.g().cylinder(Vector3(0, y + h + 2.0, 0), Vector3(0, y + 3.55, 0), 0.015, 0.015, 3, kit.col(&"metal"), 0)
		var lamp := kit.g(&"glow")
		lamp.uv = Vector2(0, 0.6)
		lamp.blob(Vector3(0, y + 3.35, 0), 0.17, 1, Color(1.0, 0.86, 0.62), null, 0.0, Vector3(1, 1.2, 1))
		kit.g().cylinder(Vector3(0, y + 3.5, 0), Vector3(0, y + 3.58, 0), 0.2, 0.13, 8, kit.col(&"metal"), 2)
		# cots with furs around the pool
		for k in 4:
			var a := TAU * (k + 0.5) / 4.0 + PI * 0.5
			var c := Vector3(cos(a) * 3.9, y, sin(a) * 3.9)
			var yaw := atan2(c.x, c.z)
			kit.box_t(Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, 0.25, 0)), Vector3(0.9, 0.5, 2.0), &"wood", false)
			kit.box_t(Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, 0.55, 0)), Vector3(0.95, 0.12, 2.0), Color(0.86, 0.84, 0.78).srgb_to_linear(), false)
			kit.box_t(Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, 0.66, 0.7)), Vector3(0.6, 0.15, 0.4), &"cloth", false)
			kit.box_t(Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, 0.63, -0.3)), Vector3(1.05, 0.1, 0.9), Color(0.55, 0.43, 0.33).srgb_to_linear(), false)
		# patterned rugs on the floor
		for k in 3:
			var a := TAU * k / 3.0 + 0.4
			var c := Vector3(cos(a) * 2.6, y + 0.02, sin(a) * 2.6)
			kit.box_t(Transform3D(Basis(Vector3.UP, a), c), Vector3(1.6, 0.03, 1.0), &"cloth", false)
			kit.box_t(Transform3D(Basis(Vector3.UP, a), c + Vector3(0, 0.01, 0)), Vector3(1.2, 0.03, 0.6), &"cloth_alt", false)
		# herb shelves with jars on the back wall, drying herbs on strings, tapestries
		for sx: float in [-1.0, 1.0]:
			var sc := Vector3(sx * 2.2, y, r - 1.0)
			kit.box(sc + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.4), &"wood_dark", true)
			for row in 2:
				for j in 3:
					var p := sc + Vector3(-0.6 + j * 0.6, 0.65 + row * 0.75, -0.05)
					kit.g().cylinder(p, p + Vector3(0, 0.3, 0), 0.12, 0.09, 6, kit.col(&"accent" if (j + row) % 2 else &"stone"), 2)
			KitX.banner(kit, Transform3D(Basis(Vector3.UP, sx * 0.9 + PI), Vector3(sx * (r - 0.75) * 0.78, y + h - 0.6, (r - 0.75) * 0.62 - 1.0)), 1.0, 2.2, &"cloth", &"cloth_alt", &"moon")
		var rope := PackedVector3Array([Vector3(-3.2, y + h - 0.5, 1.6), Vector3(0, y + h - 0.85, 1.9), Vector3(3.2, y + h - 0.5, 1.6)])
		var rr := PackedFloat32Array([0.015, 0.015, 0.015])
		kit.g().tube(rope, rr, 3, kit.col(&"wood_dark"))
		for k in 7:
			var t := (k + 0.5) / 7.0
			var hp := Vector3(lerpf(-3.0, 3.0, t), y + h - 0.65 - sin(t * PI) * 0.33 - 0.25, 1.6 + sin(t * PI) * 0.3)
			kit.g().blob(hp, 0.11, 0, Color(0.40, 0.55, 0.28).srgb_to_linear(), null, 0.0, Vector3(0.6, 2.0, 0.6))
		KitX.lantern(kit, Vector3(-3.4, y, -2.0), {"style": &"post", "height": 1.3, "light": false})
	_interior_light(kit, Vector3(0, y + h - 0.8, 0), Color(0.80, 0.90, 1.0), 9.0, 1.1)
	_interior_light(kit, Vector3(0, y + 1.0, 0), Color(0.55, 0.85, 1.0), 4.0, 0.8)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -r - 3.2)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y, 0)))
	kit.mark(&"healer", Transform3D(Basis(Vector3.UP, PI), Vector3(0, y, 2.4)))


static func training_hall(kit: BuildingKit, _spec: Dictionary) -> void:
	var w := 22.0
	var d := 16.0
	var h := 6.5
	var y := 0.3
	var hx := w * 0.5
	var hz := d * 0.5
	kit.box(Vector3(0, -0.5, 0), Vector3(w + 1.2, 1.6, d + 1.2), &"base", false)
	kit.box(Vector3(0, y - 0.05, 0), Vector3(w - 0.2, 0.1, d - 0.2), &"floor", true)
	var wopts := {"role": &"wall", "cap_role": &"trim", "base_role": &"wall_alt"}
	kit.wall(Vector3(hx, y, -hz), Vector3(-hx, y, -hz), h, 0.8, wopts.merged({"openings": [
		{"t": 0.5, "width": 3.4, "height": 4.0, "kind": &"gate", "leaf": &"none", "frame_role": &"trim"},
		{"t": 0.17, "width": 1.0, "height": 1.6, "kind": &"window", "sill": 2.6},
		{"t": 0.83, "width": 1.0, "height": 1.6, "kind": &"window", "sill": 2.6}]}, true))
	var side_win := []
	for t in [0.2, 0.5, 0.8]:
		side_win.append({"t": t, "width": 0.8, "height": 1.8, "kind": &"window", "sill": 3.0})
	kit.wall(Vector3(hx, y, hz), Vector3(hx, y, -hz), h, 0.8, wopts.merged({"openings": side_win}, true))
	kit.wall(Vector3(-hx, y, -hz), Vector3(-hx, y, hz), h, 0.8, wopts.merged({"openings": side_win}, true))
	kit.wall(Vector3(-hx, y, hz), Vector3(hx, y, hz), h, 0.8, wopts)
	KitRoofs.flat(kit, Vector3(0, y + h, 0), w, d, {"role": &"wall_alt", "parapet": true, "parapet_role": &"wall", "icicles": true})
	if kit.lod < 2:
		kit.box(Vector3(0, y + h - 0.12, 0), Vector3(w - 1.0, 0.1, d - 1.0), &"interior", false)
		kit.cylinder(Vector3(0, y + h + 0.35, 0), 1.2, 3.2, &"wall_alt", 16, true)
	KitRoofs.dome(kit, Vector3(0, y + h + 1.55, 0), 3.3, {"squash": 0.8, "role": NwtStyle.dome(0), "rib_role": &"wall_alt", "slot": &"ice",
		"finial": kit.lod < 2, "finial_role": &"trim"})
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 3.6, y + h - 0.4, -hz - 0.45)), 1.1, 3.6)
			kit.push(Transform3D(Basis(), Vector3(sx * 4.2, 0.0, -hz - 3.0)))
			NwtProps.brazier(kit, 0)
			kit.pop()
		KitX.emblem_water(kit, Vector3(0, y + 5.4, -hz - 0.42), 1.4, &"trim", 0.02)
	if kit.lod == 0:
		# ice columns
		for sx: float in [-1.0, 1.0]:
			for k in 4:
				kit.column(Vector3(sx * (hx - 2.6), y, lerpf(-hz + 3.0, hz - 3.0, k / 3.0)), h - 0.2, 0.4, &"ice", &"ice", &"wall_alt")
		# sparring circle inlay
		var ring := PackedVector2Array()
		var inner := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			ring.append(Vector2(cos(a), sin(a)) * 4.6)
			inner.append(Vector2(cos(a), sin(a)) * 4.2)
		kit.slab(ring, y, y + 0.03, &"trim", false)
		kit.slab(inner, y, y + 0.045, &"wall_alt", false)
		KitX.water_inlay(kit, Vector3(0, y + 0.05, -0.5), 3.0, &"trim")
		# water basins along the side walls
		for sx: float in [-1.0, 1.0]:
			var bc := Vector3(sx * (hx - 1.2), y, 0)
			kit.box(bc + Vector3(0, 0.3, 0), Vector3(1.4, 0.6, d - 5.0), &"wall_alt", true)
			var gw := kit.g(&"glow")
			gw.uv = Vector2(0, 0.1)
			gw.box(Transform3D(Basis(), bc + Vector3(0, 0.58, 0)), Vector3(1.0, 0.04, d - 5.4), Color(0.4, 0.75, 1.0) * 0.55)
		# master's dais with cushion, banners behind
		kit.box(Vector3(0, y + 0.25, hz - 2.2), Vector3(6.0, 0.5, 3.0), &"wall_alt", true)
		kit.stairs(Vector3(0, y, hz - 4.6), Vector3(0, y + 0.5, hz - 3.7), 3.0, {"role": &"wall_alt"})
		kit.box(Vector3(0, y + 0.62, hz - 2.0), Vector3(1.2, 0.25, 1.2), &"cloth", false)
		for sx: float in [-1.0, 0.0, 1.0]:
			KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI), Vector3(sx * 2.6, y + h - 0.7, hz - 0.45)), 1.2, 4.0)
		# practice targets: ice pillars
		for k in 3:
			kit.cylinder(Vector3(-4.0 + k * 4.0, y, -hz + 3.2), 1.8, 0.35, &"ice", 6, true, 0.25, &"ice")
	for k in 3:
		_interior_light(kit, Vector3(-6.0 + k * 6.0, y + h - 1.2, 0), Color(1.0, 0.88, 0.70), 11.0, 1.3)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hz - 1.8)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y, 0)))
	kit.mark(&"trainer", Transform3D(Basis(Vector3.UP, PI), Vector3(0, y + 0.5, hz - 2.0)))


static func family_home(kit: BuildingKit, _spec: Dictionary) -> void:
	var w := 10.0
	var d := 8.0
	var h := 3.6
	var y := 0.3
	var hx := w * 0.5
	var hz := d * 0.5
	kit.box(Vector3(0, -0.5, 0), Vector3(w + 0.6, 1.6, d + 0.6), &"base", false)
	kit.box(Vector3(0, y - 0.05, 0), Vector3(w - 0.2, 0.1, d - 0.2), &"floor", true)
	var wopts := {"role": &"wall", "cap_role": &"trim"}
	kit.wall(Vector3(hx, y, -hz), Vector3(-hx, y, -hz), h, 0.6, wopts.merged({"openings": [
		{"t": 0.5, "width": 1.5, "height": 2.4, "kind": &"door", "leaf": &"none", "frame_role": &"trim"},
		{"t": 0.18, "width": 0.8, "height": 0.9, "kind": &"window", "sill": 1.3},
		{"t": 0.82, "width": 0.8, "height": 0.9, "kind": &"window", "sill": 1.3}]}, true))
	kit.wall(Vector3(hx, y, hz), Vector3(hx, y, -hz), h, 0.6, wopts.merged({"openings": [{"t": 0.5, "width": 0.8, "height": 0.9, "kind": &"window", "sill": 1.3}]}, true))
	kit.wall(Vector3(-hx, y, -hz), Vector3(-hx, y, hz), h, 0.6, wopts)
	kit.wall(Vector3(-hx, y, hz), Vector3(hx, y, hz), h, 0.6, wopts)
	KitRoofs.flat(kit, Vector3(0, y + h, 0), w, d, {"role": &"wall_alt", "parapet": true, "parapet_role": &"wall", "icicles": true})
	if kit.lod < 2:
		kit.box(Vector3(0, y + h - 0.1, 0), Vector3(w - 0.8, 0.1, d - 0.8), &"interior", false)
		kit.cylinder(Vector3(1.6, y + h + 0.35, 1.0), 0.6, 1.6, &"wall_alt", 14, true)
	KitRoofs.dome(kit, Vector3(1.6, y + h + 0.95, 1.0), 1.7, {"squash": 0.85, "role": NwtStyle.dome(0), "rib_role": &"wall_alt", "slot": &"ice",
		"finial": false})
	if kit.lod < 2:
		KitX.banner(kit, Transform3D(Basis(), Vector3(-2.8, y + h - 0.3, -hz - 0.35)), 0.7, 2.0)
	if kit.lod == 0:
		# fire pit with a stone ring + cooking pot
		for k in 8:
			var a := TAU * k / 8.0
			kit.g().blob(Vector3(cos(a) * 0.75, y + 0.12, sin(a) * 0.75 + 0.6), 0.18, 0, kit.col(&"stone_dark"), null, 0.0, Vector3(1, 0.7, 1))
		var gb := kit.g(&"glow")
		gb.uv = Vector2(0, 1)
		gb.cone(Vector3(0, y + 0.05, 0.6), Vector3(0, y + 0.75, 0.6), 0.4, 6, Color(1.0, 0.55, 0.2))
		if kit.lod == 0:
			kit.add_fire(Vector3(0, y + 0.05, 0.6), &"campfire", 0.45)
		kit.beam(Vector3(-0.8, y, 0.6), Vector3(0, y + 1.6, 0.6), 0.05, 0.05, &"wood")
		kit.beam(Vector3(0.8, y, 0.6), Vector3(0, y + 1.6, 0.6), 0.05, 0.05, &"wood")
		kit.g().cylinder(Vector3(0, y + 0.9, 0.6), Vector3(0, y + 1.25, 0.6), 0.25, 0.3, 8, kit.col(&"metal"), 1)
		# sleeping furs along the back wall
		for k in 3:
			var c := Vector3(-3.0 + k * 2.4, y + 0.12, hz - 1.0)
			kit.box(c, Vector3(1.8, 0.24, 1.3), Color(0.82, 0.78, 0.70).srgb_to_linear() if k % 2 == 0 else Color(0.55, 0.45, 0.36).srgb_to_linear(), false)
		# low table, shelf with pots, rug, spears and a paddle on the wall
		kit.box(Vector3(-2.6, y + 0.3, -1.2), Vector3(1.4, 0.08, 0.9), &"wood", false)
		kit.box(Vector3(-2.6, y + 0.13, -1.2), Vector3(1.2, 0.26, 0.7), &"wood_dark", false)
		kit.box(Vector3(hx - 0.55, y + 0.9, 0.0), Vector3(0.5, 1.8, 2.4), &"wood_dark", true)
		for j in 3:
			kit.g().cylinder(Vector3(hx - 0.55, y + 1.25, -0.8 + j * 0.8), Vector3(hx - 0.55, y + 1.55, -0.8 + j * 0.8), 0.15, 0.12, 6, kit.col(&"stone"), 2)
		kit.box(Vector3(0.8, y + 0.02, -1.6), Vector3(2.6, 0.04, 1.6), &"cloth", false)
		for k in 2:
			kit.beam(Vector3(-hx + 0.4, y + 0.4, -1.5 + k * 0.4), Vector3(-hx + 0.4, y + 2.6, -1.3 + k * 0.4), 0.05, 0.05, &"wood")
		kit.box(Vector3(-hx + 0.42, y + 1.6, 1.2), Vector3(0.06, 1.8, 0.25), &"wood", false)
	_interior_light(kit, Vector3(0, y + 1.4, 0.6), Color(1.0, 0.70, 0.40), 8.0, 1.4)
	_interior_light(kit, Vector3(-2.5, y + h - 0.8, -1.5), Color(1.0, 0.85, 0.65), 6.0, 0.7)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hz - 1.2)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y, 0)))
	kit.mark(&"hearth", Transform3D(Basis(), Vector3(0, y, 0.6)))


## Spirit Oasis enclosure (origin = pond centre on the oasis floor, -Z = gate). spec: r (wall
## radius), pond (pond radius), y_pond (water level relative to the origin).
static func oasis(kit: BuildingKit, spec: Dictionary) -> void:
	var R := float(spec.get("r", 33.0))
	var pond := float(spec.get("pond", 10.5))
	var n := 24 if kit.lod == 0 else 14
	var gate := {"t": 0.5, "width": 4.0, "height": 4.6, "kind": &"gate", "leaf": &"none", "frame_role": &"trim"}
	_ring_walls(kit, R, 5.5, 1.2, n, -1.0, gate, {"role": &"wall", "cap_role": &"trim", "crenels": {"width": 0.9, "gap": 0.6, "height": 0.8}})
	if kit.lod >= 2:
		return
	# pylons with spires flanking the gate
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * 3.4, 0, -R + 0.2)
		kit.box(p + Vector3(0, 3.5, 0), Vector3(1.6, 7.0, 2.2), &"wall_alt", true)
		KitRoofs.cone(kit, p + Vector3(0, 7.0, 0), 1.1, 4.0, {"role": NwtStyle.spire(0), "alt_role": NwtStyle.spire(1), "slot": &"ice", "flare": 0.1,
			"trim_role": &"trim", "finial_role": &"trim", "sides": 10})
		if kit.lod == 0:
			KitX.banner(kit, Transform3D(Basis(), Vector3(p.x, 6.2, p.z - 1.15)), 1.0, 3.2)
	# lawn (green ring), pond rim, path
	var green := OASIS_GREEN.srgb_to_linear()
	var nl := 32 if kit.lod == 0 else 16
	var g := kit.g()
	for i in nl:
		var a0 := TAU * i / nl
		var a1 := TAU * (i + 1) / nl
		for k in 3:
			var r0 := lerpf(pond + 1.2, R - 0.6, k / 3.0)
			var r1 := lerpf(pond + 1.2, R - 0.6, (k + 1) / 3.0)
			var c := green * (0.92 + 0.12 * ((i * 7 + k * 3) % 5) / 4.0)
			g.flat_quad(Vector3(cos(a0) * r0, 0.06, sin(a0) * r0), Vector3(cos(a1) * r0, 0.06, sin(a1) * r0),
					Vector3(cos(a1) * r1, 0.06, sin(a1) * r1), Vector3(cos(a0) * r1, 0.06, sin(a0) * r1), c)
	# lush grass tufts and flowers (kit-built: the oasis stays green under the arctic snow cover)
	if kit.lod == 0:
		var grng := ContentHash.rng(ContentHash.hash_name("oasis_grass"))
		for k in 420:
			var a := grng.randf() * TAU
			var rr := sqrt(grng.randf_range(pow(pond + 1.4, 2.0), pow(R - 1.4, 2.0)))
			var p := Vector3(cos(a) * rr, 0.06, sin(a) * rr)
			if absf(p.x) < 1.8 and p.z < -pond:
				continue
			KitX.grass_tuft(kit, p, grng.randf_range(0.35, 0.75), green * grng.randf_range(0.85, 1.25), grng)
			if k % 9 == 0:
				var fc: Color = [Color(1.0, 0.95, 0.85), Color(0.95, 0.55, 0.75), Color(0.75, 0.70, 1.0), Color(1.0, 0.85, 0.35)][k % 4]
				g.cylinder(p, p + Vector3(0, 0.45, 0), 0.012, 0.012, 3, green * 0.8, 0)
				g.blob(p + Vector3(0, 0.5, 0), 0.07, 0, fc.srgb_to_linear())
	# rim stones around the pond
	var rim := 28 if kit.lod == 0 else 12
	for i in rim:
		var a := TAU * i / rim
		var p := Vector3(cos(a) * (pond + 0.6), 0.05, sin(a) * (pond + 0.6))
		g.blob(p, 0.55, 0 if kit.lod > 0 else 1, kit.col(&"stone"), kit.rng, 0.2, Vector3(1.2, 0.55, 1.0), Vector3.INF, 0.0, kit.col(&"stone_dark"), Vector2.ZERO, true)
	if kit.lod == 0:
		# stepping stones from the gate to the pond
		for k in 9:
			var z := lerpf(-R + 2.5, -pond - 2.0, k / 8.0)
			var x := sin(k * 0.9) * 1.2
			g.cylinder(Vector3(x, 0.0, z), Vector3(x, 0.12, z), 0.7, 0.65, 8, kit.col(&"stone"), 2)
		# stone lanterns around the pond
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			KitX.lantern(kit, Vector3(cos(a) * (pond + 3.0), 0.0, sin(a) * (pond + 3.0)), {"style": &"stone", "height": 1.4,
				"light": false, "color": Color(1.0, 0.8, 0.5)})
		# a low wooden bench and an ice shrine facing the pond
		kit.box(Vector3(-pond - 5.0, 0.4, 3.0), Vector3(0.6, 0.12, 2.4), &"wood", false)
		kit.box(Vector3(0, 0.6, pond + 6.0), Vector3(2.2, 1.2, 1.4), &"wall_alt", true)
		KitRoofs.dome(kit, Vector3(0, 1.2, pond + 6.0), 1.0, {"squash": 0.9, "role": NwtStyle.dome(0), "slot": &"ice", "finial": true, "finial_role": &"trim"})
	kit.mark(&"gate", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -R - 2.0)))


## Canal waterfall frame through a tier wall. Origin = lip centre at the upper water level,
## -Z = downstream. spec: W (canal width), drop (upper level - lower level), H (top above the
## lip), lower (lower ground above the lower water), bed (lower canal bed below lower water).
static func canal_fall(kit: BuildingKit, spec: Dictionary) -> void:
	var W := float(spec.get("W", 9.0))
	var drop := float(spec.get("drop", 14.2))
	var H := float(spec.get("H", 1.8))
	var bed := float(spec.get("bed", 3.0))
	var bottom := -drop - bed - 0.5
	# wet chute wall behind the falling sheet (darker, slick)
	kit.box(Vector3(0, (bottom - 0.2) * 0.5, 1.4), Vector3(W + 0.2, -bottom - 0.2, 2.8), &"stone_dark")
	kit.box(Vector3(0, -0.15, -0.2), Vector3(W + 0.4, 0.3, 0.8), &"trim", false)
	# pylons on both banks
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (W * 0.5 + 1.6)
		kit.box(Vector3(x, (bottom + H + 3.0) * 0.5, 0.8), Vector3(3.2, H + 3.0 - bottom, 5.6), &"wall_alt", true)
		if kit.lod < 2:
			kit.box(Vector3(x, H + 3.2, 0.8), Vector3(3.6, 0.4, 6.0), &"trim", false)
			kit.box(Vector3(x, -drop + 0.6, 0.6), Vector3(3.6, 1.6, 6.2), &"base", false)
		KitRoofs.cone(kit, Vector3(x, H + 3.4, 0.8), 1.7, 6.5, {"role": NwtStyle.spire(0), "alt_role": NwtStyle.spire(1), "slot": &"ice", "flare": 0.1,
			"trim_role": &"trim", "finial_role": &"trim", "sides": 12})
		if kit.lod == 0:
			KitX.banner(kit, Transform3D(Basis(), Vector3(x, H + 2.6, -2.05)), 1.4, minf(drop * 0.6, 8.0))
			KitX.icicles(kit, Vector3(x - 1.5, -0.3, -2.0), Vector3(x + 1.5, -0.3, -2.0), 1.5, 1.2)
