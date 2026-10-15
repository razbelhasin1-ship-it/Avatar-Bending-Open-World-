class_name RigSolver
extends RefCounted
## Converts a RigPose into bone-local rotations: FK for the spine/neck/head,
## analytic two-bone IK for arms and legs (with elbow/knee poles, forearm
## twist, toe-off heel pivot, ground alignment), finger curl, face scales.
## Keeps its own model-space bone globals so other layers (springs, sockets,
## footsteps) can read them without querying the Skeleton3D.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")
const P = preload("res://src/characters/anim/rig_pose.gd")

var def: RigSkeletonDef
var count := 0
var parents := PackedInt32Array()
var rest_off := PackedVector3Array()
var local_rot: Array[Basis] = []
var local_pos := PackedVector3Array()
var local_scale := PackedVector3Array()
var g_basis: Array[Basis] = []
var g_pos := PackedVector3Array()

## Inputs from the ground layer (model space), per side.
var ground_dy := PackedFloat32Array([0.0, 0.0])
var ground_n: Array[Vector3] = [Vector3.UP, Vector3.UP]
var ground_w := PackedFloat32Array([0.0, 0.0])
var hips_drop := 0.0
var blink := 0.0
## Heel lift applied by the toe pivot last solve (radians), per side.
var heel_lift := PackedFloat32Array([0.0, 0.0])
## Thigh swing (radians, forward +) and abduction per side, for skirts.
var thigh_swing := PackedFloat32Array([0.0, 0.0])
var thigh_abduct := PackedFloat32Array([0.0, 0.0])

var _foot_fwd_len := [0.0, 0.0]


func setup(d: RigSkeletonDef) -> void:
	def = d
	count = d.bone_count()
	parents = d.parents
	rest_off.resize(count)
	local_pos.resize(count)
	local_scale.resize(count)
	g_pos.resize(count)
	local_rot.resize(count)
	g_basis.resize(count)
	for i in count:
		rest_off[i] = d.local_rest(i).origin
		local_pos[i] = rest_off[i]
		local_scale[i] = Vector3.ONE
		local_rot[i] = Basis.IDENTITY
		g_basis[i] = Basis.IDENTITY
		g_pos[i] = d.rest_pos[i]
	for side in 2:
		_foot_fwd_len[side] = d.rest_pos[SK.TOES[side]].distance_to(d.rest_pos[SK.FOOT[side]])


static func euler(e: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-e.x), deg_to_rad(e.y), deg_to_rad(e.z)), EULER_ORDER_YXZ)


func _fk(i: int) -> void:
	var par := parents[i]
	if par < 0:
		g_basis[i] = local_rot[i]
		g_pos[i] = local_pos[i]
		return
	g_pos[i] = g_pos[par] + g_basis[par] * local_pos[i]
	g_basis[i] = g_basis[par] * local_rot[i]


## Solves the pose into local rotations and model-space globals.
func solve(pose: RigPose) -> void:
	var leg := def.leg_len
	var v := pose.v
	# Torso chain.
	var hp: Vector3 = v[P.HIPS]
	local_pos[SK.HIPS] = rest_off[SK.HIPS] + Vector3(hp.x, hp.y, -hp.z) * leg + Vector3(0, -hips_drop, 0)
	local_rot[SK.HIPS] = euler(v[P.HIPS_ROT])
	local_rot[SK.SPINE] = euler(v[P.SPINE])
	var ch: Vector3 = v[P.CHEST]
	local_rot[SK.CHEST] = euler(ch * 0.5)
	local_rot[SK.UPPER_CHEST] = euler(ch * 0.5)
	local_rot[SK.NECK] = euler(v[P.NECK])
	local_rot[SK.HEAD] = euler(v[P.HEAD])
	for i in [SK.ROOT, SK.HIPS, SK.SPINE, SK.CHEST, SK.UPPER_CHEST, SK.NECK, SK.HEAD]:
		_fk(i)
	# Face.
	var eye_s := Vector3(1.0, maxf(1.0 - blink * 0.94, 0.05), 1.0)
	local_scale[SK.EYE_L] = eye_s
	local_scale[SK.EYE_R] = eye_s
	var m: float = clampf(v[P.MOUTH], 0.0, 1.0)
	local_scale[SK.MOUTH] = Vector3(1.0 - 0.15 * m, 1.0 + 3.2 * m, 1.0)
	for i in [SK.EYE_L, SK.EYE_R, SK.MOUTH]:
		_fk(i)
	for side in 2:
		_solve_arm(side, pose)
	for side in 2:
		_solve_leg(side, pose)


func _solve_arm(side: int, pose: RigPose) -> void:
	var v := pose.v
	var sg := SK.SIDE_SIGN[side]
	var clav := SK.CLAVICLE[side]
	var ua := SK.UPPERARM[side]
	var fa := SK.FOREARM[side]
	var hd := SK.HAND[side]
	var cv: Vector3 = v[P.CLAV_L + side]
	local_rot[clav] = Basis(Vector3.UP, deg_to_rad(sg * cv.y)) * Basis(Vector3.BACK, deg_to_rad(-sg * cv.x))
	_fk(clav)
	# Upper arm head position (does not depend on its own rotation).
	var a := g_pos[clav] + g_basis[clav] * rest_off[ua]
	var buc := g_basis[SK.UPPER_CHEST]
	var hv: Vector3 = v[P.HAND_L + side]
	var ev: Vector3 = v[P.ELBOW_L + side]
	var target := a + buc * (Vector3(sg * hv.x, hv.y, -hv.z) * def.arm_len)
	var pole := buc * Vector3(sg * ev.x, ev.y, -ev.z)
	var l1 := def.upper_arm_len
	var l2 := def.forearm_len
	var u0 := (def.rest_pos[fa] - def.rest_pos[ua]).normalized()
	var p0 := Vector3.BACK
	var res := two_bone(a, target, pole, l1, l2, buc * Vector3(0, -1, 0))
	var elbow: Vector3 = res[0]
	var wrist: Vector3 = res[1]
	var pperp: Vector3 = res[2]
	var x1 := (elbow - a).normalized()
	var r_up := _frame(x1, pperp) * _frame(u0, p0).transposed()
	var x2 := (wrist - elbow).normalized()
	var r_fore := _frame(x2, pperp) * _frame(u0, p0).transposed()
	var wv: Vector3 = v[P.WRIST_L + side]
	r_fore = Basis(x2, deg_to_rad(-sg * wv.y)) * r_fore
	local_rot[ua] = g_basis[clav].transposed() * r_up
	local_pos[ua] = rest_off[ua]
	_fk(ua)
	local_rot[fa] = r_up.transposed() * r_fore
	_fk(fa)
	var ca := def.curl_axis[side]
	var pn := def.palm_normal[side]
	local_rot[hd] = Basis(ca, deg_to_rad(wv.x)) * Basis(pn, deg_to_rad(-sg * wv.z * 0.0 + wv.z))
	_fk(hd)
	var fist: float = clampf(v[P.FIST_L + side], 0.0, 1.0)
	local_rot[SK.FINGERS[side]] = Basis(ca, fist * 1.45)
	local_rot[SK.FINGERTIPS[side]] = Basis(ca, fist * 1.7)
	local_rot[SK.THUMB[side]] = Basis(def.thumb_axis[side], fist * 0.9) * Basis(ca, fist * 0.35)
	_fk(SK.FINGERS[side])
	_fk(SK.FINGERTIPS[side])
	_fk(SK.THUMB[side])


func _solve_leg(side: int, pose: RigPose) -> void:
	var v := pose.v
	var sg := SK.SIDE_SIGN[side]
	var th := SK.THIGH[side]
	var sh := SK.SHIN[side]
	var ft := SK.FOOT[side]
	var to := SK.TOES[side]
	var hip := g_pos[SK.HIPS] + g_basis[SK.HIPS] * rest_off[th]
	var fv: Vector3 = v[P.FOOT_L + side]
	var kv: Vector3 = v[P.KNEE_L + side]
	var rv: Vector3 = v[P.FOOT_ROT_L + side]
	var target := def.rest_pos[ft] + Vector3(sg * fv.x, fv.y, -fv.z) * def.leg_len
	target.y += ground_dy[side]
	var pole := Vector3(sg * kv.x, kv.y, -kv.z)
	# Foot orientation in model space (yaw/pitch/roll + ground tilt).
	var r_foot := Basis(Vector3.UP, deg_to_rad(-sg * rv.y)) * Basis(Vector3.RIGHT, deg_to_rad(rv.x)) * Basis(Vector3.BACK, deg_to_rad(sg * rv.z))
	var gw := ground_w[side]
	if gw > 0.001 and ground_n[side].dot(Vector3.UP) < 0.9999:
		var q := Quaternion(Vector3.UP, ground_n[side].normalized())
		r_foot = Basis(Quaternion.IDENTITY.slerp(q, gw)) * r_foot
	var l1 := def.thigh_len
	var l2 := def.shin_len
	var reach := (l1 + l2) * 0.997
	# Out of reach: a trailing foot lifts its heel around the ball (toe-off); a
	# leading foot rotates toe-up around the heel (heel strike).
	heel_lift[side] = 0.0
	if hip.distance_to(target) > reach:
		var leading := (target - hip).dot(g_basis[SK.HIPS] * Vector3.FORWARD) > 0.0
		var pivot_off: Vector3
		if leading:
			pivot_off = r_foot * Vector3(0, -def.rest_pos[ft].y * 0.6, float(def.p["foot"]) * float(def.p["height"]) * 0.17)
		else:
			pivot_off = r_foot * (def.rest_pos[to] - def.rest_pos[ft])
		var pivot := target + pivot_off
		var axis := r_foot * Vector3.RIGHT
		var sgn := 1.0 if leading else -1.0
		var lo := 0.0
		var hi := 1.1
		for k in 10:
			var mid := (lo + hi) * 0.5
			var ank := pivot + Basis(axis, sgn * mid) * (-pivot_off)
			if hip.distance_to(ank) > reach:
				lo = mid
			else:
				hi = mid
		target = pivot + Basis(axis, sgn * hi) * (-pivot_off)
		r_foot = Basis(axis, sgn * hi) * r_foot
		if not leading:
			heel_lift[side] = hi
	var res := two_bone(hip, target, pole, l1, l2, Vector3(0, 0, -1))
	var knee: Vector3 = res[0]
	var ankle: Vector3 = res[1]
	var pperp: Vector3 = res[2]
	var u0 := (def.rest_pos[sh] - def.rest_pos[th]).normalized()
	var p0 := Vector3.FORWARD
	var x1 := (knee - hip).normalized()
	var r_th := _frame(x1, pperp) * _frame(u0, p0).transposed()
	var x2 := (ankle - knee).normalized()
	var u1 := (def.rest_pos[ft] - def.rest_pos[sh]).normalized()
	var r_sh := _frame(x2, pperp) * _frame(u1, p0).transposed()
	local_rot[th] = g_basis[SK.HIPS].transposed() * r_th
	_fk(th)
	local_rot[sh] = r_th.transposed() * r_sh
	_fk(sh)
	local_rot[ft] = r_sh.transposed() * r_foot
	_fk(ft)
	var toe_deg: float = v[P.TOE_L + side]
	local_rot[to] = Basis(Vector3.RIGHT, deg_to_rad(toe_deg) + heel_lift[side])
	_fk(to)
	# Thigh swing relative to the hips (for skirts): angle of the thigh in the hips' sagittal plane.
	var hb := g_basis[SK.HIPS]
	var dl := hb.transposed() * x1
	thigh_swing[side] = atan2(-dl.z, -dl.y)
	thigh_abduct[side] = atan2(dl.x * sg, -dl.y)


## Orthonormal frame with X along `x` and Y toward `p` (made perpendicular).
static func _frame(x: Vector3, p: Vector3) -> Basis:
	var xn := x.normalized()
	var y := p - xn * p.dot(xn)
	if y.length_squared() < 1e-10:
		y = xn.cross(Vector3.RIGHT if absf(xn.x) < 0.9 else Vector3.UP)
	y = y.normalized()
	return Basis(xn, y, xn.cross(y))


## Analytic two-bone IK. Returns [mid joint, end, pole direction (perpendicular)].
static func two_bone(a: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float, fallback_pole: Vector3) -> Array:
	var to := target - a
	var dist := to.length()
	var dir := to / dist if dist > 1e-6 else Vector3.DOWN
	var d := clampf(dist, absf(l1 - l2) + 0.001, (l1 + l2) * 0.9995)
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sa := sqrt(1.0 - ca * ca)
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-8:
		pp = fallback_pole - dir * fallback_pole.dot(dir)
		if pp.length_squared() < 1e-8:
			pp = dir.cross(Vector3.RIGHT)
	pp = pp.normalized()
	var mid := a + dir * (ca * l1) + pp * (sa * l1)
	var end := a + dir * d
	return [mid, end, pp]


## Writes the solved locals into the skeleton.
func apply(sk: Skeleton3D, hips_dirty: bool = true) -> void:
	for i in count:
		sk.set_bone_pose_rotation(i, local_rot[i].get_rotation_quaternion())
	if hips_dirty:
		sk.set_bone_pose_position(SK.HIPS, local_pos[SK.HIPS])
	for i in [SK.EYE_L, SK.EYE_R, SK.MOUTH]:
		sk.set_bone_pose_scale(i, local_scale[i])


## Model-space transform of a bone after the last solve.
func bone_global(i: int) -> Transform3D:
	return Transform3D(g_basis[i], g_pos[i])
