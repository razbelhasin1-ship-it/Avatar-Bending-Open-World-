extends BendingAbility
## Air Tornado (signature, 100 Focus). Sink and coil, two fast spins, both palms
## driven at the target: a tornado forms there (the clip's &"release"). While the
## palms stir it (1.6 s) it drifts after the target and pulses every 0.22 s:
## everyone within `pull_radius` is dragged toward the column (PULL), whoever
## reaches `capture_radius` is lifted (LAUNCH) and carried round the funnel, rising
## to `lift_top` m. When the palms are thrown to the sky (&"impact") the tornado
## bursts: every captured target (and anyone still in the column) is flung outward
## and up (26 dmg LAUNCH, unblockable). Enemy projectiles that touch the funnel are
## swallowed. Poise armor + 50 % damage reduction while casting. Grass, trees and
## cloth swirl around it, dust / snow / spray skirt, props are sucked in, fires out.
## Bodies that resist the lift (heavy, guarding) are only dragged.

var vortex: AirVortexFx = null
var center := Vector3.ZERO
var formed := false
var blown := false
var captured: Dictionary = {}

var _pulse_t := 0.0
var _env_t := 0.0
var _loop_id := 0
var _impulse := 0
var _form_t := 0.0
var _surface: StringName = &"stone"


func can_use() -> StringName:
	AirCommon.prepare()
	return &""


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 900.0
	ctx.poise_armor = def.poise_armor
	ctx.damage_reduction = float(param("damage_reduction", 0.5))
	if AirCommon.airborne(ctx):
		ctx.gravity_scale = 0.4
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.08})
	max_time = clip_end + 1.0
	center = _target_ground()
	# Telegraph: the reach of the pull, faint on the ground where the tornado will form.
	FxRing.spawn(ctx.caster, center, float(param("pull_radius", 7.5)), Color(0.85, 0.94, 1.0), 0.9, {"opacity": 0.3, "width": 0.08, "fill": 0.06})


func _target_ground() -> Vector3:
	var o := ctx.origin()
	var t := ctx.aim_target()
	var p: Vector3
	if t != null:
		p = t.global_position
	else:
		var a: Dictionary = ctx.aim()
		var pt: Vector3 = a.get("point", Vector3.INF)
		p = pt if pt.is_finite() and Vector2(pt.x - o.x, pt.z - o.z).length() > 2.5 else o + ctx.aim_flat() * float(param("distance", 6.0))
	var flat := p - o
	flat.y = 0.0
	var maxd := float(param("max_distance", 14.0))
	if flat.length() > maxd:
		p = o + flat.normalized() * maxd
	if flat.length() < 2.5:
		p = o + ctx.aim_flat() * 3.0
	return ctx.ground_point(p)


func on_event(event: StringName) -> void:
	match event:
		&"gather":
			AirFx.swirl(ctx.caster, ctx.origin() + Vector3.UP * 0.5, 1.0, 0.5, {"grow": 2.2, "spin": 16.0, "height": 0.3, "opacity": 0.6})
			sound(&"cast_heavy", ctx.origin(), -2.0)
		&"release":
			_form()
		&"impact":
			_blow()


func _form() -> void:
	if formed:
		return
	formed = true
	center = _target_ground()
	_surface = ctx.surface_at(center)
	vortex = AirVortexFx.spawn(ctx.caster, center, float(param("height", 9.0)), float(param("funnel_radius", 3.4)), _surface)
	vortex.power = 1.0
	_loop_id = Audio.start_bending_loop(ctx.element, &"special_loop", vortex, 0.0)
	_impulse = AirWindField.add(ctx.caster, center, float(param("pull_radius", 7.5)) + 2.0, 30.0, AirWindField.VORTEX, Vector3(1, 0, 0), INF)
	sound(&"push", center, 2.0)
	FxBurst.spawn(ctx.caster, &"dust_ring", center, {"color": FxLib.surface_color(_surface), "radius": 1.5, "count": 1.5})
	BendingFeedback.impulse(Vector3.UP, 0.25)
	if ctx.is_player():
		BendingFeedback.shake(0.3, 0.3)
	AirEnv.practiced(ctx, def.id)
	_pulse_t = 0.0
	_env_t = 0.0


func update(delta: float) -> void:
	if formed and not blown:
		_form_t += delta
		_drift(delta)
		_pulse_t -= delta
		if _pulse_t <= 0.0:
			_pulse_t = float(param("pulse", 0.22))
			_pulse()
		_steer(delta)
		_swallow()
		_env_t -= delta
		if _env_t <= 0.0:
			_env_t = 0.3
			AirEnv.blow(ctx, center, 4.5, 1.6, {"mode": &"vortex", "dir": Vector3(1, 0, 0), "plants": false, "by": ctx.caster})
			if _surface == &"grass":
				FxBurst.spawn(ctx.caster, &"leaves", center + Vector3.UP * 1.5, {"count": 0.8, "radius": 1.6})
			else:
				FxBurst.spawn(ctx.caster, &"dust", center + Vector3.UP * 0.3, {"color": FxLib.surface_color(_surface), "count": 0.7, "radius": 1.4})
	super.update(delta)


## The tornado walks after its target.
func _drift(delta: float) -> void:
	var t := ctx.aim_target()
	if t != null and is_instance_valid(t) and not captured.has(t.get_instance_id()):
		var to := t.global_position - center
		to.y = 0.0
		if to.length() > 0.3:
			center += to.normalized() * minf(to.length(), float(param("drift", 2.2)) * delta)
			center = ctx.ground_point(center)
	if vortex and is_instance_valid(vortex):
		vortex.global_position = center
	if _impulse != 0:
		AirWindField.move(_impulse, center)


func _pulse() -> void:
	var pull_r := float(param("pull_radius", 7.5))
	var cap_r := float(param("capture_radius", 2.4))
	var mid := center + Vector3.UP * 1.0
	var pull := hit_data()
	var lift := hit_data(param("lift_hit", {}) as Dictionary)
	new_attack()
	for t in BendingHits.targets_in_sphere(ctx, mid, pull_r):
		if not (t is Node3D) or not Combat.is_alive(t):
			continue
		var id := t.get_instance_id()
		var tp := BendingContext.target_point(t as Node3D)
		var flat := (t as Node3D).global_position - center
		flat.y = 0.0
		if captured.has(id) or not BendingHits.line_of_sight(ctx, mid, tp, t):
			continue
		var close := flat.length() <= cap_r
		var h := lift if close else pull
		var dir := -flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
		var hit := ctx.make_hit(h, dir, attack_id, def.id)
		hit.origin = center
		hit.position = tp
		hit.set_meta(&"no_hitstop", true)
		hit.set_meta(&"no_focus", true)
		var res := BendingHits.deliver(ctx, t, hit)
		if close and (res == Combat.Result.HIT or res == Combat.Result.KILLED) and t is CharacterBody3D and t.get("look") != &"post":
			captured[id] = {"node": t, "angle": atan2(flat.z, flat.x), "t": 0.0, "h0": (t as Node3D).global_position.y - center.y}


## Carries the captured round the funnel, rising.
func _steer(delta: float) -> void:
	var orbit_r := float(param("orbit_radius", 1.7))
	var spin := float(param("orbit_speed", 4.2))
	var top := float(param("lift_top", 4.2))
	for id: int in captured.keys():
		var c: Dictionary = captured[id]
		var b := c["node"] as CharacterBody3D
		if b == null or not is_instance_valid(b) or not b.is_inside_tree() or not Combat.is_alive(b):
			captured.erase(id)
			continue
		c["t"] = float(c["t"]) + delta
		c["angle"] = float(c["angle"]) + spin * delta
		var a := float(c["angle"])
		var rise := clampf(float(c["t"]) / 1.2, 0.0, 1.0)
		var h := lerpf(maxf(float(c["h0"]), 0.6), top, rise * rise * (3.0 - 2.0 * rise))
		var want := center + Vector3(cos(a) * orbit_r, h, sin(a) * orbit_r)
		var to := want - b.global_position
		if to.length() > 6.0:
			captured.erase(id)
			continue
		var v := to * 7.0 + Vector3(-sin(a), 0.0, cos(a)) * orbit_r * spin * 0.6
		v = v.limit_length(16.0)
		v.y += 9.8 * delta
		b.velocity = v


## Enemy projectiles that touch the funnel are torn apart.
func _swallow() -> void:
	var r := float(param("funnel_radius", 3.4)) * 0.6
	for proj: BendingProjectile in BendingProjectile.live.duplicate():
		if not is_instance_valid(proj) or not proj.alive or proj.team == ctx.team:
			continue
		var d := proj.global_position - center
		if d.y < -0.5 or d.y > float(param("height", 9.0)):
			continue
		if Vector2(d.x, d.z).length() < r + d.y * 0.18:
			proj.destroy(true)


## The palms rise: the tornado bursts and flings everyone out.
func _blow() -> void:
	if not formed or blown:
		return
	blown = true
	new_attack()
	var rel := hit_data(param("release_hit", {}) as Dictionary)
	var flung := {}
	for id: int in captured.keys():
		var c: Dictionary = captured[id]
		var b := c["node"] as Node3D
		if b != null and is_instance_valid(b):
			_fling(b, rel)
			flung[id] = true
	for t in BendingHits.targets_in_sphere(ctx, center + Vector3.UP * 1.5, float(param("capture_radius", 2.4)) + 0.8):
		if t is Node3D and not flung.has(t.get_instance_id()):
			_fling(t as Node3D, rel)
	captured.clear()
	if vortex and is_instance_valid(vortex):
		vortex.release(0.6)
	vortex = null
	if _impulse != 0:
		AirWindField.release(_impulse)
		_impulse = 0
	AirWaveFx.spawn(ctx.caster, center, 6.0, 0.35, {"height": 1.6})
	AirEnv.blow(ctx, center, 6.0, 1.8, {"mode": &"radial", "by": ctx.caster})
	FxFlash.spawn(ctx.caster, center + Vector3.UP * 2.0, Color(0.85, 0.94, 1.0), 2.0, 0.25, 9.0)
	sound(&"push", center + Vector3.UP, 4.0)
	sound(&"cast_heavy", center + Vector3.UP * 2.0, 2.0)
	_stop_loop(0.4)
	BendingFeedback.impulse(Vector3.UP, 0.35)
	if ctx.is_player():
		BendingFeedback.shake(0.5, 0.35)


func _fling(t: Node3D, h: Dictionary) -> void:
	var flat := t.global_position - center
	flat.y = 0.0
	var dir := flat.normalized() if flat.length() > 0.2 else Vector3(cos(randf() * TAU), 0.0, sin(randf() * TAU))
	var hit := ctx.make_hit(h, dir, attack_id, def.id)
	hit.origin = center
	hit.position = BendingContext.target_point(t)
	BendingHits.deliver(ctx, t, hit)


func _stop_loop(fade: float) -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, fade)
		_loop_id = 0


func _cleanup() -> void:
	if vortex and is_instance_valid(vortex):
		vortex.release(0.35)
	vortex = null
	if _impulse != 0:
		AirWindField.release(_impulse)
		_impulse = 0
	_stop_loop(0.3)
	captured.clear()


func on_cancel(_reason: StringName) -> void:
	_cleanup()


func on_finish() -> void:
	_cleanup()
