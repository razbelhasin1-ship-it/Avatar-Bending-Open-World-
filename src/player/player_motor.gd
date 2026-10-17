class_name PlayerMotor
extends RefCounted
## Movement physics of a CharacterBody3D driven by a LocomotionProfile:
## acceleration/deceleration, momentum-preserving turns ("carving"), facing turn
## rate, jumps with coyote time + jump buffer, Air double jump and glide, slopes
## and step-up, deep snow slowdown, wading and swimming (never drowns), Water
## skating on snow/ice.
##
## The owner calls, once per physics tick and in this order:
##   motor.sense()                         # ground / water info
##   motor.locomote(dt, move, sprint, face) or air_move / swim / brake ...
##   motor.integrate(dt)                   # gravity + move_and_slide + step-up
## and reads `landed_this_tick`, `impact_speed`, `fall_height` afterwards.

signal jumped(kind: StringName)
signal landed(impact_speed: float, fall_height: float)

const TERMINAL_SPEED := 45.0
const SWIM_DEPTH := 1.3
const SWIM_EXIT_DEPTH := 1.1

var body: CharacterBody3D
var profile: LocomotionProfile

# --- sensed state ----------------------------------------------------------------
var on_floor := true
var floor_normal := Vector3.UP
var surface: StringName = &"grass"
var snow_depth := 0.0
var water_height := -INF
## Water depth over the feet (0 when dry).
var water_depth := 0.0
var swimming := false
var skating := false
var gliding := false
# --- air state ----------------------------------------------------------------------
var air_time := 0.0
var since_floor := 0.0
var air_jumps_used := 0
var jumped_this_air := false
var peak_y := 0.0
var landed_this_tick := false
var impact_speed := 0.0
var fall_height := 0.0
## Facing yaw (radians, 0 faces -Z). Applied to body.rotation.y.
var yaw := 0.0
var _yaw_target_smooth := 0.0
var _jump_buffer := 0.0
var _prev_vy := 0.0
var _last_safe := Vector3.INF
var _sense_tick := 0
## Horizontal speed multiplier from external effects (armor, chill...). 1 = none.
var speed_scale := 1.0
## The body is carried by something else (a mount's seat, collision off): no floor sensing and
## the seat never becomes the last safe ground. is_on_floor() keeps the value of the last
## move_and_slide before mounting, so without this every saddle position (high up on a flyer)
## was recorded as safe ground and saves made in flight continued in mid-air (bughunt_gameplay).
var carried := false
## Climbing out of water: keep pushing onto the ledge for this long.
var _climb_time := 0.0


func _init(p_body: CharacterBody3D, p_profile: LocomotionProfile) -> void:
	body = p_body
	set_profile(p_profile)
	yaw = body.rotation.y
	_yaw_target_smooth = yaw


func set_profile(p: LocomotionProfile) -> void:
	profile = p
	body.floor_max_angle = deg_to_rad(p.max_slope_deg)
	body.floor_snap_length = 0.42
	body.floor_constant_speed = true
	body.floor_block_on_wall = true
	body.max_slides = 5


## Updates floor / surface / water information. Call first every tick.
func sense() -> void:
	_sense_tick += 1
	on_floor = body.is_on_floor() and not carried
	floor_normal = body.get_floor_normal() if on_floor else Vector3.UP
	var pos := body.global_position
	# Surface queries are cheap but not free; refresh at 20 Hz.
	if _sense_tick % 3 == 1 or _sense_tick < 3:
		surface = GroundSampler.surface(pos)
		snow_depth = GroundSampler.snow_depth(pos)
		water_height = GroundSampler.water_height(pos)
	water_depth = maxf(0.0, water_height - pos.y) if water_height > -INF else 0.0
	if swimming:
		swimming = not (water_depth < SWIM_EXIT_DEPTH and on_floor) and water_depth > 0.6
	else:
		swimming = water_depth > SWIM_DEPTH + (0.25 if on_floor else 0.0)
	if on_floor and not swimming:
		since_floor = 0.0
		if water_depth < 0.4 and floor_normal.angle_to(Vector3.UP) < deg_to_rad(32.0):
			_last_safe = pos
	else:
		since_floor += 1.0 / Engine.physics_ticks_per_second


## Last position the body stood on dry, walkable ground (respawn fallback).
func last_safe_position() -> Vector3:
	return _last_safe if _last_safe.is_finite() else body.global_position


## While `carried`: the carrier (a ground mount) stands on the floor at `pos`. Dry, walkable
## ground there is the rider's safe ground, so a save mid-ride continues where the mount stands
## rather than where the ride began. A flying mount is never on the floor; a swimming or wading
## one is rejected by the water check (bughunt_gameplay).
func carrier_on_floor(pos: Vector3, normal: Vector3) -> void:
	if not carried or not pos.is_finite() or normal.angle_to(Vector3.UP) > deg_to_rad(32.0):
		return
	if water_height > -INF and water_height > pos.y - 0.5:
		return
	_last_safe = pos


## Snow / wading speed factor for ground movement.
func terrain_speed_factor(sprinting: bool) -> float:
	var f := 1.0
	if snow_depth > 0.05 and not (profile.snow_ignored_when_sprinting and sprinting):
		f *= 1.0 - profile.snow_slow_max * clampf((snow_depth - 0.05) / 0.45, 0.0, 1.0)
	if water_depth > 0.25 and not swimming:
		f *= 1.0 - profile.wade_slow_max * clampf((water_depth - 0.25) / 0.95, 0.0, 1.0)
	return f * speed_scale


## True if Water can skate here (sprinting on snow/ice).
func can_skate_here() -> bool:
	return profile.can_skate() and on_floor and (surface == &"ice" or surface == &"snow") and water_depth < 0.2


# --- ground / air movement ---------------------------------------------------------------

## Ground locomotion toward `move` (world dir, length = stick magnitude).
## `face_dir`: optional facing override (lock-on strafing); ZERO = face travel.
func locomote(delta: float, move: Vector3, sprint: bool, face_dir: Vector3 = Vector3.ZERO) -> void:
	var p := profile
	var mag := clampf(move.length(), 0.0, 1.0)
	skating = sprint and mag > 0.5 and can_skate_here()
	var top := p.skate_speed if skating else p.target_speed(mag, sprint)
	top *= terrain_speed_factor(sprint)
	var desired := move.normalized() * top if mag > 0.05 else Vector3.ZERO
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var accel := p.accel * (0.55 if skating else 1.0)
	var decel := p.decel * (0.35 if skating else 1.0)
	hv = _approach(hv, desired, accel, decel, deg_to_rad(p.turn_rate) * (0.6 if skating else 1.0), delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	var face := face_dir
	if face == Vector3.ZERO:
		if hv.length() > 0.6:
			face = hv
		elif mag > 0.05:
			face = move
	if face != Vector3.ZERO:
		turn_toward(face, delta)


## Air movement with reduced control; momentum is kept without input.
func air_move(delta: float, move: Vector3, sprint: bool, face_dir: Vector3 = Vector3.ZERO) -> void:
	var p := profile
	var mag := clampf(move.length(), 0.0, 1.0)
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if _climb_time > 0.0:
		# Vaulting out of water: keep driving onto the ledge until landed.
		_climb_time -= delta
		var f := _forward() * 3.0
		body.velocity.x = f.x
		body.velocity.z = f.z
		return
	if gliding:
		var top := p.glide_speed
		var fwd := move.normalized() if mag > 0.05 else _forward()
		var desired := fwd * top
		hv = _approach(hv, desired, p.accel * 0.35, p.decel * 0.1, deg_to_rad(p.turn_rate) * 0.35, delta)
		turn_toward(hv if hv.length() > 0.5 else fwd, delta, 0.5)
	elif mag > 0.05:
		var top := maxf(p.target_speed(mag, sprint), hv.length() if hv.dot(move) > 0.0 else 0.0)
		top = minf(top, maxf(p.sprint_speed, p.skate_speed) * 1.05)
		var desired := move.normalized() * top
		hv = hv.move_toward(desired, p.accel * p.air_control * delta)
		var face := face_dir if face_dir != Vector3.ZERO else move
		turn_toward(face, delta, 0.6)
	else:
		hv = hv.move_toward(Vector3.ZERO, 0.6 * delta)
		if face_dir != Vector3.ZERO:
			turn_toward(face_dir, delta, 0.6)
	body.velocity.x = hv.x
	body.velocity.z = hv.z


## Swimming: buoyancy holds the chest at the surface; never sinks or drowns.
func swim(delta: float, move: Vector3, sprint: bool) -> void:
	var p := profile
	var mag := clampf(move.length(), 0.0, 1.0)
	var top := (p.swim_sprint_speed if sprint else p.swim_speed) * mag
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z)
	hv = hv.move_toward(move.normalized() * top if mag > 0.05 else Vector3.ZERO, 6.0 * delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	var target_y := water_height - SWIM_DEPTH
	var err := target_y - body.global_position.y
	body.velocity.y = lerpf(body.velocity.y, clampf(err * 4.0, -3.0, 3.0), 1.0 - exp(-delta * 6.0))
	if mag > 0.05:
		turn_toward(move, delta, 0.5)


## Decelerates horizontal velocity (actions, stuns).
func brake(delta: float, rate: float) -> void:
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(Vector3.ZERO, rate * delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z


## Moves horizontal velocity toward `v` at `rate` (dashes, lunges).
func drive(delta: float, v: Vector3, rate: float) -> void:
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(Vector3(v.x, 0.0, v.z), rate * delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z


func _approach(hv: Vector3, desired: Vector3, accel: float, decel: float, turn_rad: float, delta: float) -> Vector3:
	var speed := hv.length()
	if desired != Vector3.ZERO and speed > 0.5:
		var ang := Vector2(hv.x, hv.z).angle_to(Vector2(desired.x, desired.z))
		if absf(ang) < deg_to_rad(135.0):
			# Carve: rotate momentum at the turn rate, keep speed.
			var max_rot := turn_rad * delta
			hv = hv.rotated(Vector3.UP, -clampf(ang, -max_rot, max_rot))
	var speeding_up := desired.length() > hv.length() - 0.01 and hv.dot(desired) >= 0.0
	return hv.move_toward(desired, (accel if speeding_up else decel) * delta)


# --- facing ------------------------------------------------------------------------------

func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Turns the facing toward `dir` at the profile turn rate (× rate_mult).
func turn_toward(dir: Vector3, delta: float, rate_mult: float = 1.0) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-6:
		return
	var target := yaw_of(d)
	if profile.turn_smoothing > 0.0:
		var k := 1.0 - exp(-delta / profile.turn_smoothing)
		_yaw_target_smooth = lerp_angle(_yaw_target_smooth, target, k)
		target = _yaw_target_smooth
	else:
		_yaw_target_smooth = target
	var step := deg_to_rad(profile.turn_rate * rate_mult) * delta
	yaw = _rotate_toward(yaw, target, step)
	body.rotation.y = yaw


## Instantly faces `dir` (attack snapping, respawn).
func face(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-6:
		return
	yaw = yaw_of(d)
	_yaw_target_smooth = yaw
	body.rotation.y = yaw


## Fast turn toward `dir` limited to `deg_per_sec`.
func face_toward(dir: Vector3, delta: float, deg_per_sec: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-6:
		return
	yaw = _rotate_toward(yaw, yaw_of(d), deg_to_rad(deg_per_sec) * delta)
	_yaw_target_smooth = yaw
	body.rotation.y = yaw


static func _rotate_toward(from: float, to: float, step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	if absf(diff) <= step:
		return wrapf(to, -PI, PI)
	return wrapf(from + signf(diff) * step, -PI, PI)


# --- jumping ------------------------------------------------------------------------------

## Registers a jump press (buffered for profile.jump_buffer seconds).
func press_jump() -> void:
	_jump_buffer = profile.jump_buffer


func has_buffered_jump() -> bool:
	return _jump_buffer > 0.0


## Ground jump (with coyote time). Returns true if it jumped.
func try_ground_jump() -> bool:
	if _jump_buffer <= 0.0 or swimming:
		return false
	if not (on_floor or (since_floor <= profile.coyote_time and not jumped_this_air)):
		return false
	_jump_buffer = 0.0
	var v := profile.jump_velocity
	if water_depth > 0.5:
		v *= 0.75
	body.velocity.y = v
	jumped_this_air = true
	on_floor = false
	since_floor = profile.coyote_time + 1.0
	peak_y = body.global_position.y
	jumped.emit(&"jump")
	return true


## Air jump (Air element). Returns true if it jumped.
func try_air_jump() -> bool:
	if profile.air_jumps <= 0 or air_jumps_used >= profile.air_jumps or on_floor or swimming:
		return false
	air_jumps_used += 1
	gliding = false
	_jump_buffer = 0.0
	body.velocity.y = profile.air_jump_velocity
	peak_y = body.global_position.y
	jumped.emit(&"air_jump")
	return true


## Climb out of water onto a nearby ledge.
func try_swim_exit() -> bool:
	if not swimming:
		return false
	var fwd := _forward()
	var xf := body.global_transform
	if not body.test_move(xf, fwd * 0.6):
		return false
	# Wall ahead: is there standing room above it?
	var up := Vector3.UP * 1.8
	if body.test_move(xf, up):
		return false
	if body.test_move(xf.translated(up), fwd * 0.8):
		return false
	# Ledge height (ray down just past the wall) -> exact vault velocity.
	var from := body.global_position + fwd * 0.75 + up
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.5, Layers.SOLID)
	var ex: Array[RID] = [body.get_rid()]
	q.exclude = ex
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	var top: float = (hit["position"] as Vector3).y if not hit.is_empty() else body.global_position.y + 1.4
	var rise := maxf(0.5, top - body.global_position.y + 0.65)
	body.velocity.y = sqrt(2.0 * profile.gravity() * rise)
	body.velocity.x = fwd.x * 3.0
	body.velocity.z = fwd.z * 3.0
	swimming = false
	_climb_time = 1.0
	jumped.emit(&"climb")
	return true


## Variable jump height: releasing jump early cuts the rise of a GROUND jump
## (the Air jump is a burst of wind and always gives its full height).
func release_jump() -> void:
	if body.velocity.y > 2.0 and not gliding and air_jumps_used == 0 and _climb_time <= 0.0:
		body.velocity.y *= 0.55


func set_gliding(on: bool) -> void:
	gliding = on and profile.can_glide() and not on_floor and not swimming


# --- integration ---------------------------------------------------------------------------

## Gravity + move_and_slide + step-up + landing detection.
## `gravity_mult` 0 disables gravity (dashes, swimming handles its own).
func integrate(delta: float, gravity_mult: float = 1.0) -> void:
	landed_this_tick = false
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	var was_floor := on_floor
	if not swimming and gravity_mult > 0.0:
		var g := profile.gravity() * gravity_mult
		if body.velocity.y < 0.0:
			g *= profile.fall_gravity_mult
		body.velocity.y = maxf(body.velocity.y - g * delta, -TERMINAL_SPEED)
		if gliding:
			body.velocity.y = maxf(body.velocity.y, -profile.glide_fall_speed)
	elif swimming:
		pass
	if on_floor and body.velocity.y <= 0.0 and not swimming:
		# Keep a small downward push so floor snapping holds on slopes.
		body.velocity.y = minf(body.velocity.y, -0.5)
	_prev_vy = body.velocity.y
	var hv_before := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var pos_before := body.global_position
	body.move_and_slide()
	if was_floor and hv_before.length() > 0.5:
		_try_step_up(hv_before, pos_before, delta)
	var now_floor := body.is_on_floor()
	if not now_floor:
		air_time += delta
		peak_y = maxf(peak_y, body.global_position.y)
	if now_floor and not was_floor and air_time > 0.05:
		landed_this_tick = true
		impact_speed = maxf(0.0, -_prev_vy)
		fall_height = maxf(0.0, peak_y - body.global_position.y)
		landed.emit(impact_speed, fall_height)
	if now_floor:
		air_time = 0.0
		air_jumps_used = 0
		jumped_this_air = false
		gliding = false
		_climb_time = 0.0
		peak_y = body.global_position.y
	on_floor = now_floor


func _try_step_up(hv: Vector3, pos_before: Vector3, delta: float) -> void:
	var moved := body.global_position - pos_before
	moved.y = 0.0
	var intended := hv * delta
	if moved.length() > intended.length() * 0.6:
		return
	var blocked := false
	for i in body.get_slide_collision_count():
		var n := body.get_slide_collision(i).get_normal()
		if n.angle_to(Vector3.UP) > deg_to_rad(profile.max_slope_deg + 5.0) and n.dot(hv) < 0.0:
			blocked = true
			break
	if not blocked:
		return
	var step := Vector3.UP * profile.step_height
	var dir := hv.normalized()
	var motion := dir * maxf(0.18, intended.length())
	var xf := body.global_transform
	if body.test_move(xf, step):
		return
	var xf2 := xf.translated(step)
	if body.test_move(xf2, motion):
		return
	var xf3 := xf2.translated(motion)
	var col := KinematicCollision3D.new()
	if body.test_move(xf3, -step * 1.2, col):
		if col.get_normal().angle_to(Vector3.UP) > deg_to_rad(profile.max_slope_deg):
			return
		body.global_position = xf3.origin + col.get_travel()
		body.apply_floor_snap()


## Teleports the body and resets air/water state (respawn, cinematics). `mark_safe` = false
## for destinations that may be mid-air or in water (letting go of a flying mount): the last
## safe ground then stays where the body last stood (saves / rescues use it).
func teleport(xform: Transform3D, mark_safe: bool = true) -> void:
	body.global_position = xform.origin
	body.velocity = Vector3.ZERO
	var f := -xform.basis.z
	if Vector2(f.x, f.z).length() > 0.01:
		face(f)
	air_time = 0.0
	air_jumps_used = 0
	gliding = false
	swimming = false
	_climb_time = 0.0
	peak_y = xform.origin.y
	if mark_safe or not _last_safe.is_finite():
		_last_safe = xform.origin
