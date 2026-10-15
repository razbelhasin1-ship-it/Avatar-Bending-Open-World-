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
	if env == "ik":
		await _turning(p, show)
		await _stairs(p, show)
		return
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
	show.frame_camera(Vector3(-r, 3.4, -4.2), Vector3(-r, 0.5, 0.0), 46.0)
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
	# A single 18 cm step under the left foot only.
	var x0 := 20.0
	show.add_block(Vector3(x0 - 0.35, 0.09, 0.0), Vector3(0.6, 0.18, 1.6))
	var rig := show.spawn({"preset": &"earth_kingdom"}, Vector3(x0 + 0.03, 0.0, 0.0), 0.0)
	show.run_for(0.8)
	p.check(rig.animator.solver.ground_dy[0] > 0.12 and absf(rig.animator.solver.ground_dy[1]) < 0.03,
		"foot IK: left foot on the step (dy %.2f), right on the floor (dy %.2f)" % [rig.animator.solver.ground_dy[0], rig.animator.solver.ground_dy[1]])
	show.frame_camera(Vector3(x0 + 1.2, 1.0, -2.8), Vector3(x0, 0.75, 0), 40.0)
	await p.frames(2)
	await p.screenshot("motion_ik_step")
	# Walk up a staircase (15 cm risers, 40 cm treads): the body root snaps to
	# the tread under it like a character controller, feet land on their own steps.
	show.clear_rigs()
	await p.frames(1)
	var x1 := 30.0
	var riser := 0.15
	var tread := 0.4
	for i in 6:
		var hgt := riser * float(i + 1)
		show.add_block(Vector3(x1, hgt * 0.5, -1.0 - tread * float(i) - tread * 0.5), Vector3(1.4, hgt, tread))
	var climber := show.spawn({"preset": &"fire_nation"}, Vector3(x1, 0, 0.5), 0.0)
	show.run_for(0.4)
	var vel := Vector3(0, 0, -1.2)
	var shots := 0
	for i in 150:
		var z := climber.position.z + vel.z / 60.0
		var step_i := int(floor((-1.0 - z) / tread))
		var ground := clampf(float(step_i + 1), 0.0, 6.0) * riser if z < -1.0 else 0.0
		climber.position = Vector3(x1, lerpf(climber.position.y, ground, 0.35), z)
		climber.set_locomotion(vel, true)
		climber.advance(1.0 / 60.0)
		if i >= 90 and i % 12 == 0 and shots < 4:
			show.frame_camera(Vector3(x1 + 3.6, climber.position.y + 1.1, climber.position.z), Vector3(x1, climber.position.y + 0.85, climber.position.z), 38.0)
			await p.frames(2)
			await p.screenshot("motion_stairs_%d" % shots)
			shots += 1
