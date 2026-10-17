extends RefCounted
## bughunt_gameplay: the fixed bugs, played for real (rendered, through InputMap actions where a
## player would press buttons) with observer + player-view screenshots and measured numbers:
##   jet     Water Jet held 3 s on a dummy: no hitstop per pulse, Focus only every 4th pulse
##   torrent Tidal Torrent among four dummies: the signature gives no Focus back
##   ride    riding the badgermole when a cinematic starts (the training grounds end on Ride):
##           the rider is set down, stands on the floor during and after it
##   sea     the polar bear dog swimming far out at sea, F to hop off: the rider lands in the
##           water beside it (was: an arc to dry land hundreds of metres away)
##   flight  sky bison: take off, climb, let go, save while falling: the save holds solid ground
## PART=jet,torrent,ride,sea,flight (default all).

const E := ElementDefs.Element

var p: Playtest
var cam: Camera3D


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("PART")
	for part in ["jet", "torrent", "ride", "sea", "flight"]:
		if only == "" or only.split(",").has(part):
			p.note("--- %s ---" % part)
			await call("_" + part)


# --- helpers -------------------------------------------------------------------------------------------

func _obs(shot: String, focus: Vector3, from_dir: Vector3, dist: float, height: float) -> void:
	var d := from_dir.normalized()
	cam.look_at_from_position(focus + d * dist + Vector3.UP * height, focus, Vector3.UP)
	cam.make_current()
	await p.screenshot(shot)


func _arena(e: int) -> Node:
	GameState.new_game(e)
	GameState.intro_done = true
	var arena: Node = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e})
	await p.wait_game(0.5)
	var pl: PlayerCharacter = arena.get("player")
	pl.camera_rig.require_capture = false
	cam = Camera3D.new()
	cam.fov = 55.0
	arena.add_child(cam)
	return arena


func _dummies(arena: Node, center: Vector3, n: int, r: float) -> Array[TrainingDummy]:
	var out: Array[TrainingDummy] = []
	for d: TrainingDummy in arena.get("dummies"):
		d.queue_free()
	for i in n:
		var a := TAU * float(i) / float(n) + 0.4
		var d := TrainingDummy.new()
		d.look = &"post" if i % 2 == 0 else &"humanoid"
		d.max_health = 4000.0
		d.position = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		arena.add_child(d)
		d.home = d.global_transform
		out.append(d)
	return out


## Focus gained and hitstops requested while `seconds` of game time run.
func _measure(pl: PlayerCharacter, seconds: float, shots: Dictionary = {}) -> Dictionary:
	var stops := [0]
	var cb := func(_d: float) -> void: stops[0] += 1
	Events.hitstop.connect(cb)
	var gained := 0.0
	var last := pl.resources.focus
	var t := 0.0
	var hits0 := BendingHits.applied_hits
	while t < seconds:
		await p.get_tree().physics_frame
		t += 1.0 / 60.0
		if pl.resources.focus > last:
			gained += pl.resources.focus - last
		last = pl.resources.focus
		for k: String in shots.keys():
			if t >= float(k):
				var c: Callable = shots[k]
				shots.erase(k)
				await c.call()
	Events.hitstop.disconnect(cb)
	return {"hitstops": stops[0], "focus": gained, "hits": BendingHits.applied_hits - hits0}


# --- Water Jet -----------------------------------------------------------------------------------------

func _jet() -> void:
	var arena := await _arena(E.WATER)
	var pl: PlayerCharacter = arena.get("player")
	var ds := _dummies(arena, Vector3(0, 0, -2.0), 1, 0.0)
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 4.5)))
	pl.camera_rig.snap_behind(pl)
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"water_jet"))
	pl.resources.infinite_chi = true
	pl.resources.set_focus(0.0)
	pl.resources.mark_combat()
	await p.wait_game(0.4)
	p.hold(&"ability_1")
	var m := await _measure(pl, 3.4, {"1.2": _jet_shots.bind(pl)})
	p.release(&"ability_1")
	await p.wait_game(0.6)
	await p.screenshot("jet_3_after_focus")
	p.note("water jet: %d pulses landed, %d hitstops, +%.0f Focus" % [m["hits"], m["hitstops"], m["focus"]])
	p.check(int(m["hits"]) >= 10, "the jet kept hitting the dummy (%d)" % m["hits"])
	p.check(int(m["hitstops"]) <= 2, "no hitstop per pulse (%d)" % m["hitstops"])
	p.check(float(m["focus"]) <= 30.0, "Focus from the stream stays modest (+%.0f)" % m["focus"])
	for d in ds:
		d.queue_free()


func _jet_shots(pl: PlayerCharacter) -> void:
	await p.screenshot("jet_1_player_view")
	await _obs("jet_2_side", Vector3(0, 1.1, 1.0), Vector3(1, 0, 0.35), 6.5, 1.6)
	pl.camera_rig.make_current()


func _torrent_shot_1(pl: PlayerCharacter) -> void:
	await _obs("torrent_1_vortex", pl.global_position + Vector3.UP * 1.5, Vector3(0.8, 0, 1), 11.0, 4.0)
	pl.camera_rig.make_current()


func _torrent_shot_2() -> void:
	await p.screenshot("torrent_2_player_view")


# --- Tidal Torrent -------------------------------------------------------------------------------------

func _torrent() -> void:
	var arena := await _arena(E.WATER)
	var pl: PlayerCharacter = arena.get("player")
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 2.0)))
	pl.camera_rig.snap_behind(pl)
	var ds := _dummies(arena, Vector3(0, 0, 1.0), 4, 3.6)
	pl.controller.set_slot(&"signature", AbilityRegistry.get_def(&"tidal_torrent"))
	pl.resources.mark_combat()
	pl.resources.set_focus(100.0)
	await p.wait_game(0.4)
	await p.tap(&"ability_special")
	var m := await _measure(pl, 3.2, {"1.0": _torrent_shot_1.bind(pl), "2.0": _torrent_shot_2})
	p.note("tidal torrent: %d hits, +%.0f Focus, focus now %.0f" % [m["hits"], m["focus"], pl.resources.focus])
	p.check(int(m["hits"]) >= 4, "the torrent hit the ring of dummies (%d)" % m["hits"])
	p.check(float(m["focus"]) < 1.0 and pl.resources.focus < 1.0, "the signature gives no Focus back (+%.0f, bar %.0f)" % [m["focus"], pl.resources.focus])
	for d in ds:
		d.queue_free()


# --- riding into a cinematic -----------------------------------------------------------------------------

func _ride() -> void:
	var arena := await _arena(E.EARTH)
	var pl: PlayerCharacter = arena.get("player")
	var c := Companion.create(&"badgermole")
	c.player = pl
	arena.add_child(c)
	c.motor.teleport(pl.global_position + Vector3(-2.4, 0, 0), 0.0)
	c.rig.reset_feet()
	pl.companion = c
	await p.wait_game(0.8)
	var ok := false
	for i in 4:
		if c.can_mount(pl):
			await p.tap(&"mount")
			ok = await p.wait_until(func() -> bool: return c.mode == Companion.Mode.RIDDEN, 6.0)
			if ok:
				break
		await p.wait_game(0.3)
	p.check(ok, "mounted the badgermole")
	p.hold(&"move_forward")
	await p.wait_game(1.5)
	p.release(&"move_forward")
	await p.wait_game(0.4)
	await p.screenshot("ride_1_riding")
	# The training grounds' complete screen: a cinematic starts while riding.
	pl.enter_cinematic(6.0)
	await p.wait_game(1.5)
	var y_during := pl.global_position.y
	await _obs("ride_2_cinematic_observer", pl.global_position + Vector3.UP, Vector3(1, 0, 0.6), 7.0, 2.4)
	pl.camera_rig.make_current()
	p.check(pl.get_state() == PlayerCharacter.State.CINEMATIC and absf(y_during) < 0.3, "standing on the floor during the cinematic (y %.2f)" % y_during)
	p.check(not c.is_ridden() and pl.collision_layer == Layers.PLAYER, "set down: companion %s, collision layer %d" % [c.get_mode_name(), pl.collision_layer])
	pl.exit_cinematic()
	await p.wait_game(1.5)
	await p.screenshot("ride_3_after")
	p.check(pl.get_state() == PlayerCharacter.State.LOCOMOTION and pl.global_position.y > -0.3, "on foot after it (%s, y %.2f)" % [pl.get_state_name(), pl.global_position.y])
	c.queue_free()


# --- dismount at sea -------------------------------------------------------------------------------------

func _open_sea_near(home: Vector3) -> Vector3:
	var best := Vector3.INF
	for r in range(140, 1400, 40):
		for k in 32:
			var a := TAU * float(k) / 32.0
			var x := home.x + sin(a) * float(r)
			var z := home.z + cos(a) * float(r)
			var w := WorldData.get_water_height(x, z)
			if not is_finite(w) or w - WorldData.get_height(x, z) < 6.0:
				continue
			var s := WorldData.get_safe_ground(Vector3(x, w, z))
			if Vector2(s.x - x, s.z - z).length() > 90.0:
				return Vector3(x, w, z)
	return best


func _sea() -> void:
	GameState.new_game(E.WATER)
	GameState.intro_done = true
	GameState.time_of_day = 11.0
	var home := WorldData.get_spawn(E.WATER).origin
	var sea := _open_sea_near(home)
	if not p.check(sea.is_finite(), "open sea near the Water Tribe"):
		return
	var w: WorldScene = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": Transform3D(Basis.IDENTITY, sea + Vector3.UP * 0.2)}) as WorldScene
	if not p.check(await p.wait_until(func() -> bool: return w.playing, 300.0), "world ready"):
		return
	var pl := w.player
	pl.camera_rig.require_capture = false
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	await p.wait_game(1.5)
	var c := pl.get_companion() as Companion
	if not p.check(c != null, "the polar bear dog is here"):
		return
	c.teleport_near_player()
	c.motor.teleport(pl.global_position + Vector3(-2.2, -0.6, 0), 0.0)
	await p.wait_game(1.0)
	var ok := false
	for i in 6:
		pl.teleport(Transform3D(Basis.IDENTITY, c.global_position + Vector3(2.0, 0.6, 0)))
		await p.wait_game(0.3)
		if c.can_mount(pl):
			await p.tap(&"mount")
			ok = await p.wait_until(func() -> bool: return c.mode == Companion.Mode.RIDDEN, 6.0)
			if ok:
				break
		await p.wait_game(0.4)
	p.check(ok, "riding the polar bear dog out at sea (swimming %s)" % c.motor.swimming)
	if not ok:
		return
	p.hold(&"move_forward")
	await p.wait_game(1.2)
	p.release(&"move_forward")
	await p.wait_game(0.5)
	await _obs("sea_1_riding", c.global_position + Vector3.UP, Vector3(1, 0, 1), 9.0, 3.0)
	pl.camera_rig.make_current()
	var before := c.global_position
	await p.tap(&"mount")
	await p.wait_until(func() -> bool: return pl.get_state() != PlayerCharacter.State.MOUNTED, 4.0)
	await p.wait_game(1.0)
	var d := Vector2(pl.global_position.x - before.x, pl.global_position.z - before.z).length()
	await _obs("sea_2_after_hop", pl.global_position + Vector3.UP * 0.5, Vector3(1, 0, 0.7), 7.0, 2.5)
	pl.camera_rig.make_current()
	await p.screenshot("sea_3_player_view")
	p.note("hopped off at sea: %.1f m from the mount, swimming %s" % [d, pl.motor.swimming])
	p.check(d < 6.0 and pl.motor.swimming, "the rider slipped into the water beside the mount (%.1f m, swimming %s)" % [d, pl.motor.swimming])


# --- let go of the sky bison, save while falling -----------------------------------------------------------

func _flight() -> void:
	GameState.new_game(E.AIR)
	GameState.intro_done = true
	GameState.time_of_day = 10.5
	var w: WorldScene = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": WorldData.get_spawn(E.AIR)}) as WorldScene
	if not p.check(await p.wait_until(func() -> bool: return w.playing, 300.0), "world ready"):
		return
	var pl := w.player
	pl.camera_rig.require_capture = false
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	await p.wait_game(2.0)
	var c := pl.get_companion() as Companion
	if not p.check(c != null, "the sky bison is here"):
		return
	var stand := pl.global_position
	var ok := false
	for i in 8:
		if c.can_mount(pl):
			await p.tap(&"mount")
			ok = await p.wait_until(func() -> bool: return c.mode == Companion.Mode.RIDDEN, 6.0)
			if ok:
				break
		c.motor.teleport(pl.global_position + pl.global_basis.x * -3.2, pl.rotation.y)
		await p.wait_game(0.6)
	if not p.check(ok, "riding the sky bison"):
		return
	await p.tap(&"jump")
	await p.wait_until(func() -> bool: return c.is_airborne(), 6.0)
	p.hold(&"jump")
	p.hold(&"move_forward")
	await p.wait_game(4.0)
	p.release(&"jump")
	await p.wait_game(1.0)
	p.release(&"move_forward")
	var alt := c.global_position.y - WorldData.get_height(c.global_position.x, c.global_position.z)
	await _obs("flight_1_airborne", c.global_position, Vector3(1, -0.2, 1), 16.0, 4.0)
	pl.camera_rig.make_current()
	# The safe ground while flying is where the player last stood - not the saddle.
	var safe_in_flight := pl.motor.last_safe_position()
	await p.tap(&"mount")
	await p.wait_until(func() -> bool: return pl.get_state() != PlayerCharacter.State.MOUNTED, 3.0)
	await p.wait_game(0.4)
	SaveSystem.save_game(2)
	var data := SaveSystem.read_slot(2)
	var v: Variant = data.get("player_position")
	var saved := Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Vector3.INF
	await p.screenshot("flight_2_falling_view")
	var ground_at_save := WorldData.get_height(saved.x, saved.z) if saved.is_finite() else INF
	p.note("let go at %.0f m above ground; safe ground in flight %s (stood at %s); saved %s (terrain %.1f)" % [alt, safe_in_flight.snapped(Vector3.ONE * 0.1),
			stand.snapped(Vector3.ONE * 0.1), saved.snapped(Vector3.ONE * 0.1), ground_at_save])
	p.check(alt > 10.0, "flew up first (%.0f m)" % alt)
	p.check(saved.is_finite() and absf(saved.y - ground_at_save) < 3.0, "the save made while falling holds solid ground (y %.1f vs terrain %.1f)" % [saved.y, ground_at_save])
	await p.wait_until(func() -> bool: return pl.motor.on_floor, 20.0)
	await p.wait_game(1.0)
	await p.screenshot("flight_3_landed")
