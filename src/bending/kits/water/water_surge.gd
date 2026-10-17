extends BendingAbility
## Water Surge (starter technique): the bender scoops low and heaves a large
## mass of water out of the nearest source (sea, lake, canal, fountain, or snow
## pulled up from the ground; the canteen without one: smaller, +30 % chi),
## circles it overhead on the back foot and, stepping in, drives it down into a
## crashing wave that rolls forward over ground or water (WaterWaveRunner):
## knocks back and soaks everything in its path, carries the targets it hits,
## puts out fires and douses fire projectiles.
## Events: gather (the mass gathers at the hands), release (the wave is thrown).

var _src: Dictionary = {}
var _size := 1.0
var _mass: WaterStream = null
var _mass_r := 0.2
var _released := false
var runner: WaterWaveRunner = null


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func can_use() -> StringName:
	return &"" if WaterCommon.grounded(ctx) else &"airborne"


func begin() -> void:
	WaterCommon.prepare()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 720.0
	ctx.poise_armor = def.poise_armor
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.08})
	_src = WaterSource.find(ctx)
	_size = WaterSource.size_mult(ctx)
	var t_gather := maxf(time_to_event(&"gather"), 0.15)
	WaterCommon.pull(ctx, _src, _mass_point, t_gather + 0.05, 0.17 * _size, 2 if _size >= 1.0 else 1)
	sound(&"surge", ctx.hands_pos(), -4.0)


## The gathered mass rides just above and in front of the hands.
func _mass_point() -> Vector3:
	if ctx == null or not ctx.is_valid():
		return Vector3.ZERO
	return ctx.hands_pos() + Vector3.UP * 0.3 + ctx.forward() * 0.6


func on_event(event: StringName) -> void:
	match event:
		&"gather":
			_mass_r = 0.32 * _size
			_mass = WaterFx.orb(ctx.caster, _mass_point, _mass_r)
			FxBurst.spawn(ctx.caster, &"spray", _mass_point(), {"count": 0.6, "size": 0.8})
		&"release":
			_release()


func update(delta: float) -> void:
	if not _released:
		ctx.face_dir = ctx.aim_flat()
		if _mass != null and is_instance_valid(_mass):
			# The mass swells while it circles overhead.
			_mass_r = minf(0.62 * _size, _mass_r + delta * 0.9 * _size)
			WaterFx.set_orb_radius(_mass, _mass_r)
	if time >= clip_end:
		finish()


func _release() -> void:
	_released = true
	ctx.face_dir = Vector3.ZERO
	_drop_mass(0.12)
	var dir := ctx.aim_flat()
	var start := ctx.origin() + dir * float(param("start_ahead", 1.6))
	start.y = WaterEnv.surface_y(ctx, start + Vector3.UP * 1.0, 1.6, 3.0)
	var h := hit_data()
	if _size < 1.0:
		h["damage"] = float(h.get("damage", 18.0)) * 0.8
		h["force"] = float(h.get("force", 9.0)) * 0.8
	runner = WaterWaveRunner.launch(ctx, start, dir, {"speed": float(param("speed", 14.0)), "distance": float(param("distance", 10.0)) * lerpf(0.75, 1.0, _size),
			"width": float(param("width", 4.0)) * _size, "height": float(param("height", 1.8)) * _size, "hit": h,
			"attack_id": attack_id, "ability_id": def.id, "carry": float(param("carry", 0.55))})
	# The mass hits the ground: splash at the hands' landing point.
	IceFx.splash(ctx.caster, start + Vector3.UP * 0.3, 1.1 * _size, (dir + Vector3.UP).normalized())
	WaterEnv.splash_ground(ctx.caster, start, 0.5)
	sound(&"special", start, 1.0)
	BendingFeedback.impulse(dir, 0.25)
	if ctx.is_player():
		BendingFeedback.shake(0.3, 0.25)
	WaterCommon.practiced(ctx, def)


func _drop_mass(fade: float) -> void:
	if _mass != null and is_instance_valid(_mass):
		_mass.finish(fade)
	_mass = null


func on_cancel(_reason: StringName) -> void:
	if _mass != null and is_instance_valid(_mass):
		# The held water falls when the bender is interrupted.
		WaterEnv.splash_ground(ctx.caster, ctx.ground_point(_mass_point()), 0.8)
	_drop_mass(0.15)


func on_finish() -> void:
	_drop_mass(0.15)
