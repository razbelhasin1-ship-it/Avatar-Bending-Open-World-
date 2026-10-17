extends BendingAbility
## Fire Ring: coil, spin on the left foot with the right leg sweeping at hip height;
## when the leg whips through the front (&"release") a standing wall of flame races
## out in a full circle (FireRingWave: 6.5 m in 0.38 s). Each target is hit once, when
## the flames reach it: KNOCKBACK + burn. Counterplay: jump it (> 1.4 m clear), stand
## behind a wall, or be outside 6.5 m. A scorched ring stays.


func begin() -> void:
	FireCommon.begin()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1440.0
	ctx.poise_armor = def.poise_armor
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})


func on_event(event: StringName) -> void:
	if event != &"release":
		return
	ctx.face_dir = Vector3.ZERO
	var g := ctx.ground_point(ctx.origin())
	FireRingWave.start(ctx, g, float(param("radius", 6.5)), float(param("wave_time", 0.38)), hit_data(), attack_id, def.id,
			{"height": float(param("height", 1.35)), "clearance": float(param("clearance", 1.4)), "r0": 0.7, "lean": 0.3, "power": 1.0})
	var foot := ctx.socket_pos(&"foot_r")
	FireFx.burst(ctx.caster, foot, 1.0, Vector3.UP)
	FxFlash.spawn(ctx.caster, g + Vector3.UP * 0.8, FireCommon.HOT, 4.0, 0.45, 9.0)
	HeatShimmer.spawn(ctx.caster, g, 3.0, 2.2, 0.6, 0.8)
	sound(&"special", g, 1.0)
	FireCommon.shake(ctx, 0.28, 0.25)
	BendingFeedback.impulse(Vector3.UP, 0.12)
	FireCommon.practiced(ctx, def.id)
