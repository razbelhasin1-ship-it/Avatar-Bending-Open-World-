class_name SatTowers
extends RefCounted
## The spires of the Southern Air Temple (BuildingKit recipes, thread-safe; origin = ground
## centre, -Z = front). Every tower reads at three LODs: LOD2 keeps the shaft, the eave drum and
## the flared blue-teal cone so the cluster of spires reads from kilometres away.
##   spire        round cream tower: masonry foot (reaching `base` metres below the origin, so
##                towers stand on lower terraces or cling to the cliff), orange / saffron bands,
##                arched windows, optional balcony ring with railing and banners, eave drum, a
##                deeply flared cone with a gold finial, optional cupola (second drum + cone)
##   great_spire  the Sanctum's central spire: stepped podium, cross-shaped hall with four teal
##                hip-roofed wings, the tall shaft with two balconies, the great cone and cupola
##
## spire spec: r (shaft radius), h (shaft top above the origin), base (foot, <= 0), roof_h,
## roof_r (eave radius, default r + 1.8), v (tint/roof variant), balcony (bool), cupola (bool),
## door (bool), banners (bool).


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"spire": spire(kit, spec)
		&"great_spire": great_spire(kit, spec)


## Arched window on the shaft surface at angle `a` (radians, 0 = +X), centre height y.
static func _shaft_window(kit: BuildingKit, r: float, a: float, y: float, w: float, h: float, lit: bool) -> void:
	var dir := Vector3(cos(a), 0, sin(a))
	kit.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI), dir * (r - 0.03) + Vector3(0, y, 0)))
	if lit:
		KitX.glow(kit, Vector3(0, 0, -0.25), SettlementFx.GLOW_WINDOW, clampf(w * 1.1, 0.7, 1.6))
	if kit.lod >= 2:
		if lit:
			kit.g(&"glow").box(Transform3D(Basis(), Vector3(0, 0, -0.06)), Vector3(w * 1.2, h * 1.1, 0.05), KitX.lit_window_color(kit) * 1.1)
	else:
		if lit:
			kit.g(&"glow").box(Transform3D(Basis(), Vector3(0, -h * 0.1, -0.05)), Vector3(w, h * 0.8, 0.05), KitX.lit_window_color(kit))
		else:
			kit.box(Vector3(0, -h * 0.1, -0.05), Vector3(w, h * 0.8, 0.06), &"window", false)
		# arched head: a dark half disc + orange frame ring
		var segs := 6 if kit.lod == 0 else 3
		var gb := kit.g()
		var dark := kit.col(&"window", false) if not lit else KitX.lit_window_color(kit)
		var top := h * 0.3
		for i in segs:
			var a0 := PI * float(i) / segs
			var a1 := PI * float(i + 1) / segs
			var p0 := Vector3(cos(a0) * w * 0.5, top + sin(a0) * w * 0.5, -0.06)
			var p1 := Vector3(cos(a1) * w * 0.5, top + sin(a1) * w * 0.5, -0.06)
			if lit:
				kit.g(&"glow").flat_tri(Vector3(0, top, -0.06), p1, p0, dark)
			else:
				gb.flat_tri(Vector3(0, top, -0.06), p1, p0, dark)
			if kit.lod == 0:
				kit.beam(p0 + Vector3(0, 0, -0.05), p1 + Vector3(0, 0, -0.05), 0.12, 0.12, SatStyle.orange())
		if kit.lod == 0:
			kit.box(Vector3(0, -h * 0.5 - 0.04, -0.1), Vector3(w + 0.3, 0.1, 0.2), SatStyle.orange(), false)
	kit.pop()


## Ring of `n` lit / dark arched windows around a shaft at height y.
static func _window_ring(kit: BuildingKit, r: float, y: float, n: int, w: float, h: float, seed: int, phase: float = 0.0) -> void:
	for k in n:
		var a := TAU * k / n + phase
		var lit := ContentHash.unit(ContentHash.hash4(seed, k, int(y * 10.0))) < 0.3
		if kit.lod < 2 or lit:
			_shaft_window(kit, r, a, y, w, h, lit)


## Balcony ring around a shaft (radius r) at height y: slab, brackets, railing posts.
static func _balcony(kit: BuildingKit, r: float, y: float, out: float = 1.3) -> void:
	kit.cylinder(Vector3(0, y - 0.3, 0), 0.3, r + out, SatStyle.masonry(0), 20, true)
	if kit.lod >= 2:
		return
	kit.cylinder(Vector3(0, y - 0.36, 0), 0.08, r + out + 0.05, SatStyle.orange(), 20, false)
	var n := 16 if kit.lod == 0 else 8
	if kit.lod == 0:
		for k in 10:
			var a := TAU * k / 10.0
			var d := Vector3(cos(a), 0, sin(a))
			kit.beam(d * r + Vector3(0, y - 1.3, 0), d * (r + out - 0.2) + Vector3(0, y - 0.35, 0), 0.22, 0.22, SatStyle.masonry(1))
	var ring := PackedVector3Array()
	for k in n + 1:
		var a := TAU * k / n
		ring.append(Vector3(cos(a) * (r + out - 0.15), y, sin(a) * (r + out - 0.15)))
	if kit.lod == 0:
		kit.railing(ring, 0.95, {"role": SatStyle.orange(), "post_role": SatStyle.wall(0), "spacing": 1.1, "rails": 1})
	else:
		for k in n:
			kit.beam(ring[k] + Vector3(0, 0.5, 0), ring[k + 1] + Vector3(0, 0.5, 0), 0.12, 1.0, SatStyle.wall(0))


## Eave drum + cone roof (+ cupola) on a shaft of radius r whose top is at y. Returns the apex y.
static func _crown(kit: BuildingKit, r: float, y: float, roof_r: float, roof_h: float, v: int, cupola: bool) -> float:
	kit.cylinder(Vector3(0, y, 0), 1.1, r + 0.25, SatStyle.wall(v + 1), 20, true)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, y + 0.85, 0), 0.25, r + 0.4, SatStyle.saffron(), 20, false)
		kit.cylinder(Vector3(0, y - 0.15, 0), 0.3, r + 0.32, SatStyle.orange(), 20, false)
	var cy := y + 1.1
	if not cupola:
		KitRoofs.cone(kit, Vector3(0, cy, 0), roof_r, roof_h, SatStyle.cone_opts(v))
		return cy + roof_h
	# lower cone, a cupola drum emerging from it and a smaller upper cone
	KitRoofs.cone(kit, Vector3(0, cy, 0), roof_r, roof_h, SatStyle.cone_opts(v).merged({"finial": false}, true))
	var s := 0.4
	var rc := roof_r * pow(1.0 - s, 1.6) * 0.9
	var dy := cy + roof_h * s - 0.4
	var dh := maxf(rc * 1.2, 1.8)
	kit.cylinder(Vector3(0, dy, 0), dh, rc, SatStyle.wall(v), 14, true)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, dy + dh - 0.2, 0), 0.25, rc + 0.12, SatStyle.orange(), 14, false)
		for k in 4:
			_shaft_window(kit, rc, TAU * k / 4.0 + PI * 0.25, dy + dh * 0.45, rc * 0.45, dh * 0.5, false)
	KitRoofs.cone(kit, Vector3(0, dy + dh, 0), rc * 1.45 + 0.4, roof_h * 0.6, SatStyle.cone_opts(v + 1, 16))
	return dy + dh + roof_h * 0.6


static func spire(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 4.0))
	var h := float(spec.get("h", 22.0))
	var base := float(spec.get("base", -1.5))
	var v := int(spec.get("v", 0))
	# wide, deeply flared cones: the eave reaches ~1.6 x the shaft so the spires read from afar
	var roof_r := float(spec.get("roof_r", r * 1.5 + 1.0))
	var roof_h := float(spec.get("roof_h", r * 2.7))
	var seed := ContentHash.hash4(int(r * 10.0), int(h), v, 7)
	# masonry foot: from `base` (cliff / lower terrace) up to the ground line
	if base < -0.2:
		kit.cylinder(Vector3(0, base - 1.0, 0), -base + 1.3, r + 0.7, SatStyle.masonry(v), 20, true, r + 0.5)
		if kit.lod < 2 and base < -6.0:
			# buttress ribs down the foot
			for k in 6:
				var a := TAU * k / 6.0 + 0.3
				var d := Vector3(cos(a), 0, sin(a))
				kit.box_t(Transform3D(Basis(Vector3.UP, -a), d * (r + 0.9) + Vector3(0, (base + 0.3) * 0.5, 0)), Vector3(0.9, -base, 0.9),
						SatStyle.masonry(v + 1), false)
			kit.cylinder(Vector3(0, -0.2, 0), 0.5, r + 1.0, SatStyle.orange(), 20, false)
	# shaft
	kit.cylinder(Vector3(0, 0.0, 0), h, r, SatStyle.wall(v), 20, true, r * 0.95)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, 0.0, 0), 0.6, r + 0.12, SatStyle.masonry(v), 20, false)
		kit.cylinder(Vector3(0, h * 0.5, 0), 0.22, r * 0.975 + 0.08, SatStyle.saffron(), 20, false)
	# windows: two or three rows, offset so the shaft never shows a grid
	var rows := 2 if h < 18.0 else 3
	for row in rows:
		var y := h * (0.28 + 0.26 * row)
		_window_ring(kit, r * (1.0 - 0.05 * y / h), y, 5 if r > 3.5 else 4, minf(r * 0.28, 1.0), minf(r * 0.5, 1.9), seed + row, row * 0.6)
	# balcony + banners
	if spec.get("balcony", h > 16.0):
		var by := h * 0.8
		_balcony(kit, r * 0.96, by)
		if kit.lod < 2 and spec.get("banners", true):
			for sx: float in [-1.0, 1.0]:
				KitX.banner(kit, Transform3D(Basis(), Vector3(sx * r * 0.42, by - 0.6, -r * 0.93 - 0.08)), 0.9, minf(h * 0.3, 5.0),
						SatStyle.orange(), SatStyle.saffron(), &"swirl")
	if spec.get("door", true) and kit.lod < 2:
		KitX.doorway(kit, Vector3(0, 0.0, -r + 0.05), minf(r * 0.45, 1.5), 2.5, SatStyle.orange(), SatStyle.saffron(), 0.0)
	var apex := _crown(kit, r * 0.95, h, roof_r, roof_h, v, spec.get("cupola", false))
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, apex, 0)))
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -r - 1.0)))


## Teal hip-roofed wing of the great spire's hall: from the shaft outward along local -Z.
static func _wing(kit: BuildingKit, length: float, w: float, h: float, v: int) -> void:
	var zc := -length * 0.5
	# the body reaches 1.3 m down into the stepped podium (no gap over the lower step)
	kit.box(Vector3(0, (h - 1.3) * 0.5, zc), Vector3(w, h + 1.3, length), SatStyle.wall(v))
	if kit.lod < 2:
		kit.box(Vector3(0, 0.4, zc), Vector3(w + 0.4, 0.8, length + 0.4), SatStyle.masonry(v), false)
		kit.box(Vector3(0, h - 0.4, zc), Vector3(w + 0.2, 0.5, length + 0.2), SatStyle.orange(), false)
		kit.box(Vector3(0, h - 0.05, zc), Vector3(w + 0.35, 0.18, length + 0.35), SatStyle.saffron(), false)
		# end facade: a tall arched window and an emblem
		kit.push(Transform3D(Basis(), Vector3(0, 0, -length)))
		KitX.doorway(kit, Vector3(0, 0, 0.0), 2.4, 4.4, SatStyle.orange(), SatStyle.saffron(), 0.0)
		KitX.emblem_air(kit, Vector3(0, h - 2.0, 0.0), 1.8, SatStyle.gold(), 0.08)
		kit.pop()
		for side: float in [-1.0, 1.0]:
			for k in 2:
				var z := lerpf(-length * 0.3, -length * 0.8, k)
				kit.push(Transform3D(Basis(Vector3.UP, -side * PI * 0.5), Vector3(side * w * 0.5, h * 0.5, z)))
				KitX.window(kit, Vector3.ZERO, 0.9, 1.8, SatStyle.orange(), 0.0, (k + v) % 3 == 0)
				kit.pop()
	KitRoofs.hip(kit, Vector3(0, h, zc - 0.5), w, length + 1.0, w * 0.42, {"role": SatStyle.roof(v), "alt_role": SatStyle.roof_stripe(v),
		"ridge_role": SatStyle.gold(), "under_role": &"roof_under", "curve": 0.7, "overhang": 1.1, "ornaments": true})


## The Sanctum's great spire. spec: r (shaft), h (shaft height), roof_h.
static func great_spire(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 9.0))
	var h := float(spec.get("h", 46.0))
	var roof_h := float(spec.get("roof_h", 30.0))
	# stepped octagonal podium
	for step in 2:
		var rr := r + 9.0 - step * 3.0
		var poly := PackedVector2Array()
		for i in 8:
			var a := TAU * (i + 0.5) / 8.0
			poly.append(Vector2(cos(a), sin(a)) * rr)
		kit.slab(poly, -2.0 + step * 0.0, 0.6 + step * 0.6, SatStyle.masonry(step), true, &"floor")
	# cross hall with four wings (ends face the four winds)
	for k in 4:
		kit.push(Transform3D(Basis(Vector3.UP, k * PI * 0.5), Vector3(0, 1.2, 0)))
		_wing(kit, r + 8.0, 11.0, 9.0, k)
		kit.pop()
	# corner shrines between the wings (low drums with small cones)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var c := Vector3(cos(a), 0, sin(a)) * (r + 4.2) + Vector3(0, 1.2, 0)
		kit.cylinder(c, 6.5, 2.2, SatStyle.wall(k + 1), 14, true)
		if kit.lod < 2:
			kit.cylinder(c + Vector3(0, 6.0, 0), 0.3, 2.35, SatStyle.orange(), 14, false)
		KitRoofs.cone(kit, c + Vector3(0, 6.5, 0), 3.1, 4.6, SatStyle.cone_opts(k + 2, 14, 0.5))
	# the shaft
	var y0 := 1.2
	kit.cylinder(Vector3(0, y0, 0), h, r, SatStyle.wall(0), 24, true, r * 0.92)
	if kit.lod < 2:
		for band: float in [11.0, h * 0.5, h * 0.74]:
			var rb := r * (1.0 - 0.08 * band / h) + 0.1
			kit.cylinder(Vector3(0, y0 + band, 0), 0.4, rb, SatStyle.orange(), 24, false)
			kit.cylinder(Vector3(0, y0 + band + 0.45, 0), 0.15, rb, SatStyle.saffron(), 24, false)
	var rows := maxi(int((h - 16.0) / 8.0), 3)
	for row in rows:
		var y := y0 + 14.0 + row * (h - 18.0) / rows
		_window_ring(kit, r * (1.0 - 0.08 * (y - y0) / h), y, 8, 1.1, 2.2, 991 + row, row * 0.4)
	_balcony(kit, r * (1.0 - 0.08 * 0.4), y0 + h * 0.4, 1.4)
	_balcony(kit, r * (1.0 - 0.08 * 0.62), y0 + h * 0.62, 1.6)
	_balcony(kit, r * (1.0 - 0.08 * 0.88), y0 + h * 0.88, 1.4)
	if kit.lod < 2:
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			kit.push(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a), 0, sin(a)) * (r * 0.95 + 0.06)))
			KitX.banner(kit, Transform3D(Basis(), Vector3(0, y0 + h * 0.62 - 0.6, -0.05)), 1.6, 10.0, SatStyle.orange(), SatStyle.saffron(), &"swirl")
			kit.pop()
	var apex := _crown(kit, r * 0.92, y0 + h, r * 1.9, roof_h, 0, true)
	kit.mark(&"top", Transform3D(Basis(), Vector3(0, apex, 0)))
