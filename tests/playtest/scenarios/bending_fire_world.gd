extends RefCounted
## Fire in the real open world (world.tscn, streamed terrain + vegetation): a dry grass
## field near the Fire Nation home spawn. The player (InputMap actions only):
##   1 field     stands in the grass
##   2 burst     Fire Burst: the grass around catches (GrassFire), the ground is scorched
##   3 spread    the fire creeps downwind cell by cell - never past its budget
##   4 burnout   every cell burns out on its own, leaving charred ground + smoke
##   5 again     the burnt patch does not catch again; fresh grass does
##   6 rain      in the rain the grass will not catch (only a scorch mark)
## Observer + player-camera screenshots, cell counts, frame times.

const E := ElementDefs.Element

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var cam: Camera3D
var spot := Vector3.ZERO


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.FIRE)
	GameState.intro_done = true
	GameState.time_of_day = 16.2
	var home := WorldData.get_spawn(E.FIRE)
	var cands := _find_fields(home.origin, 8)
	if not p.check(not cands.is_empty(), "dry grass fields near the Fire Nation spawn (%d)" % cands.size()):
		return
	spot = cands[0]
	var spawn := Transform3D(Basis(Vector3.UP, 0.6), spot + Vector3.UP * 0.3)
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 240.0)
	p.check(ok, "world ready %s" % str(w.load_report))
	pl = w.player
	# The field must be open (no wall, building or cliff within 12 m): checked in the
	# streamed world, moving on to the next candidate when it is not.
	var open := false
	for i in cands.size():
		spot = cands[i]
		if i > 0:
			pl.teleport(Transform3D(Basis(Vector3.UP, 0.6), spot + Vector3.UP * 0.3))
			await p.wait_game(3.0)
		else:
			await p.wait_game(1.0)
		open = _is_open(spot, 12.0)
		print("[fire_world] candidate %d at %s (%.0f m from the Fire home spawn): open %s" % [i, spot,
				Vector2(spot.x - home.origin.x, spot.z - home.origin.z).length(), str(open)])
		if open:
			break
	p.check(open, "a dry patch clear of walls (%s, %.0f m from the Fire home spawn, region %s)" % [spot,
			Vector2(spot.x - home.origin.x, spot.z - home.origin.z).length(), str(WorldData.get_region(spot.x, spot.z))])
	pl.camera_rig.require_capture = false
	pl.resources.infinite_chi = true
	pl.health.invulnerable = true
	pl.camera_rig.pitch = deg_to_rad(10.0)
	var r: Node = FireEnv.renderer(pl)
	if r != null:
		r.call("set_weather", &"clear", 0.0)
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"fire_burst"))
	pl.controller.reset_cooldowns()
	# Let the region card pass and the grass stream in.
	await p.wait_game(5.0)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
	p.check(FireEnv.is_burnable(pl.global_position), "standing on dry grass (%s)" % str(GroundSampler.surface(pl.global_position)))
	await p.screenshot("world_1_field")

	# 2) Fire Burst in the grass.
	var lit0 := GrassFire.cells_lit
	p.check(await _cast(&"ability_1", &"fire_burst"), "fire burst cast")
	await p.wait_game(0.3)
	await _obs("world_2_burst", pl.global_position, 1.0, 6.0, 5.5)
	p.check(GrassFire.burning_count() > 0, "the grass caught (%d cells)" % GrassFire.burning_count())
	# Step out of the fire (the bender's own fire does not burn them, but it is good form).
	p.hold(&"move_back")
	await p.wait_game(1.4)
	p.release(&"move_back")

	# 3) Spread within the budget.
	var center := spot
	var max_cells := 0
	var t := 0.0
	var frames: Array[float] = []
	var shots := {2.0: "world_3_spread", 5.0: "world_4_spread_wide"}
	while t < 30.0:
		var t0 := Time.get_ticks_usec()
		await p.wait_game(0.25)
		frames.append(float(Time.get_ticks_usec() - t0) / 1000.0 / 15.0)
		t += 0.25
		max_cells = maxi(max_cells, GrassFire.burning_count())
		for k: float in shots.keys():
			if absf(t - k) < 0.01:
				await _obs(shots[k], center, -1.0, 6.5 if k < 4.0 else 11.0, 6.5 if k < 4.0 else 12.0)
				if k < 4.0:
					await p.screenshot("world_3_spread_player")
		if t > 3.0 and GrassFire.burning_count() == 0:
			break
	var lit := GrassFire.cells_lit - lit0
	p.note("grass fire: %d cells lit in total, %d burning at most (budget %d / fire %d), burnt out after %.1f s" % [lit, max_cells,
			GrassFire.max_cells(), GrassFire.PER_FIRE, t])
	p.check(lit > 1, "the fire spread past where it started (%d cells)" % lit)
	p.check(max_cells <= GrassFire.max_cells(), "never more than the budget burning (%d <= %d)" % [max_cells, GrassFire.max_cells()])
	p.check(GrassFire.burning_count() == 0, "it burned out on its own (%.1f s)" % t)
	frames.sort()
	p.note("approx. ms per frame while burning (median of 0.25 s windows): %.1f" % (frames[frames.size() / 2] if not frames.is_empty() else 0.0))
	await p.wait_game(0.5)
	await _obs("world_5_burnt", center, 1.0, 6.0, 7.0)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.2)
	await p.screenshot("world_5_burnt_player")

	# 5) The burnt patch does not catch again (cooldown); fresh grass does.
	var again := GrassFire.ignite(pl.controller.ctx, center, 1.0)
	p.check(not again, "the burnt patch does not catch again")
	if GrassFire.current() != null:
		GrassFire.current().clear()

	# 6) Rain: fresh grass a little way off does not catch.
	var fresh := _find_field(center + Vector3(14.0, 0.0, 0.0), 6.0, 40.0)
	if fresh != Vector3.INF and r != null:
		r.call("set_weather", &"rain", 0.0)
		await p.wait_game(0.3)
		pl.teleport(Transform3D(Basis(Vector3.UP, 0.6), fresh + Vector3.UP * 0.3))
		pl.camera_rig.snap_behind(pl)
		await p.wait_game(1.0)
		pl.controller.reset_cooldowns()
		var before := GrassFire.cells_lit
		p.check(await _cast(&"ability_1", &"fire_burst"), "fire burst in the rain")
		await p.wait_game(0.4)
		await p.screenshot("world_6_rain")
		p.check(GrassFire.cells_lit == before, "wet grass does not catch in the rain")
		r.call("set_weather", &"clear", 0.0)
	else:
		p.note("no second grass spot / renderer: rain step skipped")


# --- helpers ---------------------------------------------------------------------------------------

## The nearest flat, dry, burnable grass point around `origin` (rings out to max_r).
## Up to `count` candidate fields, nearest first, at least 60 m apart.
func _find_fields(origin: Vector3, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var r := 40.0
	while out.size() < count and r < 1600.0:
		var q := _find_field(origin, r, r + 60.0)
		if q != Vector3.INF and out.all(func(o: Vector3) -> bool: return o.distance_to(q) > 60.0):
			out.append(q)
		r += 40.0
	return out


## No wall, building or cliff around (horizontal rays at knee and head height out to
## `radius`): nothing within 4 m and at most two thirds of the rays blocked - the Fire
## Nation's dry patches are in its bamboo / broadleaf forests, so trunks are expected.
func _is_open(at: Vector3, radius: float) -> bool:
	var space := pl.get_world_3d().direct_space_state
	var blocked := 0
	for h: float in [0.8, 2.2]:
		for k in 12:
			var a := TAU * k / 12.0
			var from := Vector3(at.x, WorldData.get_height(at.x, at.z) + h, at.z)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0.0, sin(a)) * radius)
			q.exclude = [pl.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				blocked += 1
				if (hit["position"] as Vector3).distance_to(from) < 4.0:
					return false
	return blocked <= 16


## (The Fire Nation's home island is mostly city, rock and ash; its forests are humid -
## wet ground does not catch - so the nearest dry patch is a few hundred metres out.)
func _find_field(origin: Vector3, min_r: float = 40.0, max_r: float = 1400.0) -> Vector3:
	var r := min_r
	while r <= max_r:
		var n := maxi(12, int(TAU * r / 20.0))
		for i in n:
			var a := TAU * float(i) / n
			var x := origin.x + cos(a) * r
			var z := origin.z + sin(a) * r
			var q := Vector3(x, WorldData.get_height(x, z), z)
			if not FireEnv.is_burnable(q):
				continue
			var good := 0
			var steep := false
			for k in 8:
				var b := TAU * k / 8.0
				var qq := Vector3(x + 5.0 * cos(b), 0.0, z + 5.0 * sin(b))
				qq.y = WorldData.get_height(qq.x, qq.z)
				steep = steep or absf(qq.y - q.y) > 1.5
				if FireEnv.is_burnable(qq):
					good += 1
			if not steep and good >= 6:
				return q
		r += 20.0
	return Vector3.INF


func _cast(action: StringName, want: StringName) -> bool:
	for attempt in 3:
		await p.wait_until(func() -> bool: return pl.states.is_free() and not pl.controller.is_busy(), 3.0)
		Input.action_press(action)
		var ok := await p.wait_until(func() -> bool: return pl.controller.current != null and pl.controller.current.def.id == want, 0.5)
		await p.wait_game(0.06)
		Input.action_release(action)
		if ok:
			return true
		await p.wait_game(0.2)
	return false


func _obs(shot: String, focus: Vector3, side: float = 1.0, dist: float = 8.0, height: float = 3.0) -> void:
	var fwd := -pl.camera_rig.global_basis.z if pl.camera_rig else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var eye := focus + right * side * dist - fwd * dist * 0.4
	eye.y = WorldData.get_height(eye.x, eye.z) + height
	cam.look_at_from_position(eye, focus + Vector3.UP * 0.6, Vector3.UP)
	cam.make_current()
	await p.screenshot(shot)
	pl.camera_rig.make_current()
