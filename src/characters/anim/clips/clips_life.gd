class_name ClipsLife
extends RefCounted
## NPC / life clips: talking gestures, wave, cheer, point, bow, sitting
## (bench and ground), kneel, meditate, sleep, work (hammer, sweep, fish,
## carry), interact/reach, mount + ride, swim.
## Looping clips play until stop_action(); *_loop clips also back pose states.
## Riding expects the rig origin at the saddle seat point.

const K = preload("res://src/characters/anim/clips/clip_kit.gd")


static func register_all() -> void:
	_social()
	_rest()
	_work()
	_travel()


static func _social() -> void:
	K.reg(&"talk_1", {"length": 3.2, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"hand_l": Vector3(0.05, -0.55, 0.45), "hand_r": Vector3(0.1, -0.6, 0.4), "wrist_l": Vector3(-20, -60, 0), "wrist_r": Vector3(-10, -50, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.1, "fist_r": 0.2, "head": Vector3(2, 4, 0), "chest": Vector3(0, 3, 0)}],
		[0.25, {"hand_l": Vector3(0.15, -0.45, 0.55), "wrist_l": Vector3(-30, -80, 0), "head": Vector3(-2, 8, 3)}],
		[0.5, {"hand_r": Vector3(0.2, -0.45, 0.55), "wrist_r": Vector3(-30, -80, 0), "hand_l": Vector3(0.05, -0.62, 0.38), "head": Vector3(3, -4, -2), "chest": Vector3(0, -4, 0)}],
		[0.75, {"hand_l": Vector3(0.2, -0.5, 0.5), "hand_r": Vector3(0.15, -0.5, 0.5), "head": Vector3(0, 2, 0)}],
	]})
	K.reg(&"talk_2", {"length": 2.6, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"hand_r": Vector3(0.05, -0.4, 0.55), "wrist_r": Vector3(-30, -70, 0), "elbow_r": K.ELBOW_DOWN, "fist_r": 0.2, "hand_l": Vector3(0.1, -0.95, 0.06), "head": Vector3(0, -6, 0)}],
		[0.3, {"hand_r": Vector3(0.1, -0.3, 0.65), "wrist_r": Vector3(-50, -80, 0), "head": Vector3(-3, -8, 2)}],
		[0.6, {"hand_r": Vector3(-0.05, -0.45, 0.5), "wrist_r": Vector3(-10, -40, 0), "head": Vector3(2, -2, 0)}],
	]})
	K.reg(&"talk_3", {"length": 1.6, "mask": &"upper", "events": [[0.4, &"shrug"]], "keys": [
		[0.4, {"clav_l": Vector3(18, 0, 0), "clav_r": Vector3(18, 0, 0), "hand_l": Vector3(0.45, -0.45, 0.35), "hand_r": Vector3(0.45, -0.45, 0.35), "wrist_l": Vector3(-30, -90, 0),
			"wrist_r": Vector3(-30, -90, 0), "fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "head": Vector3(0, 0, 10)}, &"out"],
		[0.65, {"clav_l": Vector3(14, 0, 0), "clav_r": Vector3(14, 0, 0)}],
	]})
	K.reg_pair("wave", {"length": 1.8, "mask": &"upper", "events": [[0.25, &"wave"]], "keys": [
		[0.2, {"hand_r": Vector3(0.38, 0.8, 0.15), "elbow_r": Vector3(1, -0.5, -0.2), "wrist_r": Vector3(-20, -80, 0), "fist_r": 0.0, "clav_r": Vector3(10, 0, 0), "head": Vector3(-4, -6, 0)}, &"out"],
		[0.35, {"hand_r": Vector3(0.55, 0.72, 0.15)}],
		[0.5, {"hand_r": Vector3(0.28, 0.82, 0.15)}],
		[0.65, {"hand_r": Vector3(0.55, 0.72, 0.15)}],
		[0.8, {"hand_r": Vector3(0.38, 0.8, 0.15)}],
	]})
	K.reg(&"cheer", {"length": 1.3, "events": [[0.3, &"cheer"]], "plants": [[0.62, "l", 0.7], [0.63, "r", 0.7]], "keys": [
		[0.15, {"hips": Vector3(0, -0.1, 0), "hand_l": Vector3(0.2, -0.4, 0.3), "hand_r": Vector3(0.2, -0.4, 0.3), "fist_l": 1.0, "fist_r": 1.0}, &"out"],
		[0.35, {"hips": Vector3(0, 0.08, 0), "hand_l": Vector3(0.3, 0.95, 0.1), "hand_r": Vector3(0.3, 0.95, 0.1), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "chest": Vector3(-10, 0, 0),
			"head": Vector3(-14, 0, 0), "mouth": 1.0, "foot_l": Vector3(0, 0.12, 0.0), "foot_r": Vector3(0, 0.12, 0.0), "foot_rot_l": Vector3(-30, 0, 0), "foot_rot_r": Vector3(-30, 0, 0)}, &"out"],
		[0.6, {"hips": Vector3(0, -0.06, 0), "foot_l": Vector3(0, 0, 0), "foot_r": Vector3(0, 0, 0), "foot_rot_l": Vector3.ZERO, "foot_rot_r": Vector3.ZERO, "mouth": 0.8}, &"in"],
		[0.8, {"hips": Vector3(0, 0.0, 0), "hand_l": Vector3(0.35, 0.9, 0.15), "hand_r": Vector3(0.35, 0.9, 0.15), "mouth": 0.7}],
	]})
	K.reg_pair("point", {"length": 1.4, "mask": &"upper", "events": [[0.3, &"point"]], "keys": [
		[0.3, {"hand_r": Vector3(-0.02, 0.18, 0.96), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 60, 0), "fist_r": 0.7, "chest": Vector3(0, 12, 0), "head": Vector3(-4, -8, 0)}, &"out"],
		[0.75, {"hand_r": Vector3(0.0, 0.2, 0.95)}],
	]})
	K.reg(&"bow", {"length": 1.6, "events": [[0.45, &"bow"]], "keys": [
		[0.3, {"hand_l": Vector3(-0.32, -0.3, 0.42), "hand_r": Vector3(-0.3, -0.32, 0.4), "wrist_l": Vector3(-70, 0, 0), "wrist_r": Vector3(0, 80, 0), "fist_l": 0.0, "fist_r": 1.0,
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT}, &"inout"],
		[0.5, {"spine": Vector3(18, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(10, 0, 0), "hips": Vector3(0, -0.02, -0.03)}, &"inout"],
		[0.75, {"spine": Vector3(16, 0, 0), "chest": Vector3(12, 0, 0)}],
	]})


static func _rest() -> void:
	var sit := {"hips": Vector3(0, -0.54, -0.12), "spine": Vector3(-2, 0, 0), "chest": Vector3(2, 0, 0), "head": Vector3(0, 0, 0),
		"foot_l": Vector3(0.02, 0, 0.36), "foot_r": Vector3(0.04, 0, 0.32), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD, "foot_rot_l": Vector3(0, 8, 0), "foot_rot_r": Vector3(0, 10, 0),
		"hand_l": Vector3(-0.05, -0.75, 0.48), "hand_r": Vector3(0.0, -0.78, 0.45), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "wrist_l": Vector3(30, -60, 0), "wrist_r": Vector3(30, -60, 0),
		"fist_l": 0.3, "fist_r": 0.3}
	K.reg(&"sit_loop", {"length": 4.0, "loop": true, "keys": [[0.0, sit], [0.5, {"head": Vector3(2, 6, 0), "chest": Vector3(3, 2, 0)}]]})
	K.reg(&"sit", {"length": 0.9, "then_state": &"sitting", "hold": true, "keys": [
		[0.4, {"hips": Vector3(0, -0.3, -0.04), "spine": Vector3(26, 0, 0), "chest": Vector3(10, 0, 0), "hand_l": Vector3(0.1, -0.6, 0.45), "hand_r": Vector3(0.1, -0.6, 0.45),
			"foot_l": Vector3(0.02, 0, 0.2), "foot_r": Vector3(0.04, 0, 0.16)}, &"inout"],
		[1.0, sit, &"inout"],
	]})
	var cross := {"hips": Vector3(0, -0.92, -0.05), "spine": Vector3(4, 0, 0), "chest": Vector3(-2, 0, 0), "head": Vector3(4, 0, 0),
		"foot_l": Vector3(-0.32, 0.03, 0.38), "foot_r": Vector3(-0.3, 0.06, 0.3), "knee_l": Vector3(1, 0.6, 0.6), "knee_r": Vector3(1, 0.6, 0.6),
		"foot_rot_l": Vector3(0, -70, -40), "foot_rot_r": Vector3(0, -70, -40),
		"hand_l": Vector3(0.12, -0.92, 0.42), "hand_r": Vector3(0.12, -0.92, 0.42), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
		"wrist_l": Vector3(10, -90, 0), "wrist_r": Vector3(10, -90, 0), "fist_l": 0.2, "fist_r": 0.2}
	K.reg(&"meditate_loop", {"length": 6.0, "loop": true, "keys": [[0.0, cross], [0.5, {"chest": Vector3(-3, 0, 0), "head": Vector3(2, 0, 0)}]]})
	K.reg(&"meditate", {"length": 1.4, "then_state": &"meditating", "hold": true, "keys": [
		[0.45, {"hips": Vector3(0, -0.5, 0.0), "spine": Vector3(24, 0, 0), "foot_l": Vector3(-0.1, 0.0, 0.25), "foot_r": Vector3(0.05, 0, 0.0), "hand_l": Vector3(0.2, -0.6, 0.45),
			"hand_r": Vector3(0.2, -0.6, 0.45)}, &"inout"],
		[1.0, cross, &"inout"],
	]})
	K.reg(&"kneel", {"length": 0.9, "hold": true, "events": [[0.6, &"knee_down"]], "keys": [
		[0.6, {"hips": Vector3(0, -0.46, 0.02), "spine": Vector3(8, 0, 0), "chest": Vector3(4, 0, 0), "head": Vector3(6, 0, 0),
			"foot_l": Vector3(0.02, 0, 0.38), "knee_l": K.KNEE_FWD, "foot_r": Vector3(0.04, 0.1, -0.42), "knee_r": Vector3(0.1, -1, 0.3), "foot_rot_r": Vector3(-60, 6, 0), "toe_r": 55.0,
			"hand_l": Vector3(0.0, -0.6, 0.5), "hand_r": Vector3(0.1, -0.88, 0.2), "elbow_l": K.ELBOW_OUT, "fist_l": 0.3, "fist_r": 0.6}, &"inout"],
		[1.0, {"hips": Vector3(0, -0.47, 0.02)}],
	]})
	var lie := {"hips": Vector3(0, -0.92, -0.3), "hips_rot": Vector3(-88, 0, 0), "spine": Vector3(-2, 0, 0), "chest": Vector3(0, 0, 0), "head": Vector3(10, 20, 0),
		"feet_hips": 1.0, "foot_l": Vector3(0.06, 0.0, 0.05), "foot_r": Vector3(0.04, 0.1, 0.12), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
		"hand_l": Vector3(-0.2, -0.45, 0.35), "hand_r": Vector3(-0.15, -0.5, 0.3), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.3, "fist_r": 0.3}
	K.reg(&"sleep_loop", {"length": 5.0, "loop": true, "keys": [[0.0, lie], [0.5, {"chest": Vector3(-3, 0, 0)}]]})


static func _work() -> void:
	K.reg(&"work_hammer", {"length": 1.0, "loop": true, "mask": &"upper", "events": [[0.55, &"impact"]], "keys": [
		[0.0, {"spine": Vector3(14, 0, 0), "chest": Vector3(8, 4, 0), "head": Vector3(10, 0, 0), "hand_l": Vector3(-0.15, -0.6, 0.55), "elbow_l": K.ELBOW_OUT, "fist_l": 0.6,
			"hand_r": Vector3(0.0, -0.55, 0.55), "elbow_r": K.ELBOW_OUT, "fist_r": 1.0, "wrist_r": Vector3(30, 0, 0)}],
		[0.35, {"hand_r": Vector3(0.25, 0.45, 0.2), "wrist_r": Vector3(-40, 0, 0), "chest": Vector3(2, -6, 0)}, &"out"],
		[0.55, {"hand_r": Vector3(-0.02, -0.56, 0.58), "wrist_r": Vector3(40, 0, 0), "chest": Vector3(10, 4, 0)}, &"in"],
		[0.7, {"hand_r": Vector3(0.0, -0.5, 0.55)}],
	]})
	K.reg(&"sweep", {"length": 1.8, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"spine": Vector3(16, 0, 0), "chest": Vector3(6, -14, 0), "hand_r": Vector3(0.05, -0.8, 0.3), "hand_l": Vector3(-0.3, -0.4, 0.4), "fist_l": 1.0, "fist_r": 1.0,
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "head": Vector3(14, 0, 0)}],
		[0.5, {"chest": Vector3(6, 16, 0), "hand_r": Vector3(-0.35, -0.85, 0.45), "hand_l": Vector3(-0.55, -0.45, 0.35)}],
	]})
	K.reg(&"carry", {"length": 2.0, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(-4, 0, 0), "hand_l": Vector3(-0.08, -0.48, 0.48), "hand_r": Vector3(-0.08, -0.48, 0.48), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": Vector3(10, -90, 0), "wrist_r": Vector3(10, -90, 0), "fist_l": 0.4, "fist_r": 0.4}],
		[0.5, {"chest": Vector3(-5, 0, 0), "hand_l": Vector3(-0.08, -0.47, 0.49), "hand_r": Vector3(-0.08, -0.47, 0.49)}],
	]})
	K.reg(&"fish", {"length": 4.0, "loop": true, "mask": &"upper", "events": [[0.62, &"twitch"]], "keys": [
		[0.0, {"hand_r": Vector3(-0.15, -0.45, 0.48), "hand_l": Vector3(-0.3, -0.25, 0.62), "fist_l": 0.9, "fist_r": 0.9, "wrist_r": Vector3(-20, 60, 0), "wrist_l": Vector3(-20, 60, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "head": Vector3(10, 0, 0)}],
		[0.6, {"hand_r": Vector3(-0.15, -0.45, 0.48), "hand_l": Vector3(-0.3, -0.25, 0.62)}],
		[0.64, {"hand_r": Vector3(-0.12, -0.38, 0.44), "hand_l": Vector3(-0.28, -0.12, 0.56), "head": Vector3(4, 0, 0)}, &"snap"],
		[0.75, {"hand_r": Vector3(-0.15, -0.45, 0.48), "hand_l": Vector3(-0.3, -0.25, 0.62), "head": Vector3(10, 0, 0)}],
	]})
	K.reg_pair("hold_pole", {"length": 3.0, "loop": true, "mask": &"arm_r", "keys": [
		[0.0, {"hand_r": Vector3(0.12, -0.55, 0.45), "elbow_r": Vector3(0.25, -1.0, -0.3), "wrist_r": Vector3(0, 0, 0), "fist_r": 1.0}],
		[0.5, {"hand_r": Vector3(0.12, -0.56, 0.44)}],
	]})
	K.reg_pair("hold_lantern", {"length": 3.0, "loop": true, "mask": &"arm_r", "keys": [
		[0.0, {"hand_r": Vector3(0.05, -0.58, 0.5), "elbow_r": Vector3(0.2, -1.0, -0.2), "wrist_r": Vector3(0, 0, 0), "fist_r": 1.0}],
		[0.5, {"hand_r": Vector3(0.06, -0.57, 0.5)}],
	]})
	K.reg_pair("interact", {"length": 0.85, "events": [[0.5, &"grab"]], "keys": [
		[0.5, {"hips": Vector3(0, -0.1, 0.0), "spine": Vector3(26, 0, 0), "chest": Vector3(10, 8, 0), "head": Vector3(6, 0, 0), "hand_r": Vector3(-0.05, -0.45, 0.88),
			"elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(10, 30, 0), "fist_r": 0.0}, &"inout"],
		[0.6, {"fist_r": 0.8, "hand_r": Vector3(-0.05, -0.44, 0.86)}],
	]})


static func _travel() -> void:
	var ride := {"hips": Vector3(0, -0.98, 0.0), "spine": Vector3(6, 0, 0), "chest": Vector3(2, 0, 0), "head": Vector3(-4, 0, 0),
		"foot_l": Vector3(0.36, -0.28, 0.1), "foot_r": Vector3(0.36, -0.28, 0.1), "knee_l": Vector3(0.8, 0, 1), "knee_r": Vector3(0.8, 0, 1),
		"foot_rot_l": Vector3(-20, 10, 0), "foot_rot_r": Vector3(-20, 10, 0),
		"hand_l": Vector3(-0.18, -0.55, 0.55), "hand_r": Vector3(-0.18, -0.55, 0.55), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.9, "fist_r": 0.9,
		"wrist_l": Vector3(0, 70, 0), "wrist_r": Vector3(0, 70, 0)}
	K.reg(&"ride", {"length": 1.2, "loop": true, "keys": [[0.0, ride], [0.5, {"hips": Vector3(0, -0.965, 0.0), "chest": Vector3(3, 0, 0)}]]})
	K.reg(&"mount", {"length": 0.9, "events": [[0.85, &"seated"]], "then_state": &"riding", "hold": true,
		"root": [[0.0, Vector3.ZERO], [0.5, Vector3(0, 0.8, 0.2)], [1.0, Vector3(0, 0.6, 0.3)]], "keys": [
		[0.2, {"hips": Vector3(0, -0.22, 0), "spine": Vector3(16, 0, 0), "hand_l": Vector3(0.2, -0.3, 0.6), "hand_r": Vector3(0.2, -0.3, 0.6)}, &"out"],
		[0.55, {"hips": Vector3(0, -0.4, 0), "hips_rot": Vector3(0, 0, -20), "foot_r": Vector3(0.6, 0.55, 0.0), "knee_r": Vector3(1, 0.4, 0.4), "spine": Vector3(20, 0, 10),
			"hand_l": Vector3(0.0, -0.6, 0.55), "hand_r": Vector3(0.2, -0.6, 0.5)}],
		[1.0, ride, &"inout"],
	]})
	K.reg(&"dismount", {"length": 0.7, "events": [[0.9, &"landed"]], "plants": [[0.9, "l", 0.9], [0.92, "r", 0.9]], "keys": [
		[0.0, ride],
		[0.4, {"hips": Vector3(0, -0.5, 0), "hips_rot": Vector3(0, 0, 18), "foot_r": Vector3(0.5, 0.3, 0.0), "foot_l": Vector3(0.1, -0.2, 0.0)}],
		[0.9, {"hips": Vector3(0, -0.2, 0), "spine": Vector3(14, 0, 0), "foot_l": Vector3(0.05, 0, 0), "foot_r": Vector3(0.05, 0, 0)}, &"in"],
	]})
	K.reg(&"swim", {"length": 1.6, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0, -0.2, 0.0), "hips_rot": Vector3(78, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(-40, 0, 0),
			"hand_r": Vector3(0.1, 0.9, 0.3), "hand_l": Vector3(0.2, -0.9, -0.1), "elbow_r": K.ELBOW_OUT, "elbow_l": K.ELBOW_OUT, "fist_l": 0.0, "fist_r": 0.0,
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.0, 0.12), "foot_r": Vector3(0.02, 0.0, -0.1), "foot_rot_l": Vector3(-60, 0, 0), "foot_rot_r": Vector3(-60, 0, 0)}],
		[0.25, {"hand_r": Vector3(0.15, 0.2, 0.9), "hand_l": Vector3(0.6, -0.3, -0.4), "foot_l": Vector3(0.0, 0.0, -0.1), "foot_r": Vector3(0.02, 0.0, 0.12), "chest": Vector3(-6, -10, 0)}],
		[0.5, {"hand_r": Vector3(0.2, -0.9, -0.1), "hand_l": Vector3(0.1, 0.9, 0.3), "foot_l": Vector3(0.0, 0.0, 0.12), "foot_r": Vector3(0.02, 0.0, -0.1), "chest": Vector3(-6, 0, 0)}],
		[0.75, {"hand_r": Vector3(0.6, -0.3, -0.4), "hand_l": Vector3(0.15, 0.2, 0.9), "foot_l": Vector3(0.0, 0.0, -0.1), "foot_r": Vector3(0.02, 0.0, 0.12), "chest": Vector3(-6, 10, 0)}],
	]})
