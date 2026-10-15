class_name EarthPreviewFx
extends PreviewFx
## Earthbending showcase: a stomp tears a boulder out of the ground, it is lifted and
## hurled across the frame; punches launch rock chunks; every stomp kicks up debris.

var _rocks: Array[Dictionary] = []
var _rock_mesh: ArrayMesh
var _rock_mat: Material
var _held: Dictionary = {}


func sequence() -> Array[Dictionary]:
	return [
		{"clip": &"earth_throw", "pause": 0.7},
		{"clip": &"earth_jab_r", "pause": 0.2}, {"clip": &"earth_jab_l", "pause": 0.9},
	]


func _setup() -> void:
	_rock_mesh = make_rock_mesh(7)
	# in the show-intro motif the rock is a dark red-brown mass, like the opening titles
	_rock_mat = ToonMaterials.make(Color(0.42, 0.20, 0.13) if motif else Color(0.50, 0.43, 0.36))


func on_event(clip: StringName, event: StringName) -> void:
	var fwd := forward()
	var ground := rig.global_position
	match [clip, event]:
		[&"earth_throw", &"stomp"]:
			var pos := ground + fwd * 0.85
			_held = _spawn_rock(pos + Vector3.DOWN * 0.7, 0.42)
			_held["target"] = pos + Vector3.UP * 0.45
			_held["state"] = &"rise"
			CreatureFx.debris_burst(self, pos, &"stone", 1.0 * budget + 0.3, 0.6)
		[&"earth_throw", &"lift"]:
			if not _held.is_empty():
				_held["target"] = ground + fwd * 0.75 + Vector3.UP * 1.45
		[&"earth_throw", &"release"]:
			if not _held.is_empty():
				_held["state"] = &"fly"
				_held["vel"] = fwd * 9.0 + Vector3.UP * 0.6
				_held = {}
		[&"earth_jab_r", &"stomp"], [&"earth_jab_l", &"stomp"]:
			var p2 := ground + fwd * 0.7 + rig.global_transform.basis.x * (0.15 if clip == &"earth_jab_r" else -0.15)
			var chunk := _spawn_rock(p2 + Vector3.DOWN * 0.3, 0.2)
			chunk["target"] = p2 + Vector3.UP * 1.0
			chunk["state"] = &"rise"
			chunk["punch_at"] = 0.06
			CreatureFx.debris_burst(self, p2, &"stone", 0.5 * budget + 0.2, 0.35)
		[&"earth_jab_r", &"release"], [&"earth_jab_l", &"release"]:
			for r: Dictionary in _rocks:
				if r.get("state") == &"rise" and r.has("punch_at"):
					r["state"] = &"fly"
					r["vel"] = fwd * 11.0 + Vector3.UP * 0.4


func _spawn_rock(pos: Vector3, size: float) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_mesh
	mi.material_override = _rock_mat
	mi.scale = Vector3.ONE * size
	add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var d := {"node": mi, "state": &"rise", "target": pos, "vel": Vector3.ZERO, "life": 2.5, "spin": Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))}
	_rocks.append(d)
	return d


func step(delta: float) -> void:
	for i in range(_rocks.size() - 1, -1, -1):
		var r: Dictionary = _rocks[i]
		var n: MeshInstance3D = r["node"]
		r["life"] = float(r["life"]) - delta
		match r["state"]:
			&"rise":
				n.global_position = n.global_position.lerp(r["target"], 1.0 - exp(-delta * 9.0))
				n.rotation += Vector3(0.4, 0.7, 0.2) * delta
			&"fly":
				r["vel"] = (r["vel"] as Vector3) + Vector3(0, -3.0, 0) * delta
				n.global_position += (r["vel"] as Vector3) * delta
				n.rotation += (r["spin"] as Vector3) * delta
				if float(r["life"]) > 1.2:
					r["life"] = 1.2
		if float(r["life"]) <= 0.0:
			n.queue_free()
			_rocks.remove_at(i)


## Faceted boulder: an icosphere-like sphere pushed around by noise (flat shaded).
static func make_rock_mesh(seed_v: int) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 1.6
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for k in idx.size():
		var v := verts[idx[k]]
		var d := 1.0 + n.get_noise_3dv(v * 1.3) * 0.35
		v = v * d
		v.y *= 0.8
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()
