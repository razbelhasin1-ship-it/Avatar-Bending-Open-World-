extends ComboAbility
## Air Combo: palm gust (left), spinning kick gust (low, wide), double-palm
## burst (staggers). Each strike launches a travelling gust volume from the
## striking hand/foot; every step pushes.


func strike(_i: int, sd: Dictionary) -> void:
	var cfg: Dictionary = sd.get("gust", {})
	var from := _origin(StringName(sd.get("hand", &"hand_l")))
	var dir := AirCommon.aim_dir(ctx, from, float(cfg.get("speed", 30.0)))
	from += dir * 0.25
	AirCommon.gust(self, from, dir, cfg, step_hit())
	sound(&"cast_light", from, -1.0 if step < 2 else 1.0)
	if step == 1:
		# Spinning kick throws a ring of wind off the planted foot.
		AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.25, 0.9, 0.35, {"grow": 1.8, "spin": 16.0, "height": 0.1, "opacity": 0.6})
	if step == 2:
		AirFx.ground_puff(ctx.caster, ctx.ground_point(ctx.origin() + dir * 0.8), ctx.surface_at(ctx.origin()), 0.8, (dir + Vector3.UP).normalized())
		BendingFeedback.impulse(dir, 0.12)


func _origin(socket: StringName) -> Vector3:
	if socket == &"hands":
		return ctx.hands_pos()
	return ctx.socket_pos(socket)
