extends BendingAbility
## Wind Blade (advanced technique): a spinning crescent kick compresses the air
## into a thin crescent blade that flies 24 m at 40 m/s and slices through every
## enemy in its path (pierces; each target is hit once). The blade is its own hit
## volume: three spheres spread across its width travel together under one attack
## id. In the air the bender pops up into a front flip and an axe kick sends the
## blade down at an angle (it can strike enemies below). Grass under its path is
## flattened and torn, fires it passes are blown out.

var _air := false
var _fired := false


func can_use() -> StringName:
	AirCommon.prepare()
	return &""


func begin() -> void:
	_air = AirCommon.airborne(ctx)
	ctx.move_mode = BendingContext.Move.FREE if _air else BendingContext.Move.BRAKE
	ctx.move_speed_scale = 0.2
	ctx.brake_rate = 24.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1500.0
	ctx.poise_armor = 12.0
	var c: StringName = param("air_clip", def.clip) if _air else def.clip
	play_clip(c, {"speed": def.clip_speed, "blend_in": 0.05})
	if _air and ctx.body:
		ctx.body.velocity.y = maxf(ctx.body.velocity.y, float(param("air_lift", 2.5)))
	AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.9, 0.5, 0.3, {"grow": 1.6, "spin": 18.0, "height": 0.3, "opacity": 0.45})


func update(delta: float) -> void:
	if _air:
		AirCommon.hang(ctx, delta, 0.3 if not _fired else -1.0)
	if not _fired:
		ctx.face_dir = ctx.aim_flat()
	super.update(delta)


func on_event(event: StringName) -> void:
	if event != &"release" or _fired:
		return
	_fired = true
	ctx.face_dir = Vector3.ZERO
	var speed := float(param("speed", 40.0))
	var hw := float(param("half_width", 1.25))
	var from := ctx.origin() + Vector3.UP * (1.05 if not _air else 0.9) + ctx.forward() * 0.55
	var dir := ctx.aim_dir_from(from, speed, 0.5)
	if _air:
		dir.y = clampf(dir.y, -0.75, 0.1)
		if ctx.aim_target() == null:
			dir.y = minf(dir.y, -0.25)
	else:
		dir.y = clampf(dir.y, -0.15, 0.2)
	dir = dir.normalized()
	# Across the blade: horizontal for the ground kick, vertical-ish for the axe kick.
	var right := dir.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = ctx.right()
	var side := right if not _air else right.cross(dir).normalized()
	var h := hit_data()
	var fx := WindBladeFx.spawn(ctx.caster, hw, PI * 0.5 if _air else 0.0)
	var puffer := AirCommon.GustPuffer.new()
	puffer.ctx = ctx
	puffer.dir = dir
	puffer.power = 0.55
	puffer.radius = hw
	puffer.impulse = AirWindField.add(ctx.caster, from, hw + 0.8, 22.0, AirWindField.DIRECTIONAL, dir, INF)
	var finish_cb := func(v: Node3D) -> void:
		puffer.done(v)
		if v != null and is_instance_valid(v) and v.has_method("finish"):
			v.call("finish", 0.12)
	var impact_cb := func(proj: BendingProjectile, pos: Vector3, _n: Vector3, target: Node) -> void:
		if target == null and proj.is_inside_tree():
			AirEnv.blow(proj, pos, 1.6, 0.7, {"dir": proj.velocity.normalized(), "by": proj})
	var main := BendingProjectile.launch(ctx, from, dir, speed, h, {
		"radius": 0.42, "range": float(param("range", 24.0)), "pierce": true, "attack_id": attack_id, "ability_id": def.id,
		"impact_size": 0.8, "visual": fx, "on_step": puffer.step, "on_finish": finish_cb, "on_impact": impact_cb})
	main.set_meta(&"puffer", puffer)
	for s: float in [-1.0, 1.0]:
		BendingProjectile.launch(ctx, from + side * hw * 0.78 * s, dir, speed, h, {
			"radius": 0.36, "range": float(param("range", 24.0)), "pierce": true, "attack_id": attack_id, "ability_id": def.id,
			"impact_size": 0.4, "visual": null})
	sound(&"cast_heavy", from, 2.0)
	Audio.play_bending(ctx.element, &"dash", from, -2.0)
	AirEnv.practiced(ctx, def.id)
	BendingFeedback.impulse(dir, 0.12)
	if not _air:
		AirEnv.puff(ctx.caster, ctx.ground_point(ctx.origin()), ctx.surface_at(ctx.origin()), 0.6, (dir + Vector3.UP).normalized())
	if ctx.is_player():
		BendingFeedback.shake(0.14, 0.12)
