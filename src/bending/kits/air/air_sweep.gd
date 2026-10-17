extends BendingAbility
## Air Sweep (starter technique): a low 360° sweep kick; on the clip's release
## a ring of wind bursts outward and knocks back every enemy around. The ground
## answers: dust / leaves / snow ring, grass flattened in a circle, props shoved,
## small fires blown out.


func can_use() -> StringName:
	AirCommon.prepare()
	return &""


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.poise_armor = 20.0
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})
	AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.4, 0.6, 0.4, {"grow": 1.4, "spin": 12.0, "height": 0.2, "opacity": 0.5})


func update(delta: float) -> void:
	if AirCommon.airborne(ctx):
		AirCommon.hang(ctx, delta, 0.0)
	super.update(delta)


func on_event(event: StringName) -> void:
	if event != &"release":
		return
	var radius := float(param("radius", 4.6))
	var center := ctx.origin() + Vector3.UP * 0.6
	BendingHits.sphere(ctx, center, radius, hit_data(), attack_id, def.id, {"push": &"radial"})
	var g := ctx.ground_point(ctx.origin())
	AirFx.swirl(ctx.caster, g + Vector3.UP * 0.35, radius * 0.55, 0.5, {"grow": 1.9, "spin": 13.0, "height": 0.35, "tilt": 0.08, "opacity": 0.9})
	AirFx.swirl(ctx.caster, g + Vector3.UP * 0.9, radius * 0.35, 0.45, {"grow": 2.4, "spin": -10.0, "height": 0.2, "tilt": 0.12, "opacity": 0.6})
	FxRing.spawn(ctx.caster, g, radius, Color(0.92, 0.97, 1.0), 0.5, {"opacity": 0.6, "width": 0.14, "fill": 0.15})
	AirEnv.blow(ctx, g, radius, 1.0, {"mode": &"vortex", "dir": Vector3(-1, 0, 0), "by": ctx.caster})
	sound(&"cast_heavy", center, 1.0)
	AirEnv.practiced(ctx, def.id)
	if ctx.is_player():
		BendingFeedback.shake(0.22, 0.2)
