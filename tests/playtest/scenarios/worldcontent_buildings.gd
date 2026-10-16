extends RefCounted
## Building kit showcase: the four nation demo buildings by day and by night (lanterns,
## braziers, budgeted lights), close-ups and an interior. Reports triangles, draw calls and build
## time per building. `--views=a,b` limits the set.

const VIEWS := ["overview_day", "water_tribe", "earth_kingdom", "fire_nation", "air_nomads", "interior", "overview_night",
		"earth_kingdom_night", "fire_nation_night"]


func run(p: Playtest) -> void:
	var scene := await p.load_scene("res://scenes/dev/worldcontent_buildings.tscn")
	p.check(scene != null, "buildings scene loaded")
	if scene == null:
		return
	var world: WorldRenderer = scene.world
	# --gfx=key:value,... overrides graphics settings (renderer diagnostics)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gfx="):
			for kv in a.substr(6).split(","):
				var parts := kv.split(":")
				Settings.set_value("graphics", parts[0], str_to_var(parts[1]))
			Settings.apply_graphics()
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	for n: StringName in scene.buildings:
		var b: Dictionary = scene.buildings[n]
		var res: KitResult = b["result"]
		p.note("%s: %d tris, %d surfaces, %d boxes, %d faces, %d lights, built in %.1f ms" % [n, res.triangle_count, res.surfaces.size(),
				res.boxes.size(), res.faces.size() / 3, res.lights.size(), b["build_ms"]])
		p.check(res.triangle_count > 500, "%s has geometry" % n)
		p.check(res.markers.has(&"door"), "%s has a door marker" % n)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			only = a.substr(8)
	for v: String in VIEWS:
		if not only.is_empty() and not only.split(",").has(v):
			continue
		var night := v.ends_with("night")
		world.set_time_of_day(21.8 if night else 15.5)
		match v:
			"overview_day", "overview_night":
				scene.look_at_overview()
			"interior":
				world.set_time_of_day(19.5)
				scene.look_inside(&"earth_kingdom")
			_:
				scene.look_at_building(StringName(v.trim_suffix("_night")), 24.0, 5.0)
		await scene.content.wait_until_settled(20.0)
		await p.frames(3)
		await p.wait(1.2)
		var t := Time.get_ticks_usec()
		await p.frames(8)
		var ms := (Time.get_ticks_usec() - t) / 8000.0
		p.note("%s: %.0f ms/frame, %d draw calls, lights on %d/%d" % [v, ms,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), LightBudget.active_count(), LightBudget.light_count()])
		if night:
			p.check(LightBudget.active_count() > 0, "%s: kit lights enabled at night" % v)
		await p.screenshot("worldcontent_buildings_%s" % v)
