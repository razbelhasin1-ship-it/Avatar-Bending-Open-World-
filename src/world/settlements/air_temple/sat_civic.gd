class_name SatCivic
extends RefCounted
## Southern Air Temple civic architecture (BuildingKit recipes, thread-safe):
##   tier_wall    one chord of a 20 m retaining wall between temple tiers. Local frame: x along the
##                wall (-L/2..L/2), the FACE at z = 0 looking -Z towards the lower (outer) tier,
##                the body behind it (z 0..depth), y = 0 on the lower ground, top flush with the
##                upper tier at H. Coursed masonry with a plinth, buttress piers, an orange band,
##                gallery windows / arched niches and banners, and a balustrade on top.
##   edge_rail    balustrade chord along a cliff edge (x along, -Z = the drop), collides.
##   stair        grand stair over a radial ramp (foot at the origin, climbing towards -Z): stone
##                flights, masonry cheek walls with orange copings, stone lanterns at the foot.
##   gateway      Air Nomad gate: round pillars with teal caps, an upswept orange lintel carrying
##                the air swirl and a row of bronze bells; passage along Z.
##   sky_bridge   one segment (t0..t1) of a suspended plank bridge between two cliff anchors:
##                planks, walkable deck strip, rope barriers, handrail and foot ropes, hangers,
##                prayer-flag lines on poles. Built with yaw 0 (local = world - pos).
##   court        paved disc with an inlaid air swirl (plazas, the bison landing circle).


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"tier_wall": tier_wall(kit, spec)
		&"edge_rail": edge_rail(kit, spec)
		&"stair": stair(kit, spec)
		&"gateway": gateway(kit, spec)
		&"sky_bridge": sky_bridge(kit, spec)
		&"court": court(kit, spec)


## Archetype key of a wall chord.
static func wall_arch(spec: Dictionary) -> String:
	return "sat_wall:%d:%d:%d:%d:%d:%d" % [roundi(float(spec["L"]) * 10.0), roundi(float(spec["H"]) * 10.0),
		roundi(float(spec.get("bottom", -1.2)) * 10.0), int(spec.get("v", 0)), int(spec.get("rail", true)),
		roundi(float(spec.get("depth", 5.6)) * 2.0)]


static func tier_wall(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec["L"])
	var H := float(spec["H"])
	var depth := float(spec.get("depth", 5.6))
	var bottom := float(spec.get("bottom", -1.2))
	var v := int(spec.get("v", 0))
	var hl := L * 0.5
	var stone := SatStyle.masonry(v % 2)
	kit.box(Vector3(0, (H + bottom) * 0.5, depth * 0.5), Vector3(L + 0.04, H - bottom, depth), stone)
	if kit.lod >= 2:
		if H > 6.0:
			kit.box(Vector3(0, H - 2.4, -0.1), Vector3(L, 0.8, 0.2), SatStyle.orange(), false)
		if spec.get("rail", true):
			kit.box(Vector3(0, H + 0.5, 0.4), Vector3(L, 1.0, 0.6), SatStyle.wall(0), false)
		return
	# plinth, orange band under the parapet, buttress pier at the chord joint
	kit.box(Vector3(0, 0.6, -0.15), Vector3(L, 1.6, 0.3), SatStyle.masonry(v + 1), false)
	if H > 6.0:
		kit.box(Vector3(0, H - 2.4, -0.12), Vector3(L, 0.7, 0.24), SatStyle.orange(), false)
		kit.box(Vector3(0, H - 1.85, -0.08), Vector3(L, 0.16, 0.16), SatStyle.saffron(), false)
		kit.box(Vector3(-hl, (H + bottom) * 0.5 - 0.6, -0.45), Vector3(1.4, H - bottom - 1.2, 0.9), SatStyle.masonry(v + 2), true)
		kit.box(Vector3(-hl, H - 1.0, -0.55), Vector3(1.7, 0.5, 1.1), SatStyle.orange(), false)
		if kit.lod == 0:
			kit.box(Vector3(-hl, 0.7, -0.6), Vector3(1.8, 1.4, 1.2), SatStyle.masonry(v + 1), false)
			KitX.joints(kit, -hl + 0.7, hl - 0.2, 1.4, H - 2.8, 0.0, 1.6, -1.0, SatStyle.masonry(v + 1) * 0.86)
		if H > 12.0:
			match v % 4:
				0, 3:
					# the monastery halls built into the tier: storeys of arched windows, a
					# balcony on one storey and teal pent roofs over the top row
					_facade(kit, L, H, v)
				1:
					# a shallow framed arch panel with a hanging banner
					_relief_arch(kit, Vector3(hl * 0.1, 1.2, 0.0), 3.6, minf(H * 0.62, 12.0), v)
					KitX.banner(kit, Transform3D(Basis(), Vector3(hl * 0.1, H - 2.8, -0.35)), 1.5, minf(H * 0.45, 8.0),
							SatStyle.orange(), SatStyle.saffron(), &"swirl")
				2:
					for sx: float in [-1.0, 1.0]:
						_flat_arch_window(kit, Vector3(sx * hl * 0.42, H * 0.42, 0.0), 1.2, 4.2,
								ContentHash.unit(ContentHash.hash4(int(L * 10.0), int(sx), v)) < 0.35)
					if kit.lod == 0:
						KitX.emblem_air(kit, Vector3(0, H * 0.66, 0.0), 2.6, SatStyle.saffron(), 0.1)
	if spec.get("rail", true):
		_balustrade(kit, Vector3(-hl, H, 0.45), Vector3(hl, H, 0.45), 1.05, v)
	if kit.lod == 0:
		kit.box(Vector3(0, H + 0.03, depth * 0.55), Vector3(L, 0.06, depth * 0.7), SatStyle.masonry(v) * 1.04, false)


## Storeys of the halls inside a tier wall (face at z = 0 looking -Z): window rows every 5.5 m,
## lit at random, a balcony with an orange railing on the second storey (v even), teal pent
## roofs over the top row, a cream wash panel behind the windows so the face reads as a building.
static func _facade(kit: BuildingKit, L: float, H: float, v: int) -> void:
	var hl := L * 0.5
	var rows := maxi(int((H - 5.0) / 5.5), 1)
	kit.box(Vector3(0.35, (H - 2.9 + 1.4) * 0.5, -0.06), Vector3(L - 1.6, H - 2.9 - 1.4, 0.1), SatStyle.wall(v), false)
	var n := maxi(int((L - 1.6) / 3.4), 1)
	for row in rows:
		var y := 4.0 + row * 5.5
		for k in n:
			var x := lerpf(-hl + 1.9, hl - 1.2, (k + 0.5) / n)
			var lit := ContentHash.unit(ContentHash.hash4(int(L * 10.0) + row * 7, k, v, 3)) < 0.32
			_flat_arch_window(kit, Vector3(x, y, -0.1), 1.0, 2.3, lit)
		if row == 1 and v % 2 == 0:
			kit.box(Vector3(0.35, y - 1.45, -0.75), Vector3(L - 1.8, 0.22, 1.4), SatStyle.masonry(v + 2), true)
			if kit.lod == 0:
				for k in n + 1:
					var x := lerpf(-hl + 1.0, hl - 0.3, float(k) / n)
					kit.beam(Vector3(x, y - 2.6, -0.1), Vector3(x, y - 1.6, -1.2), 0.2, 0.2, SatStyle.masonry(v + 1))
				kit.railing(PackedVector3Array([Vector3(-hl + 1.0, y - 1.34, -1.35), Vector3(hl - 0.3, y - 1.34, -1.35)]), 0.85,
						{"role": SatStyle.orange(), "post_role": SatStyle.wall(0), "spacing": 0.8, "collide": true})
		if row == rows - 1:
			_pent_roof(kit, -hl + 1.0, hl - 0.3, y + 1.85, 1.2, v)


## Lean-to roof strip on a wall face (x0..x1 at height y, projecting `d` towards -Z).
static func _pent_roof(kit: BuildingKit, x0: float, x1: float, y: float, d: float, v: int) -> void:
	var g := kit.g()
	var top := kit.col(SatStyle.roof(v))
	var under := kit.col(&"roof_under")
	var a := Vector3(x0, y + 0.55, 0.0)
	var b := Vector3(x1, y + 0.55, 0.0)
	var c := Vector3(x1, y, -d)
	var e := Vector3(x0, y, -d)
	g.flat_quad(a, b, c, e, top)
	g.flat_quad(e - Vector3(0, 0.12, 0), c - Vector3(0, 0.12, 0), b - Vector3(0, 0.12, 0), a - Vector3(0, 0.12, 0), under)
	g.flat_quad(e - Vector3(0, 0.12, 0), e, c, c - Vector3(0, 0.12, 0), kit.col(SatStyle.gold()))
	kit.collide_quad(a, b, c, e)
	if kit.lod == 0:
		for k in int((x1 - x0) / 0.5):
			var x := x0 + 0.25 + k * 0.5
			g.cylinder(Vector3(x, y + 0.57, 0.0), Vector3(x, y + 0.03, -d), 0.05, 0.05, 3, top * 0.8, 0)


## Shallow framed arch panel (lighter masonry inset with an orange frame) on a -Z face.
static func _relief_arch(kit: BuildingKit, c: Vector3, w: float, h: float, v: int) -> void:
	var spring := h - w * 0.5
	kit.box(c + Vector3(0, spring * 0.5, -0.04), Vector3(w, spring, 0.08), SatStyle.wall(v + 1), false)
	var segs := 8 if kit.lod == 0 else 4
	var g := kit.g()
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		var p0 := c + Vector3(cos(a0) * w * 0.5, spring + sin(a0) * w * 0.5, -0.06)
		var p1 := c + Vector3(cos(a1) * w * 0.5, spring + sin(a1) * w * 0.5, -0.06)
		g.flat_tri(c + Vector3(0, spring, -0.06), p1, p0, kit.col(SatStyle.wall(v + 1)))
		kit.beam(p0 + Vector3(0, 0, -0.08), p1 + Vector3(0, 0, -0.08), 0.32, 0.22, SatStyle.orange())
	for sx: float in [-1.0, 1.0]:
		kit.box(c + Vector3(sx * (w * 0.5 + 0.16), spring * 0.5, -0.14), Vector3(0.32, spring, 0.22), SatStyle.orange(), false)


## Arched window flush with a flat face facing -Z at local `c` (centre).
static func _flat_arch_window(kit: BuildingKit, c: Vector3, w: float, h: float, lit: bool) -> void:
	kit.push(Transform3D(Basis(), c))
	var slot: StringName = &"glow" if lit else &"solid"
	var col: Color = KitX.lit_window_color(kit) if lit else kit.col(&"window", false)
	kit.g(slot).box(Transform3D(Basis(), Vector3(0, -h * 0.15, -0.05)), Vector3(w, h * 0.7, 0.06), col)
	var segs := 6 if kit.lod == 0 else 3
	var top := h * 0.2
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		var p0 := Vector3(cos(a0) * w * 0.5, top + sin(a0) * w * 0.5, -0.06)
		var p1 := Vector3(cos(a1) * w * 0.5, top + sin(a1) * w * 0.5, -0.06)
		kit.g(slot).flat_tri(Vector3(0, top, -0.06), p1, p0, col)
		if kit.lod == 0:
			kit.beam(p0 + Vector3(0, 0, -0.06), p1 + Vector3(0, 0, -0.06), 0.16, 0.16, SatStyle.orange())
	if kit.lod == 0:
		for sx: float in [-1.0, 1.0]:
			kit.box(Vector3(sx * (w * 0.5 + 0.08), -h * 0.15, -0.1), Vector3(0.16, h * 0.7, 0.16), SatStyle.orange(), false)
		kit.box(Vector3(0, -h * 0.5 - 0.05, -0.14), Vector3(w + 0.5, 0.12, 0.3), SatStyle.masonry(2), false)
	kit.pop()


## Balustrade from a to b (base points on the walking surface, local): plinth, balusters, an
## orange coping rail; collides as one box.
static func _balustrade(kit: BuildingKit, a: Vector3, b: Vector3, h: float, v: int) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.3:
		return
	var x := d / length
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())
	var mid := (a + b) * 0.5
	kit.box_t(Transform3D(basis, mid + Vector3(0, 0.15, 0)), Vector3(length, 0.3, 0.5), SatStyle.wall(v + 1), false)
	kit.box_t(Transform3D(basis, mid + Vector3(0, h - 0.08, 0)), Vector3(length + 0.04, 0.16, 0.42), SatStyle.orange(), false)
	if kit.lod == 0:
		var n := maxi(int(length / 0.55), 1)
		for i in n:
			var p := a + x * (length * (i + 0.5) / n)
			kit.g().cylinder(p + Vector3(0, 0.3, 0), p + Vector3(0, h - 0.16, 0), 0.1, 0.1, 6, kit.col(SatStyle.wall(v)), 0)
			kit.g().blob(p + Vector3(0, h * 0.55, 0), 0.13, 0, kit.col(SatStyle.wall(v)), null, 0.0, Vector3(1, 1.6, 1))
	else:
		kit.box_t(Transform3D(basis, mid + Vector3(0, h * 0.5, 0)), Vector3(length, h - 0.3, 0.2), SatStyle.wall(v), false)
	kit.boxes.append([kit.xform * Transform3D(basis, mid + Vector3(0, h * 0.5 + 0.1, 0)), Vector3(length, h + 0.2, 0.45)])


## Balustrade chord along a cliff edge. spec: L, v, posts (bool: lantern posts at the ends).
static func edge_rail(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 8.0))
	var v := int(spec.get("v", 0))
	# footing reaching into the ground so slopes never show a gap
	kit.box(Vector3(0, -0.6, 0.2), Vector3(L + 0.05, 1.5, 0.9), SatStyle.masonry(v), false)
	_balustrade(kit, Vector3(-L * 0.5, 0.0, 0.0), Vector3(L * 0.5, 0.0, 0.0), 1.05, v)
	if kit.lod < 2:
		kit.box(Vector3(-L * 0.5, 0.65, 0.0), Vector3(0.55, 1.3, 0.55), SatStyle.wall(v + 2), false)
		if kit.lod == 0:
			kit.ornament(Vector3(-L * 0.5, 1.3, 0.0), &"orb", 0.36, SatStyle.saffron())
		if spec.get("lamp", false):
			kit.lantern(Vector3(-L * 0.5, 1.3, 0.0), {"style": &"stone", "height": 0.9, "range": 9.0, "energy": 1.4})


## Grand stair over a ramp: rise H over run R (local -Z), strip width W. spec: H, R, W, half
## (distance from the foot where the outside ground switches from the lower to the upper tier).
static func stair(kit: BuildingKit, spec: Dictionary) -> void:
	var H := float(spec["H"])
	var R := float(spec["R"])
	var W := float(spec.get("W", 12.0))
	var half := float(spec.get("half", R * 0.5))
	var sw := W - 3.0
	kit.stairs(Vector3(0, 0.0, 0.0), Vector3(0, H, -R), sw, {"role": SatStyle.masonry(2), "rise": 0.22})
	if kit.lod == 0:
		# landings every third of the climb: lighter slabs with an inlaid orange strip
		for k: int in [1, 2]:
			var z := -R * k / 3.0
			kit.box(Vector3(0, H * k / 3.0 + 0.02, z), Vector3(sw, 0.06, 0.8), SatStyle.wall(0), false)
	var nseg := maxi(int(R / 3.4), 2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (sw * 0.5 + 0.75)
		for k in nseg:
			var z0 := -R * k / nseg
			var z1 := -R * (k + 1) / nseg
			var ry0 := H * k / nseg
			var ry1 := H * (k + 1) / nseg
			var outside := 0.0 if -z1 <= half else H
			var top := maxf(ry1, outside)
			kit.box(Vector3(x, (top - 1.2) * 0.5, (z0 + z1) * 0.5), Vector3(1.5, top + 1.2, absf(z1 - z0) + 0.02), SatStyle.masonry(k % 2))
			if outside < ry1 + 0.01 or -z0 < half:
				kit.beam(Vector3(x, ry0 + 0.55, z0), Vector3(x, ry1 + 0.55, z1), 1.2, 1.1, SatStyle.wall(1), true)
		if kit.lod < 2:
			kit.beam(Vector3(x, 1.12, 0.0), Vector3(x, H + 1.12, -R), 1.35, 0.2, SatStyle.orange())
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			var p := Vector3(sx * (sw * 0.5 + 0.75), 0.0, 1.0)
			kit.box(p + Vector3(0, 0.9, 0), Vector3(1.5, 1.8, 1.5), SatStyle.wall(2), true)
			kit.box(p + Vector3(0, 1.85, 0), Vector3(1.7, 0.18, 1.7), SatStyle.orange(), false)
			kit.lantern(p + Vector3(0, 1.95, 0), {"style": &"stone", "height": 1.3, "range": 10.0, "energy": 1.5})
			var q := Vector3(sx * (sw * 0.5 + 0.75), H, -R - 0.6)
			kit.box(q + Vector3(0, 0.6, 0), Vector3(1.5, 1.2, 1.5), SatStyle.wall(2), true)
			if kit.lod == 0:
				kit.ornament(q + Vector3(0, 1.3, 0), &"orb", 0.6, SatStyle.saffron())


## Air Nomad gate. spec: span (clear width), height (clear), roof (bool: small teal roof on the
## lintel), bells (bool).
static func gateway(kit: BuildingKit, spec: Dictionary) -> void:
	var span := float(spec.get("span", 6.0))
	var h := float(spec.get("height", 6.0))
	var pr := clampf(span * 0.07, 0.38, 0.75)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (span * 0.5 + pr)
		kit.box(Vector3(x, 0.35, 0), Vector3(pr * 3.0, 0.7, pr * 3.0), SatStyle.masonry(1), true)
		kit.cylinder(Vector3(x, 0.7, 0), h + 0.5, pr, SatStyle.wall(0), 12, true, pr * 0.9)
		if kit.lod < 2:
			for band: float in [1.2, h * 0.7]:
				kit.cylinder(Vector3(x, band, 0), 0.22, pr + 0.06, SatStyle.orange(), 12, false)
		KitRoofs.cone(kit, Vector3(x, h + 1.9, 0), pr * 1.9, pr * 3.2, SatStyle.cone_opts(1, 12, 0.5))
	# upswept lintel: a beam bowed upward at both ends
	var lw := span + pr * 4.0 + 1.6
	var segs := 6 if kit.lod == 0 else 2
	var prev := Vector3.ZERO
	for i in segs + 1:
		var t := float(i) / segs
		var x := lerpf(-lw * 0.5, lw * 0.5, t)
		var y := h + 1.2 + pow(absf(t - 0.5) * 2.0, 3.0) * 0.8
		var p := Vector3(x, y, 0)
		if i > 0:
			kit.beam(prev, p, 0.7, 0.55, SatStyle.orange(), true)
		prev = p
	kit.box(Vector3(0, h + 0.55, 0), Vector3(span + pr * 2.0, 0.35, 0.45), SatStyle.saffron(), false)
	if kit.lod < 2:
		kit.g().cylinder(Vector3(0, h + 1.35, -0.32), Vector3(0, h + 1.35, 0.32), 0.85, 0.85, 14, kit.col(SatStyle.sky()), 2)
		KitX.emblem_air(kit, Vector3(0, h + 1.35, -0.32), 1.25, SatStyle.gold(), 0.04)
		var back := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		kit.push(back)
		KitX.emblem_air(kit, Vector3(0, h + 1.35, -0.32), 1.25, SatStyle.gold(), 0.04)
		kit.pop()
		if spec.get("roof", false):
			KitRoofs.hip(kit, Vector3(0, h + 1.8, 0), lw - 0.6, 1.4, 1.3, {"role": SatStyle.roof(0), "alt_role": SatStyle.roof_stripe(0),
				"ridge_role": SatStyle.gold(), "curve": 0.6, "overhang": 0.5, "ornaments": kit.lod == 0})
		if spec.get("bells", true) and kit.lod == 0:
			var nb := maxi(int(span / 1.4), 2)
			for k in nb:
				var x := lerpf(-span * 0.4, span * 0.4, float(k) / maxf(nb - 1, 1))
				kit.g().cylinder(Vector3(x, h + 0.38, 0), Vector3(x, h - 0.1, 0), 0.008, 0.008, 3, kit.col(&"wood_dark"), 0)
				kit.g().cone(Vector3(x, h - 0.42, 0), Vector3(x, h - 0.08, 0), 0.16, 8, kit.col(SatStyle.gold()))


## One segment of a suspended plank bridge. spec: a, b (deck anchors, world), width, t0, t1
## (segment range along a->b), origin (= piece pos: the frame is yaw 0, local = world - pos),
## profile (deck heights relative to a.y every metre, SatPlanner.deck_profile), poles (bool).
static func sky_bridge(kit: BuildingKit, spec: Dictionary) -> void:
	var pos: Vector3 = spec["origin"]
	var a: Vector3 = (spec["a"] as Vector3) - pos
	var b: Vector3 = (spec["b"] as Vector3) - pos
	var width := float(spec.get("width", 3.2))
	var t0 := float(spec.get("t0", 0.0))
	var t1 := float(spec.get("t1", 1.0))
	var prof: PackedFloat32Array = spec["profile"]
	var dir := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := dir.length()
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var yaw := atan2(dir.x, dir.z)
	var deck := func(t: float) -> float:
		return SatPlanner.deck_y(prof, t) + a.y
	var seg_len := (t1 - t0) * length
	# planks
	var plank := 0.34
	var n := maxi(int(seg_len / (plank + 0.07)), 1)
	if kit.lod >= 2:
		var m := maxi(int(seg_len / 6.0), 1)
		for i in m:
			var ta := lerpf(t0, t1, float(i) / m)
			var tb := lerpf(t0, t1, float(i + 1) / m)
			var pa := a.lerp(b, ta)
			var pb := a.lerp(b, tb)
			pa.y = deck.call(ta)
			pb.y = deck.call(tb)
			kit.beam(pa - Vector3(0, 0.15, 0), pb - Vector3(0, 0.15, 0), width + 0.3, 0.3, &"wood_dark")
		return
	for i in n:
		var t := lerpf(t0, t1, (float(i) + 0.5) / n)
		var ta := lerpf(t0, t1, float(i) / n)
		var tb := lerpf(t0, t1, float(i + 1) / n)
		var p := a.lerp(b, t)
		p.y = deck.call(t)
		var slope := atan2(float(deck.call(tb)) - float(deck.call(ta)), seg_len / n)
		var basis := Basis(side, Vector3.UP.rotated(side, slope), -dir.rotated(side, slope)).orthonormalized()
		if kit.lod == 0:
			kit.box_t(Transform3D(basis, p - Vector3(0, 0.05, 0)), Vector3(width + kit.rng.randf_range(-0.12, 0.12), 0.09, plank),
					&"wood" if i % 5 else &"wood_dark", false)
		elif i % 3 == 0:
			kit.box_t(Transform3D(basis, p - Vector3(0, 0.05, 0)), Vector3(width, 0.09, (plank + 0.07) * 3.0), &"wood", false)
	# deck collision strip + rope barriers
	var segs := maxi(int(seg_len / 2.0), 1)
	var hw := side * width * 0.5
	for i in segs:
		var ta := lerpf(t0, t1, float(i) / segs)
		var tb := lerpf(t0, t1, float(i + 1) / segs)
		var p0 := a.lerp(b, ta)
		var p1 := a.lerp(b, tb)
		p0.y = deck.call(ta)
		p1.y = deck.call(tb)
		kit.collide_quad(p0 - hw, p0 + hw, p1 + hw, p1 - hw)
		for s: float in [-1.0, 1.0]:
			var m := (p0 + p1) * 0.5 + side * s * (width * 0.5 + 0.08) + Vector3(0, 0.6, 0)
			var sb := Basis(side, Vector3.UP, (p1 - p0).normalized()).orthonormalized()
			kit.boxes.append([kit.xform * Transform3D(sb, m), Vector3(0.12, 1.3, p0.distance_to(p1) + 0.05)])
	# ropes, hangers, flag lines
	var rail_h := 1.05
	var nr := maxi(int(seg_len / 2.5), 2)
	for s: float in [-1.0, 1.0]:
		var rope := PackedVector3Array()
		var foot := PackedVector3Array()
		for i in nr + 1:
			var t := lerpf(t0, t1, float(i) / nr)
			var p := a.lerp(b, t) + side * s * (width * 0.5 + 0.06)
			var dy: float = deck.call(t)
			foot.append(Vector3(p.x, dy + 0.02, p.z))
			rope.append(Vector3(p.x, dy + rail_h + 0.18 * (1.0 - 4.0 * t * (1.0 - t)), p.z))
		var radii := PackedFloat32Array()
		radii.resize(rope.size())
		radii.fill(0.04)
		kit.g().tube(rope, radii, 4, kit.col(&"wood_dark"))
		kit.g().tube(foot, radii, 4, kit.col(&"wood_dark"))
		if kit.lod == 0:
			for i in range(1, rope.size() - 1):
				kit.g().cylinder(foot[i], rope[i], 0.02, 0.02, 3, kit.col(&"wood_dark"), 0)
	if spec.get("poles", true) and kit.lod == 0:
		# prayer-flag lines strung between poles on both rails
		var np := maxi(int(seg_len / 12.0), 1)
		var flag_roles: Array = [SatStyle.orange(), SatStyle.saffron(), SatStyle.sky(), SatStyle.wall(0), Color(0.75, 0.22, 0.16).srgb_to_linear()]
		for s: float in [-1.0, 1.0]:
			var tops: Array[Vector3] = []
			for k in np + 1:
				var t := lerpf(t0, t1, float(k) / np)
				var p := a.lerp(b, t) + side * s * (width * 0.5 + 0.12)
				p.y = deck.call(t)
				kit.g().cylinder(p, p + Vector3(0, 2.6, 0), 0.05, 0.04, 5, kit.col(&"wood_dark"), 1)
				tops.append(p + Vector3(0, 2.55, 0))
			for k in np:
				KitX.flag_string(kit, tops[k], tops[k + 1], 0.45, flag_roles, 0.3)
	kit.mark(&"deck", Transform3D(Basis(Vector3.UP, yaw), a.lerp(b, (t0 + t1) * 0.5)))


## Paved disc with an inlaid air swirl. spec: r, swirl (bool).
static func court(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 10.0))
	var sides := 32 if kit.lod == 0 else 16
	var ring := func(rad: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in sides:
			var a := TAU * i / sides
			pts.append(Vector2(cos(a), sin(a)) * rad)
		return pts
	kit.slab(ring.call(r), -0.4, 0.06, SatStyle.masonry(1), true, SatStyle.wall(1))
	if kit.lod >= 2:
		return
	kit.slab(ring.call(r - 0.5), 0.0, 0.08, SatStyle.orange(), false)
	kit.slab(ring.call(r - 1.0), 0.0, 0.09, SatStyle.wall(0), false)
	if kit.lod == 0:
		for i in 12:
			var a := TAU * i / 12.0
			kit.beam(Vector3(cos(a), 0, sin(a)) * (r * 0.62) + Vector3(0, 0.095, 0), Vector3(cos(a), 0, sin(a)) * (r - 1.1) + Vector3(0, 0.095, 0),
					0.08, 0.02, SatStyle.masonry(2))
	if spec.get("swirl", true):
		kit.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.1, 0)))
		KitX.emblem_air(kit, Vector3.ZERO, r * 1.1, SatStyle.orange(), 0.0)
		kit.pop()
