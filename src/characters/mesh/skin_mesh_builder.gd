class_name SkinMeshBuilder
extends RefCounted
## Accumulates skinned geometry for one surface: positions (model/rest space),
## vertex colors and up to 4 bone influences per vertex, then commits it to an
## ArrayMesh surface. Normals are computed per "part" from the triangles so
## each part shades smoothly while separate parts keep crisp edges.
##
## Winding: quads/tris are given counter-clockwise as seen from outside; the
## builder emits them in Godot's front-face order.

var verts := PackedVector3Array()
var colors := PackedColorArray()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var indices := PackedInt32Array()
var normals := PackedVector3Array()

var _part_vstart := 0
var _part_istart := 0


## Weight helpers: weights are Dictionaries {bone_index: weight}.
static func w1(bone: int) -> Dictionary:
	return {bone: 1.0}


static func w2(a: int, b: int, t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0001:
		return {a: 1.0}
	if t >= 0.9999:
		return {b: 1.0}
	if a == b:
		return {a: 1.0}
	return {a: 1.0 - t, b: t}


## Linear mix of two weight dictionaries.
static func wmix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0001:
		return a
	if t >= 0.9999:
		return b
	var out := {}
	for k: int in a:
		out[k] = float(a[k]) * (1.0 - t)
	for k: int in b:
		out[k] = float(out.get(k, 0.0)) + float(b[k]) * t
	return out


func vertex_count() -> int:
	return verts.size()


func begin_part() -> void:
	_part_vstart = verts.size()
	_part_istart = indices.size()


## Adds a vertex; `w` is {bone: weight} (normalized to the 4 strongest).
func add_vertex(pos: Vector3, color: Color, w: Dictionary) -> int:
	verts.append(pos)
	# Shader multiplies COLOR as linear; authoring colors are sRGB.
	colors.append(color.srgb_to_linear())
	normals.append(Vector3.UP)
	var ks: Array = w.keys()
	if ks.size() > 4:
		ks.sort_custom(func(x: int, y: int) -> bool: return float(w[x]) > float(w[y]))
		ks.resize(4)
	var total := 0.0
	for k: int in ks:
		total += maxf(float(w[k]), 0.0)
	if total <= 0.000001:
		total = 1.0
	for i in 4:
		if i < ks.size():
			bones.append(int(ks[i]))
			weights.append(maxf(float(w[ks[i]]), 0.0) / total)
		else:
			bones.append(0)
			weights.append(0.0)
	return verts.size() - 1


## Triangle a, b, c counter-clockwise seen from outside.
func add_tri(a: int, b: int, c: int) -> void:
	# Godot treats clockwise as front-facing.
	indices.append(a)
	indices.append(c)
	indices.append(b)


## Quad a, b, c, d counter-clockwise seen from outside.
func add_quad(a: int, b: int, c: int, d: int) -> void:
	add_tri(a, b, c)
	add_tri(a, c, d)


## Connects ring rows (each a PackedInt32Array of equal length) into a grid.
## `closed` wraps around each ring. `skip` lists row gaps (i -> i+1) to leave open.
func add_grid(rows: Array, closed: bool, skip: PackedInt32Array = PackedInt32Array(), flip: bool = false) -> void:
	for r in rows.size() - 1:
		if skip.has(r):
			continue
		var r0: PackedInt32Array = rows[r]
		var r1: PackedInt32Array = rows[r + 1]
		var n := r0.size()
		var segs := n if closed else n - 1
		for i in segs:
			var j := (i + 1) % n
			if flip:
				add_quad(r0[i], r1[i], r1[j], r0[j])
			else:
				add_quad(r0[i], r0[j], r1[j], r1[i])


## Closes a ring with a fan to `center` (a vertex index). `facing_forward`
## flips orientation for the end cap vs the start cap.
func add_cap(ring: PackedInt32Array, center: int, flip: bool) -> void:
	var n := ring.size()
	for i in n:
		var j := (i + 1) % n
		if flip:
			add_tri(center, ring[j], ring[i])
		else:
			add_tri(center, ring[i], ring[j])


## Computes smooth normals for the current part from its triangles.
func end_part() -> void:
	var vn := verts.size()
	for i in range(_part_vstart, vn):
		normals[i] = Vector3.ZERO
	var i := _part_istart
	var ni := indices.size()
	while i < ni:
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		# Stored order is clockwise (front), so the outward normal is (c-a)x(b-a).
		var fn := (verts[c] - verts[a]).cross(verts[b] - verts[a])
		normals[a] += fn
		normals[b] += fn
		normals[c] += fn
		i += 3
	for k in range(_part_vstart, vn):
		var n := normals[k]
		normals[k] = n.normalized() if n.length_squared() > 1e-14 else Vector3.UP
	_part_vstart = vn
	_part_istart = indices.size()


## Overrides the normal of a vertex (call after end_part()).
func set_normal(i: int, n: Vector3) -> void:
	normals[i] = n.normalized()


func is_empty() -> bool:
	return indices.is_empty()


## Mesh arrays for ArrayMesh.add_surface_from_arrays().
func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = indices
	return arr


## Appends this builder's geometry as a surface of `mesh`.
func commit(mesh: ArrayMesh, material: Material = null) -> void:
	if is_empty():
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays())
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
