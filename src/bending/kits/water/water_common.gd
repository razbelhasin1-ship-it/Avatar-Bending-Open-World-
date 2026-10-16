class_name WaterCommon
extends RefCounted
## Helpers shared by the Water abilities: where the water comes from (and the
## visible pull from that source), aim points on the ground, practice
## bookkeeping, carrying targets along with moving water.

## Water closer than this is "at the feet" (snow, ice, standing in a pool).
const NEAR := 1.5


## Every Water ability calls this in begin(): clips + the soaked listener.
static func prepare() -> void:
	WaterClips.ensure()
	WaterStatus.ensure()


## Standing on something (floor contact, or the ground / a floe just under the
## feet): the big earth-bound techniques need footing, not a perfect contact flag.
static func grounded(ctx: BendingContext) -> bool:
	if ctx.body == null or ctx.body.is_on_floor():
		return true
	var o := ctx.origin()
	if o.y - WaterEnv.surface_y(ctx, o + Vector3.UP * 0.5, 0.8, 2.0) < 0.45 and ctx.body.velocity.y < 1.0:
		return true
	return IceFloe.supports(o)


## Where visible water comes from for `src` (WaterSource.find result):
## {"start": Vector3, "kind": &"water"|&"snow"|&"ice"|&"canteen", "surface_y": float}.
static func origin(ctx: BendingContext, src: Dictionary) -> Dictionary:
	var found := bool(src.get("found", false))
	var kind: StringName = src.get("kind", &"")
	if not found:
		return {"start": ctx.socket_pos(&"pelvis") + ctx.right() * 0.22, "kind": &"canteen", "surface_y": ctx.origin().y}
	if kind == &"snow" or kind == &"ice" or float(src.get("distance", 0.0)) < NEAR:
		var g := ctx.ground_point(ctx.origin() + ctx.forward() * 1.3)
		var k: StringName = kind if kind == &"snow" or kind == &"ice" else &"water"
		if k == &"water":
			var w := WaterEnv.water_level(g)
			if w > -INF:
				g.y = maxf(g.y, w)
		return {"start": g, "kind": k, "surface_y": g.y}
	var p: Vector3 = src["position"]
	return {"start": p, "kind": &"water", "surface_y": p.y}


## Pulls water from the caster's source to `target_fn()` over `duration` s
## (thick strands for big techniques). Without a source a thin canteen stream.
static func pull(ctx: BendingContext, src: Dictionary, target_fn: Callable, duration: float, radius: float = 0.12, strands: int = 1) -> Array[WaterStream]:
	var o := origin(ctx, src)
	var kind: StringName = o["kind"]
	if kind == &"canteen":
		radius = minf(radius, 0.05)
		strands = 1
	BendingFeedback.sound(ElementDefs.Element.WATER, &"draw", o["start"], -3.0)
	return WaterFx.pull(ctx.caster, o["start"], target_fn, duration, {"radius": radius, "strands": strands, "kind": kind,
			"surface_y": float(o["surface_y"]), "arc": 0.6 if kind == &"snow" else 1.0})


## Ground point the caster aims at: the target's feet (lock / soft aim) within
## `max_dist`, else the camera aim ray's ground hit, else `fallback` m ahead.
static func aim_ground(ctx: BendingContext, max_dist: float, fallback: float) -> Vector3:
	var o := ctx.origin()
	var t := ctx.aim_target()
	if t != null and t.global_position.distance_to(o) <= max_dist + 1.0:
		var tp := t.global_position
		return Vector3(tp.x, WaterEnv.surface_y(ctx, tp + Vector3.UP * 0.5, 1.5, 4.0), tp.z)
	var a := ctx.aim()
	var pt: Vector3 = a.get("point", Vector3.INF)
	var flat := ctx.aim_flat()
	var p := o + flat * fallback
	if pt.is_finite():
		var d := Vector2(pt.x - o.x, pt.z - o.z).length()
		if d > 1.5 and d <= max_dist:
			p = Vector3(pt.x, o.y, pt.z)
		elif d > max_dist:
			p = o + flat * max_dist
	return Vector3(p.x, WaterEnv.surface_y(ctx, p + Vector3.UP * 0.5, 2.5, 6.0), p.z)


## Practice: a technique performed by the player counts toward the unlock
## rules that require practising it (AbilityDef.unlock "practice").
static func practiced(ctx: BendingContext, def: AbilityDef) -> void:
	if ctx != null and ctx.is_player() and def != null and not String(def.id).begins_with("enemy_"):
		GameState.add_practice(def.id)


## Moving water carries a target along: horizontal velocity at least `speed`
## along `dir` (CharacterBody3D targets only; never the caster).
static func carry(ctx: BendingContext, target: Node, dir: Vector3, speed: float) -> void:
	var cb := target as CharacterBody3D
	if cb == null or cb == ctx.caster or not Combat.is_alive(cb):
		return
	var hv := Vector3(cb.velocity.x, 0.0, cb.velocity.z)
	var along := hv.dot(dir)
	if along < speed:
		hv += dir * (speed - along)
		cb.velocity.x = hv.x
		cb.velocity.z = hv.z


## Body velocity.y that brings the caster's feet to `target_y` (abilities that
## ride or lift on water set ctx.gravity_scale = 0 and call this every tick).
static func hold_height(ctx: BendingContext, target_y: float, rate: float = 10.0, max_speed: float = 9.0) -> void:
	if ctx.body == null:
		return
	ctx.body.velocity.y = clampf((target_y - ctx.origin().y) * rate, -max_speed, max_speed)


## Health of a damageable (player, enemy, dummy): its HealthComponent or null.
static func health_of(n: Node) -> HealthComponent:
	if n == null or not is_instance_valid(n):
		return null
	if n.has_method("get_health_component"):
		return n.call("get_health_component") as HealthComponent
	if "health" in n and n.get("health") is HealthComponent:
		return n.get("health")
	return null
