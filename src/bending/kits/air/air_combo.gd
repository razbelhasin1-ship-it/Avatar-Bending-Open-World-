extends ComboAbility
## Air Combo: palm gust (left), spinning hook-kick gust (low, wide), double-palm
## burst (staggers). Each strike launches a travelling gust volume from the
## striking hand / foot; every step pushes the target back (air keeps its distance).
## In the air every strike is air-assisted: the bender hangs (AirCommon.hang, 1.6 s
## per jump) and the gusts may angle down at targets below.

var _air := false


func begin() -> void:
	AirCommon.prepare()
	super.begin()


func on_step_begin(_i: int, _sd: Dictionary) -> void:
	_air = AirCommon.airborne(ctx)
	if _air:
		ctx.move_mode = BendingContext.Move.FREE
		ctx.move_speed_scale = 0.35


func update(delta: float) -> void:
	if _air:
		AirCommon.hang(ctx, delta, float(param("air_lift", 0.6)))
	super.update(delta)


func strike(_i: int, sd: Dictionary) -> void:
	var cfg: Dictionary = (sd.get("gust", {}) as Dictionary).duplicate()
	if _air:
		cfg["min_y"] = -0.7
		cfg["low"] = false
	var from := _origin(StringName(sd.get("hand", &"hand_l")))
	var dir := AirCommon.aim_dir(ctx, from, float(cfg.get("speed", 30.0)))
	if _air:
		dir = ctx.aim_dir_from(from, float(cfg.get("speed", 30.0)), 0.5)
	from += dir * 0.25
	AirCommon.gust(self, from, dir, cfg, step_hit())
	sound(&"cast_light", from, -1.0 if step < 2 else 1.0)
	if step == 1:
		# The hook kick throws a ring of wind off the pivot foot.
		AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.25, 0.9, 0.35, {"grow": 1.8, "spin": 16.0, "height": 0.1, "opacity": 0.6})
	if step == 2:
		if not _air:
			AirFx.ground_puff(ctx.caster, ctx.ground_point(ctx.origin() + dir * 0.8), ctx.surface_at(ctx.origin()), 0.8, (dir + Vector3.UP).normalized())
		BendingFeedback.impulse(dir, 0.12)


func _origin(socket: StringName) -> Vector3:
	if socket == &"hands":
		return ctx.hands_pos()
	return ctx.socket_pos(socket)
