extends DodgeAbility
## Air Dash: a long wind-assisted dash (7 m, 0.32 s i-frames), usable in the
## air. Leaves a wind trail and kicks up the ground at the start.

var _trail_timer := 0.0


func on_dodge_start() -> void:
	var back := -dir
	var xf := Transform3D(Basis.looking_at(back, Vector3.UP), ctx.origin() + Vector3.UP * 0.9 + dir * 0.4)
	AirFx.gust(ctx.caster, xf, 3.5, 0.55, 0.3, {"opacity": 0.7, "tail": 0.8})
	if not in_air:
		AirFx.ground_puff(ctx.caster, ctx.ground_point(ctx.origin()), ctx.surface_at(ctx.origin()), 0.7, (back + Vector3.UP).normalized())
	else:
		AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.6, 0.6, 0.3, {"grow": 1.8, "spin": 16.0, "height": 0.1, "opacity": 0.6})


func on_dodge_tick(delta: float) -> void:
	_trail_timer -= delta
	if _trail_timer <= 0.0 and time < duration:
		_trail_timer = 0.09
		var xf := Transform3D(Basis.looking_at(-dir, Vector3.UP), ctx.origin() + Vector3.UP * 1.0)
		AirFx.gust(ctx.caster, xf, 1.8, 0.35, 0.22, {"opacity": 0.45, "tail": 0.9})
