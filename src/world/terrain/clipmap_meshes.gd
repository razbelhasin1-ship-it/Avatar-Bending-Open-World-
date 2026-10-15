class_name ClipmapMeshes
extends RefCounted
## Shared meshes of the geometry clipmap (after M. Savage's "simple terrain rendering with
## level of detail"), expressed in cell units of one level (x/z integers, y = 0). A level of
## scale `s` metres per cell draws them with a Transform3D scaled by (s, 1, s).
##
## Layout of level l around its snapped origin P (in cells, P is the bottom-left corner of the
## cell containing the camera):
##   extent  [-2T, 2T + 1] in x and z (4T + 1 cells)
##   tiles   T x T at x0, z0 in {-2T, -T, 1, T + 1}; levels > 0 skip the inner 2 x 2
##   filler  1-cell arms between the outer tiles; level 0 uses the full `cross` instead
##   trim    1-cell L strip that fills the gap to the hole of level l + 1 (4 variants,
##           chosen by the parity of P relative to the next level's origin)
##   seam    degenerate (even, odd, even) triangles along the hole of level l + 1 that close
##           T-junction cracks exactly (zero area once geomorphing collapses odd vertices)
## Every quad is split along the same (0,0)-(1,1) diagonal so that, with odd vertices morphed
## to the average of their even neighbours, a level degenerates exactly into the next one.
## Godot front faces are clockwise when seen from above (+Y looking down, -Z up on screen).

var tile_res: int = 32
var tile: ArrayMesh
var filler: ArrayMesh
var cross: ArrayMesh
## trims[ox + 2 * oz] where ox/oz = 1 when the level origin is one cell past the next level's.
var trims: Array[ArrayMesh] = []
var seam: ArrayMesh


func _init(t: int = 32) -> void:
	tile_res = t
	tile = _grid_mesh([Rect2i(0, 0, t, t)])
	filler = _grid_mesh([Rect2i(t + 1, 0, t, 1), Rect2i(-2 * t, 0, t, 1),
			Rect2i(0, t + 1, 1, t), Rect2i(0, -2 * t, 1, t)])
	cross = _grid_mesh([Rect2i(-2 * t, 0, 4 * t + 1, 1), Rect2i(0, -2 * t, 1, 2 * t), Rect2i(0, 1, 1, 2 * t)])
	trims.clear()
	for oz in 2:
		for ox in 2:
			var gx := 2 * t + 1 if ox == 0 else -2 * t
			var gz := 2 * t + 1 if oz == 0 else -2 * t
			# column covers the full hole height; the row covers the level's own x extent
			trims.append(_grid_mesh([Rect2i(gx, -2 * t, 1, 4 * t + 2), Rect2i(-2 * t + ox, gz, 4 * t + 1, 1)]))
	seam = _seam_mesh(4 * t + 2, -2 * t)


## Number of cells covered by one level (outer extent).
func level_cells() -> int:
	return 4 * tile_res + 1


## Tile origins (cells, relative to the level origin) for a level.
func tile_origins(level: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var t := tile_res
	var starts := [-2 * t, -t, 1, t + 1]
	for zi in 4:
		for xi in 4:
			if level > 0 and (xi == 1 or xi == 2) and (zi == 1 or zi == 2):
				continue
			out.append(Vector2i(starts[xi], starts[zi]))
	return out


## Triangle count of one full level (for budgets/diagnostics).
func level_triangles(level: int) -> int:
	var t := tile_res
	var tiles := 16 if level == 0 else 12
	var n := tiles * t * t * 2
	n += (4 * t + 1 + 4 * t) * 2 if level == 0 else 4 * t * 2
	n += (8 * t + 3) * 2      # trim
	n += (4 * t + 2) * 4      # seam (both windings)
	return n


static func _grid_mesh(rects: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for r: Rect2i in rects:
		var base := verts.size()
		var w := r.size.x
		var h := r.size.y
		for j in h + 1:
			for i in w + 1:
				verts.append(Vector3(r.position.x + i, 0.0, r.position.y + j))
		var row := w + 1
		for j in h:
			for i in w:
				var a := base + j * row + i
				var b := a + 1
				var c := a + row
				var d := c + 1
				idx.append_array([a, b, d, a, d, c])
	return _make(verts, idx)


## Ring of degenerate triangles along the square [origin, origin + side] (cells, side even).
static func _seam_mesh(side: int, origin: int) -> ArrayMesh:
	var ring := PackedVector3Array()
	for i in side:
		ring.append(Vector3(origin + i, 0.0, origin))
	for i in side:
		ring.append(Vector3(origin + side, 0.0, origin + i))
	for i in side:
		ring.append(Vector3(origin + side - i, 0.0, origin + side))
	for i in side:
		ring.append(Vector3(origin, 0.0, origin + side - i))
	var n := ring.size()
	var idx := PackedInt32Array()
	for k in range(0, n, 2):
		var a := k
		var b := (k + 1) % n
		var c := (k + 2) % n
		# both windings: the slivers are vertical and must be visible from either side
		idx.append_array([a, b, c, a, c, b])
	return _make(ring, idx)


static func _make(verts: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
