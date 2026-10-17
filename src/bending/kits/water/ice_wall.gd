extends BendingAbility
## Ice Wall (starter technique): sinking into a horse stance the bender lifts a
## sheet of water out of the ground (snow / a nearby source, the canteen
## without one) and clenches: it freezes into a wall of ice crystals (solid
## BendingConstruct: blocks movement, projectiles and line of sight). Fire
## melts it fast (x1.8). When enemies BREAK it, it shatters into a burst of
## ice shards flying at them; when it simply expires it shatters harmlessly.
## Over water the wall stands on a fresh ice floe (walkable).
## Events: gather (the water rises), release (the wall freezes up).

var _src: Dictionary = {}
var _size := 1.0
var wall: BendingConstruct = null
var floe: IceFloe = null


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func can_use() -> StringName:
	return &"" if WaterCommon.grounded(ctx) else &"airborne"


func begin() -> void:
	WaterCommon.prepare()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 900.0
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})
	_src = WaterSource.find(ctx)
	_size = WaterSource.size_mult(ctx)


func _place() -> Vector3:
	var dir := ctx.aim_flat()
	var dist := float(param("distance", 3.4))
	var t := ctx.aim_target()
	if t != null:
		var d := Vector2(t.global_position.x - ctx.origin().x, t.global_position.z - ctx.origin().z).length()
		dist = clampf(d - 1.6, 2.0, dist)
	var p := ctx.origin() + dir * dist
	return Vector3(p.x, ctx.ground_y(p + Vector3.UP * 0.5, 2.5, 4.0), p.z)


func on_event(event: StringName) -> void:
	match event:
		&"gather":
			var p := _place()
			WaterCommon.pull(ctx, _src, func() -> Vector3: return p + Vector3.UP * 0.4, maxf(time_to_event(&"release"), 0.1), 0.14 * _size, 2)
		&"release":
			_raise()


func _raise() -> void:
	var dir := ctx.aim_flat()
	var p := _place()
	var water := WaterEnv.water_level(p)
	if water > p.y + 0.25:
		# Frozen out of the water: a floe to stand on, the wall on top of it.
		floe = WaterEnv.freeze_floe(ctx, p, float(param("floe_radius", 3.0)), float(param("lifetime", 10.0)) + 2.0)
		p.y = water + IceFloe.FREEBOARD
	var size: Vector3 = param("size", Vector3(4.6, 2.8, 0.9))
	size = Vector3(size.x * _size, size.y * lerpf(0.8, 1.0, _size), size.z)
	wall = BendingConstruct.raise(ctx, p, dir, {"kind": &"ice", "size": size, "hp": float(param("hp", 150.0)) * _size,
			"lifetime": float(param("lifetime", 10.0)), "rise_time": float(param("rise_time", 0.22)),
			"launch": {"lift": float(param("lift", 5.0)), "damage": float(param("launch_damage", 6.0))}})
	# Shatter outward when broken by enemies (not when it expires).
	var c := ctx
	var shard_hit: Dictionary = param("shard_hit", {"damage": 7.0, "reaction": HitInfo.Reaction.FLINCH, "force": 3.0, "poise": 10.0,
			"status": {"chill": 2.0}})
	var n := int(param("shards", 7))
	var aid := def.id
	wall.broken.connect(func(w: BendingConstruct) -> void:
		if w.hp <= 0.0 and c != null and c.is_valid():
			IceWallShards.burst(c, w, n, shard_hit, aid))
	WaterEnv.extinguish(ctx, p + Vector3.UP, size.x * 0.6)
	if ctx.is_player():
		BendingFeedback.impulse(dir, 0.15)
	WaterCommon.practiced(ctx, def)


func update(_delta: float) -> void:
	if time >= clip_end:
		finish()


## Ice shards flying out of a broken wall (one attack per shard).
class IceWallShards extends RefCounted:
	static func burst(ctx: BendingContext, w: BendingConstruct, count: int, h: Dictionary, ability_id: StringName) -> void:
		var fwd := -w.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else ctx.forward()
		# Shards fly away from the caster's side (toward whoever broke it).
		if fwd.dot(w.global_position - ctx.origin()) < 0.0:
			fwd = -fwd
		var right := w.global_basis.x
		var give_back := func(v: Node3D) -> void:
			if v != null and is_instance_valid(v):
				FxLib.release(v)
		var shatter := func(p: BendingProjectile, pos: Vector3, normal: Vector3, _t: Node) -> void:
			IceFx.shatter(p, pos, normal, 0.35)
		for i in count:
			var u := (float(i) + 0.5) / count - 0.5
			var from := w.global_position + right * u * w.size.x * 0.9 + Vector3.UP * randf_range(0.6, w.size.y * 0.8) + fwd * 0.6
			var d := fwd.rotated(Vector3.UP, u * 0.9 + randf_range(-0.12, 0.12)) + Vector3.UP * randf_range(0.0, 0.15)
			var s := IceFx.shard(ctx.caster, 0.55, i % 4)
			BendingProjectile.launch(ctx, from, d.normalized(), 22.0, h, {"radius": 0.16, "range": 10.0, "gravity": 2.0,
					"attack_id": HitInfo.new_attack_id(), "ability_id": ability_id, "visual": s, "align": true, "homing": 0.0,
					"impact_size": 0.4, "on_impact": shatter, "on_finish": give_back})
