extends ChargeAbility
## Air Blast. Tap: a fast gust that staggers and pushes 8 m/s. Hold: wind
## spirals into a ball between the palms; release hurls a wide blast that
## knocks enemies back (radius, range and force grow with the charge).

var _ball: AirFx.AirSwirl = null


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


func on_charging_tick(_d: float) -> void:
	pass


func update(delta: float) -> void:
	super.update(delta)
	if charging and _ball and is_instance_valid(_ball):
		_ball.global_position = ctx.hands_pos() + ctx.forward() * 0.1


func release_attack(c: float, was_tap: bool) -> void:
	_stop_charge_fx()
	var from := ctx.hands_pos()
	var cfg := {"radius": 0.7, "grow": 0.8, "speed": 38.0, "range": 14.0}
	var h := hit_data()
	if not was_tap:
		cfg = {"radius": 0.9 + c * 0.5, "grow": 1.2 + c * 1.4, "speed": 34.0, "range": 15.0 + c * 4.0, "opacity": 1.0}
		h["damage"] = 18.0 + 16.0 * c
		h["reaction"] = HitInfo.Reaction.KNOCKBACK
		h["force"] = 10.0 + 6.0 * c
		h["lift"] = 1.5 + 2.0 * c
		h["poise"] = 30.0 + 25.0 * c
	var dir := AirCommon.aim_dir(ctx, from, float(cfg["speed"]))
	from += dir * 0.3
	AirCommon.gust(self, from, dir, cfg, h)
	sound(&"cast_heavy", from, 0.0 if was_tap else 2.0)
	AirFx.ground_puff(ctx.caster, ctx.ground_point(ctx.origin() + dir * 0.6), ctx.surface_at(ctx.origin()), 0.6 + c, (dir + Vector3.UP * 0.6).normalized())
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
