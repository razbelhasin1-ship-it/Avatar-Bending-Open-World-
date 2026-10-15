extends TestCase
## Characters module tests (WIP).


func test_debug_walk() -> void:
	var rig := HumanoidRig.create({"preset": &"water_tribe"})
	rig.auto_lod = false
	add_child(rig)
	await frames(2)
	rig.set_process(false)
	var dt := 1.0 / 60.0
	var a := rig.animator
	for i in 120:
		rig.position += Vector3(0, 0, -1.5 * dt)
		var xf := rig.skeleton.global_transform
		a.update(dt, xf, Vector3(0, 0, -1.5), true, true, false)
		if i % 10 == 0:
			var l := a.loco
			print("i %d moving %s phase %.2f planted %s foot_l %s foot_r %s final foot_l %s" % [i, l.moving, l.phase, str(l.is_planted), l.foot_pos[0], l.foot_pos[1], a.final.v[RigPose.FOOT_L]])
