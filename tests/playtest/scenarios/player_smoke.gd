extends RefCounted
## Quick smoke run of the combat arena: spawn, walk, jump, light combo, heavy,
## technique. ELEMENT=air|earth|fire|water (default fire).


func run(p: Playtest) -> void:
	var e := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT"))) if OS.get_environment("ELEMENT") != "" else ElementDefs.Element.FIRE
	var arena: Node = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e})
	await p.wait_game(0.8)
	var pl := p.player() as PlayerCharacter
	p.check(pl != null, "player spawned")
	await p.screenshot("smoke_00_spawn")
	p.hold(&"move_forward")
	await p.wait_game(1.0)
	await p.screenshot("smoke_01_run")
	p.release(&"move_forward")
	await p.tap(&"jump")
	await p.wait_game(0.3)
	await p.screenshot("smoke_02_jump")
	await p.wait_game(1.0)
	for i in 4:
		await p.tap(&"attack_light")
		await p.wait_game(0.08)
		await p.screenshot("smoke_03_light_%d" % i)
		await p.wait_game(0.15)
	await p.wait_game(0.6)
	p.note("before heavy: pos %s state %s" % [pl.global_position, pl.get_state_name()])
	p.hold(&"attack_heavy")
	await p.wait_game(0.8)
	await p.screenshot("smoke_04_charge")
	p.release(&"attack_heavy")
	await p.wait_game(0.25)
	await p.screenshot("smoke_05_release")
	for i in 5:
		await p.wait_game(0.2)
		p.note("after heavy: pos %s vel %s state %s" % [pl.global_position, pl.velocity, pl.get_state_name()])
	await p.tap(&"ability_1")
	await p.wait_game(0.5)
	p.note("after tech: pos %s state %s cam %s" % [pl.global_position, pl.get_state_name(), pl.camera_rig.global_position])
	await p.screenshot("smoke_06_technique")
	await p.wait_game(1.0)
	await p.screenshot("smoke_07_after")
	var hits := 0
	for d in (arena as Node).get("dummies"):
		hits += (d as TrainingDummy).hits_taken
	p.note("dummy hits: %d, state %s" % [hits, pl.get_state_name()])
	p.check(hits > 0, "dummies were hit")
