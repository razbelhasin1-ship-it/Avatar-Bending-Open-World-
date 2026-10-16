extends RefCounted
## Settlements II inside the real game: a new Earth game (arrival flight over Ba Sing Se's palace
## onto the Upper Ring) and a new Fire game (flight over the Fire Lord's palace onto the Palace
## Terrace), through the world scene and its WorldHooks. Checks that the hook streams the city,
## the spawn stands on real ground inside it (no safety floor), and that the player can walk.
## ELEMENT=earth|fire (default both).


func run(p: Playtest) -> void:
	var only := OS.get_environment("ELEMENT")
	for el: StringName in [&"earth", &"fire"]:
		if only != "" and only != String(el):
			continue
		await _game(p, ElementDefs.from_id(el), String(el))


func _game(p: Playtest, e: int, el: String) -> void:
	GameState.new_game(e)
	var t0 := Time.get_ticks_msec()
	var w := await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": e}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready, 300.0)
	p.check(ok, "%s world ready (%.1f s, %s)" % [el, (Time.get_ticks_msec() - t0) / 1000.0, str(w.load_report)])
	if not ok:
		return
	var sid := Settlements.BA_SING_SE if e == ElementDefs.Element.EARTH else Settlements.FN_CAPITAL
	p.check(w.content != null and w.content.get_provider(StringName("settlement_%s" % sid)) != null, "%s: the hook streams %s" % [el, sid])
	p.check(w.content.get_provider(StringName("settlement_far_%s" % sid)) != null, "%s: and its far silhouettes" % el)
	p.check(not bool(w.load_report.get("safety_floor", false)), "%s: spawned on real ground" % el)
	if w.arrival:
		var arr := w.arrival
		for s: Array in [[0.3, "a"], [0.55, "b"], [0.75, "c"], [0.92, "d"]]:
			await p.wait_until(func() -> bool: return not is_instance_valid(arr) or arr.time >= arr.duration * float(s[0]), 60.0)
			if is_instance_valid(arr):
				await p.screenshot("settlements_ef_world_%s_arrival_%s" % [el, s[1]])
	await p.wait_until(func() -> bool: return w.playing, 60.0)
	p.check(w.playing, "%s: control handed to the player" % el)
	var pl := w.player
	await p.wait_game(0.5)
	p.check(pl.is_on_floor(), "%s: the player stands on the floor at %s" % [el, pl.global_position])
	p.note("%s: spawn district %s (%s)" % [el, Settlements.district_at(pl.global_position), Settlements.settlement_at(pl.global_position)])
	p.check(Settlements.settlement_at(pl.global_position) == sid, "%s: spawned inside %s" % [el, sid])
	await p.screenshot("settlements_ef_world_%s_gameplay" % el)
	var start := pl.global_position
	Input.action_press(&"move_forward")
	await p.wait_game(2.0)
	Input.action_release(&"move_forward")
	await p.wait_game(0.3)
	var moved := pl.global_position.distance_to(start)
	p.check(moved > 4.0, "%s: walked %.1f m from the spawn" % [el, moved])
	await p.screenshot("settlements_ef_world_%s_walked" % el)
