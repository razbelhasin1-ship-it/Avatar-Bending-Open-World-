extends RefCounted
## Snow deformation playtest: a synthetic walker leaves walking prints, a jump-landing crater,
## running prints, and a heavy creature (polar bear dog sized paws) walks alongside, all through
## Events.footstep / Events.landed on the Water Tribe's upper tier. Close-ups at ~3 m with a
## low afternoon sun, a wide view, and a view after refill during snowfall.

const START := Vector3(1000.0, 0.0, -2808.0)


func run(p: Playtest) -> void:
	var scene := await p.load_scene("res://scenes/dev/world_render_test.tscn")
	if scene == null:
		return
	var world: WorldRenderer = scene.world
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	world.set_time_scale(0.0)
	world.set_time_of_day(14.6)
	world.set_weather(&"clear", 0.0)
	var y0 := WorldData.get_height(START.x, START.z)
	var walker := CharacterBody3D.new()
	walker.name = "SyntheticWalker"
	scene.add_child(walker)
	walker.global_position = Vector3(START.x, y0, START.z)
	var yaw_east := -PI * 0.5           # forward (-sin, -cos) = +X
	var fwd := Vector3(1, 0, 0)
	var side := Vector3(0, 0, 1)
	var stamps_before := world.snow.stamp_count()
	# walking: 0.72 m stride, feet 0.11 m either side of the path
	var pos := walker.global_position
	walker.velocity = fwd * 1.6
	for i in 14:
		var foot := pos + fwd * (i * 0.72) + side * (0.11 if i % 2 == 0 else -0.11)
		foot.y = WorldData.get_height(foot.x, foot.z)
		Events.footstep.emit(walker, foot, yaw_east + randf_range(-0.06, 0.06), 0.28, 1.0, &"snow")
		await p.frames(1)
	# jump and land
	var land := pos + fwd * (14 * 0.72 + 1.9)
	land.y = WorldData.get_height(land.x, land.z)
	Events.landed.emit(walker, land, -9.0, &"snow")
	await p.frames(1)
	# running: 1.35 m stride, kicked snow
	walker.velocity = fwd * 6.5
	var run0 := land + fwd * 1.2
	for i in 10:
		var foot := run0 + fwd * (i * 1.35) + side * (0.09 if i % 2 == 0 else -0.09)
		foot.y = WorldData.get_height(foot.x, foot.z)
		Events.footstep.emit(walker, foot, yaw_east + randf_range(-0.05, 0.05), 0.28, 1.15, &"snow")
		await p.frames(1)
	# heavy creature 2.6 m to the side: four big paws per cycle
	var beast := CharacterBody3D.new()
	scene.add_child(beast)
	beast.velocity = fwd * 1.8
	var b0 := pos + side * 2.6 - fwd * 1.0
	for i in 12:
		var along := i * 0.62
		for pair in [[0.0, 0.32], [0.95, -0.32]]:
			var lateral: float = pair[1] if i % 2 == 0 else -pair[1]
			var foot := b0 + fwd * (along + float(pair[0])) + side * lateral
			foot.y = WorldData.get_height(foot.x, foot.z)
			Events.footstep.emit(beast, foot, yaw_east, 0.55, 2.6, &"snow")
		await p.frames(1)
	await p.frames(6)
	p.check(world.snow.stamp_count() - stamps_before >= 14 + 1 + 10 + 24, "all prints stored (%d)" % (world.snow.stamp_count() - stamps_before))
	var mid := pos + fwd * 5.0
	var sink := world.get_snow_sink_depth(pos + fwd * (2 * 0.72) + side * 0.11)
	p.check(sink > 0.04 and sink < 0.3, "walking print depth %.3f m" % sink)
	var crater := world.get_snow_sink_depth(land)
	p.check(crater > sink, "landing crater (%.3f m) deeper than a step" % crater)
	var paw := world.get_snow_sink_depth(b0 + fwd * 0.0 + side * 0.32)
	p.check(paw > sink, "heavy creature print (%.3f m) deeper than a human step" % paw)
	# a stand-in figure standing in its last print (feet sunk by the sink depth)
	var figure := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 1.72
	figure.mesh = cap
	figure.material_override = ToonMaterials.make(Color(0.2, 0.36, 0.62))
	scene.add_child(figure)
	var last := run0 + fwd * (9 * 1.35)
	figure.global_position = Vector3(last.x + 0.6, WorldData.get_height(last.x + 0.6, last.z) - 0.08 + 0.86, last.z)
	await p.frames(4)
	# close-up at ~3 m (walking prints), low side light
	_cam(scene, mid + Vector3(-1.2, 1.75, 2.5), mid + Vector3(0.6, 0.0, -0.1))
	await p.wait(0.6)
	await p.screenshot("worldrender_snow_walk_closeup")
	# crater + running prints
	_cam(scene, land + Vector3(-2.2, 2.0, 2.4), land + Vector3(1.6, 0.0, 0.0))
	await p.wait(0.6)
	await p.screenshot("worldrender_snow_landing_running")
	# heavy creature prints next to human prints
	var bmid := b0 + fwd * 3.0
	_cam(scene, bmid + Vector3(-1.4, 2.2, 2.6), bmid + Vector3(0.6, 0.0, -1.2))
	await p.wait(0.6)
	await p.screenshot("worldrender_snow_creature")
	# wide view of the whole trail
	_cam(scene, pos + Vector3(-5.0, 4.5, 7.0), pos + fwd * 14.0 + side * 0.8)
	await p.wait(0.6)
	await p.screenshot("worldrender_snow_trail_wide")
	# refill during heavy snowfall: prints soften and fill in
	world.set_weather(&"snow", 0.0)
	var before := world.get_snow_sink_depth(pos + fwd * (2 * 0.72) + side * 0.11)
	# skip ~45 s of snowfall (the renderer sets the snowfall refill multiplier every frame)
	for i in 90:
		world.snow.update(walker.global_position, 0.5)
		await p.frames(1)
	var after := world.get_snow_sink_depth(pos + fwd * (2 * 0.72) + side * 0.11)
	p.check(after < before, "prints refill (%.3f -> %.3f m)" % [before, after])
	_cam(scene, mid + Vector3(-1.2, 1.75, 2.5), mid + Vector3(0.6, 0.0, -0.1))
	await p.wait(1.0)
	await p.screenshot("worldrender_snow_refilled")


func _cam(scene: Node, pos: Vector3, look: Vector3) -> void:
	scene.place_camera(pos, look, 62.0)
