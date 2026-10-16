extends RefCounted
## Fast fly-over measuring the content system while it streams: the camera moves a fixed distance
## per *frame* (`--step=` metres, default 2 m = 120 m/s at 60 fps, faster than a diving glider or
## a sprinting sky bison), so the per-frame main-thread budget is tested independently of how
## slow the software renderer is. Per leg it reports the content main-thread time per frame
## (instantiation steps, scans, releases: max / p95 / avg), the frame time, draw calls,
## primitives, loaded cells and instances, and how far streaming lags behind (queued cells).
## `--preset=mobile|low|medium|high|ultra` applies a graphics preset first (default: high, or
## mobile with --mobile). PASS: content main-thread time stays bounded every frame.

## Legs: [name, from, to, metres above ground]
const LEGS := [
	["ek_forest_low", Vector3(1700, 0, -700), Vector3(2300, 0, -1300), 35.0],
	["ek_farms_to_mountains", Vector3(1650, 0, -250), Vector3(2350, 0, -900), 120.0],
	["fn_jungle_volcano", Vector3(-3500, 0, 1050), Vector3(-3300, 0, 1800), 60.0],
	["wt_coast", Vector3(-1400, 0, -2700), Vector3(-700, 0, -3150), 50.0],
]


func run(p: Playtest) -> void:
	var step := 2.0
	var preset := "mobile" if OS.get_cmdline_user_args().has("--mobile") else "high"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.substr(7))
		elif a.begins_with("--preset="):
			preset = a.substr(9)
		elif a.begins_with("--legs="):
			only = a.substr(7)
	Settings.apply_preset(preset)
	Settings.apply()
	var scene := await p.load_scene("res://scenes/dev/worldcontent_world.tscn")
	p.check(scene != null and WorldData.has_world_data(), "dev scene + world data loaded")
	if scene == null:
		return
	var content: WorldContent = scene.content
	var world: WorldRenderer = scene.world
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	await p.wait_until(func() -> bool: return VegetationLibrary.is_ready(), 30.0)
	p.note("preset %s, renderer %s, step %.1f m/frame (= %.0f m/s at 60 fps), frame budget %d us, jobs %d" % [preset,
			RenderingServer.get_current_rendering_method(), step, step * 60.0, content.frame_budget_usec, content.max_jobs])
	var all := PackedInt32Array()
	for leg: Array in LEGS:
		if not only.is_empty() and not only.split(",").has(leg[0]):
			continue
		all.append_array(await _leg(p, scene, content, leg, step))
	var budget := content.frame_budget_usec
	all.sort()
	if all.is_empty():
		return
	var p99 := all[int(all.size() * 0.99)]
	var hitches := 0
	for us in all:
		if us > budget + 6000:
			hitches += 1
	# one time-sliced step may overrun the budget; the OS may preempt the main thread on this
	# shared machine now and then, so single outliers are tolerated, systematic ones are not
	p.check(p99 <= budget + 3000, "content main-thread time p99 %d us (budget %d us)" % [p99, budget])
	p.check(hitches <= maxi(2, all.size() / 200), "content frames over budget + 6 ms: %d of %d (worst %d us)" % [hitches, all.size(), all[all.size() - 1]])


func _leg(p: Playtest, scene: Node, content: WorldContent, leg: Array, step: float) -> PackedInt32Array:
	var a: Vector3 = leg[1]
	var b: Vector3 = leg[2]
	var agl: float = leg[3]
	var dir := (b - a).normalized()
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var pos := _at(a, agl)
	scene.place_camera(pos, pos + dir * 100.0 - Vector3(0, agl * 0.6, 0), 66.0)
	scene.world.set_time_of_day(11.0)
	content.load_now(pos)
	await p.frames(3)
	content.reset_stats()
	var mains := PackedInt32Array()
	var frame_ms := PackedFloat32Array()
	var max_dc := 0
	var max_prims := 0
	var max_queue := 0
	var max_inst := 0
	var t_prev := Time.get_ticks_usec()
	var travelled := 0.0
	var shot := false
	while travelled < length:
		travelled += step
		var q := _at(a + dir * travelled, agl)
		# smooth the height so the camera glides instead of following every bump
		pos = Vector3(q.x, lerpf(pos.y, q.y, 0.08), q.z)
		scene.cam.global_position = pos
		scene.cam.look_at(pos + dir * 100.0 - Vector3(0, agl * 0.6, 0), Vector3.UP)
		await p.frames(1)
		var now := Time.get_ticks_usec()
		frame_ms.append((now - t_prev) / 1000.0)
		t_prev = now
		var st := content.get_stats()
		mains.append(int(st["main_usec_last"]))
		max_queue = maxi(max_queue, int(st["queue"]) + int(st["built_waiting"]))
		max_inst = maxi(max_inst, int(st["instances"]))
		max_dc = maxi(max_dc, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		max_prims = maxi(max_prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		if not shot and travelled > length * 0.5:
			shot = true
			await p.screenshot("worldcontent_flyover_%s" % leg[0])
	var st2 := content.get_stats()
	var sorted := mains.duplicate()
	sorted.sort()
	var fs := frame_ms.duplicate()
	fs.sort()
	var avg := 0.0
	for m in mains:
		avg += m
	avg /= maxf(mains.size(), 1.0)
	var per := []
	for id: StringName in st2["providers"]:
		var s: Dictionary = st2["providers"][id]
		per.append("%s %d" % [id, s["active"]])
	p.note("%s: %d frames over %.0f m at %.0f m agl" % [leg[0], mains.size(), length, agl])
	var over := 0
	for m in mains:
		if m > content.frame_budget_usec + 2000:
			over += 1
	p.note("  content main thread us/frame: max %d, p99 %d, p95 %d, avg %.0f, frames > budget+2ms: %d (step max %d %s, scan max %d, update max %d %s)" % [
			sorted[sorted.size() - 1], sorted[int(sorted.size() * 0.99)], sorted[int(sorted.size() * 0.95)], avg, over,
			st2["step_usec_max"], st2["step_max_info"], st2["scan_usec_max"], st2["update_usec_max"], st2["update_max_info"]])
	p.note("  frame ms: median %.0f, p95 %.0f, max %.0f | draw calls max %d, primitives max %d" % [fs[fs.size() / 2],
			fs[int(fs.size() * 0.95)], fs[fs.size() - 1], max_dc, max_prims])
	p.note("  instances max %d, cells built %d released %d, max backlog %d cells, build ms avg %.1f max %.1f | active %s" % [
			max_inst, st2["cells_built"], st2["cells_released"], max_queue, st2["build_ms_avg"], st2["build_ms_max"], ", ".join(per)])
	return mains


static func _at(p: Vector3, agl: float) -> Vector3:
	return Vector3(p.x, maxf(WorldData.get_height(p.x, p.z), 0.0) + agl, p.z)
