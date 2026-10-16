class_name FxMeshes
extends RefCounted
## Procedural meshes for bending effects (cached): flat-shaded rocks, earth
## slabs, ice shards and blocks, and ribbon strips (helix gusts, rings, arcs)
## whose UVs drive the ribbon shaders (UV.x along, UV.y across).

static var _cache: Dictionary = {}


# --- rocks ---------------------------------------------------------------------------------

## Flat-shaded rock (~1 m across). `variant` picks one of a few cached shapes.
## Vertex colours carry light dust on top and darker undersides.
static func rock(variant: int = 0, detail: int = 1) -> ArrayMesh:
	var key := "rock_%d_%d" % [variant % 8, detail]
	if _cache.has(key):
		return _cache[key]
	var ico := _icosphere(clampi(detail, 0, 2))
	var fn := FastNoiseLite.new()
	fn.seed = 101 + variant * 37
	fn.frequency = 1.6
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + variant * 13
	var squash := Vector3(rng.randf_range(0.85, 1.15), rng.randf_range(0.65, 0.95), rng.randf_range(0.85, 1.2))
	var verts: PackedVector3Array = ico[0]
	for i in verts.size():
		var v := verts[i]
		var n := fn.get_noise_3dv(v * 1.3)
		# Chunky planar facets: quantize the displacement a little.
		var d := 1.0 + n * 0.32
		d = lerpf(d, roundf(d * 6.0) / 6.0, 0.4)
		verts[i] = v * d * squash * 0.5
	var mesh := _flat_mesh(verts, ico[1], func(p: Vector3, nrm: Vector3) -> Color:
		var top := clampf(nrm.y, 0.0, 1.0)
		var shade := 0.82 + 0.18 * fn.get_noise_3dv(p * 4.0)
		var c := Color(0.92, 0.88, 0.8).lerp(Color(1.05, 1.02, 0.95), top * 0.6) * shade
		if nrm.y < -0.3:
			c *= 0.78
		return c)
	_cache[key] = mesh
	return mesh


## Rough earth slab (wall) of `size` (x width, y height, z thickness), base at
## y = 0 and centred on x/z. Strata bands in the vertex colours, chipped top.
static func slab(size: Vector3, variant: int = 0) -> ArrayMesh:
	var key := "slab_%s_%d" % [str(size), variant]
	if _cache.has(key):
		return _cache[key]
	var fn := FastNoiseLite.new()
	fn.seed = 55 + variant
	fn.frequency = 0.7
	var sx := maxi(4, int(size.x * 1.6))
	var sy := maxi(3, int(size.y * 1.6))
	var sz := 2
	var tris := PackedVector3Array()
	# Six faces of a subdivided box, displaced.
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), sx, sy],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0), sx, sy],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), sz, sy],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), sz, sy],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), sx, sz],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), sx, sz],
	]
	var half := size * 0.5
	var disp := func(p: Vector3) -> Vector3:
		var q := Vector3(p.x * half.x, p.y * half.y + half.y, p.z * half.z)
		var n := fn.get_noise_3dv(q)
		var out := q
		out.x += n * 0.12 * signf(p.x) * absf(p.x)
		out.z += (n * 0.16 + 0.05 * sin(q.y * 3.1 + q.x)) * signf(p.z) * maxf(absf(p.z), 0.3)
		if p.y > 0.99:
			out.y += fn.get_noise_2d(q.x * 2.2, q.z * 2.0) * 0.28 - 0.08 - absf(p.x) * 0.22
		return out
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var nu: int = f[3]
		var nv: int = f[4]
		for i in nu:
			for j in nv:
				var a := nrm + u * (2.0 * i / nu - 1.0) + v * (2.0 * j / nv - 1.0)
				var b := nrm + u * (2.0 * (i + 1) / nu - 1.0) + v * (2.0 * j / nv - 1.0)
				var c := nrm + u * (2.0 * (i + 1) / nu - 1.0) + v * (2.0 * (j + 1) / nv - 1.0)
				var d := nrm + u * (2.0 * i / nu - 1.0) + v * (2.0 * (j + 1) / nv - 1.0)
				var pa: Vector3 = disp.call(a)
				var pb: Vector3 = disp.call(b)
				var pc: Vector3 = disp.call(c)
				var pd: Vector3 = disp.call(d)
				tris.append_array([pa, pc, pb, pa, pd, pc])
	var mesh := _flat_tris(tris, func(p: Vector3, n: Vector3) -> Color:
		var band := 0.5 + 0.5 * sin(p.y * 5.3 + fn.get_noise_2d(p.x * 3.0, p.z * 3.0) * 2.5)
		var c := Color(0.86, 0.8, 0.7).lerp(Color(1.0, 0.95, 0.85), band * 0.45)
		c *= lerpf(0.72, 1.0, clampf(p.y / maxf(size.y, 0.1) + 0.25, 0.0, 1.0))
		if n.y > 0.6:
			c = c.lerp(Color(1.06, 1.0, 0.9), 0.35)
		return c)
	_cache[key] = mesh
	return mesh


## Ice dagger along -Z (tip at -length*0.65, tail at +length*0.35).
static func shard(length: float = 0.7, radius: float = 0.08, variant: int = 0) -> ArrayMesh:
	var key := "shard_%.2f_%.2f_%d" % [length, radius, variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var sides := 6
	var tip := Vector3(0, 0, -length * 0.65)
	var tail := Vector3(0, 0, length * 0.35)
	var ring: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / sides + rng.randf_range(-0.15, 0.15)
		var r := radius * rng.randf_range(0.8, 1.2)
		ring.append(Vector3(cos(a) * r, sin(a) * r, length * 0.12 + rng.randf_range(-0.03, 0.03)))
	var tris := PackedVector3Array()
	for i in sides:
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		tris.append_array([tip, a, b, tail, b, a])
	var mesh := _flat_tris(tris, func(_p: Vector3, _n: Vector3) -> Color: return Color.WHITE)
	_cache[key] = mesh
	return mesh


## Faceted ice block (ice walls, frozen chunks), size like slab(): base at y = 0.
static func ice_block(size: Vector3, variant: int = 0) -> ArrayMesh:
	var key := "iceblock_%s_%d" % [str(size), variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant
	var tris := PackedVector3Array()
	# A row of leaning crystal prisms.
	var count := maxi(3, int(size.x / 0.8))
	for i in count:
		var cx := lerpf(-size.x * 0.5 + 0.4, size.x * 0.5 - 0.4, float(i) / maxf(count - 1, 1))
		var h := size.y * rng.randf_range(0.75, 1.1)
		var w := size.x / count * rng.randf_range(0.6, 0.85)
		var d := size.z * rng.randf_range(0.7, 1.0)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.1, 0.1))
		var b0 := Vector3(cx - w * 0.5, 0, -d * 0.5)
		var b1 := Vector3(cx + w * 0.5, 0, -d * 0.5)
		var b2 := Vector3(cx + w * 0.5, 0, d * 0.5)
		var b3 := Vector3(cx - w * 0.5, 0, d * 0.5)
		var t0 := b0 * Vector3(1, 0, 0.8) + Vector3(w * 0.12, h * 0.85, 0) + lean
		var t1 := b1 * Vector3(1, 0, 0.8) + Vector3(-w * 0.12, h * 0.85, 0) + lean
		var t2 := b2 * Vector3(1, 0, 0.8) + Vector3(-w * 0.12, h * 0.85, 0) + lean
		var t3 := b3 * Vector3(1, 0, 0.8) + Vector3(w * 0.12, h * 0.85, 0) + lean
		var apex := Vector3(cx, h, rng.randf_range(-0.1, 0.1)) + lean
		for q: Array in [[b0, b1, t1, t0], [b1, b2, t2, t1], [b2, b3, t3, t2], [b3, b0, t0, t3]]:
			tris.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
		for e: Array in [[t0, t1], [t1, t2], [t2, t3], [t3, t0]]:
			tris.append_array([e[0], e[1], apex])
	var mesh := _flat_tris(tris, func(_p: Vector3, _n: Vector3) -> Color: return Color.WHITE)
	_cache[key] = mesh
	return mesh


# --- ribbons -------------------------------------------------------------------------------

## Generic strip through `points` with per-point half-width vectors `sides`.
## UV.x = 0 at the first point .. 1 at the last, UV.y = 0 / 1 across.
static func strip(points: PackedVector3Array, sides: PackedVector3Array, alphas: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := points.size()
	for i in n:
		var u := float(i) / maxf(n - 1, 1)
		var a := alphas[i] if i < alphas.size() else 1.0
		verts.append(points[i] - sides[i])
		verts.append(points[i] + sides[i])
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		cols.append(Color(1, 1, 1, a))
		cols.append(Color(1, 1, 1, a))
		if i < n - 1:
			var k := i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Helical ribbons along -Z from z = 0 to z = -length (meters).
## `strands` ribbons, `turns` revolutions, radius growing from r0 to r1.
static func helix(strands: int = 3, turns: float = 1.2, r0: float = 0.18, r1: float = 0.5, width: float = 0.09, length: float = 1.0, segments: int = 28) -> ArrayMesh:
	var key := "helix_%d_%.2f_%.2f_%.2f_%.2f_%.1f" % [strands, turns, r0, r1, width, length]
	if _cache.has(key):
		return _cache[key]
	var all := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in strands:
		var ph := TAU * float(s) / strands
		var pts := PackedVector3Array()
		var sides := PackedVector3Array()
		for i in segments:
			var u := float(i) / (segments - 1)
			var a := ph + u * turns * TAU
			var r := lerpf(r0, r1, u)
			var p := Vector3(cos(a) * r, sin(a) * r, -u * length)
			pts.append(p)
			var radial := Vector3(cos(a), sin(a), 0.0)
			# Half radial, half along the axis: readable from behind and from the side.
			var w := width * lerpf(0.6, 1.4, u) * 0.5
			sides.append(radial * w * 0.75 + Vector3(0, 0, w * 0.75))
		st.append_from(strip(pts, sides), 0, Transform3D.IDENTITY)
	st.commit(all)
	_cache[key] = all
	return all


## Flat ring band in the XZ plane (radius 1, unit; scale the node). UV.x around, UV.y across.
static func ring(segments: int = 48, width: float = 0.12, height: float = 0.0) -> ArrayMesh:
	var key := "ring_%d_%.2f_%.2f" % [segments, width, height]
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector3Array()
	var sides := PackedVector3Array()
	for i in segments + 1:
		var a := TAU * float(i) / segments
		var radial := Vector3(cos(a), 0.0, sin(a))
		pts.append(radial)
		sides.append(radial * width * 0.5 + Vector3.UP * height * 0.5)
	var m := strip(pts, sides)
	_cache[key] = m
	return m


## Vertical wall-like arc (fire waves): base on y = 0 from angle a0 to a1 (rad,
## 0 = -Z, positive turning right) at radius 1, `height` tall. UV.x along, UV.y up.
static func arc_wall(a0: float, a1: float, height: float = 1.0, segments: int = 32, lean: float = 0.25) -> ArrayMesh:
	var key := "arcw_%.2f_%.2f_%.2f_%.2f" % [a0, a1, height, lean]
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in segments + 1:
		var u := float(i) / segments
		var a := lerpf(a0, a1, u)
		var dir := Vector3(sin(a), 0.0, -cos(a))
		verts.append(dir)
		verts.append(dir * (1.0 + lean) + Vector3.UP * height)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		if i < segments:
			var k := i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache[key] = m
	return m


## Flat crescent band (kick arcs) in the XZ plane from angle a0 to a1 at radius 1,
## band `width` (radial). UV.x along the arc, UV.y across (symmetric).
static func crescent(a0: float, a1: float, width: float = 0.35, segments: int = 28) -> ArrayMesh:
	var key := "cres_%.2f_%.2f_%.2f" % [a0, a1, width]
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector3Array()
	var sides := PackedVector3Array()
	var alphas := PackedFloat32Array()
	for i in segments + 1:
		var u := float(i) / segments
		var a := lerpf(a0, a1, u)
		var dir := Vector3(sin(a), 0.0, -cos(a))
		pts.append(dir)
		var w := width * sin(PI * clampf(u * 0.85 + 0.15, 0.0, 1.0))
		sides.append(dir * w * 0.5)
		alphas.append(1.0)
	var m := strip(pts, sides, alphas)
	_cache[key] = m
	return m


# --- builders ------------------------------------------------------------------------------

static func _icosphere(level: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for l in level:
		var mid := {}
		var nf: Array = []
		for f: Array in faces:
			var m: Array[int] = []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var k := "%d_%d" % [mini(a, b), maxi(a, b)]
				if not mid.has(k):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mid[k] = verts.size() - 1
				m.append(mid[k])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		faces = nf
	return [verts, faces]


static func _flat_mesh(verts: PackedVector3Array, faces: Array, color_fn: Callable) -> ArrayMesh:
	var tris := PackedVector3Array()
	for f: Array in faces:
		tris.append_array([verts[f[0]], verts[f[2]], verts[f[1]]])
	return _flat_tris(tris, color_fn)


## Triangles (clockwise front faces, Godot convention) -> flat-shaded mesh.
static func _flat_tris(tris: PackedVector3Array, color_fn: Callable) -> ArrayMesh:
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	normals.resize(tris.size())
	cols.resize(tris.size())
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (c - a).cross(b - a)
		n = n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
		var col: Color = color_fn.call((a + b + c) / 3.0, n)
		for k in 3:
			normals[i + k] = n
			cols[i + k] = col
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = tris
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
