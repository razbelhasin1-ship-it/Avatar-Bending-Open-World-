class_name BendingHits
extends RefCounted
## Area / cone / sweep hit helpers for abilities. Every target is hit at most
## ONCE per attack_id, hits need line of sight (walls and constructs block
## them), and every delivered hit goes through BendingFeedback so the impact
## VFX / hitstop / shake only appear for hits that gameplay really applied.
##
##   BendingHits.sphere(ctx, center, 4.5, hit_dict, attack_id, &"air_sweep", {"push": &"radial"})
##   BendingHits.cone(ctx, origin, dir, 7.0, 55.0, hit_dict, attack_id, &"flame_sweep")
##   BendingHits.sweep(ctx, from, to, 0.45, hit_dict, attack_id, &"water_whip")
##   BendingHits.deliver(ctx, target, hit)      # single target (projectiles use this)
## opts: push (&"radial" from the centre, &"forward" along `dir`, &"pull" toward
## the origin), los (bool, default true), exclude (Array of nodes), meta (Dictionary set on
## every HitInfo: &"no_hitstop" / &"no_focus" for sustained pulses, see BendingFeedback).
## Returns [{target, result, hit}] for every target the attack reached.

const LOG_SIZE := 256

## attack_id -> {instance_id: true}
static var _log: Dictionary = {}
static var _order: Array[int] = []
## Total hits delivered with a HIT/KILLED result (tests).
static var applied_hits := 0


static func already_hit(attack_id: int, target: Node) -> bool:
	return attack_id != 0 and _log.has(attack_id) and (_log[attack_id] as Dictionary).has(target.get_instance_id())


static func mark(attack_id: int, target: Node) -> void:
	if attack_id == 0:
		return
	if not _log.has(attack_id):
		_log[attack_id] = {}
		_order.append(attack_id)
		if _order.size() > LOG_SIZE:
			_log.erase(_order.pop_front())
	(_log[attack_id] as Dictionary)[target.get_instance_id()] = true


static func clear_log() -> void:
	_log.clear()
	_order.clear()


## Delivers one hit (once per attack_id), with feedback. Returns the Combat.Result.
static func deliver(ctx: BendingContext, target: Node, hit: HitInfo) -> int:
	var dmg := Combat.find_damageable(target)
	if dmg == null or already_hit(hit.attack_id, dmg):
		return Combat.Result.IGNORED
	if not Combat.can_hit(dmg, hit):
		return Combat.Result.IGNORED
	if hit.position == Vector3.ZERO and dmg is Node3D:
		hit.position = BendingContext.target_point(dmg as Node3D)
	var requested := hit.damage
	var result := Combat.deal(dmg, hit)
	if result == Combat.Result.IGNORED:
		return result
	mark(hit.attack_id, dmg)
	if result == Combat.Result.HIT or result == Combat.Result.KILLED:
		applied_hits += 1
	BendingFeedback.on_result(ctx, hit, dmg, result, requested)
	if ctx != null and ctx.on_hit.is_valid():
		ctx.on_hit.call(hit, dmg, result)
	return result


## Unique damageables overlapping a sphere (caster excluded).
static func targets_in_sphere(ctx: BendingContext, center: Vector3, radius: float, extra_exclude: Array = []) -> Array[Node]:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = ctx.hit_mask()
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = ctx.exclude()
	var out: Array[Node] = []
	for r: Dictionary in ctx.space().intersect_shape(params, 48):
		var col: Object = r.get("collider")
		if col == null or not (col is Node):
			continue
		var d := Combat.find_damageable(col as Node)
		if d != null and d != ctx.caster and not out.has(d) and not extra_exclude.has(d):
			out.append(d)
	return out


## True if nothing solid (terrain, constructs other than `target`) is between a and b.
static func line_of_sight(ctx: BendingContext, a: Vector3, b: Vector3, target: Node = null) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Layers.SOLID)
	var ex := ctx.exclude()
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())
	q.exclude = ex
	var r := ctx.space().intersect_ray(q)
	if r.is_empty():
		return true
	var hit_node := Combat.find_damageable(r["collider"] as Node) if r["collider"] is Node else null
	return hit_node != null and hit_node == target


static func sphere(ctx: BendingContext, center: Vector3, radius: float, h: Dictionary, attack_id: int, ability_id: StringName,
		opts: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in targets_in_sphere(ctx, center, radius, opts.get("exclude", [])):
		var tp := BendingContext.target_point(t as Node3D) if t is Node3D else center
		if bool(opts.get("los", true)) and not line_of_sight(ctx, center + Vector3.UP * 0.2, tp, t):
			continue
		out.append(_hit_one(ctx, t, center, tp, h, attack_id, ability_id, opts))
	return out


static func cone(ctx: BendingContext, origin: Vector3, dir: Vector3, range_m: float, half_angle_deg: float, h: Dictionary,
		attack_id: int, ability_id: StringName, opts: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fwd := Vector3(dir.x, 0.0, dir.z).normalized()
	var cos_limit := cos(deg_to_rad(half_angle_deg))
	var o := Dictionary(opts)
	if not o.has("push"):
		o["push"] = &"forward"
	o["dir"] = fwd
	for t in targets_in_sphere(ctx, origin, range_m, opts.get("exclude", [])):
		if not (t is Node3D):
			continue
		var tp := BendingContext.target_point(t as Node3D)
		var to := tp - origin
		to.y = 0.0
		if to.length() > 0.8 and fwd.dot(to.normalized()) < cos_limit:
			continue
		if bool(opts.get("los", true)) and not line_of_sight(ctx, origin, tp, t):
			continue
		out.append(_hit_one(ctx, t, origin, tp, h, attack_id, ability_id, o))
	return out


## Capsule from `a` to `b` (whips, kicks, beams).
static func sweep(ctx: BendingContext, a: Vector3, b: Vector3, radius: float, h: Dictionary, attack_id: int, ability_id: StringName,
		opts: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seg := b - a
	var length := seg.length()
	if length < 0.01:
		return sphere(ctx, a, radius, h, attack_id, ability_id, opts)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = length + radius * 2.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	var y := seg / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	params.transform = Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), (a + b) * 0.5)
	params.collision_mask = ctx.hit_mask()
	params.collide_with_areas = true
	params.exclude = ctx.exclude()
	var o := Dictionary(opts)
	if not o.has("push"):
		o["push"] = &"forward"
	o["dir"] = Vector3(seg.x, 0.0, seg.z).normalized()
	var seen: Array[Node] = []
	for r: Dictionary in ctx.space().intersect_shape(params, 32):
		var col: Object = r.get("collider")
		if col == null or not (col is Node):
			continue
		var t := Combat.find_damageable(col as Node)
		if t == null or t == ctx.caster or seen.has(t) or (opts.get("exclude", []) as Array).has(t):
			continue
		seen.append(t)
		var tp := BendingContext.target_point(t as Node3D) if t is Node3D else b
		# Closest point on the segment, for the impact position.
		var u := clampf((tp - a).dot(y) / length, 0.0, 1.0)
		var cp := a + seg * u
		if bool(opts.get("los", true)) and not line_of_sight(ctx, a, cp.lerp(tp, 0.5), t):
			continue
		out.append(_hit_one(ctx, t, cp, tp, h, attack_id, ability_id, o))
	return out


static func _hit_one(ctx: BendingContext, t: Node, from: Vector3, tp: Vector3, h: Dictionary, attack_id: int, ability_id: StringName,
		opts: Dictionary) -> Dictionary:
	var dir := Vector3.ZERO
	match StringName(opts.get("push", &"radial")):
		&"forward":
			dir = opts.get("dir", ctx.forward())
		&"pull":
			dir = from - tp
		_:
			dir = tp - from
	dir.y = 0.0
	if dir.length_squared() < 1e-4:
		dir = ctx.forward()
	var hit := ctx.make_hit(h, dir.normalized(), attack_id, ability_id)
	hit.origin = from
	hit.position = tp.lerp(from, 0.25) if from.distance_to(tp) < 3.0 else tp
	# Hit metadata for sustained multi-hit moves (opts "meta": {&"no_hitstop": true, &"no_focus": true}).
	var meta: Dictionary = opts.get("meta", {})
	for k: StringName in meta:
		hit.set_meta(k, meta[k])
	var res := deliver(ctx, t, hit)
	return {"target": t, "result": res, "hit": hit}


## Number of entries with a landed (HIT / KILLED) result.
static func count_landed(results: Array) -> int:
	var n := 0
	for r: Dictionary in results:
		if int(r["result"]) == Combat.Result.HIT or int(r["result"]) == Combat.Result.KILLED:
			n += 1
	return n
