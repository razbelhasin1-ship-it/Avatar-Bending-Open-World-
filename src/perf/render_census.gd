class_name RenderCensus
extends RefCounted
## What the camera actually draws, grouped by origin (perf_polish, docs/qa/perf_polish.md).
##
##   var c := RenderCensus.take(scene_root, camera)
##   # {"groups": [{group, instances, draws, triangles, shadow_casters}...], "totals": {...}}
##
## Unlike PerfProbe.census (mobile module) this one frustum-culls with the camera, applies
## visibility ranges exactly like the renderer (distance to the instance AABB centre) and
## counts draw passes the way the renderers do: one per surface plus one per material
## next_pass (the ink outline of the toon materials), MultiMesh triangles x visible instances.
## Streamed content is grouped by provider and LOD tag ("settlement_northern_water_tribe/lod1",
## "settlement_far_.../sub", ".../glow", "vegetation/..."), everything else by owning script.


static func take(root: Node, camera: Camera3D) -> Dictionary:
	var planes := camera.get_frustum()
	var cam_pos := camera.global_position
	var groups := {}
	var totals := {"instances": 0, "draws": 0, "triangles": 0, "shadow_casters": 0, "shadow_triangles": 0}
	var tri_cache := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is CanvasItem or n is CanvasLayer:
			continue
		for c in n.get_children():
			stack.append(c)
		if not (n is GeometryInstance3D):
			continue
		var gi := n as GeometryInstance3D
		if not gi.is_inside_tree() or (gi.layers & camera.cull_mask) == 0:
			continue
		var aabb := gi.global_transform * gi.get_aabb()
		var d := cam_pos.distance_to(aabb.get_center())
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin:
			continue
		if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin - gi.visibility_range_begin_margin:
			continue
		# HLOD: only drawn while the visibility parent is hidden for being closer than its begin
		if not gi.visibility_parent.is_empty():
			var par := gi.get_node_or_null(gi.visibility_parent) as GeometryInstance3D
			if par != null and par.visible:
				var pd := cam_pos.distance_to((par.global_transform * par.get_aabb()).get_center())
				if not (par.visibility_range_begin > 0.0 and pd < par.visibility_range_begin):
					continue
		if not aabb_in_frustum(aabb, planes):
			continue
		var info := _draw_info(gi, tri_cache)
		if int(info["draws"]) == 0:
			continue
		var key := group_of(gi, root)
		var e: Dictionary = groups.get(key, {"group": key, "instances": 0, "draws": 0, "triangles": 0, "shadow_casters": 0})
		e["instances"] = int(e["instances"]) + 1
		e["draws"] = int(e["draws"]) + int(info["draws"])
		e["triangles"] = int(e["triangles"]) + int(info["triangles"])
		totals["instances"] += 1
		totals["draws"] += int(info["draws"])
		totals["triangles"] += int(info["triangles"])
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			e["shadow_casters"] = int(e["shadow_casters"]) + 1
			totals["shadow_casters"] += 1
			totals["shadow_triangles"] += int(info["base_triangles"])
		groups[key] = e
	var ranked: Array = groups.values()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["triangles"]) > int(b["triangles"]))
	return {"groups": ranked, "totals": totals}


## True when the world-space AABB is (at least partly) inside the frustum planes.
static func aabb_in_frustum(aabb: AABB, planes: Array[Plane]) -> bool:
	for pl in planes:
		# the corner furthest along the plane normal must be behind the plane (Godot frustum
		# planes point outwards)
		var v := aabb.position
		if pl.normal.x < 0.0:
			v.x += aabb.size.x
		if pl.normal.y < 0.0:
			v.y += aabb.size.y
		if pl.normal.z < 0.0:
			v.z += aabb.size.z
		if pl.distance_to(v) > 0.0:
			return false
	return true


## {draws, triangles (all passes), base_triangles (first pass only)} of one instance.
static func _draw_info(gi: GeometryInstance3D, cache: Dictionary) -> Dictionary:
	var mesh: Mesh = null
	var count := 1
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm == null:
			return {"draws": 0, "triangles": 0, "base_triangles": 0}
		mesh = mm.mesh
		count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	else:
		# particles, sprites, CSG...: one draw, triangles unknown
		return {"draws": 1, "triangles": 0, "base_triangles": 0}
	if mesh == null or count <= 0:
		return {"draws": 0, "triangles": 0, "base_triangles": 0}
	var draws := 0
	var tris := 0
	var base := 0
	for s in mesh.get_surface_count():
		var t := _surface_tris(mesh, s, cache) * count
		var mat: Material = gi.material_override
		if mat == null and gi is MeshInstance3D:
			mat = (gi as MeshInstance3D).get_active_material(s)
		var passes := 1
		var m := mat.next_pass if mat != null else null
		while m != null and passes < 8:
			passes += 1
			m = m.next_pass
		draws += passes
		tris += t * passes
		base += t
	return {"draws": draws, "triangles": tris, "base_triangles": base}


static func _surface_tris(mesh: Mesh, s: int, cache: Dictionary) -> int:
	var key := "%d|%d" % [mesh.get_instance_id(), s]
	if cache.has(key):
		return int(cache[key])
	var t := 0
	if mesh is ArrayMesh or mesh is PrimitiveMesh:
		var arr := mesh.surface_get_arrays(s)
		if not arr.is_empty():
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				t = (idx as PackedInt32Array).size() / 3
			elif arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				t = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	cache[key] = t
	return t


## Group name of an instance: content provider + LOD tag, else the owning script.
static func group_of(n: Node, root: Node) -> String:
	var cur := n
	var prev: Node = null
	while cur != null and cur != root:
		if cur is WorldContent and prev != null:
			var parts := String(prev.name).split("_")
			var provider := "_".join(parts.slice(0, maxi(1, parts.size() - 2)))
			return "%s/%s" % [provider, lod_tag(String(n.name))]
		var s: Script = cur.get_script()
		if s != null and not s.resource_path.is_empty() and not (cur is WorldContent):
			return s.resource_path.trim_prefix("res://src/").trim_suffix(".gd")
		prev = cur
		cur = cur.get_parent()
	return "(unscripted)"


## Coarse kind of a streamed node from its payload tag ("..._lod0", "..._glow_3_4", ...).
static func lod_tag(node_name: String) -> String:
	if node_name.contains("_glow"):
		return "glow"
	if node_name.contains("_lod0m"):
		return "lod0_mid"
	if node_name.contains("_lod0q"):
		return "lod0_fine"
	if node_name.contains("_lod0"):
		return "lod0"
	if node_name.contains("_lod1"):
		return "lod1"
	if node_name.begins_with("settlement_far_"):
		return "sub"
	return node_name.lstrip("@").rstrip("@0123456789").trim_suffix("_")
