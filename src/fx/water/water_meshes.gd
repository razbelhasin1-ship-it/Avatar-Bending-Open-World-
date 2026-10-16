class_name WaterMeshes
extends RefCounted
## Procedural meshes for the Water techniques (cached): the travelling wave
## crest (Water Surge, Water Wave, Tidal Torrent crash), the ice prison
## (Ice Trap) and flat-shaded triangle helpers.
##
##   WaterMeshes.crest(deg_to_rad(80), 4.0, 1.8, 1.4)   # crescent wave, -Z forward
##   WaterMeshes.add_tri(tris, a, b, c, outward)         # oriented flat triangle

static var _cache: Dictionary = {}

## Wave cross-section, normalized (forward offset in units of `depth`, height
## fraction, foam weight): a long thin tail of water flowing along the ground
## behind the wave -> back slope -> crest -> curling lip -> hollow front face
## -> front foot (spray).
const PROFILE: Array[Vector3] = [
	Vector3(-2.4, 0.0, 0.45), Vector3(-1.8, 0.04, 0.2), Vector3(-1.25, 0.12, 0.06), Vector3(-0.8, 0.3, 0.02),
	Vector3(-0.45, 0.58, 0.04), Vector3(-0.15, 0.86, 0.4), Vector3(0.08, 1.0, 0.85), Vector3(0.28, 0.99, 0.9),
	Vector3(0.45, 0.88, 1.0), Vector3(0.53, 0.72, 0.85), Vector3(0.47, 0.58, 0.4), Vector3(0.32, 0.5, 0.12),
	Vector3(0.21, 0.36, 0.06), Vector3(0.18, 0.16, 0.25), Vector3(0.3, 0.0, 0.8),
]
## Alpha per profile point (the tail fades into the ground water).
const PROFILE_A: Array[float] = [0.0, 0.45, 0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.6]


## Appends triangle (a, b, c) so its front face (Godot: clockwise) faces `outward`.
static func add_tri(tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(outward) < 0.0:
		tris.append_array([a, c, b])
	else:
		tris.append_array([a, b, c])


## Flat-shaded mesh from oriented triangles; color_fn(center, normal) -> Color.
static func flat(tris: PackedVector3Array, color_fn: Callable = Callable()) -> ArrayMesh:
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
		var col: Color = color_fn.call((a + b + c) / 3.0, n) if color_fn.is_valid() else Color.WHITE
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


## Crescent wave crest centred on the local origin's arc: the crest line lies at
## `radius` along -Z (angles -span/2..span/2 around +Y), travelling outward
## (-Z at the centre). `height` m tall at the middle, `depth` m from back foot
## to crest, tapering at both ends. UV.x across (0..1), UV.y along the profile
## (0 back foot .. 1 front foot); COLOR.r = foam weight, COLOR.a = edge fade.
## span >= TAU makes a closed ring wave.
static func crest(span: float, radius: float, height: float, depth: float, segments: int = 0) -> ArrayMesh:
	var ring := span >= TAU - 0.01
	var key := "crest_%.2f_%.1f_%.1f_%.1f_%s" % [span, radius, height, depth, ring]
	if _cache.has(key):
		return _cache[key]
	var segs := segments if segments > 0 else clampi(int(span * radius * 2.0), 10, 64)
	var np := PROFILE.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var u := float(i) / segs
		var a := (u - 0.5) * span
		var fwd := Vector3(sin(a), 0.0, -cos(a))
		# Taper: full height in the middle, sinking to nothing at the tips.
		# Flat-topped crest with rounded ends (a rolling wall of water, not a dome).
		var env := 1.0 if ring else pow(sin(PI * clampf(u, 0.0, 1.0)), 0.3)
		var edge_a := 1.0 if ring else clampf(sin(PI * u) * 4.0, 0.0, 1.0)
		for k in np:
			var pr: Vector3 = PROFILE[k]
			var off := pr.x * depth * (0.65 + 0.35 * env)
			var p := fwd * maxf(radius + off, radius * 0.25) + Vector3.UP * pr.y * height * env
			verts.append(p)
			uvs.append(Vector2(u, float(k) / (np - 1)))
			cols.append(Color(pr.z, 0.0, 0.0, edge_a * PROFILE_A[k]))
			norms.append(Vector3.UP)
	# Smooth normals from the grid, consistently on the outer side of the sheet
	# (the shader is double sided and flips them for back faces).
	for i in segs + 1:
		for k in np:
			var pk0 := verts[i * np + maxi(k - 1, 0)]
			var pk1 := verts[i * np + mini(k + 1, np - 1)]
			var pi0 := verts[maxi(i - 1, 0) * np + k]
			var pi1 := verts[mini(i + 1, segs) * np + k]
			var tk := pk1 - pk0
			var ti := pi1 - pi0
			var n := ti.cross(tk)
			if n.length_squared() < 1e-10:
				n = Vector3.UP
			norms[i * np + k] = n.normalized()
	for i in segs:
		for k in np - 1:
			var a0 := i * np + k
			var a1 := (i + 1) * np + k
			var b0 := a0 + 1
			var b1 := a1 + 1
			idx.append_array([a0, b0, a1, a1, b0, b1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache[key] = m
	return m


## Ice prison around a character's legs: a ring of leaning crystals closing
## in toward the centre, `radius` wide and `height` tall (base at y = 0).
static func ice_prison(radius: float = 0.55, height: float = 1.15, variant: int = 0) -> ArrayMesh:
	var key := "prison_%.2f_%.2f_%d" % [radius, height, variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7300 + variant
	var tris := PackedVector3Array()
	var n := 9
	for i in n:
		var a := TAU * float(i) / n + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var r := radius * rng.randf_range(0.85, 1.15)
		var h := height * rng.randf_range(0.6, 1.1)
		var w := radius * rng.randf_range(0.42, 0.6)
		var base := dir * r
		# Crystal leans inward: apex over the target's thighs.
		var apex := dir * r * rng.randf_range(0.15, 0.45) + Vector3.UP * h
		var bq: Array[Vector3] = [base - side * w * 0.5 - dir * w * 0.3, base + side * w * 0.5 - dir * w * 0.3,
				base + side * w * 0.4 + dir * w * 0.35, base - side * w * 0.4 + dir * w * 0.35]
		# Waist ring at 55 % height, a little fatter than a straight taper (faceted crystal).
		var wq: Array[Vector3] = []
		for b in bq:
			wq.append(b.lerp(apex, 0.55) + (b - base) * 0.25)
		for e in 4:
			var f := (e + 1) % 4
			var out := (bq[e] + bq[f]) * 0.5 - base
			out.y = 0.0
			add_tri(tris, bq[e], bq[f], wq[f], out)
			add_tri(tris, bq[e], wq[f], wq[e], out)
			add_tri(tris, wq[e], wq[f], apex, out + Vector3.UP * 0.3)
	# A frozen slab at the feet ties the crystals together.
	var slab := FxMeshes.ice_block(Vector3(radius * 2.2, height * 0.35, radius * 1.8), variant)
	var m := flat(tris, func(_c: Vector3, _n: Vector3) -> Color: return Color.WHITE)
	var arrays := slab.surface_get_arrays(0)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = m
	return m
