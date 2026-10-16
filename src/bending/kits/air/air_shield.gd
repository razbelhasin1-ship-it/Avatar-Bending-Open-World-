extends DefenseAbility
## Air Shield: a spinning current around the body. Blocks 70% from the front,
## deflects projectiles aside; a perfect (parry) block redirects them back at
## the attacker and blows melee attackers away.

var _swirl: AirFx.AirSwirl = null


func on_guard_up() -> void:
	_swirl = AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.9, 0.95, 1.0, {"loop": true, "follow": ctx.caster, "spin": 11.0, "height": 1.1, "tilt": 0.25, "opacity": 0.7})
	AirFx.ground_puff(ctx.caster, ctx.ground_point(ctx.origin()), ctx.surface_at(ctx.origin()), 0.5)


func on_guard_down() -> void:
	if _swirl and is_instance_valid(_swirl):
		_swirl.stop(0.18)
	_swirl = null


func on_block(hit: HitInfo) -> void:
	AirFx.swirl(ctx.caster, hit.position, 0.4, 0.25, {"grow": 1.8, "spin": 20.0, "height": 0.1, "opacity": 0.6})


func counter(hit: HitInfo, attacker: Node3D) -> void:
	# Burst of wind: blows the attacker away (projectiles are redirected by the base).
	AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.9, 1.2, 0.4, {"grow": 2.2, "spin": 22.0, "height": 0.8})
	if attacker != null and is_instance_valid(attacker) and not hit.is_projectile:
		var h := ctx.make_hit({"damage": 4.0, "reaction": HitInfo.Reaction.KNOCKBACK, "force": 12.0, "lift": 2.0, "poise": 40.0},
				attacker.global_position - ctx.origin(), 0, def.id)
		BendingHits.deliver(ctx, attacker, h)
