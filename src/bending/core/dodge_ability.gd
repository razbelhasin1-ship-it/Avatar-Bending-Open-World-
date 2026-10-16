class_name DodgeAbility
extends BendingAbility
## Element dodge. Direction = move input (or backward without input), relative
## to the facing; distance / duration / i-frames / poise armor / in-air come
## from the caster's LocomotionProfile (design table) unless params override.
## params.clips: {"fwd": clip, "back": clip, "left": clip, "right": clip};
## params.cancel_strikes: strikes may cancel the dodge after this many seconds
## (Fire Step). Perfect dodge: a hit that lands inside the first
## PERFECT_WINDOW s of i-frames calls on_perfect_dodge(hit).

const PERFECT_WINDOW := 0.2

var dir := Vector3.FORWARD
var distance := 4.0
var duration := 0.35
var iframes := 0.25
var in_air := false
var perfect := false
var local_side: StringName = &"fwd"


func can_use() -> StringName:
	var prof := _profile()
	var air_ok := bool(param("in_air", prof.dodge_in_air if prof else false))
	if ctx.body != null and not ctx.body.is_on_floor() and not air_ok:
		return &"airborne"
	return &""


func _profile() -> LocomotionProfile:
	return LocomotionProfile.for_element(ctx.element)


func begin() -> void:
	var prof := _profile()
	distance = float(param("distance", prof.dodge_distance))
	duration = float(param("duration", prof.dodge_duration))
	iframes = float(param("iframes", prof.dodge_iframes))
	in_air = ctx.body != null and not ctx.body.is_on_floor()
	var mv := ctx.move_input
	mv.y = 0.0
	dir = mv.normalized() if mv.length() > 0.2 else -ctx.forward()
	var f := ctx.forward()
	var r := ctx.right()
	var lf := dir.dot(f)
	var lr := dir.dot(r)
	if absf(lf) >= absf(lr):
		local_side = &"fwd" if lf > 0.0 else &"back"
	else:
		local_side = &"right" if lr > 0.0 else &"left"
	var clips: Dictionary = param("clips", {})
	var c: StringName = clips.get(local_side, clips.get("fwd", &"dodge_roll"))
	var cl := AnimLibrary.get_clip(c)
	var speed := (cl.length / maxf(duration + float(param("recovery", 0.12)), 0.05)) if cl else 1.0
	play_clip(c, {"speed": speed, "blend_in": 0.03})
	clip_end = duration + float(param("recovery", 0.12))
	ctx.move_mode = BendingContext.Move.DRIVE
	ctx.move_velocity = dir * _speed_at(0.0)
	ctx.gravity_scale = float(param("gravity", 0.0 if in_air else 1.0))
	ctx.invulnerable = iframes > 0.0
	ctx.poise_armor = 999.0 if bool(param("poise_armor", prof.dodge_poise_armor)) else 0.0
	ctx.face_dir = Vector3.ZERO
	cancel_at = duration * 0.7
	BendingFeedback.sound(ctx.element, &"dash", ctx.origin())
	on_dodge_start()


## Speed profile: fast burst easing out; integrates to `distance` over `duration`.
func _speed_at(t: float) -> float:
	var u := clampf(t / maxf(duration, 0.01), 0.0, 1.0)
	# v(u) = v0 * (1 - u^2)  ->  distance = v0 * duration * 2/3
	return distance * 1.5 / maxf(duration, 0.01) * (1.0 - u * u)


func update(delta: float) -> void:
	if time < duration:
		ctx.move_mode = BendingContext.Move.DRIVE
		ctx.move_velocity = dir * _speed_at(time)
	else:
		ctx.move_mode = BendingContext.Move.BRAKE
		ctx.brake_rate = 40.0
		ctx.gravity_scale = 1.0
	if time >= iframes:
		ctx.invulnerable = false
	if time >= duration:
		ctx.poise_armor = 0.0
	on_dodge_tick(delta)
	if time >= clip_end:
		finish()


func can_cancel_into(slot_kind: StringName) -> bool:
	var strikes := float(param("cancel_strikes", -1.0))
	if strikes >= 0.0 and (slot_kind == &"light" or slot_kind == &"heavy") and time >= strikes:
		return true
	if slot_kind == &"defense" and time >= duration * 0.8:
		return true
	return slot_kind == &"dodge" and time >= duration + 0.04


func has_iframes() -> bool:
	return time < iframes and iframes > 0.0


## The caster dodged `hit` (called by the caster's receive_hit).
func notify_dodged(hit: HitInfo) -> void:
	if not perfect and time <= PERFECT_WINDOW:
		perfect = true
		on_perfect_dodge(hit)


func on_cancel(_reason: StringName) -> void:
	on_dodge_end()


func on_finish() -> void:
	on_dodge_end()


# --- overridables ----------------------------------------------------------------------------

func on_dodge_start() -> void:
	pass


func on_dodge_tick(_delta: float) -> void:
	pass


func on_dodge_end() -> void:
	pass


func on_perfect_dodge(_hit: HitInfo) -> void:
	pass
