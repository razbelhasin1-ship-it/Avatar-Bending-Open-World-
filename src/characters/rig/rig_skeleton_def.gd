class_name RigSkeletonDef
extends RefCounted
## Core humanoid bone layout and rest positions computed from body proportions.
##
## Every bone rest has an IDENTITY rotation, so a bone's local axes are the model
## axes (+X = character right, +Y = up, -Z = forward) in rest pose. Poses are
## therefore easy to author and to solve procedurally. Core bones always occupy
## the indices below; outfit secondary bones (cloth/hair springs) are appended.

const ROOT := 0
const HIPS := 1
const SPINE := 2
const CHEST := 3
const UPPER_CHEST := 4
const NECK := 5
const HEAD := 6
const EYE_L := 7
const EYE_R := 8
const MOUTH := 9
const CLAVICLE_L := 10
const UPPERARM_L := 11
const FOREARM_L := 12
const HAND_L := 13
const FINGERS_L := 14
const FINGERTIPS_L := 15
const THUMB_L := 16
const CLAVICLE_R := 17
const UPPERARM_R := 18
const FOREARM_R := 19
const HAND_R := 20
const FINGERS_R := 21
const FINGERTIPS_R := 22
const THUMB_R := 23
const THIGH_L := 24
const SHIN_L := 25
const FOOT_L := 26
const TOES_L := 27
const THIGH_R := 28
const SHIN_R := 29
const FOOT_R := 30
const TOES_R := 31
const CORE_COUNT := 32

const NAMES: PackedStringArray = [
	"root", "hips", "spine", "chest", "upper_chest", "neck", "head", "eye_l", "eye_r", "mouth",
	"clavicle_l", "upperarm_l", "forearm_l", "hand_l", "fingers_l", "fingertips_l", "thumb_l",
	"clavicle_r", "upperarm_r", "forearm_r", "hand_r", "fingers_r", "fingertips_r", "thumb_r",
	"thigh_l", "shin_l", "foot_l", "toes_l", "thigh_r", "shin_r", "foot_r", "toes_r",
]
const PARENTS: PackedInt32Array = [
	-1, ROOT, HIPS, SPINE, CHEST, UPPER_CHEST, NECK, HEAD, HEAD, HEAD,
	UPPER_CHEST, CLAVICLE_L, UPPERARM_L, FOREARM_L, HAND_L, FINGERS_L, HAND_L,
	UPPER_CHEST, CLAVICLE_R, UPPERARM_R, FOREARM_R, HAND_R, FINGERS_R, HAND_R,
	HIPS, THIGH_L, SHIN_L, FOOT_L, HIPS, THIGH_R, SHIN_R, FOOT_R,
]

## Arm chains indexed by side (0 = left, 1 = right).
const CLAVICLE: PackedInt32Array = [CLAVICLE_L, CLAVICLE_R]
const UPPERARM: PackedInt32Array = [UPPERARM_L, UPPERARM_R]
const FOREARM: PackedInt32Array = [FOREARM_L, FOREARM_R]
const HAND: PackedInt32Array = [HAND_L, HAND_R]
const FINGERS: PackedInt32Array = [FINGERS_L, FINGERS_R]
const FINGERTIPS: PackedInt32Array = [FINGERTIPS_L, FINGERTIPS_R]
const THUMB: PackedInt32Array = [THUMB_L, THUMB_R]
const THIGH: PackedInt32Array = [THIGH_L, THIGH_R]
const SHIN: PackedInt32Array = [SHIN_L, SHIN_R]
const FOOT: PackedInt32Array = [FOOT_L, FOOT_R]
const TOES: PackedInt32Array = [TOES_L, TOES_R]
const EYE: PackedInt32Array = [EYE_L, EYE_R]
## Side sign: left = -1 (-X), right = +1 (+X).
const SIDE_SIGN: PackedFloat32Array = [-1.0, 1.0]

## Canonical standing heights per body/age; the rig scales from these.
const CANON_HEIGHT := {
	"male": {"adult": 1.76, "elder": 1.70, "teen": 1.52, "child": 1.18},
	"female": {"adult": 1.66, "elder": 1.60, "teen": 1.48, "child": 1.16},
}

## Arm abduction of the rest (bind) pose in degrees from vertical.
const ARM_REST_DEG := 16.0

var names: PackedStringArray = PackedStringArray()
var parents: PackedInt32Array = PackedInt32Array()
## Global rest position (model space) of every bone head.
var rest_pos: PackedVector3Array = PackedVector3Array()
## Body proportions (meters + shape ratios) used by the mesh builders.
var p: Dictionary = {}
## Reference points (model space): fingertip, toe tips, heel, crown, chin...
var ref: Dictionary = {}
## Finger curl axes per side (model space at rest).
var curl_axis: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var thumb_axis: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Rest arm direction (shoulder -> wrist) per side.
var arm_dir: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Rest palm normal per side.
var palm_normal: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

var upper_arm_len := 0.0
var forearm_len := 0.0
var thigh_len := 0.0
var shin_len := 0.0
## Hip joint height above the soles at rest (leg length incl. ankle height).
var leg_len := 0.0
var arm_len := 0.0


## Body proportions for `body` ("male"/"female"), `age` ("adult", "teen",
## "child", "elder") and `bulk` (-1 slim .. +1 heavy/muscular).
static func make_proportions(body: String, age: String, bulk: float) -> Dictionary:
	var female := body == "female"
	var h: float = CANON_HEIGHT.get(body, CANON_HEIGHT["male"]).get(age, 1.76)
	var d := {
		"body": body, "age": age, "bulk": bulk, "height": h, "female": female,
		"head_ratio": 6.5, "leg": 0.505, "shoulder_x": 0.101, "hip_x": 0.049,
		"upper_arm": 0.168, "forearm": 0.146, "hand": 0.104, "foot": 0.148,
		# Mesh shape ratios (fractions of height unless noted).
		"chest_w": 0.1, "chest_d": 0.058, "waist_w": 0.078, "waist_d": 0.050,
		"hip_w": 0.086, "hip_d": 0.056, "neck_r": 0.034, "limb": 1.0,
		"head_w": 0.94, "jaw": 0.74, "eye_size": 1.0, "bust": 0.0,
	}
	if female:
		d["head_ratio"] = 6.3
		d["leg"] = 0.51
		d["shoulder_x"] = 0.094
		d["hip_x"] = 0.051
		d["upper_arm"] = 0.163
		d["forearm"] = 0.141
		d["hand"] = 0.098
		d["foot"] = 0.138
		d["chest_w"] = 0.085
		d["chest_d"] = 0.056
		d["waist_w"] = 0.066
		d["waist_d"] = 0.045
		d["hip_w"] = 0.098
		d["hip_d"] = 0.060
		d["neck_r"] = 0.029
		d["limb"] = 0.86
		d["head_w"] = 0.9
		d["jaw"] = 0.62
		d["eye_size"] = 1.1
		d["bust"] = 1.0
	match age:
		"teen":
			d["head_ratio"] = float(d["head_ratio"]) - 0.75
			d["leg"] = float(d["leg"]) - 0.012
			d["shoulder_x"] = float(d["shoulder_x"]) * 0.93
			d["chest_w"] = float(d["chest_w"]) * 0.92
			d["limb"] = float(d["limb"]) * 0.88
			d["jaw"] = float(d["jaw"]) * 0.9
			d["eye_size"] = float(d["eye_size"]) * 1.12
			d["bust"] = float(d["bust"]) * 0.4
		"child":
			d["head_ratio"] = 4.8
			d["leg"] = 0.45
			d["shoulder_x"] = 0.098
			d["hip_x"] = 0.055
			d["upper_arm"] = 0.155
			d["forearm"] = 0.135
			d["hand"] = 0.095
			d["chest_w"] = 0.098
			d["chest_d"] = 0.066
			d["waist_w"] = 0.094
			d["waist_d"] = 0.066
			d["hip_w"] = 0.096
			d["hip_d"] = 0.064
			d["limb"] = 0.98
			d["neck_r"] = 0.036
			d["jaw"] = 0.68
			d["eye_size"] = 1.22
			d["bust"] = 0.0
		"elder":
			d["shoulder_x"] = float(d["shoulder_x"]) * 0.96
			d["limb"] = float(d["limb"]) * 0.92
			d["waist_w"] = float(d["waist_w"]) * 1.05
			d["eye_size"] = float(d["eye_size"]) * 0.88
			d["bust"] = float(d["bust"]) * 0.6
	var b := clampf(bulk, -1.0, 1.0)
	d["chest_w"] = float(d["chest_w"]) * (1.0 + 0.10 * b)
	d["chest_d"] = float(d["chest_d"]) * (1.0 + 0.12 * b)
	d["waist_w"] = float(d["waist_w"]) * (1.0 + 0.20 * b)
	d["waist_d"] = float(d["waist_d"]) * (1.0 + 0.30 * b)
	d["hip_w"] = float(d["hip_w"]) * (1.0 + 0.08 * b)
	d["limb"] = float(d["limb"]) * (1.0 + 0.16 * b)
	d["shoulder_x"] = float(d["shoulder_x"]) * (1.0 + 0.05 * b)
	return d


## Builds the rest layout from proportions (see make_proportions()).
func build(props: Dictionary) -> RigSkeletonDef:
	p = props
	var h: float = p["height"]
	names = NAMES.duplicate()
	parents = PARENTS.duplicate()
	rest_pos.resize(CORE_COUNT)
	var head_h: float = h / float(p["head_ratio"])
	var ankle_y := 0.043 * h
	var hip_y: float = float(p["leg"]) * h
	var knee_y := ankle_y + (hip_y - ankle_y) * 0.49
	var chin_y := h - head_h
	var shoulder_y := chin_y - 0.034 * h
	var neck_base_y := shoulder_y + 0.006 * h
	var hips_y := hip_y + 0.026 * h
	var sx: float = float(p["shoulder_x"]) * h
	var hx: float = float(p["hip_x"]) * h
	p["head_h"] = head_h
	p["chin_y"] = chin_y
	p["crown_y"] = h
	p["shoulder_y"] = shoulder_y
	p["neck_base_y"] = neck_base_y
	p["hip_y"] = hip_y
	p["hips_y"] = hips_y
	p["knee_y"] = knee_y
	p["ankle_y"] = ankle_y

	rest_pos[ROOT] = Vector3.ZERO
	rest_pos[HIPS] = Vector3(0, hips_y, 0.0)
	var torso := neck_base_y - hips_y
	rest_pos[SPINE] = Vector3(0, hips_y + torso * 0.26, 0.004 * h)
	rest_pos[CHEST] = Vector3(0, hips_y + torso * 0.52, 0.0)
	rest_pos[UPPER_CHEST] = Vector3(0, hips_y + torso * 0.77, 0.0)
	rest_pos[NECK] = Vector3(0, neck_base_y, 0.006 * h)
	rest_pos[HEAD] = Vector3(0, chin_y + head_h * 0.2, 0.002 * h)
	# Face feature pivots (head space reference: skull center).
	var skull_c := Vector3(0, chin_y + head_h * 0.53, 0.0)
	var head_rw := head_h * 0.5 * float(p["head_w"]) * 0.82
	var eye_y := chin_y + head_h * 0.42
	var eye_x := head_rw * 0.36
	var eye_z := -head_h * 0.43
	rest_pos[EYE_L] = Vector3(-eye_x, eye_y, eye_z)
	rest_pos[EYE_R] = Vector3(eye_x, eye_y, eye_z)
	rest_pos[MOUTH] = Vector3(0, chin_y + head_h * 0.17, -head_h * 0.40)
	p["skull_c"] = skull_c
	p["eye_y"] = eye_y

	upper_arm_len = float(p["upper_arm"]) * h
	forearm_len = float(p["forearm"]) * h
	var hand_len: float = float(p["hand"]) * h
	arm_len = upper_arm_len + forearm_len
	var a := deg_to_rad(ARM_REST_DEG)
	for side in 2:
		var s := SIDE_SIGN[side]
		var dir := Vector3(sin(a) * s, -cos(a), 0.0)
		arm_dir[side] = dir
		var pn := Vector3(-cos(a) * s, -sin(a), 0.0)
		palm_normal[side] = pn
		var shoulder := Vector3(sx * s, shoulder_y, 0.004 * h)
		rest_pos[CLAVICLE[side]] = Vector3(0.016 * h * s, neck_base_y - 0.012 * h, -0.016 * h)
		rest_pos[UPPERARM[side]] = shoulder
		var elbow := shoulder + dir * upper_arm_len
		var wrist := elbow + dir * forearm_len
		rest_pos[FOREARM[side]] = elbow
		rest_pos[HAND[side]] = wrist
		rest_pos[FINGERS[side]] = wrist + dir * hand_len * 0.47 + pn * hand_len * 0.03
		rest_pos[FINGERTIPS[side]] = wrist + dir * hand_len * 0.72 + pn * hand_len * 0.03
		rest_pos[THUMB[side]] = wrist + dir * hand_len * 0.12 + Vector3(0, 0, -hand_len * 0.13) + pn * hand_len * 0.05
		ref["fingertip_%d" % side] = wrist + dir * hand_len
		curl_axis[side] = dir.cross(pn).normalized()
		# Thumb folds across the palm: rotate toward the palm around the finger direction.
		thumb_axis[side] = dir.normalized() * s
		var hip_joint := Vector3(hx * s, hip_y, 0.0)
		rest_pos[THIGH[side]] = hip_joint
		rest_pos[SHIN[side]] = Vector3(hx * s, knee_y, -0.004 * h)
		rest_pos[FOOT[side]] = Vector3(hx * s, ankle_y, 0.0)
		var foot_len: float = float(p["foot"]) * h
		rest_pos[TOES[side]] = Vector3(hx * s, 0.013 * h, -foot_len * 0.66)
		ref["toe_tip_%d" % side] = Vector3(hx * s, 0.01 * h, -foot_len * 0.88)
		ref["heel_%d" % side] = Vector3(hx * s, 0.0, foot_len * 0.12)
	thigh_len = rest_pos[THIGH_L].distance_to(rest_pos[SHIN_L])
	shin_len = rest_pos[SHIN_L].distance_to(rest_pos[FOOT_L])
	leg_len = hip_y
	ref["crown"] = Vector3(0, h, 0)
	ref["chin"] = Vector3(0, chin_y, -head_h * 0.36)
	return self


func bone_count() -> int:
	return names.size()


## Rest transform of bone `i` relative to its parent (identity rotation).
func local_rest(i: int) -> Transform3D:
	var par := parents[i]
	var origin := rest_pos[i] - (rest_pos[par] if par >= 0 else Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, origin)


## Appends a secondary (spring/cloth) bone; returns its index.
func add_bone(bone_name: String, parent: int, pos: Vector3) -> int:
	names.append(bone_name)
	parents.append(parent)
	rest_pos.append(pos)
	return names.size() - 1


func find(bone_name: String) -> int:
	return names.find(bone_name)


## Creates and fills a Skeleton3D with this layout (poses reset to rest).
func create_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for i in names.size():
		sk.add_bone(names[i])
	for i in names.size():
		if parents[i] >= 0:
			sk.set_bone_parent(i, parents[i])
		sk.set_bone_rest(i, local_rest(i))
	sk.reset_bone_poses()
	return sk
