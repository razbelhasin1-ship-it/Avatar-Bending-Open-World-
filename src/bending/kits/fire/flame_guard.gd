extends DefenseAbility
## Flame Guard: a flare of fire in front (burns incoming projectiles away),
## then burning forearms crossed high while held (75% frontal block).
## Perfect timing: Fire Burst counter, a point-blank explosion that knocks
## the attacker down.

var _flame_t := 0.0


func on_guard_up() -> void:
	_flare(1.0)
	BendingFeedback.sound(ctx.element, &"ignite", ctx.hands_pos())


func _flare(k: float) -> void:
	var yaw_basis := Basis(Vector3.UP, atan2(-ctx.forward().x, -ctx.forward().z))
	FireFx.arc(ctx.caster, Transform3D(yaw_basis, ctx.ground_point(ctx.origin()) + Vector3.UP * 0.05), -0.9, 0.9, 0.95,
			0.12, {"standing": true, "height": 1.6 * k, "lean": 0.15, "hold": 0.25, "tongues": 7.0})
	FxFlash.spawn(ctx.caster, ctx.hands_pos() + ctx.forward() * 0.6, Color(1.0, 0.6, 0.25), 2.5 * k, 0.3, 5.0)


func on_guard(delta: float) -> void:
	_flame_t -= delta
	if _flame_t <= 0.0:
		_flame_t = 0.11
		for s: StringName in [&"hand_l", &"hand_r"]:
			FxBurst.spawn(ctx.caster, &"flame", ctx.socket_pos(s), {"size": 0.32, "count": 0.3, "speed": 0.5})


func on_block(hit: HitInfo) -> void:
	FireFx.burst(ctx.caster, hit.position, 0.6, -hit.direction)


func counter(_hit: HitInfo, attacker: Node3D) -> void:
	# Fire Burst: explosion around the bender.
	var c := ctx.origin() + Vector3.UP * 1.0
	FireFx.explosion(ctx.caster, c + ctx.forward() * 0.8, 3.0, ctx.ground_y(c))
	BendingFeedback.sound(ctx.element, &"explosion", c, 2.0)
	BendingHits.sphere(ctx, c, 3.2, {"damage": 12.0, "reaction": HitInfo.Reaction.KNOCKDOWN, "force": 9.0, "lift": 3.0, "poise": 60.0, "heavy": true,
			"status": {"burn": 3.0}}, HitInfo.new_attack_id(), def.id, {"push": &"radial"})
	if attacker == null:
		pass
