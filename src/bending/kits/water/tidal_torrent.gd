extends BendingAbility
## Tidal Torrent (signature, 100 Focus): the bender sinks and calls the water
## of the whole area in (thick streams from the source / snow / the canteen),
## rises on a column of water at the heart of a huge spiralling vortex that
## pulls enemies in (repeated PULL pulses, the closest are swept up and
## launched), swallows incoming enemy projectiles and douses fires - then rears
## back and drives the whole vortex outward: an expanding ring wave that knocks
## everyone around down plus a towering wave crest rolling forward.
## Events: gather (water converges), rise (vortex + column), release (the crash).
## Heavy poise armor and 50 % damage reduction while it runs.

var _src: Dictionary = {}
var _size := 1.0
var vortex: WaterVortexFx = null
var phase := 0  # 0 gather, 1 vortex, 2 crashed
var _vortex_t := 0.0
var _pulse_t := 0.0
var pulses := 0
var pulled: Array[Node] = []
var launched: Array[Node] = []
var swallowed := 0
var ring: WaterWaveRunner = null
var wave: WaterWaveRunner = null
var _launch_attack := 0
var _ground_y := 0.0
var _loop_id := 0


func chi_cost() -> float:
	return 0.0


func can_use() -> StringName:
	return &"" if WaterCommon.grounded(ctx) else &"airborne"


func begin() -> void:
	WaterCommon.prepare()
	_src = WaterSource.find(ctx)
	_size = WaterSource.size_mult(ctx)
	ctx.move_mode = BendingContext.Move.HOLD
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 360.0
	ctx.poise_armor = 999.0
	ctx.damage_reduction = float(param("damage_reduction", 0.5))
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.1})
	max_time = 6.0
	_ground_y = ctx.origin().y
	_launch_attack = HitInfo.new_attack_id()
	sound(&"draw", ctx.origin(), 0.0)
	if ctx.is_player():
		BendingFeedback.shake(0.15, 0.4)


func _vortex_center() -> Vector3:
	return Vector3(ctx.origin().x, _ground_y, ctx.origin().z)


func on_event(event: StringName) -> void:
	match event:
		&"gather":
			var c := ctx
			var gy := _ground_y
			WaterCommon.pull(ctx, _src, func() -> Vector3: return Vector3(c.origin().x, gy + 0.6, c.origin().z) if c.is_valid() else Vector3.ZERO,
					maxf(time_to_event(&"rise"), 0.2), 0.24 * _size, 3)
			# Water converges from all around, not just the source.
			for i in 3:
				var a := TAU * float(i) / 3.0 + randf() * 0.6
				var p := ctx.origin() + Vector3(cos(a), 0, sin(a)) * 5.0
				p.y = WaterEnv.surface_y(ctx, p + Vector3.UP, 1.5, 4.0)
				WaterFx.pull(ctx.caster, p, func() -> Vector3: return Vector3(c.origin().x, gy + 0.8, c.origin().z) if c.is_valid() else Vector3.ZERO,
						maxf(time_to_event(&"rise"), 0.2) * 1.1, {"radius": 0.14 * _size, "kind": &"snow" if GroundSampler.surface(p) == &"snow" else &"water"})
			sound(&"surge", ctx.origin(), 2.0)
		&"rise":
			phase = 1
			_vortex_t = 0.0
			vortex = WaterVortexFx.spawn(ctx.caster, _vortex_center(), float(param("vortex_radius", 3.6)) * _size, float(param("vortex_height", 6.0)) * _size)
			_loop_id = Audio.start_bending_loop(ctx.element, &"special_loop", ctx.caster, 0.0)
			FxRing.spawn(ctx.caster, _vortex_center(), 4.0, Color(0.75, 0.92, 1.0), 0.6, {"opacity": 0.7, "fill": 0.3})
			WaterEnv.splash_ground(ctx.caster, _vortex_center(), 1.6)
			ctx.gravity_scale = 0.0
		&"release":
			_crash()


func update(delta: float) -> void:
	if phase == 0:
		ctx.face_dir = ctx.aim_flat()
	elif phase == 1:
		_vortex_t += delta
		var power := clampf(_vortex_t / 0.5, 0.0, 1.0)
		var lift := float(param("lift", 1.3)) * power
		WaterCommon.hold_height(ctx, _ground_y + lift, 8.0)
		if vortex != null and is_instance_valid(vortex):
			vortex.tick(_vortex_center(), power, ctx.origin().y - _ground_y, delta)
		ctx.face_dir = ctx.aim_flat()
		_pulse_t -= delta
		if _pulse_t <= 0.0:
			_pulse_t = float(param("pulse", 0.25))
			_pulse(power)
		_swallow()
	elif phase == 2:
		# Come back down off the column.
		if ctx.origin().y > _ground_y + 0.05:
			WaterCommon.hold_height(ctx, _ground_y, 7.0)
		else:
			ctx.gravity_scale = 1.0
	if time >= clip_end:
		finish()


func _pulse(power: float) -> void:
	pulses += 1
	var center := _vortex_center()
	var r := float(param("pull_radius", 9.0)) * lerpf(0.8, 1.0, _size)
	var pull_hit := {"damage": 3.0, "reaction": HitInfo.Reaction.PULL, "force": 6.0 + 3.0 * power, "stun": 0.35, "poise": 12.0,
			"status": {"soaked": 6.0}}
	var aid := HitInfo.new_attack_id()
	for t in BendingHits.targets_in_sphere(ctx, center + Vector3.UP * 1.0, r):
		if not (t is Node3D) or t is BendingConstruct:
			continue
		var tn := t as Node3D
		var flat := Vector2(tn.global_position.x - center.x, tn.global_position.z - center.z).length()
		if flat <= float(param("launch_radius", 3.4)) and not launched.has(tn):
			var lh := ctx.make_hit({"damage": 6.0, "reaction": HitInfo.Reaction.LAUNCH, "lift": 5.5, "force": 2.0, "poise": 40.0,
					"status": {"soaked": 6.0}}, tn.global_position - center, _launch_attack, def.id)
			lh.origin = center
			if BendingHits.deliver(ctx, tn, lh) != Combat.Result.IGNORED:
				launched.append(tn)
			continue
		var h := ctx.make_hit(pull_hit, center - tn.global_position, aid, def.id)
		h.origin = center
		h.position = BendingContext.target_point(tn)
		var res := BendingHits.deliver(ctx, tn, h)
		if (res == Combat.Result.HIT or res == Combat.Result.KILLED) and not pulled.has(tn):
			pulled.append(tn)
	WaterEnv.extinguish(ctx, center + Vector3.UP, r)
	if ctx.is_player():
		BendingFeedback.shake(0.1 + 0.08 * power, 0.12)


## Enemy projectiles entering the vortex are swallowed by the water.
func _swallow() -> void:
	var center := _vortex_center() + Vector3.UP * 1.5
	var r := float(param("vortex_radius", 3.6)) * _size + 0.8
	for p in BendingProjectile.incoming(center, r, ctx.team):
		IceFx.splash(ctx.caster, p.global_position, 0.6)
		p.destroy(false)
		swallowed += 1


func _crash() -> void:
	if phase == 2:
		return
	phase = 2
	ctx.damage_reduction = 0.0
	ctx.move_mode = BendingContext.Move.BRAKE
	_stop_loop()
	if vortex != null and is_instance_valid(vortex):
		vortex.collapse(0.5)
	vortex = null
	var center := _vortex_center()
	var dir := ctx.aim_flat()
	var crash_hit := hit_data()
	ring = WaterWaveRunner.ring(ctx, center, {"r0": 1.5, "r1": float(param("ring_radius", 10.0)) * _size, "speed": 17.0, "height": 1.6 * _size,
			"depth": 2.2, "hit": crash_hit, "attack_id": attack_id, "ability_id": def.id, "carry": 0.35})
	var wave_hit: Dictionary = param("wave_hit", {"damage": 20.0, "reaction": HitInfo.Reaction.LAUNCH, "force": 10.0, "lift": 6.0, "poise": 70.0,
			"heavy": true, "status": {"soaked": 8.0}})
	var start := center + dir * 1.8
	start.y = WaterEnv.surface_y(ctx, start + Vector3.UP, 1.5, 3.0)
	wave = WaterWaveRunner.launch(ctx, start, dir, {"speed": 16.0, "distance": float(param("wave_distance", 15.0)) * _size,
			"width": 7.0 * _size, "height": 2.8 * _size, "depth": 2.0, "hit": wave_hit, "ability_id": def.id, "carry": 0.5, "rise_time": 0.1})
	sound(&"special", center, 3.0)
	FxFlash.spawn(ctx.caster, center + Vector3.UP * 2.0, Color(0.55, 0.85, 1.0), 4.0, 0.4, 14.0)
	FxRing.spawn(ctx.caster, center, 8.0, Color(0.8, 0.94, 1.0), 0.7, {"opacity": 0.8, "fill": 0.25, "width": 0.2})
	BendingFeedback.impulse(dir, 0.5)
	if ctx.is_player():
		BendingFeedback.hitstop(0.1)
		BendingFeedback.shake(0.7, 0.45)
	WaterCommon.practiced(ctx, def)


func _stop_loop() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.3)
		_loop_id = 0


func _cleanup() -> void:
	_stop_loop()
	if vortex != null and is_instance_valid(vortex):
		vortex.collapse(0.3)
	vortex = null
	ctx.damage_reduction = 0.0


func on_cancel(_reason: StringName) -> void:
	_cleanup()


func on_finish() -> void:
	_cleanup()
