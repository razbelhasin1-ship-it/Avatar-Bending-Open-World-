extends BendingAbility
## Water Jet (unlock): hold - palms stacked forward, a pressurised stream
## pours out of the hands (fed by a visible stream from the source behind)
## and follows the aim, so it can be swept. It pulses every params.pulse s: each
## pulse hits what the jet touches (a fresh attack, small damage, push along
## the stream, soak) - the first target stops the stream, walls splash it. It
## douses fires and fire projectiles along its length. Chi upkeep while held;
## max params.max_hold s. Without a source: shorter (x0.7) and +30 % chi.
## Clip: water_jet_open (hold), the stream starts on &"release".

var _src: Dictionary = {}
var _size := 1.0
var jetting := false
var jet_time := 0.0
var end_point := Vector3.ZERO
var pulses := 0
var landed := 0
var _jet: WaterStream = null
var _feed: WaterStream = null
var _pulse_t := 0.0
var _spray_t := 0.0
var _loop_id := 0
var _wobble := 0.0
var _stopped := false


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func begin() -> void:
	WaterCommon.prepare()
	_src = WaterSource.find(ctx)
	_size = WaterSource.size_mult(ctx)
	ctx.move_mode = BendingContext.Move.FREE
	ctx.move_speed_scale = float(param("walk_scale", 0.25))
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 540.0
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})
	clip_end = INF
	max_time = float(param("max_hold", 3.0)) + 2.0
	var c := ctx
	WaterCommon.pull(ctx, _src, func() -> Vector3: return c.hands_pos() if c.is_valid() else Vector3.ZERO, maxf(time_to_event(&"release"), 0.12), 0.1, 1)


func on_event(event: StringName) -> void:
	if event == &"release" and not jetting and not _stopped:
		jetting = true
		ctx.set_upkeep(float(param("upkeep", 16.0)))
		_jet = WaterStream.spawn(ctx.caster)
		_loop_id = Audio.start_bending_loop(ctx.element, &"shield_loop", ctx.caster, -4.0)
		if _loop_id != 0:
			Audio.set_loop_pitch(_loop_id, 1.35)
		sound(&"cast_heavy", ctx.hands_pos(), -2.0)
		var o := WaterCommon.origin(ctx, _src)
		if StringName(o["kind"]) == &"water" and (o["start"] as Vector3).distance_to(ctx.origin()) > 2.0:
			_feed = WaterStream.spawn(ctx.caster)
			_feed.set_meta(&"feed_start", o["start"])


func _from() -> Vector3:
	return ctx.hands_pos() + ctx.forward() * 0.28


func update(delta: float) -> void:
	if _stopped:
		if time >= clip_end:
			finish()
		return
	ctx.face_dir = ctx.aim_flat()
	if not jetting:
		# Waiting for the clip's release (a tap still pours for min_hold).
		return
	jet_time += delta
	var from := _from()
	var dir := ctx.aim_dir_from(from, 0.0)
	dir.y = clampf(dir.y, -0.45, 0.35)
	dir = dir.normalized()
	var reach := float(param("range", 12.0)) * lerpf(0.7, 1.0, _size)
	end_point = _trace(from, dir, reach)
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = float(param("pulse", 0.15))
		_pulse(from, dir)
	_update_visual(from, dir, delta)
	if (not input_held and jet_time >= float(param("min_hold", 0.35))) or jet_time >= float(param("max_hold", 3.0)) or ctx.chi() <= 0.5:
		_stop()


## Where the jet ends: the first target or wall along the stream.
func _trace(from: Vector3, dir: Vector3, reach: float) -> Vector3:
	var to := from + dir * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID | ctx.hit_mask())
	q.exclude = ctx.exclude()
	q.collide_with_areas = true
	var r := ctx.space().intersect_ray(q)
	if not r.is_empty():
		return r["position"]
	# Falls to the ground if it reaches that far.
	var g := ctx.ground_y(to, 1.0, 3.0)
	if to.y < g:
		return Vector3(to.x, g, to.z)
	return to


func _pulse(from: Vector3, dir: Vector3) -> void:
	pulses += 1
	new_attack()
	var h := hit_data()
	var res := BendingHits.sweep(ctx, from, end_point, float(param("radius", 0.3)) * lerpf(0.8, 1.0, _size), h, attack_id, def.id, {"push": &"forward"})
	var n := BendingHits.count_landed(res)
	landed += n
	for r: Dictionary in res:
		if int(r["result"]) == Combat.Result.HIT or int(r["result"]) == Combat.Result.KILLED:
			WaterCommon.carry(ctx, r["target"], Vector3(dir.x, 0.0, dir.z).normalized(), float(param("push_speed", 3.5)))
	# Douse along the stream.
	var length := from.distance_to(end_point)
	var k := 0.0
	while k <= length:
		WaterEnv.extinguish(ctx, from + dir * k, 1.0)
		k += 3.0
	if n == 0 and pulses % 2 == 0:
		BendingFeedback.world_impact(ctx.caster, ElementDefs.Element.WATER, end_point, -dir, 0.5)
	if n > 0 and ctx.is_player():
		BendingFeedback.shake(0.06, 0.06)
	if pulses == 1:
		WaterCommon.practiced(ctx, def)


func _update_visual(from: Vector3, dir: Vector3, delta: float) -> void:
	_wobble += delta * 30.0
	if _jet != null and is_instance_valid(_jet):
		var pts := PackedVector3Array()
		var n := 9
		var length := from.distance_to(end_point)
		var right := dir.cross(Vector3.UP).normalized()
		for i in n:
			var s := float(i) / (n - 1)
			# Pressurised: dead straight near the hands, a slight shiver and sag farther out.
			var sag := Vector3.DOWN * s * s * length * 0.03
			var shiver := right * sin(_wobble + s * 6.0) * 0.03 * s
			pts.append(from.lerp(end_point, s) + sag + shiver)
		_jet.set_points(pts, 0.11 * _size, 0.13 * _size)
		_jet.set_spray(true)
	if _feed != null and is_instance_valid(_feed):
		var st: Vector3 = _feed.get_meta(&"feed_start", from)
		var back := ctx.socket_pos(&"hand_r")
		var mid := st.lerp(back, 0.5) + Vector3.UP * (0.6 + st.distance_to(back) * 0.12)
		_feed.set_points(PackedVector3Array([st, st.lerp(mid, 0.5), mid, mid.lerp(back, 0.6), back]), 0.08, 0.06)
	_spray_t -= delta
	if _spray_t <= 0.0:
		_spray_t = 0.08
		FxBurst.spawn(ctx.caster, &"spray", end_point, {"count": 0.5, "size": 0.9, "dir": -dir})
		if randf() < 0.4:
			WaterEnv.splash_ground(ctx.caster, ctx.ground_point(end_point), 0.4)


func _stop() -> void:
	if _stopped:
		return
	_stopped = true
	jetting = false
	ctx.set_upkeep(0.0)
	_end_visuals()
	if ctx.rig and ctx.rig.current_action() == def.clip:
		ctx.rig.stop_action(0.18)
	clip_end = time + 0.2


func _end_visuals() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.15)
		_loop_id = 0
	if _jet != null and is_instance_valid(_jet):
		_jet.finish(0.18)
	_jet = null
	if _feed != null and is_instance_valid(_feed):
		_feed.finish(0.25)
	_feed = null


func on_cancel(_reason: StringName) -> void:
	_end_visuals()
	ctx.set_upkeep(0.0)


func on_finish() -> void:
	_end_visuals()
	ctx.set_upkeep(0.0)
	if ctx.rig and ctx.rig.current_action() == def.clip:
		ctx.rig.stop_action(0.18)
