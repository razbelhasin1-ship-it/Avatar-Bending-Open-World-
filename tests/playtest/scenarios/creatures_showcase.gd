extends RefCounted
## Companion showcase (scenes/dev/creature_showcase.tscn): every companion next to a
## 1.75 m human marker from 3/4 and side views, face close-ups and signature actions.
## Run: tools/playtest.sh creatures_showcase <out_dir> 1280x720

const LAYOUT := {
	&"polar_bear_dog": [Vector3(-15.0, 0, 0), 0.5],
	&"sky_bison": [Vector3(-5.0, 0, -1.0), 0.45],
	&"badgermole": [Vector3(6.5, 0, 0), 0.5],
	&"dragon": [Vector3(17.0, 0, -2.0), 0.55],
}


## Waits on the creature's own animation clock (playtest waits are wall-clock).
func rt(p: Playtest, rig: CreatureRig, t: float) -> void:
	var end := rig.time + t
	await p.wait_until(func() -> bool: return rig.time >= end, t * 30.0 + 5.0)


func run(p: Playtest) -> void:
	var stage: Node = await p.load_scene("res://scenes/dev/creature_showcase.tscn")
	var rigs := {}
	for sp: StringName in LAYOUT:
		var at: Array = LAYOUT[sp]
		var rig: CreatureRig = stage.spawn(sp, at[0], at[1], {"idle": false})
		rigs[sp] = rig
		var d := rig.get_dimensions()
		var side := rig.global_basis.x
		stage.add_reference_human(rig.global_position + side * (float(d["width"]) * 0.5 + 1.0) + rig.global_basis.z * 0.5)
	var clock: CreatureRig = rigs[&"polar_bear_dog"]
	await rt(p, clock, 1.0)
	stage.frame(Vector3(-1.0, 7.5, -27.0), Vector3(1.5, 2.0, 0.0), 48.0)
	await rt(p, clock, 0.2)
	await p.screenshot("companions_lineup")
	for sp: StringName in LAYOUT:
		var rig: CreatureRig = rigs[sp]
		var d := rig.get_dimensions()
		var L: float = minf(float(d["length"]), float(d["height"]) * 3.0)
		var H: float = d["height"]
		var b := rig.global_basis
		var c := rig.global_position + Vector3(0, H * 0.45, 0)
		if sp == &"dragon":
			c += b.z * 3.0
		stage.frame(c + (b * Vector3(1.0, 0.0, -1.05)).normalized() * L * 1.45 + Vector3(0, H * 0.35, 0), c, 45.0)
		await rt(p, clock, 0.15)
		await p.screenshot("%s_34" % sp)
		var cs := c + (b.z * 4.0 if sp == &"dragon" else Vector3.ZERO)
		stage.frame(cs + b.x * L * (2.0 if sp == &"dragon" else 1.55) + Vector3(0, H * 0.1, 0), cs, 45.0)
		await rt(p, clock, 0.15)
		await p.screenshot("%s_side" % sp)
		var hp := rig.get_socket(&"head").global_position
		var face_dir := (b * Vector3(0.75, 0.12, -1.0)).normalized()
		var fd := maxf(H * 0.62, float(d["length"]) * 0.45) if sp != &"dragon" else H * 0.7
		stage.frame(hp + face_dir * fd, hp + Vector3(0, -H * 0.04, 0), 42.0)
		await rt(p, clock, 0.15)
		await p.screenshot("%s_face" % sp)
	# Signature actions.
	var acts := {&"polar_bear_dog": &"howl", &"sky_bison": &"call", &"badgermole": &"rear_up", &"dragon": &"roar"}
	var at_t := {&"polar_bear_dog": 1.6, &"sky_bison": 1.0, &"badgermole": 0.9, &"dragon": 1.2}
	for sp: StringName in acts:
		var rig: CreatureRig = rigs[sp]
		var d := rig.get_dimensions()
		var H: float = d["height"]
		var L: float = minf(float(d["length"]), H * 3.0)
		var b := rig.global_basis
		var c := rig.global_position + Vector3(0, H * 0.55, 0)
		stage.frame(c + (b * Vector3(1.1, 0.1, -0.9)).normalized() * L * 1.3 + Vector3(0, H * 0.15, 0), c, 45.0)
		var dur := rig.play_action(acts[sp])
		p.check(dur > 0.0, "%s plays %s" % [sp, acts[sp]])
		await rt(p, rig, at_t[sp])
		await p.screenshot("%s_%s" % [sp, acts[sp]])
	var bison: CreatureRig = rigs[&"sky_bison"]
	p.check(bison.get_socket(&"saddle").global_position.y > 3.0, "bison saddle on top of the head")
