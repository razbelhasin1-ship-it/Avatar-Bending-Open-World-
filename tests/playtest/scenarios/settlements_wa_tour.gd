extends RefCounted
## Settlement screenshot tour: --views=a,b,c (names of SettlementsDev.VIEWS; default all).


func run(p: Playtest) -> void:
	var views: Array = []
	var preset := "high"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			views = a.substr(8).split(",")
		elif a.begins_with("--preset="):
			preset = a.substr(9)
	Settings.apply_preset(preset)
	Settings.apply()
	var scene := await p.load_scene("res://scenes/dev/settlements_wa.tscn")
	p.check(scene != null and WorldData.has_world_data(), "dev scene + world data loaded")
	if scene == null:
		return
	var content: WorldContent = scene.content
	var world: WorldRenderer = scene.world
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	await p.wait_until(func() -> bool: return VegetationLibrary.is_ready(), 30.0)
	if views.is_empty():
		views = scene.VIEWS.keys()
	for v: String in views:
		scene.set_view(v)
		var t0 := Time.get_ticks_msec()
		content.load_now(scene.cam.global_position)
		p.note("view %s loaded in %d ms" % [v, Time.get_ticks_msec() - t0])
		await p.frames(8)
		await p.screenshot("settlements_wa_%s" % v)
	for pr in content.get_providers():
		if pr is SettlementProvider:
			p.note("%s %s" % [pr.id, (pr as SettlementProvider).stats])
