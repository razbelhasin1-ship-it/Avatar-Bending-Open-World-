extends RefCounted
## Wildlife showcase: otter penguin (waddle + belly slide), turtle duck (pond swim),
## ostrich horse (run), komodo rhino (walk), gull and hawk flocks overhead.


func rt(p: Playtest, rig: CreatureRig, t: float) -> void:
	var end := rig.time + t
	await p.wait_until(func() -> bool: return rig.time >= end, t * 30.0 + 5.0)


func run(p: Playtest) -> void:
	var stage: Node = await p.load_scene("res://scenes/dev/creature_showcase.tscn")
	var peng: CreatureRig = stage.spawn(&"otter_penguin", Vector3(-4.5, 0, 0), 0.5, {"idle": false})
	var duck: CreatureRig = stage.spawn(&"turtle_duck", Vector3(-2.2, 0, 0.6), 0.3, {"idle": false})
	var ostrich: CreatureRig = stage.spawn(&"ostrich_horse", Vector3(0.8, 0, 0), 0.6, {"idle": false})
	var komodo: CreatureRig = stage.spawn(&"komodo_rhino", Vector3(5.5, 0, 0.5), 0.7, {"idle": false})
	stage.add_reference_human(Vector3(-0.8, 0, 2.0))
	var gulls := BirdFlock.create(&"gull", 12, Vector3(-10, 0, -25), 22.0, 14.0, 7)
	stage.add_child(gulls)
	var hawks := BirdFlock.create(&"hawk", 3, Vector3(10, 0, -30), 30.0, 26.0, 9)
	stage.add_child(hawks)
	await rt(p, peng, 0.8)
	stage.frame(Vector3(1.5, 3.2, 11.0), Vector3(0.5, 1.0, 0), 50.0)
	await rt(p, peng, 0.2)
	await p.screenshot("wildlife_lineup")
	# Close-ups.
	for r: CreatureRig in [peng, duck, ostrich, komodo]:
		var d := r.get_dimensions()
		var hp: Vector3 = r.get_socket(&"head").global_position
		var L: float = maxf(float(d["height"]), 0.5)
		stage.frame(hp + (r.global_basis * Vector3(0.9, 0.15, -1.6)).normalized() * L * 1.1, hp + Vector3(0, -0.15 * L, 0), 40.0)
		await rt(p, peng, 0.15)
		await p.screenshot("wildlife_face_%s" % r.species_id)
	# Penguin waddle then belly slide.
	var dp: CreatureDriver = stage.driver(peng)
	dp.line(Vector3.BACK, peng.walk_speed)
	await rt(p, peng, 1.5)
	for i in 2:
		var pp := peng.global_position
		stage.frame(pp + Vector3(2.2, 0.8, 0.6), pp + Vector3(0, 0.5, 0), 45.0)
		await rt(p, peng, 0.18)
		await p.screenshot("penguin_waddle_%d" % i)
	peng.play_action(&"belly_slide")
	dp.line(Vector3.BACK, 4.5)
	await rt(p, peng, 1.4)
	var ps := peng.global_position
	stage.frame(ps + Vector3(2.5, 1.0, 2.5), ps + Vector3(0, 0.2, 0), 45.0)
	await rt(p, peng, 0.1)
	await p.screenshot("penguin_slide")
	p.check(peng.is_action_playing(&"belly_slide"), "penguin keeps sliding while moving")
	dp.idle()
	peng.stop_action()
	# Turtle duck on a pond.
	stage.add_pond(Vector3(-2.0, 0, 8.0), 4.0)
	duck.global_position = Vector3(-2.0, 0.03, 8.0)
	duck.reset_feet()
	duck.set_swimming(true, 0.03)
	var dd: CreatureDriver = stage.driver(duck)
	dd.circle(Vector3(-2.0, 0.03, 8.0), 1.6, 0.5)
	await rt(p, duck, 2.0)
	var dq := duck.global_position
	stage.frame(dq + Vector3(1.4, 0.7, 1.2), dq + Vector3(0, 0.15, 0), 45.0)
	await rt(p, duck, 0.1)
	await p.screenshot("turtle_duck_swim")
	# Ostrich horse run.
	var dos: CreatureDriver = stage.driver(ostrich)
	dos.accel = 8.0
	dos.line(Vector3.FORWARD, ostrich.run_speed)
	await rt(p, ostrich, 2.5)
	for i in 3:
		var op := ostrich.global_position
		stage.frame(op + Vector3(5.5, 1.6, 0.0), op + Vector3(0, 1.4, 0), 50.0)
		await rt(p, ostrich, 0.09)
		await p.screenshot("ostrich_run_%d" % i)
	dos.idle()
	# Komodo rhino walk.
	var dk: CreatureDriver = stage.driver(komodo)
	dk.line(Vector3.FORWARD, komodo.walk_speed)
	await rt(p, komodo, 2.0)
	for i in 2:
		var kp := komodo.global_position
		stage.frame(kp + Vector3(4.0, 2.4, -2.5), kp + Vector3(0, 0.7, -0.5), 50.0)
		await rt(p, komodo, 0.3)
		await p.screenshot("komodo_walk_%d" % i)
	# Sky.
	stage.frame(Vector3(0, 2.0, 6.0), Vector3(-3, 16.0, -25.0), 60.0)
	await rt(p, komodo, 0.5)
	await p.screenshot("birds_sky")
	p.check(peng.gait.footsteps > 2 and ostrich.gait.footsteps > 4 and komodo.gait.footsteps > 4, "wildlife footsteps")
	p.check(gulls.bird_positions().size() == 12, "gull flock")
