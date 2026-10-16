extends ComboAbility
## Fire Fist / Fire Kick: jab-jab (fire bolts from the fists), kick (a flame
## arc sweeps where the leg cuts), roundhouse (a wide arc that knocks back).


func on_step_begin(_i: int, sd: Dictionary) -> void:
	# The striking limb ignites at the start of the strike.
	var p := ctx.socket_pos(StringName(sd.get("hand", &"hand_r")))
	FxBurst.spawn(ctx.caster, &"flame", p, {"size": 0.35, "count": 0.35, "speed": 0.6})


func strike(_i: int, sd: Dictionary) -> void:
	match String(sd.get("kind", "bolt")):
		"bolt":
			_bolt(sd)
		"kick":
			_arc(sd, 1.15, -0.9, 1.3, 3.4, 60.0, true)
		"wave":
			_arc(sd, 2.4, 1.6, -1.5, 4.8, 82.0, false)


func _bolt(sd: Dictionary) -> void:
	var from := ctx.socket_pos(StringName(sd.get("hand", &"hand_r")))
	var speed := float(param("bolt_speed", 34.0))
	var dir := ctx.aim_dir_from(from, speed, 0.6)
	from += dir * 0.2
	var ball := FireFx.ball(ctx.caster, 0.17, FxLib.tier() >= 2)
	BendingProjectile.launch(ctx, from, dir, speed, step_hit(), {"radius": 0.2, "range": float(param("bolt_range", 15.0)),
			"attack_id": attack_id, "ability_id": def.id, "visual": ball, "align": false, "homing": 40.0, "impact_size": 0.6})
	FireFx.muzzle(ctx.caster, from, dir, 0.8)
	sound(&"cast_light", from, -2.0)


## Flame arc where the leg cut: `vertical` for the front kick (a rising crescent
## in front), horizontal for the roundhouse (sweeping from the right to the left).
func _arc(sd: Dictionary, radius: float, a0: float, a1: float, reach: float, half_angle: float, vertical: bool) -> void:
	var foot := ctx.socket_pos(StringName(sd.get("hand", &"foot_r")))
	var h := foot.y - ctx.origin().y
	var yaw_basis := Basis(Vector3.UP, atan2(-ctx.forward().x, -ctx.forward().z))
	var center := ctx.origin() + Vector3.UP * clampf(h, 0.5, 1.4)
	if vertical:
		yaw_basis = yaw_basis * Basis(Vector3.BACK, PI * 0.5)
		center = ctx.origin() + Vector3.UP * 0.95 + ctx.forward() * 0.15
	FireFx.arc(ctx.caster, Transform3D(yaw_basis, center), a0, a1, radius, 0.14, {"width": 0.5 if vertical else 0.6, "hold": 0.14})
	BendingHits.cone(ctx, ctx.origin() + Vector3.UP * 1.0, ctx.forward(), reach, half_angle, step_hit(), attack_id, def.id)
	sound(&"cast_light", center, 0.0 if step < 3 else 2.0)
	if step == 3:
		FxBurst.spawn(ctx.caster, &"embers", center + ctx.forward() * radius * 0.6, {"count": 1.2, "spread": 120.0})
		if ctx.is_player():
			BendingFeedback.shake(0.12, 0.12)
