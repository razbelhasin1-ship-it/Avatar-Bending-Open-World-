extends RefCounted
## Gait sequences: each companion walks then runs past a side-tracking camera; frames
## are spaced over a stride so the leg phases, body bob and spine motion can be judged.
## SPECIES env var limits it to one creature.

const PLAN := {
	&"polar_bear_dog": [[&"walk", 1.6, 0.16], [&"trot", 4.2, 0.1], [&"gallop", 11.0, 0.07]],
	&"sky_bison": [[&"walk", 1.6, 0.3], [&"run", 4.8, 0.14]],
	&"badgermole": [[&"walk", 1.4, 0.18], [&"run", 6.5, 0.08]],
	&"dragon": [[&"walk", 2.2, 0.25], [&"run", 7.5, 0.12]],
}


func rt(p: Playtest, rig: CreatureRig, t: float) -> void:
	var end := rig.time + t
	await p.wait_until(func() -> bool: return rig.time >= end, t * 30.0 + 5.0)


func run(p: Playtest) -> void:
	var only := OS.get_environment("SPECIES")
	var stage: Node = await p.load_scene("res://scenes/dev/creature_showcase.tscn")
	for sp: StringName in PLAN:
		if only != "" and String(sp) != only:
			continue
		var rig: CreatureRig = stage.spawn(sp, Vector3.ZERO, -PI * 0.5, {"idle": false})
		var d := rig.get_dimensions()
		var H: float = d["height"]
		var L: float = minf(float(d["length"]), H * 2.6)
		var drv: CreatureDriver = stage.driver(rig)
		drv.accel = 6.0
		var x := 0.0
		for g: Array in PLAN[sp]:
			drv.line(Vector3.RIGHT, g[1])
			await rt(p, rig, 2.2 if g[1] < 5.0 else 3.0)
			var look_back := L * 0.25 if sp == &"dragon" else 0.0
			stage.follow(rig, Vector3(0.0, H * 0.25, L * 1.75), Vector3(0.0, H * 0.42, look_back), 45.0, false)
			for i in 4:
				await rt(p, rig, g[2])
				await p.screenshot("%s_%s_%d" % [sp, g[0], i])
			p.check(rig.gait.current_gait() == g[0], "%s uses %s at %.1f m/s (got %s)" % [sp, g[0], g[1], rig.gait.current_gait()])
			x += 1.0
		drv.idle()
		await rt(p, rig, 1.0)
		stage.follow(rig, Vector3(L * 1.2, H * 0.6, L * 1.2), Vector3(0, H * 0.4, 0), 45.0, false)
		await rt(p, rig, 1.2)
		await p.screenshot("%s_stopped" % sp)
		var planted := 0
		for l in rig.legs:
			if l.planted:
				planted += 1
		p.check(planted == rig.legs.size(), "%s all feet planted after stopping" % sp)
		rig.queue_free()
		await p.frames(2)
