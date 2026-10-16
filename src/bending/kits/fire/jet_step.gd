extends BendingAbility
## Jet Step: crouch, palms pushed down (jet_step_launch), and on &"takeoff" fire jets
## blast from the feet and palms: the bender launches up and forward (9.5 + 8 m/s).
## Keep the button held through the thrust to HOVER on the jets (gravity off, drift
## with the stick, 18 chi/s, 1.1 s max); release to fall with your momentum. Usable
## once in the air (a boost upward, no crouch). Taking off from the ground scorches
## whoever stands within 2.2 m (KNOCKBACK + burn) and the ground under the feet.
## Non-player casters always take the short leap (no hover).

const CROUCH := 0
const THRUST := 1
const HOVER := 2
const DONE := 3

var phase := CROUCH
var phase_t := 0.0
var airborne_start := false
var dir := Vector3.FORWARD
var _jets: Array[FireJetFx] = []
var _loop_id := 0
var _trail_t := 0.0


func can_use() -> StringName:
	if not FireCommon.grounded(ctx) and bool(ctx.caster.get_meta(&"jet_air_used", false)):
		return &"airborne"
	return &""


func begin() -> void:
	FireCommon.begin()
	airborne_start = not FireCommon.grounded(ctx)
	if airborne_start:
		ctx.caster.set_meta(&"jet_air_used", true)
		if ctx.caster.get_node_or_null(^"JetLandWatch") == null:
			var w := LandWatch.new()
			w.name = "JetLandWatch"
			w.body = ctx.body
			ctx.caster.add_child(w)
	var mv := ctx.move_input
	mv.y = 0.0
	if mv.length() > 0.2:
		dir = mv.normalized()
	elif ctx.aim_target() != null:
		dir = ctx.aim_flat()
	else:
		dir = ctx.forward()
	ctx.face_dir = dir
	ctx.face_rate = 1440.0
	ctx.poise_armor = 15.0
	ctx.move_mode = BendingContext.Move.BRAKE if not airborne_start else BendingContext.Move.FREE
	ctx.brake_rate = 30.0
	max_time = 4.0
	if airborne_start:
		play_clip(def.clip, {"start": 0.3, "speed": 1.6, "blend_in": 0.03})
	else:
		play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.04})
	clip_end = INF


func on_event(event: StringName) -> void:
	if event == &"takeoff" and phase == CROUCH:
		_takeoff()


func _takeoff() -> void:
	phase = THRUST
	phase_t = 0.0
	var up := float(param("air_up", 7.0)) if airborne_start else float(param("launch_up", 9.5))
	_set_vy(up)
	ctx.gravity_scale = 0.35
	ctx.move_mode = BendingContext.Move.DRIVE
	ctx.move_velocity = dir * float(param("launch_fwd", 8.0)) * (0.75 if airborne_start else 1.0)
	_start_jets()
	var feet := (ctx.socket_pos(&"foot_l") + ctx.socket_pos(&"foot_r")) * 0.5
	if not airborne_start:
		var g := ctx.ground_point(ctx.origin())
		BendingHits.sphere(ctx, g + Vector3.UP * 0.7, float(param("takeoff_radius", 2.2)), hit_data(), attack_id, def.id, {"push": &"radial"})
		FireFx.burst(ctx.caster, g + Vector3.UP * 0.15, 1.3, Vector3.UP)
		FxBurst.spawn(ctx.caster, &"dust_ring", g + Vector3.UP * 0.05, {"color": Color(0.3, 0.27, 0.24), "count": 0.7, "size": 0.8})
		FireEnv.heat(ctx, g + Vector3.UP * 0.2, 1.2, 0.6, {"mark": 0.9})
	else:
		FireFx.burst(ctx.caster, feet, 1.0, Vector3.DOWN)
	FxFlash.spawn(ctx.caster, feet, FireCommon.HOT, 3.5, 0.3, 6.0)
	sound(&"jump", feet, 2.0)
	_loop_id = Audio.start_bending_loop(ctx.element, &"special_loop", ctx.caster, -5.0, 0.05)
	FireCommon.shake(ctx, 0.15, 0.15)
	FireCommon.practiced(ctx, def.id)


func _set_vy(v: float) -> void:
	if ctx.body != null:
		ctx.body.velocity.y = v


func _vy() -> float:
	return ctx.body.velocity.y if ctx.body != null else 0.0


func _start_jets() -> void:
	if not _jets.is_empty():
		return
	for i in 4:
		_jets.append(FireJetFx.spawn(ctx.caster))


func _stop_jets() -> void:
	for j in _jets:
		if is_instance_valid(j):
			j.stop()
	_jets.clear()
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.2)
		_loop_id = 0


func update(delta: float) -> void:
	phase_t += delta
	match phase:
		CROUCH:
			if time > 0.8:
				_takeoff()
		THRUST:
			if phase_t >= float(param("thrust_time", 0.28)):
				var held := input_held and ctx.is_player() and phase_t >= float(param("min_hold", 0.22))
				if held and ctx.has_chi(1.0):
					phase = HOVER
					phase_t = 0.0
					ctx.gravity_scale = 0.0
					ctx.set_upkeep(float(param("hover_upkeep", 18.0)))
					if ctx.rig:
						ctx.rig.play_action(&"jet_hover", {"blend_in": 0.15})
				else:
					_end_flight()
		HOVER:
			# Ease the climb to a standstill and drift with the stick.
			var vy := move_toward(_vy(), 0.4 * sin(time * 6.0), 30.0 * delta)
			_set_vy(vy)
			var mv := ctx.move_input
			mv.y = 0.0
			ctx.move_mode = BendingContext.Move.DRIVE
			ctx.move_velocity = mv.limit_length(1.0) * float(param("drift", 5.0))
			if mv.length() > 0.2:
				ctx.face_dir = mv.normalized()
			if not input_held or phase_t >= float(param("hover_time", 1.1)) or ctx.chi() <= 0.5:
				_end_flight()
		DONE:
			finish()
	_update_jets(delta)


func _update_jets(delta: float) -> void:
	if _jets.size() < 4:
		return
	var k := 1.0 if phase == THRUST else 0.7
	var down := Vector3.DOWN
	var back := -dir * 0.35 if phase == THRUST else Vector3.ZERO
	var sockets: Array[StringName] = [&"foot_l", &"foot_r", &"hand_l", &"hand_r"]
	for i in 4:
		var j := _jets[i]
		if not is_instance_valid(j):
			continue
		var feet := i < 2
		var nozzle := ctx.socket_pos(sockets[i]) + (Vector3.DOWN * 0.04 if feet else Vector3.ZERO)
		j.aim(nozzle, (down + back).normalized(), 1.25 if feet else 0.75, k)
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.12
		var g := ctx.ground_y(ctx.origin(), 0.5, 4.0)
		if ctx.origin().y - g < 2.2:
			# Low over the ground the jets scorch it.
			FxDecal.spawn(ctx.caster, Vector3(ctx.origin().x, g, ctx.origin().z), &"scorch", 0.5)


func _end_flight() -> void:
	if phase == DONE:
		return
	phase = DONE
	ctx.gravity_scale = 1.0
	ctx.set_upkeep(0.0)
	_stop_jets()
	finish()


func on_cancel(_reason: StringName) -> void:
	_cleanup()


func on_finish() -> void:
	_cleanup()


func _cleanup() -> void:
	ctx.set_upkeep(0.0)
	_stop_jets()


## Clears the "used in the air" flag once the body is back on the ground (8 s cap).
class LandWatch extends Node:
	var body: CharacterBody3D
	var t := 0.0

	func _physics_process(delta: float) -> void:
		t += delta
		if body == null or not is_instance_valid(body) or (body.is_on_floor() and t > 0.1) or t > 8.0:
			if body != null and is_instance_valid(body):
				body.set_meta(&"jet_air_used", false)
			queue_free()
