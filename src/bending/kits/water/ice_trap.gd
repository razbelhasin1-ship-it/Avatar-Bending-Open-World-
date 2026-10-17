extends BendingAbility
## Ice Trap (unlock): a low sweeping palm sends a snake of water skimming along
## the ground to the target's feet (or the aimed spot); on the fist clench
## (clip event &"freeze") it freezes: everyone standing there is encased in ice
## (FREEZE root, longer on SOAKED targets), shown by an ice prison around the
## legs. If nobody is caught the frozen patch stays armed for a few seconds and
## catches the first enemy stepping in. Aimed at open water it freezes the
## surface into a walkable ice floe instead.
## Events: release (the water leaves the hand), freeze (it freezes).

var _src: Dictionary = {}
var _size := 1.0
var _target_pos := Vector3.ZERO
var _from := Vector3.ZERO
var _snake: WaterStream = null
var _t_release := 0.0
var _t_freeze := 0.3
var _released := false
var frozen: Array[Node] = []
var floe: IceFloe = null
var trap: IceTrapZone = null


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func can_use() -> StringName:
	return &"" if WaterCommon.grounded(ctx) else &"airborne"


func begin() -> void:
	WaterCommon.prepare()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1080.0
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})
	_src = WaterSource.find(ctx)
	_size = WaterSource.size_mult(ctx)
	_target_pos = WaterCommon.aim_ground(ctx, float(param("range", 14.0)), float(param("default_distance", 8.0)))
	var o := WaterCommon.origin(ctx, _src)
	if StringName(o["kind"]) != &"canteen" and (o["start"] as Vector3).distance_to(ctx.origin()) > 2.0:
		var c := ctx
		WaterCommon.pull(ctx, _src, func() -> Vector3: return c.socket_pos(&"hand_r") if c.is_valid() else Vector3.ZERO,
				maxf(time_to_event(&"release"), 0.12), 0.08, 1)


func on_event(event: StringName) -> void:
	match event:
		&"release":
			_released = true
			_t_release = time
			_t_freeze = maxf(time_to_event(&"freeze"), 0.08)
			# Track a moving target until the water arrives.
			_target_pos = WaterCommon.aim_ground(ctx, float(param("range", 14.0)), float(param("default_distance", 8.0)))
			_from = ctx.ground_point(ctx.socket_pos(&"hand_r"))
			_snake = WaterStream.spawn(ctx.caster)
			sound(&"cast_light", ctx.socket_pos(&"hand_r"))
			ctx.face_dir = Vector3.ZERO
		&"freeze":
			_freeze()


func update(_delta: float) -> void:
	if not _released:
		ctx.face_dir = ctx.aim_flat()
	elif _snake != null and is_instance_valid(_snake):
		var t := ctx.aim_target()
		if t != null and t.global_position.distance_to(_target_pos) < 2.5:
			_target_pos = Vector3(t.global_position.x, _target_pos.y, t.global_position.z)
		_update_snake(clampf((time - _t_release) / _t_freeze, 0.0, 1.0))
	if time >= clip_end:
		finish()


## The water skims the ground from the hand to the target, a low wake behind.
func _update_snake(u: float) -> void:
	var head := _from.lerp(_target_pos, 1.0 - pow(1.0 - u, 1.6))
	var pts := PackedVector3Array()
	var n := 8
	var right := (_target_pos - _from).cross(Vector3.UP).normalized()
	for k in n:
		var s := float(k) / (n - 1)
		var p := _from.lerp(head, s)
		p += right * sin(s * 9.0 - time * 14.0) * 0.18 * s
		p.y = WaterEnv.surface_y(ctx, p + Vector3.UP * 0.8, 1.2, 2.5) + 0.12
		pts.append(p)
	_snake.set_points(pts, 0.14 * _size, 0.06)
	_snake.set_spray(true)
	if randf() < 0.35:
		WaterEnv.splash_ground(ctx.caster, Vector3(head.x, pts[n - 1].y - 0.1, head.z), 0.35)


func _freeze() -> void:
	if _snake != null and is_instance_valid(_snake):
		_snake.freeze = 1.0
		_snake.finish(0.35)
	_snake = null
	var p := _target_pos
	var radius := float(param("radius", 1.4)) * lerpf(0.8, 1.0, _size)
	var base_stun := float(param("stun", 2.0)) * lerpf(0.75, 1.0, _size)
	frozen = IceTrapZone.freeze_at(ctx, p, radius, hit_data(), base_stun, attack_id, def.id)
	sound(&"freeze", p)
	if frozen.is_empty():
		if WaterEnv.is_over_water(ctx, p):
			floe = WaterEnv.freeze_floe(ctx, p, float(param("floe_radius", 2.6)), float(param("floe_lifetime", 14.0)))
		else:
			trap = IceTrapZone.arm(ctx, p, radius, hit_data(), base_stun, def.id, float(param("armed_time", 4.0)))
	if ctx.is_player() and not frozen.is_empty():
		BendingFeedback.shake(0.18, 0.12)
	WaterCommon.practiced(ctx, def)


func _drop() -> void:
	if _snake != null and is_instance_valid(_snake):
		_snake.finish(0.15)
	_snake = null


func on_cancel(_reason: StringName) -> void:
	_drop()


func on_finish() -> void:
	_drop()
