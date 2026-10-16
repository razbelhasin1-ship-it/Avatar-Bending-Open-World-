class_name EarthCommon
extends RefCounted
## Shared earth pieces: a rock torn out of the ground that rises to a point
## (RockRiser), and launching a rock as a projectile (spinning, dust trail,
## debris + optional splash damage on impact).


## Tears a rock of `radius` out of the ground at `ground_pos` and lifts it to
## `to` over `duration` s. Keep the returned riser; launch() hands the rock over.
static func rise_rock(ctx: BendingContext, ground_pos: Vector3, to: Vector3, radius: float, duration: float) -> RockRiser:
	var r := RockRiser.new()
	r.ctx = ctx
	r.rock = EarthFx.rock(ctx.caster, radius)
	r.start = ground_pos - Vector3.UP * radius
	r.target = to
	r.duration = maxf(duration, 0.02)
	r.rock.global_position = r.start
	r.spin = Vector3(randf_range(-3, 3), randf_range(-4, 4), randf_range(-3, 3))
	FxLib.root(ctx.caster).add_child(r)
	EarthFx.tear_out(ctx.caster, ground_pos, radius * 1.4, GroundSampler.surface(ground_pos))
	BendingFeedback.sound(ElementDefs.Element.EARTH, &"debris", ground_pos, -6.0)
	return r


## Launches `rock` (a pooled EarthFx.rock node) as a projectile.
## opts: splash (radius of area damage on impact), splash_hit (dict), gravity, range.
static func launch(ab: BendingAbility, rock: MeshInstance3D, from: Vector3, dir: Vector3, speed: float, radius: float, h: Dictionary, opts: Dictionary = {}) -> BendingProjectile:
	var ctx := ab.ctx
	var splash := float(opts.get("splash", 0.0))
	var splash_hit: Dictionary = opts.get("splash_hit", {})
	var aid := ab.attack_id
	var aname := ab.def.id
	var trail := DustTrail.new()
	var impact := func(proj: BendingProjectile, pos: Vector3, _n: Vector3, target: Node) -> void:
		var gy := ctx.ground_y(pos, 1.0, 3.0) if ctx.is_valid() else pos.y - 0.5
		EarthFx.impact(proj, pos, radius * 2.2, GroundSampler.surface(pos), gy)
		if target != null:
			BendingFeedback.sound(ElementDefs.Element.EARTH, &"impact", pos, 0.0)
		if splash > 0.0 and ctx.is_valid():
			BendingHits.sphere(ctx, pos, splash, splash_hit, aid, aname, {"push": &"radial", "los": false})
			if ctx.is_player():
				BendingFeedback.shake(0.3, 0.25)
	var done := func(v: Node3D) -> void:
		if v != null and is_instance_valid(v):
			EarthFx.release_rock(v as MeshInstance3D)
	var p := BendingProjectile.launch(ctx, from, dir, speed, h, {
		"radius": radius * 0.95, "range": float(opts.get("range", 28.0)), "gravity": float(opts.get("gravity", 3.0)),
		"attack_id": aid, "ability_id": aname, "visual": rock, "align": false,
		"spin": Vector3(randf_range(6, 10), 0, randf_range(-4, 4)), "impact_size": radius * 2.5,
		"on_impact": impact, "on_step": trail.step, "on_finish": done,
	})
	p.set_meta(&"trail", trail)
	return p


## Animates a rock rising out of the ground to a target point (and holding there).
class RockRiser extends Node3D:
	var ctx: BendingContext
	var rock: MeshInstance3D
	var start := Vector3.ZERO
	var target := Vector3.ZERO
	var duration := 0.2
	var t := 0.0
	var spin := Vector3.ZERO
	var released := false
	## Follow a moving point after rising (boulder held overhead).
	var follow: Callable = Callable()
	var bob := 0.0

	func _process(delta: float) -> void:
		if released or rock == null or not is_instance_valid(rock):
			queue_free()
			return
		t += delta
		if follow.is_valid():
			target = follow.call()
		var u := clampf(t / duration, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		var p := start.lerp(target, e)
		if u >= 1.0:
			bob += delta
			p = target + Vector3.UP * sin(bob * 3.2) * 0.04
		rock.global_position = p
		rock.rotate_object_local(Vector3(1, 0, 0), spin.x * delta * (1.0 - e * 0.8))
		rock.rotate_object_local(Vector3(0, 1, 0), spin.y * delta * (1.0 - e * 0.8))

	## Hands the rock over (to a projectile) and stops animating it.
	func take() -> MeshInstance3D:
		released = true
		return rock

	## Drops the rock back into the ground (ability cancelled).
	func drop() -> void:
		if released or rock == null:
			return
		released = true
		if is_instance_valid(rock):
			FxDebris.spawn(rock, rock.global_position, {"count": 5, "size": rock.scale.x * 0.25, "up": 2.0, "out": 1.5, "ground_y": start.y})
			EarthFx.release_rock(rock)


## Dust shed by a flying rock (every ~1.5 m, max 6).
class DustTrail extends RefCounted:
	var next := 1.0
	var n := 0

	func step(proj: BendingProjectile, _dt: float) -> void:
		if proj.traveled < next or n >= 6:
			return
		next += 1.5
		n += 1
		FxBurst.spawn(proj, &"dust", proj.global_position, {"color": Color(0.7, 0.62, 0.5), "count": 0.25, "size": 0.45, "speed": 0.4})
