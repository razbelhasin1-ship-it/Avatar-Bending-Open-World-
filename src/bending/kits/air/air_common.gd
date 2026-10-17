class_name AirCommon
extends RefCounted
## Shared air pieces: the travelling gust (a piercing projectile volume with a
## helix current whose head rides exactly on the hit volume) and ground puffs
## along its path, aerial helpers (airborne, height, hang time), the caster's
## input (player only) and kit preparation.

## Seconds of air-assisted hang time per airtime (aerial strikes / charges).
const HANG_BUDGET := 1.6


## Clips + world hooks every Air ability relies on (cheap, idempotent).
static func prepare() -> void:
	AirClips.ensure()
	AirTraversal.watch()


## Launches a gust from `from` along `dir`. cfg: radius, grow (radius gained
## over the range), speed, range, low (stay near the ground), opacity, env (world
## reaction strength along the path, 0 = none), core (radius that meets terrain / walls).
static func gust(ab: BendingAbility, from: Vector3, dir: Vector3, cfg: Dictionary, h: Dictionary) -> BendingProjectile:
	var ctx := ab.ctx
	var speed := float(cfg.get("speed", 30.0))
	var range_m := float(cfg.get("range", 7.0))
	var radius := float(cfg.get("radius", 0.6))
	var grow := float(cfg.get("grow", 1.5))
	var d := dir
	if bool(cfg.get("low", false)):
		d.y = minf(d.y, 0.0)
	d.y = clampf(d.y, float(cfg.get("min_y", -0.35)), 0.35)
	d = d.normalized()
	var travel := range_m / speed
	var xf := Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT), from)
	# The current lingers a little after the hit volume passed (readability).
	var g := AirFx.gust(ctx.caster, xf, range_m, radius + grow * 0.6, travel * 1.3 + 0.18, {"opacity": float(cfg.get("opacity", 0.9)), "tail": 0.55})
	var puffer := GustPuffer.new()
	puffer.ctx = ctx
	puffer.dir = d
	puffer.power = float(cfg.get("env", 0.5))
	puffer.radius = radius + grow * 0.5
	if puffer.power > 0.0 and ctx.is_valid():
		puffer.impulse = AirWindField.add(ctx.caster, from, puffer.radius + 1.2, 10.0 + 14.0 * puffer.power, AirWindField.DIRECTIONAL, d, INF)
	# Bodies meet the whole (growing) gust; the ground and walls only its core, so a low or
	# wide gust skims the floor instead of dying on it (cfg "core", default 0.25 m).
	var p := BendingProjectile.launch(ctx, from, d, speed, h, {
		"radius": radius, "radius_growth": grow / maxf(travel, 0.05), "max_radius": radius + grow, "range": range_m,
		"world_radius": minf(float(cfg.get("core", 0.25)), radius),
		"pierce": true, "attack_id": ab.attack_id, "ability_id": ab.def.id, "impact_size": 0.6 + grow * 0.3,
		"deflectable": false, "visual": null, "on_step": puffer.step, "on_finish": puffer.done,
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


## In the air: not on the floor AND more than 0.3 m above the ground below (a body
## that never moved yet - spawned casters, tests - reads as grounded).
static func airborne(ctx: BendingContext) -> bool:
	if ctx.body == null or ctx.body.is_on_floor():
		return false
	var o := ctx.origin()
	return o.y - ctx.ground_y(o, 0.3, 40.0) > 0.3


## Height of the caster's feet above the ground below (0 on the ground).
static func height(ctx: BendingContext) -> float:
	if ctx.body == null or ctx.body.is_on_floor():
		return 0.0
	var o := ctx.origin()
	return maxf(0.0, o.y - ctx.ground_y(o, 0.3, 40.0))


## The player's input component (null for AI / rig-less casters).
static func input(ctx: BendingContext) -> PlayerInput:
	if ctx == null or not ctx.is_valid() or not ("input" in ctx.caster):
		return null
	return ctx.caster.get("input") as PlayerInput


## Hang time left this airtime (refilled on the ground).
static func hang_left(ctx: BendingContext) -> float:
	if ctx.body == null:
		return 0.0
	if ctx.body.is_on_floor() or not ctx.caster.has_meta(&"air_hang"):
		ctx.caster.set_meta(&"air_hang", HANG_BUDGET)
	return float(ctx.caster.get_meta(&"air_hang"))


## Air-assisted hang: while airborne and budget remains, gravity nearly off and the
## fall is braked (aerial strikes, charging in the air). Call every tick; returns
## true while hanging. `lift` keeps a small upward drift.
static func hang(ctx: BendingContext, delta: float, lift: float = 0.0) -> bool:
	if not airborne(ctx):
		return false
	var left := hang_left(ctx)
	if left <= 0.0:
		ctx.gravity_scale = 0.75
		return false
	ctx.caster.set_meta(&"air_hang", left - delta)
	ctx.gravity_scale = 0.06
	var v := ctx.body.velocity
	v.y = move_toward(v.y, lift, 30.0 * delta) if v.y < lift else move_toward(v.y, lift, 9.0 * delta)
	ctx.body.velocity = v
	return true


## Kicks up the ground under a passing gust (max 4 puffs) and pushes the world:
## the gust's wind impulse rides on its head; fires / props it passes react.
class GustPuffer extends RefCounted:
	var ctx: BendingContext
	var dir := Vector3.FORWARD
	var next_puff := 1.2
	var next_env := 0.8
	var puffs := 0
	var power := 0.5
	var radius := 1.0
	var impulse := 0

	func step(proj: BendingProjectile, _dt: float) -> void:
		var gp := proj.global_position
		if impulse != 0:
			AirWindField.move(impulse, gp, dir)
		if power > 0.0 and proj.traveled >= next_env:
			next_env += 1.6
			AirEnv.blow(proj, gp, proj.radius + 0.6, power, {"dir": dir, "plants": false, "ground": false, "by": ctx.caster if ctx != null and ctx.is_valid() else proj})
		if proj.traveled < next_puff or puffs >= 4:
			return
		next_puff += 1.6
		puffs += 1
		var gy := ctx.ground_y(gp, 1.0, 2.5) if ctx != null and ctx.is_valid() else gp.y - 1.0
		if gp.y - gy < 1.8:
			AirEnv.puff(proj, Vector3(gp.x, gy, gp.z), GroundSampler.surface(gp), 0.55, (dir + Vector3.UP).normalized())

	func done(_visual: Node3D) -> void:
		if impulse != 0:
			AirWindField.release(impulse)
			impulse = 0
