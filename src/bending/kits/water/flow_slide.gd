extends DodgeAbility
## Flow Slide: a smooth slide roll over a sheet of water (4 m, 0.26 s
## i-frames), spraying water and leaving wet marks. A perfect dodge (an attack
## that would have hit inside the first 0.2 s) slows time briefly.

var _spray_t := 0.0


func on_dodge_start() -> void:
	var g := ctx.ground_point(ctx.origin())
	IceFx.splash(ctx.caster, g + Vector3.UP * 0.1, 0.6, (-dir + Vector3.UP).normalized(), g.y)


func on_dodge_tick(delta: float) -> void:
	_spray_t -= delta
	if _spray_t <= 0.0 and time < duration:
		_spray_t = 0.06
		var g := ctx.ground_point(ctx.origin())
		FxBurst.spawn(ctx.caster, &"spray", g + Vector3.UP * 0.1, {"count": 0.4, "dir": (-dir + Vector3.UP).normalized(), "size": 0.7})
		FxDecal.spawn(ctx.caster, g, &"wet", 0.55)


func on_perfect_dodge(_hit: HitInfo) -> void:
	TimeDilation.request(float(param("slowmo_scale", 0.35)), float(param("slowmo_time", 0.55)))
	FxBurst.spawn(ctx.caster, &"sparkle", ctx.origin() + Vector3.UP, {"count": 1.5, "color": Color(0.7, 0.9, 1.0)})
	ctx.add_focus(5.0)
