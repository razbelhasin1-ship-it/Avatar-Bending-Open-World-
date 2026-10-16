extends BendingAbility
## Flame Sweep (starter technique): a low spinning sweep kick; on its impact
## frame a wide wall of flame rolls outward along the ground in front. The
## wave is a growing cone: each target is hit once, when the wave reaches it.

func begin() -> void:
	FireCommon.begin()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1440.0
	ctx.poise_armor = 15.0
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})


func on_event(event: StringName) -> void:
	if event != &"impact":
		return
	ctx.face_dir = Vector3.ZERO
	var fwd := ctx.forward()
	var g := ctx.ground_point(ctx.origin())
	var range_m := float(param("range", 7.5))
	var wave_t := float(param("wave_time", 0.42))
	var half := float(param("half_angle", 62.0))
	var yaw_basis := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))
	var a := deg_to_rad(half)
	FireFx.arc(ctx.caster, Transform3D(yaw_basis, g + Vector3.UP * 0.03), -a, a, 0.8, wave_t,
			{"standing": true, "height": 1.25, "lean": 0.35, "hold": 0.15, "grow_to": range_m, "tail": 3.0, "tongues": 9.0})
	FireFx.burst(ctx.caster, g + fwd * 0.8 + Vector3.UP * 0.2, 1.2, fwd)
	FxFlash.spawn(ctx.caster, g + fwd * 2.0 + Vector3.UP * 0.6, Color(1.0, 0.55, 0.2), 4.0, wave_t + 0.2, 8.0)
	sound(&"cast_heavy", g + fwd, 2.0)
	if ctx.is_player():
		BendingFeedback.shake(0.25, 0.25)
	var wave := FlameWave.new()
	wave.ctx = ctx
	wave.origin = g + Vector3.UP * 0.6
	wave.dir = fwd
	wave.range_m = range_m
	wave.duration = wave_t
	wave.half_angle = half
	wave.h = hit_data()
	wave.attack_id = attack_id
	wave.ability_id = def.id
	FxLib.root(ctx.caster).add_child(wave)
	FireCommon.practiced(ctx, def.id)


## Expanding cone of fire: hits targets as the front reaches them, scorches the ground.
class FlameWave extends Node:
	var ctx: BendingContext
	var origin := Vector3.ZERO
	var dir := Vector3.FORWARD
	var range_m := 7.0
	var duration := 0.4
	var half_angle := 60.0
	var h: Dictionary = {}
	var attack_id := 0
	var ability_id: StringName = &""
	var t := 0.0
	var _next_mark := 1.5

	func _physics_process(delta: float) -> void:
		t += delta
		if ctx == null or not ctx.is_valid():
			queue_free()
			return
		var u := clampf(t / duration, 0.0, 1.0)
		var r := lerpf(0.8, range_m, 1.0 - pow(1.0 - u, 1.6))
		BendingHits.cone(ctx, origin, dir, r, half_angle, h, attack_id, ability_id, {"push": &"radial"})
		while r >= _next_mark:
			var side := Vector3(-dir.z, 0, dir.x)
			for k in [-0.6, 0.0, 0.6]:
				var p := origin + dir * _next_mark * cos(deg_to_rad(half_angle) * k) + side * _next_mark * sin(deg_to_rad(half_angle) * k)
				FxDecal.spawn(ctx.caster, ctx.ground_point(p), &"scorch", 0.6)
				# The wave front reaches the world: grass catches, snow steams, braziers light.
				var to := (p - origin)
				FireEnv.heat(ctx, p, 1.2, 0.7, {"mark": 0.9 if k == 0.0 else 0.0, "stretch": 2.0, "dir": to})
			_next_mark += 2.5
		if u >= 1.0:
			queue_free()
