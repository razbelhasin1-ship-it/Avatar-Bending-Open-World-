class_name ChargeAbility
extends BendingAbility
## Heavy strike: tap for the element's heavy, hold to charge.
## Pressing starts the wind-up (params.hold_clip, a looping or one-shot clip);
## releasing before params.tap_time is a TAP, holding longer charges 0..1 over
## def.charge_time (extra chi params.charge_chi spent progressively). Releasing
## (or def.max_hold) plays the release clip and the attack spawns on its
## &"release" event via release_attack(charge, tapped).
## params: hold_clip, hold_speed, release_clip, release_speed, release_start,
## tap_clip (optional different release for taps), tap_time (0.2), min_windup (0.1),
## charge_chi (extra chi at full charge), walk_scale (move speed while charging).

var charge := 0.0
var tapped := true
var charging := true
var hold_time := 0.0
var released := false
var _charge_spent := 0.0
var _loop_id := 0


func begin() -> void:
	ctx.move_mode = BendingContext.Move.FREE
	ctx.move_speed_scale = float(param("walk_scale", 0.3))
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 900.0
	ctx.poise_armor = def.poise_armor
	var hc: StringName = param("hold_clip", &"")
	if hc != &"":
		play_clip(hc, {"speed": float(param("hold_speed", 1.0)), "blend_in": 0.08})
	clip_end = INF
	max_time = maxf(def.max_hold, 1.0) + 3.0
	on_windup()


func update(delta: float) -> void:
	if charging:
		hold_time += delta
		ctx.face_dir = ctx.aim_flat()
		var tap_t := float(param("tap_time", 0.2))
		if hold_time > tap_t and def.charge_time > 0.0:
			tapped = false
			var want := clampf((hold_time - tap_t) / def.charge_time, 0.0, 1.0)
			var extra := float(param("charge_chi", 0.0))
			if extra > 0.0 and want > charge:
				var cost := (want - charge) * extra
				if ctx.spend_chi(cost):
					_charge_spent += cost
					charge = want
			else:
				charge = want
			on_charging(charge, delta)
		var min_w := float(param("min_windup", 0.1))
		if (not input_held and hold_time >= min_w) or (def.max_hold > 0.0 and hold_time >= def.max_hold):
			_do_release()
		return
	if time >= clip_end:
		finish()


func on_input_released() -> void:
	pass


func _do_release() -> void:
	charging = false
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.move_speed_scale = 0.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1800.0
	var rc: StringName = param("tap_clip", param("release_clip", def.clip)) if tapped else param("release_clip", def.clip)
	var start := float(param("release_start", 0.0))
	if tapped:
		start = float(param("tap_start", start))
	play_clip(rc, {"speed": float(param("release_speed", 1.0)) * (float(param("tap_speed_mult", 1.15)) if tapped else 1.0), "start": start, "blend_in": 0.06})
	on_release_begin(charge, tapped)
	# Clips without a release event release immediately.
	if time_to_event(&"release") == INF:
		on_event(&"release")


func on_event(event: StringName) -> void:
	if event == &"release" and not charging and not released:
		released = true
		ctx.face_dir = Vector3.ZERO
		release_attack(charge, tapped)
	else:
		on_clip_event(event)


func on_cancel(_reason: StringName) -> void:
	on_cleanup()


func on_finish() -> void:
	on_cleanup()


# --- overridables ----------------------------------------------------------------------------

func on_windup() -> void:
	pass


## Called every tick while charging (charge 0..1).
func on_charging(_charge: float, _delta: float) -> void:
	pass


func on_release_begin(_charge: float, _tapped: bool) -> void:
	pass


## Spawn the attack (projectile / blast) here.
func release_attack(_charge: float, _tapped: bool) -> void:
	pass


func on_clip_event(_event: StringName) -> void:
	pass


## Stop loops / free held visuals (also on cancel).
func on_cleanup() -> void:
	pass
