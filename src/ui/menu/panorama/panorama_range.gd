class_name PanoramaRange
extends RefCounted
## One mountain range of the menu panorama: a heightfield strip between x0..x1 whose
## cross-section rises from the front edge to a ridge and falls behind it. The ridge line is
## ridged fractal noise plus art-directed peaks ({x, h, w} gaussians), tapered at both ends
## so ranges dip into the sea. `height_at()` lets landmarks sit exactly on the terrain.

var x0 := -1000.0
var x1 := 1000.0
## World z of the front edge (ranges extend toward -z by `depth`).
var z_front := -500.0
var depth := 400.0
var base_height := 60.0
var noise_height := 120.0
## Art-directed peaks: Array of {"x": float, "h": float, "w": float}.
var peaks: Array[Dictionary] = []
## Fraction of the depth where the ridge crest sits.
var crest := 0.45
var taper := 0.12
var res_x := 180
var res_z := 40
var seed_value := 1
## Amplitude of the 2D detail relief relative to the ridge height (rocky near ranges).
var roughness := 0.18

var _ridge := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init(cfg: Dictionary = {}) -> void:
	for k: String in cfg:
		if k == "peaks":
			for p: Dictionary in cfg[k]:
				peaks.append(p)
		else:
			set(k, cfg[k])
	_ridge.seed = seed_value
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_ridge.frequency = 1.0 / maxf((x1 - x0) * 0.22, 1.0)
	_detail.seed = seed_value * 7 + 3
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_detail.fractal_octaves = 5
	_detail.frequency = 1.0 / maxf(depth * 0.35, 1.0)


## Ridge height (crest line) at x.
func ridge_at(x: float) -> float:
	var u := (x - x0) / (x1 - x0)
	var ends := smoothstep(0.0, taper, u) * smoothstep(1.0, 1.0 - taper, u)
	var h := base_height + (_ridge.get_noise_1d(x) * 0.5 + 0.5) * noise_height
	for p: Dictionary in peaks:
		var dx := (x - float(p["x"])) / float(p["w"])
		h += float(p["h"]) * exp(-dx * dx)
	return h * ends


## Terrain height at x and depth fraction v (0 = front edge, 1 = back edge).
func height_at(x: float, v: float) -> float:
	var r := ridge_at(x)
	var prof: float
	if v < crest:
		prof = pow(sin(v / crest * PI * 0.5), 1.4)
	else:
		prof = pow(cos((v - crest) / (1.0 - crest) * PI * 0.5), 0.9)
	var z := z_front - v * depth
	var detail := (_detail.get_noise_2d(x, z) - 0.2) * roughness * r
	return maxf(-12.0, r * prof + detail * prof - 10.0 * (1.0 - prof))


## World position on the crest at x (for landmarks).
func crest_point(x: float) -> Vector3:
	return Vector3(x, height_at(x, crest), z_front - crest * depth)


func build_mesh() -> ArrayMesh:
	var nx := res_x + 1
	var nz := res_z + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for j in nz:
		var v := float(j) / res_z
		for i in nx:
			var x := lerpf(x0, x1, float(i) / res_x)
			hs[j * nx + i] = height_at(x, v)
	var dx := (x1 - x0) / res_x
	var dz := depth / res_z
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	uvs.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var x := x0 + i * dx
			var z := z_front - j * dz
			verts[k] = Vector3(x, hs[k], z)
			var hl := hs[j * nx + maxi(i - 1, 0)]
			var hr := hs[j * nx + mini(i + 1, nx - 1)]
			var hf := hs[maxi(j - 1, 0) * nx + i]
			var hb := hs[mini(j + 1, nz - 1) * nx + i]
			# z decreases with j, so the "back" sample is at -z
			norms[k] = Vector3(-(hr - hl) / (2.0 * dx), 1.0, (hb - hf) / (2.0 * dz)).normalized()
			uvs[k] = Vector2(float(i) / res_x, float(j) / res_z)
	var idx := PackedInt32Array()
	idx.resize(res_x * res_z * 6)
	var w := 0
	for j in res_z:
		for i in res_x:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			idx[w] = a
			idx[w + 1] = c
			idx[w + 2] = b
			idx[w + 3] = b
			idx[w + 4] = c
			idx[w + 5] = d
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A radial cone mountain (volcano) with an optional crater, centred at the origin.
static func build_cone(radius: float, height: float, crater: float, seed_v: int, rings: int = 36, segs: int = 96) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 3.0
	n.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[PackedVector3Array] = []
	for r in rings + 1:
		var row := PackedVector3Array()
		var u := float(r) / rings
		for s in segs:
			var a := TAU * s / segs
			var dir := Vector2(cos(a), sin(a))
			var rad := lerpf(crater, radius, u)
			var jag := n.get_noise_2d(dir.x * 1.3 + 3.0, dir.y * 1.3 + u * 2.0)
			var h := height * pow(1.0 - u, 1.35) * (1.0 + jag * 0.12 * (1.0 - u * 0.5))
			# gullies
			h *= 1.0 - 0.06 * absf(sin(a * 9.0 + jag * 3.0)) * u
			if r == 0:
				h -= height * 0.05
			row.append(Vector3(dir.x * rad * (1.0 + jag * 0.08), h, dir.y * rad * (1.0 + jag * 0.08)))
		pts.append(row)
	for r in rings:
		for s in segs:
			var s2 := (s + 1) % segs
			var a := pts[r][s]
			var b := pts[r][s2]
			var c := pts[r + 1][s]
			var d := pts[r + 1][s2]
			# clockwise seen from above (Godot front faces)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	return st.commit()
