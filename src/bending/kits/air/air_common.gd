class_name AirCommon
extends RefCounted
## Shared air pieces: the travelling gust (a piercing projectile volume with a
## helix current whose head rides exactly on the hit volume) and ground puffs
## along its path.


## Launches a gust from `from` along `dir`. cfg: radius, grow (radius gained
## over the range), speed, range, low (stay near the ground), opacity.
static func gust(ab: BendingAbility, from: Vector3, dir: Vector3, cfg: Dictionary, h: Dictionary) -> BendingProjectile:
	var ctx := ab.ctx
	var speed := float(cfg.get("speed", 30.0))
	var range_m := float(cfg.get("range", 7.0))
	var radius := float(cfg.get("radius", 0.6))
	var grow := float(cfg.get("grow", 1.5))
	var d := dir
	if bool(cfg.get("low", false)):
		d.y = minf(d.y, 0.0)
	d.y = clampf(d.y, -0.35, 0.35)
	d = d.normalized()
	var travel := range_m / speed
	var xf := Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT), from)
	var g := AirFx.gust(ctx.caster, xf, range_m, radius + grow * 0.6, travel * 1.3, {"opacity": float(cfg.get("opacity", 0.9)), "tail": 0.55})
	var puffer := GustPuffer.new()
	puffer.ctx = ctx
	puffer.dir = d
	var p := BendingProjectile.launch(ctx, from, d, speed, h, {
		"radius": radius, "radius_growth": grow / maxf(travel, 0.05), "max_radius": radius + grow, "range": range_m,
		"pierce": true, "attack_id": ab.attack_id, "ability_id": ab.def.id, "impact_size": 0.6 + grow * 0.3,
		"deflectable": false, "visual": null, "on_step": puffer.step,
	})
	p.set_meta(&"gust_fx", g)
	# Callables do not keep RefCounted objects alive; the meta does.
	p.set_meta(&"puffer", puffer)
	return p


## Gust direction from a socket toward the aim (slight lead), kept fairly level.
static func aim_dir(ctx: BendingContext, from: Vector3, speed: float) -> Vector3:
	var d := ctx.aim_dir_from(from, speed, 0.5)
	d.y = clampf(d.y, -0.3, 0.3)
	return d.normalized()


## Kicks up the ground under a passing gust (max 4 puffs).
class GustPuffer extends RefCounted:
	var ctx: BendingContext
	var dir := Vector3.FORWARD
	var next_puff := 1.2
	var puffs := 0

	func step(proj: BendingProjectile, _dt: float) -> void:
		if proj.traveled < next_puff or puffs >= 4:
			return
		next_puff += 1.6
		puffs += 1
		var gp := proj.global_position
		var gy := ctx.ground_y(gp, 1.0, 2.5) if ctx != null and ctx.is_valid() else gp.y - 1.0
		if gp.y - gy < 1.8:
			AirFx.ground_puff(proj, Vector3(gp.x, gy, gp.z), GroundSampler.surface(gp), 0.5, (dir + Vector3.UP).normalized())
