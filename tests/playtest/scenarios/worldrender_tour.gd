extends RefCounted
## World renderer tour: every nation's signature view through the real WorldRenderer
## (clipmap terrain, water, sky, regional atmosphere, weather). Pass `--views=a,b` to limit.
## Also measures frame time and draw calls per view.

const SHOTS := ["water_tribe", "water_tribe_blizzard", "water_tribe_night", "ba_sing_se", "fire_nation",
		"air_temple", "shore", "vista"]


func run(p: Playtest) -> void:
	var t0 := Time.get_ticks_msec()
	var scene := await p.load_scene("res://scenes/dev/world_render_test.tscn")
	p.check(scene != null and WorldData.has_world_data(), "dev scene + world data loaded")
	if scene == null:
		return
	var world: WorldRenderer = scene.world
	p.note("scene ready in %d ms" % (Time.get_ticks_msec() - t0))
	# let the normal map bake and shaders compile
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	p.check(world.normal_baker.texture != null, "terrain normal map baked (%.2f s)" % world.normal_baker.bake_time_sec)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			only = a.substr(8)
	for v: String in SHOTS:
		if not only.is_empty() and not only.split(",").has(v):
			continue
		scene.set_view(v)
		var view: Dictionary = scene.VIEWS[v]
		if world.has_method(&"set_weather"):
			world.call(&"set_weather", view.get("weather", &"clear"), 0.0)
		await p.frames(3)
		await p.wait(1.5)
		var stats := await _measure(p, 20)
		p.note("%s: %.1f ms/frame, %d draw calls, %d primitives" % [v, stats.x, int(stats.y), int(stats.z)])
		await p.screenshot("worldrender_%s" % v)


## Average frame time (ms), draw calls and primitives over n frames.
func _measure(p: Playtest, n: int) -> Vector3:
	var t := Time.get_ticks_usec()
	await p.frames(n)
	var ms := (Time.get_ticks_usec() - t) / 1000.0 / n
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	return Vector3(ms, dc, prims)
