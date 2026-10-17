extends BendingAbility
## Inferno (signature, 100 Focus): sink and breathe in (&"gather": the fists flare, a
## faint ring on the ground marks the final reach), rise spinning twice inside a
## whirling column of fire (&"spin": FireVortexFx) that scorches everyone within 3 m on
## every &"pulse" (5 dmg + burn) and swallows incoming projectiles, then stomp into a
## horse stance and drive both palms out (&"release"): the column bursts into a towering
## ring of flame racing out to 11 m that LAUNCHES everything it reaches (34 dmg + burn).
## Hyper armor + 50 % damage reduction while it runs; jump the ring or hide behind a
## wall to avoid it.

var _vortex: FireVortexFx = null
var _loop_id := 0
var _light: FxFlash = null
var _ground := Vector3.ZERO
var _pulses := 0


func begin() -> void:
	FireCommon.begin()
	ctx.move_mode = BendingContext.Move.HOLD
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 720.0
	ctx.poise_armor = 999.0
	ctx.damage_reduction = float(param("damage_reduction", 0.5))
	max_time = 4.0
	_ground = ctx.ground_point(ctx.origin())
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})


func on_event(event: StringName) -> void:
	match event:
		&"gather":
			for s: StringName in [&"hand_l", &"hand_r"]:
				FireCommon.ignite_limb(ctx, s, 1.0)
			FxRing.spawn(ctx.caster, _ground + Vector3.UP * 0.04, float(param("ring_radius", 11.0)), Color(1.0, 0.45, 0.15), 1.25,
					{"opacity": 0.28, "width": 0.18, "fill": 0.0})
			sound(&"ignite", ctx.hands_pos(), 0.0)
			_light = FxFlash.attach(ctx.caster, ctx.caster, FireCommon.HOT, 2.0, 7.0)
		&"spin":
			_ground = ctx.ground_point(ctx.origin())
			_vortex = FireVortexFx.spawn(ctx.caster, _ground, float(param("vortex_radius", 3.0)), float(param("vortex_height", 4.5)))
			_loop_id = Audio.start_bending_loop(ctx.element, &"special_loop", ctx.caster, 0.0, 0.1)
			HeatShimmer.spawn(ctx.caster, _ground, 5.0, 4.5, 1.2, 1.0)
			FireEnv.heat(ctx, _ground + Vector3.UP * 0.3, 2.6, 1.0, {"mark": 1.8})
			FireCommon.shake(ctx, 0.18, 0.4)
		&"pulse":
			_pulses += 1
			var c := ctx.origin() + Vector3.UP * 1.0
			BendingHits.sphere(ctx, c, float(param("vortex_radius", 3.0)), hit_data(param("vortex_hit", {})), new_attack(), def.id, {"push": &"radial"})
			FireCommon.burn_projectiles(ctx, c, float(param("vortex_radius", 3.0)) + 1.0)
			FxBurst.spawn(ctx.caster, &"embers", c, {"count": 0.8, "speed": 1.6, "spread": 180.0})
		&"release":
			_release()


func _release() -> void:
	ctx.face_dir = Vector3.ZERO
	if _vortex != null and is_instance_valid(_vortex):
		_vortex.release()
	_vortex = null
	_stop_loop()
	_ground = ctx.ground_point(ctx.origin())
	var aid := new_attack()
	FireRingWave.start(ctx, _ground, float(param("ring_radius", 11.0)), float(param("ring_time", 0.55)), hit_data(), aid, def.id,
			{"height": float(param("ring_height", 2.2)), "clearance": float(param("clearance", 1.8)), "r0": 1.6, "lean": 0.35, "power": 2.0, "hold": 0.3})
	var c := ctx.origin() + Vector3.UP * 1.0
	FxBurst.spawn(ctx.caster, &"flame", c, {"size": 1.8, "count": 1.8, "speed": 3.0, "radius": 1.2, "spread": 180.0})
	FxBurst.spawn(ctx.caster, &"smoke", _ground + Vector3.UP * 0.8, {"size": 1.6, "count": 1.2, "radius": 2.0})
	FxBurst.spawn(ctx.caster, &"sparks", c, {"count": 1.6, "speed": 1.8, "spread": 180.0})
	FxFlash.spawn(ctx.caster, c, FireCommon.HOT, 8.0, 0.6, 18.0)
	HeatShimmer.spawn(ctx.caster, _ground, 9.0, 3.5, 1.0, 1.0)
	BendingFeedback.sound(ctx.element, &"explosion", c, 4.0)
	sound(&"special", c, 3.0)
	FireCommon.shake(ctx, 0.55, 0.45)
	BendingFeedback.impulse(Vector3.UP, 0.25)
	FireCommon.practiced(ctx, def.id)
	if _light != null and is_instance_valid(_light):
		_light.fade_out(0.6)
	_light = null


func update(_delta: float) -> void:
	if _light != null and is_instance_valid(_light):
		_light.set_energy(1.2 + 0.4 * sin(time * 20.0) + 0.4 * float(_pulses))
	if time >= clip_end:
		finish()


func _stop_loop() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.25)
		_loop_id = 0


func on_cancel(_reason: StringName) -> void:
	_cleanup()


func on_finish() -> void:
	_cleanup()


func _cleanup() -> void:
	_stop_loop()
	if _vortex != null and is_instance_valid(_vortex):
		_vortex.release()
	_vortex = null
	if _light != null and is_instance_valid(_light):
		_light.fade_out(0.3)
	_light = null
