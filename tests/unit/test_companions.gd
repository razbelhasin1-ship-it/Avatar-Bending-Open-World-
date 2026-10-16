extends TestCase
## Companions module: profiles, spawning every species, follow formation (never blocking
## the player / camera), obstacle avoidance + unstick, call (run / fly in / teleport),
## never-lost teleports, mount / dismount transitions and rider attachment, ground riding,
## flight (takeoff, thrust, banking, climb / dive, boost, stall prevention, terrain + sea
## avoidance, ceiling, world edge, landing), mid-air dismount + catch, badgermole burrow,
## health that never kills + retreat / recover, combat assist with real hits, persistence,
## HUD contract and a random-input riding fuzz (no stuck states).

const E := ElementDefs.Element
const S := PlayerCharacter.State
const M := Companion.Mode

var _ground: StaticBody3D


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	BendingHits.clear_log()
	GameState.new_game(E.AIR)
	_ground = PlayerSim.ground(self, 1200.0)


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0
	for n in get_children():
		n.queue_free()
	await frames(2)


func _setup(species: StringName, element: int, c_pos: Vector3 = Vector3(-6, 0, 3)) -> Array:
	var p := PlayerSim.player(self, element, Vector3.ZERO)
	var c := CompanionSim.companion(self, species, c_pos, p)
	await CompanionSim.step(c, p, 5)
	return [c, p]


static func _flat(a: Vector3, b: Vector3) -> float:
	return CompanionSim.flat_distance(a, b)


# --- profiles / spawning -------------------------------------------------------------------------------

func test_profiles_per_species() -> void:
	for id in CompanionProfile.SPECIES:
		var pr := CompanionProfile.for_species(id)
		expect(pr.max_health > 100.0 and pr.radius() > 0.3 and pr.body_height() > 1.0, "%s basic numbers" % id)
		expect(pr.f(pr.follow, "side") > pr.radius(), "%s formation slot beside the player" % id)
		expect(pr.f(pr.ride, "sprint") > pr.f(pr.ride, "run") and pr.f(pr.ride, "run") > pr.f(pr.ride, "walk"), "%s ride speeds ordered" % id)
		expect(not StringName(pr.assist.get("kind", &"")).is_empty(), "%s has an assist move" % id)
		expect((pr.assist.get("hit", {}) as Dictionary).has("damage"), "%s assist hit data" % id)
	expect(CompanionProfile.for_species(&"sky_bison").can_fly and CompanionProfile.for_species(&"dragon").can_fly, "flyers")
	expect(not CompanionProfile.for_species(&"polar_bear_dog").can_fly and CompanionProfile.for_species(&"badgermole").can_burrow, "ground mounts")
	expect(CompanionProfile.for_species(&"polar_bear_dog").f(CompanionProfile.for_species(&"polar_bear_dog").ride, "snow") == 0.0, "polar bear dog ignores deep snow")
	expect(CompanionProfile.for_species(&"polar_bear_dog").f(CompanionProfile.for_species(&"polar_bear_dog").ride, "sprint") > 14.0, "fast gallop")
	expect(CompanionProfile.for_species(&"badgermole").f(CompanionProfile.for_species(&"badgermole").ride, "max_slope") >= 52.0, "badgermole climbs rugged slopes")
	for e in ElementDefs.ALL:
		expect(CompanionProfile.SPECIES.has(CompanionProfile.species_for_element(e)), "element %d has a companion" % e)


func test_every_species_spawns_and_stands() -> void:
	for id in CompanionProfile.SPECIES:
		var r: Array = await _setup(id, E.WATER)
		var c: Companion = r[0]
		var p: PlayerCharacter = r[1]
		await CompanionSim.step(c, p, 60)
		expect(c.rig != null and c.health.health > 0.0, "%s built" % id)
		expect(c.motor.on_floor and absf(c.global_position.y) < 0.3, "%s stands on the ground (y %.2f)" % [id, c.global_position.y])
		expect(c.is_in_group(&"damageable") and c.team == Combat.Team.PLAYER, "%s damageable on the player's team" % id)
		expect(c.collision_layer == Layers.COMPANION and (c.collision_mask & Layers.PLAYER) == 0, "%s never blocks the player physically" % id)
		expect(not c.get_status_text().is_empty(), "%s status text" % id)
		expect(HudLockOn.find_health(c) == c.health, "%s HUD finds its health" % id)
		c.queue_free()
		p.queue_free()
		await frames(1)


# --- follow ---------------------------------------------------------------------------------------------

func test_follow_formation_beside_and_behind() -> void:
	var r: Array = await _setup(&"polar_bear_dog", E.WATER, Vector3(-5, 0, 6))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	p.input.press(&"move_forward")
	var min_d := INF
	for i in 6:
		await CompanionSim.step(c, p, 60)
		min_d = minf(min_d, _flat(c.global_position, p.global_position))
	p.input.release(&"move_forward")
	await CompanionSim.step(c, p, 120)
	var to := c.global_position - p.global_position
	var fwd := -p.global_basis.z
	expect(p.global_position.z < -25.0, "player walked forward (%.1f)" % p.global_position.z)
	expect(_flat(c.global_position, p.global_position) < 8.0, "kept up (%.1f m)" % _flat(c.global_position, p.global_position))
	expect(to.dot(fwd) < 1.0, "beside / behind, not in front (%.2f)" % to.dot(fwd))
	expect(min_d > c.prof.radius() + 0.4, "never ran into the player (min %.2f)" % min_d)
	expect(c.mode == M.FOLLOW and c.get_status_text() in ["Waiting", "Resting", "Following"], "following / resting at the slot (%s)" % c.get_status_text())


func test_follow_steers_around_a_wall() -> void:
	var r: Array = await _setup(&"badgermole", E.EARTH, Vector3(0, 0, 20))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	# A wall between the companion and the player.
	PlayerSim.box(self, Vector3(0, 2, 10), Vector3(14, 4, 1))
	await CompanionSim.step(c, p, 60 * 12)
	expect(_flat(c.global_position, p.global_position) < 9.0, "went around the wall (%.1f m, %s)" % [_flat(c.global_position, p.global_position), c.global_position])
	expect(c.global_position.z < 10.0, "now on the player's side of the wall")


func test_stuck_companion_teleports_when_called() -> void:
	var r: Array = await _setup(&"polar_bear_dog", E.WATER, Vector3(0, 0, 30))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	# Boxed in: four walls.
	for off: Vector3 in [Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
		var size := Vector3(1, 4, 7) if off.x != 0.0 else Vector3(7, 4, 1)
		PlayerSim.box(self, Vector3(0, 2, 30) + off, size)
	await CompanionSim.step(c, p, 60 * 4)
	var calls: Array = []
	var cb := func(cmd: StringName) -> void: calls.append(cmd)
	Events.companion_command.connect(cb)
	await CompanionSim.tap(c, p, &"companion_call")
	await CompanionSim.step(c, p, 60 * 8)
	Events.companion_command.disconnect(cb)
	expect(calls.has(&"call"), "Events.companion_command(&\"call\") (tutorial lesson)")
	expect(_flat(c.global_position, p.global_position) < 10.0, "free again next to the player (%.1f m)" % _flat(c.global_position, p.global_position))
	expect(absf(c.global_position.z - 30.0) > 4.0, "out of the box")


func test_call_from_far_away() -> void:
	for id: StringName in [&"polar_bear_dog", &"sky_bison"]:
		var r: Array = await _setup(id, E.AIR, Vector3(0, 0, 80))
		var c: Companion = r[0]
		var p: PlayerCharacter = r[1]
		c.brain._stay = true
		await CompanionSim.step(c, p, 30)
		expect(c.mode == M.WAIT, "%s stays when told" % id)
		await CompanionSim.tap(c, p, &"companion_call")
		var n := await CompanionSim.step_until(c, p, func() -> bool:
			return _flat(c.global_position, p.global_position) < 14.0 and c.mode == M.FOLLOW and not c.is_flying(), 60 * 25)
		expect(n >= 0, "%s came back (%.1f m, mode %s, flight %s)" % [id, _flat(c.global_position, p.global_position), c.get_mode_name(),
				c.flight.phase_name() if c.flight else "-"])
		expect(c.global_position.y > -0.5 and c.global_position.y < 1.0, "%s on the ground at the end" % id)
		c.queue_free()
		p.queue_free()
		await frames(1)


func test_never_lost_after_player_teleport() -> void:
	var r: Array = await _setup(&"badgermole", E.EARTH)
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	p.teleport(Transform3D(Basis(), Vector3(400, 0, -300)))
	await CompanionSim.step(c, p, 30)
	expect(_flat(c.global_position, p.global_position) < 30.0, "teleported to the player (%.1f m)" % _flat(c.global_position, p.global_position))
	# A broken position is repaired too.
	c.global_position = Vector3(NAN, 0, 0)
	await CompanionSim.step(c, p, 20)
	expect(c.global_position.is_finite() and _flat(c.global_position, p.global_position) < 30.0, "NaN position repaired")
	# Fallen under the world.
	c.global_position = p.global_position + Vector3(5, -40, 0)
	await CompanionSim.step(c, p, 30)
	expect(c.global_position.y > -1.0, "back on top of the world (y %.1f)" % c.global_position.y)


# --- mount / ride ---------------------------------------------------------------------------------------

func _mount(c: Companion, p: PlayerCharacter) -> bool:
	await CompanionSim.tap(c, p, &"mount")
	var n := await CompanionSim.step_until(c, p, func() -> bool: return c.mode == M.RIDDEN, 120)
	return n >= 0


func test_mount_ride_dismount_ground() -> void:
	var r: Array = await _setup(&"polar_bear_dog", E.WATER, Vector3(-2.2, 0, 0))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	await CompanionSim.step(c, p, 30)
	expect(c.can_mount(p), "in range")
	var mounted: Array = []
	var cb := func(m: Node3D) -> void: mounted.append(m)
	Events.mounted.connect(cb)
	await CompanionSim.tap(c, p, &"mount")
	expect(c.mode == M.MOUNTING and p.get_state() == S.MOUNTED, "mount transition started (%s)" % c.get_mode_name())
	var n := await CompanionSim.step_until(c, p, func() -> bool: return c.mode == M.RIDDEN, 120)
	Events.mounted.disconnect(cb)
	expect(n >= 0 and n < 70, "seated after the leap (%d frames)" % n)
	expect(mounted.has(c), "Events.mounted")
	await CompanionSim.step(c, p, 2)
	var seat := c.rider.saddle_transform().origin
	expect(p.global_position.distance_to(seat) < 0.05, "rider on the saddle socket (%.3f m)" % p.global_position.distance_to(seat))
	expect(p.visual.get_pose() == &"riding", "riding pose (%s)" % p.visual.get_pose())
	# Gallop forward.
	var start := c.global_position
	p.input.press(&"move_forward")
	p.input.press(&"sprint")
	await CompanionSim.step(c, p, 60 * 3)
	var max_err := 0.0
	for i in 30:
		await CompanionSim.step(c, p, 1)
		max_err = maxf(max_err, p.global_position.distance_to(c.rider.saddle_transform().origin))
	p.input.release(&"sprint")
	p.input.release(&"move_forward")
	var hs := Vector2(c.velocity.x, c.velocity.z).length()
	expect(_flat(start, c.global_position) > 30.0, "galloped (%.1f m)" % _flat(start, c.global_position))
	expect(hs > 12.0, "fast gallop (%.1f m/s)" % hs)
	expect(max_err < 0.08, "rider stays on the saddle at full gallop (max %.3f m)" % max_err)
	await CompanionSim.step(c, p, 90)
	# Dismount: animated hop down beside the mount.
	await CompanionSim.tap(c, p, &"mount")
	expect(c.mode == M.DISMOUNTING, "dismount transition (%s)" % c.get_mode_name())
	n = await CompanionSim.step_until(c, p, func() -> bool: return p.get_state() != S.MOUNTED, 120)
	expect(n >= 0, "back on foot")
	await CompanionSim.step(c, p, 30)
	expect(p.get_state() == S.LOCOMOTION and p.motor.on_floor, "standing (%s)" % p.get_state_name())
	expect(absf(p.global_position.y) < 0.2, "on the ground, not inside the mount (y %.2f)" % p.global_position.y)
	expect(_flat(p.global_position, c.global_position) > c.prof.radius(), "beside the mount")
	expect(p.visual.rig.transform.basis.is_equal_approx(Basis.IDENTITY), "rider tilt reset")
	expect(c.mode == M.FOLLOW, "companion follows again")


func test_mount_through_the_interact_prompt() -> void:
	var prompts: Array = []
	var cb := func(text: String, vis: bool) -> void: if vis: prompts.append(text)
	Events.interaction_prompt.connect(cb)
	var r: Array = await _setup(&"badgermole", E.EARTH, Vector3(0, 0, -2.8))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	await CompanionSim.step(c, p, 20)
	Events.interaction_prompt.disconnect(cb)
	expect(prompts.any(func(t: String) -> bool: return t.contains("Ride the Badgermole")), "prompt shown %s" % str(prompts))
	await CompanionSim.tap(c, p, &"interact")
	var n := await CompanionSim.step_until(c, p, func() -> bool: return c.mode == M.RIDDEN, 120)
	expect(n >= 0, "mounted via interact (%s)" % c.get_mode_name())
	await CompanionSim.tap(c, p, &"interact")
	n = await CompanionSim.step_until(c, p, func() -> bool: return p.get_state() == S.LOCOMOTION, 120)
	expect(n >= 0, "interact also dismounts (gamepad)")


func test_external_dismount_cleans_up() -> void:
	var r: Array = await _setup(&"polar_bear_dog", E.WATER, Vector3(-2.2, 0, 0))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	expect(await _mount(c, p), "mounted")
	p.dismount(Vector3(10, 0, 10))   # travel / respawn code path
	await CompanionSim.step(c, p, 10)
	expect(c.mode == M.FOLLOW and c.rider.phase == CompanionRider.Phase.NONE, "companion released (%s)" % c.get_mode_name())
	expect(p.visual.rig.visible and p.visual.rig.transform.basis.is_equal_approx(Basis.IDENTITY), "rider visuals restored")


# --- flight ---------------------------------------------------------------------------------------------

func test_flight_takeoff_bank_climb_boost_land() -> void:
	for id: StringName in [&"sky_bison", &"dragon"]:
		var r: Array = await _setup(id, E.AIR, Vector3(-3.5, 0, 0))
		var c: Companion = r[0]
		var p: PlayerCharacter = r[1]
		expect(await _mount(c, p), "%s mounted" % id)
		await CompanionSim.tap(c, p, &"jump")
		var n := await CompanionSim.step_until(c, p, func() -> bool: return c.flight.phase == CompanionFlight.Phase.FLY, 60 * 5)
		expect(n >= 0, "%s took off" % id)
		expect(c.flight.altitude() > 4.0, "%s climbed out (%.1f m)" % [id, c.flight.altitude()])
		# Thrust: cruise speed.
		p.input.press(&"move_forward")
		await CompanionSim.step(c, p, 60 * 6)
		var cruise := c.flight.f("cruise")
		expect(absf(c.flight.speed - cruise) < 3.0, "%s cruises (%.1f / %.1f)" % [id, c.flight.speed, cruise])
		# Banking left turn (camera-relative: steer to the left of the camera view).
		p.input.release(&"move_forward")
		p.input.press(&"move_left")
		var h0 := c.flight.heading
		var min_bank := 0.0
		var min_rig := 0.0
		for i in 60 * 3:
			await CompanionSim.step(c, p, 1)
			min_bank = minf(min_bank, c.flight.bank)
			min_rig = minf(min_rig, c.rig.flight_bank)
		expect(min_bank < -0.2, "%s banks into a left turn (%.2f rad)" % [id, min_bank])
		expect(absf(wrapf(c.flight.heading - h0, -PI, PI)) > 0.5, "%s turned" % id)
		expect(min_rig < -0.2, "%s rig rolls with the bank (%.2f)" % [id, min_rig])
		p.input.release(&"move_left")
		# Climb.
		var y0 := c.global_position.y
		p.input.press(&"jump")
		await CompanionSim.step(c, p, 120)
		p.input.release(&"jump")
		expect(c.global_position.y > y0 + 8.0, "%s climbs while jump is held (+%.1f m)" % [id, c.global_position.y - y0])
		expect(c.flight.pitch > 0.05 or c.flight.vy > 2.0, "%s noses up" % id)
		# Boost.
		p.input.press(&"move_forward")
		p.input.press(&"sprint")
		await CompanionSim.step(c, p, 60 * 5)
		expect(c.flight.speed > cruise + 6.0, "%s boosts (%.1f)" % [id, c.flight.speed])
		p.input.release(&"sprint")
		p.input.release(&"move_forward")
		# Glide: no input -> slow sink, never a stall.
		var yg := c.global_position.y
		await CompanionSim.step(c, p, 60 * 3)
		expect(c.global_position.y < yg, "%s glides down slowly" % id)
		expect(c.flight.speed >= c.flight.f("min") - 0.01, "%s never stalls (%.1f)" % [id, c.flight.speed])
		# Dive + land.
		p.input.press(&"descend")
		n = await CompanionSim.step_until(c, p, func() -> bool: return not c.flight.is_active(), 60 * 30)
		p.input.release(&"descend")
		expect(n >= 0, "%s landed (%s, alt %.1f)" % [id, c.flight.phase_name(), c.flight.altitude()])
		await CompanionSim.step(c, p, 30)
		expect(c.mode == M.RIDDEN and absf(c.global_position.y) < 0.3, "%s on the ground, still ridden (y %.2f)" % [id, c.global_position.y])
		expect(p.global_position.distance_to(c.rider.saddle_transform().origin) < 0.08, "%s rider still seated" % id)
		c.queue_free()
		p.queue_free()
		await frames(1)


func test_flight_bounds_terrain_sea_ceiling_edge() -> void:
	var r: Array = await _setup(&"dragon", E.FIRE, Vector3(-3.5, 0, 0))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	expect(await _mount(c, p), "mounted")
	await CompanionSim.tap(c, p, &"jump")
	await CompanionSim.step_until(c, p, func() -> bool: return c.flight.phase == CompanionFlight.Phase.FLY, 300)
	# A 120 m cliff ahead (WorldData heights): the flyer pulls up instead of hitting it.
	WorldData.height_override = func(_x: float, z: float) -> float: return 120.0 if z < -150.0 else 0.0
	PlayerSim.box(self, Vector3(0, 60, -450), Vector3(1200, 120, 600))
	p.input.press(&"move_forward")
	var min_clear := INF
	for i in 60 * 14:
		await CompanionSim.step(c, p, 1)
		var q := c.global_position
		min_clear = minf(min_clear, q.y - WorldData.get_height(q.x, q.z))
	expect(c.global_position.z < -150.0, "flew over the cliff (z %.0f)" % c.global_position.z)
	expect(min_clear > 0.3, "never below the terrain (min clearance %.2f)" % min_clear)
	# Diving at the ground never goes through it.
	p.input.press(&"descend")
	p.input.release(&"move_forward")
	for i in 60 * 4:
		await CompanionSim.step(c, p, 1)
		var q2 := c.global_position
		min_clear = minf(min_clear, q2.y - WorldData.get_height(q2.x, q2.z))
	p.input.release(&"descend")
	expect(min_clear > -0.01, "dive stops at the ground (%.2f)" % min_clear)
	# Ceiling.
	WorldData.height_override = Callable()
	if c.flight.is_active():
		c.motor.teleport(Vector3(0, 400, 0))
		c.flight.start_airborne(0.0, 20.0)
		p.input.press(&"jump")
		await CompanionSim.step(c, p, 60 * 4)
		p.input.release(&"jump")
		expect(c.global_position.y < CompanionFlight.CEILING_ABOVE_TERRAIN + 30.0, "ceiling holds (y %.0f)" % c.global_position.y)
		# World edge: flying out to sea turns back.
		c.motor.teleport(Vector3(3990, 60, 0), CompanionNav.yaw_of(Vector3.RIGHT))
		c.flight.start_airborne(CompanionNav.yaw_of(Vector3.RIGHT), 24.0)
		p.input.press(&"move_right")
		var max_x := 0.0
		for i in 60 * 10:
			await CompanionSim.step(c, p, 1)
			max_x = maxf(max_x, c.global_position.x)
		p.input.release(&"move_right")
		expect(max_x < 4096.0 and c.global_position.x < max_x - 20.0, "the winds turn it back at the world edge (max x %.0f, now %.0f)" % [max_x, c.global_position.x])


func test_midair_dismount_and_catch() -> void:
	var r: Array = await _setup(&"sky_bison", E.WATER, Vector3(-3.5, 0, 0))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	expect(await _mount(c, p), "mounted")
	await CompanionSim.tap(c, p, &"jump")
	await CompanionSim.step_until(c, p, func() -> bool: return c.flight.phase == CompanionFlight.Phase.FLY, 300)
	p.input.press(&"jump")
	await CompanionSim.step(c, p, 150)
	p.input.release(&"jump")
	var alt := c.global_position.y
	expect(alt > 15.0, "high up (%.1f)" % alt)
	await CompanionSim.tap(c, p, &"mount")
	await CompanionSim.step(c, p, 5)
	expect(p.get_state() == S.AIRBORNE, "let go: falling (%s)" % p.get_state_name())
	expect(c.mode == M.ESCORT and c.is_airborne(), "the bison keeps flying (%s)" % c.get_mode_name())
	expect(p.global_position.y > alt - 3.0, "released at the saddle, not teleported to the ground (y %.1f)" % p.global_position.y)
	# Catch: put the falling rider next to the saddle and press mount.
	await CompanionSim.step(c, p, 10)
	p.global_position = c.rider.saddle_transform().origin + Vector3(1.0, 0.5, 0)
	p.velocity = Vector3(0, -3, 0)
	await CompanionSim.tap(c, p, &"mount")
	var n := await CompanionSim.step_until(c, p, func() -> bool: return c.mode == M.RIDDEN, 90)
	expect(n >= 0 and c.rider.catches == 1, "caught in mid-air (%s)" % c.get_mode_name())
	# Let go again and fall to the ground safely.
	await CompanionSim.tap(c, p, &"mount")
	n = await CompanionSim.step_until(c, p, func() -> bool: return p.motor.on_floor, 60 * 12)
	expect(n >= 0 and p.is_alive() and absf(p.global_position.y) < 0.3, "landed safely (y %.2f, alive %s)" % [p.global_position.y, p.is_alive()])
	n = await CompanionSim.step_until(c, p, func() -> bool: return c.mode == M.FOLLOW and not c.is_flying(), 60 * 30)
	expect(n >= 0, "the bison lands beside the player (%s %s)" % [c.get_mode_name(), c.flight.phase_name()])


# --- burrow ---------------------------------------------------------------------------------------------

func test_badgermole_burrow_ridden() -> void:
	var r: Array = await _setup(&"badgermole", E.EARTH, Vector3(0, 0, -2.8))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	expect(await _mount(c, p), "mounted")
	var start := c.global_position
	var want := start + Vector3(0, 0, -30)
	expect(c.burrow.start_to(want, true), "burrow started")
	expect(c.mode == M.BURROW and c.collision_layer == 0, "digging, collision off")
	var seen := {"hidden": false, "min_y": INF}
	var phases: Array = []
	var n := await CompanionSim.step_until(c, p, func() -> bool:
		if not phases.has(c.burrow.phase_name()):
			phases.append(c.burrow.phase_name())
		seen["hidden"] = bool(seen["hidden"]) or not p.visual.rig.visible
		seen["min_y"] = minf(float(seen["min_y"]), p.global_position.y)
		return not c.burrow.is_active(), 60 * 15)
	expect(n >= 0, "tunnel finished (%s)" % str(phases))
	expect(phases.has("dig") and phases.has("travel") and phases.has("emerge"), "dig -> travel -> emerge %s" % str(phases))
	expect(bool(seen["hidden"]), "rider hidden while underground")
	expect(float(seen["min_y"]) > -0.2, "rider seat never under the surface (%.2f)" % float(seen["min_y"]))
	expect(_flat(c.global_position, want) < 1.5, "emerged at the target (%.1f m off)" % _flat(c.global_position, want))
	expect(c.mode == M.RIDDEN and p.get_state() == S.MOUNTED and p.visual.rig.visible, "still ridden, rider visible")
	expect(c.collision_layer == Layers.COMPANION, "collision restored")
	expect(c.burrow.tunnels == 1, "one tunnel")
	# Through input: descend digs toward the view.
	p.input.press(&"descend")
	await CompanionSim.step(c, p, 3)
	p.input.release(&"descend")
	expect(c.mode == M.BURROW, "descend digs in while riding")
	await CompanionSim.step_until(c, p, func() -> bool: return not c.burrow.is_active(), 60 * 15)


func test_burrow_refuses_invalid_exits() -> void:
	var r: Array = await _setup(&"badgermole", E.EARTH, Vector3(0, 0, -2.8))
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	expect(not c.burrow.start_to(c.global_position + Vector3(0, 0, -3), false), "too short")
	# Deep water everywhere ahead.
	WorldData.height_override = func(x: float, z: float) -> float: return -6.0 if z < -6.0 else 0.0
	expect(not c.burrow.start_to(c.global_position + Vector3(0, 0, -30), false), "no exit under water")
	WorldData.height_override = Callable()
	expect(c.mode != M.BURROW, "nothing started")


# --- health / assist ---------------------------------------------------------------------------------------

func test_never_dies_retreats_and_recovers() -> void:
	var r: Array = await _setup(&"polar_bear_dog", E.WATER)
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	var hit := HitInfo.make(99999.0, null, E.FIRE, HitInfo.Reaction.KNOCKDOWN, Vector3.FORWARD, 10.0)
	hit.team = Combat.Team.ENEMY
	var res := Combat.deal(c, hit)
	expect(res == Combat.Result.HIT, "hit lands")
	expect(c.health.health >= 1.0 and not c.health.is_dead() and c.is_alive(), "never dies (%.1f)" % c.health.health)
	await CompanionSim.step(c, p, 5)
	expect(c.mode == M.RETREAT and c.get_status_text().contains("recovering"), "retreats (%s)" % c.get_status_text())
	var n := await CompanionSim.step_until(c, p, func() -> bool: return c.mode == M.FOLLOW, 60 * 40)
	expect(n >= 0 and c.health.ratio() >= 0.69, "recovered (%.2f)" % c.health.ratio())
	# Ridden companions ignore hits (like the rider).
	c.motor.teleport(Vector3(-2.2, 0, 0))
	await CompanionSim.step(c, p, 5)
	expect(await _mount(c, p), "mounted")
	var h2 := HitInfo.make(50.0, null, E.FIRE, HitInfo.Reaction.FLINCH, Vector3.FORWARD)
	h2.team = Combat.Team.ENEMY
	expect(Combat.deal(c, h2) == Combat.Result.IGNORED, "ridden: ignored")


func test_assist_hits_an_engaged_enemy() -> void:
	for id: StringName in CompanionProfile.SPECIES:
		var r: Array = await _setup(id, E.EARTH, Vector3(-6, 0, 3))
		var c: Companion = r[0]
		var p: PlayerCharacter = r[1]
		var e := EnemyBase.create(&"bandit_brawler", {"home": Transform3D(Basis(), Vector3(4, 0, -8)), "rewards": false})
		add_child(e)
		await CompanionSim.step(c, p, 2)
		e.brain.engage(p)
		c.assist.cooldown_left = 0.0
		var hp0 := e.health.health
		var hits: Array = []
		var cb := func(hit: HitInfo, target: Node, result: int) -> void:
			if target == e and String(hit.ability_id).begins_with("companion_"):
				hits.append([hit, result])
		Events.hit_landed.connect(cb)
		var n := await CompanionSim.step_until(c, p, func() -> bool: return not hits.is_empty() or not e.is_alive(), 60 * 12)
		Events.hit_landed.disconnect(cb)
		expect(n >= 0, "%s assisted (mode %s, assist phase %d, uses %d)" % [id, c.get_mode_name(), c.assist.phase, c.assist.uses])
		if not hits.is_empty():
			var h: HitInfo = hits[0][0]
			expect(h.source == p and h.team == Combat.Team.PLAYER, "%s: credit goes to the player" % id)
			expect(e.health.health < hp0, "%s: real damage (%.0f -> %.0f)" % [id, hp0, e.health.health])
		await CompanionSim.step(c, p, 60 * 3)
		expect(c.assist.cooldown_left > 0.0 or c.assist.is_active(), "%s cooldown running" % id)
		e.queue_free()
		c.queue_free()
		p.queue_free()
		await frames(2)


# --- persistence / HUD ----------------------------------------------------------------------------------------

func test_persistence_and_hud_status() -> void:
	GameState.companion["health_ratio"] = 0.6
	var r: Array = await _setup(&"sky_bison", E.AIR)
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	expect_near(c.health.ratio(), 0.6, 0.02, "health restored from GameState")
	c.health.health = c.health.max_health * 0.8
	c.write_save_state()
	expect_near(float(GameState.companion["health_ratio"]), 0.8, 0.01, "saved ratio")
	expect(GameState.companion["type"] == "sky_bison", "saved type")
	var d := GameState.to_dict()
	GameState.from_dict(d)
	expect_near(float(GameState.companion["health_ratio"]), 0.8, 0.01, "survives a save round trip")
	expect(p.get_companion() == c, "player.get_companion() (HUD)")
	expect(c.get_display_name() == "Sky Bison", "display name")


# --- fuzz -------------------------------------------------------------------------------------------------

func test_random_riding_never_gets_stuck() -> void:
	var actions: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"descend", &"mount", &"companion_call", &"interact"]
	for id: StringName in CompanionProfile.SPECIES:
		var r: Array = await _setup(id, E.AIR, Vector3(-2.5, 0, 0))
		var c: Companion = r[0]
		var p: PlayerCharacter = r[1]
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var modes := {}
		for i in 2400:
			if i % 12 == 0:
				for a in actions:
					if rng.randf() < (0.06 if a in [&"mount", &"interact", &"companion_call"] else 0.3):
						p.input.press(a)
					else:
						p.input.release(a)
			CompanionSim.step_once(c, p)
			if i % 30 == 0:
				await get_tree().physics_frame
			modes[c.get_mode_name()] = true
			var q := c.global_position
			if not q.is_finite() or q.y < -1.0:
				fail("%s invalid position %s at frame %d (%s)" % [id, q, i, c.get_mode_name()])
				break
		p.input.release_all()
		# Let everything settle: no state may last forever.
		await CompanionSim.step(c, p, 60 * 25)
		if p.get_state() == S.MOUNTED:
			c.request_dismount()
			await CompanionSim.step(c, p, 60 * 20)
		expect(p.get_state() in [S.LOCOMOTION, S.AIRBORNE], "%s player free at the end (%s)" % [id, p.get_state_name()])
		expect(c.mode in [M.FOLLOW, M.ESCORT, M.WAIT], "%s companion settled (%s, modes seen %s)" % [id, c.get_mode_name(), str(modes.keys())])
		c.queue_free()
		p.queue_free()
		await frames(1)
