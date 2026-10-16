extends ChargeAbility
## Air Push (starter technique): gather the air into a ball between the palms
## (hold to charge, 0.8 s), then stomp into a horse stance and throw both palms out:
## a ring of wind races outward along the ground. Every target is hit once, when the
## visible front reaches it: within `close` m it is knocked down, beyond it is blown
## back. Enemy projectiles the front passes are flung outward (they turn on their
## owners). Grass flattens, dust / snow / spray rings, props fly, fires go out.
## Works in the air too (a sphere of wind, the bender hangs for a moment).
## Non-player casters push at once (tap).

var _ball: AirFx.AirSwirl = null
var _ring_t := 0.0
var _front := -1.0
var _front_time := 0.2
var _radius := 4.4
var _close := 2.0
var _center := Vector3.ZERO
var _power := 0.0
var _deflected := {}
var _airborne := false


func can_use() -> StringName:
	AirCommon.prepare()
	return &""


func begin() -> void:
	super.begin()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 26.0
	ctx.poise_armor = def.poise_armor
	_airborne = AirCommon.airborne(ctx)
	if not ctx.is_player():
		input_held = false


func on_windup() -> void:
	_ball = AirFx.swirl(ctx.caster, ctx.hands_pos(), 0.2, 1.0, {"loop": true, "spin": 16.0, "height": 0.06, "tilt": 0.7, "opacity": 0.8})
	_loop_id = Audio.start_bending_loop(ctx.element, &"charge_loop", ctx.caster, -9.0)


func on_charging(c: float, delta: float) -> void:
	if _ball and is_instance_valid(_ball):
		_ball.global_position = ctx.hands_pos() + ctx.forward() * 0.05
		_ball.radius = 0.2 + c * 0.3
	if _loop_id != 0:
		Audio.set_loop_pitch(_loop_id, 0.9 + c * 0.4)
	# The reach of the push grows on the ground (readable telegraph for both sides).
	_ring_t -= delta
	if _ring_t <= 0.0 and not AirCommon.airborne(ctx):
		_ring_t = 0.3
		var r := lerpf(float(param("radius", 4.4)), float(param("radius_full", 6.8)), c)
		FxRing.spawn(ctx.caster, ctx.ground_point(ctx.origin()), r, Color(0.88, 0.95, 1.0), 0.32, {"opacity": 0.22 + 0.25 * c, "width": 0.06, "fill": 0.04})
	if c > 0.99 and int(time * 10.0) % 4 == 0:
		FxBurst.spawn(ctx.caster, &"sparkle", ctx.hands_pos(), {"count": 0.3, "color": Color(0.9, 0.97, 1.0)})


func update(delta: float) -> void:
	if AirCommon.airborne(ctx):
		AirCommon.hang(ctx, delta, 0.4)
	if charging:
		if _ball and is_instance_valid(_ball):
			_ball.global_position = ctx.hands_pos() + ctx.forward() * 0.05
		super.update(delta)
		return
	if _front >= 0.0:
		_tick_front(delta)
	if time >= clip_end and _front < 0.0:
		finish()


func on_clip_event(event: StringName) -> void:
	if event == &"gather" and _ball and is_instance_valid(_ball):
		# The ball is pulled in to the chest just before the release.
		_ball.radius *= 0.6


func release_attack(c: float, _was_tap: bool) -> void:
	_stop_charge_fx()
	_power = c
	_radius = lerpf(float(param("radius", 4.4)), float(param("radius_full", 6.8)), c)
	_close = lerpf(float(param("close", 2.0)), float(param("close_full", 3.0)), c)
	_front_time = lerpf(float(param("front_time", 0.2)), float(param("front_time_full", 0.28)), c)
	var o := ctx.origin()
	var high := AirCommon.height(ctx) > 1.2
	_center = o + Vector3.UP * (0.9 if high else 0.25)
	var g := ctx.ground_point(o) if not high else _center
	AirWaveFx.spawn(ctx.caster, g, _radius, _front_time + 0.12, {"height": 1.0 + c * 0.7, "dome": true})
	AirFx.swirl(ctx.caster, o + Vector3.UP * 0.9, 0.7, 0.35, {"grow": 2.6, "spin": 18.0, "height": 0.5, "opacity": 0.75})
	AirEnv.blow(ctx, g, _radius, 1.0 + 0.6 * c, {"mode": &"radial", "hold": _front_time, "by": ctx.caster})
	FxFlash.spawn(ctx.caster, o + Vector3.UP * 1.0, Color(0.85, 0.94, 1.0), 1.2 + c, 0.18, _radius)
	sound(&"push", o + Vector3.UP, 1.0 + 2.0 * c)
	BendingFeedback.impulse(Vector3.DOWN, 0.18 + 0.15 * c)
	if ctx.is_player():
		BendingFeedback.shake(0.22 + 0.2 * c, 0.2)
	if high:
		# The recoil of a push in the air lifts the bender a little.
		var v := ctx.body.velocity if ctx.body else Vector3.ZERO
		if ctx.body:
			ctx.body.velocity = Vector3(v.x * 0.5, maxf(v.y, 2.5), v.z * 0.5)
	_front = 0.0
	_deflected.clear()
	AirEnv.practiced(ctx, def.id)
	_tick_front(0.0)


func _tick_front(delta: float) -> void:
	_front += delta
	var p := clampf(_front / maxf(_front_time, 0.05), 0.0, 1.0)
	var r := AirWaveFx.front(p, _radius)
	var far_h := hit_data()
	var close_h := hit_data(param("close_hit", {}) as Dictionary)
	var scale := 1.0 + 0.45 * _power
	for h: Dictionary in [far_h, close_h]:
		h["damage"] = float(h.get("damage", 8.0)) * scale
		h["force"] = float(h.get("force", 10.0)) * (1.0 + 0.25 * _power)
	for t in BendingHits.targets_in_sphere(ctx, _center, r + 0.35):
		if BendingHits.already_hit(attack_id, t) or not (t is Node3D):
			continue
		var tp := BendingContext.target_point(t as Node3D)
		var flat := tp - _center
		flat.y = 0.0
		if not BendingHits.line_of_sight(ctx, _center + Vector3.UP * 0.3, tp, t):
			continue
		var dir := flat.normalized() if flat.length() > 0.05 else ctx.forward()
		var hit := ctx.make_hit(close_h if flat.length() <= _close else far_h, dir, attack_id, def.id)
		hit.origin = _center
		hit.position = tp - dir * 0.3
		BendingHits.deliver(ctx, t, hit)
	# Projectiles caught by the front are flung outward (they now belong to the bender).
	for proj: BendingProjectile in BendingProjectile.live.duplicate():
		if not is_instance_valid(proj) or not proj.alive or proj.team == ctx.team or _deflected.has(proj.get_instance_id()):
			continue
		var d := proj.global_position - _center
		if d.length() > r + 0.4 or absf(d.y) > 3.0:
			continue
		_deflected[proj.get_instance_id()] = true
		var out := Vector3(d.x, 0.15, d.z).normalized() if Vector2(d.x, d.z).length() > 0.1 else -proj.velocity.normalized()
		if proj.deflectable:
			proj.redirect(out, ctx.team, ctx.caster, 0.9)
		else:
			proj.destroy(true)
	if p >= 1.0:
		_front = -1.0


func _stop_charge_fx() -> void:
	if _ball and is_instance_valid(_ball):
		_ball.stop(0.1)
	_ball = null
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.1)
		_loop_id = 0


func on_cleanup() -> void:
	_stop_charge_fx()
