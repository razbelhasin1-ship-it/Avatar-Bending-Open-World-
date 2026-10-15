class_name RigShapes
extends RefCounted
## Static helpers that emit common skinned shapes into a SkinMeshBuilder.


## UV sphere whose points come from `fn(theta, phi) -> Vector3` (theta azimuth,
## 0 = front/-Z, increasing toward +X; phi polar from top 0 to bottom PI).
## `col_fn(theta, phi, pos) -> Color`, `w_fn(theta, phi, pos) -> Dictionary`.
static func sphere_fn(b: SkinMeshBuilder, fn: Callable, col_fn: Callable, w_fn: Callable, rings: int, segs: int, phi_max: float = PI) -> void:
	b.begin_part()
	var rows: Array = []
	var top_pos: Vector3 = fn.call(0.0, 0.0)
	var top := b.add_vertex(top_pos, col_fn.call(0.0, 0.0, top_pos), w_fn.call(0.0, 0.0, top_pos))
	for r in range(1, rings + (1 if phi_max < PI - 0.001 else 0)):
		var phi := phi_max * float(r) / float(rings)
		var row := PackedInt32Array()
		row.resize(segs)
		for s in segs:
			var th := TAU * float(s) / float(segs)
			var pos: Vector3 = fn.call(th, phi)
			row[s] = b.add_vertex(pos, col_fn.call(th, phi, pos), w_fn.call(th, phi, pos))
		rows.append(row)
	# Rows run top -> bottom; ring order goes front -> right (+X): counter-clockwise
	# when looking back along the row direction, the same convention as RigLoft.
	b.add_grid(rows, true, PackedInt32Array(), false)
	b.add_cap(rows[0], top, true)
	if phi_max >= PI - 0.001:
		var bot_pos: Vector3 = fn.call(0.0, PI)
		var bot := b.add_vertex(bot_pos, col_fn.call(0.0, PI, bot_pos), w_fn.call(0.0, PI, bot_pos))
		b.add_cap(rows[rows.size() - 1], bot, false)
	b.end_part()


## Ellipsoid with semi-axes along `basis` columns (scaled), single bone weights.
static func ellipsoid(b: SkinMeshBuilder, center: Vector3, basis: Basis, col: Color, w: Dictionary, rings: int = 8, segs: int = 12) -> void:
	sphere_fn(b,
		func(th: float, ph: float) -> Vector3: return center + basis * Vector3(sin(ph) * sin(th), cos(ph), -sin(ph) * cos(th)),
		func(_th: float, _ph: float, _p: Vector3) -> Color: return col,
		func(_th: float, _ph: float, _p: Vector3) -> Dictionary: return w,
		rings, segs)


## Basis whose columns are the given axes scaled by radii (x, y, z).
static func axes(x: Vector3, y: Vector3, z: Vector3, r: Vector3) -> Basis:
	return Basis(x.normalized() * r.x, y.normalized() * r.y, z.normalized() * r.z)


## Flat polygon patch lying on a surface. `surf(u, v) -> [pos, normal]` maps 2D
## patch coordinates to the surface; `outline` is a closed 2D polygon (CCW when
## viewed from outside). The patch is built as concentric rings for curvature.
static func patch(b: SkinMeshBuilder, surf: Callable, outline: PackedVector2Array, lift: float, col: Color, w: Dictionary, rings: int = 3) -> void:
	b.begin_part()
	var c2 := Vector2.ZERO
	for q in outline:
		c2 += q
	c2 /= float(outline.size())
	var sp: Array = surf.call(c2.x, c2.y)
	var center := b.add_vertex((sp[0] as Vector3) + (sp[1] as Vector3) * lift, col, w)
	var prev := PackedInt32Array()
	for r in range(1, rings + 1):
		var f := float(r) / float(rings)
		var row := PackedInt32Array()
		for q in outline:
			var uv := c2.lerp(q, f)
			var s2: Array = surf.call(uv.x, uv.y)
			row.append(b.add_vertex((s2[0] as Vector3) + (s2[1] as Vector3) * lift, col, w))
		if r == 1:
			var n := row.size()
			for i in n:
				b.add_tri(center, row[i], row[(i + 1) % n])
		else:
			var n2 := row.size()
			for i in n2:
				var j := (i + 1) % n2
				b.add_quad(prev[i], row[i], row[j], prev[j])
		prev = row
	b.end_part()


## Band between two 2D polylines (same length) on a surface: `lower[i]` to
## `upper[i]`, with x increasing toward the viewer's right as seen from outside.
static func band2d(b: SkinMeshBuilder, surf: Callable, lower: PackedVector2Array, upper: PackedVector2Array, lift: float, col: Color, w: Dictionary) -> void:
	b.begin_part()
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	for i in lower.size():
		var s0: Array = surf.call(lower[i].x, lower[i].y)
		var s1: Array = surf.call(upper[i].x, upper[i].y)
		lo.append(b.add_vertex((s0[0] as Vector3) + (s0[1] as Vector3) * lift, col, w))
		hi.append(b.add_vertex((s1[0] as Vector3) + (s1[1] as Vector3) * lift, col, w))
	var ascending := lower.size() < 2 or lower[lower.size() - 1].x >= lower[0].x
	for i in lower.size() - 1:
		if ascending:
			b.add_quad(lo[i], lo[i + 1], hi[i + 1], hi[i])
		else:
			b.add_quad(lo[i + 1], lo[i], hi[i], hi[i + 1])
	b.end_part()


## Ellipse polygon (CCW) for patches.
static func ellipse2(center: Vector2, rx: float, ry: float, n: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## Thick ribbon following 3D points (a flat bar with 4 sides), useful for
## straps, bands and props. `up` gives the ribbon's face direction per point.
static func bar(b: SkinMeshBuilder, pts: PackedVector3Array, ups: PackedVector3Array, width: float, thick: float, col: Color, weights: Array) -> void:
	b.begin_part()
	var rows: Array = []
	var n := pts.size()
	for i in n:
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var up := ups[i] - tg * ups[i].dot(tg)
		up = up.normalized()
		var side := tg.cross(up).normalized()
		var w: Dictionary = weights[i]
		var row := PackedInt32Array()
		for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var c: Vector2 = corner
			row.append(b.add_vertex(pts[i] + side * c.x * width * 0.5 + up * c.y * thick * 0.5, col, w))
		rows.append(row)
	b.add_grid(rows, true, PackedInt32Array(), true)
	b.add_quad(rows[0][0], rows[0][1], rows[0][2], rows[0][3])
	var last: PackedInt32Array = rows[n - 1]
	b.add_quad(last[3], last[2], last[1], last[0])
	b.end_part()
