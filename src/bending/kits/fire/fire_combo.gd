extends ComboAbility
## Fire Fist / Fire Kick (Northern Shaolin): jab, jab (fire darts snap from the
## fists), front kick (a rising crescent of flame where the leg cuts), roundhouse (a
## wide horizontal arc that knocks back and sets the target alight). Darts that miss
## scorch what they hit and light braziers; the arcs scorch the ground in front.


func begin() -> void:
	FireCommon.begin()
	super.begin()


func on_step_begin(_i: int, sd: Dictionary) -> void:
	# The striking limb ignites at the start of the strike.
	FireCommon.ignite_limb(ctx, StringName(sd.get("hand", &"hand_r")), 0.7)


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
	var speed := float(param("bolt_speed", 38.0))
	var dir := ctx.aim_dir_from(from, speed, 0.6)
	from += dir * 0.2
	var size := float(param("bolt_size", 0.2))
	var ball := FireFx.ball(ctx.caster, size, FxLib.tier() >= 2)
	var sctx := ctx
	var on_impact := func(_p: BendingProjectile, pos: Vector3, n: Vector3, target: Node) -> void:
		if target == null and sctx.is_valid():
			FireEnv.heat(sctx, pos, 0.5, 0.3, {"grass": false, "mark": 0.35, "normal": n, "glow": 0.6})
	BendingProjectile.launch(ctx, from, dir, speed, step_hit(), {"radius": 0.2, "range": float(param("bolt_range", 16.0)),
			"attack_id": attack_id, "ability_id": def.id, "visual": ball, "align": false, "homing": 40.0, "impact_size": 0.6,
			"on_impact": on_impact})
	FireFx.muzzle(ctx.caster, from, dir, 0.9)
	sound(&"cast_light", from, -2.0)


## Flame arc where the leg cut: `vertical` for the front kick (a rising crescent
## in front), horizontal for the roundhouse (sweeping from the right to the left).
func _arc(sd: Dictionary, radius: float, a0: float, a1: float, reach: float, half_angle: float, vertical: bool) -> void:
	var foot := ctx.socket_pos(StringName(sd.get("hand", &"foot_r")))
	var h := foot.y - ctx.origin().y
	var fwd := ctx.forward()
	var yaw_basis := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))
	var center := ctx.origin() + Vector3.UP * clampf(h, 0.5, 1.4)
	if vertical:
		yaw_basis = yaw_basis * Basis(Vector3.BACK, PI * 0.5)
		center = ctx.origin() + Vector3.UP * 0.95 + fwd * 0.15
	FireFx.arc(ctx.caster, Transform3D(yaw_basis, center), a0, a1, radius, 0.14, {"width": 0.5 if vertical else 0.6, "hold": 0.14})
	BendingHits.cone(ctx, ctx.origin() + Vector3.UP * 1.0, fwd, reach, half_angle, step_hit(), attack_id, def.id)
	sound(&"cast_light", center, 0.0 if step < 3 else 2.0)
	if step == 3:
		FxBurst.spawn(ctx.caster, &"embers", center + fwd * radius * 0.6, {"count": 1.2, "spread": 120.0})
		FxFlash.spawn(ctx.caster, center + fwd * 1.2, FireCommon.HOT, 2.5, 0.18, 6.0)
		FireEnv.heat(ctx, ctx.origin() + fwd * 2.2 + Vector3.UP * 0.3, 1.6, 0.5, {"grass": false, "mark": 0.0})
		FireCommon.shake(ctx, 0.12, 0.12)
