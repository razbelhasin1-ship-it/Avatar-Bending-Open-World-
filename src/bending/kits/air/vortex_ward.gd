extends BendingAbility
## Vortex Ward (technique): both palms circle around the body and the wind closes
## into a spinning sphere (3.5 s, walkable). Enemy projectiles from ANY side that
## reach it are caught and whirled around the bender; anyone stepping within
## `reach` m is blown away (pulses every 0.35 s). When it ends (time, or pressing
## the technique again) the sphere bursts: a ring of wind knocks back everyone
## within `burst_radius` and every caught projectile is flung back at the nearest
## enemy (it now belongs to the bender). 35 % damage reduction + poise armor while up.

var ward: AirWardFx = null
var held: Array[BendingProjectile] = []
var bursted := false

var _pulse_t := 0.0
var _loop_id := 0
var _angle := 0.0
var _impulse := 0


func can_use() -> StringName:
	AirCommon.prepare()
	return &""


func begin() -> void:
	ctx.move_mode = BendingContext.Move.FREE
	ctx.move_speed_scale = float(param("walk_scale", 0.55))
	ctx.poise_armor = 30.0
	ctx.damage_reduction = 0.35
	play_clip(def.clip, {"blend_in": 0.1})
	clip_end = INF
	max_time = float(param("duration", 3.5)) + 1.5
	ward = AirWardFx.spawn(ctx.caster, ctx.caster, float(param("radius", 1.6)))
	_loop_id = Audio.start_bending_loop(ctx.element, &"shield_loop", ctx.caster, -3.0)
	sound(&"shield_up", ctx.origin() + Vector3.UP, 0.0)
	_impulse = AirWindField.add(ctx.caster, ctx.origin(), 3.2, 16.0, AirWindField.VORTEX, Vector3(-1, 0, 0), INF)
	AirEnv.practiced(ctx, def.id)


func on_repress() -> bool:
	if time > 0.3 and not bursted:
		_burst()
	return true


func update(delta: float) -> void:
	if bursted:
		if time >= clip_end:
			finish()
		return
	if AirCommon.airborne(ctx):
		AirCommon.hang(ctx, delta, -0.5)
	_angle += delta * 7.0
	_catch()
	_orbit(delta)
	if _impulse != 0:
		AirWindField.move(_impulse, ctx.origin())
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = float(param("pulse", 0.35))
		_repel()
	if time >= float(param("duration", 3.5)):
		_burst()


func _catch() -> void:
	var c := ctx.origin() + Vector3.UP * 0.95
	var r := float(param("radius", 1.6)) + 1.0
	for proj: BendingProjectile in BendingProjectile.live.duplicate():
		if not is_instance_valid(proj) or not proj.alive or proj.team == ctx.team or held.has(proj):
			continue
		if proj.global_position.distance_to(c) > r:
			continue
		# Caught: it now belongs to the ward (it cannot hit the bender any more).
		var speed := proj.velocity.length()
		proj.redirect(Vector3.UP, ctx.team, ctx.caster, 0.5)
		proj.set_meta(&"ward_speed", maxf(speed, 18.0))
		held.append(proj)
		AirFx.swirl(ctx.caster, proj.global_position, 0.35, 0.25, {"grow": 1.8, "spin": 20.0, "height": 0.1, "opacity": 0.6})


func _orbit(_delta: float) -> void:
	var c := ctx.origin() + Vector3.UP * 0.95
	var r := float(param("radius", 1.6)) * 0.95
	for i in range(held.size() - 1, -1, -1):
		var p := held[i]
		if not is_instance_valid(p) or not p.alive:
			held.remove_at(i)
			continue
		var a := _angle + TAU * float(i) / maxf(held.size(), 1)
		var want := c + Vector3(cos(a) * r, sin(a * 1.7) * 0.35, sin(a) * r)
		p.velocity = ((want - p.global_position) * 14.0).limit_length(30.0)
		p.age = 0.0
		p.traveled = 0.0


## Anyone stepping in close is blown away.
func _repel() -> void:
	new_attack()
	var c := ctx.origin() + Vector3.UP * 0.9
	var hit_r := float(param("reach", 2.4))
	var res := BendingHits.sphere(ctx, c, hit_r, hit_data(), attack_id, def.id, {"push": &"radial"})
	if not res.is_empty():
		AirFx.swirl(ctx.caster, c, hit_r * 0.6, 0.3, {"grow": 1.8, "spin": 20.0, "height": 0.4, "opacity": 0.6})


func _burst() -> void:
	if bursted:
		return
	bursted = true
	new_attack()
	var o := ctx.origin()
	var c := o + Vector3.UP * 0.9
	var br := float(param("burst_radius", 3.6))
	BendingHits.sphere(ctx, c, br, hit_data(param("burst_hit", {}) as Dictionary), attack_id, def.id, {"push": &"radial"})
	# Fling the caught projectiles back at the nearest enemies.
	var foes := BendingHits.targets_in_sphere(ctx, c, 24.0)
	for i in held.size():
		var p := held[i]
		if not is_instance_valid(p) or not p.alive:
			continue
		var dir := (p.global_position - c).normalized()
		if not foes.is_empty():
			var f := foes[i % foes.size()] as Node3D
			if f != null:
				dir = (BendingContext.target_point(f) - p.global_position).normalized()
		var spd := float(p.get_meta(&"ward_speed", 24.0)) * float(param("fling_speed_mult", 1.2))
		p.redirect(dir, ctx.team, ctx.caster, 1.0)
		p.velocity = dir * spd
	held.clear()
	if ward and is_instance_valid(ward):
		ward.burst(0.3)
	ward = null
	AirWaveFx.spawn(ctx.caster, ctx.ground_point(o), br, 0.24, {"height": 1.1})
	AirEnv.blow(ctx, ctx.ground_point(o), br, 1.1, {"mode": &"radial", "by": ctx.caster})
	sound(&"push", c, 1.0)
	if ctx.is_player():
		BendingFeedback.shake(0.25, 0.2)
	_end_loop()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.damage_reduction = 0.0
	clip_end = time + 0.3
	if ctx.rig and ctx.rig.current_action() == def.clip:
		ctx.rig.play_action(&"air_push_release", {"start": 0.25, "blend_in": 0.05})


func _end_loop() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.2)
		_loop_id = 0
	if _impulse != 0:
		AirWindField.release(_impulse)
		_impulse = 0


func _cleanup() -> void:
	_end_loop()
	if ward and is_instance_valid(ward):
		ward.burst(0.2)
	ward = null
	# Anything still held drops out of the whirl and flies off outward.
	var c := ctx.origin() + Vector3.UP * 0.9 if ctx.is_valid() else Vector3.ZERO
	for p in held:
		if is_instance_valid(p) and p.alive:
			p.velocity = (p.global_position - c).normalized() * float(p.get_meta(&"ward_speed", 20.0))
	held.clear()


func on_cancel(_reason: StringName) -> void:
	_cleanup()


func on_finish() -> void:
	_cleanup()
