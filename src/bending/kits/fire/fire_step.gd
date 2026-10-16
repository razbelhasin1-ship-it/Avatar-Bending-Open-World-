extends DodgeAbility
## Fire Step: an explosive burst step (4.5 m, 0.2 s i-frames) jet-propelled
## from the feet, leaving a short flame trail and scorch marks. Strikes may
## cancel it after 0.14 s (aggressive re-engage).

var _trail_t := 0.0


func on_dodge_start() -> void:
	var g := ctx.ground_point(ctx.origin())
	FireFx.burst(ctx.caster, g + Vector3.UP * 0.15, 1.0, (-dir + Vector3.UP * 0.5).normalized())
	FxDecal.spawn(ctx.caster, g, &"scorch", 0.7)
	FxFlash.spawn(ctx.caster, g + Vector3.UP * 0.4, Color(1.0, 0.55, 0.2), 2.0, 0.2, 4.0)
	BendingFeedback.sound(ctx.element, &"ignite", g)


func on_dodge_tick(delta: float) -> void:
	_trail_t -= delta
	if _trail_t <= 0.0 and time < duration:
		_trail_t = 0.045
		for s: StringName in [&"foot_l", &"foot_r"]:
			FxBurst.spawn(ctx.caster, &"flame", ctx.socket_pos(s), {"size": 0.4, "count": 0.3, "dir": -dir, "speed": 0.8})
		FxDecal.spawn(ctx.caster, ctx.ground_point(ctx.origin()), &"scorch", 0.45)
