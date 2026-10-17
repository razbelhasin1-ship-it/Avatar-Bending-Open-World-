extends RefCounted
## Air in the real world (world.tscn: streamed terrain, vegetation, grass, snow trails)
## near the Air home region (docs/modules/bending_air.md). The player starts on a
## grassy, level spot near the Southern Air Temple (searched on rings around the Air
## spawn, outside the settlement) and, through InputMap actions only:
##   gust     Air Blast through the grass (the wind impulse parts it along the path)
##   push     Air Push: a ring flattening the grass, bushes / trees swaying
##   blade    Wind Blade over the meadow
##   scooter  ride across the grass (wake + dust trail), jump off, glide (wake)
##   tornado  Air Tornado on two bandits (dust skirt in the ground colours, lift, fling)
##   snow     on a snowfield: Air Push / sweep scour hollows in the snow trails
## Measures the frame time while the wind effects run. SPOT=x,z overrides the spot.

const E := ElementDefs.Element

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.AIR)
	GameState.intro_done = true
	GameState.time_of_day = 10.5
	var home := WorldData.get_spawn(E.AIR)
	var grass := _find_spot(home.origin, &"grass", 80.0, 700.0)
	var snow := _find_spot(home.origin, &"snow", 40.0, 1500.0)
	if not snow.is_finite():
		# The temple's mountains are not snow-capped here: the nearest snowfield is by the
		# Water Tribe (a fast-travel hop).
		snow = _find_spot(WorldData.get_spawn(E.WATER).origin, &"snow", 120.0, 1500.0)
	if OS.get_environment("SPOT") != "":
		var xz := OS.get_environment("SPOT").split(",")
		grass = Vector3(float(xz[0]), 0.0, float(xz[1]))
		grass.y = WorldData.get_height(grass.x, grass.z)
	p.note("air home %s; grass spot %s (%.0f m, %s); snow spot %s (%.0f m)" % [home.origin, grass, _flat(grass - home.origin),
			WorldData.get_region(grass.x, grass.z), snow, _flat(snow - home.origin)])
	if not p.check(grass.is_finite(), "found a grassy spot near the Air home"):
		return
	var to_home := home.origin - grass
	var spawn := Transform3D(Basis(Vector3.UP, atan2(to_home.x, to_home.z)), grass + Vector3.UP * 0.3)
	var t0 := Time.get_ticks_msec()
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 300.0)
	p.check(ok, "world ready in %.1f s %s" % [(Time.get_ticks_msec() - t0) / 1000.0, str(w.load_report)])
	if not ok:
		return
	pl = w.player
	pl.camera_rig.require_capture = false
	pl.resources.infinite_chi = true
	pl.health.invulnerable = true
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	for pair: Array in [[&"technique_1", &"air_push"], [&"technique_2", &"wind_blade"], [&"technique_3", &"air_scooter"],
			[&"technique_4", &"air_sweep"], [&"signature", &"air_tornado"]]:
		pl.controller.set_slot(pair[0], AbilityRegistry.get_def(pair[1]))
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void: hits.append([hit.ability_id, t, r]))
	await p.wait_game(1.0)
	# An open patch of meadow nearby (few trunks within 9 m) so the observer sees the wind.
	var open := _open_spot(pl.global_position, 40.0)
	if open.is_finite():
		pl.teleport(Transform3D(pl.global_basis, open + Vector3.UP * 0.3))
		await p.wait_game(1.0)
	_park_companion()
	# Let the "region discovered" banner pass.
	await p.wait_game(6.0)
	p.note("standing on %s at %s" % [WorldData.get_surface(pl.global_position), pl.global_position])
	await _gust()
	await _push()
	await _blade()
	await _scooter()
	await _tornado()
	if snow.is_finite():
		await _snow(snow)
	p.note("AirEnv: %d blows, %d bodies pushed, %d snow hollows; AirWindField started %d" % [AirEnv.blows, AirEnv.bodies_pushed,
			AirEnv.snow_scoured, AirWindField.started])


# --- helpers -----------------------------------------------------------------------------------------

static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## A level spot with `surface` on rings around `c` (outside settlements, dry, 8 m of level
## ground around it). Vector3.INF if none.
static func _find_spot(c: Vector3, surface: StringName, r0: float, r1: float) -> Vector3:
	var r := r0
	while r <= r1:
		for k in 24:
			var a := TAU * float(k) / 24.0
			var q := c + Vector3(cos(a), 0.0, sin(a)) * r
			q.y = WorldData.get_height(q.x, q.z)
			if WorldData.get_surface(q) != surface or Settlements.settlement_at(q) != &"":
				continue
			if WorldData.get_water_height(q.x, q.z) > q.y - 0.5:
				continue
			var level := true
			for j in 8:
				var b := TAU * float(j) / 8.0
				var h := WorldData.get_height(q.x + 8.0 * cos(b), q.z + 8.0 * sin(b))
				if absf(h - q.y) > 1.2:
					level = false
					break
			if level:
				return q
		r += 40.0
	return Vector3.INF


## Trunk / boulder colliders (WorldContent) within `r` of `at`.
func _content_near(at: Vector3, r: float) -> int:
	var space := w.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = Layers.WORLD
	var n := 0
	for hit: Dictionary in space.intersect_shape(q, 32):
		var c: Object = hit.get("collider")
		if c is Node and (c as Node).is_in_group(&"world_content"):
			n += 1
	return n


## The level grass point within `r` m with the fewest trunks around it.
func _open_spot(c: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var best_n := 1 << 20
	for k in 36:
		var a := TAU * float(k) / 12.0
		var q := c + Vector3(cos(a), 0.0, sin(a)) * r * (0.35 + 0.65 * float(k / 12) / 2.0)
		q.y = WorldData.get_height(q.x, q.z)
		if WorldData.get_surface(q) != &"grass" or WorldData.get_slope_deg(q.x, q.z) > 12.0:
			continue
		var n := _content_near(q + Vector3.UP * 2.0, 9.0)
		if n < best_n:
			best_n = n
			best = q
	p.note("open meadow spot %s (%d trunks within 9 m)" % [best, best_n])
	return best


## The sky bison sits this one out (it follows / circles the player and would fill the
## observer shots): parked far behind, frozen and hidden.
func _park_companion() -> void:
	var comp := pl.companion as Companion
	if comp == null or not is_instance_valid(comp):
		return
	comp.set_mode(Companion.Mode.WAIT)
	var at := pl.global_position + pl.global_basis.z * 40.0
	at.y = WorldData.get_height(at.x, at.z) + 0.5
	comp.global_position = at
	comp.process_mode = Node.PROCESS_MODE_DISABLED
	comp.visible = false


func _tick_until(cond: Callable, timeout: float) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _cur_id() -> StringName:
	return pl.controller.current.def.id if pl.controller.current != null else &""


func _cast(action: StringName, want: StringName, hold: float = 0.06) -> bool:
	for attempt in 6:
		await _tick_until(func() -> bool: return not pl.controller.is_busy() and pl.states.is_free(), 3.0)
		p.hold(action)
		var ok := await _tick_until(func() -> bool: return _cur_id() == want, 0.4)
		if ok:
			await p.wait_game(hold)
			p.release(action)
			return true
		p.release(action)
		await p.wait_game(0.15)
	return false


## Observer shot: from the side of the bender, looking across `focus`; the first
## candidate without trunks near the camera / view line (canopies have no collision).
func _shot(name: String, focus: Vector3, side: float = 1.0, dist: float = 7.5, height: float = 2.4) -> void:
	var a := pl.global_position + Vector3.UP
	var f := focus - a
	f.y = 0.0
	var fwd := f.normalized() if f.length() > 0.5 else -pl.global_basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var mid := a.lerp(focus, 0.45)
	var space := w.get_world_3d().direct_space_state
	var pos := Vector3.INF
	for c: Array in [[side, 0.35, 0.0], [-side, 0.35, 0.0], [side, 0.9, 1.5], [-side, 0.9, 1.5], [0.25, 1.2, 3.0], [side, 0.2, 4.0]]:
		var q: Vector3 = mid + right * float(c[0]) * dist - fwd * dist * float(c[1]) + Vector3.UP * (height + float(c[2]))
		q.y = maxf(q.y, WorldData.get_height(q.x, q.z) + 1.4)
		if _content_near(q, 4.0) > 0 or _content_near(q.lerp(mid, 0.4), 3.0) > 0:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(q, mid, Layers.WORLD)).is_empty():
			continue
		pos = q
		break
	if not pos.is_finite():
		# Nothing clear: the player's own camera.
		await p.screenshot(name)
		return
	cam.look_at_from_position(pos, mid, Vector3.UP)
	cam.make_current()
	await p.screenshot(name)
	pl.camera_rig.make_current()


## Average / worst frame time (ms) over `seconds` of real time.
func _frame_time(seconds: float) -> Vector2:
	var n := 0
	var sum := 0.0
	var worst := 0.0
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await p.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		sum += dt
		worst = maxf(worst, dt)
		n += 1
	return Vector2(sum / maxf(n, 1), worst)


func _hits_on(id: StringName, from: int) -> int:
	var n := 0
	for i in range(from, hits.size()):
		if hits[i][0] == id and hits[i][1] is EnemyBase and (hits[i][2] == Combat.Result.HIT or hits[i][2] == Combat.Result.KILLED):
			n += 1
	return n


# --- sections ------------------------------------------------------------------------------------------

func _gust() -> void:
	var base := await _frame_time(0.6)
	p.note("frame time on the meadow, no wind: %.1f ms avg, %.1f ms worst" % [base.x, base.y])
	await _shot("world_meadow", pl.global_position - pl.global_basis.z * 6.0 + Vector3.UP * 0.5, 1.0, 8.0, 2.6)
	var started := AirWindField.started
	p.check(await _cast(&"attack_heavy", &"air_blast", 0.04), "air blast")
	await p.wait_game(0.25)
	await _shot("world_gust_grass", pl.global_position - pl.global_basis.z * 5.0, 1.0, 6.5, 2.2)
	p.check(AirWindField.started > started, "the gust pressed a wind impulse into the grass")
	await p.wait_game(0.8)


func _push() -> void:
	var b0 := AirEnv.blows
	p.check(await _cast(&"ability_1", &"air_push", 0.04), "air push")
	await _tick_until(func() -> bool:
		var a := pl.controller.current as ChargeAbility
		return a == null or a.released, 1.0)
	await p.wait_game(0.12)
	await _shot("world_push_ring", pl.global_position + Vector3.UP * 0.2 - pl.global_basis.z * 0.5, -1.0, 8.5, 4.0)
	var ft := await _frame_time(0.6)
	p.note("frame time during the push wind: %.1f ms avg, %.1f ms worst" % [ft.x, ft.y])
	p.check(AirEnv.blows > b0, "push blew the meadow")
	await p.wait_game(0.6)


func _blade() -> void:
	p.check(await _cast(&"ability_2", &"wind_blade", 0.04), "wind blade")
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a == null or bool(a.get("_fired")), 1.0)
	await p.wait_game(0.05)
	await _shot("world_blade", pl.global_position - pl.global_basis.z * 5.0 + Vector3.UP, 1.0, 6.0, 1.6)
	await p.wait_game(0.6)


func _scooter() -> void:
	p.check(await _cast(&"ability_3", &"air_scooter"), "air scooter")
	p.hold(&"move_forward")
	var start := pl.global_position
	await p.wait_game(1.2)
	await _shot("world_scooter_wake", pl.global_position + Vector3(0, 0.4, 0) + pl.velocity.normalized() * 2.0, 1.0, 6.5, 1.6)
	var spd := Vector2(pl.velocity.x, pl.velocity.z).length()
	p.check(spd > 10.0, "riding across the meadow (%.1f m/s, %.0f m so far)" % [spd, pl.global_position.distance_to(start)])
	await p.wait_game(0.6)
	await p.tap(&"jump", 0.08)
	await p.wait_game(0.5)
	p.hold(&"jump")
	var gliding := await _tick_until(func() -> bool: return pl.motor.gliding, 1.5)
	await p.wait_game(0.3)
	await _shot("world_glide", pl.global_position + pl.velocity.normalized() * 2.0, -1.0, 7.0, 0.8)
	p.check(gliding, "jumped off the ball into a glide")
	p.release(&"jump")
	p.release(&"move_forward")
	await _tick_until(func() -> bool: return pl.is_on_floor(), 4.0)
	await p.wait_game(0.5)


func _tornado() -> void:
	# Two bandits rush in from the front.
	var fwd := -pl.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var foes: Array[EnemyBase] = []
	for i in 2:
		var at := pl.global_position + fwd * 6.5 + Vector3(-fwd.z, 0, fwd.x) * (1.4 if i == 0 else -1.4)
		at.y = WorldData.get_height(at.x, at.z)
		var e := EnemyBase.create(&"bandit_brawler" if i == 0 else &"bandit_skirmisher", {"seed": 40 + i, "rewards": false,
				"home": Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), at)})
		w.add_child(e)
		e.low_health_mode = &""
		foes.append(e)
	await p.wait_game(0.4)
	for e in foes:
		e.brain.engage(pl)
	pl.targeting.lock(foes[0])
	pl.resources.set_focus(100.0)
	await p.wait_game(0.3)
	var h0 := hits.size()
	p.check(await _cast(&"ability_special", &"air_tornado"), "air tornado")
	var torn := pl.controller.current
	await p.wait_game(1.1)
	var c := Vector3(torn.get("center")) if torn != null and is_instance_valid(torn) else pl.global_position + fwd * 6.0
	await _shot("world_tornado", c + Vector3.UP * 3.5, 1.0, 13.0, 2.0)
	var ft := await _frame_time(0.8)
	p.note("frame time during the tornado: %.1f ms avg, %.1f ms worst" % [ft.x, ft.y])
	var lifted := false
	for e in foes:
		if is_instance_valid(e) and e.global_position.y > WorldData.get_height(e.global_position.x, e.global_position.z) + 1.2:
			lifted = true
	await _shot("world_tornado_lift", c + Vector3.UP * 3.0, -1.0, 12.0, 3.5)
	await _tick_until(func() -> bool: return pl.controller.current != torn, 4.0)
	await p.wait_game(0.2)
	await _shot("world_tornado_release", c + Vector3.UP * 1.5, 1.0, 14.0, 4.0)
	p.note("tornado lifted a bandit: %s; tornado hits %d" % [lifted, _hits_on(&"air_tornado", h0)])
	p.check(_hits_on(&"air_tornado", h0) >= 2, "tornado hits on the bandits (%d)" % _hits_on(&"air_tornado", h0))
	await p.wait_game(1.0)
	for e in foes:
		if is_instance_valid(e):
			e.queue_free()
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")
	await p.wait_game(0.3)


func _snow(at: Vector3) -> void:
	var travelled: bool = await w.travel.travel_to(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.4), {"fade": 0.2, "autosave": false})
	p.check(travelled, "travelled to the snowfield")
	await _tick_until(func() -> bool: return pl.is_on_floor() and not w.travel.busy, 20.0)
	_park_companion()
	await p.wait_game(1.5)
	p.note("snowfield: %s, snow depth %.2f m" % [WorldData.get_surface(pl.global_position), WorldData.get_snow_depth(at.x, at.z)])
	var s0 := AirEnv.snow_scoured
	p.check(await _cast(&"ability_1", &"air_push", 0.04), "push on the snow")
	await _tick_until(func() -> bool:
		var a := pl.controller.current as ChargeAbility
		return a == null or a.released, 1.0)
	await p.wait_game(0.15)
	await _shot("world_snow_push", pl.global_position + Vector3.UP * 0.3, 1.0, 7.5, 3.5)
	await p.wait_game(1.0)
	p.check(await _cast(&"ability_4", &"air_sweep"), "sweep on the snow")
	await p.wait_game(1.2)
	await _shot("world_snow_after", pl.global_position + Vector3.UP * 0.2, -1.0, 6.5, 3.0)
	p.check(AirEnv.snow_scoured > s0, "the wind scoured hollows in the snow (%d)" % (AirEnv.snow_scoured - s0))
