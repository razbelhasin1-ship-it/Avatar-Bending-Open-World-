extends RefCounted
## Pose contact sheets for reviewing clips frozen at a normalized time.
## SHEET="clip@t,preset:clip@t+prop/socket;clip,clip" (";" separates images)
## PRESET=fire_nation (default preset; "<preset>_f" = female) VIEW=front|side|34|back|back34
## CLOSE=1 frames the upper body. Without SHEET a default review set is used.
func run(p: Playtest) -> void:
	var show: CharacterShowcase = await p.load_scene("res://scenes/dev/character_showcase.tscn")
	var sheet_env := OS.get_environment("SHEET")
	if sheet_env == "":
		sheet_env = "villager_earth:work_hammer@0.35+hammer/hand_r,villager_fire:sweep@0.2+broom/hand_r,villager_water:fish@0.1+fishing_rod/hand_r,villager_earth_f:carry@0.2+basket/hand_r;air_nomad:idle_air@0.2,guard:idle_soldier@0.2,merchant:talk_1@0.3,villager_air_f:wave_r@0.35;monk_elder:meditate_loop@0.2,villager_fire:sit_loop@0.2,water_tribe:kneel@0.9,earth_soldier:bow@0.6"
	var sheets := sheet_env.split(";", false)
	var preset := OS.get_environment("PRESET")
	if preset == "":
		preset = "fire_nation"
	var view := OS.get_environment("VIEW")
	var labels: Array[Node] = []
	var si := 0
	for sheet in sheets:
		show.clear_rigs()
		for l in labels:
			l.queue_free()
		labels.clear()
		await p.frames(1)
		var items := sheet.split(",", false)
		var n := items.size()
		var spacing := 1.5
		var i := 0
		for it: String in items:
			var pre := preset
			var prop_spec := ""
			if it.contains("+"):
				prop_spec = it.get_slice("+", 1)
				it = it.get_slice("+", 0)
			if it.contains(":"):
				pre = it.get_slice(":", 0)
				it = it.get_slice(":", 1)
			var parts := it.split("@")
			var clip := StringName(parts[0])
			var t := float(parts[1]) if parts.size() > 1 else -1.0
			var pos := Vector3((float(i) - (n - 1) * 0.5) * spacing, 0, 0)
			var yaw: float = {"side": 90.0, "34": 30.0, "back": 180.0, "back34": 145.0}.get(view, 0.0)
			var cfg := {"preset": StringName(pre.trim_suffix("_f"))}
			if pre.ends_with("_f"):
				cfg["body"] = "female"
			var rig := show.spawn(cfg, pos, yaw)
			if prop_spec != "":
				rig.attach_prop(StringName(prop_spec.get_slice("/", 0)), StringName(prop_spec.get_slice("/", 1)))
			var cl := AnimLibrary.get_clip(clip)
			if cl == null:
				p.check(false, "missing clip %s" % clip)
				continue
			if t < 0.0:
				t = cl.event_time(&"impact")
				if t < 0.0:
					t = cl.event_time(&"release")
				if t < 0.0:
					t = 0.5
			show.run_for(0.3)
			if String(clip).begins_with("idle"):
				# Idles are the rig's own base layer (carry clips layer over it).
				show.run_for(t * cl.length)
			else:
				rig.play_action(clip, {"blend_in": 0.0, "start": t})
			rig.animator.paused = true
			# Pose frozen; let spring chains (capes, hair) settle into it.
			for k in 45:
				rig.advance(1.0 / 30.0)
			var lab := Label3D.new()
			lab.text = "%s @%.2f" % [clip, t]
			lab.font_size = 36
			lab.pixel_size = 0.003
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.position = pos + Vector3(0, 2.05, 0)
			lab.modulate = Color(0.1, 0.1, 0.1)
			show.add_child(lab)
			labels.append(lab)
			i += 1
		var dist := 2.2 + float(n) * 1.45
		if OS.get_environment("CLOSE") != "":
			dist = 0.9 + float(n) * 0.75
			show.frame_camera(Vector3(0, 1.45, -dist), Vector3(0, 1.3, 0), 38.0)
		else:
			show.frame_camera(Vector3(0, 1.3, -dist), Vector3(0, 0.95, 0), 38.0)
		await p.frames(3)
		await p.screenshot("sheet_%s_%d" % [preset, si])
		si += 1
