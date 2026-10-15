extends RefCounted
## Action poses: each entry plays an action and captures it at a characteristic time.
## SPECIES env var limits it to one creature. The dragon's fire uses CreatureFx.fire_breath.

const SHOTS := [
	[&"polar_bear_dog", &"sit", 1.4], [&"polar_bear_dog", &"lie_down", 2.2], [&"polar_bear_dog", &"shake", 0.55],
	[&"polar_bear_dog", &"scratch", 1.0], [&"polar_bear_dog", &"sniff", 1.0], [&"polar_bear_dog", &"bite", 0.45],
	[&"sky_bison", &"lie_down", 2.2], [&"sky_bison", &"groan", 1.2], [&"sky_bison", &"swipe", 0.5],
	[&"badgermole", &"dig", 1.0], [&"badgermole", &"sniff", 1.0],
	[&"dragon", &"breathe_fire_start", 1.2], [&"dragon", &"stretch_wings", 1.6], [&"dragon", &"prowl", 1.2],
	[&"dragon", &"yawn", 1.3],
]


func rt(p: Playtest, rig: CreatureRig, t: float) -> void:
	var end := rig.time + t
	await p.wait_until(func() -> bool: return rig.time >= end, t * 30.0 + 5.0)


func run(p: Playtest) -> void:
	var stage: Node = await p.load_scene("res://scenes/dev/creature_showcase.tscn")
	var rigs := {}
	for sp: StringName in [&"polar_bear_dog", &"sky_bison", &"badgermole", &"dragon"]:
		var x: float = {&"polar_bear_dog": -40.0, &"sky_bison": -15.0, &"badgermole": 15.0, &"dragon": 45.0}[sp]
		rigs[sp] = stage.spawn(sp, Vector3(x, 0, 0), 0.0, {"idle": false})
	# Visual fire stream on the dragon's mouth socket, driven by its action events.
	var dragon: CreatureRig = rigs[&"dragon"]
	var flames := CreatureFx.fire_breath(dragon.get_socket(&"mouth"))
	dragon.action_event.connect(func(_a: StringName, e: StringName) -> void:
		if e == &"fire_start":
			flames.emitting = true
		elif e == &"fire_end":
			flames.emitting = false)
	var only := OS.get_environment("SPECIES")
	for shot: Array in SHOTS:
		if only != "" and String(shot[0]) != only:
			continue
		var rig: CreatureRig = rigs[shot[0]]
		var d := rig.get_dimensions()
		var H: float = d["height"]
		var L: float = minf(float(d["length"]), H * 2.4)
		var look := Vector3(0, H * 0.45, -L * 0.1)
		if shot[0] == &"dragon":
			look = Vector3(0, H * 0.6, -L * 0.25)
		stage.follow(rig, Vector3(L * 1.15, H * 0.5, -L * 0.95), look, 45.0)
		var dur := rig.play_action(shot[1])
		p.check(dur > 0.0, "%s %s plays" % [shot[0], shot[1]])
		await rt(p, rig, shot[2])
		await p.screenshot("action_%s_%s" % [shot[0], shot[1]])
		rig.stop_action()
		if shot[1] == &"breathe_fire_start":
			rig.play_action(&"breathe_fire_end")
		await rt(p, rig, 1.2)
