extends ChargeAbility
## Fire Blast / Blaze Charge. Tap: a fast long-range fireball (stagger).
## Hold: the fire is breathed into a ball cupped at the right hip (fire_blaze_hold)
## and builds in stages you can read: it grows and brightens, heat ripples run along
## the ground under the bender, embers are drawn in, the air shimmers, and at full
## charge it FLARES (flash + crack + burst: release now). Release: step in and drive it
## out with both palms (fire_blaze_release): a big blast that explodes on impact - a
## ring of flame races along the ground to the blast radius (2.4 m tap-charged ..
## 4.2 m full), knocking back everyone inside, scorching the ground, lighting grass.

var _ball: FireFx.FireBall = null
var _shimmer: HeatShimmer = null
var _ripple_t := 0.0
var _ready_cued := false


func begin() -> void:
	FireCommon.begin()
	super.begin()


func on_windup() -> void:
	_ball = FireFx.ball(ctx.caster, 0.14, true)
	_ball.global_position = ctx.hands_pos()
	_loop_id = Audio.start_bending_loop(ctx.element, &"charge_loop", ctx.caster, -6.0)
	BendingFeedback.sound(ctx.element, &"ignite", ctx.hands_pos(), -4.0)


func update(delta: float) -> void:
	super.update(delta)
	if charging and _ball and is_instance_valid(_ball):
		_ball.global_position = ctx.hands_pos() + ctx.forward() * 0.1


func on_charging(c: float, delta: float) -> void:
	if _ball and is_instance_valid(_ball):
		var pulse := 1.0 + 0.06 * sin(time * (8.0 + 10.0 * c))
		_ball.set_size((0.14 + c * 0.32) * pulse)
		_ball.set_heat(1.0 + c * 0.7)
		if _ball.light and is_instance_valid(_ball.light):
			_ball.light.set_energy(0.8 + c * 1.6)
	if _loop_id != 0:
		Audio.set_loop_pitch(_loop_id, 1.0 + c * 0.45)
	# Embers drawn into the ball, faster as it builds.
	if int(time * 14.0) % 2 == 0:
		FxBurst.spawn(ctx.caster, &"embers", ctx.hands_pos(), {"count": 0.2 + c * 0.45, "speed": 0.5 + c})
	# Heat ripples run out along the ground under the bender.
	_ripple_t -= delta
	if _ripple_t <= 0.0 and c > 0.2:
		_ripple_t = lerpf(0.55, 0.3, c)
		FxRing.spawn(ctx.caster, ctx.ground_point(ctx.origin()), 1.2 + c * 1.4, Color(1.0, 0.5, 0.18), 0.45, {"opacity": 0.25 + 0.3 * c, "width": 0.08, "fill": 0.0})
	if c > 0.35 and _shimmer == null and _ball != null:
		_shimmer = HeatShimmer.attach(ctx.caster, _ball, 0.9, 1.3, 0.8)
	if c >= 1.0 and not _ready_cued:
		_ready_cued = true
		var p := ctx.hands_pos()
		FireFx.burst(ctx.caster, p, 0.9, Vector3.UP)
		FxFlash.spawn(ctx.caster, p, FireCommon.HOT, 3.5, 0.2, 5.0)
		BendingFeedback.sound(ctx.element, &"ignite", p, 2.0)
		FireCommon.shake(ctx, 0.1, 0.1)


func release_attack(c: float, was_tap: bool) -> void:
	var from := ctx.hands_pos()
	var speed := float(param("speed", 36.0)) * (1.0 if was_tap else 0.85)
	var dir := ctx.aim_dir_from(from, speed, 0.7)
	from += dir * 0.35
	var size := 0.3 if was_tap else 0.42 + c * 0.32
	var h := hit_data()
	var radius := 0.0
	if not was_tap:
		h["damage"] = 20.0 + 18.0 * c
		h["reaction"] = HitInfo.Reaction.KNOCKBACK
		h["force"] = 9.0 + 5.0 * c
		h["lift"] = 2.0 + 2.0 * c
		h["poise"] = 35.0 + 25.0 * c
		radius = lerpf(float(param("explode_radius", 2.4)), float(param("explode_radius_full", 4.2)), c)
	var vis: FireFx.FireBall = _ball if _ball and is_instance_valid(_ball) else FireFx.ball(ctx.caster, size, true)
	_ball = null
	_stop_shimmer()
	vis.set_size(size)
	vis.set_heat(1.2 if was_tap else 1.4 + c * 0.5)
	var sctx := ctx
	var aid := attack_id
	var aname := def.id
	var full := c
	var splash_h := {"damage": 12.0 + 12.0 * c, "reaction": HitInfo.Reaction.KNOCKBACK, "force": 8.0 + 4.0 * c, "lift": 2.0, "poise": 30.0, "heavy": true, "status": {"burn": 4.0}}
	var explode := func(_p: BendingProjectile, pos: Vector3, n: Vector3, target: Node) -> void:
		if not sctx.is_valid():
			return
		if radius <= 0.0:
			# Tap fireball: scorches / lights what it hits.
			if target == null:
				FireEnv.heat(sctx, pos, 0.9, 0.6, {"mark": 0.6, "normal": n})
			return
		BlazeExplosion.explode(sctx, pos, radius, full)
		BendingHits.sphere(sctx, pos, radius, splash_h, aid, aname, {"push": &"radial"})
	BendingProjectile.launch(ctx, from, dir, speed, h, {"radius": size * 0.8, "range": float(param("range", 32.0)),
			"attack_id": attack_id, "ability_id": def.id, "visual": vis, "align": false, "homing": 25.0 if was_tap else 15.0,
			"impact_size": 1.0 + size, "on_impact": explode})
	FireFx.muzzle(ctx.caster, from, dir, 1.0 + c)
	sound(&"cast_heavy", from, 0.0 if was_tap else 2.0)
	BendingFeedback.impulse(dir, 0.12 + c * 0.2)
	FireCommon.shake(ctx, 0.1 + c * 0.2, 0.15)
	_stop_loop()


func _stop_loop() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.12)
		_loop_id = 0


func _stop_shimmer() -> void:
	if _shimmer != null and is_instance_valid(_shimmer):
		_shimmer.stop(0.2)
	_shimmer = null


func on_cleanup() -> void:
	_stop_loop()
	_stop_shimmer()
	if _ball and is_instance_valid(_ball):
		_ball.finish()
	_ball = null


## The charged blast's explosion: a ball of flame and smoke, a ring of fire racing to the
## blast radius along the ground (when close to it), light, shimmer, scorch, grass catches.
class BlazeExplosion:
	static func explode(ctx: BendingContext, pos: Vector3, radius: float, charge: float) -> void:
		var from: Node = ctx.caster
		var k := radius / 2.5
		var gy := ctx.ground_y(pos, 1.0, 4.0)
		var near_ground := pos.y - gy < 3.0
		FxBurst.spawn(from, &"flame", pos, {"size": 1.3 * k, "count": 1.6, "speed": 2.0 * k, "radius": 1.2 * k, "spread": 180.0})
		FxBurst.spawn(from, &"embers", pos, {"count": 1.8, "speed": 2.0 * k, "spread": 180.0})
		FxBurst.spawn(from, &"smoke", pos + Vector3.UP * 0.6, {"size": 1.4 * k, "count": 1.3, "radius": 0.6 * k})
		FxBurst.spawn(from, &"sparks", pos, {"count": 1.2, "speed": 1.3 * k, "spread": 180.0})
		FxFlash.spawn(from, pos + Vector3.UP * 0.5, FireCommon.HOT, 5.0 * k, 0.4, radius * 3.0)
		if near_ground:
			var g := Vector3(pos.x, gy, pos.z)
			FireRingWave.visual(ctx, g, radius, 0.2, {"height": 0.7 + 0.5 * charge, "r0": 0.4, "hold": 0.12, "lean": 0.5})
			HeatShimmer.spawn(from, g, radius * 1.3, 2.6, 0.8, 1.0)
			FireEnv.heat(ctx, g + Vector3.UP * 0.2, radius * 0.75, 1.0 + charge, {"mark": radius * 0.6})
		else:
			FireEnv.heat(ctx, pos, radius * 0.6, 1.0, {"ground": false})
		BendingFeedback.sound(ElementDefs.Element.FIRE, &"explosion", pos, 2.0 + charge * 2.0)
		FireCommon.shake(ctx, 0.3 + 0.2 * charge, 0.3)
