class_name KitRoofs
extends RefCounted
## Roof generators for BuildingKit (all in the kit's current frame, thread-safe):
##   hip()    East-Asian hip roof: concave slopes, upturned eave corners, tile ribs, ridge with
##            end horns, hip ridges, fascia — Earth Kingdom / Fire Nation halls, pagoda tiers.
##   gable()  two-slope roof with curved eaves and gable ends (houses, gatehouses, tents frames).
##   cone()   conical spire with a concave flare and finial (Air Nomad towers, Water Tribe spires).
##   dome()   ribbed dome (Water Tribe ice domes, observatories).
##   flat()   flat roof slab with parapet / crenels / icicles (Water Tribe ice blocks).
##   pagoda() stacked hip tiers with wall drums between them.
## `center` is the centre of the footprint at eave height; w/d are the WALL footprint sizes (the
## eaves overhang by opts.overhang). Roofs collide as trimesh (walkable by acrobatic benders).

## Concave East-Asian profile: flat at the eave, steep at the ridge.
static func _profile(s: float, concave: float) -> float:
	return lerpf(s, pow(s, 1.9), concave)


static func hip(kit: BuildingKit, center: Vector3, w: float, d: float, h: float, opts: Dictionary = {}) -> void:
	var o := float(opts.get("overhang", 0.9))
	var lift := float(opts.get("curve", 0.55))
	var concave := float(opts.get("concave", 0.45))
	var th := float(opts.get("thickness", 0.22))
	var role: Variant = opts.get("role", &"roof")
	var alt: Variant = opts.get("alt_role", &"roof_alt")
	var under: Variant = opts.get("under_role", &"roof_under")
	var W := w + o * 2.0
	var D := d + o * 2.0
	var swap := D > W
	if swap:
		var tmp := W
		W = D
		D = tmp
	kit.push(Transform3D(Basis(Vector3.UP, PI * 0.5) if swap else Basis.IDENTITY, center))
	var rx := maxf((W - D) * 0.5 * float(opts.get("ridge", 1.0)), 0.0)
	var ns: int = [6, 3, 1][clampi(kit.lod, 0, 2)]
	var nt: int = [10, 5, 1][clampi(kit.lod, 0, 2)]
	var faces := [
		# eave start, eave end, ridge start, ridge end (counter-clockwise from above outside)
		[Vector3(-W * 0.5, 0, D * 0.5), Vector3(W * 0.5, 0, D * 0.5), Vector3(-rx, h, 0), Vector3(rx, h, 0)],
		[Vector3(W * 0.5, 0, -D * 0.5), Vector3(-W * 0.5, 0, -D * 0.5), Vector3(rx, h, 0), Vector3(-rx, h, 0)],
		[Vector3(W * 0.5, 0, D * 0.5), Vector3(W * 0.5, 0, -D * 0.5), Vector3(rx, h, 0), Vector3(rx, h, 0)],
		[Vector3(-W * 0.5, 0, -D * 0.5), Vector3(-W * 0.5, 0, D * 0.5), Vector3(-rx, h, 0), Vector3(-rx, h, 0)],
	]
	for f: Array in faces:
		_face(kit, f[0], f[1], f[2], f[3], ns, nt, h, lift, concave, th, role, alt, under, kit.lod == 0)
	# ridge, hips, ornaments
	if kit.lod < 2:
		var rr: Variant = opts.get("ridge_role", &"ridge")
		var top := h + 0.08
		if rx > 0.05:
			kit.beam(Vector3(-rx - 0.1, top, 0), Vector3(rx + 0.1, top, 0), 0.32, 0.34, rr)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := Vector3(sx * W * 0.5, lift, sz * D * 0.5)
				var rp := Vector3(sx * rx, h, 0)
				_hip_ridge(kit, rp, corner, h, lift, concave, rr)
		if opts.get("ornaments", true) and kit.lod == 0:
			for sx in [-1.0, 1.0]:
				kit.ornament(Vector3(sx * (rx + 0.1), top + 0.12, 0), &"horn", 0.9, rr, Vector3(sx, 0, 0))
			if opts.get("finial", false):
				kit.ornament(Vector3(0, top + 0.1, 0), &"finial", 1.2, &"metal")
	# walkable collision: coarse planes
	for f: Array in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var c: Vector3 = f[3]
		var dd: Vector3 = f[2]
		kit.collide_quad(a + Vector3(0, lift * 0.5, 0), b + Vector3(0, lift * 0.5, 0), c, dd)
	kit.pop()


## One roof face as a curved grid: e0->e1 eave edge, r0->r1 ridge edge (r0 == r1 for hip ends).
static func _face(kit: BuildingKit, e0: Vector3, e1: Vector3, r0: Vector3, r1: Vector3, ns: int, nt: int, h: float,
		lift: float, concave: float, th: float, role: Variant, alt: Variant, under: Variant, ribs: bool) -> void:
	var gb := kit.g()
	var c_top := kit.col(role)
	var c_alt := kit.col(alt)
	var c_under := kit.col(under)
	var c_edge := kit.col(&"trim")
	var pts: Array = []        # [j][i] Vector3 top surface
	for j in ns + 1:
		var s := float(j) / ns
		var row: Array = []
		for i in nt + 1:
			var t := float(i) / nt
			var e := e0.lerp(e1, t)
			var r := r0.lerp(r1, t)
			var p := e.lerp(r, s)
			p.y = h * _profile(s, concave)
			# upturned corners: lift grows towards the eave ends, fades up the slope
			var corner := pow(absf(t - 0.5) * 2.0, 3.0)
			p.y += lift * corner * pow(1.0 - s, 2.0)
			# slight outward kick of the eave line at the corners
			row.append(p)
		pts.append(row)
	var base := gb.vertex_count()
	# top surface (smooth normals from the grid), tile colour stripes along t
	for j in ns + 1:
		for i in nt + 1:
			var p: Vector3 = pts[j][i]
			var pu: Vector3 = pts[mini(j + 1, ns)][i] - pts[maxi(j - 1, 0)][i]
			var pv: Vector3 = pts[j][mini(i + 1, nt)] - pts[j][maxi(i - 1, 0)]
			var n := pv.cross(pu).normalized()
			if n.y < 0.0:
				n = -n
			var c := c_top.lerp(c_alt, 0.35 if (i % 2 == 1 and nt > 2) else 0.0)
			gb.vertex(p, n, c)
	for j in ns:
		for i in nt:
			var k := base + j * (nt + 1) + i
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			if (b - a).cross(c - a).y >= 0.0:
				gb.quad(k, k + 1, k + nt + 2, k + nt + 1)
			else:
				gb.quad(k, k + nt + 1, k + nt + 2, k + 1)
	# underside (rafters colour), offset down
	var ub := gb.vertex_count()
	for j in ns + 1:
		for i in nt + 1:
			var p: Vector3 = pts[j][i]
			gb.vertex(p - Vector3(0, th, 0), Vector3.DOWN, c_under)
	for j in ns:
		for i in nt:
			var k := ub + j * (nt + 1) + i
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			if (b - a).cross(c - a).y >= 0.0:
				gb.quad(k, k + nt + 1, k + nt + 2, k + 1)
			else:
				gb.quad(k, k + 1, k + nt + 2, k + nt + 1)
	# fascia along the eave
	for i in nt:
		var a: Vector3 = pts[0][i]
		var b: Vector3 = pts[0][i + 1]
		var to_ridge: Vector3 = pts[1][i] - pts[0][i]
		if (b - a).cross(Vector3.UP).dot(to_ridge) < 0.0:
			gb.flat_quad(a - Vector3(0, th, 0), b - Vector3(0, th, 0), b, a, c_edge)
		else:
			gb.flat_quad(b - Vector3(0, th, 0), a - Vector3(0, th, 0), a, b, c_edge)
	# tile ribs (rounded tile rows) down the slope
	if ribs and nt > 2:
		var nr := int(e0.distance_to(e1) / 0.45)
		for r in nr:
			var t := (float(r) + 0.5) / nr
			var line := PackedVector3Array()
			for j in ns + 1:
				var s := float(j) / ns
				var e := e0.lerp(e1, t)
				var rr := r0.lerp(r1, t)
				var p := e.lerp(rr, s)
				p.y = h * _profile(s, concave) + lift * pow(absf(t - 0.5) * 2.0, 3.0) * pow(1.0 - s, 2.0) + 0.05
				line.append(p)
			if line[0].distance_to(line[ns]) < 0.3:
				continue
			var radii := PackedFloat32Array()
			radii.resize(line.size())
			radii.fill(0.075)
			gb.tube(line, radii, 3, c_top.lerp(c_alt, 0.6))


static func _hip_ridge(kit: BuildingKit, rp: Vector3, corner: Vector3, h: float, lift: float, concave: float, rr: Variant) -> void:
	var n := 4 if kit.lod == 0 else 2
	var prev := rp + Vector3(0, 0.1, 0)
	for k in range(1, n + 1):
		var s := 1.0 - float(k) / n
		var p := corner.lerp(rp, s)
		p.y = h * _profile(s, concave) + lift * pow(1.0 - s, 2.0) + 0.1
		kit.beam(prev, p, 0.22, 0.24, rr)
		prev = p
	if kit.lod == 0:
		kit.ornament(prev, &"horn", 0.55, rr, Vector3(corner.x, 0, corner.z).normalized())


## Gable roof: ridge along the longer side; gable ends filled with `gable_role`.
static func gable(kit: BuildingKit, center: Vector3, w: float, d: float, h: float, opts: Dictionary = {}) -> void:
	var o := float(opts.get("overhang", 0.7))
	var lift := float(opts.get("curve", 0.35))
	var concave := float(opts.get("concave", 0.35))
	var th := float(opts.get("thickness", 0.2))
	var W := w + o * 2.0
	var D := d + o * 2.0
	var swap := D > W
	if swap:
		var tmp := W
		W = D
		D = tmp
	kit.push(Transform3D(Basis(Vector3.UP, PI * 0.5) if swap else Basis.IDENTITY, center))
	var ns: int = [5, 3, 1][clampi(kit.lod, 0, 2)]
	var nt: int = [8, 4, 1][clampi(kit.lod, 0, 2)]
	var role: Variant = opts.get("role", &"roof")
	var alt: Variant = opts.get("alt_role", &"roof_alt")
	var under: Variant = opts.get("under_role", &"roof_under")
	_face(kit, Vector3(-W * 0.5, 0, D * 0.5), Vector3(W * 0.5, 0, D * 0.5), Vector3(-W * 0.5, h, 0), Vector3(W * 0.5, h, 0), ns, nt, h, lift, concave, th, role, alt, under, kit.lod == 0)
	_face(kit, Vector3(W * 0.5, 0, -D * 0.5), Vector3(-W * 0.5, 0, -D * 0.5), Vector3(W * 0.5, h, 0), Vector3(-W * 0.5, h, 0), ns, nt, h, lift, concave, th, role, alt, under, kit.lod == 0)
	# gable triangles (inset to the wall line)
	var gr: Variant = opts.get("gable_role", &"wall_alt")
	var gw := (W - o * 2.0) * 0.5
	var dd := D * 0.5 - o
	for sx in [-1.0, 1.0]:
		var x: float = sx * gw
		var a := Vector3(x, 0, dd)
		var b := Vector3(x, 0, -dd)
		var c := Vector3(x, h * 0.92, 0)
		if sx > 0.0:
			kit.g().flat_tri(a, b, c, kit.col(gr))
		else:
			kit.g().flat_tri(b, a, c, kit.col(gr))
	if kit.lod < 2:
		kit.beam(Vector3(-W * 0.5 - 0.1, h + 0.08, 0), Vector3(W * 0.5 + 0.1, h + 0.08, 0), 0.28, 0.3, opts.get("ridge_role", &"ridge"))
		if kit.lod == 0 and opts.get("ornaments", true):
			for sx in [-1.0, 1.0]:
				kit.ornament(Vector3(sx * (W * 0.5 + 0.05), h + 0.18, 0), &"horn", 0.7, opts.get("ridge_role", &"ridge"), Vector3(sx, 0, 0))
	kit.collide_quad(Vector3(-W * 0.5, lift * 0.3, D * 0.5), Vector3(W * 0.5, lift * 0.3, D * 0.5), Vector3(W * 0.5, h, 0), Vector3(-W * 0.5, h, 0))
	kit.collide_quad(Vector3(W * 0.5, lift * 0.3, -D * 0.5), Vector3(-W * 0.5, lift * 0.3, -D * 0.5), Vector3(-W * 0.5, h, 0), Vector3(W * 0.5, h, 0))
	kit.pop()


## Conical spire: eave radius r (incl. overhang), height h, concave flare. opts: role, alt_role
## (alternating segment stripes), trim_role (eave ring), finial (bool), sides, flare.
static func cone(kit: BuildingKit, center: Vector3, r: float, h: float, opts: Dictionary = {}) -> void:
	var sides: int = int(opts.get("sides", 16))
	sides = maxi(sides - [0, 6, 10][clampi(kit.lod, 0, 2)], 6)
	var rings: int = [7, 4, 2][clampi(kit.lod, 0, 2)]
	var flare := float(opts.get("flare", 0.35))
	var role: Variant = opts.get("role", &"roof")
	var alt: Variant = opts.get("alt_role", role)
	var slot: StringName = opts.get("slot", &"solid")
	var gb := kit.g(slot)
	var c0 := kit.col(role)
	var c1 := kit.col(alt)
	var base := gb.vertex_count()
	var prof: Array = []
	for j in rings + 1:
		var s := float(j) / rings
		var rr := r * pow(1.0 - s, 1.0 + flare) if j < rings else 0.0
		prof.append(Vector2(rr, h * s))
	for j in rings + 1:
		var p: Vector2 = prof[j]
		var dp: Vector2 = prof[mini(j + 1, rings)] - prof[maxi(j - 1, 0)]
		for i in sides + 1:
			var a := TAU * float(i % sides) / sides
			var dir := Vector3(cos(a), 0, sin(a))
			var n := (dir * dp.y - Vector3.UP * dp.x * 1.0).normalized() if dp.length_squared() > 0.0 else Vector3.UP
			if n.y < 0.0:
				n = Vector3(n.x, -n.y, n.z)
			var c := c0 if (i % 2 == 0 or alt == role) else c1
			gb.vertex(center + dir * p.x + Vector3(0, p.y, 0), n, c)
	for j in rings:
		for i in sides:
			var k := base + j * (sides + 1) + i
			gb.quad(k, k + sides + 1, k + sides + 2, k + 1)
	# underside disc + eave trim ring
	gb.vertex(center + Vector3(0, -0.05, 0), Vector3.DOWN, kit.col(&"roof_under"))
	var hub := gb.vertex_count() - 1
	var ring0 := gb.vertex_count()
	for i in sides:
		var a := TAU * float(i) / sides
		gb.vertex(center + Vector3(cos(a) * r, 0, sin(a) * r), Vector3.DOWN, kit.col(&"roof_under"))
	for i in sides:
		gb.tri(hub, ring0 + i, ring0 + (i + 1) % sides)
	if kit.lod < 2:
		kit.g().cylinder(center - Vector3(0, 0.22, 0), center + Vector3(0, 0.02, 0), r + 0.04, r + 0.04, sides, kit.col(opts.get("trim_role", &"trim")), 0)
	if opts.get("finial", true):
		kit.ornament(center + Vector3(0, h - 0.05, 0), &"finial", maxf(h * 0.18, 0.6), opts.get("finial_role", &"metal"))
	# collision: 8-sided pyramid
	var cn := 8
	for i in cn:
		var a0 := TAU * float(i) / cn
		var a1 := TAU * float(i + 1) / cn
		kit.collide_faces(PackedVector3Array([center + Vector3(cos(a0) * r, 0, sin(a0) * r), center + Vector3(0, h, 0), center + Vector3(cos(a1) * r, 0, sin(a1) * r)]))


## Ribbed dome (hemisphere scaled by `squash`). opts: role, rib_role, finial, block_lines (ice
## block joints baked as darker vertex colours), slot.
static func dome(kit: BuildingKit, center: Vector3, r: float, opts: Dictionary = {}) -> void:
	var squash := float(opts.get("squash", 0.85))
	var sides: int = [18, 12, 8][clampi(kit.lod, 0, 2)]
	var rings: int = [7, 4, 3][clampi(kit.lod, 0, 2)]
	var slot: StringName = opts.get("slot", &"solid")
	var gb := kit.g(slot)
	var c0 := kit.col(opts.get("role", &"roof"))
	var joints: bool = opts.get("block_lines", false) and kit.lod == 0
	var base := gb.vertex_count()
	for j in rings + 1:
		var phi := PI * 0.5 * float(j) / rings
		for i in sides + 1:
			var a := TAU * float(i % sides) / sides
			var n := Vector3(cos(a) * cos(phi), sin(phi), sin(a) * cos(phi))
			var c := c0
			if joints and (j % 2 == 0 or (i + j) % 3 == 0):
				c = c0 * 0.86
			gb.vertex(center + Vector3(n.x * r, n.y * r * squash, n.z * r), Vector3(n.x, n.y / maxf(squash, 0.2), n.z).normalized(), c)
	for j in rings:
		for i in sides:
			var k := base + j * (sides + 1) + i
			gb.quad(k, k + sides + 1, k + sides + 2, k + 1)
	if kit.lod < 2 and opts.get("ribs", true):
		var rr: Variant = opts.get("rib_role", &"trim")
		var nr := 8 if kit.lod == 0 else 4
		for i in nr:
			var a := TAU * float(i) / nr
			var line := PackedVector3Array()
			for j in 7:
				var phi := PI * 0.5 * float(j) / 6.0
				line.append(center + Vector3(cos(a) * cos(phi) * (r + 0.04), sin(phi) * (r + 0.04) * squash, sin(a) * cos(phi) * (r + 0.04)))
			var radii := PackedFloat32Array()
			radii.resize(line.size())
			radii.fill(0.07)
			kit.g(slot).tube(line, radii, 4, kit.col(rr))
	if opts.get("finial", true):
		kit.ornament(center + Vector3(0, r * squash - 0.05, 0), &"finial", r * 0.35, opts.get("finial_role", &"metal"))
	var cn := 8
	for i in cn:
		var a0 := TAU * float(i) / cn
		var a1 := TAU * float(i + 1) / cn
		kit.collide_faces(PackedVector3Array([center + Vector3(cos(a0) * r, 0, sin(a0) * r), center + Vector3(0, r * squash, 0), center + Vector3(cos(a1) * r, 0, sin(a1) * r)]))


## Flat roof slab over a w x d footprint with an optional parapet (crenellated) and icicles.
static func flat(kit: BuildingKit, center: Vector3, w: float, d: float, opts: Dictionary = {}) -> void:
	var th := float(opts.get("thickness", 0.35))
	var o := float(opts.get("overhang", 0.25))
	var role: Variant = opts.get("role", &"roof")
	var slot: StringName = opts.get("slot", &"solid")
	kit.g(slot).box(Transform3D(Basis(), center + Vector3(0, th * 0.5, 0)), Vector3(w + o * 2.0, th, d + o * 2.0), kit.col(role))
	kit.collide_box(center + Vector3(0, th * 0.5, 0), Vector3(w + o * 2.0, th, d + o * 2.0))
	var top := center + Vector3(0, th, 0)
	if opts.get("parapet", true) and kit.lod < 2:
		var ph := float(opts.get("parapet_height", 0.6))
		var pr: Variant = opts.get("parapet_role", role)
		var hw := w * 0.5 + o
		var hd := d * 0.5 + o
		var corners := PackedVector3Array([top + Vector3(-hw, 0, hd), top + Vector3(hw, 0, hd), top + Vector3(hw, 0, -hd), top + Vector3(-hw, 0, -hd)])
		var cren: Dictionary = {"width": 0.7, "gap": 0.5, "height": 0.5, "role": pr} if opts.get("crenels", true) else {}
		for i in 4:
			kit.wall(corners[i], corners[(i + 1) % 4], ph, 0.3, {"role": pr, "cap": false, "crenels": cren})
	if opts.get("icicles", false) and kit.lod == 0:
		var ice := kit.col(&"ice")
		var n := int((w + d) * 1.2)
		for i in n:
			var side := i % 4
			var t := kit.rng.randf()
			var p: Vector3
			match side:
				0: p = center + Vector3((t - 0.5) * w, 0, d * 0.5 + o)
				1: p = center + Vector3((t - 0.5) * w, 0, -d * 0.5 - o)
				2: p = center + Vector3(w * 0.5 + o, 0, (t - 0.5) * d)
				_: p = center + Vector3(-w * 0.5 - o, 0, (t - 0.5) * d)
			kit.g(&"ice").cone(p, p - Vector3(0, kit.rng.randf_range(0.25, 0.9), 0), 0.07, 4, ice, false)


## Pagoda: `tiers` stacked hip roofs with drums; returns the top height (relative to center.y).
static func pagoda(kit: BuildingKit, center: Vector3, w: float, d: float, tiers: int, opts: Dictionary = {}) -> float:
	var y := 0.0
	var drum_h := float(opts.get("drum_height", 2.2))
	var shrink := float(opts.get("shrink", 0.78))
	var roof_h := float(opts.get("roof_height", minf(w, d) * 0.32))
	var cw := w
	var cd := d
	for t in tiers:
		var last := t == tiers - 1
		hip(kit, center + Vector3(0, y, 0), cw, cd, roof_h * (1.25 if last else 0.85), {"overhang": float(opts.get("overhang", 1.1)) * (1.0 if t == 0 else 0.85),
			"curve": float(opts.get("curve", 0.7)), "role": opts.get("role", &"roof"), "alt_role": opts.get("alt_role", &"roof_alt"),
			"ridge_role": opts.get("ridge_role", &"ridge"), "ridge": 0.6 if last else 1.0, "finial": last, "ornaments": true})
		if last:
			return y + roof_h * 1.25
		# drum (walls of the next floor), slightly inset
		var nw := cw * shrink
		var nd := cd * shrink
		var base := center + Vector3(0, y + roof_h * 0.45, 0)
		kit.box(base + Vector3(0, drum_h * 0.5, 0), Vector3(nw, drum_h, nd), opts.get("drum_role", &"wall"))
		if kit.lod == 0:
			# drum posts
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					kit.box(base + Vector3(sx * nw * 0.5, drum_h * 0.5, sz * nd * 0.5), Vector3(0.3, drum_h, 0.3), opts.get("post_role", &"wood"), false)
			kit.railing(PackedVector3Array([base + Vector3(-nw * 0.5 - 0.5, 0.0, nd * 0.5 + 0.5), base + Vector3(nw * 0.5 + 0.5, 0.0, nd * 0.5 + 0.5)]), 0.7, {"role": opts.get("post_role", &"wood"), "collide": false})
		y += roof_h * 0.45 + drum_h
		cw = nw
		cd = nd
	return y
