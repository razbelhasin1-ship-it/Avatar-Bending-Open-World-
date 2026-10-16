extends RefCounted
## Quick look at a home city through the real world scene: crowd + named NPCs around the spawn,
## the opening quest started, talking to the first quest giver (dialogue camera), a vantage shot.
## ELEMENT=water|earth|fire|air (default water), HOUR=11.0, PREFIX=quests_npcs_city.

var p: Playtest
var w: WorldScene


func run(pt: Playtest) -> void:
	p = pt
	var el := OS.get_environment("ELEMENT")
	if el == "":
		el = "water"
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 11.0
	var prefix := OS.get_environment("PREFIX") if OS.get_environment("PREFIX") != "" else "quests_npcs_city"
	var e := ElementDefs.from_id(StringName(el))
	GameState.new_game(e)
	GameState.intro_done = true
	var t0 := Time.get_ticks_msec()
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": e, "skip_intro": true, "time_of_day": hour}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 300.0)
	p.check(ok, "%s world ready (%.1f s)" % [el, (Time.get_ticks_msec() - t0) / 1000.0])
	if not ok:
		return
	var dir := _director()
	p.check(dir != null, "NPC director installed")
	await p.wait_game(3.0)
	await p.wait_until(func() -> bool: return dir.live_count() >= 4, 40.0)
	p.note("records %d, live %d (budget %d)" % [dir.record_count(), dir.live_count(), dir.max_npcs])
	p.check(dir.live_count() >= 4, "townsfolk around the spawn: %d" % dir.live_count())
	var first: StringName = {&"water": &"wt_anaaya", &"earth": &"ek_lin", &"fire": &"fn_kaida", &"air": &"at_pasang"}.get(StringName(el), &"")
	var q1: StringName = {&"water": &"wt_born_of_the_tide", &"earth": &"ek_stone_beneath_the_sky", &"fire": &"fn_a_spark_returns", &"air": &"at_first_breath"}.get(StringName(el), &"")
	p.check(Quests.is_active(q1), "opening quest %s started" % q1)
	await p.wait_game(1.0)
	await p.screenshot("%s_%s_spawn" % [prefix, el])
	# turn around to see the other side of the plaza
	w.player.camera_rig.snap_behind(w.player)
	for i in 6:
		p.look(-120, 0)
		await p.wait_game(0.05)
	await p.wait_game(0.6)
	await p.screenshot("%s_%s_spawn_back" % [prefix, el])
	var npc := NpcRegistry.live_npc(first)
	p.check(npc != null, "quest giver %s spawned" % first)
	if npc != null:
		await _talk(npc, prefix + "_" + el)
	await _vantage(prefix + "_" + el)
	if OS.get_environment("TOUR") != "0":
		var sid: StringName = {&"water": &"northern_water_tribe", &"earth": &"ba_sing_se", &"fire": &"fire_nation_capital", &"air": &"southern_air_temple"}.get(StringName(el), &"")
		for kind: StringName in [&"market_stall", &"guard_post", &"child_play"]:
			await _visit(sid, kind, "%s_%s_%s" % [prefix, el, kind])


## Fast-travels to the anchor of `kind` nearest the spawn that has people around it, looks at it.
func _visit(sid: StringName, kind: StringName, shot: String) -> void:
	var sp := WorldData.get_spawn(w.element).origin
	var best := {}
	var bd := INF
	for a in Settlements.get_anchors(sid, kind):
		if bool(a.get("interior", false)):
			continue
		var d := (a["position"] as Vector3).distance_to(sp)
		if d < bd:
			bd = d
			best = a
	if best.is_empty():
		p.note("no %s anchor in %s" % [kind, sid])
		return
	var at: Vector3 = best["position"]
	var fwd := Basis(Vector3.UP, float(best.get("yaw", 0.0))) * Vector3.FORWARD
	var stand := at + fwd * 7.0
	var d2 := at - stand
	var ok: bool = await w.travel.travel_to(Transform3D(Basis(Vector3.UP, atan2(-d2.x, -d2.z)), stand), {"text": "", "autosave": false})
	p.check(ok, "travelled to a %s" % kind)
	await p.wait_game(1.0)
	var q := PhysicsRayQueryParameters3D.create(w.player.global_position + Vector3(0, 1.5, 0), at + Vector3(0, 1.5, 0), Layers.SOLID)
	if not w.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		# planners differ on which way an anchor faces: try the other side
		stand = at - fwd * 7.0
		d2 = at - stand
		await w.travel.travel_to(Transform3D(Basis(Vector3.UP, atan2(-d2.x, -d2.z)), stand), {"text": "", "autosave": false})
		p.note("%s: viewed from the other side" % kind)
	await p.wait_game(3.0)
	var dir := _director()
	var near := 0
	for n in dir.live_npcs():
		if n.global_position.distance_to(at) < 25.0:
			near += 1
	p.note("%s: %d NPCs within 25 m, %d live" % [kind, near, dir.live_count()])
	p.check(near >= 1, "people at the %s (%d)" % [kind, near])
	# an elevated observer view of the spot from the player's side (pulled in before walls)
	var cam := Camera3D.new()
	w.add_child(cam)
	var side := w.player.global_position - at
	side.y = 0.0
	side = side.normalized() if side.length() > 0.5 else -fwd
	var focus := at + Vector3(0, 1.2, 0)
	var eye := at + side * 11.0 + Vector3(0, 6.5, 0)
	var hit := w.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(focus, eye, Layers.CAMERA_BLOCKERS))
	if not hit.is_empty():
		eye = focus.lerp(hit["position"], 0.85)
	cam.global_transform = Transform3D(Basis.looking_at(focus - eye, Vector3.UP), eye)
	cam.fov = 60.0
	cam.make_current()
	await p.wait_game(0.5)
	await p.screenshot(shot)
	w.player.camera_rig.make_current()
	cam.queue_free()


func _director() -> NpcDirector:
	for h in w.hooks:
		if h.get("director") is NpcDirector:
			return h.get("director")
	return null


## Walks up to the NPC (teleport next to it), interacts, screenshots, advances to the end.
func _talk(npc: NpcCharacter, prefix: String) -> void:
	var pl := w.player
	var to := npc.global_position + (-npc.global_basis.z) * 1.8
	pl.teleport(Transform3D(Basis(Vector3.UP, npc.rotation.y + PI), to))
	await p.wait_game(0.6)
	var runner := _director().runner
	await p.tap(&"interact")
	var started := await p.wait_until(func() -> bool: return runner.busy, 5.0)
	p.check(started, "conversation started with %s" % npc.display_name())
	await p.wait_game(1.2)
	await p.screenshot("%s_talk_a" % prefix)
	var guard := 0
	while runner.busy and guard < 30:
		guard += 1
		var box: DialogueBox = w.dialogue
		if box.choices.size() > 0:
			box.choose(0)
		else:
			box.advance()
			box.advance()
		await p.wait_game(0.5)
		if guard == 2:
			await p.screenshot("%s_talk_b" % prefix)
	p.check(not runner.busy, "conversation finished (%d lines)" % runner.transcript.size())
	for l: Array in runner.transcript:
		p.note("  %s: %s" % [l[0], l[1]])


func _vantage(prefix: String) -> void:
	var pl := w.player
	var cam := Camera3D.new()
	w.add_child(cam)
	var at := pl.global_position + Vector3(0, 9, 0) + pl.global_basis.z * 12.0
	cam.global_transform = Transform3D(Basis.looking_at(pl.global_position - at + Vector3(0, -1.5, 0) + (-pl.global_basis.z) * 14.0, Vector3.UP), at)
	cam.make_current()
	await p.wait_game(0.5)
	await p.screenshot("%s_vantage" % prefix)
	pl.camera_rig.make_current()
	cam.queue_free()
