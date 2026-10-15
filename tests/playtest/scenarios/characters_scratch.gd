extends RefCounted
## Scratch locomotion check (development aid).
func run(p: Playtest) -> void:
	var show: CharacterShowcase = await p.load_scene("res://scenes/dev/character_showcase.tscn")
	var speed := float(OS.get_environment("SCRATCH_SPEED")) if OS.get_environment("SCRATCH_SPEED") != "" else 1.5
	var presets := ["air_nomad", "earth_kingdom", "fire_nation", "water_tribe"]
	var x := -1.8
	for pr: String in presets:
		show.spawn({"preset": StringName(pr)}, Vector3(x, 0, 0))
		x += 1.2
	show.run_for(0.5)
	var vel := Vector3(0, 0, -speed)
	show.run_for(1.5, vel, true)
	for i in 6:
		var z := show.rigs[0].position.z
		show.frame_camera(Vector3(6.5, 1.0, z), Vector3(0, 0.85, z), 30.0)
		await p.frames(2)
		await p.screenshot("walk_%d" % i)
		show.run_for(0.1, vel, true)
