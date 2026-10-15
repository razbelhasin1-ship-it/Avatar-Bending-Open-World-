extends RefCounted
## Quick iteration scenario: one species, a few angles and a short walk.
## SPECIES env var picks the creature (default polar_bear_dog).


func run(p: Playtest) -> void:
	var sp := StringName(OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "polar_bear_dog")
	var stage: Node = await p.load_scene("res://scenes/dev/creature_showcase.tscn")
	var rig: CreatureRig = stage.spawn(sp, Vector3.ZERO, 0.0, {"idle": false})
	var d: Dictionary = rig.get_dimensions()
	var L: float = d["length"]
	var H: float = d["height"]
	stage.add_reference_human(Vector3(L * 0.45 + 1.2, 0, 0.8))
	await p.wait(0.6)
	stage.frame(Vector3(L * 1.1, H * 0.75, -L * 1.0), Vector3(0, H * 0.45, 0), 45.0)
	await p.wait(0.3)
	await p.screenshot("%s_34front" % sp)
	stage.frame(Vector3(L * 1.6, H * 0.5, 0.0), Vector3(0, H * 0.45, 0), 45.0)
	await p.wait(0.2)
	await p.screenshot("%s_side" % sp)
	var hp: Vector3 = rig.get_socket(&"head").global_position
	stage.frame(hp + Vector3(L * 0.28, 0.0, -L * 0.42), hp + Vector3(0, -0.1 * L, -0.05 * L), 40.0)
	await p.wait(0.2)
	await p.screenshot("%s_face" % sp)
	# Walk sequence.
	var drv: CreatureDriver = stage.driver(rig)
	drv.line(Vector3.LEFT, rig.walk_speed)
	stage.frame(Vector3(-4.0, H * 0.6, L * 1.6), Vector3(-4.0, H * 0.4, 0), 50.0)
	await p.wait(1.5)
	for i in 3:
		var pos := rig.global_position
		stage.frame(pos + Vector3(0.0, H * 0.55, L * 1.5), pos + Vector3(0, H * 0.4, 0), 50.0)
		await p.wait(0.22)
		await p.screenshot("%s_walk_%d" % [sp, i])
	drv.line(Vector3.LEFT, rig.run_speed * 1.5)
	await p.wait(2.0)
	for i in 3:
		var pos := rig.global_position
		stage.frame(pos + Vector3(0.0, H * 0.55, L * 1.7), pos + Vector3(0, H * 0.4, 0), 50.0)
		await p.wait(0.13)
		await p.screenshot("%s_run_%d" % [sp, i])
	p.check(rig.gait.footsteps > 4, "footsteps emitted (%d)" % rig.gait.footsteps)
