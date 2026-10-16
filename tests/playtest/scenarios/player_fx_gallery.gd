extends RefCounted
## VFX review sheet: every effect primitive spawned in front of a fixed close
## camera in the combat arena and captured mid-flight. FX=fire,air,... limits it.

var cam: Camera3D


func run(p: Playtest) -> void:
	var arena: Node3D = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": ElementDefs.Element.FIRE})
	await p.wait_game(0.5)
	var pl := p.player() as PlayerCharacter
	pl.global_position = Vector3(0, 0, 30)
	(arena.get("bot") as SparringBot).active = false
	cam = Camera3D.new()
	cam.fov = 50.0
	arena.add_child(cam)
	cam.make_current()
	var only := OS.get_environment("FX")
	var center := Vector3(0, 1.2, 12)
	cam.global_transform = Transform3D(Basis.IDENTITY, center + Vector3(0.0, 0.4, 4.2)).looking_at(center, Vector3.UP)
	if only == "" or only.contains("fire"):
		var ball := FireFx.ball(arena, 0.4)
		ball.global_position = center + Vector3(-1.4, 0.3, 0)
		var big := FireFx.ball(arena, 0.18)
		big.global_position = center + Vector3(-0.5, 0.3, 0)
		FireFx.arc(arena, Transform3D(Basis.IDENTITY, center + Vector3(1.0, -0.4, 0)), -1.2, 1.2, 1.0, 0.3)
		await p.wait_game(0.2)
		FireFx.burst(arena, center + Vector3(1.6, 0.4, 0), 1.0)
		await p.wait_game(0.12)
		await p.screenshot("fx_fire_a")
		FireFx.explosion(arena, center + Vector3(0, -0.3, -1.5), 2.5, 0.0)
		await p.wait_game(0.15)
		await p.screenshot("fx_fire_explosion")
		FireFx.arc(arena, Transform3D(Basis.IDENTITY, Vector3(center.x, 0.03, center.z + 1.5)), -1.1, 1.1, 0.8, 0.42,
				{"standing": true, "height": 1.25, "lean": 0.35, "hold": 0.15, "grow_to": 5.0, "tail": 3.0, "tongues": 9.0})
		await p.wait_game(0.3)
		await p.screenshot("fx_fire_wave")
		ball.finish()
		big.finish()
		await p.wait_game(1.0)
	if only == "" or only.contains("air"):
		AirFx.gust(arena, Transform3D(Basis.looking_at(Vector3(1, 0, -0.3).normalized(), Vector3.UP), center + Vector3(-2.5, 0, 0)), 6.0, 0.8, 0.4)
		AirFx.swirl(arena, center + Vector3(1.5, -1.0, -1.0), 1.0, 0.8, {"grow": 1.4})
		AirFx.ground_puff(arena, Vector3(center.x - 1.0, 0.0, center.z - 1.0), &"grass", 1.0)
		await p.wait_game(0.18)
		await p.screenshot("fx_air")
		await p.wait_game(1.0)
	if only == "" or only.contains("water"):
		var s := WaterStream.spawn(arena)
		var pts := PackedVector3Array()
		for i in 8:
			var u := float(i) / 7.0
			pts.append(center + Vector3(-2.0 + u * 4.0, sin(u * PI) * 0.6 - 0.2, -0.3 * sin(u * 6.0)))
		s.set_points(pts, 0.12, 0.05)
		s.set_spray(true)
		IceFx.splash(arena, center + Vector3(1.5, -0.6, -0.5), 1.0, Vector3.UP, 0.0)
		for i in 3:
			var sh := IceFx.shard(arena, 0.7, i)
			sh.global_position = center + Vector3(-0.6 + i * 0.6, 0.7, 0.5)
			sh.global_basis = Basis.looking_at(Vector3(0.3, 0.1, -1).normalized(), Vector3.UP)
		await p.wait_game(0.15)
		await p.screenshot("fx_water")
		s.freeze = 1.0
		IceFx.shatter(arena, center + Vector3(0, 0, -1.0), Vector3.UP, 1.0, 0.0)
		await p.wait_game(0.1)
		await p.screenshot("fx_ice")
		s.finish(0.1)
		await p.wait_game(1.0)
	if only == "" or only.contains("earth"):
		var rock := EarthFx.rock(arena, 0.35)
		rock.global_position = center + Vector3(-1.2, 0.3, 0)
		var rock2 := EarthFx.rock(arena, 0.6, 2)
		rock2.global_position = center + Vector3(0.8, 0.0, -1.0)
		EarthFx.tear_out(arena, Vector3(center.x + 1.5, 0, center.z), 0.6, &"stone")
		EarthFx.quake(arena, Vector3(center.x - 1.0, 0, center.z - 1.5), 2.5, &"dirt")
		await p.wait_game(0.15)
		await p.screenshot("fx_earth")
		FxLib.release(rock)
		FxLib.release(rock2)
	p.check(true, "gallery done")
