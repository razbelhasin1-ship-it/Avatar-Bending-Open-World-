class_name MeshLods
extends RefCounted
## Automatic mesh LODs for procedurally built meshes (perf_polish, docs/qa/perf_polish.md).
##
## Godot draws an ArrayMesh surface that carries LOD index buffers with the coarsest one whose
## screen-space error stays under Viewport.mesh_lod_threshold (Settings: 4 px on phones, 1 px on
## High), per instance and per frame, in every pass (shadows and the ink outline too). Imported
## models get those buffers at import time; the game builds its meshes in code, so they had none.
##
##   var lods := MeshLods.for_arrays(arrays)          # WORKER-THREAD SAFE: pure data
##   mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)   # main thread
##
## Uses ImporterMesh.generate_lods (meshoptimizer) without ever creating a RenderingServer
## resource, so it runs inside WorldContent cell builds. Vertex arrays are left untouched (the
## index buffers refer to them), including unreferenced AABB-normalising vertices.

## Surfaces smaller than this are not worth an extra index buffer.
const MIN_TRIANGLES := 600


## {lod_size: PackedInt32Array indices} for one triangle surface (empty when not useful).
static func for_arrays(arrays: Array, merge_angle: float = 25.0, split_angle: float = 60.0) -> Dictionary:
	if arrays.is_empty() or arrays[Mesh.ARRAY_INDEX] == null:
		return {}
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.size() / 3 < MIN_TRIANGLES:
		return {}
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(merge_angle, split_angle, [])
	if im.get_surface_count() != 1:
		return {}
	# The LOD buffers must index the very same vertex array (they do: generate_lods only adds
	# index buffers) - anything else would scramble the mesh, so it is checked, not assumed.
	var after := im.get_surface_arrays(0)
	if (after[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		return {}
	var out := {}
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		if li.size() >= 3:
			out[im.get_surface_lod_size(0, l)] = li
	return out


## Triangle counts of the LOD chain of `lods` (largest first), for reports.
static func chain(lods: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for k: float in lods:
		out.append((lods[k] as PackedInt32Array).size() / 3)
	out.sort()
	out.reverse()
	return out
