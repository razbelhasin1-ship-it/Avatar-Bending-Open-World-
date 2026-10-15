extends RefCounted
## Locomotion review: each style idle -> walk -> run (side view sequences),
## a turning circle and stairs/slope foot IK. Checks footstep emission.
## MOTION_STYLES="air,earth" limits the styles (default: all element styles + others).

const STYLE_PRESET := {
	&"air": &"air_nomad", &"earth": &"earth_kingdom", &"fire": &"fire_nation", &"water": &"water_tribe",
	&"civilian": &"villager_earth", &"soldier": &"earth_soldier", &"elder": &"monk_elder", &"child": &"villager_air",
}

var _steps := 0


func run(p: Playtest) -> void:
	var show: CharacterShowcase = await p.load_scene("res://scenes/dev/character_showcase.tscn")
	Events.footstep.connect(func(_a: Node3D, _pos: Vector3, _yaw: float, _s: float, _w: float, _surf: StringName) -> void: _steps += 1)
	var styles: Array = []
	var env := OS.get_environment("MOTION_STYLES")
	if env != "":
		for s in env.split(","):
			styles.append(StringName(s))
	else:
		styles = [&"air", &"earth", &"fire", &"water", &"civilian", &"soldier", &"elder", &"child"]
	for st: StringName in styles:
		await _style_run(p, show, st)
	if env == "":
		await _turning(p, show)
		await _stairs(p, show)


func _style_run(p: Playtest, show: CharacterShowcase, style: StringName) -> void:
	show.clear_rigs()
	await p.frames(1)
	var cfg := {"preset": STYLE_PRESET[style], "style": style}
	if style == &"child":
		cfg["age"] = "child"
	var rig := show.spawn(cfg, Vector3.ZERO, 90.0)
	show.run_for(0.6)
	show.frame_camera(Vector3(0, 1.0, -4.2), Vector3(0, 0.85, 0), 34.0)
	await p.frames(2)
	await p.screenshot("motion_%s_idle" % style)
	_steps = 0
	# Walk then run along -X (the rig faces -X).
	for gait: Array in [["walk", 1.5], ["run", 4.6]]:
		var v := Vector3(-float(gait[1]), 0, 0)
		show.run_for(1.4, v, true)
		for i in 5:
			var x := rig.position.x
			show.frame_camera(Vector3(x, 0.8, -4.4 if gait[0] == "walk" else -5.0), Vector3(x, 0.8, 0), 34.0)
			await p.frames(2)
			var lo := rig.animator.loco
			p.note("%s %s %d spd %.2f rf %.2f ph %.2f lift %.2f %.2f planted %s" % [style, gait[0], i, lo.speed, lo.run_factor, lo.phase, lo.foot_lift[0], lo.foot_lift[1], str(lo.is_planted)])
			await p.screenshot("motion_%s_%s_%d" % [style, gait[0], i])
			show.run_for(0.07 if gait[0] == "run" else 0.11, v, true)
	p.check(_steps >= 6, "%s: footsteps emitted while moving (%d)" % [style, _steps])


func _turning(p: Playtest, show: CharacterShowcase) -> void:
	show.clear_rigs()
	await p.frames(1)
	var rig := show.spawn({"preset": &"water_tribe"}, Vector3.ZERO, 0.0)
	show.run_for(0.5)
	# Walk a 2.5 m radius circle; feet must stay planted (no sliding).
	var r := 2.5
	var ang := 0.0
	var speed := 1.6
	for i in 150:
		var dt := 1.0 / 60.0
		ang += speed / r * dt
		var pos := Vector3(cos(ang) * r - r, 0, sin(ang) * r)
		var vel := (pos - rig.position) / dt
		rig.position = pos
		rig.rotation.y = atan2(-vel.x, -vel.z)
		rig.set_locomotion(vel, true)
		rig.advance(dt)
	show.frame_camera(Vector3(-r, 4.2, -3.2), Vector3(-r, 0.4, 0.4), 50.0)
	await p.frames(2)
	await p.screenshot("motion_turning")
	# Turn in place: the rig rotates while standing, feet re-step.
	for i in 60:
		rig.rotation.y += deg_to_rad(2.0)
		rig.set_locomotion(Vector3.ZERO, true)
		rig.advance(1.0 / 60.0)
	show.frame_camera(rig.position + Vector3(1.8, 1.4, -2.2), rig.position + Vector3(0, 0.6, 0), 40.0)
	await p.frames(2)
	await p.screenshot("motion_turn_in_place")


func _stairs(p: Playtest, show: CharacterShowcase) -> void:
	show.clear_rigs()
	await p.frames(1)
	# Steps along -X: 18 cm risers.
	for i in 5:
		show.add_block(Vector3(-1.5 - i * 0.45, 0.09 + i * 0.18, 0.0), Vector3(0.45, 0.18 + i * 0.36, 1.6))
	var rig := show.spawn({"preset": &"earth_kingdom"}, Vector3(-1.5, 0.18, 0.4), 90.0)
	rig.position.y = 0.0
	# Stand with one foot on the first step.
	rig.position = Vector3(-1.22, 0.0, 0.0)
	show.run_for(0.8)
	show.frame_camera(Vector3(-1.3, 0.9, -2.4), Vector3(-1.3, 0.5, 0), 40.0)
	await p.frames(2)
	await p.screenshot("motion_ik_stairs")
	show.clear_rigs()
	await p.frames(1)
	show.add_ramp(Vector3(4.0, 0.0, 0.0), Vector3(2.5, 0.3, 3.0), 0.0)
	var rig2 := show.spawn({"preset": &"fire_nation"}, Vector3(4.0, 0.15, 0.0), 0.0)
	show.run_for(0.6)
	p.check(rig2.animator.solver.ground_dy[0] > 0.05, "foot IK found the raised ground (dy=%.2f)" % rig2.animator.solver.ground_dy[0])
