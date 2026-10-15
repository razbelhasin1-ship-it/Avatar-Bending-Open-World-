extends RefCounted
## Renders the baked world (scenes/dev/world_overview.tscn): top-down map view, a wide oblique,
## and close views of every nation with 2 m GPU-displaced detail patches.
## Markers (POIs gold, gates red, spawns blue) use CPU heights and must sit on the GPU terrain.

const SHOTS := ["top", "world_south", "water_tribe", "ba_sing_se", "omashu", "fire_nation", "air_temple", "air_temple_close"]


func run(p: Playtest) -> void:
	var t0 := Time.get_ticks_msec()
	var scene := await p.load_scene("res://scenes/dev/world_overview.tscn")
	p.note("scene ready in %d ms (world load %.2f s)" % [Time.get_ticks_msec() - t0, WorldData.load_time_sec])
	p.check(WorldData.has_world_data(), "baked world data loaded")
	if scene == null or not WorldData.has_world_data():
		return
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			only = a.substr(8)
	for v: String in SHOTS:
		if not only.is_empty() and not only.split(",").has(v):
			continue
		scene.set_view(v)
		await p.frames(4)
		await p.wait(0.6)
		await p.screenshot("worlddata_%s" % v)
	p.check(scene.get_node_or_null("WorldMesh") != null, "world mesh built")
	p.check(WorldData.get_height_texture() != null, "height texture available for shaders")
