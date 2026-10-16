extends DodgeAbility
## Air Dash: a long wind-assisted dash (7 m, 0.32 s i-frames), usable in the
## air (twice per jump: params.air_dashes, refilled on landing). Leaves a wind
## trail, kicks up the ground at the start and pushes the grass along its path.
## Perfect dodge (a hit inside the first 0.2 s): the gust left behind knocks the
## attacker back (evasive counter, no Focus).

var _trail_timer := 0.0
var _impulse := 0


func can_use() -> StringName:
	AirCommon.prepare()
	var why := super.can_use()
	if why != &"":
		return why
	if AirCommon.airborne(ctx):
		var used := int(ctx.caster.get_meta(&"air_dashes_used", 0))
		if used >= int(param("air_dashes", 2)):
			return &"air_dashes"
	return &""


func on_dodge_start() -> void:
	if in_air:
		ctx.caster.set_meta(&"air_dashes_used", int(ctx.caster.get_meta(&"air_dashes_used", 0)) + 1)
	else:
		ctx.caster.set_meta(&"air_dashes_used", 0)
	var back := -dir
	var xf := Transform3D(Basis.looking_at(back, Vector3.UP), ctx.origin() + Vector3.UP * 0.9 + dir * 0.4)
	AirFx.gust(ctx.caster, xf, 3.5, 0.55, 0.3, {"opacity": 0.7, "tail": 0.8})
	if not in_air:
		AirFx.ground_puff(ctx.caster, ctx.ground_point(ctx.origin()), ctx.surface_at(ctx.origin()), 0.7, (back + Vector3.UP).normalized())
		_impulse = AirWindField.add(ctx.caster, ctx.origin(), 2.2, 16.0, AirWindField.DIRECTIONAL, dir, INF)
	else:
		AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.6, 0.6, 0.3, {"grow": 1.8, "spin": 16.0, "height": 0.1, "opacity": 0.6})


func on_dodge_tick(delta: float) -> void:
	# Landing refills the air dashes.
	if ctx.body != null and ctx.body.is_on_floor() and time > 0.05:
		ctx.caster.set_meta(&"air_dashes_used", 0)
	if _impulse != 0:
		AirWindField.move(_impulse, ctx.origin(), dir)
	_trail_timer -= delta
	if _trail_timer <= 0.0 and time < duration:
		_trail_timer = 0.09
		var xf := Transform3D(Basis.looking_at(-dir, Vector3.UP), ctx.origin() + Vector3.UP * 1.0)
		AirFx.gust(ctx.caster, xf, 1.8, 0.35, 0.22, {"opacity": 0.45, "tail": 0.9})


func on_dodge_end() -> void:
	if _impulse != 0:
		AirWindField.release(_impulse)
		_impulse = 0


func on_perfect_dodge(hit: HitInfo) -> void:
	var attacker := hit.source as Node3D
	var at := ctx.origin() - dir * 1.2 + Vector3.UP * 0.9
	AirFx.swirl(ctx.caster, at, 0.8, 0.35, {"grow": 2.2, "spin": 22.0, "height": 0.6, "opacity": 0.8})
	sound(&"push", at, -2.0)
	if attacker == null or not is_instance_valid(attacker) or hit.is_projectile:
		return
	if attacker.global_position.distance_to(at) > 3.6:
		return
	var h := ctx.make_hit(param("perfect_hit", {}) as Dictionary, attacker.global_position - at, HitInfo.new_attack_id(), def.id)
	h.origin = at
	ctx.no_focus = true
	BendingHits.deliver(ctx, attacker, h)
	ctx.no_focus = false
