extends RefCounted
## Mobile performance pass (docs/modules/mobile.md "Performance"): measures the phone preset
## in the real world scene (home region spawn, four view directions) and in a fight in the
## combat arena, and writes a census of what is drawn (instances, triangles, skinned rigs,
## particles, lights) ranked by owning module. Report: <out>/perf_<renderer>.json + log.
## Run: MOBILE=1 RENDERER=mobile tools/playtest.sh mobile_perf .playtest/mobile_perf 1280x720
##      MOBILE=1 RENDERER=gl_compatibility tools/playtest.sh mobile_perf ...
## ELEMENT=water|earth|fire|air picks the home region (default water: snow city, heaviest).
## PRESET=low|medium|high overrides the preset (before/after comparisons); SHADOWS=0..4
## overrides the shadow level; SKIP_WORLD=1 / SKIP_ARENA=1 measure one scene only.

var p: Playtest
var report := {}


func run(pt: Playtest) -> void:
	p = pt
	var preset := OS.get_environment("PRESET")
	if preset == "":
		preset = "mobile"
	Settings.apply_preset(preset)
	if preset == "mobile":
		Settings.set_value("display", "render_scale", 0.75)
		Settings.set_value("display", "upscaler", "fsr1")
	if OS.get_environment("SHADOWS") != "":
		Settings.set_value("graphics", "shadows", int(OS.get_environment("SHADOWS")))
	Settings.apply()
	report["renderer"] = Settings.rendering_method()
	report["preset"] = preset
	report["touch"] = Settings.touch_controls_enabled()
	report["platform"] = PlatformInfo.describe()
	p.note("preset %s, renderer %s, touch %s" % [preset, report["renderer"], str(report["touch"])])
	var e := ElementDefs.Element.WATER
	if OS.get_environment("ELEMENT") != "":
		e = ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	if OS.get_environment("SKIP_WORLD") == "":
		await _world(e)
	if OS.get_environment("SKIP_ARENA") == "":
		await _arena(e)
	var path := p.out_dir.path_join("perf_%s_%s.json" % [report["renderer"], preset])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
	p.note("report written to %s" % path)


func _world(e: int) -> void:
	GameState.new_game(e)
	var w := await p.load_scene("res://scenes/world/world.tscn", {"element": e, "new_game": true, "skip_intro": true}) as PlayableScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready, 240.0)
	p.check(ok, "world scene ready")
	await p.wait_game(4.0)
	var pl := p.player() as PlayerCharacter
	if pl == null:
		return
	var cam := pl.camera_rig
	var dirs: Array = []
	for i in 4:
		cam.set_yaw(pl.camera_rig.get_yaw() + PI * 0.5 if i > 0 else cam.get_yaw())
		await p.wait_game(1.2)
		var s: Dictionary = await PerfProbe.sample(p.get_tree(), p.get_viewport(), 3.0)
		s["yaw_deg"] = rad_to_deg(cam.get_yaw())
		dirs.append(s)
		p.note("world view %d: %s" % [i, PerfProbe.describe(s)])
		await p.screenshot("perf_world_%s_%d" % [report["renderer"], i])
		if i == 0:
			var c := PerfProbe.census(p.get_tree().current_scene, cam.get_camera(), Settings.view_distance_m())
			report["world_census"] = _trim_census(c)
			p.note("world census: %d instances, %dk tris, %d multimesh instances, %d skinned, %d particle systems (%d particles), %d lights (%d shadowed)" % [
					c["instances"], int(c["triangles"]) / 1000, c["multimesh_instances"], c["skinned"], c["particles"], c["particle_amount"], c["lights"], c["shadow_lights"]])
			for row: Dictionary in (c["by_owner"] as Array).slice(0, 12):
				p.note("   %-48s inst %5d  tris %7dk  skinned %d  particles %d  lights %d" % [row["owner"], row["instances"], int(row["triangles"]) / 1000, row["skinned"], row["particles"], row["lights"]])
	report["world"] = dirs
	cam.set_yaw(float(dirs[0]["yaw_deg"]) * PI / 180.0)
	await p.wait_game(1.0)
	report["world_breakdown"] = await _breakdown(w)
	# Run through the region for a few seconds (streaming while moving).
	pl.camera_rig.snap_behind(pl)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var run_s: Dictionary = await PerfProbe.sample(p.get_tree(), p.get_viewport(), 5.0)
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	p.note("world sprinting: %s" % PerfProbe.describe(run_s))
	report["world_run"] = run_s
	await p.screenshot("perf_world_%s_run" % report["renderer"])


## What each part of the world costs: hides one group at a time and measures the drop in
## draw calls / primitives (visible + shadow pass) on the same static view.
func _breakdown(w: Node) -> Array:
	var groups: Dictionary = {}
	var renderer := w.get("renderer") as WorldRenderer
	if renderer:
		groups["terrain"] = [renderer.clipmap]
		groups["water"] = [renderer.water]
		groups["weather/sky fx"] = [renderer.precipitation, renderer.cloud_sea, renderer.volcano_smoke]
	var content := w.get("content") as Node
	if content:
		for c in content.get_children():
			var parts := String(c.name).split("_")
			if parts.size() < 3:
				continue
			var key := "content/" + "_".join(parts.slice(0, parts.size() - 2))
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(c)
	var pl := p.player()
	if pl:
		groups["player"] = [pl]
	var comp := w.get("companion_root") as Node
	if comp:
		groups["companion"] = [comp]
	var base := await _frame_snapshot()
	var out: Array = []
	for key: String in groups:
		var nodes: Array = []
		for n: Variant in groups[key]:
			if n is Node3D and (n as Node3D).visible:
				nodes.append(n)
		if nodes.is_empty():
			continue
		for n: Node3D in nodes:
			n.visible = false
		var s := await _frame_snapshot()
		for n: Node3D in nodes:
			n.visible = true
		var row := {"group": key, "nodes": nodes.size(),
				"draw_calls": int(base["draw_calls"]) - int(s["draw_calls"]),
				"shadow_draw_calls": int(base["shadow_draw_calls"]) - int(s["shadow_draw_calls"]),
				"primitives": int(base["primitives"]) - int(s["primitives"]),
				"shadow_primitives": int(base["shadow_primitives"]) - int(s["shadow_primitives"])}
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["primitives"]) + int(a["shadow_primitives"]) > int(b["primitives"]) + int(b["shadow_primitives"]))
	p.note("world breakdown (total %d draws +%d shadow, %dk prims +%dk shadow):" % [base["draw_calls"], base["shadow_draw_calls"],
			int(base["primitives"]) / 1000, int(base["shadow_primitives"]) / 1000])
	for r: Dictionary in out:
		p.note("   %-34s draws %4d +%3d shadow   prims %6dk +%6dk shadow" % [r["group"], r["draw_calls"], r["shadow_draw_calls"],
				int(r["primitives"]) / 1000, int(r["shadow_primitives"]) / 1000])
	return out


func _frame_snapshot() -> Dictionary:
	for i in 3:
		await RenderingServer.frame_post_draw
	return PerfProbe.frame_stats(p.get_viewport())


func _arena(e: int) -> void:
	var arena := await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e})
	await p.wait_game(1.0)
	var pl := p.player() as PlayerCharacter
	var bot := arena.get("bot") as Node
	if bot:
		bot.set("active", true)
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -3.0)))
	await p.wait_game(0.4)
	pl.camera_rig.snap_behind(pl)
	var idle: Dictionary = await PerfProbe.sample(p.get_tree(), p.get_viewport(), 2.0)
	p.note("arena idle: %s" % PerfProbe.describe(idle))
	# Fight: combo + heavy + technique while sampling.
	var fighting := true
	var spam := func() -> void:
		var k := 0
		while fighting:
			var a: StringName = [&"attack_light", &"attack_light", &"attack_light", &"attack_heavy", &"ability_1", &"ability_2"][k % 6]
			Input.action_press(a)
			await p.wait_game(0.08)
			Input.action_release(a)
			await p.wait_game(0.3)
			pl.resources.set_chi(PlayerResources.CHI_MAX)
			k += 1
	spam.call()
	var fight: Dictionary = await PerfProbe.sample(p.get_tree(), p.get_viewport(), 5.0)
	p.note("arena fight (first casts, shaders compiling): %s" % PerfProbe.describe(fight))
	var warm: Dictionary = await PerfProbe.sample(p.get_tree(), p.get_viewport(), 5.0)
	fighting = false
	await p.wait_game(0.5)
	p.note("arena fight (warm): %s" % PerfProbe.describe(warm))
	await p.screenshot("perf_arena_%s" % report["renderer"])
	var c := PerfProbe.census(p.get_tree().current_scene, pl.camera_rig.get_camera())
	report["arena"] = {"idle": idle, "fight": fight, "fight_warm": warm, "census": _trim_census(c)}
	p.note("arena census: %d instances, %dk tris, %d skinned, %d particle systems (%d particles), %d lights" % [
			c["instances"], int(c["triangles"]) / 1000, c["skinned"], c["particles"], c["particle_amount"], c["lights"]])


func _trim_census(c: Dictionary) -> Dictionary:
	var out := c.duplicate()
	out["by_owner"] = (c["by_owner"] as Array).slice(0, 20)
	return out
