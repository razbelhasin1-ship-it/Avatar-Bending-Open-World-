extends RefCounted
## World renderer tour: every nation's signature view through the real WorldRenderer
## (clipmap terrain, water, sky, regional atmosphere, weather). Pass `--views=a,b` to limit.
## Also measures frame time and draw calls per view.

const SHOTS := ["water_tribe", "water_tribe_blizzard", "water_tribe_night", "ba_sing_se", "fire_nation",
		"fire_volcano", "air_temple", "shore", "vista"]


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
	if only.is_empty() or only.split(",").has("canal"):
		await _canal(p, scene, world)
	if only.is_empty() or only.split(",").has("splash"):
		await _splash(p, scene, world)


## Close view along the Water Tribe's ring canal (middle tier, level 14.2 m).
func _canal(p: Playtest, scene: Node, world: WorldRenderer) -> void:
	var ring: Dictionary = {}
	for c in WorldData.get_canals():
		if c["id"] == &"nwt_canal_ring":
			ring = c
	if not p.check(not ring.is_empty(), "ring canal record"):
		return
	var pts: PackedVector2Array = ring["points"]
	var a := pts[pts.size() / 2 + 3]
	var b := pts[pts.size() / 2 + 7]
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var level := float(ring["level"])
	var cam := a - dir * 6.0 + side * 9.0
	scene.place_camera(Vector3(cam.x, level + 6.5, cam.y), Vector3(b.x, level, b.y), 66.0)
	world.set_time_of_day(11.0)
	world.set_weather(&"clear", 0.0)
	await p.wait(1.5)
	p.check(WorldData.get_water_height(a.x, a.y) > 10.0, "canal water level from WorldData")
	await p.screenshot("worldrender_canal")


## Bending splashes on the ocean: ripple rings, foam and spray.
func _splash(p: Playtest, scene: Node, world: WorldRenderer) -> void:
	scene.set_view("shore")
	world.set_weather(&"clear", 0.0)
	await p.wait(0.8)
	var cam: Camera3D = scene.cam
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ok := 0
	for k in 3:
		var pt := cam.global_position + fwd * (14.0 + k * 7.0) + cam.global_basis.x * (k - 1) * 5.0
		if world.splash(Vector3(pt.x, 0.0, pt.z), 1.2 + k * 0.6):
			ok += 1
		await p.wait(0.25)
	p.check(ok >= 2, "splashes landed on water (%d/3)" % ok)
	await p.wait(0.5)
	await p.screenshot("worldrender_splash")


## Average frame time (ms), draw calls and primitives over n frames.
func _measure(p: Playtest, n: int) -> Vector3:
	var t := Time.get_ticks_usec()
	await p.frames(n)
	var ms := (Time.get_ticks_usec() - t) / 1000.0 / n
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	return Vector3(ms, dc, prims)
