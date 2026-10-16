extends RefCounted
## Settlements II screenshot tour over the views of the settlements_ef dev scene (EF_VIEWS, and
## settlements_wa's VIEWS by name).
##   VIEWS=bss_far,bss_gate tools/playtest.sh settlements_ef_tour out 960x540   (default: all EF views)
##   PRESET=mobile|low|medium|high|ultra (default high)   HOUR=22 overrides every view's hour


func run(p: Playtest) -> void:
	var views: Array = []
	var preset := OS.get_environment("PRESET") if OS.get_environment("PRESET") != "" else "high"
	if OS.get_environment("VIEWS") != "":
		views = Array(OS.get_environment("VIEWS").split(","))
	Settings.apply_preset(preset)
	Settings.apply()
	var scene := await p.load_scene("res://scenes/dev/settlements_ef.tscn", {"view": "bss_far"})
	p.check(scene != null and WorldData.has_world_data(), "dev scene + world data loaded")
	if scene == null:
		return
	var content: WorldContent = scene.content
	var world: WorldRenderer = scene.world
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	await p.wait_until(func() -> bool: return VegetationLibrary.is_ready(), 30.0)
	if views.is_empty():
		views = scene.EF_VIEWS.keys()
	for v: String in views:
		if not scene.has_view(v):
			p.note("unknown view %s" % v)
			continue
		scene.set_view(v)
		if OS.get_environment("HOUR") != "":
			world.set_time_of_day(float(OS.get_environment("HOUR")))
		var t0 := Time.get_ticks_msec()
		content.load_now(scene.cam.global_position)
		p.note("view %s loaded in %d ms" % [v, Time.get_ticks_msec() - t0])
		await p.frames(8)
		await p.screenshot("settlements_ef_%s" % v)
	for pr in content.get_providers():
		if pr is SettlementProvider:
			p.note("%s %s" % [pr.id, (pr as SettlementProvider).stats])
