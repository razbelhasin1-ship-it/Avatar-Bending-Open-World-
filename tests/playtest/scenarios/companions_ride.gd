extends RefCounted
## Ground mounts in the real world, ridden with InputMap actions only:
##   polar bear dog (Water, snowfields of the north): mount, trot, full gallop through deep
##   snow, a leap (jump), dismount (hop down beside it);
##   badgermole (Earth, hills by Ba Sing Se): mount, run up rugged slopes, burrow (descend:
##   digs in, tunnels toward the camera's aim point with a crack + dust trail on the surface,
##   bursts out at the target, rider still seated), dismount.
## SPECIES=polar_bear_dog|badgermole limits it to one. Observer + player-camera shots.

const E := ElementDefs.Element
const Follow := preload("res://tests/playtest/scenarios/companions_follow.gd")

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var c: Companion
var cam: Camera3D
var tag := ""
var max_rider_err := 0.0
var min_clear := INF


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("SPECIES")
	for pair: Array in [[&"polar_bear_dog", E.WATER], [&"badgermole", E.EARTH]]:
		if only != "" and String(pair[0]) != only:
			continue
		await _ride(pair[0], pair[1])


func _ride(species: StringName, e: int) -> void:
	tag = String(species)
	max_rider_err = 0.0
	min_clear = INF
	GameState.new_game(e)
	GameState.intro_done = true
	GameState.time_of_day = 11.0
	var spawn: Transform3D = Follow.route_start(WorldData.get_spawn(e).origin, 140.0, 30.0 if species == &"badgermole" else 22.0)
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
	# Mount from the flank.
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var stand := c.global_position - right * (c.prof.radius() + 1.2)
	stand.y = WorldData.get_height(stand.x, stand.z) + 0.1
	pl.teleport(Transform3D(Basis(Vector3.UP, CompanionNav.yaw_of(CompanionNav.flat_dir(c.global_position - stand))), stand))
	await p.wait_game(0.5)
	await p.screenshot("%s_0_prompt_view" % tag)
	await p.tap(&"mount")
	await p.wait_game(c.rider.duration * 0.5)
	await _observe("%s_1_mount_leap" % tag, Vector3(1.4, 0.45, 0.4))
	ok = await _until(func() -> bool: return c.mode == Companion.Mode.RIDDEN, 4.0)
	p.check(ok, "%s seated" % tag)
	await p.wait_game(0.5)
	await _observe("%s_1_seated" % tag, Vector3(1.3, 0.5, 0.8))
	# Point the camera along the mount and ride.
	pl.camera_rig.set_yaw(c.motor.yaw)
	var start := c.global_position
	p.hold(&"move_forward")
	await _ride_for(2.5)
	p.note("%s trot %.1f m/s" % [tag, c.motor.speed])
	p.hold(&"sprint")
	await _ride_for(4.0)
	var top := Vector2(c.velocity.x, c.velocity.z).length()
	p.note("%s sprint %.1f m/s (snow %.2f m, slope %.0f deg)" % [tag, top, WorldData.get_snow_depth(c.global_position.x, c.global_position.z),
			WorldData.get_slope_deg(c.global_position.x, c.global_position.z)])
	p.check(top > c.prof.f(c.prof.ride, "sprint") * 0.75, "%s full speed (%.1f of %.1f m/s)" % [tag, top, c.prof.f(c.prof.ride, "sprint")])
	await p.screenshot("%s_2_gallop_view" % tag)
	await _observe("%s_2_gallop_side" % tag, Vector3(1.5, 0.3, 0.5), true)
	p.hold(&"move_left", 0.6)
	await _ride_for(2.0)
	p.release(&"move_left")
	await _observe("%s_2_turn_front" % tag, Vector3(-0.4, 0.25, 1.6), true)
	if c.prof.f(c.prof.ride, "jump") > 0.0:
		await p.tap(&"jump")
		await p.wait_game(0.35)
		await _observe("%s_3_leap" % tag, Vector3(1.6, 0.25, 0.2), true)
		await _ride_for(1.0)
	p.release(&"sprint")
	p.release(&"move_forward")
	await _ride_for(2.0)
	p.check(c.global_position.distance_to(start) > 40.0, "%s covered ground (%.0f m)" % [tag, c.global_position.distance_to(start)])
	p.check(max_rider_err < 0.12, "%s rider attached (max %.3f m)" % [tag, max_rider_err])
	p.check(min_clear > -0.6, "%s on the terrain (min %.2f)" % [tag, min_clear])
	if c.burrow != null:
		await _burrow()
	# Dismount.
	await p.tap(&"mount")
	await p.wait_game(0.3)
	await _observe("%s_9_dismount" % tag, Vector3(1.3, 0.45, 0.6))
	ok = await _until(func() -> bool: return pl.get_state() == PlayerCharacter.State.LOCOMOTION, 4.0)
	p.check(ok and pl.motor.on_floor, "%s back on foot (%s)" % [tag, pl.get_state_name()])
	await p.wait_game(1.0)
	await p.screenshot("%s_9_on_foot_view" % tag)


func _burrow() -> void:
	# Aim the camera ahead and down a little: the tunnel goes where the player looks.
	pl.camera_rig.set_yaw(c.motor.yaw)
	pl.camera_rig.pitch = deg_to_rad(20.0)
	await p.wait_game(0.5)
	var from := c.global_position
	p.hold(&"descend")
	await p.wait_game(0.15)
	p.release(&"descend")
	var started := await _until(func() -> bool: return c.mode == Companion.Mode.BURROW, 1.0)
	p.check(started, "%s descend digs in (%s)" % [tag, c.get_mode_name()])
	if not started:
		return
	var target := c.burrow.target
	await p.wait_game(1.0)
	await _observe("%s_4_dig_in" % tag, Vector3(1.3, 0.35, 0.9))
	await _until(func() -> bool: return c.burrow.phase == CompanionBurrow.Phase.TRAVEL, 4.0)
	await p.wait_game(0.8)
	await p.screenshot("%s_5_tunnel_view" % tag)
	await _observe("%s_5_tunnel_trail" % tag, Vector3(1.6, 1.1, -0.6))
	await _until(func() -> bool: return c.burrow.phase == CompanionBurrow.Phase.EMERGE, 8.0)
	await p.wait_game(0.25)
	await _observe("%s_6_emerge_burst" % tag, Vector3(1.4, 0.4, 1.0))
	var done := await _until(func() -> bool: return not c.burrow.is_active(), 6.0)
	p.check(done and c.mode == Companion.Mode.RIDDEN, "%s emerged, still ridden (%s)" % [tag, c.get_mode_name()])
	p.check(Vector2(c.global_position.x - target.x, c.global_position.z - target.z).length() < 1.5, "%s emerged at the target" % tag)
	p.note("%s tunnel %.1f m" % [tag, Vector2(from.x - target.x, from.z - target.z).length()])
	p.check(pl.visual.rig.visible, "%s rider visible again" % tag)
	await p.wait_game(0.8)
	await p.screenshot("%s_6_emerged_view" % tag)


func _ride_for(t: float) -> void:
	for i in int(t / 0.1):
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
	min_clear = minf(min_clear, q.y - WorldData.get_height(q.x, q.z))
	if c.mode == Companion.Mode.RIDDEN:
		max_rider_err = maxf(max_rider_err, pl.global_position.distance_to(c.rider.seat.global_position))


func _observe(shot_name: String, rel: Vector3, track: bool = false) -> void:
	var L := float(c.rig.get_dimensions().get("length", 4.0))
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var focus := c.global_position + Vector3.UP * c.prof.body_height() * 0.65
	var lead := c.velocity * 0.12 if track else Vector3.ZERO
	var pos := focus + lead + (right * rel.x + Vector3.UP * rel.y + fwd * rel.z) * L * 1.5
	pos.y = maxf(pos.y, WorldData.get_height(pos.x, pos.z) + 1.0)
	pos = Follow.unblocked(c, focus + lead, pos)
	cam.global_position = pos
	cam.look_at(focus + lead, Vector3.UP)
	cam.make_current()
	await p.frames(1)
	await p.screenshot(shot_name)
	pl.camera_rig.make_current()
