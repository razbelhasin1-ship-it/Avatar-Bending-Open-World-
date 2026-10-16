extends RefCounted
## Flying mounts in the real world: the sky bison (Air) and the dragon (Fire), ridden with
## InputMap actions only. SPECIES=sky_bison|dragon limits it to one.
##   1 mount      walk up, mount (leap onto the saddle), seated
##   2 takeoff    jump: crouch, leap, climb out
##   3 circuit    thrust + a banking left turn (stick left, camera auto-aligns), climb,
##                boost, glide; observer shots of the bank from the front and behind
##   4 terrain    a low pass toward rising ground: automatic pull-up keeps the clearance
##   5 landing    descend near the ground: flare, touchdown, still seated
##   6 let go     climb, dismount in the air: the rider falls / glides, the flyer escorts and
##                lands next to them
## Checks: altitude never below the terrain / sea, bank sign, speeds, rider attached.

const E := ElementDefs.Element
const Follow := preload("res://tests/playtest/scenarios/companions_follow.gd")

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var c: Companion
var cam: Camera3D
var tag := ""
var min_clear := INF
var max_rider_err := 0.0


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("SPECIES")
	for pair: Array in [[&"sky_bison", E.AIR], [&"dragon", E.FIRE]]:
		if only != "" and String(pair[0]) != only:
			continue
		await _fly(pair[0], pair[1])


func _fly(species: StringName, e: int) -> void:
	tag = String(species)
	min_clear = INF
	max_rider_err = 0.0
	GameState.new_game(e)
	GameState.intro_done = true
	GameState.time_of_day = 10.5
	var spawn: Transform3D = Follow.route_start(WorldData.get_spawn(e).origin, 140.0, 18.0)
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn, "skip_intro": true}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 240.0)
	p.check(ok, "%s world ready" % tag)
	pl = w.player
	pl.camera_rig.require_capture = false
	c = pl.get_companion() as Companion
	if not p.check(c != null and c.species == species, "%s companion present" % tag):
		return
	cam = Camera3D.new()
	cam.fov = 50.0
	w.add_child(cam)
	await p.wait_game(3.0)

	# 1) Mount: stand beside it and press mount.
	var side := Vector3(-CompanionNav.dir_of(c.motor.yaw).z, 0.0, CompanionNav.dir_of(c.motor.yaw).x)
	var stand := c.global_position - side * (c.prof.radius() + 1.4)
	stand.y = WorldData.get_height(stand.x, stand.z) + 0.1
	pl.teleport(Transform3D(Basis(Vector3.UP, CompanionNav.yaw_of(CompanionNav.flat_dir(c.global_position - stand))), stand))
	await p.wait_game(0.5)
	p.check(c.can_mount(pl), "%s in mount range" % tag)
	await p.tap(&"mount")
	await p.wait_game(c.rider.duration * 0.45)
	await _observe("%s_1_mount_leap" % tag, Vector3(1.6, 0.5, 0.6), 1.1)
	ok = await _until(func() -> bool: return c.mode == Companion.Mode.RIDDEN, 4.0)
	p.check(ok and pl.get_state() == PlayerCharacter.State.MOUNTED, "%s seated (%s)" % [tag, c.get_mode_name()])
	await p.wait_game(0.6)
	await p.screenshot("%s_1_seated_view" % tag)
	await _observe("%s_1_seated_side" % tag, Vector3(1.2, 0.45, 0.9), 0.9)

	# 2) Takeoff.
	await p.tap(&"jump")
	await p.wait_game(0.5)
	await _observe("%s_2_takeoff_crouch" % tag, Vector3(1.3, 0.3, -1.0), 1.1)
	ok = await _until(func() -> bool: return c.flight.phase == CompanionFlight.Phase.FLY, 6.0)
	p.check(ok, "%s airborne (%s)" % [tag, c.flight.phase_name()])
	await _observe("%s_2_takeoff_climb" % tag, Vector3(1.4, 0.1, -0.8), 1.2)

	# 3) Circuit: thrust, then a long banking left turn, climb, boost.
	p.hold(&"move_forward")
	await _fly_for(4.0)
	p.check(absf(c.flight.speed - c.flight.f("cruise")) < 4.0, "%s cruising (%.1f m/s)" % [tag, c.flight.speed])
	await p.screenshot("%s_3_cruise_view" % tag)
	p.release(&"move_forward")
	p.hold(&"move_left")
	p.hold(&"move_forward", 0.4)
	var min_bank := 0.0
	var h0 := c.flight.heading
	for i in 16:
		await _fly_for(0.25)
		min_bank = minf(min_bank, c.flight.bank)
		if i == 8:
			await p.screenshot("%s_3_bank_view" % tag)
		if i == 10:
			await _observe("%s_3_bank_front" % tag, Vector3(-0.35, 0.12, 1.6), 1.0, true)
		if i == 13:
			await _observe("%s_3_bank_behind" % tag, Vector3(0.25, 0.35, -1.7), 1.0, true)
	var turned := absf(wrapf(c.flight.heading - h0, -PI, PI))
	p.check(min_bank < -0.2, "%s banks into the left turn (%.2f rad)" % [tag, min_bank])
	p.check(turned > 0.8, "%s turned %.0f deg" % [tag, rad_to_deg(turned)])
	p.release(&"move_left")
	p.hold(&"move_forward")
	p.hold(&"jump")
	await _fly_for(2.5)
	p.release(&"jump")
	await _observe("%s_3_climb_side" % tag, Vector3(1.6, -0.1, 0.0), 1.1, true)
	p.hold(&"sprint")
	await _fly_for(4.0)
	p.check(c.flight.speed > c.flight.f("cruise") + 5.0, "%s boost (%.1f m/s)" % [tag, c.flight.speed])
	await p.screenshot("%s_3_boost_view" % tag)
	p.release(&"sprint")
	p.release(&"move_forward")
	await _fly_for(2.0)
	p.check(c.flight.speed >= c.flight.f("min") - 0.1, "%s gliding, no stall (%.1f)" % [tag, c.flight.speed])
	await _observe("%s_3_glide_side" % tag, Vector3(1.5, 0.15, 0.3), 1.0, true)

	# 4) Low pass: dive, then hold altitude toward the terrain ahead.
	p.hold(&"descend")
	p.hold(&"move_forward")
	await _fly_for(1.2)
	p.release(&"descend")
	await _fly_for(5.0)
	await p.screenshot("%s_4_low_pass_view" % tag)
	p.release(&"move_forward")
	p.note("%s low pass: min clearance %.1f m, avoiding %.2f, alt %.1f" % [tag, min_clear, c.flight.avoiding, c.flight.altitude()])
	p.check(min_clear > 0.2, "%s never below the terrain / sea (min %.2f m)" % [tag, min_clear])

	# 5) Landing.
	p.hold(&"descend")
	var landed := await _until(func() -> bool: return c.flight.phase == CompanionFlight.Phase.LANDING or not c.flight.is_active(), 14.0)
	p.check(landed, "%s landing started (%s, alt %.1f)" % [tag, c.flight.phase_name(), c.flight.altitude()])
	await p.wait_game(0.6)
	await _observe("%s_5_landing" % tag, Vector3(1.4, 0.25, -0.9), 1.1)
	landed = await _until(func() -> bool: return not c.flight.is_active(), 10.0)
	p.release(&"descend")
	p.check(landed and c.mode == Companion.Mode.RIDDEN, "%s touched down, still ridden (%s)" % [tag, c.get_mode_name()])
	await p.wait_game(1.2)
	await _observe("%s_5_landed_side" % tag, Vector3(1.3, 0.4, 0.7), 1.0)
	p.check(max_rider_err < 0.15, "%s rider stayed on the saddle (max %.3f m)" % [tag, max_rider_err])

	# 6) Take off again, climb, let go in the air.
	await p.tap(&"jump")
	await _until(func() -> bool: return c.flight.phase == CompanionFlight.Phase.FLY, 6.0)
	p.hold(&"move_forward")
	p.hold(&"jump")
	await _fly_for(3.0)
	p.release(&"jump")
	p.release(&"move_forward")
	var alt := c.flight.altitude()
	await p.tap(&"mount")
	await p.wait_game(0.6)
	p.check(pl.get_state() == PlayerCharacter.State.AIRBORNE, "%s let go at %.0f m: falling (%s)" % [tag, alt, pl.get_state_name()])
	await _observe("%s_6_falling" % tag, Vector3(1.2, 0.2, 0.4), 1.2, true)
	ok = await p.wait_until(func() -> bool: return pl.motor.on_floor or pl.motor.swimming, 60.0)
	p.check(ok and pl.is_alive(), "%s rider landed safely" % tag)
	ok = await _until(func() -> bool: return c.mode == Companion.Mode.FOLLOW and not c.is_flying(), 40.0)
	p.check(ok, "%s flyer landed near the rider (%s %s, %.1f m)" % [tag, c.get_mode_name(), c.flight.phase_name(),
			c.global_position.distance_to(pl.global_position)])
	await p.wait_game(1.0)
	await p.screenshot("%s_6_back_on_foot_view" % tag)


func _fly_for(t: float) -> void:
	var n := int(t / 0.1)
	for i in n:
		await p.wait_game(0.1)
		_sample()


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await p.wait_game(0.1)
		_sample()
		t += 0.1
	return cond.call()


func _sample() -> void:
	var q := c.global_position
	if c.is_airborne():
		min_clear = minf(min_clear, q.y - CompanionNav.surface_y(q.x, q.z))
	if c.mode == Companion.Mode.RIDDEN:
		max_rider_err = maxf(max_rider_err, pl.global_position.distance_to(c.rider.seat.global_position))


## Observer shot: `rel` = offset in units of the creature's length (x right, y up, z ahead).
func _observe(shot_name: String, rel: Vector3, frame: float, track: bool = false) -> void:
	var L := minf(float(c.rig.get_dimensions().get("length", 6.0)), 12.0)
	var fwd := CompanionNav.dir_of(c.flight.heading if c.flight and c.flight.is_active() else c.motor.yaw)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var focus := c.global_position + Vector3.UP * c.prof.body_height() * 0.6
	var lead := c.velocity * 0.15 if track else Vector3.ZERO
	var pos := focus + lead + (right * rel.x + Vector3.UP * rel.y + fwd * rel.z) * L * frame * 1.4
	pos.y = maxf(pos.y, CompanionNav.surface_y(pos.x, pos.z) + 1.2)
	pos = Follow.unblocked(c, focus + lead, pos)
	cam.global_position = pos
	cam.look_at(focus + lead, Vector3.UP)
	cam.make_current()
	await p.frames(1)
	await p.screenshot(shot_name)
	pl.camera_rig.make_current()
