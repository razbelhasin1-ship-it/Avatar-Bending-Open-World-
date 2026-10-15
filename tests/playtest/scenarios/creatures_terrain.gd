extends RefCounted
## Uneven ground: companions walk over rolling hills (foot IK on slopes, body pitch/roll
## from the support feet) and stand across a slope. Checks paws stay on the ground.


func rt(p: Playtest, rig: CreatureRig, t: float) -> void:
	var end := rig.time + t
	await p.wait_until(func() -> bool: return rig.time >= end, t * 30.0 + 5.0)


func run(p: Playtest) -> void:
	var stage: Node = await p.load_scene("res://scenes/dev/creature_showcase.tscn")
	var h: Callable = stage.set_hills(Vector3.ZERO, 120.0, 1.6)
	await p.frames(3)
	var plan := [[&"polar_bear_dog", 3.5], [&"sky_bison", 1.6], [&"badgermole", 1.4]]
	for row: Array in plan:
		var sp: StringName = row[0]
		var start := Vector3(-22.0, 0.0, 4.0)
		start.y = h.call(start.x, start.z)
		var rig: CreatureRig = stage.spawn(sp, start, -PI * 0.5, {"idle": false})
		var d := rig.get_dimensions()
		var H: float = d["height"]
		var L: float = d["length"]
		var drv: CreatureDriver = stage.driver(rig)
		drv.line(Vector3.RIGHT, row[1])
		await rt(p, rig, 3.0)
		stage.follow(rig, Vector3(0.0, H * 0.35, L * 1.6), Vector3(0, H * 0.35, 0), 45.0, false)
		var worst := 0.0
		for i in 3:
			await rt(p, rig, 2.0)
			await p.screenshot("terrain_%s_%d" % [sp, i])
			for l in rig.legs:
				if l.planted:
					worst = maxf(worst, absf(l.foot_world.y - float(h.call(l.foot_world.x, l.foot_world.z))))
		p.check(worst < 0.06, "%s planted paws on the hill surface (max err %.3f m)" % [sp, worst])
		# Stand still across the slope.
		drv.idle()
		await rt(p, rig, 1.5)
		stage.follow(rig, Vector3(L * 1.1, H * 0.4, -L * 1.1), Vector3(0, H * 0.4, 0), 45.0, false)
		await rt(p, rig, 0.3)
		await p.screenshot("terrain_%s_stand" % sp)
		var ik_err := 0.0
		for l in rig.legs:
			ik_err = maxf(ik_err, l.paw_world.distance_to(l.foot_world))
		p.check(ik_err < 0.1, "%s IK reaches the slope (err %.3f m)" % [sp, ik_err])
		rig.queue_free()
		await p.frames(2)
	WorldData.height_override = Callable()
