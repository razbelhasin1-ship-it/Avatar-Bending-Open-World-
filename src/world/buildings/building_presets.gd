class_name BuildingPresets
extends RefCounted
## Ready-made buildings assembled from BuildingKit pieces (thread-safe). Settlement builders can
## use these directly, vary them through `spec`, or copy them as recipes for their own types.
## All take the kit, a transform (origin = ground centre of the footprint, -Z = front/door side)
## and a spec Dictionary; unknown keys are ignored.
##
##   house(kit, t, {"w": 8, "d": 6, "floors": 1, "roof": &"hip", "interior": true})
##   ek_hall / fn_temple / wt_hall / an_tower(kit, t, spec)   nation signature buildings
##   gatehouse(kit, t, spec)   tent(kit, t, spec)   shrine(kit, t, spec)   watchtower(kit, t, spec)
##   wall_run(kit, points, spec)                              city/camp walls with towers
##   demo(kit, nation)                                        the four kit showcase buildings
##
## Markers written (kit space): &"door" (outside the door, facing out), &"interior" (room
## centre), &"top" (roof apex).


## Default roof per nation for generic houses.
static func default_roof(nation: StringName) -> StringName:
	match nation:
		&"water_tribe": return &"dome"
		&"air_nomads": return &"cone"
		&"fire_nation": return &"hip"
	return &"hip"


## Generic house/hall. spec: w, d, floors, floor_h, base_h, roof (&"hip"|&"gable"|&"cone"|&"dome"
## |&"flat"|&"pagoda"), roof_h, door (bool), windows (bool), interior (bool: hollow room with an
## open door, floor, ceiling and a lamp), porch (bool: front colonnade), lanterns (bool),
## banners (bool), wall_role, roof_role.
static func house(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var nation := kit.palette.nation
	var w := float(spec.get("w", 7.0))
	var d := float(spec.get("d", 5.5))
	var floors := int(spec.get("floors", 1))
	var fh := float(spec.get("floor_h", 3.0))
	var base_h := float(spec.get("base_h", 0.5))
	var roof: StringName = spec.get("roof", default_roof(nation))
	var wall_role: Variant = spec.get("wall_role", &"wall")
	var interior: bool = spec.get("interior", false)
	var th := 0.35
	kit.push(t)
	# plinth
	kit.box(Vector3(0, base_h * 0.5, 0), Vector3(w + 0.6, base_h, d + 0.6), &"base")
	if base_h > 0.25 and kit.lod < 2:
		kit.stairs(Vector3(0, 0, -d * 0.5 - 0.3 - base_h * 1.6), Vector3(0, base_h, -d * 0.5 - 0.3), 1.8, {"role": &"stone"})
	var y := base_h
	for f in floors:
		var fw := w - f * 0.6
		var fd := d - f * 0.6
		var hx := fw * 0.5
		var hz := fd * 0.5
		var hollow := interior and f == 0
		if hollow or kit.lod < 2:
			var door_open: Dictionary = {"t": 0.5, "width": 1.4, "height": minf(2.3, fh - 0.4), "kind": &"door", "leaf": &"open" if hollow else &"closed"}
			var win: bool = spec.get("windows", true) and kit.lod < 2
			var front_open: Array = []
			if f == 0 and spec.get("door", true):
				front_open.append(door_open)
			if win:
				for wt in ([0.2, 0.8] if fw > 5.5 else []):
					front_open.append({"t": wt, "width": 0.9, "height": 1.0, "kind": &"window", "sill": 1.1})
			var side_open: Array = []
			if win:
				side_open.append({"t": 0.5, "width": 0.9, "height": 1.0, "kind": &"window", "sill": 1.1})
			var wopts := {"role": wall_role, "cap_role": &"wood", "piers": 2.4 if nation == &"earth_kingdom" or nation == &"fire_nation" else 0.0, "pier_role": &"wood"}
			var corners := PackedVector3Array([Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz)])
			# front (-z) wall: from (+hx,-hz) to (-hx,-hz) so its outward side faces -Z
			kit.wall(corners[1], corners[0], fh, th, wopts.merged({"openings": front_open}, true))
			kit.wall(corners[2], corners[1], fh, th, wopts.merged({"openings": side_open}, true))
			kit.wall(corners[3], corners[2], fh, th, wopts.merged({"openings": side_open if fd > 5.0 else []}, true))
			kit.wall(corners[0], corners[3], fh, th, wopts.merged({"openings": side_open}, true))
			if hollow:
				kit.box(Vector3(0, y + 0.05, 0), Vector3(fw - th, 0.1, fd - th), &"floor", true)
				kit.box(Vector3(0, y + fh - 0.06, 0), Vector3(fw - th, 0.12, fd - th), &"interior", false)
				_interior_props(kit, Vector3(0, y, 0), fw - th * 2.0, fd - th * 2.0)
				kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y, 0)))
				kit.add_light(Vector3(0, y + fh - 0.6, 0), kit.palette.color(&"glow"), maxf(fw, fd) * 0.9, 1.4, 2)
		else:
			kit.box(Vector3(0, y + fh * 0.5, 0), Vector3(fw, fh, fd), wall_role)
		y += fh
		if f < floors - 1:
			# floor band between storeys
			kit.box(Vector3(0, y + 0.1, 0), Vector3(fw + 0.3, 0.2, fd + 0.3), &"trim", false)
			if roof == &"hip" and kit.lod < 2:
				# skirt roof between floors (Earth Kingdom / Fire Nation multi-storey look)
				KitRoofs.hip(kit, Vector3(0, y - 0.3, 0), fw, fd, 0.9, {"overhang": 1.0, "curve": 0.35, "ornaments": false, "ridge": 1.0})
	if spec.get("porch", false):
		var cols := maxi(int(w / 2.4), 2)
		for i in cols + 1:
			var cx := lerpf(-w * 0.5, w * 0.5, float(i) / cols)
			kit.column(Vector3(cx, base_h, -d * 0.5 - 1.2), fh, 0.18, &"wood", &"round")
	var top_w := w - (floors - 1) * 0.6
	var top_d := d - (floors - 1) * 0.6
	var roof_h := float(spec.get("roof_h", minf(top_w, top_d) * 0.42))
	var rc := Vector3(0, y, 0)
	var roof_role: Variant = spec.get("roof_role", &"roof")
	match roof:
		&"gable":
			KitRoofs.gable(kit, rc, top_w, top_d + (2.4 if spec.get("porch", false) else 0.0), roof_h, {"role": roof_role})
		&"cone":
			KitRoofs.cone(kit, rc, maxf(top_w, top_d) * 0.62, roof_h * 1.6, {"role": roof_role})
		&"dome":
			KitRoofs.flat(kit, rc, top_w, top_d, {"parapet": false, "role": &"wall_alt"})
			KitRoofs.dome(kit, rc + Vector3(0, 0.3, 0), minf(top_w, top_d) * 0.5, {"role": roof_role, "block_lines": true})
		&"flat":
			KitRoofs.flat(kit, rc, top_w, top_d, {"role": roof_role, "icicles": nation == &"water_tribe"})
		&"pagoda":
			KitRoofs.pagoda(kit, rc, top_w, top_d, int(spec.get("tiers", 2)), {"role": roof_role})
		_:
			KitRoofs.hip(kit, rc, top_w, top_d + (2.4 if spec.get("porch", false) else 0.0), roof_h, {"role": roof_role})
	kit.mark(&"top", Transform3D(Basis(), rc + Vector3(0, roof_h, 0)))
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, base_h, -d * 0.5 - 1.0)))
	if spec.get("lanterns", true) and kit.lod < 2:
		var ls: StringName = &"ice" if nation == &"water_tribe" else &"paper"
		for sx in [-1.0, 1.0]:
			if ls == &"paper":
				kit.lantern(Vector3(sx * (w * 0.5 - 0.4), base_h + fh - 0.5, -d * 0.5 - 0.9), {"style": &"paper", "range": 8.0})
			else:
				kit.lantern(Vector3(sx * 1.6, base_h, -d * 0.5 - 1.2), {"style": &"ice"})
	if spec.get("banners", false) and kit.lod < 2:
		for sx in [-1.0, 1.0]:
			kit.banner(Transform3D(Basis(), Vector3(sx * 1.4, base_h + fh - 0.2, -d * 0.5 - 0.25)), 0.7, 2.0)
	kit.pop()


## Furniture of a hollow room: low table, cushions/mats, shelf, a lamp.
static func _interior_props(kit: BuildingKit, floor_c: Vector3, w: float, d: float) -> void:
	if kit.lod > 0:
		return
	kit.box(floor_c + Vector3(0, 0.3, 0.2), Vector3(1.4, 0.08, 0.8), &"wood", false)
	for sx in [-0.5, 0.5]:
		for sz in [-0.25, 0.25]:
			kit.box(floor_c + Vector3(sx * 1.2, 0.14, 0.2 + sz * 1.0), Vector3(0.08, 0.28, 0.08), &"wood_dark", false)
	for sx in [-1.0, 1.0]:
		kit.box(floor_c + Vector3(sx * 1.2, 0.06, 0.2), Vector3(0.6, 0.12, 0.6), &"cloth", false)
	kit.box(floor_c + Vector3(0, 0.9, d * 0.5 - 0.25), Vector3(minf(w * 0.6, 3.0), 1.8, 0.4), &"wood_dark", true)
	kit.box(floor_c + Vector3(-w * 0.5 + 0.6, 0.03, -d * 0.2), Vector3(1.0, 0.06, 1.8), &"cloth_alt", false)
	kit.lantern(floor_c + Vector3(w * 0.3, 0.0, d * 0.25), {"style": &"post", "height": 1.2, "light": false})


# --- Nation signature buildings (the kit demo) ---------------------------------------------

## Earth Kingdom hall: stone podium, plaster walls with wood frame, front colonnade, double-eave
## green tile roof with ridge horns, enterable interior, stone lanterns, banners.
static func ek_hall(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var w := float(spec.get("w", 12.0))
	var d := float(spec.get("d", 8.0))
	var h := float(spec.get("wall_h", 3.6))
	var base_h := 1.0
	kit.push(t)
	kit.box(Vector3(0, base_h * 0.5, 0), Vector3(w + 3.0, base_h, d + 3.0), &"base")
	if kit.lod < 2:
		kit.box(Vector3(0, base_h + 0.04, 0), Vector3(w + 3.1, 0.08, d + 3.1), &"stone_dark", false)
		kit.stairs(Vector3(0, 0, -d * 0.5 - 1.5 - 2.2), Vector3(0, base_h, -d * 0.5 - 1.5), 3.2, {"role": &"stone", "sides": true})
	# hollow walls with door and lattice windows
	var hx := w * 0.5
	var hz := d * 0.5
	var y := base_h
	var wopts := {"role": &"wall", "cap_role": &"wood", "base_role": &"stone_dark", "piers": 2.0, "pier_role": &"wood"}
	kit.wall(Vector3(hx, y, -hz), Vector3(-hx, y, -hz), h, 0.35, wopts.merged({"openings": [
		{"t": 0.5, "width": 1.8, "height": 2.6, "kind": &"door", "leaf": &"open"},
		{"t": 0.18, "width": 1.2, "height": 1.2, "kind": &"window", "sill": 1.1},
		{"t": 0.82, "width": 1.2, "height": 1.2, "kind": &"window", "sill": 1.1}]}, true))
	kit.wall(Vector3(hx, y, hz), Vector3(hx, y, -hz), h, 0.35, wopts.merged({"openings": [{"t": 0.5, "width": 1.2, "height": 1.2, "kind": &"window", "sill": 1.1}]}, true))
	kit.wall(Vector3(-hx, y, hz), Vector3(hx, y, hz), h, 0.35, wopts.merged({"openings": [{"t": 0.3, "width": 1.2, "height": 1.2, "kind": &"window", "sill": 1.1}, {"t": 0.7, "width": 1.2, "height": 1.2, "kind": &"window", "sill": 1.1}]}, true))
	kit.wall(Vector3(-hx, y, -hz), Vector3(-hx, y, hz), h, 0.35, wopts.merged({"openings": [{"t": 0.5, "width": 1.2, "height": 1.2, "kind": &"window", "sill": 1.1}]}, true))
	kit.box(Vector3(0, y + 0.05, 0), Vector3(w - 0.7, 0.1, d - 0.7), &"floor", true)
	kit.box(Vector3(0, y + h - 0.06, 0), Vector3(w - 0.7, 0.12, d - 0.7), &"interior", false)
	_interior_props(kit, Vector3(0, y, 0), w - 0.7, d - 0.7)
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y, 0)))
	kit.add_light(Vector3(0, y + h - 0.7, 0), kit.palette.color(&"glow"), 9.0, 1.5, 2)
	# front colonnade (red-lacquer posts in EK green trim)
	for i in 6:
		var cx := lerpf(-w * 0.5 - 0.4, w * 0.5 + 0.4, float(i) / 5.0)
		kit.column(Vector3(cx, y, -hz - 1.25), h, 0.2, &"wood", &"round", &"stone_dark")
	if kit.lod < 2:
		kit.beam(Vector3(-hx - 0.6, y + h - 0.15, -hz - 1.25), Vector3(hx + 0.6, y + h - 0.15, -hz - 1.25), 0.3, 0.3, &"trim")
	# double-eave roof: lower skirt around the hall + upper hip on a clerestory drum
	KitRoofs.hip(kit, Vector3(0, y + h, -0.6), w + 0.4, d + 2.6, 1.4, {"overhang": 1.3, "curve": 0.6, "ridge": 1.0, "ornaments": false})
	var drum_h := 1.4
	kit.box(Vector3(0, y + h + 0.9 + drum_h * 0.5, 0), Vector3(w * 0.72, drum_h, d * 0.72), &"wall_alt", true)
	if kit.lod == 0:
		for i in 7:
			kit.box(Vector3(lerpf(-w * 0.34, w * 0.34, i / 6.0), y + h + 0.9 + drum_h * 0.5, -d * 0.36 - 0.02), Vector3(0.1, drum_h, 0.06), &"wood_dark", false)
	KitRoofs.hip(kit, Vector3(0, y + h + 0.9 + drum_h, 0), w * 0.72, d * 0.72, 2.8, {"overhang": 1.2, "curve": 0.8, "finial": false})
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, y + h + 0.9 + drum_h + 2.8, 0)))
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, base_h, -hz - 2.0)))
	if kit.lod < 2:
		for sx in [-1.0, 1.0]:
			kit.lantern(Vector3(sx * 2.6, 0.0, -d * 0.5 - 4.5), {"style": &"stone", "height": 1.9})
			kit.lantern(Vector3(sx * (w * 0.5 - 0.6), y + h - 0.6, -hz - 1.25), {"style": &"paper", "range": 7.0})
			kit.banner(Transform3D(Basis(), Vector3(sx * 1.6, y + h - 0.3, -hz - 1.3)), 0.75, 2.2, {"role": &"cloth", "alt_role": &"cloth_alt"})
	kit.pop()


## Fire Nation temple: two-level dark stone podium with a grand stair, red colonnade around a
## red/black core, two-tier black pagoda roof with gold ridges, braziers and red banners.
static func fn_temple(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var w := float(spec.get("w", 11.0))
	var d := float(spec.get("d", 9.0))
	kit.push(t)
	# stepped podium
	kit.box(Vector3(0, 0.6, 0), Vector3(w + 6.0, 1.2, d + 6.0), &"base")
	kit.box(Vector3(0, 1.8, 0.5), Vector3(w + 2.5, 1.2, d + 2.5), &"stone_dark")
	if kit.lod < 2:
		_edge_band(kit, Vector3(0, 1.2, 0), w + 6.0, d + 6.0, 0.14, &"trim_alt")
		_edge_band(kit, Vector3(0, 2.4, 0.5), w + 2.5, d + 2.5, 0.14, &"trim_alt")
		kit.stairs(Vector3(0, 0, -d * 0.5 - 3.0 - 2.0), Vector3(0, 1.2, -d * 0.5 - 3.0), 4.0, {"role": &"stone", "sides": true, "side_role": &"stone_dark"})
		kit.stairs(Vector3(0, 1.2, -d * 0.5 - 0.75 - 2.0 + 0.5), Vector3(0, 2.4, -d * 0.5 - 0.75 + 0.5), 3.2, {"role": &"stone_dark", "sides": true, "side_role": &"trim"})
	var y := 2.4
	var h := 4.2
	# core walls (solid, dark red with black base)
	kit.box(Vector3(0, y + h * 0.5, 1.0), Vector3(w - 2.0, h, d - 2.0), &"wall")
	if kit.lod < 2:
		kit.box(Vector3(0, y + 0.4, 1.0), Vector3(w - 1.8, 0.8, d - 1.8), &"trim", false)
		kit.door(Transform3D(Basis(), Vector3(0, y, 1.0 - (d - 2.0) * 0.5 - 0.2)), 2.0, 3.0, {"frame_role": &"trim_alt", "leaf": &"closed"})
	# colonnade
	var cols := 5
	for i in cols:
		var cx := lerpf(-w * 0.5 + 0.5, w * 0.5 - 0.5, float(i) / (cols - 1))
		kit.column(Vector3(cx, y, -d * 0.5 + 0.2), h, 0.26, &"wall", &"round", &"stone_dark")
		kit.column(Vector3(cx, y, d * 0.5 + 1.0), h, 0.26, &"wall", &"round", &"stone_dark")
	for sz in [-1.0, 1.0]:
		var cz: float = 0.6 + sz * (d * 0.5 + 0.4)
		kit.column(Vector3(-w * 0.5 + 0.5, y, cz * 0.5), h, 0.26, &"wall", &"round", &"stone_dark")
		kit.column(Vector3(w * 0.5 - 0.5, y, cz * 0.5), h, 0.26, &"wall", &"round", &"stone_dark")
	if kit.lod < 2:
		kit.beam(Vector3(-w * 0.5, y + h - 0.2, -d * 0.5 + 0.2), Vector3(w * 0.5, y + h - 0.2, -d * 0.5 + 0.2), 0.35, 0.4, &"trim")
		kit.beam(Vector3(-w * 0.5, y + h - 0.55, -d * 0.5 + 0.2), Vector3(w * 0.5, y + h - 0.55, -d * 0.5 + 0.2), 0.2, 0.12, &"trim_alt")
	# two-tier pagoda roof
	var top := KitRoofs.pagoda(kit, Vector3(0, y + h, 0.5), w + 0.6, d + 2.0, 2, {"role": &"roof", "alt_role": &"roof", "ridge_role": &"ridge",
		"drum_role": &"wall", "post_role": &"trim", "roof_height": 3.0, "curve": 0.9, "overhang": 1.4, "drum_height": 2.4})
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, y + h + top, 0.5)))
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.0, -d * 0.5 - 6.0)))
	if kit.lod < 2:
		for sx in [-1.0, 1.0]:
			kit.brazier(Vector3(sx * 3.4, 0.0, -d * 0.5 - 5.4), {"height": 1.0, "radius": 0.55})
			kit.banner(Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.5), y + h - 0.7, -d * 0.5 - 0.1)), 0.9, 3.0, {"role": &"cloth", "alt_role": &"cloth_alt"})
			kit.lantern(Vector3(sx * 1.8, y + h - 0.9, -d * 0.5 + 0.0), {"style": &"paper", "range": 7.0, "color": Color(1.0, 0.45, 0.2)})
	kit.pop()


## Water Tribe ice hall: thick ice-block walls with crenels, arched gate, flat ice roof with
## icicles, two round towers with tall ice spires, blue banners, ice lanterns.
static func wt_hall(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var w := float(spec.get("w", 12.0))
	var d := float(spec.get("d", 9.0))
	var h := float(spec.get("wall_h", 5.0))
	kit.push(t)
	var prev := kit.default_slot
	kit.default_slot = &"ice"
	kit.box(Vector3(0, 0.3, 0), Vector3(w + 2.0, 0.6, d + 2.0), &"base")
	var hx := w * 0.5
	var hz := d * 0.5
	var y := 0.6
	var wopts := {"role": &"wall", "cap_role": &"wall_alt", "crenels": {"width": 0.9, "gap": 0.55, "height": 0.7, "role": &"wall"}}
	kit.wall(Vector3(hx, y, -hz), Vector3(-hx, y, -hz), h, 0.9, wopts.merged({"openings": [{"t": 0.5, "width": 2.4, "height": 3.4, "kind": &"gate", "leaf": &"none", "frame_role": &"wall_alt"}]}, true))
	kit.wall(Vector3(hx, y, hz), Vector3(hx, y, -hz), h, 0.9, wopts)
	kit.wall(Vector3(-hx, y, hz), Vector3(hx, y, hz), h, 0.9, wopts)
	kit.wall(Vector3(-hx, y, -hz), Vector3(-hx, y, hz), h, 0.9, wopts)
	kit.box(Vector3(0, y + 0.05, 0), Vector3(w - 1.6, 0.1, d - 1.6), &"floor", true)
	KitRoofs.flat(kit, Vector3(0, y + h - 0.4, 0), w - 1.7, d - 1.7, {"parapet": false, "role": &"wall_alt", "icicles": false, "overhang": 0.0})
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y, 0)))
	kit.add_light(Vector3(0, y + 2.5, 0), Color(0.75, 0.88, 1.0), 9.0, 1.2, 1)
	# block joints on the front face (darker grooves) for an ice-brick read
	if kit.lod == 0:
		for row in range(1, int(h / 0.9)):
			kit.box(Vector3(0, y + row * 0.9, -hz - 0.46), Vector3(w - 0.2, 0.05, 0.04), &"wall_alt", false)
	# corner towers with spires
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * (hx + 0.4), 0.0, -hz - 0.4)
		kit.cylinder(c, h + 2.6, 1.9, &"wall", 14, true)
		if kit.lod < 2:
			kit.cylinder(c + Vector3(0, h + 2.6, 0), 0.3, 2.15, &"wall_alt", 14, false)
			for k in 8:
				var a := TAU * k / 8.0
				kit.box(c + Vector3(cos(a) * 1.95, h + 3.15, sin(a) * 1.95), Vector3(0.55, 0.6, 0.55), &"wall", false)
			kit.window(Transform3D(Basis(), c + Vector3(0, h - 0.8, -1.92)), 0.6, 1.1, {"frame_role": &"wall_alt"})
		KitRoofs.cone(kit, c + Vector3(0, h + 2.9, 0), 1.7, 5.2, {"role": &"wall", "alt_role": &"wall_alt", "slot": &"ice", "flare": 0.3, "trim_role": &"trim", "finial_role": &"wall_alt"})
	# great dome over the hall on a drum, with a slender spire behind it
	kit.cylinder(Vector3(0, y + h - 0.4, 0.8), 1.3, 3.6, &"wall_alt", 18, true)
	KitRoofs.dome(kit, Vector3(0, y + h + 0.9, 0.8), 3.7, {"role": &"wall", "rib_role": &"trim", "slot": &"ice", "squash": 0.95, "finial_role": &"trim"})
	KitRoofs.cone(kit, Vector3(0, y + h - 0.05, d * 0.5 - 0.6), 1.3, 9.5, {"role": &"ice", "alt_role": &"wall", "slot": &"ice", "flare": 0.05, "trim_role": &"trim"})
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, y + h + 9.5, d * 0.5 - 0.6)))
	# snow lying on the parapets and tower tops
	if kit.lod == 0:
		for sz in [-1.0, 1.0]:
			kit.box(Vector3(0, y + h + 0.2, sz * hz), Vector3(w - 0.4, 0.12, 1.0), &"snow", false)
		for sx in [-1.0, 1.0]:
			kit.box(Vector3(sx * hx, y + h + 0.2, 0), Vector3(1.0, 0.12, d - 0.4), &"snow", false)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.6, -hz - 1.6)))
	kit.default_slot = prev
	if kit.lod < 2:
		for sx in [-1.0, 1.0]:
			kit.banner(Transform3D(Basis(), Vector3(sx * 2.2, y + h - 0.6, -hz - 0.5)), 1.0, 3.2, {"role": &"cloth", "alt_role": &"cloth_alt"})
			kit.lantern(Vector3(sx * 2.0, 0.6, -hz - 2.4), {"style": &"ice", "height": 1.8})
	kit.pop()


## Air Nomad tower: square stone platform, round white tower with orange bands and arched
## window niches, balcony ring with railing, tall blue-teal spire roof with gold finial, a smaller
## annex with its own cone roof, orange banners.
static func an_tower(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var r := float(spec.get("radius", 3.6))
	var h := float(spec.get("height", 11.0))
	kit.push(t)
	kit.box(Vector3(0, 0.4, 0), Vector3(r * 2.0 + 4.0, 0.8, r * 2.0 + 4.0), &"base")
	if kit.lod < 2:
		kit.stairs(Vector3(0, 0, -r - 2.0 - 1.4), Vector3(0, 0.8, -r - 2.0), 2.4, {"role": &"stone"})
	var y := 0.8
	kit.cylinder(Vector3(0, y, 0), h, r, &"wall", 20, true)
	if kit.lod < 2:
		for band in [0.0, h * 0.45, h - 0.4]:
			kit.cylinder(Vector3(0, y + band, 0), 0.4, r + 0.08, &"trim", 20, false)
		# arched niches (dark insets with frames) around the tower
		for k in 6:
			var a := TAU * k / 6.0 + PI * 0.5
			var dir := Vector3(cos(a), 0, sin(a))
			var nb := Basis(Vector3.UP, atan2(dir.x, dir.z) + PI)
			var lower := k % 2 == 0
			var nh := 2.2 if lower else 1.4
			var ny := y + (0.0 if lower else h * 0.6)
			kit.box_t(Transform3D(nb, dir * (r - 0.02) + Vector3(0, ny + nh * 0.5 + (0.0 if lower else 0.0), 0)), Vector3(1.0 if lower else 0.7, nh, 0.12), &"window", false)
			if kit.lod == 0:
				kit.box_t(Transform3D(nb, dir * (r + 0.02) + Vector3(0, ny + nh + 0.08, 0)), Vector3(1.3 if lower else 0.95, 0.16, 0.14), &"trim", false)
		kit.door(Transform3D(Basis(), Vector3(0, y, -r - 0.05)), 1.4, 2.4, {"frame_role": &"trim", "leaf": &"closed"})
	# balcony ring
	var by := y + h * 0.62
	kit.cylinder(Vector3(0, by - 0.25, 0), 0.25, r + 1.2, &"stone", 20, true)
	if kit.lod < 2:
		var ring := PackedVector3Array()
		for k in 17:
			var a := TAU * k / 16.0
			ring.append(Vector3(cos(a) * (r + 1.05), by, sin(a) * (r + 1.05)))
		kit.railing(ring, 0.9, {"role": &"trim", "post_role": &"wood", "spacing": 1.2})
	# spire roof
	KitRoofs.cone(kit, Vector3(0, y + h, 0), r + 1.3, r * 2.6, {"role": &"roof", "alt_role": &"roof_alt", "trim_role": &"trim", "flare": 0.55, "sides": 20})
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, y + h + r * 2.6, 0)))
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.8, -r - 1.2)))
	# annex
	var ax := r + 3.4
	kit.box(Vector3(ax, y + 1.6, 1.0), Vector3(4.0, 3.2, 4.4), &"wall")
	if kit.lod < 2:
		kit.box(Vector3(ax, y + 0.2, 1.0), Vector3(4.2, 0.4, 4.6), &"trim", false)
		kit.window(Transform3D(Basis(), Vector3(ax, y + 1.2, 1.0 - 2.25)), 0.8, 1.2, {"frame_role": &"trim"})
	KitRoofs.cone(kit, Vector3(ax, y + 3.2, 1.0), 3.0, 3.4, {"role": &"roof", "alt_role": &"roof_alt", "trim_role": &"trim", "flare": 0.4, "sides": 12})
	if kit.lod < 2:
		for sx in [-1.0, 1.0]:
			kit.banner(Transform3D(Basis(Vector3.UP, 0.0), Vector3(sx * 1.4, y + 3.6, -r - 0.15)), 0.6, 2.0, {"role": &"cloth", "alt_role": &"cloth_alt"})
		kit.flag(Transform3D(Basis(), Vector3(-r - 2.2, 0.8, -r - 1.0)), 6.0, 1.6, 0.9, {"role": &"cloth", "alt_role": &"accent"})
		kit.lantern(Vector3(-1.5, 0.8, -r - 2.6), {"style": &"stone", "height": 1.4})
		kit.lantern(Vector3(1.5, 0.8, -r - 2.6), {"style": &"stone", "height": 1.4})
	kit.pop()


## The four kit showcase buildings by nation (used by the dev scene and tests).
static func demo(kit: BuildingKit, t: Transform3D) -> void:
	match kit.palette.nation:
		&"water_tribe": wt_hall(kit, t)
		&"fire_nation": fn_temple(kit, t)
		&"air_nomads": an_tower(kit, t)
		_: ek_hall(kit, t)


## Thin decorative band around the top edge of a w x d slab whose top is at `top`.
static func _edge_band(kit: BuildingKit, top: Vector3, w: float, d: float, h: float, role: Variant) -> void:
	var b := 0.12
	kit.box(top + Vector3(0, -h * 0.5, -d * 0.5), Vector3(w + b, h, b), role, false)
	kit.box(top + Vector3(0, -h * 0.5, d * 0.5), Vector3(w + b, h, b), role, false)
	kit.box(top + Vector3(-w * 0.5, -h * 0.5, 0), Vector3(b, h, d + b), role, false)
	kit.box(top + Vector3(w * 0.5, -h * 0.5, 0), Vector3(b, h, d + b), role, false)


# --- Common structures ---------------------------------------------------------------------

## Gatehouse: two piers with a roofed passage. spec: width (passage), height, depth, roof.
static func gatehouse(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var pw := float(spec.get("width", 4.0))
	var ph := float(spec.get("height", 5.0))
	var dep := float(spec.get("depth", 3.0))
	kit.push(t)
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(sx * (pw * 0.5 + 1.0), ph * 0.5, 0), Vector3(2.0, ph, dep), &"wall")
		if kit.lod < 2:
			kit.box(Vector3(sx * (pw * 0.5 + 1.0), 0.3, 0), Vector3(2.2, 0.6, dep + 0.2), &"base", false)
	kit.box(Vector3(0, ph + 0.6, 0), Vector3(pw + 4.0, 1.2, dep), &"wall_alt")
	if kit.lod < 2:
		kit.beam(Vector3(-pw * 0.5, ph - 0.2, -dep * 0.5 - 0.05), Vector3(pw * 0.5, ph - 0.2, -dep * 0.5 - 0.05), 0.3, 0.4, &"trim")
	var roof: StringName = spec.get("roof", &"hip" if kit.palette.nation != &"water_tribe" else &"flat")
	if roof == &"flat":
		KitRoofs.flat(kit, Vector3(0, ph + 1.2, 0), pw + 4.0, dep, {"role": &"wall"})
	else:
		KitRoofs.hip(kit, Vector3(0, ph + 1.2, 0), pw + 4.0, dep, 1.8, {"overhang": 0.9})
	if kit.lod < 2:
		for sx in [-1.0, 1.0]:
			kit.lantern(Vector3(sx * (pw * 0.5 + 0.3), ph - 0.9, -dep * 0.5 - 0.4), {"style": &"paper", "range": 7.0})
	kit.pop()


## Defensive wall through `points` (base points) with towers at the vertices.
## spec: height, thickness, crenels (bool), towers (bool), tower_roof.
static func wall_run(kit: BuildingKit, points: PackedVector3Array, spec: Dictionary = {}) -> void:
	var h := float(spec.get("height", 6.0))
	var th := float(spec.get("thickness", 1.4))
	var cren: Dictionary = {"width": 0.9, "gap": 0.6, "height": 0.8} if spec.get("crenels", true) else {}
	kit.wall_loop(points, h, th, {"role": spec.get("role", &"wall"), "cap_role": &"stone_dark", "crenels": cren}, spec.get("closed", false))
	if spec.get("towers", true):
		for p in points:
			watchtower(kit, Transform3D(Basis(), p), {"height": h + 3.0, "width": th + 2.0, "roof": spec.get("tower_roof", &"hip")})


## Square watchtower with a lookout platform. spec: height, width, roof.
static func watchtower(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var h := float(spec.get("height", 8.0))
	var w := float(spec.get("width", 3.2))
	kit.push(t)
	kit.box(Vector3(0, h * 0.5, 0), Vector3(w, h, w), &"wall")
	if kit.lod < 2:
		kit.box(Vector3(0, h + 0.1, 0), Vector3(w + 0.6, 0.2, w + 0.6), &"stone_dark", true)
		for k in 4:
			var a := k * PI * 0.5
			kit.box(Vector3(cos(a) * (w * 0.5 + 0.15), h + 0.6, sin(a) * (w * 0.5 + 0.15)), Vector3(0.3 if absf(cos(a)) > 0.5 else w, 0.8, w if absf(cos(a)) > 0.5 else 0.3), &"wall", true)
	match spec.get("roof", &"hip"):
		&"cone":
			KitRoofs.cone(kit, Vector3(0, h + 2.4, 0), w * 0.8, w * 1.2)
		&"none":
			pass
		_:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					kit.box(Vector3(sx * w * 0.42, h + 1.3, sz * w * 0.42), Vector3(0.2, 2.2, 0.2), &"wood", false)
			KitRoofs.hip(kit, Vector3(0, h + 2.4, 0), w, w, 1.4, {"overhang": 0.6, "ridge": 0.0})
	kit.pop()


## Tent. spec: style (&"ridge" A-frame, &"yurt" round, &"tipi" cone), w, d, h, role.
static func tent(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var style: StringName = spec.get("style", &"ridge")
	var w := float(spec.get("w", 3.0))
	var d := float(spec.get("d", 4.0))
	var h := float(spec.get("h", 2.4))
	var role: Variant = spec.get("role", &"cloth")
	kit.push(t)
	var gb := kit.g()
	var c := kit.col(role)
	match style:
		&"yurt":
			kit.cylinder(Vector3.ZERO, h * 0.55, w * 0.5, role, 12, true)
			KitRoofs.cone(kit, Vector3(0, h * 0.55, 0), w * 0.55, h * 0.45, {"role": role, "alt_role": spec.get("alt_role", &"cloth_alt"), "trim_role": &"wood_dark", "flare": 0.1, "sides": 12, "finial": false})
			kit.box(Vector3(0, 0.75, -w * 0.5), Vector3(0.9, 1.5, 0.1), &"wood_dark", false)
		&"tipi":
			KitRoofs.cone(kit, Vector3.ZERO, w * 0.5, h, {"role": role, "alt_role": spec.get("alt_role", role), "trim_role": &"wood_dark", "flare": 0.0, "sides": 10, "finial": false})
			for k in 4:
				var a := TAU * k / 4.0 + 0.3
				kit.beam(Vector3(cos(a) * 0.1, h * 0.85, sin(a) * 0.1), Vector3(-cos(a) * 0.35, h + 0.45, -sin(a) * 0.35), 0.05, 0.05, &"wood")
		_:
			# A-frame: two cloth planes + ridge pole + front flaps
			var ridge0 := Vector3(0, h, -d * 0.5)
			var ridge1 := Vector3(0, h, d * 0.5)
			gb.flat_quad(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(-w * 0.5, 0, d * 0.5), ridge1, ridge0, c)
			gb.flat_quad(Vector3(w * 0.5, 0, d * 0.5), Vector3(w * 0.5, 0, -d * 0.5), ridge0, ridge1, c)
			gb.flat_quad(Vector3(-w * 0.5, 0, d * 0.5), Vector3(-w * 0.5, 0, -d * 0.5), ridge0, ridge1, c * 0.75)
			gb.flat_quad(Vector3(w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, d * 0.5), ridge1, ridge0, c * 0.75)
			gb.flat_tri(Vector3(w * 0.5, 0, d * 0.5), ridge1, Vector3(-w * 0.5, 0, d * 0.5), c * 0.9)
			gb.flat_tri(Vector3(-w * 0.5, 0, d * 0.5), ridge1, Vector3(w * 0.5, 0, d * 0.5), c * 0.7)
			gb.flat_tri(Vector3(-w * 0.5, 0, -d * 0.5), ridge0, Vector3(-w * 0.15, 0, -d * 0.5), c * 0.9)
			gb.flat_tri(Vector3(w * 0.15, 0, -d * 0.5), ridge0, Vector3(w * 0.5, 0, -d * 0.5), c * 0.9)
			kit.beam(ridge0 + Vector3(0, 0.05, -0.2), ridge1 + Vector3(0, 0.05, 0.2), 0.08, 0.08, &"wood")
			for p in [ridge0, ridge1]:
				kit.beam(Vector3(p.x, 0, p.z), p + Vector3(0, 0.3, 0), 0.08, 0.08, &"wood")
			kit.collide_quad(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(-w * 0.5, 0, d * 0.5), ridge1, ridge0)
			kit.collide_quad(Vector3(w * 0.5, 0, d * 0.5), Vector3(w * 0.5, 0, -d * 0.5), ridge0, ridge1)
	kit.pop()


## Small roadside / sacred shrine styled per nation. spec: size.
static func shrine(kit: BuildingKit, t: Transform3D, spec: Dictionary = {}) -> void:
	var s := float(spec.get("size", 1.0))
	var nation := kit.palette.nation
	kit.push(t)
	kit.box(Vector3(0, 0.25 * s, 0), Vector3(3.2 * s, 0.5 * s, 3.2 * s), &"base")
	if kit.lod < 2:
		kit.stairs(Vector3(0, 0, -1.6 * s - 0.9 * s), Vector3(0, 0.5 * s, -1.6 * s), 1.4 * s, {"role": &"stone"})
	match nation:
		&"water_tribe":
			var prev := kit.default_slot
			kit.default_slot = &"ice"
			kit.box(Vector3(0, 0.5 * s + 1.0 * s, 0.4 * s), Vector3(2.0 * s, 2.0 * s, 1.4 * s), &"wall")
			KitRoofs.dome(kit, Vector3(0, 2.5 * s, 0.4 * s), 1.1 * s, {"role": &"wall_alt", "block_lines": true, "slot": &"ice"})
			kit.default_slot = prev
			kit.box(Vector3(0, 0.5 * s + 0.7 * s, -0.31 * s), Vector3(0.9 * s, 1.4 * s, 0.05), &"window", false)
			kit.lantern(Vector3(0, 0.5 * s, -1.3 * s), {"style": &"ice", "height": 1.0 * s, "color": Color(0.75, 0.85, 1.0)})
		&"air_nomads":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					kit.column(Vector3(sx * 1.1 * s, 0.5 * s, sz * 1.1 * s), 2.2 * s, 0.14 * s, &"wall", &"square", &"stone")
			KitRoofs.cone(kit, Vector3(0, 2.7 * s, 0), 1.9 * s, 2.2 * s, {"role": &"roof", "trim_role": &"trim", "flare": 0.5, "sides": 12})
			kit.box(Vector3(0, 0.5 * s + 0.4 * s, 0), Vector3(0.8 * s, 0.8 * s, 0.8 * s), &"stone", true)
			kit.lantern(Vector3(0, 0.5 * s + 0.8 * s, 0), {"style": &"paper", "range": 6.0})
		&"fire_nation":
			kit.box(Vector3(0, 0.5 * s + 1.2 * s, 0.3 * s), Vector3(2.0 * s, 2.4 * s, 1.6 * s), &"wall")
			KitRoofs.hip(kit, Vector3(0, 2.9 * s, 0.3 * s), 2.0 * s, 1.6 * s, 1.1 * s, {"overhang": 0.6 * s, "curve": 0.5 * s})
			kit.brazier(Vector3(0, 0.5 * s, -1.0 * s), {"height": 0.6 * s, "radius": 0.4 * s})
		_:
			kit.box(Vector3(0, 0.5 * s + 1.0 * s, 0.4 * s), Vector3(1.8 * s, 2.0 * s, 1.4 * s), &"wood")
			KitRoofs.hip(kit, Vector3(0, 2.5 * s, 0.4 * s), 1.8 * s, 1.4 * s, 1.0 * s, {"overhang": 0.6 * s, "curve": 0.4 * s})
			kit.box(Vector3(0, 0.5 * s + 0.8 * s, -0.32 * s), Vector3(0.8 * s, 1.0 * s, 0.05), &"window", false)
			for sx in [-1.0, 1.0]:
				kit.lantern(Vector3(sx * 1.1 * s, 0.5 * s, -1.3 * s), {"style": &"stone", "height": 1.3 * s, "light": sx > 0.0})
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -2.6 * s)))
	kit.pop()
