class_name KitResult
extends RefCounted
## Output of BuildingKit.build(): renderer-free mesh arrays per material slot, collision boxes and
## trimesh faces, recorded lights and markers — all in kit space. Main-thread helpers turn it into
## nodes (`instantiate`) or append it to a streamed cell (`add_to_payload`).

## [[arrays, slot StringName], ...] (non-empty surfaces only)
var surfaces: Array = []
## [[Transform3D, Vector3 size], ...]
var boxes: Array = []
var faces := PackedVector3Array()
var lights: Array[Dictionary] = []
var markers: Dictionary = {}
var aabb := AABB()
var triangle_count: int = 0


func is_empty() -> bool:
	return surfaces.is_empty() and boxes.is_empty() and faces.is_empty()


## One ArrayMesh with a surface per slot (shared slot materials). Main thread.
func make_mesh() -> ArrayMesh:
	var m := ArrayMesh.new()
	for s: Array in surfaces:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s[0])
		m.surface_set_material(m.get_surface_count() - 1, NationPalette.material(s[1]))
	return m


## Builds a node tree: Node3D "Kit" with a MeshInstance3D, a StaticBody3D (boxes + trimesh,
## Layers.WORLD) and budgeted OmniLight3Ds. opts: name, shadows (bool, default true),
## vis_end (visibility range end, 0 = none), collision (bool, default true), lights (bool).
func instantiate(opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = String(opts.get("name", "Kit"))
	if not surfaces.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = make_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opts.get("shadows", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ve := float(opts.get("vis_end", 0.0))
		if ve > 0.0:
			mi.visibility_range_end = ve
			mi.visibility_range_end_margin = 10.0
		root.add_child(mi)
	if opts.get("collision", true) and (not boxes.is_empty() or not faces.is_empty()):
		root.add_child(make_body(int(opts.get("layer", Layers.WORLD))))
	if opts.get("lights", true):
		for l in lights:
			root.add_child(LightBudget.make_light(l))
	return root


## StaticBody3D with every collision box and the trimesh faces.
func make_body(layer: int = Layers.WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = layer
	body.collision_mask = 0
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.transform = b[0]
		body.add_child(cs)
	if not faces.is_empty():
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		sh.backface_collision = true
		cs.shape = sh
		body.add_child(cs)
	return body


## Appends this result to a streamed cell payload at `t` (relative to the cell root): one mesh
## entry, static collision and the lights (created by a main-thread call). Thread-safe.
## opts: vis_end, vis_begin, shadow, tag.
func add_to_payload(p: CellPayload, t: Transform3D, opts: Dictionary = {}) -> void:
	if not surfaces.is_empty():
		var surf: Array = []
		# "outline": false = materials without the ink outline pass (distant LODs, perf_polish)
		var outline: bool = opts.get("outline", true)
		# "lods": true = automatic LOD index buffers (MeshLods, worker-safe), perf_polish
		var lods: bool = opts.get("lods", false)
		# "flat_slots": slots drawn without the outline pass even when "outline" is on (phones)
		var flat: Array = opts.get("flat_slots", [])
		for s: Array in surfaces:
			var mat := NationPalette.material(s[1], outline and not flat.has(s[1]))
			if lods:
				surf.append([s[0], mat, MeshLods.for_arrays(s[0])])
			else:
				surf.append([s[0], mat])
		p.add_mesh_surfaces(surf, t, {"shadow": opts.get("shadow", true), "vis_end": opts.get("vis_end", 0.0),
			"vis_begin": opts.get("vis_begin", 0.0), "margin": opts.get("margin", 10.0), "tag": opts.get("tag", &""),
			"fade": opts.get("fade", 0), "vis_parent": opts.get("vis_parent", &""), "lod_bias": opts.get("lod_bias", 1.0)})
	if opts.get("collision", true):
		if not boxes.is_empty():
			var bx: Array = []
			for b: Array in boxes:
				bx.append([t * (b[0] as Transform3D), b[1]])
			p.add_static_boxes(bx)
		if not faces.is_empty():
			var f := PackedVector3Array()
			f.resize(faces.size())
			for i in faces.size():
				f[i] = t * faces[i]
			p.add_static_faces(f)
	if opts.get("lights", true) and not lights.is_empty():
		var ls := lights.duplicate()
		p.add_call(func(cell: ContentCell) -> void:
			for l: Dictionary in ls:
				var d := l.duplicate()
				d["position"] = t * (l["position"] as Vector3)
				cell.root.add_child(LightBudget.make_light(d)))


## Merges another result (transformed by t) into this one (e.g. a cell of buildings).
func merge(other: KitResult, t: Transform3D = Transform3D.IDENTITY) -> void:
	for s: Array in other.surfaces:
		var slot: StringName = s[1]
		var idx := -1
		for i in surfaces.size():
			if surfaces[i][1] == slot:
				idx = i
		var gb := GeoBuilder.new()
		var src := GeoBuilder.new()
		var arr: Array = s[0]
		src.verts = arr[Mesh.ARRAY_VERTEX]
		src.normals = arr[Mesh.ARRAY_NORMAL]
		src.colors = arr[Mesh.ARRAY_COLOR]
		src.uvs = arr[Mesh.ARRAY_TEX_UV]
		src.uv2s = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		src.indices = arr[Mesh.ARRAY_INDEX]
		if idx >= 0:
			var dst_arr: Array = surfaces[idx][0]
			gb.verts = dst_arr[Mesh.ARRAY_VERTEX]
			gb.normals = dst_arr[Mesh.ARRAY_NORMAL]
			gb.colors = dst_arr[Mesh.ARRAY_COLOR]
			gb.uvs = dst_arr[Mesh.ARRAY_TEX_UV]
			gb.uv2s = dst_arr[Mesh.ARRAY_TEX_UV2] if dst_arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
			gb.indices = dst_arr[Mesh.ARRAY_INDEX]
		gb.append(src, t)
		if idx >= 0:
			surfaces[idx][0] = gb.arrays()
		else:
			surfaces.append([gb.arrays(), slot])
	for b: Array in other.boxes:
		boxes.append([t * (b[0] as Transform3D), b[1]])
	for f in other.faces:
		faces.append(t * f)
	for l: Dictionary in other.lights:
		var d := l.duplicate()
		d["position"] = t * (l["position"] as Vector3)
		lights.append(d)
	for k: StringName in other.markers:
		markers[k] = t * (other.markers[k] as Transform3D)
	triangle_count += other.triangle_count
	var ob := t * other.aabb
	aabb = ob if aabb.size == Vector3.ZERO else aabb.merge(ob)
