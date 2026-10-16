extends RefCounted
## Arrival cinematic per element (fast iteration on the flight / title / settle):
## loads the world as a new game, screenshots the flight at fixed fractions, the title card,
## the settle and the first gameplay frame, then checks control returned.
## ELEMENT=air|earth|fire|water (default: all four).

var p: Playtest


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("ELEMENT")
	var elements: Array[int] = []
	if only != "":
		elements.append(ElementDefs.from_id(StringName(only)))
	else:
		elements.assign(ElementDefs.ALL)
	for e in elements:
		await _arrival(e)


func _arrival(e: int) -> void:
	var el := String(ElementDefs.id_of(e))
	GameState.new_game(e)
	var t0 := Time.get_ticks_msec()
	var w := await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": e}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready, 240.0)
	p.check(ok, "%s world ready (%.1f s, %s)" % [el, (Time.get_ticks_msec() - t0) / 1000.0, str(w.load_report)])
	p.check(w.arrival != null, "%s arrival cinematic runs" % el)
	if w.arrival == null:
		return
	var arr := w.arrival
	var shots := [[0.04, "a_start"], [0.3, "b_title"], [0.6, "c_glide"], [0.9, "d_descend"]]
	for s: Array in shots:
		await p.wait_until(func() -> bool: return not is_instance_valid(arr) or arr.time >= arr.duration * float(s[0]), 60.0)
		if is_instance_valid(arr):
			await p.screenshot("%s_%s" % [el, s[1]])
	await p.wait_until(func() -> bool: return w.playing, 60.0)
	p.check(w.playing, "%s control handed to the player" % el)
	await p.wait_game(0.3)
	await p.screenshot("%s_e_gameplay" % el)
	var pl := w.player
	p.check(pl.get_viewport().get_camera_3d() == pl.camera_rig.camera, "%s player camera is current" % el)
	p.check(pl.get_state() == PlayerCharacter.State.LOCOMOTION, "%s player in locomotion (%s)" % [el, pl.get_state_name()])
	p.check(GameState.intro_done, "%s intro_done set" % el)
	p.check(w.overlay.bar_amount() < 0.05, "%s letterbox gone" % el)
	# move + a light strike
	Input.action_press(&"move_forward")
	await p.wait_game(1.2)
	Input.action_release(&"move_forward")
	Input.action_press(&"attack_light")
	await p.wait_game(0.08)
	Input.action_release(&"attack_light")
	await p.wait_game(0.25)
	await p.screenshot("%s_f_attack" % el)
	var moved := pl.global_position.distance_to(WorldData.get_spawn(e).origin)
	p.check(moved > 2.0, "%s moved %.1f m" % [el, moved])
