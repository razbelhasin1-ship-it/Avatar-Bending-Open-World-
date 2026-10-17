extends DodgeAbility
## Earth Slide: a short slide riding the ground (3 m). No i-frames, but full
## poise armor (hits do not interrupt it). Dust sprays along the path, the feet
## plough a furrow that stays a while, and it ends with a small shockwave that
## staggers whoever is close. Nothing to ride on ice / wood / deep water: it is
## a plain slide there (no furrow, no shockwave).

var _dust_t := 0.0
var _shocked := false
var _start := Vector3.ZERO
var _info: Dictionary = {}


func on_dodge_start() -> void:
	EarthCommon.prepare()
	_start = ctx.ground_point(ctx.origin())
	_info = EarthEnv.feet(ctx)
	if not bool(_info["ok"]):
		return
	EarthFx.dust_trail(ctx.caster, _start, dir, _info["kind"], 1.5)
	FxDecal.spawn(ctx.caster, _start, &"crack", 0.6)


func on_dodge_tick(delta: float) -> void:
	if not bool(_info.get("ok", false)):
		return
	_dust_t -= delta
	if _dust_t <= 0.0 and time < duration:
		_dust_t = 0.07
		EarthFx.dust_trail(ctx.caster, ctx.ground_point(ctx.origin()), dir, _info["kind"], 0.8)
	if not _shocked and time >= duration * 0.85:
		_shocked = true
		var g := ctx.ground_point(ctx.origin())
		var r := float(param("shock_radius", 2.4))
		BendingHits.sphere(ctx, g + Vector3.UP * 0.4, r, EarthEnv.scaled_hit(hit_data(), _info), attack_id, def.id, {"push": &"radial"})
		EarthFx.quake(ctx.caster, g, r, _info["kind"])
		var flat := g - _start
		flat.y = 0.0
		if flat.length() > 0.8:
			EarthMarks.furrow(ctx.caster, _start, flat, flat.length() + 0.4, _info["kind"], 0.9)
		sound(&"stomp", g, -4.0)
		EarthEnv.shake(ctx, g, 0.15, 0.12)
