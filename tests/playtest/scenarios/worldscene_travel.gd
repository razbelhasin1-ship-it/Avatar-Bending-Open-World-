extends RefCounted
## Travel and safety in the real world: the ferry landing at the Water Tribe harbor (moored
## ferry, interact prompt), the destination choice through the dialogue box (number key), the
## sailing interlude (cast off, open water, arrival glide), arrival on the Northreach quay;
## then death -> respawn at the nearest safe point with 50 % health, and travel_to.
## FROM=port id, TO=port id override the ferry line.

var p: Playtest


func run(pt: Playtest) -> void:
	p = pt
	var from := StringName(OS.get_environment("FROM")) if OS.get_environment("FROM") != "" else &"port_water_tribe"
	var to := StringName(OS.get_environment("TO")) if OS.get_environment("TO") != "" else &"port_northreach"
	var port := TravelSystem.port_by_id(from)
	GameState.new_game(ElementDefs.Element.WATER)
	GameState.intro_done = true
	GameState.time_of_day = 11.0
	# stand on the landing, facing the water (the moored ferry in view)
	var quay: Vector3 = port["quay"]
	var spawn := Transform3D(Basis(Vector3.UP, float(port["yaw"])), quay + Vector3(0, 0.2, 0))
	var w := await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 240.0)
	p.check(ok, "world ready at %s %s" % [from, str(w.load_report)])
	var pl := w.player
	pl.camera_rig.pitch = deg_to_rad(4.0)
	await p.wait_game(1.0)
	await p.screenshot("1_dock")
	var dock: FerryDock = w.travel.docks.get(from)
	p.check(dock != null, "dock built at %s" % from)
	# walk up to the signpost until the prompt shows
	var prompt_seen := {"v": false}
	var cb := func(text: String, visible: bool) -> void:
		if visible and text.contains("ferry"):
			prompt_seen["v"] = true
	Events.interaction_prompt.connect(cb)
	var post := dock.interactable.global_position
	pl.teleport(Transform3D(Basis(Vector3.UP, atan2(-(post - quay).x, -(post - quay).z)), quay + (post - quay) * 0.2))
	await p.wait_game(0.6)
	ok = await p.wait_until(func() -> bool: return pl.interaction.current == dock.interactable, 5.0)
	p.check(ok and prompt_seen["v"], "ferry prompt shown")
	await p.screenshot("2_prompt")
	Input.action_press(&"interact")
	await p.wait_game(0.08)
	Input.action_release(&"interact")
	ok = await p.wait_until(func() -> bool: return w.is_dialogue_open() and w.dialogue.choices.size() > 0, 10.0)
	p.check(ok, "destination choice open")
	await p.wait(0.4)
	await p.screenshot("3_choice")
	var routes := TravelSystem.routes_from(from)
	var idx := -1
	for i in routes.size():
		if routes[i]["to"] == to:
			idx = i
	p.check(idx >= 0, "route %s -> %s offered" % [from, to])
	var key := InputEventKey.new()
	key.physical_keycode = (KEY_1 + idx) as Key
	key.keycode = key.physical_keycode
	key.pressed = true
	Input.parse_input_event(key)
	ok = await p.wait_until(func() -> bool: return w.travel.phase == &"depart" and not w.fader.is_black() and w.fader.amount() < 0.3, 20.0)
	p.check(ok, "sailing out")
	await p.wait(0.6)
	await p.screenshot("4_depart")
	await p.wait_until(func() -> bool: return w.travel.phase != &"depart" or w.travel._s > TravelSystem.SAIL_OUT_DIST * 0.7, 20.0)
	await p.screenshot("5_depart_late")
	await p.wait_until(func() -> bool: return w.travel.phase == &"transit", 20.0)
	await p.screenshot("6_transit")
	await p.wait_until(func() -> bool: return w.travel.phase == &"arrive" and w.fader.amount() < 0.2, 60.0)
	await p.wait(0.4)
	await p.screenshot("7_arrive")
	ok = await p.wait_until(func() -> bool: return not w.travel.busy, 60.0)
	p.check(ok, "trip finished")
	await p.wait_game(0.5)
	var dest := TravelSystem.quay_transform(TravelSystem.port_by_id(to))
	p.check(pl.global_position.distance_to(dest.origin) < 2.5, "on the %s quay (%.1f m)" % [to, pl.global_position.distance_to(dest.origin)])
	p.check(pl.get_state() == PlayerCharacter.State.LOCOMOTION, "control back (%s)" % pl.get_state_name())
	await p.screenshot("8_arrived")
	Events.interaction_prompt.disconnect(cb)
	# death -> respawn
	var spawn_home := WorldData.get_spawn(ElementDefs.Element.WATER)
	var rp := w.respawn.respawn_point(pl.global_position)
	pl.die(null)
	await p.wait_game(1.0)
	await p.screenshot("9_dead")
	ok = await p.wait_until(func() -> bool: return pl.is_alive() and not w.respawn.busy and w.fader.amount() < 0.05, 30.0)
	p.check(ok, "respawned")
	p.check(absf(pl.health.ratio() - 0.5) < 0.02, "50 %% health (%.2f)" % pl.health.ratio())
	p.check(pl.global_position.distance_to(rp.origin) < 3.0, "at the nearest safe point (%.1f m; home spawn %.0f m away)" % [pl.global_position.distance_to(rp.origin), pl.global_position.distance_to(spawn_home.origin)])
	await p.wait_game(0.5)
	await p.screenshot("10_respawned")
	# fast travel to the Water Tribe palace tier
	ok = await w.travel.travel_to(spawn_home, {"text": "Travelling home"})
	p.check(ok and pl.global_position.distance_to(spawn_home.origin) < 2.0, "travel_to home")
	await p.wait_game(0.5)
	await p.screenshot("11_travel_to")
