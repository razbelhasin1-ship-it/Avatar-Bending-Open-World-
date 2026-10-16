class_name CompanionRider
extends RefCounted
## Mounting, riding and dismounting: the player is seated through
## `PlayerCharacter.mount_on(companion, seat)` and follows `seat` every physics tick.
##
## * `seat` is a top-level Node3D owned here. While riding it is the rig's `saddle` socket
##   recomputed from the body's CURRENT transform each tick (the companion ticks before the
##   player), so the rider never lags behind a fast mount; during transitions it flies along
##   an arc (Bezier leap from the ground up to the saddle, or down beside the creature).
## * The rider's HumanoidRig is tilted with the saddle (bank / pitch) while seated and is
##   reset on every exit path; it is hidden while the saddle is underground (burrow).
## * Mount: walk up to the companion and press mount (or interact: the prompt is a
##   CompanionMountPoint Interactable), also mid-air next to a flying mount (catch).
## * Dismount: mount / interact again: an animated hop down beside it on the ground, or the
##   rider lets go in the air (falls / glides; the flyer escorts and can catch them again).

enum Phase { NONE, MOUNTING, RIDING, DISMOUNTING }

const MOUNT_REACH := 2.4
const CATCH_REACH := 7.5

var c: Companion
var phase: int = Phase.NONE
var player: PlayerCharacter = null
var seat: Node3D
var mount_point: CompanionMountPoint
var t := 0.0
var duration := 0.9
## Mounts that happened through a mid-air catch (stats / tests).
var catches := 0

var _from := Transform3D.IDENTITY
var _to_ground := Vector3.ZERO
var _apex := 1.0
var _hidden := false
var _releasing := false
var _air_mount := false


func _init(p_c: Companion) -> void:
	c = p_c
	seat = Node3D.new()
	seat.name = "RiderSeat"
	seat.top_level = true
	c.add_child(seat)
	mount_point = CompanionMountPoint.new()
	mount_point.name = "MountPoint"
	mount_point.companion = c
	mount_point.prompt = "Ride the %s" % c.display_name
	mount_point.radius = c.prof.radius() + MOUNT_REACH
	mount_point.focus_offset = Vector3(0.0, minf(c.prof.body_height() * 0.5, 1.4), 0.0)
	c.add_child(mount_point)


func is_releasing() -> bool:
	return _releasing


## Saddle socket (or the body top as a fallback).
func saddle() -> Node3D:
	return c.rig.get_socket(&"saddle") if c.rig else null


func saddle_transform() -> Transform3D:
	var s := saddle()
	if s != null:
		return c.rig.global_transform * s.transform
	return c.global_transform.translated(Vector3.UP * c.prof.body_height())


## In range and both free: the player stands (or, for a flyer in the air, falls) next to it.
func can_mount(p: Node3D) -> bool:
	var pc := p as PlayerCharacter
	if pc == null or phase != Phase.NONE or not c.is_inside_tree():
		return false
	if c.mode in [Companion.Mode.MOUNTING, Companion.Mode.RIDDEN, Companion.Mode.DISMOUNTING, Companion.Mode.BURROW]:
		return false
	if c.flight != null and (c.flight.phase == CompanionFlight.Phase.TAKEOFF or c.flight.phase == CompanionFlight.Phase.LANDING):
		return false
	var st := pc.get_state()
	if c.is_airborne():
		# Mid-air catch: the player is falling / gliding right next to the flyer's saddle.
		return st == PlayerCharacter.State.AIRBORNE and pc.global_position.distance_to(saddle_transform().origin) < CATCH_REACH
	# INTERACTING: the mount prompt (Interactable) locks the player for a moment first.
	if st != PlayerCharacter.State.LOCOMOTION and st != PlayerCharacter.State.INTERACTING:
		return false
	var to := pc.global_position - c.global_position
	if absf(to.y) > c.prof.body_height() + 1.5:
		return false
	to.y = 0.0
	# Distance to the body's long axis (long creatures can be mounted from the flank).
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	var along := clampf(to.dot(fwd), -c.prof.radius() * 1.6, c.prof.radius() * 1.6)
	var lateral := (to - fwd * along).length()
	return lateral < c.prof.radius() + MOUNT_REACH


func begin_mount(p: Node3D) -> bool:
	if not can_mount(p):
		return false
	player = p as PlayerCharacter
	_air_mount = c.is_airborne()
	if _air_mount:
		catches += 1
	_releasing = false
	_from = player.global_transform
	var to := saddle_transform()
	var rise := maxf(to.origin.y - _from.origin.y, 0.0)
	duration = 0.35 if _air_mount else clampf(0.55 + rise * 0.1, 0.6, 1.0)
	_apex = 0.0 if _air_mount else 0.7 + rise * 0.25
	t = 0.0
	phase = Phase.MOUNTING
	seat.global_transform = _from
	if c.mode == Companion.Mode.ASSIST:
		c.assist.cancel()
	c.rig.stop_action()
	c.rig.clear_look()
	c.rig.idle_enabled = false
	c.set_mode(Companion.Mode.MOUNTING)
	player.mount_on(c, seat)
	if not _air_mount:
		player.visual.play(&"mount", {"blend_in": 0.08})
		_launch_fx(_from.origin)
	_apply_camera()
	return true


## Animated dismount on the ground: hop down beside the creature.
func begin_dismount() -> void:
	if phase != Phase.RIDING or player == null or not is_instance_valid(player):
		return
	var s := saddle_transform()
	_from = Transform3D(_yaw_basis(s.basis), s.origin)
	_to_ground = _ground_beside()
	duration = clampf(0.5 + (s.origin.y - _to_ground.y) * 0.06, 0.55, 0.85)
	_apex = 0.5
	t = 0.0
	phase = Phase.DISMOUNTING
	_set_tilt(Basis.IDENTITY)
	_show_rider()
	c.set_mode(Companion.Mode.DISMOUNTING)
	player.visual.play(&"dismount", {"blend_in": 0.06})


## Lets go in the air: the rider drops from the saddle with the mount's momentum.
func release_in_air() -> void:
	if phase != Phase.RIDING or player == null or not is_instance_valid(player):
		return
	var s := saddle_transform()
	var v := c.velocity
	var side := s.basis.x.normalized()
	var at := s.origin + side * (c.prof.radius() * 0.6 + 0.4) + Vector3.UP * 0.2
	var p := player
	var yaw := p.camera_rig.get_yaw() if p.camera_rig else 0.0
	_end_riding()
	_releasing = true
	p.dismount(at)
	_releasing = false
	p.velocity = Vector3(v.x * 0.85, maxf(v.y, 0.0) * 0.5 + 2.5, v.z * 0.85) + side * 2.0
	if p.camera_rig:
		p.camera_rig.set_yaw(yaw)   # dismount() snaps the camera behind: keep the view
	c.brain.land_requested = false
	c.set_mode(Companion.Mode.ESCORT)


## Every tick while MOUNTING / DISMOUNTING.
func tick_transition(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.get_state() != PlayerCharacter.State.MOUNTED:
		release_rider()
		c.set_mode(Companion.Mode.ESCORT if c.is_airborne() else Companion.Mode.FOLLOW)
		return
	t += delta
	var k := clampf(t / duration, 0.0, 1.0)
	# The mount waits while the rider climbs on / off (a flyer keeps flying).
	if c.is_airborne():
		c.flight.reset_intent()
		c.flight.want_dir = CompanionNav.dir_of(c.flight.heading)
		c.flight.hold_speed = c.flight.speed
		c.flight.step(delta)
	else:
		c.motor.brake(delta, 10.0)
	if phase == Phase.MOUNTING:
		var to := saddle_transform()
		var e := _ease(k)
		var pos := _arc(_from.origin, to.origin, e, _apex)
		var b := _from.basis.orthonormalized().slerp(_yaw_basis(to.basis), e)
		seat.global_transform = Transform3D(b, pos)
		if k >= 1.0:
			finish_mount()
	elif phase == Phase.DISMOUNTING:
		var e2 := _ease(k)
		var pos2 := _arc(_from.origin, _to_ground, e2, _apex)
		seat.global_transform = Transform3D(_from.basis, pos2)
		if k >= 1.0:
			finish_dismount()


func finish_mount() -> void:
	if phase != Phase.MOUNTING:
		return
	phase = Phase.RIDING
	if player and is_instance_valid(player) and player.visual:
		if player.visual.current_clip() == &"mount":
			player.visual.stop(0.2)
		player.visual.set_pose(&"riding", 0.15)
	c.set_mode(Companion.Mode.RIDDEN)
	c.ride.on_mounted()
	_apply_camera()
	c.rider_changed.emit(player)
	GameState.incr_stat("companion_rides")


func finish_dismount() -> void:
	if phase != Phase.DISMOUNTING:
		return
	var p := player
	var at := _to_ground
	var yaw := p.camera_rig.get_yaw() if p != null and is_instance_valid(p) and p.camera_rig else 0.0
	_end_riding()
	if p != null and is_instance_valid(p) and p.get_state() == PlayerCharacter.State.MOUNTED:
		_releasing = true
		p.dismount(at)
		_releasing = false
		if p.camera_rig:
			p.camera_rig.set_yaw(yaw)
	c.set_mode(Companion.Mode.FOLLOW)


## Ends any riding state without moving the player (external dismounts, freeing).
func release_rider() -> void:
	var p := player
	_end_riding()
	if p != null and is_instance_valid(p) and p.is_inside_tree() and p.get_state() == PlayerCharacter.State.MOUNTED and p.mount_node == c and not _releasing:
		# The seat may already be leaving the tree with the companion: drop the rider onto
		# the ground below where they are.
		var pp := p.global_position
		var space := p.get_world_3d().direct_space_state
		var gy := CompanionNav.ground_y(space, pp, 1.0, 80.0, [p.get_rid()])
		_releasing = true
		p.dismount(Vector3(pp.x, gy, pp.z))
		_releasing = false


func _end_riding() -> void:
	if player != null and is_instance_valid(player):
		_set_tilt(Basis.IDENTITY)
		_show_rider()
	var was := phase
	phase = Phase.NONE
	player = null
	t = 0.0
	if c.ride != null:
		c.ride.on_unmounted()
	if was != Phase.NONE:
		c.rider_changed.emit(null)


## Places the seat on the saddle (after the body moved this tick), tilts / hides the rider.
func update_seat(_delta: float) -> void:
	if phase != Phase.RIDING or player == null or not is_instance_valid(player):
		mount_point.enabled = phase == Phase.NONE and not c.is_airborne()
		return
	mount_point.enabled = false
	var s := saddle_transform()
	var b := s.basis.orthonormalized()
	var pos := s.origin
	# Underground (burrow): keep the (hidden) rider at the surface.
	var gy := WorldData.get_height(pos.x, pos.z)
	var under := pos.y < gy - 0.15 and c.burrow != null and c.burrow.is_active()
	if under:
		pos.y = maxf(pos.y, gy + 0.05)
		_hide_rider()
	elif _hidden and (c.burrow == null or not c.burrow.is_active() or pos.y > gy + 0.2):
		_show_rider()
	seat.global_transform = Transform3D(b, pos)
	_set_tilt(Basis(Vector3.UP, CompanionNav.yaw_of(CompanionNav.flat_dir(-b.z))).inverse() * b)
	if player.camera_rig and c.ride != null:
		c.ride.update_camera()


func _apply_camera() -> void:
	if player == null or player.camera_rig == null:
		return
	var params: Dictionary = c.prof.ride.get("camera", {}) if not c.is_airborne() else c.prof.flight.get("camera", {})
	player.camera_rig.set_mode(&"flight", params.duplicate())
	player.camera_rig.set_target_override(c)


func _set_tilt(local: Basis) -> void:
	if player == null or not is_instance_valid(player) or player.visual == null or player.visual.rig == null:
		return
	var prig := player.visual.rig
	var tr := prig.transform
	tr.basis = local.orthonormalized()
	prig.transform = tr


func _hide_rider() -> void:
	if _hidden or player == null or player.visual == null or player.visual.rig == null:
		return
	_hidden = true
	player.visual.rig.visible = false


func _show_rider() -> void:
	if not _hidden:
		return
	_hidden = false
	if player != null and is_instance_valid(player) and player.visual != null and player.visual.rig != null:
		player.visual.rig.visible = true


## Ground point beside the creature (left side, else right, else behind), on solid ground.
func _ground_beside() -> Vector3:
	var space := c.get_world_3d().direct_space_state
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var off := c.prof.radius() + 1.1
	var ex: Array[RID] = [c.get_rid()]
	if player:
		ex.append(player.get_rid())
	for dir: Vector3 in [-right, right, -fwd, fwd]:
		var p := c.global_position + dir * off
		var gy := CompanionNav.ground_y(space, Vector3(p.x, c.global_position.y + 3.0, p.z), 0.0, 8.0, ex)
		var g := Vector3(p.x, gy, p.z)
		if absf(gy - c.global_position.y) < 2.5 and CompanionNav.open_space(space, g, 0.35, ex) and CompanionNav.water_depth(p.x, p.z) < 1.0:
			return g
	return WorldData.get_safe_ground(c.global_position - right * off)


func _launch_fx(at: Vector3) -> void:
	if player == null:
		return
	var surf := WorldData.get_surface(at)
	if player.element == ElementDefs.Element.AIR:
		AirFx.ground_puff(c, at, surf, 0.9)
		Audio.play_sfx(&"air_jump", at, -4.0)
	else:
		FxBurst.spawn(c, &"dust", at, {"color": FxLib.surface_color(surf), "count": 0.5})
		Audio.play_sfx(&"jump", at, -6.0)


static func _yaw_basis(b: Basis) -> Basis:
	return Basis(Vector3.UP, CompanionNav.yaw_of(CompanionNav.flat_dir(-b.z)))


static func _arc(a: Vector3, b: Vector3, e: float, apex: float) -> Vector3:
	var top := maxf(a.y, b.y) + apex
	var mid := Vector3((a.x + b.x) * 0.5, top, (a.z + b.z) * 0.5)
	# Quadratic Bezier through a raised midpoint control (peak ~ apex above the higher end).
	var ctrl := mid * 2.0 - (a + b) * 0.5
	ctrl.y = top + apex * 0.5
	var u := 1.0 - e
	return a * u * u + ctrl * 2.0 * u * e + b * e * e


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)
