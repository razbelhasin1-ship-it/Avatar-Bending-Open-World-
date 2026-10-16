extends TestCase
## World scene module (worldscene): spawns and arrival paths per element, region director
## hysteresis + first visits + POI discovery, respawn points, ferry routes and travel, save
## consistency, the playable World scene end to end (headless) incl. clean exits and module
## hooks, and the training grounds (sites, steps, director).

const WORLD := "res://scenes/world/world.tscn"
const TUTORIAL := "res://scenes/world/tutorial.tscn"
const HOOK_PATH := "user://test_worldscene_hook.gd"

## Real save files are kept aside while these tests save (and restored afterwards).
var _slots: Dictionary = {}


func before_each() -> void:
	WorldData.load_world()
	GameState.reset()
	_slots.clear()
	for i in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(i):
			_slots[i] = FileAccess.get_file_as_string(SaveSystem.slot_path(i))
			SaveSystem.delete_save(i)


func after_each() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
		if _slots.has(i):
			var f := FileAccess.open(SaveSystem.slot_path(i), FileAccess.WRITE)
			f.store_string(String(_slots[i]))
			f.close()
	GameState.reset()
	Engine.time_scale = 1.0
	get_tree().paused = false
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)


## Instantiates a playable scene with options and waits until it is ready (or timeout).
func _load(path: String, opts: Dictionary, timeout: float = 90.0) -> PlayableScene:
	var w := (load(path) as PackedScene).instantiate() as PlayableScene
	w.options = opts
	add_child(w)
	var t0 := Time.get_ticks_msec()
	while not w.is_ready and Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		await get_tree().process_frame
	return w


func _free(w: Node) -> void:
	if is_instance_valid(w):
		w.queue_free()
	await frames(3)


func _wait_until(cond: Callable, timeout: float = 10.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


# --- data: spawns, arrival paths, training sites, ferries ----------------------------------------------

func test_spawns_arrivals_and_sites_per_element() -> void:
	if not expect(WorldData.has_world_data(), "world data present"):
		return
	for e in ElementDefs.ALL:
		var home := StringName(ElementDefs.get_data(e)["home_region"])
		var s := WorldData.get_spawn(e)
		expect_eq(WorldData.get_region(s.origin.x, s.origin.z), home, "%s spawn in the home region" % ElementDefs.id_of(e))
		var path := ArrivalCinematic.path_for(e, s)
		expect(not path.is_empty(), "%s arrival path" % ElementDefs.id_of(e))
		var end: Transform3D = path["end"]
		expect(end.origin.distance_to(s.origin) < 15.0, "%s arrival ends behind the player (%.1f m)" % [ElementDefs.id_of(e), end.origin.distance_to(s.origin)])
		var site := TrainingGround.site(e)
		expect(site["poi"] != &"", "%s training site" % ElementDefs.id_of(e))
		expect_eq(site["region"], home, "%s training site in the home region" % ElementDefs.id_of(e))
		# the sparring circle sits on flattened ground
		var c: Vector3 = (site["xform"] as Transform3D).origin
		var worst := 0.0
		for k in 24:
			var a := TAU * k / 24.0
			worst = maxf(worst, absf(WorldData.get_height(c.x + cos(a) * TrainingGround.RING, c.z + sin(a) * TrainingGround.RING) - c.y))
		expect(worst < 1.0, "%s training circle is flat (%.2f m)" % [ElementDefs.id_of(e), worst])


func test_ferry_routes_and_polylines() -> void:
	if not WorldData.has_world_data():
		return
	var ports := WorldData.get_ports()
	expect(ports.size() >= 4, "ports present")
	var with_routes := 0
	for port: Dictionary in ports:
		var routes := TravelSystem.routes_from(StringName(port["id"]))
		if routes.is_empty():
			continue
		with_routes += 1
		var berth: Vector3 = port["berth"]
		for r in routes:
			var pts: PackedVector2Array = r["points"]
			expect(pts[0].distance_to(Vector2(berth.x, berth.z)) < 1.0, "route %s leaves from %s's berth" % [r["ferry"], port["id"]])
			var to := TravelSystem.port_by_id(r["to"])
			var tb: Vector3 = to["berth"]
			expect(pts[pts.size() - 1].distance_to(Vector2(tb.x, tb.z)) < 1.0, "route %s arrives at %s's berth" % [r["ferry"], r["to"]])
			# back route exists
			expect(not TravelSystem.route_between(r["to"], StringName(port["id"])).is_empty(), "route %s is two-way" % r["ferry"])
		var q := TravelSystem.quay_transform(port)
		var f := -q.basis.z
		var to_berth := Vector3(berth.x - q.origin.x, 0, berth.z - q.origin.z).normalized()
		expect(f.dot(to_berth) < 0.0, "%s quay transform faces inland" % port["id"])
	expect(with_routes >= 4, "ferry ports (%d)" % with_routes)
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	expect_near(TravelSystem.polyline_length(line), 20.0, 1e-4, "length")
	expect(TravelSystem.polyline_point(line, 0.0).distance_to(Vector2(0, 0)) < 1e-4, "start")
	expect(TravelSystem.polyline_point(line, 15.0).distance_to(Vector2(10, 5)) < 1e-4, "middle of the 2nd segment")
	expect(TravelSystem.polyline_point(line, 99.0).distance_to(Vector2(10, 10)) < 1e-4, "clamped end")
	expect_near(TravelSystem.polyline_dir(line, 2.0).length(), 1.0, 1e-4, "unit direction")


# --- region director --------------------------------------------------------------------------------------

func test_region_director_hysteresis_and_first_visits() -> void:
	var rd := RegionDirector.new()
	add_child(rd)
	var marker := Node3D.new()
	add_child(marker)
	rd.target = marker
	rd.discover_pois = false
	var answer := {"r": &"water_tribe"}
	rd.region_provider = func(_x: float, _z: float) -> StringName: return answer["r"]
	rd.can_autosave = func() -> bool: return false
	var entered: Array = []
	var cb := func(r: StringName) -> void: entered.append(r)
	Events.region_entered.connect(cb)
	rd.start(&"water_tribe", false)
	expect_eq(rd.current_region, &"water_tribe", "initial region")
	expect(RegionDirector.is_visited(&"water_tribe"), "home marked visited")
	# flicker across a border never switches
	for i in 6:
		rd.step_region(&"wilds" if i % 2 == 0 else &"water_tribe", 0.5)
	expect_eq(rd.current_region, &"water_tribe", "flicker ignored")
	# a sustained change switches after HOLD_TIME
	var n := 0
	while rd.current_region == &"water_tribe" and n < 20:
		rd.step_region(&"wilds", 0.25)
		n += 1
	expect_eq(rd.current_region, &"wilds", "switched")
	expect_near(n * 0.25, RegionDirector.HOLD_TIME, 0.26, "after the hold time")
	expect(RegionDirector.is_visited(&"wilds"), "first visit recorded")
	expect_eq(GameState.region, &"wilds", "GameState.region follows")
	expect_eq(rd.saves_made, 0, "autosave vetoed by the world")
	expect_eq(entered, [&"water_tribe", &"wilds"], "region_entered once per region")
	expect(not RegionDirector.mark_visited(&"wilds"), "visited only once")
	Events.region_entered.disconnect(cb)
	rd.queue_free()
	marker.queue_free()


func test_poi_discovery_grants_xp_once() -> void:
	if not WorldData.has_world_data():
		return
	GameState.new_game(ElementDefs.Element.WATER)
	var rd := RegionDirector.new()
	add_child(rd)
	var poi := WorldData.get_poi(&"wt_moon_shrine")
	expect(not poi.is_empty(), "shrine exists")
	var toasts: Array = []
	var cb := func(text: String, kind: StringName) -> void: toasts.append([text, kind])
	Events.notify.connect(cb)
	var xp0 := GameState.xp + GameState.level * 100000
	var found := rd.check_pois(poi["position"])
	expect(found >= 1, "found the shrine (%d)" % found)
	expect(GameState.discovered_pois.has("wt_moon_shrine"), "discovered")
	expect(GameState.xp + GameState.level * 100000 > xp0, "xp granted")
	expect(toasts.any(func(t: Array) -> bool: return t[1] == &"discovery"), "discovery toast")
	expect_eq(rd.check_pois(poi["position"]), 0, "not twice")
	var far: Vector3 = poi["position"] + Vector3(400, 0, 0)
	expect_eq(rd.check_pois(far), 0, "nothing far away")
	Events.notify.disconnect(cb)
	rd.queue_free()


func test_respawn_points() -> void:
	if not WorldData.has_world_data():
		return
	GameState.new_game(ElementDefs.Element.WATER)
	var rs := RespawnSystem.new()
	add_child(rs)
	var home := WorldData.get_spawn(ElementDefs.Element.WATER)
	var shrine: Vector3 = WorldData.get_poi(&"wt_moon_shrine")["position"]
	var near_shrine := shrine + Vector3(30, 0, 30)
	expect(rs.respawn_point(near_shrine).origin.distance_to(home.origin) < 1.0, "undiscovered shrine -> home spawn")
	GameState.discover_poi(&"wt_moon_shrine")
	var rp := rs.respawn_point(near_shrine)
	expect(rp.origin.distance_to(shrine) < 40.0, "discovered shrine is the nearest safe point (%.1f m)" % rp.origin.distance_to(shrine))
	expect(WorldData.get_water_height(rp.origin.x, rp.origin.z) < rp.origin.y - 0.2, "dry ground")
	expect(rs.respawn_point(home.origin + Vector3(5, 0, 5)).origin.distance_to(home.origin) < 1.0, "home stays nearest at home")
	# visited capitals count too
	var fire := WorldData.get_spawn(ElementDefs.Element.FIRE)
	expect(rs.respawn_point(fire.origin).origin.distance_to(fire.origin) > 100.0, "unvisited capital is not a respawn point")
	RegionDirector.mark_visited(&"fire_nation")
	expect(rs.respawn_point(fire.origin).origin.distance_to(fire.origin) < 1.0, "visited capital is")
	rs.queue_free()


# --- the playable world ------------------------------------------------------------------------------------

func test_world_new_game_spawns_on_ground() -> void:
	GameState.new_game(ElementDefs.Element.FIRE)
	var w := await _load(WORLD, {"new_game": true, "skip_intro": true, "no_content": true}) as WorldScene
	if not expect(w.is_ready, "world became ready"):
		await _free(w)
		return
	await physics_frames(30)
	var p := w.player
	expect(p != null, "player spawned")
	var spawn := WorldData.get_spawn(ElementDefs.Element.FIRE)
	expect(p.global_position.distance_to(spawn.origin) < 1.5, "at the fire spawn (%s vs %s)" % [p.global_position, spawn.origin])
	expect(p.motor.on_floor, "standing on the ground")
	expect(absf(p.global_position.y - WorldData.get_height(p.global_position.x, p.global_position.z)) < 0.4, "on the terrain")
	expect(not w.load_report.get("safety_floor", true), "no safety floor needed")
	expect(w.hud.player == p and w.hud.visible, "HUD bound and shown")
	expect(w.playing, "playing (no intro)")
	expect_eq(w.region_director.current_region, &"fire_nation", "home region tracked")
	# The companions module's hook (when installed) spawns the element's companion.
	expect(w.hud.companion_panel.visible == (p.get_companion() != null), "companion panel shown exactly when a companion exists")
	expect(w.travel.docks.size() >= 4, "ferry docks built (%d)" % w.travel.docks.size())
	expect(SaveSystem.can_save(), "saving allowed in the world")
	await _free(w)


func test_continue_restores_position_time_health() -> void:
	if not WorldData.has_world_data():
		return
	GameState.new_game(ElementDefs.Element.EARTH)
	GameState.intro_done = true
	var pos := Vector3(860.0, 0.0, 440.0)   # Millet Hollow outskirts
	pos.y = WorldData.get_height(pos.x, pos.z) + 0.05
	GameState.player_position = pos
	GameState.player_yaw = 1.2
	GameState.player_health_ratio = 0.6
	GameState.time_of_day = 13.25
	GameState.equipped_abilities = [&"earth_wall", &"", &"", &""] as Array[StringName]
	GameState.unlocked_abilities = [&"earth_wall"] as Array[StringName]
	var w := await _load(WORLD, {"new_game": false, "no_content": true}) as WorldScene
	if not expect(w.is_ready and w.playing, "continued world ready and playing"):
		await _free(w)
		return
	await physics_frames(10)
	var p := w.player
	expect(w.arrival == null, "no arrival on continue")
	expect(p.global_position.distance_to(pos) < 0.6, "restored position (%.2f m)" % p.global_position.distance_to(pos))
	expect(absf(wrapf(p.motor.yaw - 1.2, -PI, PI)) < 0.05, "restored yaw")
	expect_near(p.health.ratio(), 0.6, 0.02, "restored health")
	expect_near(w.renderer.get_time_of_day(), 13.25, 0.05, "restored hour")
	expect_eq(p.controller.get_slot_def(&"technique_1").id, &"earth_wall", "restored abilities")
	await _free(w)


func test_arrival_cinematic_plays_and_skips() -> void:
	GameState.new_game(ElementDefs.Element.AIR)
	var w := await _load(WORLD, {"new_game": true, "no_content": true}) as WorldScene
	if not expect(w.is_ready and w.arrival != null, "arrival running"):
		await _free(w)
		return
	var arr := w.arrival
	expect(w.get_viewport().get_camera_3d() == arr.camera, "cinematic camera current")
	expect(w.player.get_state() == PlayerCharacter.State.CINEMATIC, "player held during the arrival")
	expect(not w.hud.visible and w.overlay.bar_amount() > 0.95, "HUD hidden, letterboxed")
	expect(not w.playing, "not playing yet")
	await _wait_until(func() -> bool: return arr.time > 0.8, 20.0)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := ev.duplicate() as InputEventKey
	ev2.pressed = false
	Input.parse_input_event(ev2)
	var ok := await _wait_until(func() -> bool: return w.playing, 5.0)
	expect(ok, "any key skips to gameplay")
	expect(GameState.intro_done, "intro_done")
	expect(w.get_viewport().get_camera_3d() == w.player.camera_rig.camera, "player camera current")
	expect(w.player.get_state() == PlayerCharacter.State.LOCOMOTION, "control returned (%s)" % w.player.get_state_name())
	expect(RegionDirector.is_visited(&"air_temple"), "home region visited (its title was the arrival)")
	expect(SaveSystem.has_save(SaveSystem.AUTOSAVE_SLOT) or not SaveSystem.can_save(), "journey autosaved after the arrival")
	await _free(w)
	SaveSystem.delete_save(SaveSystem.AUTOSAVE_SLOT)


func test_death_respawns_at_safe_point_with_half_health() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	var w := await _load(WORLD, {"new_game": true, "skip_intro": true, "no_content": true}) as WorldScene
	if not expect(w.is_ready, "world ready"):
		await _free(w)
		return
	var p := w.player
	var xp0 := GameState.xp
	var home := WorldData.get_spawn(ElementDefs.Element.WATER)
	# wander off, then die
	p.teleport(Transform3D(Basis(), home.origin + Vector3(20, 0, 30)))
	await physics_frames(5)
	# lethal hit through the real combat path
	var hit := HitInfo.make(9999.0, null, ElementDefs.Element.FIRE, HitInfo.Reaction.KNOCKDOWN, Vector3.FORWARD, 2.0)
	hit.team = Combat.Team.ENEMY
	Combat.deal(p, hit)
	await physics_frames(2)
	expect(p.get_state() == PlayerCharacter.State.DEAD and not p.is_alive(), "dead")
	# a save taken while dead stores the respawn point, not the corpse
	SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT)
	expect(GameState.player_position.distance_to(home.origin) < 2.0, "save while dead points at the respawn (%s)" % GameState.player_position)
	var ok := await _wait_until(func() -> bool: return p.is_alive() and not w.respawn.busy, 15.0)
	expect(ok, "respawned")
	expect(w.respawn.deaths == 1, "one death handled by the world")
	expect_near(p.health.ratio(), 0.5, 0.02, "50 % health")
	expect(p.global_position.distance_to(home.origin) < 2.0, "at the home spawn (%.1f m)" % p.global_position.distance_to(home.origin))
	expect(p.get_state() == PlayerCharacter.State.LOCOMOTION, "control back")
	expect(GameState.xp == xp0, "no progress lost")
	await _free(w)
	SaveSystem.delete_save(SaveSystem.AUTOSAVE_SLOT)


func test_fall_out_of_world_is_rescued() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	var w := await _load(WORLD, {"new_game": true, "skip_intro": true, "no_content": true}) as WorldScene
	if not expect(w.is_ready, "world ready"):
		await _free(w)
		return
	var p := w.player
	await physics_frames(20)
	var safe := p.global_position
	expect_eq(w.respawn.needs_rescue(), &"", "fine on the ground")
	# far below the terrain with nothing under the body (the renderer's own net may win the race)
	p.global_position = safe + Vector3(0, -120, 0)
	expect_eq(w.respawn.needs_rescue(), &"fell", "detected as fallen out of the world")
	var ok := await _wait_until(func() -> bool: return p.global_position.distance_to(safe) < 6.0 and not w.respawn.busy, 10.0)
	expect(ok, "back on safe ground (%.1f m)" % p.global_position.distance_to(safe))
	# beyond the world's edge
	var r0 := w.respawn.rescues
	p.global_position = Vector3(4085.0, 2.0, safe.z)
	expect_eq(w.respawn.needs_rescue(), &"edge", "detected beyond the edge")
	ok = await _wait_until(func() -> bool: return w.respawn.rescues > r0 and not w.respawn.busy, 15.0)
	expect(ok and absf(p.global_position.x) < 4000.0, "turned back from the edge (x %.0f)" % p.global_position.x)
	expect(p.is_alive(), "alive")
	await _free(w)


func test_travel_to_and_ferry() -> void:
	if not WorldData.has_world_data():
		return
	GameState.new_game(ElementDefs.Element.WATER)
	var w := await _load(WORLD, {"new_game": true, "skip_intro": true, "no_content": true}) as WorldScene
	if not expect(w.is_ready, "world ready"):
		await _free(w)
		return
	var p := w.player
	var tr := w.travel
	tr.interlude_scale = 0.05
	# fast travel
	var target := Vector3(1200.0, 0.0, 360.0)
	target.y = WorldData.get_height(target.x, target.z)
	var ok: bool = await tr.travel_to(Transform3D(Basis(), target), {"fade": 0.05, "autosave": false})
	expect(ok, "travel_to succeeded")
	await physics_frames(20)
	expect(p.global_position.distance_to(target) < 1.0, "arrived (%.2f m)" % p.global_position.distance_to(target))
	expect(p.motor.on_floor, "standing on the destination ground")
	expect(not tr.busy and p.process_mode == Node.PROCESS_MODE_INHERIT, "travel finished cleanly")
	# ferry: Water Tribe Harbor -> Northreach Harbor
	var from := &"port_water_tribe"
	var to := &"port_northreach"
	var quay := TravelSystem.quay_transform(TravelSystem.port_by_id(from))
	await tr.travel_to(quay, {"fade": 0.05, "autosave": false})
	var finished: Array = []
	tr.travel_finished.connect(func(kind: StringName, at: Transform3D) -> void: finished.append([kind, at]))
	var phases: Array = []
	var rode := {"on_deck": false}
	var watch := func() -> void:
		if tr.phase != &"" and not phases.has(tr.phase):
			phases.append(tr.phase)
		if tr.phase == &"depart" and tr.boat and p.global_position.distance_to(tr.boat.passenger_transform().origin) < 0.6:
			rode["on_deck"] = true
	get_tree().physics_frame.connect(watch)
	ok = await tr.take_ferry(from, to)
	get_tree().physics_frame.disconnect(watch)
	expect(ok, "ferry trip completed")
	expect(phases == [&"depart", &"transit", &"arrive"], "interlude phases %s" % str(phases))
	expect(rode["on_deck"], "the player rode on the deck")
	var dest := TravelSystem.quay_transform(TravelSystem.port_by_id(to))
	await physics_frames(10)
	expect(p.global_position.distance_to(dest.origin) < 2.0, "at the destination quay (%.1f m)" % p.global_position.distance_to(dest.origin))
	expect(p.get_state() == PlayerCharacter.State.LOCOMOTION, "control back after the ferry (%s)" % p.get_state_name())
	expect(finished.size() == 1 and finished[0][0] == &"ferry", "travel_finished(ferry)")
	expect(w.get_viewport().get_camera_3d() == p.camera_rig.camera, "player camera current")
	expect(tr.boat == null and w.hud.visible and w.overlay.bar_amount() < 0.05, "interlude cleaned up")
	await _free(w)


func test_exit_leaves_no_duplicates_or_held_input() -> void:
	var counts: Array = []
	for r_i in 2:
		GameState.new_game(ElementDefs.Element.FIRE)
		var w := await _load(WORLD, {"new_game": true, "skip_intro": true, "no_content": true}) as WorldScene
		expect(w.is_ready, "round %d ready" % r_i)
		Input.action_press(&"move_forward")
		Input.action_press(&"block")
		await _free(w)
		await frames(3)
		expect(not Input.is_action_pressed(&"move_forward") and not Input.is_action_pressed(&"block"), "held actions released")
		expect(get_tree().get_nodes_in_group(&"player").is_empty(), "no player left")
		expect(get_tree().get_nodes_in_group(&"playable_scene").is_empty(), "no scene left")
		var c := {}
		for n in get_tree().root.get_children():
			var key := String(n.name).rstrip("0123456789@")
			c[key] = int(c.get(key, 0)) + 1
		expect(not c.has("LoadingOverlay"), "no loading overlay left")
		counts.append(c)
	expect_eq(counts[0], counts[1], "same root nodes after a second round trip")
	for k: String in counts[1]:
		expect(int(counts[1][k]) == 1 or k == "TestRunner" or k.begins_with("test_"), "single %s" % k)


func test_hooks_attach_companion() -> void:
	var src := """extends Node
var calls: Array = []
var scene_ref = null
func world_setup(scene) -> void:
	calls.append("setup")
	scene_ref = scene
func player_spawned(player) -> void:
	calls.append("spawned")
	var c := Node3D.new()
	c.name = "TestCompanion"
	scene_ref.spawn_companion(c, Transform3D(Basis(), player.global_position + Vector3(2, 0, 2)))
func world_ready() -> void:
	calls.append("ready")
"""
	var f := FileAccess.open(HOOK_PATH, FileAccess.WRITE)
	f.store_string(src)
	f.close()
	GameState.new_game(ElementDefs.Element.EARTH)
	var w := (load(WORLD) as PackedScene).instantiate() as WorldScene
	w.options = {"new_game": true, "skip_intro": true, "no_content": true}
	w.extra_hooks = [HOOK_PATH] as Array[String]
	add_child(w)
	await _wait_until(func() -> bool: return w.playing, 60.0)
	# Other modules' hooks (enemies, companions, ...) may be installed too: find this test's hook.
	var mine: Array = w.hooks.filter(func(h: Node) -> bool: return h.get("calls") != null)
	expect(mine.size() == 1, "hook installed")
	if mine.size() == 1:
		expect_eq(mine[0].get("calls"), ["setup", "spawned", "ready"], "hook lifecycle")
	expect(w.player.get_companion() != null and w.player.get_companion().name == "TestCompanion", "companion linked to the player")
	expect(w.hud.companion_panel.visible, "HUD companion panel shown")
	await _free(w)
	DirAccess.remove_absolute(HOOK_PATH)


# --- training grounds -----------------------------------------------------------------------------------------

func test_tutorial_steps_per_element() -> void:
	for e in ElementDefs.ALL:
		var steps := TutorialSteps.build(e, 3, false, "Technique")
		var kinds: Array = steps.map(func(s: Dictionary) -> StringName: return s["kind"])
		for k: StringName in [&"look", &"move", &"sprint", &"jump", &"dodge", &"light", &"heavy", &"charge", &"lockon", &"block", &"parry", &"technique"]:
			expect(kinds.has(k), "%s has %s" % [ElementDefs.id_of(e), k])
		expect(kinds.has(&"glide") == (e == ElementDefs.Element.AIR) and kinds.has(&"air_jump") == (e == ElementDefs.Element.AIR), "air-only steps")
		expect(not kinds.has(&"mount") and not kinds.has(&"companion_call"), "no companion steps without a companion")
		for s in steps:
			for dev: StringName in [&"kbm", &"pad", &"touch"]:
				var txt := TutorialSteps.text_for(s, dev)
				expect(not txt.is_empty() and not txt.contains("{"), "%s/%s text resolved: %s" % [s["id"], dev, txt])
	var with_c := TutorialSteps.build(ElementDefs.Element.EARTH, 3, true)
	expect(with_c.any(func(s: Dictionary) -> bool: return s["kind"] == &"mount"), "companion steps with a companion")
	# bindings follow rebinding
	var block := TutorialSteps.build(ElementDefs.Element.FIRE, 4, false).filter(func(s: Dictionary) -> bool: return s["kind"] == &"block")[0] as Dictionary
	expect(TutorialSteps.text_for(block, &"kbm").contains("Q"), "kbm label")
	expect(TutorialSteps.text_for(block, &"pad").contains("LT"), "pad label")


func test_tutorial_runs_lessons_and_never_saves() -> void:
	GameState.new_game(ElementDefs.Element.FIRE, true)
	SaveSystem.delete_save(SaveSystem.AUTOSAVE_SLOT)
	var t := await _load(TUTORIAL, {"element": ElementDefs.Element.FIRE, "no_content": true}) as TutorialScene
	if not expect(t.is_ready, "tutorial ready"):
		await _free(t)
		return
	await _wait_until(func() -> bool: return t.director != null and t.director.running, 20.0)
	var d := t.director
	expect(d.running and d.step_id() == &"look", "first lesson: look")
	expect(t.dummies.size() == 4 and t.bot != null and not t.bot.active, "targets placed, partner waiting")
	expect(not SaveSystem.can_save() and not t.pause_menu.can_save(), "saving disabled in the tutorial")
	# look: turn the camera through the real camera rig
	t.player.camera_rig.set_yaw(t.player.camera_rig.yaw + 1.4)
	await physics_frames(2)
	t.player.camera_rig.set_yaw(t.player.camera_rig.yaw + 1.4)
	var ok := await _wait_until(func() -> bool: return d.step_id() == &"move", 5.0)
	expect(ok and d.completed.has(&"look"), "look lesson completes from camera motion")
	# hold interact to skip a lesson
	Input.action_press(&"interact")
	ok = await _wait_until(func() -> bool: return d.skipped.has(&"move"), 5.0)
	Input.action_release(&"interact")
	expect(ok, "holding interact skips")
	await _wait_until(func() -> bool: return d.step_id() == &"sprint", 5.0)
	# the partner wakes up for the defence lessons
	while d.running and d.step_id() != &"block":
		d.complete_step(true)
		await _wait_until(func() -> bool: return not d._advancing, 5.0)
	expect(t.bot.active, "sparring partner attacks in the block lesson")
	while d.running:
		d.complete_step(true)
		await _wait_until(func() -> bool: return not d._advancing, 5.0)
	expect(d.done, "director finished")
	ok = await _wait_until(func() -> bool: return t.complete_screen != null, 10.0)
	expect(ok, "completion screen")
	var routed: Array = []
	t.route_override = func(path: String, params: Dictionary) -> void: routed.append([path, params])
	t.complete_screen.options[0].pressed.emit()
	expect(routed.size() == 1 and routed[0][0] == Router.WORLD and routed[0][1]["new_game"] == true, "ENTER THE WORLD starts a journey")
	expect(not GameState.is_tutorial and GameState.element == ElementDefs.Element.FIRE, "fresh non-tutorial state")
	expect(not SaveSystem.has_save(SaveSystem.AUTOSAVE_SLOT), "nothing was saved")
	await _free(t)
