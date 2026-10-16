extends RefCounted
## Pose contact sheets of the enemy weapon clips with their props, frozen at the
## telegraph hold (windup) and at the strike (impact).
## SHEET="preset:clip@t+prop/socket+prop/socket,...;..." (";" separates images),
## VIEW=front|side|34|back, CLOSE=1. Without SHEET every archetype's attacks are shown.
func run(p: Playtest) -> void:
	EnemyClips.ensure()
	BendingClips.ensure()
	var show: CharacterShowcase = await p.load_scene("res://scenes/dev/character_showcase.tscn")
	var sheet_env := OS.get_environment("SHEET")
	if sheet_env == "":
		sheet_env = _default_sheets()
	var view := OS.get_environment("VIEW")
	var labels: Array[Node] = []
	var si := 0
	for sheet in sheet_env.split(";", false):
		show.clear_rigs()
		for l in labels:
			l.queue_free()
		labels.clear()
		await p.frames(1)
		var items := sheet.split(",", false)
		var n := items.size()
		var i := 0
		for it: String in items:
			var props := it.split("+", false)
			var head := props[0]
			var pre := "bandit"
			if head.contains(":"):
				pre = head.get_slice(":", 0)
				head = head.get_slice(":", 1)
			var parts := head.split("@")
			var clip := StringName(parts[0])
			var t := float(parts[1]) if parts.size() > 1 else 0.5
			var pos := Vector3((float(i) - (n - 1) * 0.5) * 1.6, 0, 0)
			var yaw: float = {"side": 90.0, "34": 30.0, "back": 180.0, "back34": 145.0}.get(view, 0.0)
			var cfg := {"preset": StringName(pre.trim_suffix("_f"))}
			if pre.ends_with("_f"):
				cfg["body"] = "female"
			var rig := show.spawn(cfg, pos, yaw)
			for k in range(1, props.size()):
				var spec := props[k]
				EnemyProps.attach(rig, StringName(spec.get_slice("/", 0)), StringName(spec.get_slice("/", 1)), &"fire_nation" if pre.begins_with("fire") else &"")
			var cl := AnimLibrary.get_clip(clip)
			if cl == null:
				p.check(false, "missing clip %s" % clip)
				continue
			show.run_for(0.3)
			rig.play_action(clip, {"blend_in": 0.0, "start": t})
			rig.animator.paused = true
			for k in 45:
				rig.advance(1.0 / 30.0)
			var bow := EnemyProps.find(rig, &"bow")
			if bow is EnemyProps.Bow and clip == &"enemy_bow_shot":
				var b := bow as EnemyProps.Bow
				b.draw = clampf((t - 0.25) / 0.3, 0.0, 1.0) if t < 0.6 else 0.0
				b.show_arrow = t >= 0.28 and t < 0.6
				b.draw_point = rig.get_socket(&"hand_r").global_position
			var lab := Label3D.new()
			lab.text = "%s @%.2f" % [clip, t]
			lab.font_size = 32
			lab.pixel_size = 0.003
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.position = pos + Vector3(0, 2.1, 0)
			lab.modulate = Color(0.1, 0.1, 0.1)
			show.add_child(lab)
			labels.append(lab)
			i += 1
		var dist := 2.4 + float(n) * 1.5
		if OS.get_environment("CLOSE") != "":
			dist = 1.0 + float(n) * 0.8
		show.frame_camera(Vector3(0, 1.3, -dist), Vector3(0, 0.95, 0), 38.0)
		await p.frames(3)
		await p.screenshot("enemy_sheet_%d" % si)
		si += 1


func _default_sheets() -> String:
	return ";".join([
		"bandit:enemy_slash_r@0.3+club/hand_r,bandit:enemy_slash_r@0.45+club/hand_r,bandit:enemy_backslash_r@0.26+club/hand_r,bandit:enemy_backslash_r@0.45+club/hand_r,bandit:enemy_overhead@0.36+club/hand_r,bandit:enemy_overhead@0.55+club/hand_r",
		"bandit_f:enemy_knife_slash_r@0.28+knife/hand_r+knife/hand_l,bandit_f:enemy_knife_slash_r@0.42+knife/hand_r+knife/hand_l,bandit_f:enemy_stab_r@0.3+knife/hand_r+knife/hand_l,bandit_f:enemy_stab_r@0.48+knife/hand_r+knife/hand_l,bandit_f:enemy_throw_r@0.32+knife/hand_r,bandit_f:enemy_throw_r@0.46+knife/hand_r",
		"fire_soldier:enemy_shield_guard@0.2+spear/hand_r+shield/hand_l,fire_soldier:enemy_thrust@0.32+spear/hand_r+shield/hand_l,fire_soldier:enemy_thrust@0.48+spear/hand_r+shield/hand_l,fire_soldier:enemy_shield_bash@0.3+spear/hand_r+shield/hand_l,fire_soldier:enemy_shield_bash@0.46+spear/hand_r+shield/hand_l",
		"bandit:enemy_bow_shot@0.25+bow/hand_l+quiver/back,bandit:enemy_bow_shot@0.55+bow/hand_l+quiver/back,bandit:enemy_bow_shot@0.62+bow/hand_l+quiver/back,bandit:enemy_surrender@0.95,bandit:enemy_spotted@0.3,fire_nation:enemy_war_cry@0.4",
	])
