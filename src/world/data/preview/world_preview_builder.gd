class_name WorldPreviewBuilder
extends RefCounted
## Builds lightweight visualisations of the baked world from WorldData: a whole-world terrain
## mesh, GPU-displaced detail patches, sea/lake/canal water and markers. Used by the dev overview
## scene (scenes/dev/world_overview.tscn); not meant for gameplay rendering.

const TERRAIN_SHADER := preload("res://src/world/data/preview/world_preview_terrain.gdshader")
const WATER_SHADER := preload("res://src/world/data/preview/world_preview_water.gdshader")


## Material shared by the overview mesh and the detail patches.
static func make_terrain_material(gpu_displace: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	WorldData.apply_height_uniforms(m)
	m.set_shader_parameter(&"splat_map", WorldData.get_splat_texture())
	m.set_shader_parameter(&"biome_map", WorldData.get_biome_texture())
	m.set_shader_parameter(&"region_map", WorldData.get_region_texture())
	m.set_shader_parameter(&"ground_map", WorldData.get_ground_texture())
	m.set_shader_parameter(&"road_map", WorldData.get_road_texture())
	m.set_shader_parameter(&"gpu_displace", gpu_displace)
	return m


static func make_water_material(level: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	WorldData.apply_height_uniforms(m)
	m.set_shader_parameter(&"water_level", level)
	return m


## Whole-world terrain mesh with `res` x `res` vertices (CPU heights from WorldData).
static func build_world_mesh(res: int) -> ArrayMesh:
	var size := WorldConstants.WORLD_SIZE
	var step := size / float(res)
	var origin := WorldConstants.WORLD_MIN + step * 0.5
	var heights := WorldData.get_height_block(origin, origin, res, res, step)
	var verts := PackedVector3Array()
	verts.resize(res * res)
	var k := 0
	for j in res:
		var z := origin + j * step
		for i in res:
			verts[k] = Vector3(origin + i * step, heights[k], z)
			k += 1
	var idx := PackedInt32Array()
	idx.resize((res - 1) * (res - 1) * 6)
	k = 0
	for j in res - 1:
		var r0 := j * res
		var r1 := r0 + res
		for i in res - 1:
			idx[k] = r0 + i
			idx[k + 1] = r0 + i + 1
			idx[k + 2] = r1 + i
			idx[k + 3] = r0 + i + 1
			idx[k + 4] = r1 + i + 1
			idx[k + 5] = r1 + i
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Square detail patch near (cx, cz), displaced on the GPU from the 2 m heightmap. Vertices sit
## exactly on heightmap texel centres (one per texel), so the GPU mesh reproduces the data.
static func build_patch(cx: float, cz: float, size: float) -> MeshInstance3D:
	var t := WorldConstants.TEXEL_SIZE
	var cells := int(size / t / 2.0) * 2
	size = cells * t
	# texel centres sit at odd metres; an even cell count keeps the plane centre on one too
	cx = floorf(cx / t) * t + t * 0.5
	cz = floorf(cz / t) * t + t * 0.5
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = cells - 1
	pm.subdivide_depth = cells - 1
	pm.custom_aabb = AABB(Vector3(-size * 0.5, -400.0, -size * 0.5), Vector3(size, 1700.0, size))
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(cx, 0.0, cz)
	mi.material_override = make_terrain_material(true)
	return mi


## Sea plane covering the world (plus a margin) at sea level.
static func build_sea() -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(80000.0, 80000.0)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(0.0, WorldConstants.SEA_LEVEL, 0.0)
	mi.material_override = make_water_material(WorldConstants.SEA_LEVEL)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Water surfaces for every unfrozen lake and every canal.
static func build_inland_water() -> Node3D:
	var root := Node3D.new()
	root.name = "InlandWater"
	for lk in WorldData.get_lakes():
		if lk["frozen"]:
			continue
		var poly: PackedVector2Array = lk["polygon"]
		var level := float(lk["level"])
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			continue
		var verts := PackedVector3Array()
		var grow := 1.12
		var c: Vector3 = lk["center"]
		for p in poly:
			var q := Vector2(c.x, c.z) + (p - Vector2(c.x, c.z)) * grow
			verts.append(Vector3(q.x, level, q.y))
		root.add_child(_mesh_from(verts, tris, level))
	for canal in WorldData.get_canals():
		var pts: PackedVector2Array = canal["points"]
		var hw := float(canal["width"]) * 0.5 + 0.6
		var level := float(canal["level"])
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		for k in pts.size():
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, pts.size() - 1)]
			var d := (b - a).normalized()
			var nrm := Vector2(-d.y, d.x) * hw
			verts.append(Vector3(pts[k].x + nrm.x, level, pts[k].y + nrm.y))
			verts.append(Vector3(pts[k].x - nrm.x, level, pts[k].y - nrm.y))
			if k > 0:
				var o := (k - 1) * 2
				idx.append_array([o, o + 2, o + 1, o + 1, o + 2, o + 3])
		root.add_child(_mesh_from(verts, idx, level))
	return root


static func _mesh_from(verts: PackedVector3Array, idx: PackedInt32Array, level: float) -> MeshInstance3D:
	# make the winding face up regardless of polygon orientation
	var fixed := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		if (b - a).cross(c - a).y > 0.0:
			fixed.append_array([idx[t], idx[t + 2], idx[t + 1]])
		else:
			fixed.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = fixed
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = make_water_material(level)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Marker posts (CPU heights) for POIs, gates and spawns: they must sit exactly on the
## GPU-displaced terrain, which makes them a visual check of the shared sampling formula.
static func build_markers(scale: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Markers"
	var poi_mat := ToonMaterials.make(Color(0.98, 0.78, 0.25), {"outline": false})
	var gate_mat := ToonMaterials.make(Color(0.86, 0.22, 0.12), {"outline": false})
	var spawn_mat := ToonMaterials.make(Color(0.25, 0.55, 0.98), {"outline": false})
	for p in WorldData.get_pois():
		root.add_child(_post(p["position"], poi_mat, 2.2 * scale))
	for c in WorldData.get_cities():
		for g: Dictionary in c.get("gates", []):
			root.add_child(_post(g["position"], gate_mat, 2.6 * scale))
	for e: int in ElementDefs.ALL:
		root.add_child(_post(WorldData.get_spawn(e).origin, spawn_mat, 3.0 * scale))
	return root


static func _post(pos: Vector3, mat: Material, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.35
	cyl.bottom_radius = radius * 0.35
	cyl.height = radius * 6.0
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = pos + Vector3(0, radius * 3.0, 0)
	var cap := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	cap.mesh = sph
	cap.material_override = mat
	cap.position = Vector3(0, radius * 3.0, 0)
	mi.add_child(cap)
	return mi
