class_name CreatureMotor
extends RefCounted
## Generic procedural body animation for legged creatures (quadrupeds, the six-legged
## sky bison, bipeds). Turns CreaturePose channels into bone rotations:
## body (around a pivot) -> spine chain -> neck chain -> stabilized head -> jaw, eyes,
## lids, ears, tail; then solves leg IK toward the GaitEngine's feet and runs the
## spring chains. Species configure the bone map and tuning in their build().

var skel: RigSkeleton
var root := -1
var pelvis := -1
## Spine bones from behind the pelvis forward; the last one is the chest.
var spine := PackedInt32Array()
var neck := PackedInt32Array()
var head := -1
var jaw := -1
var tail := PackedInt32Array()
var ear_l := -1
var ear_r := -1
var eye_l := -1
var eye_r := -1
var lid_l := -1
var lid_r := -1
## Bones scaled by breathing (chest/belly).
var breath_bones := PackedInt32Array()
var breath_scale := Vector3(0.025, 0.03, 0.01)

## Body pivot positions along Z (rig space): hind hips and front shoulders.
var hind_z := 1.0
var front_z := -1.0
## How the neck rotation is distributed (weights per neck bone, sums ~1).
var neck_weights := PackedFloat32Array()
var head_stab := 0.65
var jaw_open := 0.55
## Lid rotation (radians about X) when fully open / closed.
var lid_open := 0.85
var lid_closed := -0.25
var eye_limit := 0.45
## Ear rotation axis per side is local Z (flop sideways) and X (pin back).
var ear_back_angle := 0.9
var ear_flop := 0.0
var look_yaw_limit := 1.2
var look_pitch_limit := 0.6
## Fraction of the look yaw/pitch taken by the neck (the rest by the head).
var look_neck_share := 0.55

## Optional species body solver called after the pose reset instead of the pelvis/spine
## code (e.g. the dragon's trail-following spine). Signature: func(pose: CreaturePose).
var body_override: Callable = Callable()
var springs: Array[SpringChain] = []
## Animation clock (seconds), set by the rig every frame.
var time := 0.0
## Optional per-bone static rotation offsets applied on top of channels (name -> Quaternion).
var bone_offsets: Dictionary = {}

## Look target in rig space; weight 0..1.
var look_yaw := 0.0
var look_pitch := 0.0
var eye_target_rig := Vector3.ZERO
var eye_target_w := 0.0


func setup(s: RigSkeleton) -> void:
	skel = s


## Poses body, spine, neck, head, face and tail from `pose` (FK included).
func pose_body(pose: CreaturePose) -> void:
	skel.reset_pose()
	for bi: int in bone_offsets:
		skel.rot[bi] = bone_offsets[bi]
	# --- Body around its pivot (half the spine bend is taken by the pelvis so the
	# creature curves about its middle).
	var pivot_z := lerpf(lerpf(hind_z, front_z, 0.5), front_z if pose.pitch_pivot > 0.0 else hind_z, absf(pose.pitch_pivot))
	if body_override.is_valid():
		body_override.call(pose)
	elif pelvis >= 0:
		var p0 := skel.rest_pos[pelvis]
		var pivot := Vector3(0.0, p0.y, pivot_z)
		var rb := Basis.from_euler(Vector3(pose.body_pitch - pose.spine_pitch * 0.5,
				pose.body_yaw - pose.spine_yaw * 0.5, -pose.body_roll))
		var body := Transform3D(Basis.IDENTITY, Vector3(pose.body_x, pose.body_y, pose.body_z) + pivot) \
				* Transform3D(rb, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
		var pelvis_parent := skel.parent[pelvis]
		var base := Transform3D.IDENTITY
		if pelvis_parent >= 0:
			skel.fk_list(PackedInt32Array([pelvis_parent]))
			base = skel.glob[pelvis_parent]
		var want := body * Transform3D(Basis.IDENTITY, p0)
		var local := base.affine_inverse() * want
		skel.rot[pelvis] = local.basis.get_rotation_quaternion()
		skel.off[pelvis] = local.origin - skel.rest_off[pelvis]
	# --- Spine
	var ns := spine.size()
	for k in ns:
		var f := 1.0 / maxf(ns, 1)
		var q := Quaternion.from_euler(Vector3(pose.spine_pitch * f, pose.spine_yaw * f, -pose.spine_roll * f))
		skel.rot[spine[k]] = skel.rot[spine[k]] * q
	# --- Neck (arc + share of the look)
	var nn := neck.size()
	for k in nn:
		var w := neck_weights[k] if k < neck_weights.size() else 1.0 / maxf(nn, 1)
		var q := Quaternion.from_euler(Vector3((pose.neck_pitch + look_pitch * look_neck_share) * w,
				(pose.neck_yaw + look_yaw * look_neck_share) * w, 0.0))
		skel.rot[neck[k]] = skel.rot[neck[k]] * q
	# --- Tail channels (springs add the lag afterwards)
	var nt := tail.size()
	for k in nt:
		var f := float(k + 1) / maxf(nt, 1)
		var wag := pose.tail_wag * sin(time * pose.tail_wag_speed * TAU - k * 0.9)
		var q := Quaternion.from_euler(Vector3(pose.tail_pitch / maxf(nt, 1) + pose.tail_curl * f / maxf(nt, 1),
				pose.tail_yaw / maxf(nt, 1) + wag * (0.5 + f), 0.0))
		skel.rot[tail[k]] = skel.rot[tail[k]] * q
	# --- Jaw, ears, lids
	if jaw >= 0:
		skel.rot[jaw] = skel.rot[jaw] * Quaternion(Vector3.RIGHT, -pose.jaw * jaw_open)
	if ear_l >= 0:
		skel.rot[ear_l] = skel.rot[ear_l] * Quaternion.from_euler(Vector3(pose.ears_back * ear_back_angle + pose.ear_l * 0.5, 0.0, pose.ear_l * 0.35 + ear_flop))
	if ear_r >= 0:
		skel.rot[ear_r] = skel.rot[ear_r] * Quaternion.from_euler(Vector3(pose.ears_back * ear_back_angle + pose.ear_r * 0.5, 0.0, -pose.ear_r * 0.35 - ear_flop))
	var lid := lerpf(lid_open, lid_closed, clampf(maxf(pose.blink, pose.eyes_narrow * 0.55), 0.0, 1.0))
	if lid_l >= 0:
		skel.rot[lid_l] = Quaternion(Vector3.RIGHT, lid)
	if lid_r >= 0:
		skel.rot[lid_r] = Quaternion(Vector3.RIGHT, lid)
	# --- Breathing (non-inherited scale)
	for bi in breath_bones:
		var b := pose.breath
		skel.set_scale(bi, Vector3.ONE + breath_scale * b)
	skel.fk()
	# --- Head: blend between following the neck and staying level (stabilized).
	if head >= 0:
		var free_b := skel.glob[head].basis * Basis.from_euler(Vector3(pose.head_pitch + look_pitch * (1.0 - look_neck_share),
				pose.head_yaw + look_yaw * (1.0 - look_neck_share), pose.head_roll))
		var stab := clampf(head_stab + pose.head_stab, 0.0, 1.0)
		var hb := free_b
		if stab > 0.0:
			var fwd := -free_b.z
			var yaw := atan2(-fwd.x, -fwd.z)
			var rest_pitch := 0.0
			for k in nn:
				var w := neck_weights[k] if k < neck_weights.size() else 1.0 / maxf(nn, 1)
				rest_pitch += (pose.neck_pitch + look_pitch * look_neck_share) * w
			var level := Basis.from_euler(Vector3(rest_pitch + pose.head_pitch + look_pitch * (1.0 - look_neck_share), yaw, pose.head_roll))
			hb = Basis(free_b.get_rotation_quaternion().slerp(level.get_rotation_quaternion(), stab))
		skel.set_global_basis(head, hb)
		skel.fk_list(skel_subtree(head))
	# --- Eyes look at the target.
	if eye_target_w > 0.0:
		for e in [eye_l, eye_r]:
			if e < 0:
				continue
			var g := skel.glob[e]
			var d := eye_target_rig - g.origin
			if d.length_squared() < 1e-6:
				continue
			var local_d := (skel.glob[skel.parent[e]].basis.transposed() * d).normalized()
			var q := Quaternion(Vector3.FORWARD, local_d)
			var ang := q.get_angle()
			if ang > eye_limit:
				q = Quaternion.IDENTITY.slerp(q, eye_limit / ang)
			skel.rot[e] = Quaternion.IDENTITY.slerp(q, eye_target_w)
		skel.fk_list(skel_subtree(head))


var _subtree_cache: Dictionary = {}


func skel_subtree(i: int) -> PackedInt32Array:
	if not _subtree_cache.has(i):
		_subtree_cache[i] = skel.subtree(i)
	return _subtree_cache[i]


## Solves every leg toward its gait/free target. `xf` = rig global transform.
func pose_legs(legs: Array[CreatureLeg], pose: CreaturePose, xf: Transform3D) -> void:
	var inv := xf.affine_inverse()
	for l in legs:
		var parent_b := skel.glob[skel.parent[l.upper]].basis
		var hip := skel.glob[l.upper].origin
		var ground_t := inv * (l.foot_world + Vector3.UP * l.ankle_h)
		var free_t := hip + parent_b * l.tuck
		var off: Vector3 = pose.paw_offsets.get(l.index, Vector3.ZERO)
		var target := ground_t.lerp(free_t + off, l.free) if l.free > 0.0 else ground_t
		if l.free <= 0.0 and off != Vector3.ZERO:
			target += off
		var n := (inv.basis * l.ground_normal).normalized()
		l.solve(skel, target, parent_b, n)
		l.paw_world = xf * target - Vector3.UP * l.ankle_h
	# Children of the leg chains (toes, claws) follow.
	for l in legs:
		skel.fk_list(skel_subtree(l.foot))


func update_springs(xf: Transform3D, delta: float) -> void:
	for s in springs:
		s.update(skel, xf, delta)
		var last := s.bones[s.bones.size() - 1]
		skel.fk_list(skel_subtree(last))
