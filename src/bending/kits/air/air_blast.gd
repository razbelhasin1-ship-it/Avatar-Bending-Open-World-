extends ChargeAbility
## Air Blast. Tap: a fast gust that staggers and pushes 8 m/s. Hold: wind
## spirals into a ball between the palms; release hurls a wide blast that
## knocks enemies back (radius, range and force grow with the charge).
## In the air: charging hangs the bender (air-assisted), the release recoils them
## back and up. High in the air (>= dive_height): GALE DROP - the bender dives at
## dive_speed and slams a ring of wind into the ground on landing (knockdown
## within dive_radius, gameplay on the landing clip's &"impact").

var _ball: AirFx.AirSwirl = null
var _dive := false
var _landed := false
var _slammed := false
var _air := false


func can_use() -> StringName:
	AirCommon.prepare()
	return &""


func begin() -> void:
	_air = AirCommon.airborne(ctx)
	if _air and AirCommon.height(ctx) >= float(param("dive_height", 2.4)):
		_begin_dive()
		return
	super.begin()


# --- Gale Drop ---------------------------------------------------------------------------------

func _begin_dive() -> void:
	_dive = true
	charging = false
	released = true
	ctx.move_mode = BendingContext.Move.DRIVE
	ctx.move_velocity = _dive_steer()
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1200.0
	ctx.gravity_scale = 0.0
	ctx.poise_armor = 35.0
	play_clip(&"air_dive", {"blend_in": 0.06})
	clip_end = INF
	max_time = float(param("dive_max", 1.6)) + 1.5
	if ctx.body:
		ctx.body.velocity.y = -float(param("dive_speed", 24.0)) * 0.5
	AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 1.0, 0.7, 0.3, {"grow": 1.6, "spin": 20.0, "height": 0.3, "opacity": 0.6})
	sound(&"dash", ctx.origin(), 0.0)


## Horizontal drift of the dive: homes onto a locked / aimed target within
## dive_reach m (lands on it), else a slight drift along the aim.
func _dive_steer() -> Vector3:
	var flat := ctx.aim_flat() * 4.0
	var t := ctx.aim_target()
	if t == null or not is_instance_valid(t):
		return flat
	var to := t.global_position - ctx.origin()
	var h := maxf(-to.y, 0.5)
	to.y = 0.0
	if to.length() > float(param("dive_reach", 8.0)):
		return flat
	# Arrive with the fall: the remaining fall time at dive speed.
	var eta := maxf(h / float(param("dive_speed", 24.0)), 0.12)
	return (to / eta).limit_length(float(param("dive_steer", 16.0)))


func _dive_tick(delta: float) -> void:
	if _landed:
		if time >= clip_end:
			finish()
		return
	var body := ctx.body
	if body == null:
		finish()
		return
	body.velocity.y = move_toward(body.velocity.y, -float(param("dive_speed", 24.0)), 90.0 * delta)
	ctx.move_velocity = _dive_steer()
	var trail := Transform3D(Basis.looking_at(Vector3.UP, Vector3.FORWARD), ctx.origin() + Vector3.UP * 1.2)
	if int(time * 30.0) % 3 == 0:
		AirFx.gust(ctx.caster, trail, 2.4, 0.45, 0.2, {"opacity": 0.55, "tail": 0.9})
	var wh := GroundSampler.water_height(ctx.origin())
	var on_water := wh > -INF and ctx.origin().y <= wh + 0.2
	if body.is_on_floor() or on_water or time > float(param("dive_max", 1.6)):
		_landed = true
		ctx.move_mode = BendingContext.Move.BRAKE
		ctx.brake_rate = 60.0
		ctx.gravity_scale = 1.0
		ctx.face_dir = Vector3.ZERO
		play_clip(&"air_slam_land", {"blend_in": 0.03})
		if time_to_event(&"impact") == INF:
			_slam()


func _slam() -> void:
	if _slammed:
		return
	_slammed = true
	var o := ctx.origin()
	var g := ctx.ground_point(o)
	var r := float(param("dive_radius", 3.8))
	var h := hit_data(param("dive_hit", {}) as Dictionary)
	BendingHits.sphere(ctx, g + Vector3.UP * 0.5, r, h, attack_id, def.id, {"push": &"radial"})
	AirWaveFx.spawn(ctx.caster, g, r, 0.24, {"height": 1.2})
	AirEnv.blow(ctx, g, r, 1.3, {"mode": &"radial", "by": ctx.caster})
	sound(&"push", o, 2.0)
	sound(&"stomp", o, 0.0)
	BendingFeedback.impulse(Vector3.DOWN, 0.35)
	if ctx.is_player():
		BendingFeedback.shake(0.4, 0.25)


# --- charge / tap ------------------------------------------------------------------------------

func on_windup() -> void:
	_ball = AirFx.swirl(ctx.caster, ctx.hands_pos(), 0.25, 1.0, {"loop": true, "spin": 14.0, "height": 0.05, "tilt": 0.6, "opacity": 0.75})
	_loop_id = Audio.start_bending_loop(ctx.element, &"charge_loop", ctx.caster, -8.0)


func on_charging(c: float, _delta: float) -> void:
	if _ball and is_instance_valid(_ball):
		_ball.global_position = ctx.hands_pos() + ctx.forward() * 0.1
		_ball.radius = 0.25 + c * 0.35
	if _loop_id != 0:
		Audio.set_loop_pitch(_loop_id, 1.0 + c * 0.35)
	if c > 0.99 and int(time * 10.0) % 4 == 0:
		FxBurst.spawn(ctx.caster, &"sparkle", ctx.hands_pos(), {"count": 0.3, "color": Color(0.9, 0.97, 1.0)})


func update(delta: float) -> void:
	if _dive:
		_dive_tick(delta)
		return
	if _air and AirCommon.airborne(ctx):
		AirCommon.hang(ctx, delta, 0.2 if charging else -1.0)
	super.update(delta)
	if charging and _ball and is_instance_valid(_ball):
		_ball.global_position = ctx.hands_pos() + ctx.forward() * 0.1


func on_event(event: StringName) -> void:
	if _dive:
		if event == &"impact":
			_slam()
		return
	super.on_event(event)


func release_attack(c: float, was_tap: bool) -> void:
	_stop_charge_fx()
	var from := ctx.hands_pos()
	var cfg := {"radius": 0.7, "grow": 0.8, "speed": 40.0, "range": 14.0, "env": 0.7}
	var h := hit_data()
	if not was_tap:
		cfg = {"radius": 0.9 + c * 0.5, "grow": 1.2 + c * 1.4, "speed": 34.0, "range": 15.0 + c * 4.0, "opacity": 1.0, "env": 0.9 + c * 0.6}
		h["damage"] = 18.0 + 16.0 * c
		h["reaction"] = HitInfo.Reaction.KNOCKBACK
		h["force"] = 10.0 + 6.0 * c
		h["lift"] = 1.5 + 2.0 * c
		h["poise"] = 30.0 + 25.0 * c
	var dir := AirCommon.aim_dir(ctx, from, float(cfg["speed"]))
	if _air:
		cfg["min_y"] = -0.6
		dir = ctx.aim_dir_from(from, float(cfg["speed"]), 0.5)
	from += dir * 0.3
	AirCommon.gust(self, from, dir, cfg, h)
	sound(&"cast_heavy", from, 0.0 if was_tap else 2.0)
	if not _air:
		AirEnv.puff(ctx.caster, ctx.ground_point(ctx.origin() + dir * 0.6), ctx.surface_at(ctx.origin()), 0.6 + c, (dir + Vector3.UP * 0.6).normalized())
	elif ctx.body:
		# Recoil: the blast throws the bender back and up (aerial spacing).
		var back := -Vector3(dir.x, 0.0, dir.z).normalized()
		ctx.body.velocity = Vector3(back.x * (3.0 + 3.0 * c), 2.5 + 2.0 * c, back.z * (3.0 + 3.0 * c))
	BendingFeedback.impulse(dir, 0.15 + c * 0.2)
	if ctx.is_player():
		BendingFeedback.shake(0.12 + c * 0.25, 0.15)


func _stop_charge_fx() -> void:
	if _ball and is_instance_valid(_ball):
		_ball.stop(0.12)
	_ball = null
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.12)
		_loop_id = 0


func on_cleanup() -> void:
	_stop_charge_fx()
