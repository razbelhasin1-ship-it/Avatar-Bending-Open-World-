class_name RigLocomotion
extends RefCounted
## Procedural gait with zero foot sliding.
##
## * Planted feet are locked in WORLD space (position + yaw), so turning,
##   accelerating or being pushed never slides them.
## * While moving, a gait phase (cadence from speed + style) decides when each
##   foot lifts and lands; the swing lands where the foot must be at mid-stance
##   given the current velocity, so stride length always equals speed x
##   stance time.
## * When stopped, feet settle onto the idle/stance clip's foot spots with
##   discrete steps, also used for turning in place.
## * Each plant reports the true foot position/yaw for footprints/sounds.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")
const P = preload("res://src/characters/anim/rig_pose.gd")

## Emitted on every plant: side (0 left, 1 right), world footprint center,
## world yaw (radians), weight.
signal planted(side: int, world_pos: Vector3, world_yaw: float, weight: float)

var def: RigSkeletonDef
var style: Dictionary = RigStyles.get_style(RigStyles.DEFAULT)
var leg := 0.9
var foot_len := 0.26

var phase := 0.0
var moving := false
var grounded := true
var speed := 0.0
var vel := Vector3.ZERO
var accel := Vector3.ZERO
var turn_rate := 0.0
var gait_w := 0.0
var cadence := 1.0
var duty := 0.6
## 0 = walk .. 1 = run (for weights and blends).
var run_factor := 0.0

var is_planted := [true, true]
var plant_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var plant_yaw: Array[float] = [0.0, 0.0]
var swing_t: Array[float] = [0.0, 0.0]
var swing_dur: Array[float] = [0.3, 0.3]
var swing_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var swing_from_yaw: Array[float] = [0.0, 0.0]
var swing_target: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Current ground point under each ankle (model space) and relative yaw.
var foot_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var foot_yaw: Array[float] = [0.0, 0.0]
var foot_lift: Array[float] = [0.0, 0.0]
var foot_pitch: Array[float] = [0.0, 0.0]
## Desired idle foot spots (model ground points) + relative yaws.
var idle_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var idle_yaw: Array[float] = [0.0, 0.0]
## Set false while an action/pose state owns the legs (feet are released).
var feet_enabled := true

var _rig_yaw := 0.0
var _last_rig_yaw := 0.0
var _initialized := false
var _next_idle_side := 0
var _idle_cool := 0.0
var _last_vel := Vector3.ZERO


func setup(d: RigSkeletonDef) -> void:
	def = d
	leg = d.leg_len
	foot_len = float(d.p["foot"]) * float(d.p["height"])
	for side in 2:
		idle_pos[side] = _rest_ground(side)
		foot_pos[side] = idle_pos[side]


func set_style(st: Dictionary) -> void:
	style = st


func _rest_ground(side: int) -> Vector3:
	var a := def.rest_pos[SK.FOOT[side]]
	return Vector3(a.x, 0.0, a.z)


static func _yaw_of(xf: Transform3D) -> float:
	var f := -xf.basis.z
	return atan2(-f.x, -f.z)


## Re-anchors planted feet at their current model positions (after teleports).
func reset(xf: Transform3D) -> void:
	_initialized = false
	_init_feet(xf)


func _init_feet(xf: Transform3D) -> void:
	_rig_yaw = _yaw_of(xf)
	_last_rig_yaw = _rig_yaw
	for side in 2:
		is_planted[side] = true
		foot_pos[side] = idle_pos[side]
		foot_yaw[side] = idle_yaw[side]
		plant_world[side] = xf * foot_pos[side]
		plant_yaw[side] = _rig_yaw + foot_yaw[side]
		foot_lift[side] = 0.0
	_initialized = true


## Advances the gait. `vel_world` is the owner's velocity, `xf` the skeleton
## global transform (model -> world).
func update(dt: float, vel_world: Vector3, on_ground: bool, xf: Transform3D) -> void:
	if not _initialized:
		_init_feet(xf)
	grounded = on_ground
	var inv_basis := xf.basis.inverse()
	var vm := inv_basis * vel_world
	vm.y = 0.0
	var k := 1.0 - exp(-dt * 14.0)
	vel = vel.lerp(vm, k)
	var a := (vel - _last_vel) / maxf(dt, 0.001)
	_last_vel = vel
	accel = accel.lerp(a, 1.0 - exp(-dt * 6.0))
	speed = vel.length()
	_rig_yaw = _yaw_of(xf)
	var dyaw := wrapf(_rig_yaw - _last_rig_yaw, -PI, PI)
	_last_rig_yaw = _rig_yaw
	turn_rate = lerpf(turn_rate, dyaw / maxf(dt, 0.001), 1.0 - exp(-dt * 8.0))
	var rel_speed := speed * (0.889 / maxf(leg, 0.2))
	cadence = RigStyles.param(style, "cadence", rel_speed)
	duty = RigStyles.param(style, "duty", rel_speed)
	if speed > 0.05:
		var max_sweep := 1.15 * leg
		duty = minf(duty, max_sweep * cadence / speed)
	duty = clampf(duty, 0.18, 0.75)
	var sp: Array = style["speeds"]
	run_factor = smoothstep(float(sp[0]), float(sp[1]), rel_speed)
	var was_moving := moving
	if not grounded or not feet_enabled:
		moving = false
	elif moving:
		moving = speed > 0.08
	else:
		moving = speed > 0.16
	gait_w = move_toward(gait_w, 1.0 if moving else 0.0, dt * (5.0 if moving else 3.0))
	if not grounded or not feet_enabled:
		_update_released(dt, xf)
		return
	if moving and not was_moving:
		_start_cycle()
	if moving:
		phase = fposmod(phase + cadence * dt, 1.0)
		for side in 2:
			_update_moving_foot(side, dt, xf)
	else:
		for side in 2:
			_update_idle_foot(side, dt, xf)
		_idle_cool -= dt
		if is_planted[0] and is_planted[1] and _idle_cool <= 0.0:
			_maybe_idle_step(xf)
	for side in 2:
		if is_planted[side]:
			var m := xf.affine_inverse() * plant_world[side]
			foot_pos[side] = Vector3(m.x, 0.0, m.z)
			foot_yaw[side] = wrapf(plant_yaw[side] - _rig_yaw, -PI, PI)
			foot_lift[side] = 0.0
			# Safety: re-step if a planted foot ends up far from the body.
			var horiz := Vector2(foot_pos[side].x - idle_pos[side].x, foot_pos[side].z - idle_pos[side].z).length()
			if horiz > 1.6 * leg:
				_teleport_foot(side, xf)
			elif horiz > 1.05 * leg and not moving:
				_lift(side, 0.18)


func _start_cycle() -> void:
	# The foot further behind (relative to travel) swings first.
	var dir := vel.normalized()
	var d0 := foot_pos[0].dot(dir)
	var d1 := foot_pos[1].dot(dir)
	var first := 0 if d0 < d1 else 1
	# The other foot starts at mid-stance (it is under the body), the first one mid-swing.
	phase = fposmod(duty * 0.5 + (0.5 if first == 0 else 0.0), 1.0)


func _foot_phase(side: int) -> float:
	return fposmod(phase - (0.0 if side == 0 else 0.5), 1.0)


func _neutral(side: int) -> Vector3:
	var sg := SK.SIDE_SIGN[side]
	var base := _rest_ground(side)
	base.x += sg * float(style.get("width", 0.0)) * leg
	return base


func _target_yaw(side: int) -> float:
	var sg := SK.SIDE_SIGN[side]
	var toe := deg_to_rad(float(style.get("toe_out", 6.0)))
	var yaw := -sg * toe
	if moving and speed > 0.2:
		# Feet partly turn toward strafing directions (clamped).
		var ang := atan2(-vel.x, -vel.z)
		if absf(ang) < 2.2:
			yaw += clampf(ang, -0.7, 0.7) * 0.45
		else:
			yaw += clampf(wrapf(ang + PI, -PI, PI), -0.5, 0.5) * 0.3
	return yaw


## Ground point where the swinging foot should land (model space).
func _landing(side: int) -> Vector3:
	var stance_time := duty / maxf(cadence, 0.01)
	var lead := vel * stance_time * 0.5
	var back_bias := lerpf(0.0, 0.14, run_factor) * vel * stance_time
	var t := _neutral(side) + lead - back_bias
	# Anticipate turning: rotate the lead with the yaw that happens before mid-stance.
	var rot := clampf(turn_rate * stance_time * 0.5, -0.6, 0.6)
	if absf(rot) > 0.001:
		t = Basis(Vector3.UP, rot) * t
	return Vector3(t.x, 0.0, t.z)


func _update_moving_foot(side: int, dt: float, xf: Transform3D) -> void:
	var p := _foot_phase(side)
	var stance := p < duty
	if is_planted[side] and not stance:
		_lift(side, (1.0 - duty) / maxf(cadence, 0.01))
	if not is_planted[side]:
		swing_t[side] = clampf((p - duty) / maxf(1.0 - duty, 0.01), 0.0, 1.0) if not stance else 1.0
		swing_target[side] = _landing(side)
		_swing_pose(side)
		if stance or swing_t[side] >= 1.0:
			_plant(side, xf)


func _update_idle_foot(side: int, dt: float, xf: Transform3D) -> void:
	if is_planted[side]:
		return
	swing_t[side] = minf(swing_t[side] + dt / maxf(swing_dur[side], 0.05), 1.0)
	swing_target[side] = idle_pos[side]
	_swing_pose(side)
	if swing_t[side] >= 1.0:
		_plant(side, xf)


func _maybe_idle_step(_xf: Transform3D) -> void:
	var worst := -1
	var worst_err := 0.0
	for side in 2:
		var d := Vector2(foot_pos[side].x - idle_pos[side].x, foot_pos[side].z - idle_pos[side].z).length()
		var yd := absf(wrapf(foot_yaw[side] - idle_yaw[side], -PI, PI))
		var err := d / (0.07 * leg) + yd / deg_to_rad(28.0)
		if (d > 0.07 * leg or yd > deg_to_rad(28.0)) and err > worst_err:
			worst_err = err
			worst = side
	if worst < 0:
		return
	# Alternate feet when both are off (turning in place).
	var other := 1 - worst
	var od := Vector2(foot_pos[other].x - idle_pos[other].x, foot_pos[other].z - idle_pos[other].z).length()
	if od > 0.07 * leg and _next_idle_side == other:
		worst = other
	_next_idle_side = 1 - worst
	var dist := Vector2(foot_pos[worst].x - idle_pos[worst].x, foot_pos[worst].z - idle_pos[worst].z).length()
	_lift(worst, clampf(0.2 + dist * 0.35, 0.22, 0.42))
	_idle_cool = 0.08


func _lift(side: int, duration: float) -> void:
	is_planted[side] = false
	swing_t[side] = 0.0
	swing_dur[side] = maxf(duration, 0.08)
	swing_from[side] = foot_pos[side]
	swing_from_yaw[side] = foot_yaw[side]


func _swing_pose(side: int) -> void:
	var u := swing_t[side]
	var ue := u * u * (3.0 - 2.0 * u)
	var from := swing_from[side]
	var to := swing_target[side]
	foot_pos[side] = Vector3(lerpf(from.x, to.x, ue), 0.0, lerpf(from.z, to.z, ue))
	var lift := RigStyles.param(style, "lift", speed * (0.889 / maxf(leg, 0.2))) * leg
	if not moving:
		lift = minf(lift, 0.07 * leg + from.distance_to(to) * 0.25)
	var uv := pow(u, lerpf(1.0, 0.7, run_factor))
	foot_lift[side] = lift * pow(sin(PI * uv), 0.85)
	var target_yaw := _target_yaw(side) if moving else idle_yaw[side]
	foot_yaw[side] = lerp_angle(swing_from_yaw[side], target_yaw, ue)
	# Toe-off then heel-strike pitch.
	var heel := float(style.get("heel", 0.0))
	var early := -32.0 * (1.0 - smoothstep(0.0, 0.45, u)) * lerpf(0.6, 1.0, run_factor)
	var late := lerpf(16.0, 4.0, run_factor) * (1.0 - heel) * smoothstep(0.55, 0.95, u) * (1.0 - smoothstep(0.97, 1.0, u))
	foot_pitch[side] = early + late if moving else early * 0.3


func _plant(side: int, xf: Transform3D) -> void:
	is_planted[side] = true
	var m := swing_target[side]
	foot_pos[side] = m
	foot_lift[side] = 0.0
	foot_yaw[side] = _target_yaw(side) if moving else idle_yaw[side]
	plant_world[side] = xf * m
	plant_yaw[side] = _rig_yaw + foot_yaw[side]
	var sg := SK.SIDE_SIGN[side]
	var fwd_m := Basis(Vector3.UP, foot_yaw[side]) * Vector3(0, 0, -1)
	var center_m := m + fwd_m * foot_len * 0.36
	var w := lerpf(0.6, 1.0, run_factor)
	var sw := float(style.get("weight", 1.0))
	w *= sw if sw > 1.0 else lerpf(1.0, sw, 0.5)
	if not moving:
		w *= 0.6
	planted.emit(side, xf * center_m, plant_yaw[side], w)
	if sg == 0.0:
		pass


func _teleport_foot(side: int, xf: Transform3D) -> void:
	is_planted[side] = true
	foot_pos[side] = idle_pos[side]
	foot_yaw[side] = idle_yaw[side]
	plant_world[side] = xf * foot_pos[side]
	plant_yaw[side] = _rig_yaw + foot_yaw[side]


## Feet released (airborne or an action owns the legs): follow the idle spots.
func _update_released(dt: float, xf: Transform3D) -> void:
	for side in 2:
		is_planted[side] = true
		foot_pos[side] = foot_pos[side].lerp(idle_pos[side], 1.0 - exp(-dt * 10.0))
		foot_yaw[side] = lerp_angle(foot_yaw[side], idle_yaw[side], 1.0 - exp(-dt * 10.0))
		foot_lift[side] = 0.0
		foot_pitch[side] = 0.0
		plant_world[side] = xf * foot_pos[side]
		plant_yaw[side] = _rig_yaw + foot_yaw[side]


## Writes feet (and, weighted by gait_w, the gait body motion) into `pose`.
## `pose` already holds the idle/stance pose of the current style.
func write_pose(pose: RigPose, feet_weight: float = 1.0) -> void:
	var heel := float(style.get("heel", 0.0)) * gait_w
	var ball_len := foot_len * 0.66
	for side in 2:
		var sg := SK.SIDE_SIGN[side]
		var rest := def.rest_pos[SK.FOOT[side]]
		var gp := foot_pos[side]
		var clip_y: float = (pose.v[P.FOOT_L + side] as Vector3).y * leg * (1.0 - gait_w)
		var pitch := foot_pitch[side]
		var raise := 0.0
		var fwd_shift := 0.0
		if is_planted[side]:
			var heel_a := deg_to_rad(16.0) * heel
			if moving:
				# Heel-to-toe roll: heel rises around the locked ball late in stance,
				# heel strike settles around the heel early in stance.
				var s := clampf(_foot_phase(side) / maxf(duty, 0.01), 0.0, 1.0)
				heel_a = maxf(heel_a, deg_to_rad(lerpf(22.0, 34.0, run_factor)) * smoothstep(0.5, 1.0, s))
				var strike := deg_to_rad(lerpf(12.0, 3.0, run_factor)) * (1.0 - heel) * (1.0 - smoothstep(0.0, 0.18, s))
				var heel_len := foot_len * 0.17
				raise += heel_len * sin(strike)
				pitch += rad_to_deg(strike)
			if heel_a > 0.0:
				raise += ball_len * sin(heel_a)
				fwd_shift += ball_len * (1.0 - cos(heel_a))
				pitch -= rad_to_deg(heel_a)
		var fdir := Basis(Vector3.UP, foot_yaw[side]) * Vector3(0, 0, -1)
		gp = gp + fdir * fwd_shift
		var ankle := Vector3(gp.x, rest.y + foot_lift[side] + clip_y + raise, gp.z)
		var off := ankle - rest
		var ch := Vector3(sg * off.x, off.y, -off.z) / leg
		var toe_out := -sg * rad_to_deg(foot_yaw[side])
		var cur_rot: Vector3 = pose.v[P.FOOT_ROT_L + side]
		var rot := Vector3(pitch, toe_out, 0.0)
		if feet_weight >= 0.999:
			pose.v[P.FOOT_L + side] = ch
			pose.v[P.FOOT_ROT_L + side] = Vector3(cur_rot.x * (1.0 - gait_w) + rot.x, rot.y, cur_rot.z * (1.0 - gait_w))
		else:
			pose.v[P.FOOT_L + side] = (pose.v[P.FOOT_L + side] as Vector3).lerp(ch, feet_weight)
			pose.v[P.FOOT_ROT_L + side] = cur_rot.lerp(rot, feet_weight)
	if gait_w <= 0.001:
		return
	_write_gait_body(pose, gait_w)


func _write_gait_body(pose: RigPose, w: float) -> void:
	var rs := speed * (0.889 / maxf(leg, 0.2))
	var st := style
	var ph := phase * TAU
	var bob_amp := RigStyles.param(st, "bob", rs)
	var walk_bob := -cos(2.0 * ph) * bob_amp
	var run_bob := -cos(2.0 * (ph - duty * PI)) * bob_amp
	var bob := lerpf(walk_bob, run_bob, run_factor)
	var drop := float(st.get("plant_drop", 0.0))
	if drop > 0.0:
		var pl := maxf(exp(-pow(fposmod(phase, 0.5) / 0.08, 2.0)), 0.0)
		bob -= drop * pl
	var sway := -sin(ph) * RigStyles.param(st, "sway", rs)
	var crouch := float(st.get("crouch", 0.0)) + 0.035 + 0.03 * run_factor
	var hips: Vector3 = pose.v[P.HIPS]
	pose.v[P.HIPS] = hips.lerp(Vector3(sway, bob - crouch, 0.0), w)
	var hy := -cos(ph) * RigStyles.param(st, "hip_yaw", rs)
	var hr := sin(ph) * RigStyles.param(st, "hip_roll", rs)
	var lean := RigStyles.param(st, "lean", rs)
	# Acceleration lean and banking into turns.
	var fwd_acc := -accel.z
	lean += clampf(fwd_acc * 1.6, -10.0, 12.0)
	var bank := clampf(rad_to_deg(atan(speed * turn_rate / 9.8)), -22.0, 22.0)
	# Strafe: hips turn toward travel, chest keeps facing forward.
	var travel := atan2(-vel.x, -vel.z) if speed > 0.3 else 0.0
	var strafe := 0.0
	if absf(travel) < 2.3:
		strafe = rad_to_deg(clampf(travel, -0.7, 0.7)) * 0.5
	else:
		strafe = rad_to_deg(clampf(wrapf(travel + PI, -PI, PI), -0.6, 0.6)) * 0.35
		lean = -lean * 0.35
	var hrot: Vector3 = pose.v[P.HIPS_ROT]
	pose.v[P.HIPS_ROT] = hrot.lerp(Vector3(lean * 0.25, hy + strafe, hr + bank * 0.4), w)
	var sp: Vector3 = pose.v[P.SPINE]
	pose.v[P.SPINE] = sp.lerp(Vector3(lean * 0.35, -hy * 0.5 - strafe * 0.5, -hr * 0.6 + bank * 0.3), w)
	var ch: Vector3 = pose.v[P.CHEST]
	var chest_out := float(st.get("chest_out", 0.0))
	pose.v[P.CHEST] = ch.lerp(Vector3(lean * 0.4 - chest_out, -hy * 0.7 - strafe * 0.5, -hr * 0.4 + bank * 0.2), w)
	var hd: Vector3 = pose.v[P.HEAD]
	var head := float(st.get("head", 0.0))
	pose.v[P.HEAD] = hd.lerp(Vector3(head - lean * 0.75, hy * 0.3, -bank * 0.3), w)
	_write_arms(pose, w, rs)


func _write_arms(pose: RigPose, w: float, rs: float) -> void:
	var st := style
	var amp := RigStyles.param(st, "arm_swing", rs)
	var bend := RigStyles.param(st, "arm_bend", rs)
	var out := float(st.get("arm_out", 0.1))
	var trail := float(st.get("arm_trail", 0.0)) * run_factor
	var flt := float(st.get("arm_float", 0.0))
	var fist := float(st.get("fist", 0.3))
	var hands_back := float(st.get("hands_back", 0.0)) * (1.0 - run_factor * 0.8)
	var ph := phase * TAU
	for side in 2:
		# Right arm swings forward with the left leg.
		var s := cos(ph) if side == 1 else -cos(ph)
		var alpha := s * amp * 1.4 - trail
		var theta := bend * 1.45 + maxf(s, 0.0) * bend * 0.35
		var fwd := 0.53 * sin(alpha) + 0.47 * sin(alpha + theta)
		var up := -(0.53 * cos(alpha) + 0.47 * cos(alpha + theta))
		var hand := Vector3(out + 0.04 * absf(s), up, fwd)
		if flt > 0.0:
			var c := ph * 0.5 + (0.0 if side == 0 else PI)
			hand += Vector3(0.05 * sin(c), flt + 0.05 * cos(c), flt * 1.3)
		if hands_back > 0.0:
			hand = hand.lerp(Vector3(-0.22, -0.62, -0.36), hands_back)
		pose.v[P.HAND_L + side] = (pose.v[P.HAND_L + side] as Vector3).lerp(hand, w)
		pose.v[P.ELBOW_L + side] = (pose.v[P.ELBOW_L + side] as Vector3).lerp(Vector3(0.35 + hands_back * 0.6, -0.4, -1.0), w)
		pose.v[P.FIST_L + side] = lerpf(pose.v[P.FIST_L + side], fist, w)
		pose.v[P.WRIST_L + side] = (pose.v[P.WRIST_L + side] as Vector3).lerp(Vector3(lerpf(5.0, 15.0, run_factor), 10.0, 0.0), w)
