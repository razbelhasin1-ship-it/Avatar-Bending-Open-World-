extends BendingAbility
## Water Wave (unlock): hold to raise a wave under the feet and RIDE it - a
## surf stance on a moving mound of water that carries the bender fast over
## ground or open water (steered by the move stick, or the aim), bowling
## enemies aside (each hit once, knocked back and soaked). Releasing (or the
## max ride time / chi running dry) crashes the wave forward as a short
## surge (knockdown). Over water the bender lands on an ice floe frozen out
## of the surface, so the ride never ends in a swim.
## Clips: water_wave_ride (loop) -> water_wave_crash (event &"release").

const RIDE_LIFT := 0.75

var _src: Dictionary = {}
var _size := 1.0
var riding := true
var ride_time := 0.0
var dir := Vector3.FORWARD
var crest: WaterWaveFx = null
var ride_hits: Array[Dictionary] = []
var crash_runner: WaterWaveRunner = null
var floe: IceFloe = null
var _ride_attack := 0
var _trail := 0.0
var _douse := 0.0
var _released := false


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func begin() -> void:
	WaterCommon.prepare()
	_src = WaterSource.find(ctx)
	_size = WaterSource.size_mult(ctx)
	dir = ctx.aim_flat()
	ctx.move_mode = BendingContext.Move.DRIVE
	ctx.move_velocity = dir * float(param("speed", 12.0)) * 0.3
	ctx.gravity_scale = 0.0
	ctx.face_dir = dir
	ctx.face_rate = 600.0
	ctx.poise_armor = def.poise_armor
	play_clip(&"water_wave_ride", {"blend_in": 0.12})
	clip_end = INF
	max_time = float(param("max_ride", 2.6)) + 2.0
	_ride_attack = HitInfo.new_attack_id()
	crest = WaterWaveFx.spawn(ctx.caster, 1.5, 1.6 * _size, 1.0, 1.6, {"rise_time": 0.18})
	_place_crest()
	ctx.set_upkeep(float(param("upkeep", 9.0)))
	var g := ctx.ground_point(ctx.origin())
	WaterEnv.splash_ground(ctx.caster, g, 1.0)
	WaterCommon.pull(ctx, _src, func() -> Vector3: return g + Vector3.UP * 0.2, 0.25, 0.16 * _size, 2)
	sound(&"surge", ctx.origin(), -2.0)
	_loop_start()


var _loop_id := 0


func _loop_start() -> void:
	_loop_id = Audio.start_bending_loop(ctx.element, &"special_loop", ctx.caster, -6.0)


func _surface_under(p: Vector3) -> float:
	return WaterEnv.surface_y(ctx, p + Vector3.UP * 1.6, 0.6, 4.0)


func update(delta: float) -> void:
	if riding:
		ride_time += delta
		var speed := float(param("speed", 12.0)) * lerpf(0.85, 1.0, _size)
		# Steer toward the stick (or the aim when the stick is idle).
		var want := ctx.move_input
		want.y = 0.0
		if want.length() < 0.2:
			want = ctx.aim_flat()
		var ang := Vector2(dir.x, dir.z).angle_to(Vector2(want.x, want.z))
		var turn := deg_to_rad(float(param("turn_rate", 110.0))) * delta
		dir = dir.rotated(Vector3.UP, -clampf(ang, -turn, turn)).normalized()
		var ramp := clampf(ride_time / 0.25, 0.3, 1.0)
		ctx.move_mode = BendingContext.Move.DRIVE
		ctx.move_velocity = dir * speed * ramp
		ctx.face_dir = dir
		# Ride on top of the mound: the feet RIDE_LIFT above the ground / water.
		var ahead := ctx.origin() + dir * 0.6
		WaterCommon.hold_height(ctx, _surface_under(ahead) + RIDE_LIFT * clampf(ride_time / 0.2, 0.0, 1.0), 12.0)
		_place_crest()
		_ride_hits()
		_trail -= delta
		if _trail <= 0.0:
			_trail = 0.09
			var g := ctx.origin() - dir * 0.9
			g.y = _surface_under(g)
			WaterEnv.splash_ground(ctx.caster, g, 0.45, (-dir + Vector3.UP).normalized())
		_douse -= delta
		if _douse <= 0.0:
			_douse = 0.12
			WaterEnv.extinguish(ctx, ctx.origin() + dir * 1.0, 1.8)
		var max_ride := float(param("max_ride", 2.6))
		var min_ride := float(param("min_ride", 0.45))
		if (not input_held and ride_time >= min_ride) or ride_time >= max_ride or ctx.chi() <= 0.5:
			_crash()
		return
	# Crash: settle back down to the surface, then the clip ends.
	var gy := _surface_under(ctx.origin())
	if floe != null and is_instance_valid(floe):
		gy = maxf(gy, floe.top_y())
	if ctx.origin().y > gy + 0.05:
		WaterCommon.hold_height(ctx, gy, 8.0)
	else:
		ctx.gravity_scale = 1.0
	if time >= clip_end:
		finish()


func _place_crest() -> void:
	if crest == null or not is_instance_valid(crest):
		return
	var o := ctx.origin()
	var g := Vector3(o.x, _surface_under(o), o.z)
	# The mound sits under the feet; its crest just behind them, foam trailing back.
	var b := Basis.looking_at(dir, Vector3.UP)
	crest.place(Transform3D(b, g + dir * 0.35 - dir * crest.radius))
	crest.set_height_scale(clampf((o.y - g.y + 0.25) / maxf(crest.height, 0.1), 0.3, 1.4))


func _ride_hits() -> void:
	var front := ctx.origin() + dir * 0.9 + Vector3.UP * 0.6
	var h := hit_data(param("ride_hit", {}))
	var right := Vector3(-dir.z, 0.0, dir.x)
	for t in BendingHits.targets_in_sphere(ctx, front, 1.5):
		if not (t is Node3D) or BendingHits.already_hit(_ride_attack, t):
			continue
		var tn := t as Node3D
		var side := signf((tn.global_position - ctx.origin()).dot(right))
		var push := (dir + right * (side if side != 0.0 else 1.0) * 0.9).normalized()
		var hit := ctx.make_hit(h, push, _ride_attack, def.id)
		hit.origin = ctx.origin()
		hit.position = BendingContext.target_point(tn)
		var res := BendingHits.deliver(ctx, tn, hit)
		ride_hits.append({"target": tn, "result": res})


func _crash() -> void:
	riding = false
	ctx.set_upkeep(0.0)
	_stop_loop()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 18.0
	ctx.face_dir = dir
	ctx.face_rate = 900.0
	play_clip(&"water_wave_crash", {"blend_in": 0.06})
	if time_to_event(&"release") == INF:
		on_event(&"release")


func on_event(event: StringName) -> void:
	if event != &"release" or riding or _released:
		return
	_released = true
	if crest != null and is_instance_valid(crest):
		crest.crash(0.3)
	crest = null
	var start := ctx.origin() + dir * 1.2
	start.y = _surface_under(start)
	crash_runner = WaterWaveRunner.launch(ctx, start, dir, {"speed": 13.0, "distance": float(param("crash_distance", 5.0)),
			"width": 3.2 * _size, "height": 1.4 * _size, "hit": hit_data(), "attack_id": attack_id, "ability_id": def.id, "carry": 0.4})
	sound(&"special", start)
	# Over open water: freeze a floe to land on.
	if WaterEnv.is_over_water(ctx, ctx.origin()) and not IceFloe.supports(ctx.origin() + Vector3.DOWN * RIDE_LIFT):
		var p := ctx.origin()
		floe = WaterEnv.freeze_floe(ctx, p, 2.4, 12.0)
	if ctx.is_player():
		BendingFeedback.shake(0.25, 0.2)
	WaterCommon.practiced(ctx, def)


func _stop_loop() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.2)
		_loop_id = 0


func _cleanup() -> void:
	_stop_loop()
	ctx.set_upkeep(0.0)
	if crest != null and is_instance_valid(crest):
		crest.crash(0.25)
	crest = null
	if ctx.rig and ctx.rig.current_action() == &"water_wave_ride":
		ctx.rig.stop_action(0.2)


func on_cancel(_reason: StringName) -> void:
	_cleanup()
	# Never leave the bender stranded mid-air over the water.
	if ctx.is_valid() and WaterEnv.is_over_water(ctx, ctx.origin()) and floe == null:
		floe = WaterEnv.freeze_floe(ctx, ctx.origin(), 2.0, 8.0)


func on_finish() -> void:
	_cleanup()
