extends RefCounted
## Signature strikes per element style frozen at anticipation and active
## frames (side and 3/4 views), plus a reaction/acrobatics sheet. Also checks
## that action events fire during real playback.

const SETS := {
	&"air": [&"air_nomad", [&"air_jab_r", &"air_blast", &"air_sweep", &"tornado_spin", &"dodge_flip"]],
	&"earth": [&"earth_kingdom", [&"earth_jab_r", &"earth_raise", &"wall_raise", &"earth_throw", &"stomp_r"]],
	&"fire": [&"fire_nation", [&"fire_jab_r", &"fire_kick_r", &"roundhouse_r", &"fire_charge_release", &"flip_kick"]],
	&"water": [&"water_tribe", [&"water_whip_r", &"water_surge", &"draw_up", &"water_shield", &"whip_lash_l"]],
}


func run(p: Playtest) -> void:
	var show: CharacterShowcase = await p.load_scene("res://scenes/dev/character_showcase.tscn")
	for style: StringName in SETS:
		var preset: StringName = SETS[style][0]
		var clips: Array = SETS[style][1]
		await _sheet(p, show, preset, clips, "anticipation", 90.0, "strikes_%s_anticipation" % style)
		await _sheet(p, show, preset, clips, "active", 90.0, "strikes_%s_active" % style)
		await _sheet(p, show, preset, clips, "active", 35.0, "strikes_%s_active_34" % style)
	await _sheet(p, show, &"earth_soldier", [&"stagger_front", &"knockdown_back", &"getup", &"launch", &"death_front"], "mid", 90.0, "reactions")
	await _sheet(p, show, &"water_tribe", [&"dodge_roll", &"dodge_side_r", &"dodge_back", &"dodge_water_slide_r", &"dodge_fire_burst"], "mid", 35.0, "dodges")
	await _events_check(p, show)


## Normalized time of a clip's anticipation (wind-up) or active frame.
func _time_for(clip: AnimClip, which: String) -> float:
	var active := clip.event_time(&"impact")
	if active < 0.0:
		active = clip.event_time(&"release")
	if active < 0.0:
		active = 0.45
	match which:
		"anticipation":
			# The last key before the active frame is the wind-up pose.
			var best := -1.0
			for ci: int in clip.tracks:
				var ts: PackedFloat32Array = clip.tracks[ci]["t"]
				for t in ts:
					if t > 0.05 and t < active - 0.08 and t > best:
						best = t
			return best if best > 0.0 else active * 0.55
		"mid":
			return 0.35
	return active


func _sheet(p: Playtest, show: CharacterShowcase, preset: StringName, clips: Array, which: String, yaw: float, shot: String) -> void:
	show.clear_rigs()
	await p.frames(1)
	var n := clips.size()
	var spacing := 1.45
	for i in n:
		var clip := AnimLibrary.get_clip(clips[i])
		if not p.check(clip != null, "clip %s exists" % clips[i]):
			continue
		var rig := show.spawn({"preset": preset}, Vector3((float(i) - (n - 1) * 0.5) * spacing, 0, 0), yaw)
		rig.set_combat_stance(true)
		show.run_for(0.6)
		rig.play_action(clips[i], {"blend_in": 0.0, "start": _time_for(clip, which)})
		rig.animator.paused = true
		rig.advance(0.0)
	var dist := 2.4 + float(n) * 1.4
	show.frame_camera(Vector3(0, 1.25, -dist), Vector3(0, 0.95, 0), 36.0)
	await p.frames(2)
	await p.screenshot(shot)


func _events_check(p: Playtest, show: CharacterShowcase) -> void:
	show.clear_rigs()
	await p.frames(1)
	var rig := show.spawn({"preset": &"fire_nation"}, Vector3.ZERO, 0.0)
	var got: Array = []
	rig.action_event.connect(func(clip: StringName, ev: StringName) -> void: got.append([clip, ev, rig.action_progress()]))
	var finished := [false]
	rig.action_finished.connect(func(_c: StringName) -> void: finished[0] = true)
	var dur := rig.play_action(&"combo_fire")
	show.run_for(dur + 0.2)
	var impacts := got.filter(func(e: Array) -> bool: return e[1] == &"impact")
	p.check(impacts.size() == 4, "combo_fire fired 4 impact events (got %d)" % impacts.size())
	p.check(finished[0], "combo_fire finished")
