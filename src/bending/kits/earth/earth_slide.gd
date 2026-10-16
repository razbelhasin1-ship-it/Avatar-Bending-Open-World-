extends DodgeAbility
## Earth Slide: a short slide riding the ground (3 m). No i-frames, but full
## poise armor (hits do not interrupt it). Dust sprays along the path and it
## ends with a small shockwave that staggers whoever is close.

var _dust_t := 0.0
var _shocked := false


func on_dodge_start() -> void:
	EarthFx.dust_trail(ctx.caster, ctx.ground_point(ctx.origin()), dir, ctx.surface_at(ctx.origin()), 1.5)
	FxDecal.spawn(ctx.caster, ctx.ground_point(ctx.origin()), &"crack", 0.6)


func on_dodge_tick(delta: float) -> void:
	_dust_t -= delta
	if _dust_t <= 0.0 and time < duration:
		_dust_t = 0.07
		EarthFx.dust_trail(ctx.caster, ctx.ground_point(ctx.origin()), dir, ctx.surface_at(ctx.origin()), 0.8)
	if not _shocked and time >= duration * 0.85:
		_shocked = true
		var g := ctx.ground_point(ctx.origin())
		var r := float(param("shock_radius", 2.4))
		BendingHits.sphere(ctx, g + Vector3.UP * 0.4, r, hit_data(), attack_id, def.id, {"push": &"radial"})
		EarthFx.quake(ctx.caster, g, r, ctx.surface_at(g))
		sound(&"stomp", g, -4.0)
		if ctx.is_player():
			BendingFeedback.shake(0.15, 0.12)
