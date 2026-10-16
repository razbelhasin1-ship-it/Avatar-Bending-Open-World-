class_name RoofsLite
extends RefCounted
## Cheap East-Asian roofs for mass housing (thread-safe, kit's current frame). KitRoofs.hip is a
## showpiece (tile ribs, underside grid: several thousand triangles); a city of a thousand houses
## needs the same silhouette in a few dozen: a concave curved top grid (3 x 4 quads per face at
## LOD0), a darker eave course, one flat soffit, fascia strips, a ridge beam and (LOD0) small
## ridge horns. Same conventions as KitRoofs: `c` = footprint centre at eave height, w/d = WALL
## footprint (the eaves overhang by opts.overhang).
##
##   RoofsLite.hip(kit, Vector3(0, 3.2, 0), 8.0, 6.0, 2.4, {"role": &"roof", "curve": 0.4})
##   RoofsLite.gable(kit, Vector3(0, 3.2, 0), 8.0, 6.0, 2.2)
##   RoofsLite.pent(kit, Vector3(0, 2.6, -3.0), 6.0, 1.4, 0.6)   # lean-to awning along x, sloping to -Z
##
## opts: overhang, curve (upturned corners), concave, role, eave_role (lower course colour),
## ridge_role, under_role, horns (bool), ridge (ridge length factor for hips), collide (bool).


static func _profile(s: float, concave: float) -> float:
	return lerpf(s, pow(s, 1.9), concave)


static func hip(kit: BuildingKit, c: Vector3, w: float, d: float, h: float, opts: Dictionary = {}) -> void:
	var o := float(opts.get("overhang", 0.7))
	var W := w + o * 2.0
	var D := d + o * 2.0
	var swap := D > W
	if swap:
		var tmp := W
		W = D
		D = tmp
	kit.push(Transform3D(Basis(Vector3.UP, PI * 0.5) if swap else Basis.IDENTITY, c))
	var rx := maxf((W - D) * 0.5 * float(opts.get("ridge", 1.0)), 0.0)
	var faces := [
		[Vector3(-W * 0.5, 0, D * 0.5), Vector3(W * 0.5, 0, D * 0.5), Vector3(-rx, h, 0), Vector3(rx, h, 0)],
		[Vector3(W * 0.5, 0, -D * 0.5), Vector3(-W * 0.5, 0, -D * 0.5), Vector3(rx, h, 0), Vector3(-rx, h, 0)],
		[Vector3(W * 0.5, 0, D * 0.5), Vector3(W * 0.5, 0, -D * 0.5), Vector3(rx, h, 0), Vector3(rx, h, 0)],
		[Vector3(-W * 0.5, 0, -D * 0.5), Vector3(-W * 0.5, 0, D * 0.5), Vector3(-rx, h, 0), Vector3(-rx, h, 0)],
	]
	_faces(kit, faces, h, opts)
	_soffit(kit, W, D, opts)
	if kit.lod < 2:
		var rr: Variant = opts.get("ridge_role", &"ridge")
		var lift := float(opts.get("curve", 0.4))
		if rx > 0.05:
			kit.beam(Vector3(-rx - 0.15, h + 0.05, 0), Vector3(rx + 0.15, h + 0.05, 0), 0.26, 0.28, rr)
		# hip ridges (one straight beam each: the eye reads the curve from the tiles)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var corner := Vector3(sx * W * 0.5, lift + 0.05, sz * D * 0.5)
				var mid := Vector3(sx * (rx + (W * 0.5 - rx) * 0.45), h * _profile(0.55, float(opts.get("concave", 0.4))) + lift * 0.2 + 0.08,
						sz * D * 0.5 * 0.45)
				kit.beam(Vector3(sx * rx, h + 0.05, 0), mid, 0.18, 0.2, rr)
				kit.beam(mid, corner, 0.18, 0.2, rr)
		if kit.lod == 0 and opts.get("horns", true):
			for sx: float in [-1.0, 1.0]:
				kit.ornament(Vector3(sx * (rx + 0.1), h + 0.15, 0), &"horn", 0.6, rr, Vector3(sx, 0, 0))
	if opts.get("collide", true):
		var lift2 := float(opts.get("curve", 0.4)) * 0.4
		for f: Array in faces:
			kit.collide_quad((f[0] as Vector3) + Vector3(0, lift2, 0), (f[1] as Vector3) + Vector3(0, lift2, 0), f[3], f[2])
	kit.pop()


static func gable(kit: BuildingKit, c: Vector3, w: float, d: float, h: float, opts: Dictionary = {}) -> void:
	var o := float(opts.get("overhang", 0.6))
	var W := w + o * 2.0
	var D := d + o * 2.0
	var swap := D > W
	if swap:
		var tmp := W
		W = D
		D = tmp
	kit.push(Transform3D(Basis(Vector3.UP, PI * 0.5) if swap else Basis.IDENTITY, c))
	var faces := [
		[Vector3(-W * 0.5, 0, D * 0.5), Vector3(W * 0.5, 0, D * 0.5), Vector3(-W * 0.5, h, 0), Vector3(W * 0.5, h, 0)],
		[Vector3(W * 0.5, 0, -D * 0.5), Vector3(-W * 0.5, 0, -D * 0.5), Vector3(W * 0.5, h, 0), Vector3(-W * 0.5, h, 0)],
	]
	_faces(kit, faces, h, opts)
	_soffit(kit, W, D, opts)
	# gable ends (inset to the wall line)
	var gr: Variant = opts.get("gable_role", &"wall_alt")
	var gw := W * 0.5 - o
	var dd := D * 0.5 - o
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * gw
		var a := Vector3(x, 0, dd)
		var b := Vector3(x, 0, -dd)
		var top := Vector3(x, h * 0.9, 0)
		if sx > 0.0:
			kit.g().flat_tri(a, b, top, kit.col(gr))
		else:
			kit.g().flat_tri(b, a, top, kit.col(gr))
	if kit.lod < 2:
		var rr: Variant = opts.get("ridge_role", &"ridge")
		kit.beam(Vector3(-W * 0.5 - 0.1, h + 0.05, 0), Vector3(W * 0.5 + 0.1, h + 0.05, 0), 0.24, 0.26, rr)
		if kit.lod == 0 and opts.get("horns", true):
			for sx: float in [-1.0, 1.0]:
				kit.ornament(Vector3(sx * (W * 0.5 + 0.05), h + 0.12, 0), &"horn", 0.55, rr, Vector3(sx, 0, 0))
	if opts.get("collide", true):
		for f: Array in faces:
			kit.collide_quad(f[0], f[1], f[3], f[2])
	kit.pop()


## Lean-to roof (awning, porch, wall coping): spans `w` along x at local `c` (high edge), reaching
## `depth` towards -Z while dropping `drop`.
static func pent(kit: BuildingKit, c: Vector3, w: float, depth: float, drop: float, opts: Dictionary = {}) -> void:
	var role: Variant = opts.get("role", &"roof")
	var hw := w * 0.5
	var g := kit.g()
	var col := kit.col(role)
	var eave := kit.col(opts.get("eave_role", role)) * 0.85
	var n := 3 if kit.lod == 0 else 1
	var prev_y := 0.0
	for k in n:
		var s0 := float(k) / n
		var s1 := float(k + 1) / n
		var y0 := -drop * lerpf(s0, s0 * s0, 0.4)
		var y1 := -drop * lerpf(s1, s1 * s1, 0.4)
		var cc := col if k < n - 1 else eave
		var a := c + Vector3(-hw, y0, -depth * s0)
		var b := c + Vector3(hw, y0, -depth * s0)
		var bb := c + Vector3(hw, y1, -depth * s1)
		var aa := c + Vector3(-hw, y1, -depth * s1)
		g.flat_quad(a, b, bb, aa, cc)
		prev_y = y1
	# soffit
	if kit.lod < 2:
		kit.g().flat_quad(c + Vector3(-hw, -0.12, 0), c + Vector3(-hw, prev_y - 0.12, -depth), c + Vector3(hw, prev_y - 0.12, -depth), c + Vector3(hw, -0.12, 0),
				kit.col(opts.get("under_role", &"roof_under")))
		kit.box(c + Vector3(0, prev_y - 0.06, -depth), Vector3(w, 0.14, 0.1), opts.get("fascia_role", &"trim"), false)


## The curved top grids of a set of faces ([eave start, eave end, ridge start, ridge end]).
static func _faces(kit: BuildingKit, faces: Array, h: float, opts: Dictionary) -> void:
	var ns: int = [3, 2, 1][clampi(kit.lod, 0, 2)]
	var nt: int = [4, 2, 1][clampi(kit.lod, 0, 2)]
	var lift := float(opts.get("curve", 0.4))
	var concave := float(opts.get("concave", 0.4))
	var g := kit.g()
	var c_top := kit.col(opts.get("role", &"roof"))
	var c_eave := kit.col(opts.get("eave_role", opts.get("role", &"roof")), false) * 0.82
	var c_fascia := kit.col(opts.get("fascia_role", &"trim"))
	for f: Array in faces:
		var e0: Vector3 = f[0]
		var e1: Vector3 = f[1]
		var r0: Vector3 = f[2]
		var r1: Vector3 = f[3]
		var pts: Array = []
		for j in ns + 1:
			var s := float(j) / ns
			var row: Array = []
			for i in nt + 1:
				var t := float(i) / nt
				var p := e0.lerp(e1, t).lerp(r0.lerp(r1, t), s)
				p.y = h * _profile(s, concave) + lift * pow(absf(t - 0.5) * 2.0, 3.0) * pow(1.0 - s, 2.0)
				row.append(p)
			pts.append(row)
		var base := g.vertex_count()
		for j in ns + 1:
			for i in nt + 1:
				var p: Vector3 = pts[j][i]
				var pu: Vector3 = pts[mini(j + 1, ns)][i] - pts[maxi(j - 1, 0)][i]
				var pv: Vector3 = pts[j][mini(i + 1, nt)] - pts[j][maxi(i - 1, 0)]
				var nrm := pv.cross(pu).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				g.vertex(p, nrm, c_eave if j == 0 else c_top)
		for j in ns:
			for i in nt:
				var k := base + j * (nt + 1) + i
				var a: Vector3 = pts[j][i]
				var b: Vector3 = pts[j][i + 1]
				var cc: Vector3 = pts[j + 1][i + 1]
				if (b - a).cross(cc - a).y >= 0.0:
					g.quad(k, k + 1, k + nt + 2, k + nt + 1)
				else:
					g.quad(k, k + nt + 1, k + nt + 2, k + 1)
		if kit.lod < 2:
			# fascia strip under the eave line (reads as the roof thickness)
			for i in nt:
				var a: Vector3 = pts[0][i]
				var b: Vector3 = pts[0][i + 1]
				var to_ridge: Vector3 = pts[1][i] - pts[0][i]
				var th := Vector3(0, 0.22, 0)
				if (b - a).cross(Vector3.UP).dot(to_ridge) < 0.0:
					g.flat_quad(a - th, b - th, b, a, c_fascia)
				else:
					g.flat_quad(b - th, a - th, a, b, c_fascia)


## One flat ceiling under the eaves (the dark underside seen from the street).
static func _soffit(kit: BuildingKit, W: float, D: float, opts: Dictionary) -> void:
	if kit.lod >= 2:
		return
	var y := -0.2
	kit.g().flat_quad(Vector3(-W * 0.5, y, -D * 0.5), Vector3(W * 0.5, y, -D * 0.5), Vector3(W * 0.5, y, D * 0.5), Vector3(-W * 0.5, y, D * 0.5),
			kit.col(opts.get("under_role", &"roof_under")))
