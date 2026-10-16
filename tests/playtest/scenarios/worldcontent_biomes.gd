extends RefCounted
## Vegetation in the real world: every biome at ground level and from mid altitude (snow forest,
## Earth Kingdom forest + bamboo + farms, Fire Nation jungle + volcanic, Air Temple garden
## slopes) and a far-forest vista. Streams content around the camera, waits until settled and
## reports instance counts, draw calls and frame time per view. `--views=a,b` limits the set.

const SHOTS := ["snow_forest", "snow_forest_mid", "ek_forest", "ek_forest_mid", "ek_farms", "ek_farms_mid", "ek_meadow",
		"fn_jungle", "fn_jungle_mid", "fn_beach", "fn_volcanic", "fn_volcanic_mid", "at_garden", "at_slopes_mid", "forest_far", "wt_snow"]


func run(p: Playtest) -> void:
	var t0 := Time.get_ticks_msec()
	var scene := await p.load_scene("res://scenes/dev/worldcontent_world.tscn")
	p.check(scene != null and WorldData.has_world_data(), "dev scene + world data loaded")
	if scene == null:
		return
	var world: WorldRenderer = scene.world
	var content: WorldContent = scene.content
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	await p.wait_until(func() -> bool: return VegetationLibrary.is_ready(), 30.0)
	p.check(VegetationLibrary.is_ready(), "vegetation meshes built (%.0f ms)" % VegetationLibrary.build_time_ms)
	p.note("scene ready in %d ms" % (Time.get_ticks_msec() - t0))
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			only = a.substr(8)
	for v: String in SHOTS:
		if not only.is_empty() and not only.split(",").has(v):
			continue
		scene.set_view(v)
		var tl := Time.get_ticks_msec()
		var ok := content.load_now(scene.cam.global_position)
		await _clear_view(p, scene)
		var load_ms := Time.get_ticks_msec() - tl
		await p.frames(4)
		await p.wait(1.0)
		var st := content.get_stats()
		var stats := await _measure(p, 12)
		var per: Dictionary = st["providers"]
		var inst := []
		for id: StringName in per:
			inst.append("%s %d/%d cells %d inst" % [id, per[id]["active"], per[id]["cells"], per[id]["instances"]])
		p.note("%s: load %d ms (%s), %.0f ms/frame, %d draw calls, %d prims, mm nodes %d | %s" % [v, load_ms, "ok" if ok else "timeout",
				stats.x, int(stats.y), int(stats.z), int(st["multimesh_nodes"]), ", ".join(inst)])
		p.note("  build ms avg %.1f max %.1f, main us max %d, step max %d (%s), scan max %d, update max %d (%s)" % [st["build_ms_avg"],
				st["build_ms_max"], st["main_usec_max"], st["step_usec_max"], st["step_max_info"], st["scan_usec_max"],
				st["update_usec_max"], st["update_max_info"]])
		await p.screenshot("worldcontent_biome_%s" % v)
		if OS.get_cmdline_user_args().has("--breakdown"):
			await _breakdown(p, content)


## Frame cost with each provider hidden in turn (which layer costs what).
func _breakdown(p: Playtest, content: WorldContent) -> void:
	for id: StringName in [&"groundcover", &"vegetation", &"forest_far", &"landmarks", &"poi_structures", &"road_dressing"]:
		var hidden: Array[Node3D] = []
		for c in content.get_cells(id):
			if c.root and c.root.visible:
				c.root.visible = false
				hidden.append(c.root)
		await p.frames(3)
		var s := await _measure(p, 6)
		p.note("  without %s: %.0f ms, %d draw calls, %d prims" % [id, s.x, int(s.y), int(s.z)])
		for n in hidden:
			n.visible = true
	for c in _all_cells(content):
		if c.root:
			c.root.visible = false
	await p.frames(3)
	var s0 := await _measure(p, 6)
	p.note("  without content: %.0f ms, %d draw calls, %d prims" % [s0.x, int(s0.y), int(s0.z)])
	for c in _all_cells(content):
		if c.root:
			c.root.visible = true


func _all_cells(content: WorldContent) -> Array[ContentCell]:
	var out: Array[ContentCell] = []
	for p in content.get_providers():
		out.append_array(content.get_cells(p.id))
	return out


## Ground views: step the camera back while a trunk/boulder collider is right in front of it.
func _clear_view(p: Playtest, scene: Node) -> void:
	var cam: Camera3D = scene.cam
	await p.wait_game(0.1)
	var space := cam.get_world_3d().direct_space_state
	for k in 6:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 3.6
		q.shape = sh
		q.transform = Transform3D(Basis(), cam.global_position - cam.global_basis.z * 2.0)
		if space.intersect_shape(q, 1).is_empty():
			return
		var back := cam.global_basis.z
		back.y = 0.0
		cam.global_position += back.normalized() * 4.0
		cam.global_position.y = WorldData.get_height(cam.global_position.x, cam.global_position.z) + 2.0
		await p.wait_game(0.1)


func _measure(p: Playtest, n: int) -> Vector3:
	var t := Time.get_ticks_usec()
	await p.frames(n)
	var ms := (Time.get_ticks_usec() - t) / 1000.0 / n
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	return Vector3(ms, dc, prims)
