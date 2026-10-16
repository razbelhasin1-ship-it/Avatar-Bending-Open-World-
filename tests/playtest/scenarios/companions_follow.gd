extends RefCounted
## Companion follow + call in the real world (world.tscn, streamed terrain + content), per
## element's companion (ELEMENT=water|earth|fire|air or all four):
##   1 spawn       the companion appears beside the player at the home spawn
##   2 walk        the player walks / runs over the real terrain (InputMap actions); the
##                 companion keeps its formation slot, never between camera and player
##   3 rest        the player stops: the companion settles, faces them, idles
##   4 sprint      flyers take off and escort from the air; ground companions keep pace
##   5 call        the companion is put 150 m away; companion_call brings it back (run,
##                 tunnel or fly in + land) and it greets the player
## Screenshots from the player's camera and an observer camera.

const E := ElementDefs.Element

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var c: Companion
var cam: Camera3D
var el_name := ""


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("ELEMENT")
	for e: int in [E.WATER, E.EARTH, E.FIRE, E.AIR]:
		if only != "" and ElementDefs.id_of(e) != only:
			continue
		await _run_element(e)


func _run_element(e: int) -> void:
	el_name = String(ElementDefs.id_of(e))
	GameState.new_game(e)
	GameState.intro_done = true
	var spawn := route_start(WorldData.get_spawn(e).origin, 100.0)
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn, "skip_intro": true}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 240.0)
	p.check(ok, "%s world ready" % el_name)
	pl = w.player
	pl.camera_rig.require_capture = false
	c = pl.get_companion() as Companion
	if not p.check(c != null, "%s companion spawned by the world hook" % el_name):
		return
	p.note("%s companion %s at %.1f m" % [el_name, c.species, c.global_position.distance_to(pl.global_position)])
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	await p.wait_game(3.0)
	p.check(c.motor.on_floor or c.is_flying(), "%s companion on the ground at spawn" % el_name)
	p.check(w.hud.companion_panel.visible, "%s HUD companion panel visible" % el_name)
	await p.screenshot("%s_1_spawn_view" % el_name)
	await _observe("%s_1_spawn_side" % el_name, 1.0)

	# 2) Walk / run over the terrain, turning gently.
	var occluded := 0
	var samples := 0
	var max_d := 0.0
	for i in 60:
		p.hold(&"move_forward")
		if i % 20 == 10:
			p.hold(&"sprint")
		elif i % 20 == 0:
			p.release(&"sprint")
		p.look(6.0 if (i / 15) % 2 == 0 else -6.0, 0.0)
		await p.wait_game(0.2)
		samples += 1
		if _occludes():
			occluded += 1
		max_d = maxf(max_d, _flat(c.global_position, pl.global_position))
		if i == 25:
			await p.screenshot("%s_2_walk_view" % el_name)
		if i == 45:
			await _observe("%s_2_walk_side" % el_name, 0.0)
	p.release(&"sprint")
	p.release(&"move_forward")
	p.note("%s walked %.0f m from spawn; companion max distance %.1f m, occluding %d / %d samples, mode %s" % [el_name,
			_flat(pl.global_position, spawn.origin), max_d, occluded, samples, c.get_mode_name()])
	p.check(occluded <= samples / 10, "%s companion rarely between camera and player (%d / %d)" % [el_name, occluded, samples])

	# 3) Rest.
	await p.wait_game(6.0)
	var d_rest := _flat(c.global_position, pl.global_position)
	p.check(d_rest < 40.0 or c.prof.prefers_air, "%s close after stopping (%.1f m, %s)" % [el_name, d_rest, c.get_mode_name()])
	await p.screenshot("%s_3_rest_view" % el_name)
	await _observe("%s_3_rest_side" % el_name, 0.0)

	# 4) Sprint far ahead: flyers take to the air, ground companions keep pace.
	p.hold(&"move_forward")
	p.hold(&"sprint")
	await p.wait_game(9.0)
	await p.screenshot("%s_4_sprint_view" % el_name)
	p.release(&"sprint")
	p.release(&"move_forward")
	p.note("%s sprint: companion %.1f m away, mode %s, flight %s" % [el_name, _flat(c.global_position, pl.global_position), c.get_mode_name(),
			c.flight.phase_name() if c.flight else "-"])
	if c.prof.can_fly:
		await _observe("%s_4_escort_air" % el_name, 0.0, true)

	# 5) Call from far away.
	await p.wait_game(1.0)
	var away := pl.global_position + Vector3(150, 0, 0)
	away = WorldData.get_safe_ground(away)
	if c.flight and c.flight.is_active():
		c.flight.cancel()
	c.set_mode(Companion.Mode.FOLLOW)
	c.motor.teleport(away)
	c.brain._stay = true
	await p.wait_game(1.0)
	var calls: Array = []
	var cb := func(cmd: StringName) -> void: calls.append(cmd)
	Events.companion_command.connect(cb)
	await p.tap(&"companion_call")
	var t0 := Time.get_ticks_msec()
	var shot := false
	ok = false
	var max_wait := 40.0
	var waited := 0.0
	while waited < max_wait:
		await p.wait_game(0.25)
		waited += 0.25
		var d := _flat(c.global_position, pl.global_position)
		if not shot and d < 45.0 and d > 12.0:
			shot = true
			await _observe("%s_5_call_coming" % el_name, 0.0, c.is_airborne())
		if d < 16.0 and c.mode == Companion.Mode.FOLLOW and not c.is_flying():
			ok = true
			break
	Events.companion_command.disconnect(cb)
	p.check(calls.has(&"call"), "%s companion_call emits the command" % el_name)
	p.check(ok, "%s came when called from 150 m (%.1f s game, %.1f m, %s)" % [el_name, waited, _flat(c.global_position, pl.global_position), c.get_mode_name()])
	p.note("%s call took %.1f s game (%d ms wall)" % [el_name, waited, Time.get_ticks_msec() - t0])
	await p.wait_game(1.5)
	await p.screenshot("%s_5_call_arrived_view" % el_name)
	await _observe("%s_5_call_arrived_side" % el_name, 0.0)
	var q := c.global_position
	p.check(q.y > WorldData.get_height(q.x, q.z) - 0.6, "%s companion above the terrain" % el_name)


## True when the companion's body crosses the camera -> player line.
func _occludes() -> bool:
	var a := pl.camera_rig.camera.global_position
	var b := pl.global_position + Vector3.UP * 1.2
	var center := c.global_position + Vector3.UP * c.prof.body_height() * 0.5
	return CompanionNav.segment_distance(center, a, b) < c.prof.radius() * 0.8


## Observer shot: from the side of the companion (and the player) at a flattering height.
func _observe(shot_name: String, wait_s: float, air: bool = false) -> void:
	if wait_s > 0.0:
		await p.wait_game(wait_s)
	var cp := c.global_position + Vector3.UP * c.prof.body_height() * 0.5
	var pp := pl.global_position + Vector3.UP * 1.0
	var mid := cp.lerp(pp, 0.5) if not air else cp
	var span := maxf(cp.distance_to(pp), c.prof.radius() * 4.0)
	var fwd := CompanionNav.dir_of(c.motor.yaw if not c.is_flying() else c.flight.heading)
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var dist := clampf(span * 1.3 + 6.0, 9.0, 60.0)
	var pos := mid + side * dist + fwd * dist * 0.35 + Vector3.UP * (2.5 + dist * 0.18)
	pos.y = maxf(pos.y, WorldData.get_height(pos.x, pos.z) + 1.5)
	pos = unblocked(c, mid, pos)
	cam.global_position = pos
	cam.look_at(mid, Vector3.UP)
	cam.make_current()
	await p.frames(2)
	await p.screenshot(shot_name)
	pl.camera_rig.make_current()
	await p.frames(1)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Observer camera position pulled in front of rocks / trees / terrain between it and the
## subject (shared by the companion playtests).
static func unblocked(n: Node3D, focus: Vector3, pos: Vector3) -> Vector3:
	var space := n.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, pos, Layers.SOLID)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return pos
	var hit: Vector3 = r["position"]
	return hit + (focus - pos).normalized() * 0.6


## A start near `home` facing along a dry, walkable `length` m corridor over rolling ground
## (prefers some height variation: rough but walkable terrain). Shared by the companion
## playtests.
static func route_start(home: Vector3, length: float, max_slope: float = 26.0) -> Transform3D:
	var best := Transform3D(Basis(), home)
	var best_score := -INF
	for ring in 7:
		var r := 120.0 + float(ring) * 60.0
		var n := 12
		for k in n:
			var a := TAU * float(k) / float(n)
			var o := home + Vector3(cos(a), 0.0, sin(a)) * r
			for h in 12:
				var yaw := TAU * float(h) / 12.0
				var dir := CompanionNav.dir_of(yaw)
				var ok := true
				var lo := INF
				var hi := -INF
				var s := 0.0
				while s <= length + 20.0:
					var q := o + dir * s
					var biome := WorldData.get_biome(q.x, q.z)
					if not CompanionNav.walkable(q.x, q.z, max_slope, 0.0) or biome == WorldData.Biome.CITY or biome == WorldData.Biome.TEMPLE \
							or WorldData.get_road(q.x, q.z) > 0.3 or not WorldData.get_pois_in_radius(q, 45.0).is_empty():
						ok = false
						break
					for side: float in [-12.0, 12.0]:
						var q2 := q + Vector3(-dir.z, 0.0, dir.x) * side
						if CompanionNav.water_depth(q2.x, q2.z) > 0.0:
							ok = false
					var hgt := WorldData.get_height(q.x, q.z)
					lo = minf(lo, hgt)
					hi = maxf(hi, hgt)
					s += 5.0
				if not ok:
					continue
				var score := minf(hi - lo, 14.0) - r * 0.02
				if score > best_score:
					best_score = score
					best = Transform3D(Basis(Vector3.UP, yaw), Vector3(o.x, WorldData.get_height(o.x, o.z) + 0.3, o.z))
	return best
