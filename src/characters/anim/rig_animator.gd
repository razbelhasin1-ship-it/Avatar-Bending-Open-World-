class_name RigAnimator
extends RefCounted
## Per-rig layered pose engine (owned by HumanoidRig):
##   1. idle / combat-stance loop clips of the current style (blended by the
##      combat weight)  ->  idle foot spots for the locomotion
##   2. locomotion (feet, gait body motion; upper body keeps the stance in combat)
##   3. pose state loop (airborne, falling, riding, knocked_down, blocking...)
##   4. action clip (masked, mirrored, speed, events, plants, root motion)
##   5. additive: breathing, hit flinch, look-at; face: blink, mouth
##   6. snapshot crossfade (smooth transitions between anything)
##   7. ground adaptation (foot IK + pelvis drop) -> RigSolver -> secondary.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")
const P = preload("res://src/characters/anim/rig_pose.gd")

## Pose states -> [clip, mask, feet_owned_by_clip]. Style variants are looked
## up first as "<clip>_<style>".
const STATES := {
	&"normal": [&"", &"full", false],
	&"airborne": [&"jump_air", &"full", true],
	&"falling": [&"fall", &"full", true],
	&"riding": [&"ride", &"full", true],
	&"knocked_down": [&"down_loop", &"full", true],
	&"blocking": [&"block_hold", &"upper", false],
	&"charging": [&"charge_hold", &"upper", false],
	&"swimming": [&"swim", &"full", true],
	&"dead": [&"dead_loop", &"full", true],
	&"sitting": [&"sit_loop", &"full", true],
	&"meditating": [&"meditate_loop", &"full", true],
	&"sleeping": [&"sleep_loop", &"full", true],
	&"tumbling": [&"air_tumble", &"full", true],
}

var rig: Node3D
var def: RigSkeletonDef
var solver := RigSolver.new()
var loco := RigLocomotion.new()
var secondary := RigSecondary.new()

var style_name: StringName = RigStyles.DEFAULT
var style: Dictionary = RigStyles.get_style(RigStyles.DEFAULT)
var combat := false
var combat_w := 0.0
var grounded := true

var pose_state: StringName = &"normal"
var _state_clip: AnimClip = null
var _state_mask: Array = []
var _state_feet := false
var _state_t := 0.0
var _state_w := 0.0

var _idle_clip: AnimClip
var _stance_clip: AnimClip
var _idle_t := 0.0
var _stance_t := 0.0

var action: AnimClip = null
var action_t := 0.0
var action_speed := 1.0
var action_w := 0.0
var action_w_target := 1.0
var action_blend_in := 0.08
var action_blend_out := 0.15
var action_mirror := false
var action_mask: Array = []
var action_root_motion := false
var action_feet := false
var _action_prev_root := Vector3.ZERO
var root_motion_world := Vector3.ZERO
var time_scale := 1.0
## When true, time does not advance (freeze frames, debugging, hit freeze).
var paused := false

var _xfade := RigPose.new()
var _xfade_w := 0.0
var _xfade_rate := 6.0

var _flinch := RigPose.new()
var _flinch_age := 99.0
var _flinch_amount := 0.0

var look_target := Vector3.ZERO
var look_weight_target := 0.0
var _look_w := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0

var _breath_t := 0.0
var _blink_timer := 2.0
var _blink_t := -1.0
var talking := false
var _talk_t := 0.0
## Minimum fist closure per hand while gripping a prop.
var grip := PackedFloat32Array([0.0, 0.0])
## Per-hand carry clip (e.g. hold_pole_r) layered over locomotion/states.
var hold_clips: Array = [null, null]
var _hold_t := 0.0

var foot_ik := true
var ground_query: Callable
var _hips_drop := 0.0
var _ground_cache: Array = [[0.0, Vector3.UP], [0.0, Vector3.UP]]
var _ground_frame := 0
var ground_every := 1

var base := RigPose.new()
var final := RigPose.new()
var _tmp := RigPose.new()
var _tmp2 := RigPose.new()
var _neutral := RigPose.new()

var _xf := Transform3D.IDENTITY
var _pending_dt := 0.0


func setup(r: Node3D, d: RigSkeletonDef, springs: Array) -> void:
	rig = r
	def = d
	solver.setup(d)
	loco.setup(d)
	secondary.setup(d, springs)
	set_style(style_name)


func set_style(s: StringName) -> void:
	style_name = s if RigStyles.has_style(s) else RigStyles.DEFAULT
	style = RigStyles.get_style(style_name)
	loco.set_style(style)
	_idle_clip = AnimLibrary.get_clip(style["idle"])
	_stance_clip = AnimLibrary.get_clip(style["stance"])
	if _state_clip != null and pose_state != &"normal":
		_state_clip = _lookup_state_clip(pose_state)


func _lookup_state_clip(state: StringName) -> AnimClip:
	var info: Array = STATES.get(state, STATES[&"normal"])
	var cname: StringName = info[0]
	if cname == &"":
		return null
	var styled := AnimLibrary.get_clip(StringName("%s_%s" % [cname, style_name]))
	return styled if styled != null else AnimLibrary.get_clip(cname)


func set_pose_state(state: StringName, blend: float = 0.2) -> bool:
	if not STATES.has(state):
		push_warning("HumanoidRig: unknown pose state '%s'" % state)
		return false
	if state == pose_state:
		return true
	snapshot(blend)
	pose_state = state
	var info: Array = STATES[state]
	_state_clip = _lookup_state_clip(state)
	_state_mask = P.MASKS.get(info[1], [])
	_state_feet = info[2]
	_state_t = 0.0
	_state_w = 1.0 if _state_clip != null else 0.0
	return true


## Freezes the current final pose and fades from it over `blend` seconds.
func snapshot(blend: float) -> void:
	if blend <= 0.001:
		_xfade_w = 0.0
		return
	_xfade.copy_from(final)
	_xfade.wrap_angles()
	_xfade_w = 1.0
	_xfade_rate = 1.0 / blend


func play(clip: AnimClip, opts: Dictionary) -> float:
	var had_action := action != null
	var bi: float = float(opts.get("blend_in", clip.blend_in))
	if had_action:
		snapshot(maxf(bi, 0.06))
	action = clip
	action_speed = maxf(float(opts.get("speed", 1.0)), 0.01)
	action_t = clampf(float(opts.get("start", 0.0)), 0.0, 1.0)
	action_blend_in = bi
	action_blend_out = float(opts.get("blend_out", clip.blend_out))
	action_mirror = bool(opts.get("mirror", false))
	var m: Variant = opts.get("mask", null)
	action_mask = P.MASKS.get(StringName(m), clip.mask) if m != null else clip.mask
	action_root_motion = bool(opts.get("root_motion", false))
	_action_prev_root = clip.root_at(action_t)
	action_w = 1.0 if had_action or bi <= 0.0 else 0.0
	action_w_target = 1.0
	action_feet = _clip_owns_feet(clip, action_mask)
	return clip.duration(action_speed)


func _clip_owns_feet(clip: AnimClip, mask: Array) -> bool:
	for ch in [P.FOOT_L, P.FOOT_R]:
		if clip.tracks.has(ch) and (mask.is_empty() or mask.has(ch)):
			return true
	return false


func stop(blend: float = -1.0) -> void:
	if action == null:
		return
	snapshot(action_blend_out if blend < 0.0 else blend)
	action = null


func flinch(local_dir: Vector3, strength: float) -> void:
	# local_dir: push direction in model space (x right, z back).
	_flinch.set_neutral()
	var back := clampf(local_dir.z, -1.0, 1.0)
	var right := clampf(local_dir.x, -1.0, 1.0)
	var s := clampf(strength, 0.2, 2.0)
	for i in RigPose.COUNT:
		_flinch.v[i] = Vector3.ZERO if not RigPose.is_float_channel(i) else 0.0
	_flinch.v[P.SPINE] = Vector3(-8.0 * back, 0.0, 6.0 * right) * s
	_flinch.v[P.CHEST] = Vector3(-14.0 * back, -10.0 * right, 8.0 * right) * s
	_flinch.v[P.HEAD] = Vector3(-18.0 * back, -14.0 * right, 10.0 * right) * s
	_flinch.v[P.CLAV_L] = Vector3(10.0, 0.0, 0.0) * s
	_flinch.v[P.CLAV_R] = Vector3(10.0, 0.0, 0.0) * s
	_flinch.v[P.HIPS] = Vector3(0.02 * right, -0.02, -0.025 * back) * s
	_flinch_age = 0.0
	_flinch_amount = 1.0


## Main per-frame update. Returns true if a solve happened.
func update(dt: float, xf: Transform3D, vel_world: Vector3, on_ground: bool, do_solve: bool, do_ik: bool) -> bool:
	_xf = xf
	grounded = on_ground
	var sdt := 0.0 if paused else dt * time_scale
	# Clip time and events advance every frame (gameplay sync); the pose layers
	# and locomotion only run on solve frames (reduced LODs), with the
	# accumulated time.
	_advance_times(sdt)
	_pending_dt += sdt
	if not do_solve:
		return false
	sdt = minf(_pending_dt, 0.25)
	_pending_dt = 0.0
	# 1. idle / stance.
	combat_w = move_toward(combat_w, 1.0 if combat else 0.0, sdt * 4.0)
	_neutral.set_neutral()
	if _idle_clip:
		_idle_clip.evaluate(_idle_t, _neutral, base)
	else:
		base.copy_from(_neutral)
	if combat_w > 0.001 and _stance_clip:
		_stance_clip.evaluate(_stance_t, _neutral, _tmp)
		base.blend(_tmp, combat_w)
	_set_idle_feet(base)
	# 2. locomotion.
	var state_feet := _state_feet and _state_w > 0.5
	loco.feet_enabled = not state_feet and not (action != null and action_feet and action_w > 0.5)
	loco.update(sdt, vel_world, on_ground, xf)
	if loco.gait_w > 0.001 and combat_w > 0.001:
		_tmp2.copy_from(base)
	loco.write_pose(base)
	if loco.gait_w > 0.001 and combat_w > 0.001:
		# Keep the guard up while moving in combat.
		base.blend_masked(_tmp2, combat_w * 0.72 * loco.gait_w, P.MASKS[&"arms"])
	# 3. pose state.
	if _state_clip != null and _state_w > 0.0:
		_state_clip.evaluate(_state_t, base, _tmp)
		base.blend_masked(_tmp, _state_w, _state_mask)
	# 3b. carried props (arm masks), under actions.
	for side in 2:
		var hc: AnimClip = hold_clips[side]
		if hc != null:
			_hold_t = fposmod(_hold_t + sdt * 0.5 / hc.length, 1.0)
			hc.evaluate(_hold_t, base, _tmp)
			base.blend_masked(_tmp, 1.0 - loco.gait_w * 0.3, hc.mask)
	# 4. action.
	if action != null:
		if action_mirror:
			_tmp2.copy_from(base)
			_tmp2.mirror()
			action.evaluate(action_t, _tmp2, _tmp)
			_tmp.mirror()
		else:
			action.evaluate(action_t, base, _tmp)
		base.blend_masked(_tmp, action_w, action_mask)
	final.copy_from(base)
	# 5. additive layers.
	_additive(sdt)
	# 6. crossfade.
	if _xfade_w > 0.0:
		final.blend(_xfade, _xfade_w)
		_xfade_w = maxf(_xfade_w - sdt * _xfade_rate, 0.0)
	_ground(do_ik and foot_ik)
	solver.blink = _blink_value()
	solver.solve(final)
	return true


func _advance_times(dt: float) -> void:
	if _idle_clip:
		_idle_t = fposmod(_idle_t + dt / _idle_clip.length, 1.0)
	if _stance_clip:
		_stance_t = fposmod(_stance_t + dt / _stance_clip.length, 1.0)
	if _state_clip:
		if _state_clip.loop:
			_state_t = fposmod(_state_t + dt / _state_clip.length, 1.0)
		else:
			_state_t = minf(_state_t + dt / _state_clip.length, 1.0)
	_breath_t += dt
	_flinch_age += dt
	if action == null:
		return
	action_w = move_toward(action_w, action_w_target, dt / maxf(action_blend_in, 0.001))
	var prev := action_t
	var nt := action_t + dt * action_speed / action.length
	var clip := action
	if clip.loop:
		var wrapped := nt >= 1.0
		action_t = fposmod(nt, 1.0)
		_fire_events(clip, prev, nt if not wrapped else 1.0)
		if wrapped:
			_fire_events(clip, -0.0001, action_t)
		_root_motion(clip, prev, action_t, wrapped)
		return
	action_t = minf(nt, 1.0)
	_fire_events(clip, prev, action_t)
	_root_motion(clip, prev, action_t, false)
	if nt >= 1.0 and action == clip:
		_finish(clip)


func _fire_events(clip: AnimClip, t0: float, t1: float) -> void:
	for e: Array in clip.events:
		var et: float = e[0]
		if et > t0 and et <= t1:
			rig.call(&"_on_action_event", clip.name, e[1])
			if action != clip:
				return
	for pl: Array in clip.plants:
		var pt: float = pl[0]
		if pt > t0 and pt <= t1:
			var side: int = pl[1]
			if action_mirror:
				side = 1 - side
			rig.call(&"_on_clip_plant", side, float(pl[2]))


func _root_motion(clip: AnimClip, t0: float, t1: float, wrapped: bool) -> void:
	if not action_root_motion or clip.root.is_empty():
		return
	var r1 := clip.root_at(t1)
	var r0 := clip.root_at(t0) if not wrapped else clip.root_at(0.0) - (clip.root_at(1.0) - clip.root_at(t0))
	var d := r1 - r0
	if action_mirror:
		d.x = -d.x
	var k := def.leg_len / 0.889
	root_motion_world += _xf.basis * (Vector3(d.x, d.y, -d.z) * k)


func _finish(clip: AnimClip) -> void:
	snapshot(action_blend_out)
	action = null
	rig.call(&"_on_action_finished", clip.name)
	if action != null:
		return
	if clip.next != &"" and AnimLibrary.has_clip(clip.next):
		play(AnimLibrary.get_clip(clip.next), {"blend_in": 0.0})
	elif clip.then_state != &"":
		set_pose_state(clip.then_state, 0.0)
		if clip.state_clip != &"" and AnimLibrary.has_clip(clip.state_clip):
			_state_clip = AnimLibrary.get_clip(clip.state_clip)


func _set_idle_feet(p: RigPose) -> void:
	for side in 2:
		var sg := SK.SIDE_SIGN[side]
		var f: Vector3 = p.v[P.FOOT_L + side]
		var rest := def.rest_pos[SK.FOOT[side]]
		var gp := Vector3(rest.x + sg * f.x * def.leg_len, 0.0, rest.z - f.z * def.leg_len)
		loco.idle_pos[side] = gp
		var r: Vector3 = p.v[P.FOOT_ROT_L + side]
		loco.idle_yaw[side] = -sg * deg_to_rad(r.y)


func _additive(dt: float) -> void:
	# Breathing.
	var br := sin(_breath_t * TAU / (3.6 if not combat else 2.6)) * (1.0 - loco.gait_w * 0.7)
	var ch: Vector3 = final.v[P.CHEST]
	final.v[P.CHEST] = ch + Vector3(-1.3 * br, 0.0, 0.0)
	for i in [P.CLAV_L, P.CLAV_R]:
		final.v[i] = (final.v[i] as Vector3) + Vector3(1.2 * br, 0.0, 0.0)
	# Hit flinch.
	if _flinch_age < 0.6:
		var amt := _flinch_age / 0.05 if _flinch_age < 0.05 else exp(-(_flinch_age - 0.05) / 0.11)
		for i in [P.SPINE, P.CHEST, P.HEAD, P.CLAV_L, P.CLAV_R, P.HIPS]:
			final.v[i] = (final.v[i] as Vector3) + (_flinch.v[i] as Vector3) * amt
	# Look-at.
	_look_w = move_toward(_look_w, look_weight_target, dt * 3.0)
	if _look_w > 0.001:
		var head_m := solver.g_pos[SK.HEAD]
		var tgt_m := _xf.affine_inverse() * look_target
		var d := tgt_m - head_m
		var yaw := clampf(atan2(-d.x, -d.z), -1.3, 1.3)
		var pitch := clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.7, 0.6)
		if d.length_squared() < 0.01:
			yaw = 0.0
			pitch = 0.0
		var k := 1.0 - exp(-dt * 7.0)
		_look_yaw = lerpf(_look_yaw, yaw, k)
		_look_pitch = lerpf(_look_pitch, pitch, k)
		var yd := rad_to_deg(_look_yaw) * _look_w
		var pd := -rad_to_deg(_look_pitch) * _look_w
		final.v[P.CHEST] = (final.v[P.CHEST] as Vector3) + Vector3(pd * 0.15, yd * 0.25, 0.0)
		final.v[P.NECK] = (final.v[P.NECK] as Vector3) + Vector3(pd * 0.35, yd * 0.3, 0.0)
		final.v[P.HEAD] = (final.v[P.HEAD] as Vector3) + Vector3(pd * 0.5, yd * 0.45, 0.0)
	# Hands close around held props.
	for side in 2:
		if grip[side] > 0.0:
			final.v[P.FIST_L + side] = maxf(final.v[P.FIST_L + side], grip[side])
	# Talking mouth.
	if talking:
		_talk_t += dt
		var m := 0.5 + 0.5 * sin(_talk_t * 17.0) * sin(_talk_t * 5.3 + 1.0)
		final.v[P.MOUTH] = maxf(final.v[P.MOUTH], m * 0.6)


func _blink_value() -> float:
	if _blink_t >= 0.0:
		var b := _blink_t
		return 1.0 - absf(b * 2.0 - 1.0)
	return 0.0


## Called once per frame by the rig (real time) to drive blinking.
func tick_face(dt: float) -> void:
	if _blink_t >= 0.0:
		_blink_t += dt / 0.14
		if _blink_t >= 1.0:
			_blink_t = -1.0
		return
	_blink_timer -= dt
	if _blink_timer <= 0.0:
		_blink_t = 0.0
		_blink_timer = randf_range(2.2, 5.5)


func _ground(enabled: bool) -> void:
	var target_drop := 0.0
	var w_on := 1.0 if (enabled and grounded and not (_state_feet and _state_w > 0.5)) else 0.0
	if enabled and ground_query.is_valid() and w_on > 0.0:
		_ground_frame += 1
		var inv := _xf.affine_inverse()
		var root_y := _xf.origin.y
		var sc := _xf.basis.get_scale().y
		for side in 2:
			if _ground_frame % ground_every == 0 or ground_every <= 1:
				var f: Vector3 = final.v[P.FOOT_L + side]
				var sg := SK.SIDE_SIGN[side]
				var rest := def.rest_pos[SK.FOOT[side]]
				var gp_m := Vector3(rest.x + sg * f.x * def.leg_len, 0.0, rest.z - f.z * def.leg_len)
				var gp_w := _xf * gp_m
				var res: Array = ground_query.call(gp_w)
				var dy := (float(res[0]) - root_y) / maxf(sc, 0.01)
				var n_m := (inv.basis * (res[1] as Vector3)).normalized()
				_ground_cache[side] = [clampf(dy, -0.45 * def.leg_len, 0.45 * def.leg_len), n_m]
			var gc: Array = _ground_cache[side]
			solver.ground_dy[side] = gc[0]
			solver.ground_n[side] = gc[1]
			var lift: float = (final.v[P.FOOT_L + side] as Vector3).y
			solver.ground_w[side] = clampf(1.0 - lift * 4.0, 0.0, 1.0)
		target_drop = maxf(0.0, -minf(solver.ground_dy[0], solver.ground_dy[1]))
	else:
		for side in 2:
			solver.ground_dy[side] = lerpf(solver.ground_dy[side], 0.0, 0.3)
			solver.ground_w[side] = 0.0
	_hips_drop = lerpf(_hips_drop, target_drop, 0.25)
	solver.hips_drop = _hips_drop


func consume_root_motion() -> Vector3:
	var r := root_motion_world
	root_motion_world = Vector3.ZERO
	return r
