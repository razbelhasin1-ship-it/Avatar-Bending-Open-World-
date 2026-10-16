extends BendingAbility
## Earth Stomp (starter technique). Knee to the chest, fists high - then the
## foot slams down into a deep horse stance and both fists hammer toward the
## ground: a shockwave ring rolls out over the ground (5 m in 0.28 s),
## staggering everyone on the ground as the front reaches them (EarthShockwave;
## jumping avoids it, walls stop it), stone shards burst up along the front
## (EarthWaveFx) and a cracked crater stays under the bender.
## Needs earth under the feet (EarthEnv); weaker on sand / snow / mud.

var info: Dictionary = {}
var wave: EarthShockwave = null


func can_use() -> StringName:
	EarthCommon.prepare()
	if not EarthEnv.grounded(ctx):
		return &"airborne"
	info = EarthEnv.feet(ctx)
	if not bool(info["ok"]):
		return EarthEnv.refuse(ctx, def.id, info)
	return &""


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 36.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 900.0
	ctx.poise_armor = maxf(ctx.base_poise_armor, def.poise_armor)
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})
	max_time = 3.0


func on_event(event: StringName) -> void:
	if event != &"impact" or wave != null:
		return
	ctx.face_dir = Vector3.ZERO
	var g := EarthEnv.ground(ctx, ctx.origin() + ctx.forward() * 0.25)
	var gp: Vector3 = g["point"]
	var kind: StringName = info["kind"]
	var pw := EarthEnv.power(info)
	var radius := float(param("radius", 5.0)) * lerpf(1.0, pw, 0.6)
	var dur := float(param("wave_time", 0.28))
	wave = EarthShockwave.start(ctx, gp, radius, dur, EarthEnv.scaled_hit(hit_data(), info), attack_id, def.id,
			{"clearance": float(param("clearance", 1.2))})
	EarthWaveFx.spawn(ctx.caster, gp, radius, dur, kind, EarthEnv.ground_fn(ctx),
			{"rings": 3, "per_ring": int(param("shards", 9)), "height": 0.8 * pw, "inner": 0.35})
	FxRing.spawn(ctx.caster, gp, radius, EarthPalette.color(kind, "dust"), dur + 0.2, {"opacity": 0.6, "width": 0.14, "fill": 0.25,
			"inner": EarthPalette.color(kind, "rock")})
	FxBurst.spawn(ctx.caster, &"dust_ring", gp, {"color": EarthPalette.color(kind, "dust"), "radius": 1.2, "count": 1.6})
	FxDebris.spawn(ctx.caster, gp, {"count": 8, "size": 0.13, "up": 4.5, "out": 3.0, "ground_y": gp.y, "color": EarthPalette.color(kind, "debris")})
	EarthEnv.crater(ctx, gp, float(param("crater", 1.5)), kind)
	sound(&"stomp", gp, 2.0)
	sound(&"debris", gp, -4.0)
	EarthEnv.shake(ctx, gp, 0.42, 0.3)
	BendingFeedback.impulse(Vector3.DOWN, 0.25)
	EarthEnv.note_weak(ctx, info)
	EarthEnv.practiced(ctx, def.id)


## Targets the shockwave reached and hit (tests / AI).
func hits() -> int:
	if wave == null or not is_instance_valid(wave):
		return 0
	return BendingHits.count_landed(wave.hit_log.map(func(e: Array) -> Dictionary: return {"result": e[1]}))
