class_name RigPose
extends RefCounted
## A full-body pose expressed in intuitive, body-relative channels that blend
## linearly and solve onto any HumanoidRig regardless of proportions.
##
## Conventions (all "lateral" values are positive OUTWARD for limbs):
## * hips: Vector3 offset (right +, up +, forward +) in leg-length units.
## * hips_rot, spine, chest, neck, head: Euler degrees
##   (x = pitch forward +, y = yaw toward the character's left +, z = roll left +).
## * clav_l/clav_r: Vector3 degrees (x = raise/shrug +, y = forward +, z unused).
## * hand_l/hand_r: hand (wrist) position relative to the shoulder joint in the
##   upper-chest frame, in arm-length units (out +, up +, forward +).
##   (0.1, -0.95, 0.05) is a relaxed hanging arm; (0, 0, 1) a straight jab.
## * elbow_l/elbow_r: elbow pole direction (out, up, forward), e.g. (0.3, -1, -0.2).
## * wrist_l/wrist_r: degrees (x = flex toward palm +, y = pronation/twist +,
##   z = radial deviation +). Twist is applied to the forearm.
## * fist_l/fist_r: 0 open hand .. 1 closed fist (thumb follows).
## * foot_l/foot_r: ankle position relative to its rest spot under the hip, in
##   leg-length units (out +, up +, forward +).
## * knee_l/knee_r: knee pole direction (out, up, forward), default (0.15, 0, 1).
## * foot_rot_l/foot_rot_r: degrees (x = toes up +, y = toe-out +, z = outer edge up +).
## * toe_l/toe_r: toe bend degrees (+ = toes bent up).
## * mouth: 0 closed .. 1 open.  blink: 0 open .. 1 closed (face layer).

const HIPS := 0
const HIPS_ROT := 1
const SPINE := 2
const CHEST := 3
const NECK := 4
const HEAD := 5
const CLAV_L := 6
const CLAV_R := 7
const HAND_L := 8
const HAND_R := 9
const ELBOW_L := 10
const ELBOW_R := 11
const WRIST_L := 12
const WRIST_R := 13
const FIST_L := 14
const FIST_R := 15
const FOOT_L := 16
const FOOT_R := 17
const KNEE_L := 18
const KNEE_R := 19
const FOOT_ROT_L := 20
const FOOT_ROT_R := 21
const TOE_L := 22
const TOE_R := 23
const MOUTH := 24
const COUNT := 25

const NAMES: PackedStringArray = [
	"hips", "hips_rot", "spine", "chest", "neck", "head", "clav_l", "clav_r",
	"hand_l", "hand_r", "elbow_l", "elbow_r", "wrist_l", "wrist_r", "fist_l", "fist_r",
	"foot_l", "foot_r", "knee_l", "knee_r", "foot_rot_l", "foot_rot_r", "toe_l", "toe_r", "mouth",
]
## Channel indices that hold floats (the rest are Vector3).
const FLOAT_CHANNELS: PackedInt32Array = [FIST_L, FIST_R, TOE_L, TOE_R, MOUTH]
## Left/right channel pairs for mirroring.
const MIRROR_PAIRS: Array[Vector2i] = [
	Vector2i(CLAV_L, CLAV_R), Vector2i(HAND_L, HAND_R), Vector2i(ELBOW_L, ELBOW_R),
	Vector2i(WRIST_L, WRIST_R), Vector2i(FIST_L, FIST_R), Vector2i(FOOT_L, FOOT_R),
	Vector2i(KNEE_L, KNEE_R), Vector2i(FOOT_ROT_L, FOOT_ROT_R), Vector2i(TOE_L, TOE_R),
]
## Euler channels on the center line (yaw and roll flip when mirrored).
const CENTER_EULER: PackedInt32Array = [HIPS_ROT, SPINE, CHEST, NECK, HEAD]

## Masks: per-channel weights.
const MASKS := {
	&"full": [],
	&"upper": [HIPS_ROT, SPINE, CHEST, NECK, HEAD, CLAV_L, CLAV_R, HAND_L, HAND_R, ELBOW_L, ELBOW_R, WRIST_L, WRIST_R, FIST_L, FIST_R, MOUTH],
	&"arms": [CLAV_L, CLAV_R, HAND_L, HAND_R, ELBOW_L, ELBOW_R, WRIST_L, WRIST_R, FIST_L, FIST_R],
	&"arm_l": [CLAV_L, HAND_L, ELBOW_L, WRIST_L, FIST_L],
	&"arm_r": [CLAV_R, HAND_R, ELBOW_R, WRIST_R, FIST_R],
	&"legs": [HIPS, HIPS_ROT, FOOT_L, FOOT_R, KNEE_L, KNEE_R, FOOT_ROT_L, FOOT_ROT_R, TOE_L, TOE_R],
	&"head": [NECK, HEAD, MOUTH],
}

var v: Array = []


func _init() -> void:
	v.resize(COUNT)
	set_neutral()


static func channel_index(channel_name: String) -> int:
	return NAMES.find(channel_name)


static func is_float_channel(i: int) -> bool:
	return FLOAT_CHANNELS.has(i)


## Relaxed standing pose (arms hanging, feet under the hips).
func set_neutral() -> void:
	v[HIPS] = Vector3.ZERO
	v[HIPS_ROT] = Vector3.ZERO
	v[SPINE] = Vector3.ZERO
	v[CHEST] = Vector3.ZERO
	v[NECK] = Vector3.ZERO
	v[HEAD] = Vector3.ZERO
	v[CLAV_L] = Vector3.ZERO
	v[CLAV_R] = Vector3.ZERO
	v[HAND_L] = Vector3(0.1, -0.96, 0.04)
	v[HAND_R] = Vector3(0.1, -0.96, 0.04)
	v[ELBOW_L] = Vector3(0.25, 0.0, -1.0)
	v[ELBOW_R] = Vector3(0.25, 0.0, -1.0)
	v[WRIST_L] = Vector3.ZERO
	v[WRIST_R] = Vector3.ZERO
	v[FIST_L] = 0.25
	v[FIST_R] = 0.25
	v[FOOT_L] = Vector3.ZERO
	v[FOOT_R] = Vector3.ZERO
	v[KNEE_L] = Vector3(0.1, 0.0, 1.0)
	v[KNEE_R] = Vector3(0.1, 0.0, 1.0)
	v[FOOT_ROT_L] = Vector3.ZERO
	v[FOOT_ROT_R] = Vector3.ZERO
	v[TOE_L] = 0.0
	v[TOE_R] = 0.0
	v[MOUTH] = 0.0


func copy_from(o: RigPose) -> void:
	for i in COUNT:
		v[i] = o.v[i]


func duplicate_pose() -> RigPose:
	var p := RigPose.new()
	p.copy_from(self)
	return p


## this = lerp(this, o, w) for every channel.
func blend(o: RigPose, w: float) -> void:
	if w <= 0.0:
		return
	if w >= 1.0:
		copy_from(o)
		return
	for i in COUNT:
		v[i] = lerp(v[i], o.v[i], w)


## Per-channel weighted blend with a mask (Array of channel indices, empty = all).
func blend_masked(o: RigPose, w: float, mask: Array) -> void:
	if mask.is_empty():
		blend(o, w)
		return
	if w <= 0.0:
		return
	for i: int in mask:
		v[i] = lerp(v[i], o.v[i], w)


## Adds `o * w` to the Euler/float channels listed (additive layers).
func add_scaled(o: RigPose, w: float, channels: PackedInt32Array) -> void:
	for i in channels:
		v[i] = v[i] + o.v[i] * w


## Mirrors left/right in place.
func mirror() -> void:
	for pr in MIRROR_PAIRS:
		var tmp: Variant = v[pr.x]
		v[pr.x] = v[pr.y]
		v[pr.y] = tmp
	var hp: Vector3 = v[HIPS]
	v[HIPS] = Vector3(-hp.x, hp.y, hp.z)
	for i in CENTER_EULER:
		var e: Vector3 = v[i]
		v[i] = Vector3(e.x, -e.y, -e.z)


## Sets channels from a Dictionary {channel_name: value}. Unknown names are ignored.
func apply_dict(d: Dictionary) -> void:
	for k: String in d:
		var i := NAMES.find(k)
		if i >= 0:
			v[i] = float(d[k]) if is_float_channel(i) else d[k]


func get_channel(channel_name: String) -> Variant:
	var i := NAMES.find(channel_name)
	return v[i] if i >= 0 else null
