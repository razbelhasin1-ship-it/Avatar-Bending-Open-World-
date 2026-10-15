extends RefCounted
## Character lineup: every preset (front + 3/4), female / age variants, a
## seeded villager crowd and face close-ups. Rigs idle (deterministic steps).

const ROW_A := [&"air_nomad", &"monk_elder", &"water_tribe", &"water_warrior", &"earth_kingdom", &"earth_soldier", &"dai_li", &"fire_nation", &"fire_soldier"]
const ROW_B := [&"bandit", &"pirate", &"merchant", &"guard", &"villager_air", &"villager_water", &"villager_earth", &"villager_fire"]


func run(p: Playtest) -> void:
	var show: CharacterShowcase = await p.load_scene("res://scenes/dev/character_showcase.tscn")
	var t0 := Time.get_ticks_msec()
	await _row(p, show, _cfgs(ROW_A, {}), "lineup_nations")
	p.note("built row A in %d ms (cache %d meshes)" % [Time.get_ticks_msec() - t0, CharacterMeshBuilder.cache_size()])
	show.frame_camera(Vector3(5.5, 1.6, -7.5), Vector3(0.6, 0.95, 0), 38.0)
	await p.frames(2)
	await p.screenshot("lineup_nations_34")
	await _row(p, show, _cfgs(ROW_B, {}), "lineup_npcs")
	var fem: Array = []
	for pr: StringName in [&"air_nomad", &"water_tribe", &"earth_kingdom", &"fire_nation", &"villager_water", &"villager_earth", &"villager_fire", &"bandit"]:
		fem.append({"preset": pr, "body": "female"})
	await _row(p, show, fem, "lineup_female")
	var ages: Array = [
		{"preset": &"air_nomad", "age": "child"}, {"preset": &"villager_water", "age": "child", "body": "female"},
		{"preset": &"villager_earth", "age": "teen"}, {"preset": &"fire_nation", "age": "teen", "body": "female"},
		{"preset": &"villager_fire", "age": "elder"}, {"preset": &"villager_earth", "age": "elder", "body": "female"},
		{"preset": &"monk_elder"}, {"preset": &"merchant"},
	]
	await _row(p, show, ages, "lineup_ages")
	var crowd: Array = []
	for i in 10:
		crowd.append({"preset": [&"villager_earth", &"villager_fire", &"villager_water"][i % 3], "seed": i + 3, "body": "female" if i % 2 == 0 else "male"})
	await _row(p, show, crowd, "lineup_crowd")
	p.check(CharacterMeshBuilder.cache_size() > 0, "mesh cache in use")
	# Face close-ups.
	show.clear_rigs()
	await p.frames(1)
	var faces: Array = [{"preset": &"air_nomad"}, {"preset": &"water_tribe", "body": "female"}, {"preset": &"earth_kingdom"}, {"preset": &"fire_nation", "body": "female"}]
	var x := -1.2
	for c: Dictionary in faces:
		show.spawn(c, Vector3(x, 0, 0))
		x += 0.8
	show.run_for(0.6)
	show.frame_camera(Vector3(-0.8, 1.58, -1.25), Vector3(-0.8, 1.5, 0), 30.0)
	await p.frames(2)
	await p.screenshot("faces_a")
	show.frame_camera(Vector3(0.8, 1.55, -1.25), Vector3(0.8, 1.48, 0), 30.0)
	await p.frames(2)
	await p.screenshot("faces_b")


func _cfgs(presets: Array, extra: Dictionary) -> Array:
	var out: Array = []
	for pr: StringName in presets:
		var c := {"preset": pr}
		c.merge(extra)
		out.append(c)
	return out


func _row(p: Playtest, show: CharacterShowcase, cfgs: Array, shot: String) -> void:
	show.clear_rigs()
	await p.frames(1)
	var n := cfgs.size()
	var spacing := 0.95
	for i in n:
		show.spawn(cfgs[i], Vector3((float(i) - (n - 1) * 0.5) * spacing, 0, 0))
	show.run_for(0.8)
	var dist := 1.6 + float(n) * 1.15
	show.frame_camera(Vector3(0, 1.15, -dist), Vector3(0, 0.92, 0), 36.0)
	await p.frames(2)
	await p.screenshot(shot)
	p.check(show.rigs.size() == n, "%s: %d rigs built" % [shot, n])
