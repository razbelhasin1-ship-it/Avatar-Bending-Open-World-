class_name KitMerger
extends RefCounted
## Fast accumulation of many KitResults into one (a whole settlement cell = one mesh per LOD with
## at most four material surfaces). Unlike KitResult.merge (per-vertex GDScript), positions and
## normals are transformed natively (Transform3D * PackedVector3Array) and attributes appended
## with append_array, so merging a cached 3 000-vertex house costs well under a millisecond.
## Thread-safe (pure data).
##
##   var m := KitMerger.new()
##   m.add(cached_house, Transform3D(Basis(Vector3.UP, yaw), pos))
##   m.add(kit.build())                      # unique geometry built in place
##   m.normalize_aabb(cell_aabb)             # every LOD of a cell shares one AABB (LOD hand-over)
##   var res := m.to_result()

const SLOT_ORDER: Array[StringName] = [&"solid", &"ice", &"glow", &"cloth"]

var _slots: Dictionary = {}            # slot -> GeoBuilder (used as plain array storage)
## Material slot remap applied by add(): {&"ice": &"solid", ...} folds surfaces together (one draw
## call instead of up to four: the phones' merged silhouettes, perf_polish).
var slot_map: Dictionary = {}
var boxes: Array = []
var faces := PackedVector3Array()
var lights: Array[Dictionary] = []
var markers: Dictionary = {}
var triangle_count := 0


func is_empty() -> bool:
	return _slots.is_empty() and boxes.is_empty() and faces.is_empty()


func _slot(slot: StringName) -> GeoBuilder:
	if not _slots.has(slot):
		_slots[slot] = GeoBuilder.new()
	return _slots[slot]


## Appends `res` transformed by `t` (rotation + translation; no scale). opts: collision (bool),
## lights (bool), markers (bool), marker_prefix (String).
func add(res: KitResult, t: Transform3D = Transform3D.IDENTITY, opts: Dictionary = {}) -> void:
	if res == null:
		return
	var nt := Transform3D(t.basis, Vector3.ZERO)
	for s: Array in res.surfaces:
		var arr: Array = s[0]
		var dst := _slot(slot_map.get(s[1], s[1]))
		var base := dst.verts.size()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		dst.verts.append_array(t * v)
		dst.normals.append_array(nt * (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array))
		dst.colors.append_array(arr[Mesh.ARRAY_COLOR])
		dst.uvs.append_array(arr[Mesh.ARRAY_TEX_UV])
		if arr[Mesh.ARRAY_TEX_UV2] != null and (arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() == v.size():
			dst.uv2s.append_array(arr[Mesh.ARRAY_TEX_UV2])
		else:
			var z := PackedVector2Array()
			z.resize(v.size())
			dst.uv2s.append_array(z)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if base == 0:
			dst.indices.append_array(idx)
		else:
			var off := PackedInt32Array()
			off.resize(idx.size())
			for i in idx.size():
				off[i] = idx[i] + base
			dst.indices.append_array(off)
		triangle_count += idx.size() / 3
	if opts.get("collision", true):
		for b: Array in res.boxes:
			boxes.append([t * (b[0] as Transform3D), b[1]])
		if not res.faces.is_empty():
			faces.append_array(t * res.faces)
	if opts.get("lights", true):
		for l: Dictionary in res.lights:
			var d := l.duplicate()
			d["position"] = t * (l["position"] as Vector3)
			lights.append(d)
	if opts.get("markers", false):
		var pre := String(opts.get("marker_prefix", ""))
		for k: StringName in res.markers:
			markers[StringName(pre + String(k))] = t * (res.markers[k] as Transform3D)


## Adds two unreferenced vertices at the corners of `box` to every surface, so the mesh AABB (and
## the visibility-range reference point, its centre) is exactly `box` for every LOD of a cell.
func normalize_aabb(box: AABB) -> void:
	for slot: StringName in _slots:
		var g: GeoBuilder = _slots[slot]
		if g.indices.is_empty():
			continue
		for p: Vector3 in [box.position, box.end]:
			g.verts.append(p)
			g.normals.append(Vector3.UP)
			g.colors.append(Color(0, 0, 0, 0))
			g.uvs.append(Vector2.ZERO)
			g.uv2s.append(Vector2.ZERO)


## The merged KitResult (surfaces in slot order). `aabb` is stored as-is (computing the real one
## would walk every vertex in GDScript; the renderer computes its own).
func to_result(aabb: AABB = AABB()) -> KitResult:
	var r := KitResult.new()
	for slot in SLOT_ORDER:
		if not _slots.has(slot):
			continue
		var g: GeoBuilder = _slots[slot]
		if g.indices.is_empty():
			continue
		r.surfaces.append([g.arrays(), slot])
	r.aabb = aabb
	r.boxes = boxes
	r.faces = faces
	r.lights = lights
	r.markers = markers
	r.triangle_count = triangle_count
	return r
