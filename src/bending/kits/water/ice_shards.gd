extends BendingAbility
## Ice Shards (starter technique): water streams in from the nearest source
## (snow and ice count; otherwise the canteen: +30% chi), freezes into three
## ice daggers in front of the hands on the clip's gather, and they are hurled
## at the target on its release (slight lead, fanned).

var _shards: Array[MeshInstance3D] = []
var _formed := 0.0
var _src: Dictionary = {}


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func begin() -> void:
	ctx.move_mode = BendingContext.Move.FREE
	ctx.move_speed_scale = 0.3
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 900.0
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})
	_src = WaterSource.find(ctx)
	WaterSource.draw(ctx, _src, maxf(time_to_event(&"gather"), 0.15), &"hand_r")


func _shard_point(i: int, n: int) -> Vector3:
	var c := ctx.hands_pos() + ctx.forward() * 0.45 + Vector3.UP * 0.1
	var off := (float(i) - (n - 1) * 0.5) * 0.32
	return c + ctx.right() * off + Vector3.UP * (0.08 if i == 1 else 0.0)


func on_event(event: StringName) -> void:
	if event == &"gather":
		var n := int(param("count", 3))
		var size := WaterSource.size_mult(ctx)
		for i in n:
			var s := IceFx.shard(ctx.caster, 0.7 * size, i)
			s.global_position = _shard_point(i, n)
			s.scale = Vector3.ONE * 0.05
			_shards.append(s)
		FxBurst.spawn(ctx.caster, &"sparkle", ctx.hands_pos() + ctx.forward() * 0.4, {"count": 1.0})
		sound(&"freeze", ctx.hands_pos())
	elif event == &"release":
		_launch()


func update(delta: float) -> void:
	ctx.face_dir = ctx.aim_flat()
	if not _shards.is_empty():
		_formed = minf(1.0, _formed + delta / 0.18)
		var n := _shards.size()
		var size := WaterSource.size_mult(ctx)
		for i in n:
			var s := _shards[i]
			if not is_instance_valid(s):
				continue
			s.global_position = _shard_point(i, n)
			var aim := ctx.aim_dir_from(s.global_position, float(param("speed", 34.0)))
			s.global_basis = Basis.looking_at(aim, Vector3.UP).scaled(Vector3.ONE * maxf(0.05, _formed * size))
	if time >= clip_end:
		finish()


func _launch() -> void:
	var speed := float(param("speed", 34.0))
	var spread := deg_to_rad(float(param("spread_deg", 6.0)))
	var n := _shards.size()
	# Projectiles outlive this ability: use lambdas (they do not need `self`).
	var c := ctx
	var aid := def.id
	var flash := float(param("flash_freeze", 0.9))
	var shatter := func(p: BendingProjectile, pos: Vector3, normal: Vector3, t: Node) -> void:
		IceFx.shatter(p, pos, normal, 0.5)
		Audio.play_bending(ElementDefs.Element.WATER, &"shatter", pos, -4.0)
		# Ice on a soaked target: the water on it freezes solid (flash-freeze).
		if t != null and t is Node3D and flash > 0.0 and WaterStatus.is_soaked(t) and c != null and c.is_valid():
			IceShardsFreeze.flash_freeze(c, t as Node3D, flash, aid)
	var give_back := func(v: Node3D) -> void:
		if v != null and is_instance_valid(v):
			FxLib.release(v)
	for i in n:
		var s := _shards[i]
		if not is_instance_valid(s):
			continue
		var from := s.global_position
		var dir := ctx.aim_dir_from(from, speed, 0.7).rotated(Vector3.UP, (float(i) - (n - 1) * 0.5) * spread)
		var h := hit_data()
		# Each dagger is its own attack: all three can hit the same target.
		BendingProjectile.launch(ctx, from, dir, speed, h, {"radius": 0.14, "range": float(param("range", 30.0)), "gravity": 0.8,
				"attack_id": HitInfo.new_attack_id(), "ability_id": def.id, "visual": s, "align": true, "homing": 30.0,
				"impact_size": 0.6, "on_impact": shatter, "on_finish": give_back})
	_shards.clear()
	sound(&"cast_light", ctx.hands_pos(), 0.0)
	WaterCommon.practiced(ctx, def)


func _drop() -> void:
	for s in _shards:
		if is_instance_valid(s):
			IceFx.shatter(ctx.caster, s.global_position, Vector3.DOWN, 0.4)
			FxLib.release(s)
	_shards.clear()


func on_cancel(_reason: StringName) -> void:
	_drop()


func on_finish() -> void:
	_drop()


## Flash-freeze: an ice dagger striking a SOAKED target freezes the water on it.
class IceShardsFreeze extends RefCounted:
	static func flash_freeze(c: BendingContext, t: Node3D, base_stun: float, ability_id: StringName) -> void:
		var st := WaterStatus.freeze_time(t, base_stun)
		var h := c.make_hit({"damage": 2.0, "reaction": HitInfo.Reaction.FREEZE, "stun": st, "poise": 25.0, "status": {"frozen": st}},
				t.global_position - c.origin(), HitInfo.new_attack_id(), ability_id)
		h.position = BendingContext.target_point(t)
		var res := BendingHits.deliver(c, t, h)
		if res == Combat.Result.HIT:
			WaterStatus.clear(t)
			IcePrisonFx.encase(c.caster, t, st, 0.9)
			Audio.play_bending(ElementDefs.Element.WATER, &"freeze", t.global_position, -2.0)
