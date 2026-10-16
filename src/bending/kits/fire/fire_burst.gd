extends BendingAbility
## Fire Burst (starter technique): breathe in and sink with both fists chambered
## (&"gather": the fists flare), stomp into a horse stance and throw both palms out
## (&"release"): a point-blank explosion. Inside 2 m targets are knocked DOWN, out to
## 3.8 m knocked BACK; incoming projectiles are burnt away; the ground is scorched and
## grass catches. Poise armor through the wind-up: the answer to being surrounded.


func begin() -> void:
	FireCommon.begin()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 45.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1440.0
	ctx.poise_armor = def.poise_armor
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})


func on_event(event: StringName) -> void:
	match event:
		&"gather":
			# The breath: both fists flare at the ribs, sparks drawn inward.
			for s: StringName in [&"hand_l", &"hand_r"]:
				FireCommon.ignite_limb(ctx, s, 0.8)
			FxFlash.spawn(ctx.caster, ctx.hands_pos(), FireCommon.HOT, 1.5, 0.25, 3.0)
			sound(&"ignite", ctx.hands_pos(), -6.0)
		&"release":
			ctx.face_dir = Vector3.ZERO
			var center := ctx.origin() + Vector3.UP * 1.0
			FireCommon.burst(ctx, center, float(param("radius", 3.8)), hit_data(), attack_id, def.id,
					{"inner": float(param("inner", 2.0)), "inner_hit": param("inner_hit", {}), "power": 1.0})
			for s: StringName in [&"hand_l", &"hand_r"]:
				var hp := ctx.socket_pos(s)
				var out := hp - ctx.origin()
				out.y = 0.0
				FireFx.muzzle(ctx.caster, hp, out.normalized() if out.length() > 0.05 else ctx.forward(), 1.2)
			FireCommon.practiced(ctx, def.id)
