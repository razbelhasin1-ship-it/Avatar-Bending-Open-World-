class_name WaterEnv
extends RefCounted
## Water <-> world interactions shared by the Water techniques
## (docs/modules/bending_water.md "Environment"):
##
## * EXTINGUISH HOOK (shared contract, any module may implement it): a Node3D in
##   group &"extinguishable" with `func extinguish(by: Node, at: Vector3) -> bool`
##   (true = a fire went out) and optional `var extinguish_radius: float` (its size)
##   is put out by water that reaches it. Enemy fire projectiles caught in the
##   water are doused in flight. See ExtinguishableFire for a ready-made fire.
##     WaterEnv.extinguish(ctx, center, radius) -> number of fires put out
## * ICE FLOES: freezing a water surface into a temporary walkable platform.
##     WaterEnv.freeze_floe(ctx, point, radius, lifetime) -> IceFloe (or null on dry land)
## * Surfaces: water level / standing height over ground or water.
##     WaterEnv.water_level(p) -> y or -INF, WaterEnv.surface_y(ctx, p), WaterEnv.is_over_water(ctx, p)
## * Marks: WaterEnv.splash_ground(from, p, size) (wet decal / snow spray by surface).

const GROUP := &"extinguishable"
const STEAM := Color(0.92, 0.95, 0.97)

## Fires put out since start (tests / stats).
static var extinguished := 0


## Puts out every extinguishable fire and dousing enemy fire projectile within
## `radius` of `center`. Returns how many fires went out.
static func extinguish(ctx: BendingContext, center: Vector3, radius: float) -> int:
	if ctx == null or not ctx.is_valid():
		return 0
	var n := 0
	for node in ctx.tree().get_nodes_in_group(GROUP):
		if not (node is Node3D) or not is_instance_valid(node) or not node.has_method("extinguish"):
			continue
		var extra := float(node.get("extinguish_radius")) if "extinguish_radius" in node else 0.0
		if (node as Node3D).global_position.distance_to(center) > radius + extra:
			continue
		if bool(node.call("extinguish", ctx.caster, center)):
			n += 1
	for p in BendingProjectile.live.duplicate():
		if not is_instance_valid(p) or not p.alive or p.team == ctx.team or p.element != ElementDefs.Element.FIRE:
			continue
		if p.global_position.distance_to(center) <= radius + p.radius:
			FxBurst.spawn(ctx.caster, &"steam", p.global_position, {"count": 0.7, "size": 0.8})
			p.destroy(false)
			n += 1
	if n > 0:
		extinguished += n
		FxBurst.spawn(ctx.caster, &"steam", center + Vector3.UP * 0.3, {"count": 1.0, "size": 1.0, "radius": clampf(radius, 0.5, 3.0)})
		Audio.play_bending(ElementDefs.Element.FIRE, &"extinguish", center, -2.0)
	return n


## Water surface height at a point (sea, lakes, canals, pools), -INF if dry.
static func water_level(p: Vector3) -> float:
	return GroundSampler.water_height(p)


## Height something rests on at `p`: the water surface over water, else the ground.
static func surface_y(ctx: BendingContext, p: Vector3, probe_up: float = 3.0, probe_down: float = 8.0) -> float:
	var g := ctx.ground_y(p, probe_up, probe_down)
	var w := water_level(p)
	return maxf(g, w) if w > -INF else g


static func is_over_water(ctx: BendingContext, p: Vector3) -> bool:
	var w := water_level(p)
	return w > -INF and w > ctx.ground_y(p, 3.0, 8.0) + 0.25


## Freezes the water surface around `point` into a walkable ice floe. Returns
## null when there is no open water there.
static func freeze_floe(ctx: BendingContext, point: Vector3, radius: float = 2.6, lifetime: float = 14.0) -> IceFloe:
	if not is_over_water(ctx, point):
		return null
	var level := water_level(point)
	return IceFloe.create(ctx.caster, Vector3(point.x, level, point.z), radius, lifetime)


## Water landing on the ground: wet mark, or a snow spray on snow, or a splash ring on water.
static func splash_ground(from: Node, p: Vector3, size: float = 1.0, dir: Vector3 = Vector3.UP) -> void:
	var surf := GroundSampler.surface(p)
	var w := water_level(p)
	if w > -INF and w >= p.y - 0.3:
		var wp := Vector3(p.x, w, p.z)
		IceFx.splash(from, wp + Vector3.UP * 0.05, size, dir)
		FxRing.spawn(from, wp, 0.8 + size, Color(0.8, 0.93, 1.0), 0.5, {"opacity": 0.55, "fill": 0.15, "width": 0.1})
		return
	if surf == &"snow":
		snow_spray(from, p, dir, size)
		return
	FxDecal.spawn(from, p, &"wet", 0.6 + size * 0.7)
	if size > 0.6:
		FxBurst.spawn(from, &"droplets", p + Vector3.UP * 0.1, {"count": 0.4 + size * 0.4, "dir": dir})


## Snow kicked up by water bending on snow (draws, slides, wave paths).
static func snow_spray(from: Node, p: Vector3, dir: Vector3 = Vector3.UP, strength: float = 1.0) -> void:
	FxBurst.spawn(from, &"snow", p + Vector3.UP * 0.1, {"count": 0.6 + strength * 0.6, "size": 0.7 + strength * 0.4, "dir": (dir + Vector3.UP).normalized()})
	if strength > 0.7:
		FxBurst.spawn(from, &"dust_ring", p, {"color": FxLib.surface_color(&"snow"), "count": 0.6 * strength, "size": 0.8})
