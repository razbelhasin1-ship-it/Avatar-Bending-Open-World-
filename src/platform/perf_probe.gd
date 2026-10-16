class_name PerfProbe
extends RefCounted
## Performance measurement for the mobile pass (docs/modules/mobile.md "Performance").
##
##   PerfProbe.enable_timing(get_viewport())         # CPU/GPU render timings
##   var s := PerfProbe.frame_stats(get_viewport())  # draw calls, objects, primitives (+ shadow pass)
##   var c := PerfProbe.census(scene_root, camera)   # what is on screen, by module / kind
##   var r := await PerfProbe.sample(tree, vp, 5.0)  # averages over N seconds
##
## Draw calls / objects / primitives / instance and particle counts are device-independent
## and are what the budgets are written against; frame times measured under software
## rendering (llvmpipe / SwiftShader) only rank costs, they do not predict a phone.


static func enable_timing(vp: Viewport) -> void:
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)


## Counters of the last rendered frame of `vp`.
static func frame_stats(vp: Viewport) -> Dictionary:
	var rid := vp.get_viewport_rid()
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var sh := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	return {
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"cpu_render_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid),
		"gpu_render_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
		"draw_calls": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_draw_calls": RenderingServer.viewport_get_render_info(rid, sh, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_primitives": RenderingServer.viewport_get_render_info(rid, sh, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"physics_active": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
	}


## Averages frame_stats over `seconds` of wall time (one sample per rendered frame).
## Returns the means plus "frames", "fps_avg", "frame_ms_avg", "frame_ms_p95", "frame_ms_max".
static func sample(tree: SceneTree, vp: Viewport, seconds: float) -> Dictionary:
	enable_timing(vp)
	var sums := {}
	var frame_ms: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	await tree.process_frame
	while Time.get_ticks_usec() - t0 < int(seconds * 1000000.0):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		var s := frame_stats(vp)
		for k: String in s:
			sums[k] = float(sums.get(k, 0.0)) + float(s[k])
	var n := maxi(frame_ms.size(), 1)
	var out := {}
	for k: String in sums:
		out[k] = float(sums[k]) / n
	frame_ms.sort()
	var total := 0.0
	for f in frame_ms:
		total += f
	out["frames"] = frame_ms.size()
	out["frame_ms_avg"] = total / n
	out["frame_ms_p95"] = frame_ms[mini(frame_ms.size() - 1, int(frame_ms.size() * 0.95))] if not frame_ms.is_empty() else 0.0
	out["frame_ms_max"] = frame_ms[-1] if not frame_ms.is_empty() else 0.0
	out["fps_avg"] = 1000.0 / maxf(float(out["frame_ms_avg"]), 0.001)
	return out


## What is drawn: visible geometry instances, their triangle counts (MultiMesh instances x
## mesh triangles), skinned meshes, particle systems + amounts, lights and shadow casters,
## grouped by owning module (script path of the nearest scripted ancestor below `root`).
## Only nodes within `max_dist` of `camera` (and inside their visibility range) count.
static func census(root: Node, camera: Camera3D, max_dist: float = 100000.0) -> Dictionary:
	var by_owner := {}
	var totals := {"instances": 0, "triangles": 0, "multimesh_instances": 0, "skinned": 0, "particles": 0,
			"particle_amount": 0, "lights": 0, "shadow_lights": 0, "shadow_casters": 0}
	var tri_cache := {}
	var cam_pos := camera.global_position if camera else Vector3.ZERO
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is VisualInstance3D):
			continue
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var d := cam_pos.distance_to(vi.global_position) if camera else 0.0
		if d > max_dist:
			continue
		if n is GeometryInstance3D:
			var gi := n as GeometryInstance3D
			if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin:
				continue
			if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin:
				continue
		var key := _owner_key(n, root)
		var e: Dictionary = by_owner.get(key, {"instances": 0, "triangles": 0, "skinned": 0, "particles": 0, "lights": 0})
		var tris := 0
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			tris = _mesh_tris(mi.mesh, tri_cache)
			if mi.skin != null or mi.get_parent() is Skeleton3D:
				e["skinned"] = int(e["skinned"]) + 1
				totals["skinned"] += 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				totals["shadow_casters"] += 1
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm:
				var cnt := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				tris = _mesh_tris(mm.mesh, tri_cache) * cnt
				totals["multimesh_instances"] += cnt
		elif n is GPUParticles3D or n is CPUParticles3D:
			var emitting := bool(n.get("emitting"))
			if emitting:
				e["particles"] = int(e["particles"]) + 1
				totals["particles"] += 1
				totals["particle_amount"] += int(n.get("amount"))
		elif n is Light3D:
			e["lights"] = int(e["lights"]) + 1
			totals["lights"] += 1
			if (n as Light3D).shadow_enabled:
				totals["shadow_lights"] += 1
		e["instances"] = int(e["instances"]) + 1
		e["triangles"] = int(e["triangles"]) + tris
		totals["instances"] += 1
		totals["triangles"] += tris
		by_owner[key] = e
	var ranked: Array = []
	for k: String in by_owner:
		var e2: Dictionary = by_owner[k]
		e2["owner"] = k
		ranked.append(e2)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["triangles"]) > int(b["triangles"]))
	totals["by_owner"] = ranked
	return totals


static func _mesh_tris(mesh: Mesh, cache: Dictionary) -> int:
	if mesh == null:
		return 0
	var id := mesh.get_instance_id()
	if cache.has(id):
		return int(cache[id])
	var t := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		elif arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	cache[id] = t
	return t


## Owner = script file (without dir noise) of the nearest scripted ancestor below `root`,
## e.g. "world/content/world_content" or "characters/humanoid_rig".
static func _owner_key(n: Node, root: Node) -> String:
	var cur := n
	while cur != null and cur != root:
		var s: Script = cur.get_script()
		if s != null and not s.resource_path.is_empty():
			return s.resource_path.trim_prefix("res://src/").trim_suffix(".gd")
		cur = cur.get_parent()
	return "(unscripted)"


## Compact one-line summary of a sample() result.
static func describe(s: Dictionary) -> String:
	return "fps %.1f (frame avg %.1f ms, p95 %.1f) | draw calls %d (+%d shadow) | objects %d | prims %dk (+%dk shadow) | nodes %d" % [
		float(s.get("fps_avg", s.get("fps", 0.0))), float(s.get("frame_ms_avg", 0.0)), float(s.get("frame_ms_p95", 0.0)),
		int(s.get("draw_calls", 0)), int(s.get("shadow_draw_calls", 0)), int(s.get("objects", 0)),
		int(float(s.get("primitives", 0)) / 1000.0), int(float(s.get("shadow_primitives", 0)) / 1000.0), int(s.get("nodes", 0))]
