extends RefCounted
## Render budget at the four home spawns (perf_polish, docs/qa/perf_polish.md): for every
## element a new game in the real world scene (skip intro), the camera turned to four view
## directions, each sampled for 2 s (draw calls, primitives, shadow pass, frame time) with a
## frustum-culled census of what is drawn grouped by provider / LOD (RenderCensus).
## Report: <out>/budget_<renderer>_<preset>.json + screenshots of view 0 and the worst view.
##
## Run: MOBILE=1 RENDERER=mobile tools/playtest.sh perf_polish_budget .playtest/budget 1280x720
##      MOBILE=1 RENDERER=gl_compatibility tools/playtest.sh perf_polish_budget ...
##      PRESET=high tools/playtest.sh perf_polish_budget ...          (desktop look check)
## ELEMENTS=water,earth picks the spawns (default all four); HOUR=13 sets the time of day;
## BUDGET_PRIMS / BUDGET_DRAWS turn the mobile budget into checks (default 250000 / 200 for
## the mobile preset on the Mobile renderer, report-only elsewhere).

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
	Settings.apply()
	var renderer := Settings.rendering_method()
	report["renderer"] = renderer
	report["preset"] = preset
	report["platform"] = PlatformInfo.describe()
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else -1.0
	var ids := ["water", "earth", "fire", "air"]
	if OS.get_environment("ELEMENTS") != "":
		ids = OS.get_environment("ELEMENTS").split(",")
	var check_budget := preset == "mobile" and renderer == "mobile"
	var max_prims := int(OS.get_environment("BUDGET_PRIMS")) if OS.get_environment("BUDGET_PRIMS") != "" else 250000
	var max_draws := int(OS.get_environment("BUDGET_DRAWS")) if OS.get_environment("BUDGET_DRAWS") != "" else 200
	p.note("preset %s, renderer %s, elements %s" % [preset, renderer, str(ids)])
	var spawns := {}
	for id: String in ids:
		var e := ElementDefs.from_id(StringName(id))
		var res: Dictionary = await _spawn(e, hour)
		spawns[id] = res
		if res.is_empty():
			continue
		var worst: Dictionary = res["worst"]
		p.note("%s spawn worst view: %d draws (+%d shadow), %dk prims (+%dk shadow), frame %.0f ms" % [id, worst["draw_calls"],
				worst["shadow_draw_calls"], int(worst["primitives"]) / 1000, int(worst["shadow_primitives"]) / 1000, worst["frame_ms_avg"]])
		if check_budget:
			p.check(int(worst["primitives"]) < max_prims, "%s spawn: worst view %dk visible primitives < %dk (mobile budget)" % [id,
					int(worst["primitives"]) / 1000, max_prims / 1000])
			p.check(int(worst["draw_calls"]) < max_draws, "%s spawn: worst view %d draw calls < %d (mobile budget)" % [id,
					worst["draw_calls"], max_draws])
	report["spawns"] = spawns
	var path := p.out_dir.path_join("budget_%s_%s.json" % [renderer, preset])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
	p.note("report written to %s" % path)


func _spawn(e: int, hour: float) -> Dictionary:
	GameState.new_game(e)
	var params := {"element": e, "new_game": true, "skip_intro": true}
	if hour >= 0.0:
		params["time_of_day"] = hour
	var w := await p.load_scene("res://scenes/world/world.tscn", params) as PlayableScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready, 300.0)
	p.check(ok, "%s world ready" % ElementDefs.id_of(e))
	if not ok:
		return {}
	await p.wait_game(3.0)
	# Measure the streamed-in world, not a half-loaded one: the loading hold gives up after 25 s
	# (software rendering, shared cores) and the far providers load last.
	var settled := true
	if w.content != null:
		settled = await w.content.wait_until_settled(180.0)
	p.check(settled, "%s content settled before sampling" % ElementDefs.id_of(e))
	await p.wait_game(2.0)
	var pl := p.player() as PlayerCharacter
	if pl == null:
		return {}
	var cam := pl.camera_rig
	var yaw0 := cam.get_yaw()
	var views: Array = []
	var worst := {}
	var worst_i := 0
	for i in 4:
		cam.set_yaw(yaw0 + PI * 0.5 * i)
		await p.wait_game(1.0)
		var s: Dictionary = await PerfProbe.sample(p.get_tree(), p.get_viewport(), 2.0)
		var c := RenderCensus.take(p.get_tree().current_scene, cam.get_camera())
		s["census"] = c
		s["yaw_deg"] = rad_to_deg(cam.get_yaw())
		views.append(s)
		p.note("%s view %d: %s" % [ElementDefs.id_of(e), i, PerfProbe.describe(s)])
		for g: Dictionary in (c["groups"] as Array).slice(0, 8):
			p.note("     %-56s inst %4d  draws %4d  tris %7dk" % [g["group"], g["instances"], g["draws"], int(g["triangles"]) / 1000])
		if worst.is_empty() or int(s["primitives"]) > int(worst["primitives"]):
			worst = s
			worst_i = i
		if i == 0:
			await p.screenshot("budget_%s_%s_%s_view0" % [ElementDefs.id_of(e), report["renderer"], report["preset"]])
	cam.set_yaw(yaw0 + PI * 0.5 * worst_i)
	await p.wait_game(0.6)
	await p.screenshot("budget_%s_%s_%s_worst" % [ElementDefs.id_of(e), report["renderer"], report["preset"]])
	var breakdown: Array = []
	if OS.get_environment("BREAKDOWN") != "":
		breakdown = await _breakdown(w)
	cam.set_yaw(yaw0)
	return {"views": views, "worst": _strip(worst), "worst_view": worst_i, "load_report": w.load_report, "breakdown": breakdown}


## Renderer-measured cost of each part of the view (BREAKDOWN=1): hides one group at a time
## (terrain, water, each content provider, NPCs, player, companion) and records the drop in draw
## calls / primitives. Unlike the census this includes mesh LOD selection.
func _breakdown(w: PlayableScene) -> Array:
	var groups := {}
	if w.renderer:
		groups["terrain"] = [w.renderer.clipmap]
		groups["water"] = [w.renderer.water]
	if w.content:
		for c in w.content.get_children():
			var parts := String(c.name).split("_")
			if parts.size() < 3:
				continue
			var key := "_".join(parts.slice(0, parts.size() - 2))
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(c)
	groups["npcs"] = p.get_tree().get_nodes_in_group(&"npc")
	groups["player"] = [p.player()]
	groups["companion"] = [w.companion_root]
	var base := await _snapshot()
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
		var s := await _snapshot()
		for n: Node3D in nodes:
			n.visible = true
		var row := {"group": key, "draw_calls": int(base["draw_calls"]) - int(s["draw_calls"]),
				"primitives": int(base["primitives"]) - int(s["primitives"]),
				"shadow_primitives": int(base["shadow_primitives"]) - int(s["shadow_primitives"])}
		if int(row["draw_calls"]) != 0 or int(row["primitives"]) != 0:
			out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["primitives"]) > int(b["primitives"]))
	p.note("   breakdown (renderer, total %d draws, %dk prims):" % [base["draw_calls"], int(base["primitives"]) / 1000])
	for r: Dictionary in out:
		p.note("     %-40s draws %4d   prims %6dk   shadow %5dk" % [r["group"], r["draw_calls"], int(r["primitives"]) / 1000,
				int(r["shadow_primitives"]) / 1000])
	return out


func _snapshot() -> Dictionary:
	for i in 3:
		await RenderingServer.frame_post_draw
	return PerfProbe.frame_stats(p.get_viewport())


func _strip(s: Dictionary) -> Dictionary:
	var out := s.duplicate()
	out.erase("census")
	return out
