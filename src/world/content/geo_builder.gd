class_name GeoBuilder
extends RefCounted
## Thread-safe procedural mesh accumulator used by vegetation, props and the building kit.
##
## Only Packed arrays are touched, never the RenderingServer, so a GeoBuilder can be filled on a
## WorkerThreadPool task and turned into an ArrayMesh on the main thread:
##
##   var g := GeoBuilder.new()
##   g.color = Color(0.5, 0.4, 0.3)
##   g.box(Transform3D(Basis(), Vector3(0, 1, 0)), Vector3(2, 2, 2))
##   g.cylinder(Vector3.ZERO, Vector3(0, 3, 0), 0.3, 0.2, 8)
##   mesh_instance.mesh = g.to_mesh()                 # main thread
##
## Triangles are given counter-clockwise as seen from their front side (right-hand rule: the
## cross product points out of the surface); the builder emits Godot's clockwise front-face order.
## Vertex attributes: position, normal, color (albedo rgb + free alpha), UV (free: vegetation uses
## x = sway weight, y = leaf flag; the kit uses it for cloth coordinates).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
## Second UV channel (vegetation: x = cap weight, y = ember weight; free elsewhere).
var uv2s := PackedVector2Array()
var indices := PackedInt32Array()
## Transform applied to everything added (positions and normals).
var xform := Transform3D.IDENTITY
## Default vertex colour / UV for the next primitives.
var color := Color.WHITE
var uv := Vector2.ZERO
var uv2 := Vector2.ZERO


func clear() -> void:
	verts.clear()
	normals.clear()
	colors.clear()
	uvs.clear()
	uv2s.clear()
	indices.clear()


func vertex_count() -> int:
	return verts.size()


func triangle_count() -> int:
	return indices.size() / 3


func is_empty() -> bool:
	return indices.is_empty()


## Adds one vertex (local coordinates, transformed by `xform`). Returns its index.
func vertex(p: Vector3, n: Vector3, c: Color = color, t: Vector2 = uv) -> int:
	verts.append(xform * p)
	normals.append((xform.basis * n).normalized())
	colors.append(c)
	uvs.append(t)
	uv2s.append(uv2)
	return verts.size() - 1


## Adds a vertex already in builder space (no transform).
func raw_vertex(p: Vector3, n: Vector3, c: Color, t: Vector2) -> int:
	verts.append(p)
	normals.append(n)
	colors.append(c)
	uvs.append(t)
	uv2s.append(uv2)
	return verts.size() - 1


## Triangle from vertex indices, counter-clockwise seen from the front.
func tri(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(c)
	indices.append(b)


## Quad a-b-c-d counter-clockwise seen from the front.
func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


## Flat-shaded triangle from positions (normal from the winding).
func flat_tri(a: Vector3, b: Vector3, c: Vector3, col: Color = color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var i := vertex(a, n, col)
	vertex(b, n, col)
	vertex(c, n, col)
	tri(i, i + 1, i + 2)


## Flat-shaded quad from positions, counter-clockwise from the front.
func flat_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color = color) -> void:
	var n := (b - a).cross(c - a) + (c - a).cross(d - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var i := vertex(a, n, col)
	vertex(b, n, col)
	vertex(c, n, col)
	vertex(d, n, col)
	quad(i, i + 1, i + 2, i + 3)


## Axis-aligned box (in the local frame `t`) with flat faces. `skip` bitmask omits faces:
## 1 -X, 2 +X, 4 -Y (bottom), 8 +Y (top), 16 -Z, 32 +Z.
func box(t: Transform3D, size: Vector3, col: Color = color, skip: int = 0) -> void:
	var h := size * 0.5
	var p := [
		t * Vector3(-h.x, -h.y, -h.z), t * Vector3(h.x, -h.y, -h.z), t * Vector3(h.x, h.y, -h.z), t * Vector3(-h.x, h.y, -h.z),
		t * Vector3(-h.x, -h.y, h.z), t * Vector3(h.x, -h.y, h.z), t * Vector3(h.x, h.y, h.z), t * Vector3(-h.x, h.y, h.z),
	]
	if skip & 16 == 0:
		flat_quad(p[1], p[0], p[3], p[2], col)
	if skip & 32 == 0:
		flat_quad(p[4], p[5], p[6], p[7], col)
	if skip & 1 == 0:
		flat_quad(p[0], p[4], p[7], p[3], col)
	if skip & 2 == 0:
		flat_quad(p[5], p[1], p[2], p[6], col)
	if skip & 4 == 0:
		flat_quad(p[0], p[1], p[5], p[4], col)
	if skip & 8 == 0:
		flat_quad(p[3], p[7], p[6], p[2], col)


## Box between two corner points (axis aligned in the current xform).
func box_between(a: Vector3, b: Vector3, col: Color = color, skip: int = 0) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	box(Transform3D(Basis.IDENTITY, (lo + hi) * 0.5), hi - lo, col, skip)


## Orthonormal frame whose Y axis points from a to b.
static func frame_along(a: Vector3, b: Vector3) -> Basis:
	var y := (b - a)
	if y.length_squared() < 1e-12:
		return Basis.IDENTITY
	y = y.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Tapered tube from a (radius r0) to b (radius r1). smooth = shared normals around.
## caps: 1 = cap at a, 2 = cap at b. `twist` rotates the ring (radians).
func cylinder(a: Vector3, b: Vector3, r0: float, r1: float, sides: int = 8, col: Color = color,
		caps: int = 2, smooth: bool = true, col_b: Color = Color(-1, 0, 0), twist: float = 0.0, uv_a: Vector2 = uv, uv_b: Vector2 = uv) -> void:
	sides = maxi(sides, 3)
	var basis := frame_along(a, b)
	var cb := col if col_b.r < 0.0 else col_b
	var slope := (r0 - r1) / maxf(a.distance_to(b), 1e-4)
	if smooth:
		var base := verts.size()
		for k in sides + 1:
			var ang := TAU * float(k % sides) / float(sides) + twist
			var dir := basis.x * cos(ang) + basis.z * sin(ang)
			var n := (dir + basis.y * slope).normalized()
			vertex(a + dir * r0, n, col, uv_a)
			vertex(b + dir * r1, n, cb, uv_b)
		for k in sides:
			var i := base + k * 2
			# a_k, b_k, b_k+1, a_k+1 is counter-clockwise seen from outside
			quad(i, i + 1, i + 3, i + 2)
	else:
		for k in sides:
			var a0 := TAU * float(k) / float(sides) + twist
			var a1 := TAU * float(k + 1) / float(sides) + twist
			var d0 := basis.x * cos(a0) + basis.z * sin(a0)
			var d1 := basis.x * cos(a1) + basis.z * sin(a1)
			flat_quad(a + d0 * r0, b + d0 * r1, b + d1 * r1, a + d1 * r0, col)
	if caps & 1 and r0 > 0.0:
		_disc(a, -basis.y, basis, r0, sides, col, twist, uv_a)
	if caps & 2 and r1 > 0.0:
		_disc(b, basis.y, basis, r1, sides, cb, twist, uv_b)


func _disc(c: Vector3, n: Vector3, basis: Basis, r: float, sides: int, col: Color, twist: float, t: Vector2) -> void:
	var ci := vertex(c, n, col, t)
	var first := verts.size()
	for k in sides:
		var ang := TAU * float(k) / float(sides) + twist
		vertex(c + (basis.x * cos(ang) + basis.z * sin(ang)) * r, n, col, t)
	for k in sides:
		var i0 := first + k
		var i1 := first + (k + 1) % sides
		if n.dot(basis.y) > 0.0:
			tri(ci, i1, i0)
		else:
			tri(ci, i0, i1)


## Cone from a base disc (centre, radius) to an apex.
func cone(base: Vector3, apex: Vector3, r: float, sides: int = 8, col: Color = color, cap: bool = true,
		col_tip: Color = Color(-1, 0, 0), smooth: bool = true) -> void:
	cylinder(base, apex, r, 0.0, sides, col, 1 if cap else 0, smooth, col_tip)


## Tube along a polyline with per-point radii (branches, roots, ropes). Smooth normals.
func tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int = 6, col: Color = color,
		col_end: Color = Color(-1, 0, 0), uv_start: Vector2 = uv, uv_end: Vector2 = uv, cap_end: bool = false) -> void:
	var n := points.size()
	if n < 2:
		return
	var ce := col if col_end.r < 0.0 else col_end
	var base := verts.size()
	var prev_x := Vector3.ZERO
	for i in n:
		var dir: Vector3
		if i == 0:
			dir = points[1] - points[0]
		elif i == n - 1:
			dir = points[i] - points[i - 1]
		else:
			dir = points[i + 1] - points[i - 1]
		dir = dir.normalized()
		var x: Vector3
		if i == 0:
			x = frame_along(Vector3.ZERO, dir).x
		else:
			# parallel transport: keep the previous x, re-orthogonalise
			x = (prev_x - dir * prev_x.dot(dir))
			if x.length_squared() < 1e-8:
				x = frame_along(Vector3.ZERO, dir).x
			x = x.normalized()
		prev_x = x
		var z := x.cross(dir).normalized()
		var f := float(i) / float(n - 1)
		var c := col.lerp(ce, f)
		var t := uv_start.lerp(uv_end, f)
		for k in sides + 1:
			var ang := TAU * float(k % sides) / float(sides)
			var d := x * cos(ang) + z * sin(ang)
			vertex(points[i] + d * radii[i], d, c, t)
	var ring := sides + 1
	for i in n - 1:
		for k in sides:
			var a0 := base + i * ring + k
			var b0 := base + (i + 1) * ring + k
			quad(a0, b0, b0 + 1, a0 + 1)
	if cap_end and radii[n - 1] > 0.0:
		var tip := vertex(points[n - 1] + (points[n - 1] - points[n - 2]).normalized() * radii[n - 1] * 0.6,
				(points[n - 1] - points[n - 2]).normalized(), ce, uv_end)
		var last := base + (n - 1) * ring
		for k in sides:
			tri(last + k, tip, last + k + 1)


## Icosphere blob. `noise` displaces vertices radially (0..1 of radius) using `rng`.
## `scale` stretches it (e.g. flattened canopies). normal_center: when finite, normals point away
## from that point (soft "canopy" shading) mixed with the true normal by `normal_soft`.
func blob(center: Vector3, radius: float, subdiv: int, col: Color, rng: RandomNumberGenerator = null,
		noise: float = 0.0, scale: Vector3 = Vector3.ONE, normal_center: Vector3 = Vector3.INF, normal_soft: float = 0.0,
		col_bottom: Color = Color(-1, 0, 0), t: Vector2 = uv, flat: bool = false) -> void:
	var sphere := GeoBuilder.icosphere(subdiv)
	var pts: PackedVector3Array = sphere[0]
	var tris: PackedInt32Array = sphere[1]
	var disp := PackedVector3Array()
	disp.resize(pts.size())
	for i in pts.size():
		var d := pts[i]
		var r := radius * (1.0 + (rng.randf_range(-noise, noise) if rng and noise > 0.0 else 0.0))
		disp[i] = center + Vector3(d.x * scale.x, d.y * scale.y, d.z * scale.z) * r
	var cb := col if col_bottom.r < 0.0 else col_bottom
	if flat:
		for k in range(0, tris.size(), 3):
			var a := disp[tris[k]]
			var b := disp[tris[k + 1]]
			var c := disp[tris[k + 2]]
			var cy := ((pts[tris[k]].y + pts[tris[k + 1]].y + pts[tris[k + 2]].y) / 3.0) * 0.5 + 0.5
			flat_tri(a, b, c, cb.lerp(col, cy))
		return
	var base := verts.size()
	var nrm := GeoBuilder._smooth_normals(disp, tris)
	for i in disp.size():
		var n := nrm[i]
		if normal_center.is_finite() and normal_soft > 0.0:
			n = n.lerp((disp[i] - normal_center).normalized(), normal_soft).normalized()
		var cy := pts[i].y * 0.5 + 0.5
		vertex(disp[i], n, cb.lerp(col, cy), t)
	for k in range(0, tris.size(), 3):
		tri(base + tris[k], base + tris[k + 1], base + tris[k + 2])


static func _smooth_normals(p: PackedVector3Array, tris: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(p.size())
	for k in range(0, tris.size(), 3):
		var a := tris[k]
		var b := tris[k + 1]
		var c := tris[k + 2]
		var n := (p[b] - p[a]).cross(p[c] - p[a])
		out[a] += n
		out[b] += n
		out[c] += n
	for i in out.size():
		out[i] = out[i].normalized() if out[i].length_squared() > 0.0 else Vector3.UP
	return out


static var _ico_cache: Dictionary = {}
static var _ico_mutex := Mutex.new()


## Unit icosphere [PackedVector3Array points, PackedInt32Array tris (CCW outward)]. Cached.
static func icosphere(subdiv: int) -> Array:
	subdiv = clampi(subdiv, 0, 3)
	_ico_mutex.lock()
	if _ico_cache.has(subdiv):
		var cached: Array = _ico_cache[subdiv]
		_ico_mutex.unlock()
		return cached
	_ico_mutex.unlock()
	var t := (1.0 + sqrt(5.0)) / 2.0
	var pts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in pts.size():
		pts[i] = pts[i].normalized()
	var tris := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10,
		8, 6, 7, 9, 8, 1])
	for s in subdiv:
		var mid := {}
		var nt := PackedInt32Array()
		for k in range(0, tris.size(), 3):
			var v := [tris[k], tris[k + 1], tris[k + 2]]
			var m := []
			for e in 3:
				var a: int = v[e]
				var b: int = v[(e + 1) % 3]
				var key := mini(a, b) * 100000 + maxi(a, b)
				if not mid.has(key):
					pts.append(((pts[a] + pts[b]) * 0.5).normalized())
					mid[key] = pts.size() - 1
				m.append(mid[key])
			nt.append_array([v[0], m[0], m[2], v[1], m[1], m[0], v[2], m[2], m[1], m[0], m[1], m[2]])
		tris = nt
	var out := [pts, tris]
	_ico_mutex.lock()
	_ico_cache[subdiv] = out
	_ico_mutex.unlock()
	return out


## Extrudes a closed polygon (x/z points, CCW seen from above) from y0 to y1 with flat walls.
## caps: 1 bottom, 2 top.
func extrude(poly: PackedVector2Array, y0: float, y1: float, col: Color = color, caps: int = 2, col_top: Color = Color(-1, 0, 0)) -> void:
	var n := poly.size()
	if n < 3:
		return
	var ct := col if col_top.r < 0.0 else col_top
	var ccw := GeoBuilder.polygon_area(poly) > 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		if not ccw:
			var tmp := a
			a = b
			b = tmp
		# CCW from above (north = -Z up): a -> b along the outline, wall faces outward
		flat_quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), col)
	var tri_idx := Geometry2D.triangulate_polygon(poly)
	if tri_idx.is_empty():
		return
	if caps & 2:
		_cap(poly, tri_idx, y1, Vector3.UP, ct)
	if caps & 1:
		_cap(poly, tri_idx, y0, Vector3.DOWN, col)


func _cap(poly: PackedVector2Array, tri_idx: PackedInt32Array, y: float, n: Vector3, col: Color) -> void:
	for k in range(0, tri_idx.size(), 3):
		var a := Vector3(poly[tri_idx[k]].x, y, poly[tri_idx[k]].y)
		var b := Vector3(poly[tri_idx[k + 1]].x, y, poly[tri_idx[k + 1]].y)
		var c := Vector3(poly[tri_idx[k + 2]].x, y, poly[tri_idx[k + 2]].y)
		if (b - a).cross(c - a).dot(n) < 0.0:
			var tmp := b
			b = c
			c = tmp
		flat_tri(a, b, c, col)


## Signed area of an x/z polygon (positive = counter-clockwise in x right / y(z) down screen,
## i.e. counter-clockwise seen from above with north (-Z) at the top).
static func polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return -a * 0.5


## Two-sided strip (leaf blades, banners, frond strips): points along the spine, `side` vectors
## (half widths) per point. Front normal = cross(side, spine dir); back gets the flipped normal.
func strip(spine: PackedVector3Array, sides: PackedVector3Array, col_a: Color, col_b: Color, two_sided: bool = true,
		uv_a: Vector2 = uv, uv_b: Vector2 = uv, normal_override: Vector3 = Vector3.ZERO) -> void:
	var n := spine.size()
	if n < 2:
		return
	for pass_i in (2 if two_sided else 1):
		var flip := pass_i == 1
		var base := verts.size()
		for i in n:
			var dir := (spine[mini(i + 1, n - 1)] - spine[maxi(i - 1, 0)]).normalized()
			var nn := sides[i].cross(dir).normalized() if normal_override == Vector3.ZERO else normal_override
			if flip:
				nn = -nn
			var f := float(i) / float(n - 1)
			var c := col_a.lerp(col_b, f)
			var t := uv_a.lerp(uv_b, f)
			vertex(spine[i] - sides[i], nn, c, t)
			vertex(spine[i] + sides[i], nn, c, t)
		for i in n - 1:
			var a := base + i * 2
			if flip:
				quad(a, a + 2, a + 3, a + 1)
			else:
				quad(a, a + 1, a + 3, a + 2)


## Appends another builder's geometry transformed by t (and this builder's xform).
func append(other: GeoBuilder, t: Transform3D = Transform3D.IDENTITY) -> void:
	var full := xform * t
	var base := verts.size()
	var nb := full.basis.inverse().transposed()
	for i in other.verts.size():
		verts.append(full * other.verts[i])
		normals.append((nb * other.normals[i]).normalized())
		colors.append(other.colors[i])
		uvs.append(other.uvs[i])
		uv2s.append(other.uv2s[i] if i < other.uv2s.size() else Vector2.ZERO)
	for i in other.indices.size():
		indices.append(base + other.indices[i])


## Multiplies the colour of every vertex added since `from_vertex`.
func tint_from(from_vertex: int, c: Color) -> void:
	for i in range(from_vertex, colors.size()):
		colors[i] = Color(colors[i].r * c.r, colors[i].g * c.g, colors[i].b * c.b, colors[i].a)


## Sets UV of every vertex added since `from_vertex` from a function of the local height.
func set_uv_from(from_vertex: int, value: Vector2) -> void:
	for i in range(from_vertex, uvs.size()):
		uvs[i] = value


## Bounding box of everything added.
func aabb() -> AABB:
	if verts.is_empty():
		return AABB()
	var box := AABB(verts[0], Vector3.ZERO)
	for p in verts:
		box = box.expand(p)
	return box


## Mesh arrays (Mesh.ARRAY_MAX) for ArrayMesh.add_surface_from_arrays.
func arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_COLOR] = colors
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_TEX_UV2] = uv2s
	a[Mesh.ARRAY_INDEX] = indices
	return a


## Triangle soup (Godot winding) for ConcavePolygonShape3D.set_faces.
func faces() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(indices.size())
	for i in indices.size():
		out[i] = verts[indices[i]]
	return out


## Main thread only: builds an ArrayMesh (one surface, optional material).
func to_mesh(material: Material = null) -> ArrayMesh:
	var m := ArrayMesh.new()
	if indices.is_empty():
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	if material:
		m.surface_set_material(0, material)
	return m
