class_name CreaturePose
extends RefCounted
## Procedural pose channels for one frame. Locomotion, idle behaviours, actions and
## look-at all write *additively* into these; the motor (CreatureMotor) and species
## scripts then turn them into bone rotations. Angles in radians, distances in meters.
## Sign conventions: pitch + = nose up, yaw + = turn left, roll + = right side down.

# Whole body (applied around a pivot along the body axis: -1 hind hips .. +1 shoulders).
var body_y := 0.0
var body_z := 0.0
var body_x := 0.0
var body_pitch := 0.0
var body_yaw := 0.0
var body_roll := 0.0
var pitch_pivot := 0.0
# Spine: arch (+ = flexed up / hunched) and lateral bend (+ = front bends left).
var spine_pitch := 0.0
var spine_yaw := 0.0
var spine_roll := 0.0
# Neck + head (neck takes the arc, head the final orientation).
var neck_pitch := 0.0
var neck_yaw := 0.0
var head_pitch := 0.0
var head_yaw := 0.0
var head_roll := 0.0
## 0..1 how much the head ignores body bob/pitch (set per species, scaled by actions).
var head_stab := 0.0
var jaw := 0.0
var tail_pitch := 0.0
var tail_yaw := 0.0
var tail_wag := 0.0
var tail_wag_speed := 0.0
var tail_curl := 0.0
var ear_l := 0.0
var ear_r := 0.0
var ears_back := 0.0
var blink := 0.0
var eyes_narrow := 0.0
var breath := 0.0
var sniff := 0.0
## 0..1 legs released from the ground (rearing, flight, burrowed...).
var front_free := 0.0
var hind_free := 0.0
## Lowers the body by folding legs (0..1 of the leg length).
var crouch := 0.0
## Moves free paws relative to their tucked default (rig space offsets per leg index).
var paw_offsets: Dictionary = {}
## Species-specific channels (wing_fold, mane_lift, dig, ...).
var extra: Dictionary = {}


func reset() -> void:
	body_y = 0.0; body_z = 0.0; body_x = 0.0
	body_pitch = 0.0; body_yaw = 0.0; body_roll = 0.0; pitch_pivot = 0.0
	spine_pitch = 0.0; spine_yaw = 0.0; spine_roll = 0.0
	neck_pitch = 0.0; neck_yaw = 0.0
	head_pitch = 0.0; head_yaw = 0.0; head_roll = 0.0; head_stab = 0.0
	jaw = 0.0
	tail_pitch = 0.0; tail_yaw = 0.0; tail_wag = 0.0; tail_wag_speed = 0.0; tail_curl = 0.0
	ear_l = 0.0; ear_r = 0.0; ears_back = 0.0
	blink = 0.0; eyes_narrow = 0.0; breath = 0.0; sniff = 0.0
	front_free = 0.0; hind_free = 0.0; crouch = 0.0
	paw_offsets.clear()
	extra.clear()


func add_extra(key: StringName, v: float) -> void:
	extra[key] = float(extra.get(key, 0.0)) + v


func get_extra(key: StringName, fallback: float = 0.0) -> float:
	return float(extra.get(key, fallback))


## Adds a rig-space offset to a leg's paw target (blended by the leg's free weight or
## used as a stance override when `planted` legs are lifted by actions).
func add_paw(leg_index: int, offset: Vector3) -> void:
	paw_offsets[leg_index] = (paw_offsets.get(leg_index, Vector3.ZERO) as Vector3) + offset
