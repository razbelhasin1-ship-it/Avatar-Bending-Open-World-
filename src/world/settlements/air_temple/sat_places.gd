class_name SatPlaces
extends RefCounted
## Buildings and places of the Southern Air Temple (BuildingKit recipes, thread-safe; origin =
## ground centre unless noted, -Z = front / entrance).
##   sanctuary      the sanctuary hall against the Sanctum cliff: stair, podium, teal-roofed portico
##                  and the great round air-symbol door (swirl, ring, horn tubes) in an arched
##                  portal. Origin = threshold centre, the hall extends towards +Z.
##   stable         sky bison stables: open arcade front, stalls with partitions, hay, troughs,
##                  teal hip roof. spec: L (length), D (depth).
##   airball_court  paved court with the pole field and two hoop goals, low rim wall.
##   pavilion       meditation pavilion: octagonal platform on brackets (cantilevered over a cliff
##                  edge when spec.cantilever), slim columns, flared teal cone, wind chimes.
##   dormitory      monks' houses: v%3 = 0 round two-storey house with a cone roof, 1 two-storey
##                  block with a hip roof and balcony, 2 long hall with an end tower.
##   hall           ceremonial hall (dining hall / library): podium, portico, hip roof.
##   garden         planted bed (stone rim, soil, grass); its trees / shrubs / flowers come from
##                  SatBuilder.piece_extras (VegetationLibrary MultiMeshes). spec: w, d | r.
##   statue         stone statues on pedestals: v%3 = 0 seated meditating monk, 1 standing monk
##                  with a glider staff, 2 resting sky bison.


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	var v := int(spec.get("v", 0))
	match kind:
		&"sanctuary": sanctuary(kit, spec)
		&"stable": stable(kit, spec)
		&"airball_court": airball_court(kit, spec)
		&"pavilion": pavilion(kit, spec)
		&"dormitory": dormitory(kit, v)
		&"hall": hall(kit, v)
		&"garden": garden(kit, spec)
		&"statue": statue(kit, v)


## Footprint (width along the street, depth) of a dormitory / hall variant.
static func footprint(kind: StringName, v: int) -> Vector2:
	match kind:
		&"dormitory":
			match v % 3:
				0: return Vector2(11.0, 11.0)
				1: return Vector2(13.0, 10.0)
				_: return Vector2(17.0, 9.0)
		&"hall":
			return Vector2(22.0, 15.0)
	return Vector2(10, 10)


static func _interior_light(kit: BuildingKit, pos: Vector3, color: Color, range_m: float, energy: float) -> void:
	kit.lights.append({"position": kit.xform * pos, "color": color, "range": range_m, "energy": energy, "priority": 3, "interior": true})


## Hip roof in the temple style (teal tiles, gold ridge, strong upturn).
static func _hip(kit: BuildingKit, c: Vector3, w: float, d: float, h: float, v: int, overhang: float = 1.0) -> void:
	KitRoofs.hip(kit, c, w, d, h, {"role": SatStyle.roof(v), "alt_role": SatStyle.roof_stripe(v), "ridge_role": SatStyle.gold(),
		"curve": 0.75, "overhang": overhang, "concave": 0.5, "ornaments": kit.lod == 0})


## Orange / saffron bands around a w x d block at height y.
static func _bands(kit: BuildingKit, c: Vector3, w: float, d: float, y: float) -> void:
	if kit.lod >= 2:
		return
	kit.box(c + Vector3(0, y - 0.25, 0), Vector3(w + 0.14, 0.4, d + 0.14), SatStyle.orange(), false)
	kit.box(c + Vector3(0, y + 0.05, 0), Vector3(w + 0.3, 0.16, d + 0.3), SatStyle.saffron(), false)


# --- sanctuary --------------------------------------------------------------------------------------

## The great air-symbol door on the plane z = 0 facing -Z, centre at height y: a teal disc in a
## gold ring, the air swirl, and three horn tubes curling in from each side.
static func air_door(kit: BuildingKit, c: Vector3, radius: float) -> void:
	var g := kit.g()
	var segs := 28 if kit.lod == 0 else 14
	g.cylinder(c + Vector3(0, 0, 0.25), c + Vector3(0, 0, -0.25), radius, radius, segs, kit.col(SatStyle.lin(Color(0.30, 0.55, 0.62))), 2)
	if kit.lod >= 2:
		return
	# gold rim + inner ring
	var rim := PackedVector3Array()
	var inner := PackedVector3Array()
	for i in segs + 1:
		var a := TAU * i / segs
		rim.append(c + Vector3(cos(a) * radius, sin(a) * radius, -0.3))
		inner.append(c + Vector3(cos(a) * radius * 0.62, sin(a) * radius * 0.62, -0.3))
	var rr := PackedFloat32Array()
	rr.resize(rim.size())
	rr.fill(radius * 0.06)
	g.tube(rim, rr, 6, kit.col(SatStyle.gold()))
	rr.fill(radius * 0.025)
	g.tube(inner, rr, 5, kit.col(SatStyle.gold()))
	KitX.emblem_air(kit, c, radius * 1.15, SatStyle.gold(), 0.32)
	# the seam down the middle (two leaves)
	kit.box(c + Vector3(0, 0, -0.27), Vector3(0.06, radius * 1.9, 0.04), SatStyle.lin(Color(0.18, 0.33, 0.38)), false)
	# horn tubes: three per side, curling from the frame into the disc edge
	for sx: float in [-1.0, 1.0]:
		for k in 3:
			var ay := (k - 1) * 0.55
			var start := c + Vector3(sx * radius * 1.32, ay * radius - radius * 0.1, -0.35)
			var mid := c + Vector3(sx * radius * 1.12, ay * radius * 1.12 + radius * 0.18, -0.55)
			var end := c + Vector3(sx * radius * 0.9 * cos(ay * 0.9), radius * 0.9 * sin(ay * 0.9), -0.4)
			var line := PackedVector3Array([start, mid, end])
			var radii := PackedFloat32Array([radius * 0.09, radius * 0.06, radius * 0.045])
			g.tube(line, radii, 6 if kit.lod == 0 else 4, kit.col(SatStyle.gold()), kit.col(SatStyle.lin(Color(0.80, 0.56, 0.20))))
			if kit.lod == 0:
				g.cone(start + Vector3(sx * 0.02, 0, 0), start + Vector3(sx * radius * 0.16, -radius * 0.06, 0), radius * 0.13, 8, kit.col(SatStyle.gold()))


static func sanctuary(kit: BuildingKit, _spec: Dictionary) -> void:
	var W := 30.0
	var D := 24.0
	var H := 13.0
	var podium := 1.4
	var zc := D * 0.5
	# podium + front stair
	kit.box(Vector3(0, podium * 0.5 - 0.6, zc - 2.0), Vector3(W + 8.0, podium + 1.2, D + 6.0), SatStyle.masonry(0), true)
	kit.stairs(Vector3(0, 0.0, -7.6), Vector3(0, podium, -5.0), 14.0, {"role": SatStyle.masonry(2), "rise": 0.2, "sides": true, "side_role": SatStyle.wall(1)})
	var y := podium
	# hall body with a recessed portal bay
	kit.box(Vector3(-W * 0.32 - 0.6, y + H * 0.5, zc), Vector3(W * 0.36, H, D), SatStyle.wall(0))
	kit.box(Vector3(W * 0.32 + 0.6, y + H * 0.5, zc), Vector3(W * 0.36, H, D), SatStyle.wall(0))
	kit.box(Vector3(0, y + H * 0.5, zc + 2.0), Vector3(W * 0.28 + 1.4, H, D - 4.0), SatStyle.wall(1))
	_bands(kit, Vector3(0, y, zc), W, D, H)
	_hip(kit, Vector3(0, y + H, zc + 1.0), W, D + 2.0, 7.5, 0, 1.6)
	# the portal: thick orange frame, arched head, the door recessed 2 m
	var pw := 8.0
	var ph := 10.0
	var dz := 2.0
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (pw * 0.5 + 0.6), y + ph * 0.5, dz * 0.5 - 0.3), Vector3(1.2, ph, dz + 0.6), SatStyle.orange())
	if kit.lod < 2:
		var segs := 12 if kit.lod == 0 else 6
		for i in segs:
			var a0 := PI * float(i) / segs
			var a1 := PI * float(i + 1) / segs
			var p0 := Vector3(cos(a0) * (pw * 0.5 + 0.6), y + ph - pw * 0.5 + sin(a0) * (pw * 0.5 + 0.6), -0.4)
			var p1 := Vector3(cos(a1) * (pw * 0.5 + 0.6), y + ph - pw * 0.5 + sin(a1) * (pw * 0.5 + 0.6), -0.4)
			kit.beam(p0, p1, 1.2, 1.3, SatStyle.orange())
		# the dark recess behind the door and the door itself
		kit.box(Vector3(0, y + (ph - pw * 0.5) * 0.5, dz + 0.1), Vector3(pw, ph - pw * 0.5, 0.2), &"window", false)
		air_door(kit, Vector3(0, y + 3.9, dz - 0.3), 3.4)
		# pediment over the portal with a saffron emblem
		kit.box(Vector3(0, y + H - 0.8, -0.6), Vector3(pw + 4.0, 1.6, 1.2), SatStyle.wall(2), false)
		KitX.emblem_air(kit, Vector3(0, y + H - 0.8, -1.2), 1.8, SatStyle.saffron(), 0.02)
	kit.collide_box(Vector3(0, y + ph * 0.5, dz), Vector3(pw, ph, 0.6))
	# portico: four columns + a teal canopy roof over the stair head
	for k in 4:
		var x := lerpf(-11.0, 11.0, k / 3.0)
		kit.column(Vector3(x, y, -3.4), H - 1.4, 0.75, SatStyle.wall(0), &"round", SatStyle.masonry(1))
		if kit.lod < 2:
			kit.cylinder(Vector3(x, y + H - 2.6, -3.4), 0.5, 0.9, SatStyle.orange(), 12, false)
	kit.box(Vector3(0, y + H - 1.2, -3.4), Vector3(25.0, 0.6, 1.4), SatStyle.orange(), true)
	_hip(kit, Vector3(0, y + H - 0.9, -2.4), 25.0, 4.0, 2.6, 1, 1.2)
	# side windows, banners, lanterns, incense burners
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			for k in 2:
				_tall_window(kit, Vector3(sx * (W * 0.25 + k * 5.0), y + 5.0, -0.02), 1.4, 4.4, k == 0)
			KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 7.6, y + H - 2.2, -0.15)), 1.8, 7.5, SatStyle.orange(), SatStyle.saffron(), &"swirl")
			kit.lantern(Vector3(sx * 8.5, 0.0, -9.2), {"style": &"stone", "height": 2.0, "range": 11.0, "energy": 1.8})
			if kit.lod == 0:
				_incense(kit, Vector3(sx * 4.0, y, -6.2))
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, y, -2.0)))
	kit.mark(&"elder", Transform3D(Basis(Vector3.UP, PI), Vector3(2.2, y, -2.6)))


## Tall arched window flush on a -Z face at `c` (centre of the rectangle part).
static func _tall_window(kit: BuildingKit, c: Vector3, w: float, h: float, lit: bool) -> void:
	SatCivic._flat_arch_window(kit, c, w, h, lit)


## Bronze incense burner on three legs with a thin smoke column (LOD0).
static func _incense(kit: BuildingKit, p: Vector3) -> void:
	kit.g().cylinder(p + Vector3(0, 0.55, 0), p + Vector3(0, 1.0, 0), 0.32, 0.42, 10, kit.col(SatStyle.gold()) * 0.7, 2)
	for k in 3:
		var a := TAU * k / 3.0
		kit.beam(p + Vector3(cos(a) * 0.32, 0, sin(a) * 0.32), p + Vector3(cos(a) * 0.25, 0.6, sin(a) * 0.25), 0.07, 0.07, SatStyle.gold() * 0.7)
	kit.g().cone(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.35, 0), 0.3, 8, kit.col(SatStyle.gold()) * 0.75)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 0.6)
	gb.blob(p + Vector3(0, 0.98, 0), 0.12, 0, Color(1.0, 0.55, 0.2))


# --- bison stables -----------------------------------------------------------------------------------

static func stable(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 36.0))
	var D := float(spec.get("D", 12.0))
	var H := 9.0
	var hl := L * 0.5
	var hd := D * 0.5
	kit.box(Vector3(0, -0.4, 0), Vector3(L + 1.0, 1.0, D + 1.0), SatStyle.masonry(0), false)
	kit.box(Vector3(0, 0.05, 0), Vector3(L - 0.4, 0.1, D - 0.4), SatStyle.lin(Color(0.74, 0.66, 0.52)), true)
	# back + side walls
	kit.wall(Vector3(-hl, 0.1, hd), Vector3(hl, 0.1, hd), H, 0.8, {"role": SatStyle.wall(1), "base_role": SatStyle.masonry(1), "cap": false})
	kit.wall(Vector3(-hl, 0.1, -hd), Vector3(-hl, 0.1, hd), H, 0.8, {"role": SatStyle.wall(1), "base_role": SatStyle.masonry(1), "cap": false,
		"openings": [{"t": 0.5, "width": 3.0, "height": 4.0, "kind": &"door", "leaf": &"none", "frame_role": SatStyle.orange()}]})
	kit.wall(Vector3(hl, 0.1, hd), Vector3(hl, 0.1, -hd), H, 0.8, {"role": SatStyle.wall(1), "base_role": SatStyle.masonry(1), "cap": false})
	# front arcade: piers + round arches (bison-sized openings)
	var bays := maxi(int(L / 9.0), 2)
	for i in bays + 1:
		var x := lerpf(-hl, hl, float(i) / bays)
		kit.box(Vector3(x, H * 0.5, -hd), Vector3(1.4, H, 1.4), SatStyle.wall(0), true)
		if kit.lod < 2:
			kit.box(Vector3(x, 0.5, -hd), Vector3(1.8, 1.0, 1.8), SatStyle.masonry(1), false)
	for i in bays:
		var x0 := lerpf(-hl, hl, float(i) / bays) + 0.7
		var x1 := lerpf(-hl, hl, float(i + 1) / bays) - 0.7
		var span := x1 - x0
		var spring := H - span * 0.5 - 0.8
		if kit.lod < 2:
			var segs := 8 if kit.lod == 0 else 4
			for k in segs:
				var a0 := PI * float(k) / segs
				var a1 := PI * float(k + 1) / segs
				var p0 := Vector3((x0 + x1) * 0.5 - cos(a0) * span * 0.5, spring + sin(a0) * span * 0.5, -hd)
				var p1 := Vector3((x0 + x1) * 0.5 - cos(a1) * span * 0.5, spring + sin(a1) * span * 0.5, -hd)
				kit.beam(p0, p1, 1.4, 0.7, SatStyle.wall(0))
			kit.box(Vector3((x0 + x1) * 0.5, H - 0.4, -hd), Vector3(span, 0.8, 1.4), SatStyle.wall(0), false)
		else:
			kit.box(Vector3((x0 + x1) * 0.5, H - 0.8, -hd), Vector3(span, 1.6, 1.4), SatStyle.wall(0), false)
		# stall partition + hay + trough inside each bay
		if kit.lod == 0:
			kit.box(Vector3(x1 + 0.7, 1.0, 0.5), Vector3(0.25, 2.0, D - 3.0), &"wood", true)
			for k in 3:
				var hp := Vector3(lerpf(x0, x1, 0.25 + 0.25 * k), 0.55, hd - 1.6)
				kit.box_t(Transform3D(Basis(Vector3.UP, 0.2 * k - 0.2), hp), Vector3(1.6, 1.0, 1.1), SatStyle.lin(SatStyle.HAY) * (0.92 + 0.06 * k), false)
			kit.g().blob(Vector3((x0 + x1) * 0.5 + 1.5, 0.5, hd - 3.2), 1.3, 1, kit.col(SatStyle.lin(SatStyle.HAY)), kit.rng, 0.15, Vector3(1.5, 0.55, 1.0))
			kit.box(Vector3((x0 + x1) * 0.5 - 1.6, 0.45, hd - 3.4), Vector3(2.4, 0.9, 0.9), &"wood_dark", true)
			kit.box(Vector3((x0 + x1) * 0.5 - 1.6, 0.86, hd - 3.4), Vector3(2.1, 0.06, 0.65), SatStyle.lin(Color(0.35, 0.55, 0.70)), false)
	_bands(kit, Vector3(0, 0.1, 0), L, D, H)
	if kit.lod < 2:
		kit.box(Vector3(0, H - 0.1, 0), Vector3(L - 1.0, 0.2, D - 1.0), &"roof_under", false)
	_hip(kit, Vector3(0, H + 0.1, 0), L, D, 4.8, 1, 1.4)
	if kit.lod < 2:
		# a cupola vent on the ridge and banners between the arches
		kit.box(Vector3(0, H + 4.6, 0), Vector3(3.0, 1.6, 2.4), SatStyle.wall(0), false)
		_hip(kit, Vector3(0, H + 5.4, 0), 3.0, 2.4, 1.3, 1, 0.5)
		for i in bays + 1:
			if i % 2 == 0:
				var x := lerpf(-hl, hl, float(i) / bays)
				KitX.banner(kit, Transform3D(Basis(), Vector3(x, H - 1.3, -hd - 0.75)), 1.0, 3.6, SatStyle.orange(), SatStyle.saffron(), &"swirl")
	for i in bays:
		var x := lerpf(-hl, hl, (i + 0.5) / bays)
		_interior_light(kit, Vector3(x, H - 2.0, 0.5), Color(1.0, 0.82, 0.55), 10.0, 0.9)
		kit.mark(StringName("stall_%d" % i), Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.1, 0.0)))


# --- airball court ----------------------------------------------------------------------------------

static func airball_court(kit: BuildingKit, spec: Dictionary) -> void:
	var w := float(spec.get("w", 16.0))
	var l := float(spec.get("l", 28.0))
	kit.box(Vector3(0, -0.3, 0), Vector3(w + 2.0, 0.8, l + 2.0), SatStyle.masonry(1), true)
	kit.box(Vector3(0, 0.12, 0), Vector3(w, 0.06, l), SatStyle.lin(Color(0.80, 0.72, 0.58)), false)
	if kit.lod < 2:
		# boundary + centre line
		for sx: float in [-1.0, 1.0]:
			kit.box(Vector3(sx * (w * 0.5 - 0.15), 0.16, 0), Vector3(0.3, 0.04, l), SatStyle.orange(), false)
			kit.box(Vector3(0, 0.16, sx * (l * 0.5 - 0.15)), Vector3(w, 0.04, 0.3), SatStyle.orange(), false)
		kit.box(Vector3(0, 0.16, 0), Vector3(w, 0.04, 0.2), SatStyle.saffron(), false)
	# the pole field (heights vary in waves)
	var rows := 4
	var cols := 7
	for i in cols:
		for j in rows:
			var x := lerpf(-w * 0.36, w * 0.36, float(j) / (rows - 1))
			var z := lerpf(-l * 0.3, l * 0.3, float(i) / (cols - 1))
			var ph := 1.4 + 2.2 * absf(sin(i * 0.9 + j * 1.7))
			kit.cylinder(Vector3(x, 0.15, z), ph, 0.22, &"wood", 8, true, 0.2)
			if kit.lod < 2:
				kit.cylinder(Vector3(x, 0.15 + ph, z), 0.12, 0.3, SatStyle.orange(), 8, true)
	# hoop goals at both ends
	for sz: float in [-1.0, 1.0]:
		var z: float = sz * (l * 0.5 - 1.2)
		kit.cylinder(Vector3(0, 0.15, z), 5.0, 0.18, &"wood_dark", 8, true)
		if kit.lod < 2:
			var hoop := PackedVector3Array()
			for k in 17:
				var a := TAU * k / 16.0
				hoop.append(Vector3(cos(a) * 1.0, 5.6 + sin(a) * 1.0, z))
			var rr := PackedFloat32Array()
			rr.resize(hoop.size())
			rr.fill(0.07)
			kit.g().tube(hoop, rr, 4, kit.col(SatStyle.orange()))
			if kit.lod == 0:
				# net strands
				for k in 6:
					var a := TAU * k / 6.0
					kit.g().cylinder(Vector3(cos(a) * 0.95, 5.6 + sin(a) * 0.95, z), Vector3(cos(a) * 0.3, 5.6 + sin(a) * 0.3, z + sz * 0.5), 0.015, 0.015, 3, kit.col(SatStyle.wall(0)), 0)
	# low rim wall with gaps at the long-side centres
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var a := Vector3(sx * (w * 0.5 + 0.6), 0.1, sz * 2.5)
				var b := Vector3(sx * (w * 0.5 + 0.6), 0.1, sz * (l * 0.5 + 0.6))
				kit.wall(a, b, 0.7, 0.5, {"role": SatStyle.wall(1), "cap_role": SatStyle.orange()})
		for sz: float in [-1.0, 1.0]:
			kit.wall(Vector3(-w * 0.5 - 0.6, 0.1, sz * (l * 0.5 + 0.6)), Vector3(w * 0.5 + 0.6, 0.1, sz * (l * 0.5 + 0.6)), 0.7, 0.5,
					{"role": SatStyle.wall(1), "cap_role": SatStyle.orange()})


# --- pavilions -------------------------------------------------------------------------------------

## Meditation pavilion. spec: r (platform radius), cantilever (bool: platform pushed out over a
## cliff along -Z on brackets), v.
static func pavilion(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 3.6))
	var v := int(spec.get("v", 0))
	var cant: bool = spec.get("cantilever", false)
	var c := Vector3(0, 0, -r * 0.6 if cant else 0.0)
	var poly := PackedVector2Array()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		poly.append(Vector2(c.x + cos(a) * r, c.z + sin(a) * r))
	kit.slab(poly, -0.5, 0.35, SatStyle.masonry(v), true, SatStyle.wall(1))
	if cant:
		# masonry bracket and diagonal struts down into the cliff
		kit.box(Vector3(0, -2.6, r * 0.3), Vector3(r * 1.4, 4.4, r * 1.6), SatStyle.masonry(v + 1), true)
		if kit.lod < 2:
			for sx: float in [-1.0, 0.0, 1.0]:
				kit.beam(Vector3(sx * r * 0.6, -0.4, c.z - r * 0.7), Vector3(sx * r * 0.4, -4.6, r * 0.2), 0.45, 0.45, SatStyle.masonry(v + 2))
	else:
		kit.box(Vector3(0, -1.2, 0), Vector3(r * 1.7, 1.6, r * 1.7), SatStyle.masonry(v + 1), false)
	var cols := 6
	var top := 4.0
	for k in cols:
		var a := TAU * k / cols + PI / cols
		var p := c + Vector3(cos(a) * (r - 0.45), 0.35, sin(a) * (r - 0.45))
		kit.cylinder(p, top - 0.35, 0.16, SatStyle.wall(v), 8, true)
		if kit.lod < 2:
			kit.cylinder(p + Vector3(0, top - 0.95, 0), 0.25, 0.22, SatStyle.orange(), 8, false)
	kit.cylinder(c + Vector3(0, top, 0), 0.45, r - 0.1, SatStyle.orange(), 16, false)
	KitRoofs.cone(kit, c + Vector3(0, top + 0.45, 0), r + 1.0, r * 1.15, SatStyle.cone_opts(v + 2, 16, 0.75))
	if kit.lod < 2:
		# low railing between the columns (open towards -Z: the view)
		for k in cols:
			var a0 := TAU * k / cols + PI / cols
			var a1 := TAU * (k + 1) / cols + PI / cols
			if absf(wrapf((a0 + a1) * 0.5 + PI * 0.5, -PI, PI)) < 0.6:
				continue
			var p0 := c + Vector3(cos(a0) * (r - 0.45), 0.35, sin(a0) * (r - 0.45))
			var p1 := c + Vector3(cos(a1) * (r - 0.45), 0.35, sin(a1) * (r - 0.45))
			kit.beam(p0 + Vector3(0, 0.75, 0), p1 + Vector3(0, 0.75, 0), 0.12, 0.12, SatStyle.orange(), true)
		if kit.lod == 0:
			# meditation cushion, wind chimes on the eaves
			kit.g().cylinder(c + Vector3(0, 0.35, 0), c + Vector3(0, 0.55, 0), 0.55, 0.5, 10, kit.col(SatStyle.orange()), 2)
			for k in cols:
				var a := TAU * k / cols
				var p := c + Vector3(cos(a) * (r + 0.4), top + 0.3, sin(a) * (r + 0.4))
				_chime(kit, p, 0.55)
	kit.mark(&"seat", Transform3D(Basis(Vector3.UP, PI), c + Vector3(0, 0.4, 0)))


## A small wind chime hanging at `p`: cap disc + four bronze tubes of different lengths.
static func _chime(kit: BuildingKit, p: Vector3, size: float) -> void:
	var g := kit.g()
	g.cylinder(p, p - Vector3(0, size * 0.25, 0), 0.008, 0.008, 3, kit.col(&"wood_dark"), 0)
	var cap := p - Vector3(0, size * 0.25, 0)
	g.cylinder(cap, cap - Vector3(0, 0.04, 0), size * 0.14, size * 0.14, 8, kit.col(SatStyle.orange()), 2)
	for k in 4:
		var a := TAU * k / 4.0
		var q := cap + Vector3(cos(a) * size * 0.09, -0.05, sin(a) * size * 0.09)
		g.cylinder(q, q - Vector3(0, size * (0.35 + 0.12 * k), 0), 0.018, 0.018, 5, kit.col(SatStyle.gold()), 2)


# --- dwellings + halls -----------------------------------------------------------------------------

static func dormitory(kit: BuildingKit, v: int) -> void:
	var fp := footprint(&"dormitory", v)
	match v % 3:
		0:
			var r := fp.x * 0.5 - 0.6
			var h := 7.4
			kit.cylinder(Vector3(0, -1.2, 0), 1.5, r + 0.6, SatStyle.masonry(v), 18, true)
			kit.cylinder(Vector3(0, 0.3, 0), h, r, SatStyle.wall(v), 18, true)
			if kit.lod < 2:
				kit.cylinder(Vector3(0, 0.3 + 3.6, 0), 0.3, r + 0.1, SatStyle.saffron(), 18, false)
			SatTowers._window_ring(kit, r, 0.3 + 2.0, 5, 0.8, 1.4, v * 13, 0.7)
			SatTowers._window_ring(kit, r, 0.3 + 5.4, 6, 0.7, 1.2, v * 17, 0.2)
			if kit.lod < 2:
				KitX.doorway(kit, Vector3(0, 0.3, -r + 0.05), 1.3, 2.4, SatStyle.orange(), SatStyle.saffron(), 0.0)
			SatTowers._crown(kit, r, 0.3 + h, r + 1.5, r * 1.6, v, false)
		1:
			var w := fp.x - 1.0
			var d := fp.y - 1.0
			var h := 7.0
			kit.box(Vector3(0, -0.45, 0), Vector3(w + 0.8, 1.5, d + 0.8), SatStyle.masonry(v), true)
			kit.box(Vector3(0, 0.3 + h * 0.5, 0), Vector3(w, h, d), SatStyle.wall(v))
			_bands(kit, Vector3(0, 0.3, 0), w, d, h)
			if kit.lod < 2:
				kit.box(Vector3(0, 0.3 + 3.4, 0), Vector3(w + 0.1, 0.18, d + 0.1), SatStyle.saffron(), false)
				KitX.doorway(kit, Vector3(0, 0.3, -d * 0.5), 1.4, 2.5, SatStyle.orange(), SatStyle.saffron(), 0.0)
				for row in 2:
					for k in 4:
						var x := lerpf(-w * 0.38, w * 0.38, k / 3.0)
						if row == 0 and absf(x) < 1.6:
							continue
						var lit := ContentHash.unit(ContentHash.hash4(v, row, k, 5)) < 0.3
						SatCivic._flat_arch_window(kit, Vector3(x, 0.3 + 1.9 + row * 3.4, -d * 0.5 - 0.01), 0.8, 1.7, lit)
				# balcony on the upper floor
				kit.box(Vector3(0, 0.3 + 3.55, -d * 0.5 - 0.7), Vector3(w * 0.6, 0.2, 1.4), SatStyle.masonry(1), true)
				if kit.lod == 0:
					kit.railing(PackedVector3Array([Vector3(-w * 0.3, 0.3 + 3.65, -d * 0.5 - 1.35), Vector3(w * 0.3, 0.3 + 3.65, -d * 0.5 - 1.35)]), 0.9,
							{"role": SatStyle.orange(), "post_role": SatStyle.wall(0), "spacing": 0.9})
			_hip(kit, Vector3(0, 0.3 + h, 0), w, d, 3.6, v)
		_:
			var w := fp.x - 5.0
			var d := fp.y - 1.0
			var h := 5.0
			var x0 := -fp.x * 0.5 + 0.5
			kit.box(Vector3(x0 + w * 0.5, -0.45, 0), Vector3(w + 0.8, 1.5, d + 0.8), SatStyle.masonry(v), true)
			kit.box(Vector3(x0 + w * 0.5, 0.3 + h * 0.5, 0), Vector3(w, h, d), SatStyle.wall(v))
			_bands(kit, Vector3(x0 + w * 0.5, 0.3, 0), w, d, h)
			if kit.lod < 2:
				for k in 4:
					var x := x0 + w * (k + 0.5) / 4.0
					if k == 1:
						KitX.doorway(kit, Vector3(x, 0.3, -d * 0.5), 1.3, 2.4, SatStyle.orange(), SatStyle.saffron(), 0.0)
					else:
						SatCivic._flat_arch_window(kit, Vector3(x, 0.3 + 2.0, -d * 0.5 - 0.01), 0.8, 1.7, (k + v) % 3 == 0)
			_hip(kit, Vector3(x0 + w * 0.5, 0.3 + h, 0), w, d, 3.0, v + 1)
			# end tower
			var tc := Vector3(fp.x * 0.5 - 2.4, 0, 0)
			kit.push(Transform3D(Basis(), tc))
			SatTowers.spire(kit, {"r": 2.2, "h": 10.5, "base": -1.2, "v": v + 1, "balcony": false, "door": false, "roof_h": 6.2})
			kit.pop()
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -fp.y * 0.5 - 1.0)))


static func hall(kit: BuildingKit, v: int) -> void:
	var fp := footprint(&"hall", v)
	var w := fp.x - 2.0
	var d := fp.y - 4.0
	var h := 8.0
	var zc := 1.5
	kit.box(Vector3(0, -0.3, 0), Vector3(fp.x, 1.8, fp.y), SatStyle.masonry(v), true)
	kit.stairs(Vector3(0, -0.2, -fp.y * 0.5 - 1.2), Vector3(0, 0.6, -fp.y * 0.5), 6.0, {"role": SatStyle.masonry(2)})
	kit.box(Vector3(0, 0.6 + h * 0.5, zc), Vector3(w, h, d), SatStyle.wall(v))
	_bands(kit, Vector3(0, 0.6, zc), w, d, h)
	if kit.lod < 2:
		KitX.doorway(kit, Vector3(0, 0.6, zc - d * 0.5), 2.2, 3.6, SatStyle.orange(), SatStyle.saffron(), 0.0)
		for sx: float in [-1.0, 1.0]:
			for k in 2:
				SatCivic._flat_arch_window(kit, Vector3(sx * (3.6 + k * 3.4), 0.6 + 3.6, zc - d * 0.5 - 0.01), 1.1, 2.8, (k + v) % 2 == 0)
	# front colonnade
	for k in 6:
		var x := lerpf(-w * 0.45, w * 0.45, k / 5.0)
		kit.column(Vector3(x, 0.6, zc - d * 0.5 - 2.4), h - 1.0, 0.36, SatStyle.wall(v + 1), &"round", SatStyle.masonry(1))
	kit.box(Vector3(0, 0.6 + h - 0.8, zc - d * 0.5 - 2.4), Vector3(w, 0.5, 0.9), SatStyle.orange(), false)
	_hip(kit, Vector3(0, 0.6 + h - 0.5, zc - d * 0.5 - 1.6), w, 2.6, 1.6, v + 1, 0.7)
	_hip(kit, Vector3(0, 0.6 + h, zc), w, d, 5.0, v, 1.3)
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 2.0, 0.6 + h - 1.2, zc - d * 0.5 - 0.1)), 0.9, 3.4, SatStyle.orange(), SatStyle.saffron(), &"swirl")
	_interior_light(kit, Vector3(0, 0.6 + h - 2.0, zc), Color(1.0, 0.82, 0.55), 10.0, 0.8)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -fp.y * 0.5 - 1.6)))


# --- gardens + statues -----------------------------------------------------------------------------

static func garden(kit: BuildingKit, spec: Dictionary) -> void:
	var grass := SatStyle.lin(SatStyle.GRASS)
	if spec.has("r"):
		var r := float(spec["r"])
		var n := 20 if kit.lod == 0 else 10
		var poly := PackedVector2Array()
		var inner := PackedVector2Array()
		for i in n:
			var a := TAU * i / n
			poly.append(Vector2(cos(a), sin(a)) * r)
			inner.append(Vector2(cos(a), sin(a)) * (r - 0.45))
		kit.slab(poly, -0.8, 0.5, SatStyle.masonry(1), true, SatStyle.wall(2))
		if kit.lod < 2:
			kit.slab(inner, 0.4, 0.56, grass, false)
	else:
		var w := float(spec.get("w", 8.0))
		var d := float(spec.get("d", 5.0))
		kit.box(Vector3(0, -0.15, 0), Vector3(w, 1.3, d), SatStyle.masonry(1), true)
		if kit.lod < 2:
			kit.box(Vector3(0, 0.52, 0), Vector3(w + 0.1, 0.12, d + 0.1), SatStyle.wall(2), false)
			kit.box(Vector3(0, 0.53, 0), Vector3(w - 0.6, 0.12, d - 0.6), grass, false)
	if kit.lod == 0:
		var grng := ContentHash.rng(ContentHash.hash4(int(spec.get("seed", 1)), 77))
		var area := PI * pow(float(spec.get("r", 0.0)), 2.0) if spec.has("r") else float(spec.get("w", 8.0)) * float(spec.get("d", 5.0))
		for k in mini(int(area * 1.2), 160):
			var p: Vector3
			if spec.has("r"):
				var a := grng.randf() * TAU
				var rr := sqrt(grng.randf()) * (float(spec["r"]) - 0.7)
				p = Vector3(cos(a) * rr, 0.58, sin(a) * rr)
			else:
				p = Vector3(grng.randf_range(-0.5, 0.5) * (float(spec["w"]) - 0.9), 0.58, grng.randf_range(-0.5, 0.5) * (float(spec["d"]) - 0.9))
			KitX.grass_tuft(kit, p, grng.randf_range(0.25, 0.5), grass * grng.randf_range(0.85, 1.2), grng)


static func statue(kit: BuildingKit, v: int) -> void:
	var stone := SatStyle.masonry(2) * 1.05
	var stone2 := SatStyle.masonry(0)
	# stepped pedestal (long for the resting bison)
	var pl := 7.0 if v % 3 == 2 else 3.2
	kit.box(Vector3(0, 0.4, 0), Vector3(4.2, 0.8, pl + 1.0), SatStyle.masonry(1), true)
	kit.box(Vector3(0, 1.3, 0), Vector3(3.2, 1.0, pl), SatStyle.wall(1), true)
	if kit.lod < 2:
		kit.box(Vector3(0, 1.82, 0), Vector3(3.5, 0.12, pl + 0.3), SatStyle.orange(), false)
		KitX.emblem_air(kit, Vector3(0, 1.3, -pl * 0.5 - 0.01), 0.8, SatStyle.saffron(), 0.02)
	var b := Vector3(0, 1.88, 0)
	var g := kit.g()
	var sub := 1 if kit.lod == 0 else 0
	match v % 3:
		0:
			# seated monk in meditation: crossed legs, robe, folded hands, bald head
			g.blob(b + Vector3(0, 0.45, 0), 1.0, sub, kit.col(stone), null, 0.0, Vector3(1.25, 0.45, 0.95))
			g.cylinder(b + Vector3(0, 0.6, 0.1), b + Vector3(0, 2.3, 0.05), 0.85, 0.55, 10, kit.col(stone), 1)
			g.blob(b + Vector3(0, 2.35, 0.05), 0.5, sub, kit.col(stone2), null, 0.0, Vector3(1.6, 0.5, 1.0))
			g.blob(b + Vector3(0, 2.95, 0.0), 0.42, sub + 1, kit.col(stone))
			g.blob(b + Vector3(0, 1.05, -0.62), 0.3, sub, kit.col(stone), null, 0.0, Vector3(1.4, 0.6, 1.0))
			for sx: float in [-1.0, 1.0]:
				g.tube(PackedVector3Array([b + Vector3(sx * 0.7, 2.2, 0.05), b + Vector3(sx * 0.8, 1.5, -0.25), b + Vector3(sx * 0.25, 1.1, -0.6)]),
						PackedFloat32Array([0.24, 0.2, 0.16]), 6, kit.col(stone))
			if kit.lod < 2:
				# the arrow on the head
				g.box(Transform3D(Basis(Vector3.RIGHT, -0.5), b + Vector3(0, 3.3, -0.12)), Vector3(0.12, 0.03, 0.5), kit.col(SatStyle.sky()))
		1:
			# standing monk holding a glider staff
			g.cylinder(b, b + Vector3(0, 2.4, 0), 0.8, 0.5, 10, kit.col(stone), 1)
			g.blob(b + Vector3(0, 2.55, 0), 0.55, sub, kit.col(stone2), null, 0.0, Vector3(1.4, 0.45, 0.9))
			g.blob(b + Vector3(0, 3.2, 0), 0.4, sub + 1, kit.col(stone))
			g.cylinder(b + Vector3(0.75, 0.0, -0.3), b + Vector3(0.75, 4.2, -0.3), 0.07, 0.07, 6, kit.col(stone2), 2)
			g.tube(PackedVector3Array([b + Vector3(-0.5, 2.5, 0), b + Vector3(-0.6, 1.6, -0.2)]), PackedFloat32Array([0.2, 0.16]), 6, kit.col(stone))
			g.tube(PackedVector3Array([b + Vector3(0.5, 2.5, 0), b + Vector3(0.75, 2.0, -0.3)]), PackedFloat32Array([0.2, 0.16]), 6, kit.col(stone))
			if kit.lod < 2:
				for sx: float in [-1.0, 1.0]:
					g.box(Transform3D(Basis(Vector3.UP, sx * 0.4), b + Vector3(0.75 + sx * 0.55, 3.9, -0.3)), Vector3(1.0, 0.05, 0.4), kit.col(stone2))
		_:
			# resting sky bison: long furry body with a scalloped fringe, six tucked legs, the
			# broad flat face with curving horns, a wide fan tail, the arrow inlaid down its back
			var fur := SatStyle.lin(Color(0.86, 0.82, 0.74))
			var fur2 := SatStyle.lin(Color(0.74, 0.70, 0.62))
			var arrow := SatStyle.lin(Color(0.46, 0.34, 0.24))
			g.blob(b + Vector3(0, 1.05, 0.2), 1.0, sub + 1, kit.col(fur), null, 0.0, Vector3(1.45, 0.95, 2.1))
			if kit.lod < 2:
				# fur fringe: a ring of soft lobes around the belly
				for k in 14:
					var a := TAU * k / 14.0
					g.blob(b + Vector3(cos(a) * 1.35, 0.42, 0.2 + sin(a) * 1.95), 0.34, 0, kit.col(fur2), null, 0.0, Vector3(1.0, 0.8, 1.0))
			for sx: float in [-1.0, 1.0]:
				for fz: float in [-1.2, 0.2, 1.5]:
					g.blob(b + Vector3(sx * 1.15, 0.28, fz), 0.32, 0, kit.col(fur2), null, 0.0, Vector3(1.0, 0.75, 1.3))
			# head: broad, flat-faced, low in front of the body
			var hc := b + Vector3(0, 1.15, -2.15)
			g.blob(hc, 0.72, sub, kit.col(fur), null, 0.0, Vector3(1.25, 0.95, 0.95))
			g.blob(hc + Vector3(0, -0.22, -0.5), 0.42, 0, kit.col(fur2), null, 0.0, Vector3(1.3, 0.75, 0.7))
			for sx: float in [-1.0, 1.0]:
				g.tube(PackedVector3Array([hc + Vector3(sx * 0.55, 0.45, 0.05), hc + Vector3(sx * 1.05, 0.62, 0.05), hc + Vector3(sx * 1.2, 1.05, -0.2)]),
						PackedFloat32Array([0.13, 0.09, 0.025]), 6, kit.col(SatStyle.lin(Color(0.62, 0.55, 0.44))))
				g.blob(hc + Vector3(sx * 0.33, 0.12, -0.62), 0.07, 0, kit.col(arrow))
			# the broad fan tail
			g.blob(b + Vector3(0, 0.75, 2.55), 0.75, 0, kit.col(fur), null, 0.0, Vector3(1.6, 0.32, 1.0))
			if kit.lod < 2:
				# the arrow: a stripe down the back widening into the head chevron
				var spine := PackedVector3Array([b + Vector3(0, 2.02, 1.6), b + Vector3(0, 2.0, 0.2), b + Vector3(0, 1.82, -1.3), hc + Vector3(0, 0.62, -0.1)])
				g.tube(spine, PackedFloat32Array([0.12, 0.16, 0.16, 0.12]), 5, kit.col(arrow))
				for sx: float in [-1.0, 1.0]:
					g.tube(PackedVector3Array([hc + Vector3(0, 0.66, -0.1), hc + Vector3(sx * 0.32, 0.55, -0.42)]), PackedFloat32Array([0.12, 0.07]), 5, kit.col(arrow))
	kit.collide_box(Vector3(0, 3.4, 0), Vector3(2.4, 3.0, minf(pl, 5.6)))
