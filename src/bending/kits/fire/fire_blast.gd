extends ChargeAbility
## Fire Blast / Blaze Charge. Tap: a fast long-range fireball (stagger).
## Hold: flame gathers between the fists (growing fireball, embers, light);
## release fires a big blast that explodes on impact (area knockback).

var _ball: FireFx.FireBall = null


func on_windup() -> void:
	_ball = FireFx.ball(ctx.caster, 0.14, true)
	_ball.global_position = ctx.hands_pos()
	_loop_id = Audio.start_bending_loop(ctx.element, &"charge_loop", ctx.caster, -6.0)
	BendingFeedback.sound(ctx.element, &"ignite", ctx.hands_pos(), -4.0)


func update(delta: float) -> void:
	super.update(delta)
	if charging and _ball and is_instance_valid(_ball):
		_ball.global_position = ctx.hands_pos() + ctx.forward() * 0.12


func on_charging(c: float, _delta: float) -> void:
	if _ball and is_instance_valid(_ball):
		_ball.set_size(0.14 + c * 0.3)
		_ball.set_heat(1.0 + c * 0.6)
		if _ball.light and is_instance_valid(_ball.light):
			_ball.light.set_energy(1.5 + c * 3.0)
	if _loop_id != 0:
		Audio.set_loop_pitch(_loop_id, 1.0 + c * 0.4)
	if int(time * 12.0) % 3 == 0:
		FxBurst.spawn(ctx.caster, &"embers", ctx.hands_pos(), {"count": 0.25 + c * 0.4, "speed": 0.6})


func release_attack(c: float, was_tap: bool) -> void:
	var from := ctx.hands_pos()
	var speed := float(param("speed", 36.0)) * (1.0 if was_tap else 0.85)
	var dir := ctx.aim_dir_from(from, speed, 0.7)
	from += dir * 0.35
	var size := 0.3 if was_tap else 0.42 + c * 0.3
	var h := hit_data()
	var radius := 0.0
	if not was_tap:
		h["damage"] = 20.0 + 18.0 * c
		h["reaction"] = HitInfo.Reaction.KNOCKBACK
		h["force"] = 9.0 + 5.0 * c
		h["lift"] = 2.0 + 2.0 * c
		h["poise"] = 35.0 + 25.0 * c
		radius = 2.4 + 1.6 * c
	var vis: FireFx.FireBall = _ball if _ball and is_instance_valid(_ball) else FireFx.ball(ctx.caster, size, true)
	_ball = null
	vis.set_size(size)
	vis.set_heat(1.2 if was_tap else 1.4 + c * 0.4)
	var sctx := ctx
	var aid := attack_id
	var aname := def.id
	var splash_h := {"damage": 12.0 + 12.0 * c, "reaction": HitInfo.Reaction.KNOCKBACK, "force": 8.0 + 4.0 * c, "lift": 2.0, "poise": 30.0, "heavy": true, "status": {"burn": 4.0}}
	var explode := func(_p: BendingProjectile, pos: Vector3, _n: Vector3, _t: Node) -> void:
		if radius <= 0.0:
			return
		var gy := sctx.ground_y(pos, 1.0, 4.0) if sctx.is_valid() else pos.y - 1.0
		FireFx.explosion(_p, pos, radius, gy if pos.y - gy < 3.0 else INF)
		BendingFeedback.sound(ElementDefs.Element.FIRE, &"explosion", pos, 2.0)
		if sctx.is_valid():
			BendingHits.sphere(sctx, pos, radius, splash_h, aid, aname, {"push": &"radial"})
			if sctx.is_player():
				BendingFeedback.shake(0.35, 0.3)
	BendingProjectile.launch(ctx, from, dir, speed, h, {"radius": size * 0.8, "range": float(param("range", 32.0)),
			"attack_id": attack_id, "ability_id": def.id, "visual": vis, "align": false, "homing": 25.0 if was_tap else 15.0,
			"impact_size": 1.0 + size, "on_impact": explode})
	FireFx.muzzle(ctx.caster, from, dir, 1.0 + c)
	sound(&"cast_heavy", from, 0.0 if was_tap else 2.0)
	BendingFeedback.impulse(dir, 0.12 + c * 0.2)
	if ctx.is_player():
		BendingFeedback.shake(0.1 + c * 0.2, 0.15)
	_stop_loop()


func _stop_loop() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.12)
		_loop_id = 0


func on_cleanup() -> void:
	_stop_loop()
	if _ball and is_instance_valid(_ball):
		_ball.finish()
	_ball = null
