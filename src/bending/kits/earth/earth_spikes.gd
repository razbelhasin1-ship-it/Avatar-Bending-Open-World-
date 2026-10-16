extends BendingAbility
## Earth Spikes (technique). Coil back, then lunge and drive both claws down
## into the ground: a line of stone spikes erupts from the bender's feet toward
## the target (12 m at 24 m/s), each spike launching what it hits
## (EarthSpikeLine: once per target, follows the ground, stops at ice / water /
## walls / steep steps, leaves a fissure). Spikes from the ground cannot be
## blocked - sidestep the line.

var info: Dictionary = {}
var line: EarthSpikeLine = null
var _dir := Vector3.FORWARD


func can_use() -> StringName:
	EarthCommon.prepare()
	if not EarthEnv.grounded(ctx):
		return &"airborne"
	info = EarthEnv.material_at(ctx, ctx.origin() + ctx.aim_flat() * 1.2)
	if not bool(info["ok"]):
		return EarthEnv.refuse(ctx, def.id, info)
	return &""


func begin() -> void:
	_dir = _aim_dir()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = _dir
	ctx.face_rate = 1200.0
	ctx.poise_armor = maxf(ctx.base_poise_armor, def.poise_armor)
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})
	max_time = 3.0


func _aim_dir() -> Vector3:
	var t := ctx.aim_target()
	if t != null:
		var d := t.global_position - ctx.origin()
		d.y = 0.0
		if d.length() > 0.5:
			return d.normalized()
	return ctx.aim_flat()


func update(delta: float) -> void:
	if line == null and ctx.is_player():
		_dir = _aim_dir()
		ctx.face_dir = _dir
	super.update(delta)


func on_event(event: StringName) -> void:
	if event != &"release" or line != null:
		return
	ctx.face_dir = Vector3.ZERO
	var from := ctx.ground_point(ctx.origin() + _dir * float(param("start", 1.1)))
	var pw := EarthEnv.power(info)
	line = EarthSpikeLine.start(ctx, from, _dir, {"length": float(param("length", 12.0)) * lerpf(1.0, pw, 0.5), "speed": float(param("speed", 24.0)),
			"spacing": float(param("spacing", 0.6)), "radius": float(param("radius", 0.85)), "hit": EarthEnv.scaled_hit(hit_data(), info),
			"attack_id": attack_id, "ability_id": def.id, "kind": info["kind"], "power": pw, "hold": float(param("hold", 1.4))})
	var feet := ctx.ground_point(ctx.origin() + _dir * 0.5)
	EarthFx.tear_out(ctx.caster, feet, 0.6, info["kind"])
	sound(&"spikes", feet, 2.0)
	sound(&"stomp", feet, -4.0)
	EarthEnv.shake(ctx, feet, 0.3, 0.22)
	BendingFeedback.impulse(_dir, 0.15)
	EarthEnv.note_weak(ctx, info)
	EarthEnv.practiced(ctx, def.id)
