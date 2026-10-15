extends RefCounted
## Flight sequences for the sky bison and the dragon: takeoff, a banking turn seen from
## behind/front, cruising (tail strokes / flaps and glides) and landing.
## SPECIES env var limits it to one flyer.


func rt(p: Playtest, rig: CreatureRig, t: float) -> void:
	var end := rig.time + t
	await p.wait_until(func() -> bool: return rig.time >= end, t * 30.0 + 5.0)


func run(p: Playtest) -> void:
	var only := OS.get_environment("SPECIES")
	var stage: Node = await p.load_scene("res://scenes/dev/creature_showcase.tscn")
	for sp: StringName in [&"sky_bison", &"dragon"]:
		if only != "" and String(sp) != only:
			continue
		await _fly(p, stage, sp)


func _fly(p: Playtest, stage: Node, sp: StringName) -> void:
	var rig: CreatureRig = stage.spawn(sp, Vector3(0, 0, 0), 0.0, {"idle": false})
	var events: Array = []
	rig.action_event.connect(func(a: StringName, e: StringName) -> void: events.append(e))
	var d := rig.get_dimensions()
	var H: float = d["height"]
	var L: float = minf(float(d["length"]), H * 2.6)
	stage.add_reference_human(Vector3(L * 0.5, 0, -2.0))
	var drv: CreatureDriver = stage.driver(rig)
	await rt(p, rig, 0.8)
	# Takeoff (camera fixed on the launch spot, 3/4 front).
	stage.follow(rig, Vector3(L * 1.2, H * 0.55, -L * 1.25), Vector3(0, H * 0.7, 0), 50.0)
	rig.set_flying(true)
	drv.fly_line(Vector3.FORWARD, 7.0, H * 3.0)
	for i in 4:
		await rt(p, rig, 0.55)
		await p.screenshot("%s_takeoff_%d" % [sp, i])
	p.check(events.has(&"leap"), "%s leap event" % sp)
	# Banking turn: circle left, seen from behind and from the front.
	var center := rig.global_position + Vector3(-30, 0, 0)
	center.y = 0.0
	drv.fly_circle(center, 30.0, 17.0, H * 4.0)
	await rt(p, rig, 4.0)
	for view in ["behind", "front"]:
		var off := Vector3(0, H * 0.55, L * 1.7) if view == "behind" else Vector3(-L * 0.35, H * 0.25, -L * 1.8)
		stage.follow(rig, off, Vector3(0, H * 0.3, 0), 55.0)
		await rt(p, rig, 0.3)
		await p.screenshot("%s_bank_%s" % [sp, view])
	p.check(rig.pose.body_roll < -0.15, "%s banks into the left turn (roll %.2f)" % [sp, rig.pose.body_roll])
	# Cruise from the side: a few frames over a stroke cycle.
	drv.fly_line(-rig.global_basis.z, 18.0, H * 4.0)
	await rt(p, rig, 2.5)
	stage.follow(rig, Vector3(L * 2.1, H * 0.25, -L * 0.3), Vector3(0, H * 0.35, -L * 0.15), 50.0)
	for i in 3:
		await rt(p, rig, 0.45)
		await p.screenshot("%s_cruise_%d" % [sp, i])
	# Landing.
	drv.line(-rig.global_basis.z, 5.0)
	rig.set_flying(false)
	stage.follow(rig, Vector3(L * 1.5, H * 0.5, -L * 0.9), Vector3(0, H * 0.6, 0), 55.0)
	for i in 4:
		await rt(p, rig, 0.6)
		await p.screenshot("%s_land_%d" % [sp, i])
	await p.wait_until(func() -> bool: return events.has(&"touchdown"), 60.0)
	drv.idle()
	await rt(p, rig, 1.5)
	p.check(events.has(&"touchdown"), "%s touchdown event" % sp)
	p.check(rig.flight_w < 0.05, "%s landed (flight_w %.2f)" % [sp, rig.flight_w])
	rig.queue_free()
	await p.frames(2)
