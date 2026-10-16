extends BendingAbility
## Air Scooter (mobility technique): the bender hops onto a spinning ball of air and
## rides it - 16.5 m/s, carving turns with momentum, coasting to a hover when the
## stick is released, skimming across water, and running up walls for a moment
## (0.9 s) before popping over the top or peeling off. Jump launches off the ball
## with the ride's momentum (then air jump / glide as usual); pressing the
## technique again hops down; a dodge dashes off. No attacks while riding (the
## controller keeps them buffered and they expire). Chi drains 4/s; out of chi, hit
## hard or after `max_time` the ball bursts. Non-player casters ride `ai_time` s
## following their move intent (chasing / closing distance).
## The ground answers the ride: a wind wake parts the grass, dust / leaves / snow /
## spray trail behind the ball.

enum Phase { RIDE, WALL, OFF }

var phase := Phase.RIDE
var vel := Vector3.ZERO
var ball: AirBallFx = null
var ride_time := 0.0
var wall_left := 0.9
var end_reason: StringName = &""

var _wall_n := Vector3.ZERO
var _off_wall := 0.0
var _impulse := 0
var _trail_t := 0.0
var _rig_y := 0.0
var _rig_ik := true
var _rig_set := false
var _yaw_rate := 0.0
var _last_yaw := 0.0
var _speed := 16.5
var _loop_id := 0


func can_use() -> StringName:
	AirCommon.prepare()
	if ctx.body == null:
		return &"no_body"
	return &""


func begin() -> void:
	_speed = float(param("speed", 16.5))
	wall_left = float(param("wall_time", 0.9))
	max_time = float(param("max_time", 22.0)) + 1.0 if ctx.is_player() else float(param("ai_time", 5.0)) + 1.0
	var hv := Vector3(ctx.body.velocity.x, 0.0, ctx.body.velocity.z)
	# Keep the run's momentum; a standing start gets a push in the facing direction.
	vel = hv if hv.length() > 4.0 else ctx.forward() * 6.0
	ctx.move_mode = BendingContext.Move.DRIVE
	ctx.move_velocity = vel
	ctx.face_dir = vel.normalized()
	ctx.face_rate = 720.0
	ctx.set_upkeep(float(param("upkeep", 4.0)))
	play_clip(def.clip, {"blend_in": 0.12})
	clip_end = INF
	cancel_at = 0.0
	_last_yaw = atan2(-vel.x, -vel.z)
	ball = AirBallFx.spawn(ctx.caster, float(param("ball_radius", 0.5)))
	_place_ball(0.0)
	if ctx.rig and is_instance_valid(ctx.rig):
		_rig_y = ctx.rig.position.y
		_rig_ik = ctx.rig.animator.foot_ik if ctx.rig.animator else true
		ctx.rig.set_foot_ik(false)
		_rig_set = true
	_loop_id = Audio.start_bending_loop(ctx.element, &"special_loop", ctx.caster, -9.0)
	var g := ctx.ground_point(ctx.origin())
	AirFx.ground_puff(ctx.caster, g, ctx.surface_at(g), 0.7)
	AirFx.swirl(ctx.caster, g + Vector3.UP * 0.4, 0.6, 0.35, {"grow": 2.0, "spin": 18.0, "height": 0.15, "opacity": 0.7})
	_impulse = AirWindField.add(ctx.caster, g, 1.8, 14.0, AirWindField.VORTEX, Vector3(1, 0, 0), INF)
	sound(&"dash", ctx.origin(), -2.0)
	AirEnv.practiced(ctx, def.id)



## Second press of the technique: hop down.
func on_repress() -> bool:
	if time < 0.2:
		return true
	_dismount(&"hop")
	return true


func can_cancel_into(slot_kind: StringName) -> bool:
	return slot_kind == &"dodge"


func update(delta: float) -> void:
	ride_time += delta
	if phase == Phase.OFF:
		if time >= clip_end:
			finish()
		return
	var inp := AirCommon.input(ctx)
	if inp != null and inp.consume(&"jump"):
		_jump_off()
		return
	if ctx.resources != null and ctx.chi() <= 0.5:
		_dismount(&"chi")
		return
	if ride_time > max_time - 1.0:
		_dismount(&"time")
		return
	match phase:
		Phase.RIDE:
			_ride(delta)
		Phase.WALL:
			_wall(delta)
	_place_ball(delta)
	_trail(delta)
	if _loop_id != 0:
		Audio.set_loop_pitch(_loop_id, 0.85 + clampf(vel.length() / _speed, 0.0, 1.0) * 0.5)


func _ride(delta: float) -> void:
	var body := ctx.body
	if body.is_on_wall():
		# Blocked (not a wall run): the ride keeps only the motion that really happened.
		var actual := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if actual.length() < vel.length():
			vel = vel.lerp(actual, 0.5)
	var mv := ctx.move_input
	mv.y = 0.0
	var mag := clampf(mv.length(), 0.0, 1.0)
	var accel := float(param("accel", 24.0))
	if mag > 0.15:
		var want := mv.normalized()
		var spd := vel.length()
		if spd > 1.0:
			# Carve: momentum turns at the turn rate (tighter when slower).
			var ang := Vector2(vel.x, vel.z).angle_to(Vector2(want.x, want.z))
			var rate := deg_to_rad(float(param("turn", 210.0))) * lerpf(1.6, 1.0, clampf(spd / _speed, 0.0, 1.0))
			var rot := clampf(ang, -rate * delta, rate * delta)
			vel = vel.rotated(Vector3.UP, -rot)
			if absf(ang) > deg_to_rad(120.0):
				vel = vel.move_toward(Vector3.ZERO, accel * 1.4 * delta)
		var top := _speed * lerpf(0.45, 1.0, mag)
		var dir := vel.normalized() if vel.length() > 0.5 else want
		vel = dir * move_toward(vel.length(), top, accel * delta)
	else:
		# Coast down to a hover.
		vel = vel.move_toward(Vector3.ZERO, 7.0 * delta)
	ctx.move_mode = BendingContext.Move.DRIVE
	ctx.move_velocity = vel
	if vel.length() > 0.6:
		ctx.face_dir = vel.normalized()
	ctx.gravity_scale = 1.0
	# Skimming over water: the ball rides on the surface.
	var p := body.global_position
	var wh := GroundSampler.water_height(p) if bool(param("water", true)) else -INF
	if wh > -INF and wh > ctx.ground_y(p, 0.6, 3.0) + 0.2 and p.y < wh + 0.4:
		ctx.gravity_scale = 0.0
		body.velocity.y = clampf((wh + 0.05 - p.y) * 10.0, -4.0, 6.0)
	# Wall run: riding fast into a steep wall runs up it.
	if body.is_on_wall() and vel.length() > 6.0 and wall_left > 0.0:
		var n := body.get_wall_normal()
		if n.y < 0.35 and vel.normalized().dot(-Vector3(n.x, 0.0, n.z).normalized()) > 0.45:
			phase = Phase.WALL
			_wall_n = Vector3(n.x, 0.0, n.z).normalized()
			_off_wall = 0.0
			AirFx.swirl(ctx.caster, body.global_position + Vector3.UP * 0.6, 0.6, 0.3, {"grow": 1.8, "spin": 20.0, "height": 0.1, "opacity": 0.6})


func _wall(delta: float) -> void:
	var body := ctx.body
	wall_left -= delta
	ctx.gravity_scale = 0.0
	body.velocity.y = float(param("wall_speed", 8.5))
	var along := vel - _wall_n * vel.dot(_wall_n)
	ctx.move_mode = BendingContext.Move.DRIVE
	ctx.move_velocity = -_wall_n * 3.0 + along * 0.5
	ctx.face_dir = -_wall_n
	if body.is_on_wall():
		_off_wall = 0.0
	else:
		_off_wall += delta
	if _off_wall > 0.05:
		# Over the top: pop forward onto the ledge and keep riding.
		phase = Phase.RIDE
		vel = -_wall_n * 7.0 + along * 0.5
		body.velocity.y = 3.5
		ctx.move_velocity = vel
	elif wall_left <= 0.0:
		# Out of momentum: peel off the wall.
		body.velocity = _wall_n * 5.0 + Vector3.UP * 3.0
		_dismount(&"wall")


func _jump_off() -> void:
	var v := vel
	if ctx.body:
		ctx.body.velocity = Vector3(v.x, float(param("jump_off", 8.5)), v.z)
	AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.3, 0.6, 0.35, {"grow": 2.2, "spin": 20.0, "height": 0.1, "opacity": 0.7})
	sound(&"jump", ctx.origin(), 0.0)
	# A short launch phase: the jump button's release must not cut the leap.
	_dismount(&"jump", 0.25)


## Ends the ride (the ball bursts). `recover` s of stepping-off before the ability ends.
func _dismount(reason: StringName, recover: float = 0.18) -> void:
	if phase == Phase.OFF:
		return
	phase = Phase.OFF
	end_reason = reason
	ctx.set_upkeep(0.0)
	ctx.gravity_scale = 1.0
	if reason != &"jump" and reason != &"wall":
		ctx.move_mode = BendingContext.Move.DRIVE
		ctx.move_velocity = vel * 0.4
		if ctx.body:
			ctx.body.velocity.y = maxf(ctx.body.velocity.y, 2.6)
	else:
		ctx.move_mode = BendingContext.Move.FREE
		ctx.move_speed_scale = 0.6
	if ball and is_instance_valid(ball):
		AirFx.swirl(ctx.caster, ball.global_position, 0.5, 0.3, {"grow": 2.4, "spin": 22.0, "height": 0.1, "opacity": 0.6})
	_cleanup()
	clip_end = time + recover
	if recover <= 0.0:
		finish()


func _place_ball(delta: float) -> void:
	var r := float(param("ball_radius", 0.5))
	var body := ctx.body
	var feet := body.global_position
	var center := feet + Vector3.UP * r
	if phase == Phase.WALL:
		center = feet + Vector3.UP * 0.5 - _wall_n * 0.15
	if ball and is_instance_valid(ball):
		ball.update(center, body.velocity if phase != Phase.WALL else Vector3.UP * 8.0, delta)
	if _impulse != 0:
		AirWindField.move(_impulse, feet)
	if _rig_set and ctx.rig and is_instance_valid(ctx.rig):
		var lift := float(param("ride_height", 0.82))
		ctx.rig.position.y = _rig_y + lift
		# Lean into the turns (roll), back against the wall.
		var yaw := atan2(-vel.x, -vel.z) if vel.length() > 0.5 else _last_yaw
		if delta > 0.0:
			_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, 1.0 - exp(-delta * 8.0))
		_last_yaw = yaw
		var roll := clampf(_yaw_rate * 0.12, -0.45, 0.45) * clampf(vel.length() / 8.0, 0.0, 1.0)
		var pitch := 1.1 if phase == Phase.WALL else -clampf(vel.length() / _speed, 0.0, 1.0) * 0.12
		ctx.rig.rotation = Vector3(pitch, ctx.rig.rotation.y, roll)


func _trail(delta: float) -> void:
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	var spd := vel.length()
	_trail_t = 0.14 if spd > 6.0 else 0.3
	var feet := ctx.origin()
	var g := ctx.ground_point(feet)
	if feet.y - g.y > 1.2:
		return
	var back := (-vel.normalized() if spd > 0.5 else Vector3.ZERO) + Vector3.UP
	var wh := GroundSampler.water_height(feet)
	if wh > g.y + 0.2:
		FxBurst.spawn(ctx.caster, &"spray", Vector3(feet.x, wh, feet.z), {"count": 0.6, "dir": back.normalized()})
		return
	var surf := ctx.surface_at(g)
	if spd > 3.0:
		AirFx.ground_puff(ctx.caster, g, surf, clampf(spd / _speed, 0.3, 0.8), back.normalized())


func _cleanup() -> void:
	if ball and is_instance_valid(ball):
		ball.finish(0.18)
	ball = null
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.2)
		_loop_id = 0
	if _impulse != 0:
		AirWindField.release(_impulse)
		_impulse = 0
	if _rig_set and ctx.rig and is_instance_valid(ctx.rig):
		ctx.rig.position.y = _rig_y
		ctx.rig.rotation = Vector3(0.0, ctx.rig.rotation.y, 0.0)
		ctx.rig.set_foot_ik(_rig_ik)
		if ctx.rig.current_action() == def.clip:
			ctx.rig.stop_action(0.15)
	_rig_set = false


func on_cancel(_reason: StringName) -> void:
	phase = Phase.OFF
	_cleanup()


func on_finish() -> void:
	_cleanup()
