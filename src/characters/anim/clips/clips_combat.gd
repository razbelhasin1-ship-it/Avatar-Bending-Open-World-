class_name ClipsCombat
extends RefCounted
## Built-in generic strikes usable by every style: jabs, crosses, kicks
## (front, side, roundhouse, spinning, flip), palm strikes, pushes, uppercut
## lift, stomp, ground slam, sweeping arm circle, whip lash, draw-up gather,
## shield raise, wall raise, charge hold/release, spinning and leap attacks,
## tornado spin. Right-handed clips are mirrored to *_l by ClipKit.reg_pair.
## Events: &"release" (spawn projectiles), &"impact" (melee contact),
## &"recover" (actions may be cancelled from here).

const K = preload("res://src/characters/anim/clips/clip_kit.gd")


static func register_all() -> void:
	_punches()
	_kicks()
	_pushes()
	_ground()
	_spins()


static func _punches() -> void:
	K.reg_pair("jab", {"length": 0.36, "mask": &"upper", "events": [[0.42, &"release"], [0.45, &"impact"], [0.75, &"recover"]], "keys": [
		[0.22, {"hand_r": Vector3(0.0, -0.36, 0.06), "elbow_r": K.ELBOW_BACK, "fist_r": 1.0, "chest": Vector3(0, -8, 0), "wrist_r": Vector3(0, -60, 0)}, &"out"],
		[0.42, {"hand_r": Vector3(-0.13, 0.0, 0.98), "elbow_r": K.ELBOW_DOWN, "fist_r": 1.0, "wrist_r": Vector3(0, 85, 0), "chest": Vector3(2, 20, 0), "spine": Vector3(2, 6, 0), "clav_r": Vector3(0, 14, 0), "head": Vector3(0, -12, 0)}, &"snap"],
		[0.62, {"hand_r": Vector3(-0.11, -0.02, 0.9)}],
	]})
	K.reg_pair("cross", {"length": 0.5, "mask": &"upper", "events": [[0.45, &"release"], [0.48, &"impact"], [0.8, &"recover"]], "keys": [
		[0.25, {"hand_r": Vector3(0.02, -0.4, -0.05), "elbow_r": K.ELBOW_BACK, "fist_r": 1.0, "hips_rot": Vector3(0, -14, 0), "chest": Vector3(-2, -14, 0), "wrist_r": Vector3(0, -50, 0)}, &"inout"],
		[0.45, {"hand_r": Vector3(-0.2, 0.02, 1.0), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 90, 0), "hips_rot": Vector3(4, 18, 0), "spine": Vector3(4, 10, 0), "chest": Vector3(6, 24, 0),
			"clav_r": Vector3(0, 18, 0), "head": Vector3(-4, -22, 0)}, &"snap"],
		[0.68, {"hand_r": Vector3(-0.18, 0.0, 0.92), "chest": Vector3(5, 20, 0)}],
	]})


static func _kicks() -> void:
	var guard_l := Vector3(-0.2, -0.15, 0.4)
	K.reg_pair("front_kick", {"length": 0.66, "events": [[0.42, &"release"], [0.44, &"impact"], [0.8, &"recover"]], "plants": [[0.9, "r", 0.9]], "keys": [
		[0.25, {"foot_r": Vector3(0.0, 0.55, 0.32), "knee_r": Vector3(0.05, 0.4, 1.0), "foot_rot_r": Vector3(30, 0, 0), "hips": Vector3(0, -0.04, -0.02), "hips_rot": Vector3(-6, 0, 0),
			"spine": Vector3(-4, 0, 0), "hand_l": guard_l, "hand_r": Vector3(0.15, -0.4, 0.2), "fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"out"],
		[0.44, {"foot_r": Vector3(-0.03, 0.88, 0.8), "knee_r": Vector3(0.05, 1.0, 0.3), "foot_rot_r": Vector3(55, 0, 0), "hips_rot": Vector3(-14, 6, 0), "spine": Vector3(-10, 0, 0),
			"head": Vector3(12, 0, 0), "hand_r": Vector3(0.3, -0.55, -0.1), "foot_l": Vector3(0, 0, -0.05)}, &"snap"],
		[0.62, {"foot_r": Vector3(0.0, 0.5, 0.3), "knee_r": Vector3(0.05, 0.4, 1.0), "hips_rot": Vector3(-5, 0, 0)}, &"out"],
	]})
	K.reg_pair("side_kick", {"length": 0.78, "events": [[0.45, &"release"], [0.47, &"impact"], [0.82, &"recover"]], "plants": [[0.92, "r", 1.0]], "keys": [
		[0.28, {"hips_rot": Vector3(0, 60, 10), "chest": Vector3(0, 10, 8), "head": Vector3(0, -55, 0), "foot_r": Vector3(-0.1, 0.55, 0.15), "knee_r": Vector3(-0.6, 0.6, 0.6),
			"foot_l": Vector3(0.0, 0, 0.0), "foot_rot_l": Vector3(0, 50, 0), "hand_l": Vector3(-0.15, -0.2, 0.45), "hand_r": Vector3(0.0, -0.3, 0.3), "fist_l": 1.0, "fist_r": 1.0}, &"out"],
		[0.47, {"hips_rot": Vector3(0, 78, 26), "spine": Vector3(0, 6, 14), "chest": Vector3(0, 6, 12), "head": Vector3(0, -70, -10), "foot_r": Vector3(-0.15, 0.95, 0.85),
			"knee_r": Vector3(-0.3, 1.0, 0.0), "foot_rot_r": Vector3(0, -60, 70), "hand_r": Vector3(0.5, -0.45, -0.25), "hand_l": Vector3(-0.1, -0.1, 0.5)}, &"snap"],
		[0.66, {"hips_rot": Vector3(0, 60, 10), "foot_r": Vector3(-0.08, 0.5, 0.2), "knee_r": Vector3(-0.6, 0.6, 0.6)}, &"out"],
	]})
	K.reg_pair("roundhouse", {"length": 0.82, "events": [[0.46, &"release"], [0.48, &"impact"], [0.84, &"recover"]], "plants": [[0.93, "r", 1.0]], "keys": [
		[0.24, {"foot_r": Vector3(0.28, 0.55, -0.05), "knee_r": Vector3(0.9, 0.4, 0.4), "hips_rot": Vector3(-4, -10, -6), "chest": Vector3(0, -12, 0),
			"hand_l": Vector3(-0.2, -0.15, 0.42), "hand_r": Vector3(0.35, -0.3, 0.2), "fist_l": 1.0, "fist_r": 1.0, "foot_rot_l": Vector3(0, 20, 0)}, &"out"],
		[0.48, {"foot_r": Vector3(-0.25, 1.05, 0.75), "knee_r": Vector3(0.0, 1.0, -0.3), "foot_rot_r": Vector3(40, -20, 40), "hips_rot": Vector3(-14, 62, 18),
			"spine": Vector3(-6, 10, 10), "chest": Vector3(-4, 10, 8), "head": Vector3(6, -50, -10), "hand_r": Vector3(0.6, -0.4, -0.3), "hand_l": Vector3(-0.1, -0.05, 0.5),
			"foot_rot_l": Vector3(0, 80, 0)}, &"snap"],
		[0.66, {"foot_r": Vector3(-0.45, 0.6, 0.35), "hips_rot": Vector3(-6, 70, 6), "foot_rot_l": Vector3(0, 70, 0)}, &"out"],
		[0.85, {"foot_r": Vector3(0.0, 0.1, 0.25), "hips_rot": Vector3(0, 20, 0)}],
	]})
	# Spinning back kick: full turn, leg thrusts out behind at ~3/4 of the spin.
	K.reg(&"spin_kick", {"length": 0.9, "events": [[0.55, &"release"], [0.57, &"impact"], [0.85, &"recover"]], "plants": [[0.92, "r", 1.0]], "keys": [
		[0.18, {"hips_rot": Vector3(0, -40, 0), "chest": Vector3(0, -20, 0), "head": Vector3(0, -30, 0), "hips": Vector3(0, -0.08, 0), "foot_rot_l": Vector3(0, 30, 0),
			"hand_l": Vector3(-0.2, -0.15, 0.42), "hand_r": Vector3(-0.2, -0.2, 0.38), "fist_l": 1.0, "fist_r": 1.0}, &"out"],
		[0.4, {"hips_rot": Vector3(0, -180, 0), "chest": Vector3(0, -40, 0), "head": Vector3(0, -60, 0), "foot_r": Vector3(0.1, 0.4, 0.0), "knee_r": Vector3(0.0, 0.5, -1.0)}],
		[0.57, {"hips_rot": Vector3(-30, -250, 10), "chest": Vector3(-10, -20, 0), "head": Vector3(0, -30, 0), "foot_r": Vector3(0.0, 0.85, -0.85), "knee_r": Vector3(0.0, -1.0, 0.0),
			"foot_rot_r": Vector3(-20, 0, 0), "hand_l": Vector3(0.3, -0.4, 0.4), "hand_r": Vector3(0.4, -0.3, 0.2)}, &"snap"],
		[0.78, {"hips_rot": Vector3(0, -330, 0), "chest": Vector3(0, -10, 0), "head": Vector3(0, 0, 0), "foot_r": Vector3(0.05, 0.25, 0.1), "knee_r": K.KNEE_FWD}],
		[0.95, {"hips_rot": Vector3(0, -360, 0), "foot_r": Vector3(0.04, 0, 0.0)}],
	]})
	# Flip kick: backflip with one leg snapping overhead (air / fire acrobatics).
	K.reg(&"flip_kick", {"length": 0.95, "events": [[0.38, &"release"], [0.4, &"impact"], [0.9, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.4, Vector3(0, 1.2, -0.4)], [0.85, Vector3(0, 0, -0.9)], [1.0, Vector3(0, 0, -1.0)]], "plants": [[0.86, "l", 0.8], [0.88, "r", 0.8]], "keys": [
		[0.14, {"hips": Vector3(0, -0.22, 0), "spine": Vector3(12, 0, 0), "hand_l": Vector3(0.2, -0.55, -0.35), "hand_r": Vector3(0.2, -0.55, -0.35), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK}, &"out"],
		[0.4, {"hips": Vector3(0, 0.05, 0), "hips_rot": Vector3(-110, 0, 0), "spine": Vector3(-14, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(20, 0, 0), "feet_hips": 1.0,
			"foot_r": Vector3(0.0, 0.0, 1.0), "knee_r": Vector3(0, 1, 0), "foot_l": Vector3(0.0, 0.5, 0.4), "knee_l": Vector3(0.1, 0.5, 1),
			"hand_l": Vector3(0.6, 0.0, 0.0), "hand_r": Vector3(0.6, 0.0, 0.0), "fist_l": 1.0, "fist_r": 1.0}, &"snap"],
		[0.62, {"hips_rot": Vector3(-250, 0, 0), "feet_hips": 1.0, "foot_r": Vector3(0.0, 0.5, 0.42), "foot_l": Vector3(0.02, 0.5, 0.4), "knee_r": Vector3(0.1, 0.5, 1)}],
		[0.85, {"hips": Vector3(0, -0.22, 0), "hips_rot": Vector3(-360, 0, 0), "spine": Vector3(16, 0, 0), "chest": Vector3(0, 0, 0), "head": Vector3(-8, 0, 0), "feet_hips": 0.0,
			"foot_l": Vector3(0.04, 0, 0.1), "foot_r": Vector3(0.05, 0, -0.12), "hand_l": Vector3(0.5, -0.3, 0.3), "hand_r": Vector3(0.5, -0.3, 0.3)}, &"out"],
	]})


static func _pushes() -> void:
	K.reg_pair("palm_strike", {"length": 0.5, "mask": &"upper", "events": [[0.45, &"release"], [0.47, &"impact"], [0.8, &"recover"]], "keys": [
		[0.25, {"hand_r": Vector3(0.05, -0.3, 0.1), "elbow_r": K.ELBOW_BACK, "wrist_r": Vector3(-60, 90, 0), "fist_r": 0.0, "chest": Vector3(0, -12, 0)}, &"inout"],
		[0.46, {"hand_r": Vector3(-0.12, -0.05, 0.92), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(-80, 90, 0), "fist_r": 0.0, "chest": Vector3(4, 18, 0), "clav_r": Vector3(0, 14, 0)}, &"snap"],
		[0.68, {"hand_r": Vector3(-0.1, -0.05, 0.86)}],
	]})
	K.reg(&"two_hand_push", {"length": 0.62, "events": [[0.46, &"release"], [0.5, &"impact"], [0.82, &"recover"]], "plants": [[0.4, "l", 1.0]], "keys": [
		[0.28, {"hips": Vector3(0, -0.08, -0.04), "spine": Vector3(-4, 0, 0), "chest": Vector3(-6, 0, 0), "hand_l": Vector3(-0.1, -0.3, 0.2), "hand_r": Vector3(-0.1, -0.3, 0.2),
			"elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "wrist_l": Vector3(-50, 80, 0), "wrist_r": Vector3(-50, 80, 0), "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0.0, 0.06, 0.1)}, &"inout"],
		[0.48, {"hips": Vector3(0, -0.1, 0.1), "spine": Vector3(8, 0, 0), "chest": Vector3(8, 0, 0), "hand_l": Vector3(-0.15, -0.05, 0.92), "hand_r": Vector3(-0.15, -0.05, 0.92),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "wrist_l": Vector3(-80, 90, 0), "wrist_r": Vector3(-80, 90, 0),
			"foot_l": Vector3(0.0, 0.0, 0.42), "foot_r": Vector3(0.05, 0, -0.18)}, &"snap"],
		[0.7, {"hips": Vector3(0, -0.1, 0.08), "hand_l": Vector3(-0.12, -0.08, 0.86), "hand_r": Vector3(-0.12, -0.08, 0.86)}],
	]})
	K.reg(&"shield_raise", {"length": 0.55, "events": [[0.45, &"release"]], "hold": true, "keys": [
		[0.2, {"hips": Vector3(0, -0.12, 0), "spine": Vector3(10, 0, 0), "hand_l": Vector3(-0.05, -0.8, 0.35), "hand_r": Vector3(-0.05, -0.8, 0.35), "wrist_l": Vector3(20, -60, 0), "wrist_r": Vector3(20, -60, 0),
			"fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"inout"],
		[0.45, {"hips": Vector3(0, -0.1, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(-6, 0, 0), "hand_l": Vector3(0.15, 0.15, 0.62), "hand_r": Vector3(0.15, 0.15, 0.62),
			"wrist_l": Vector3(-70, 90, 0), "wrist_r": Vector3(-70, 90, 0), "elbow_l": Vector3(0.6, -1, 0), "elbow_r": Vector3(0.6, -1, 0)}, &"snap"],
		[1.0, {"hand_l": Vector3(0.12, 0.12, 0.6), "hand_r": Vector3(0.12, 0.12, 0.6)}],
	]})


static func _ground() -> void:
	var horse := {"foot_l": Vector3(0.26, 0, 0.0), "foot_r": Vector3(0.26, 0, 0.0), "foot_rot_l": Vector3(0, 22, 0), "foot_rot_r": Vector3(0, 22, 0),
		"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}
	var low := horse.duplicate()
	low.merge({"hips": Vector3(0, -0.24, 0), "spine": Vector3(26, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(-20, 0, 0),
		"hand_l": Vector3(0.0, -0.85, 0.45), "hand_r": Vector3(0.0, -0.85, 0.45), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 1.0, "fist_r": 1.0,
		"wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0)})
	# Uppercut-lift (raise earth): low gather, explosive rise of both fists.
	K.reg(&"uppercut_lift", {"length": 0.8, "events": [[0.3, &"stomp"], [0.55, &"release"], [0.85, &"recover"]], "plants": [[0.3, "r", 1.3]], "keys": [
		[0.3, low, &"inout"],
		[0.55, {"hips": Vector3(0, -0.06, 0.02), "spine": Vector3(-6, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_l": Vector3(0.0, 0.2, 0.62), "hand_r": Vector3(0.0, 0.2, 0.62), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "wrist_l": Vector3(0, -80, 0), "wrist_r": Vector3(0, -80, 0)}, &"snap"],
		[0.72, {"hips": Vector3(0, -0.1, 0.0), "hand_l": Vector3(0.0, 0.15, 0.58), "hand_r": Vector3(0.0, 0.15, 0.58)}],
	]})
	# Wall raise: both arms rise from low with palms up, wide horse stance.
	var wall_hi := horse.duplicate()
	wall_hi.merge({"hips": Vector3(0, -0.15, 0), "chest": Vector3(-8, 0, 0), "head": Vector3(-6, 0, 0), "hand_l": Vector3(0.25, 0.55, 0.45), "hand_r": Vector3(0.25, 0.55, 0.45),
		"elbow_l": Vector3(0.8, -0.6, 0), "elbow_r": Vector3(0.8, -0.6, 0), "wrist_l": Vector3(-40, -90, 0), "wrist_r": Vector3(-40, -90, 0), "fist_l": 0.2, "fist_r": 0.2})
	K.reg(&"wall_raise", {"length": 0.9, "events": [[0.28, &"stomp"], [0.6, &"release"], [0.88, &"recover"]], "plants": [[0.28, "l", 1.3]], "keys": [
		[0.28, low, &"inout"],
		[0.6, wall_hi, &"snap"],
		[0.78, {"hand_l": Vector3(0.25, 0.5, 0.42), "hand_r": Vector3(0.25, 0.5, 0.42), "hips": Vector3(0, -0.16, 0)}],
	]})
	K.reg_pair("stomp", {"length": 0.62, "events": [[0.52, &"impact"], [0.85, &"recover"]], "plants": [[0.52, "r", 1.4]], "keys": [
		[0.32, {"foot_r": Vector3(0.05, 0.6, 0.1), "knee_r": Vector3(0.3, 0.3, 1), "hips": Vector3(0, 0.02, 0), "spine": Vector3(-6, 0, -4), "chest": Vector3(-6, 0, 0),
			"hand_l": Vector3(0.2, -0.1, 0.5), "hand_r": Vector3(0.3, 0.05, 0.4), "fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"out"],
		[0.52, {"foot_r": Vector3(0.18, 0.0, 0.05), "hips": Vector3(0, -0.2, 0), "spine": Vector3(14, 0, 0), "chest": Vector3(6, 0, 0), "foot_rot_r": Vector3(0, 20, 0),
			"hand_l": Vector3(0.15, -0.85, 0.15), "hand_r": Vector3(0.15, -0.85, 0.15), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT}, &"in"],
		[0.72, {"hips": Vector3(0, -0.18, 0), "spine": Vector3(10, 0, 0)}],
	]})
	K.reg(&"ground_slam", {"length": 0.95, "events": [[0.55, &"impact"], [0.88, &"recover"]], "plants": [[0.55, "l", 1.4], [0.56, "r", 1.4]], "keys": [
		[0.3, {"hips": Vector3(0, 0.05, 0), "spine": Vector3(-10, 0, 0), "chest": Vector3(-14, 0, 0), "head": Vector3(-6, 0, 0),
			"hand_l": Vector3(0.05, 0.95, 0.2), "hand_r": Vector3(0.05, 0.95, 0.2), "fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"foot_l": Vector3(0.1, 0.12, 0.05)}, &"out"],
		[0.55, {"hips": Vector3(0, -0.42, 0.1), "spine": Vector3(42, 0, 0), "chest": Vector3(20, 0, 0), "head": Vector3(-20, 0, 0),
			"hand_l": Vector3(-0.05, -0.9, 0.42), "hand_r": Vector3(-0.05, -0.9, 0.42), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"foot_l": Vector3(0.2, 0, 0.18), "foot_r": Vector3(0.2, 0, -0.12), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT}, &"in"],
		[0.75, {"hips": Vector3(0, -0.38, 0.08), "spine": Vector3(36, 0, 0)}],
	]})
	# Draw-up: circular gather from the ground to the chest (water / earth).
	K.reg(&"draw_up", {"length": 1.0, "events": [[0.35, &"gather"], [0.75, &"release"], [0.88, &"recover"]], "keys": [
		[0.25, {"hips": Vector3(0, -0.2, 0), "spine": Vector3(20, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_l": Vector3(0.35, -0.85, 0.35), "hand_r": Vector3(0.35, -0.85, 0.35), "wrist_l": Vector3(10, -90, 0), "wrist_r": Vector3(10, -90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.0, "fist_r": 0.0}, &"inout"],
		[0.5, {"hips": Vector3(0, -0.12, 0), "spine": Vector3(6, 0, 0), "hand_l": Vector3(0.2, -0.45, 0.55), "hand_r": Vector3(0.2, -0.45, 0.55),
			"wrist_l": Vector3(-20, -90, 0), "wrist_r": Vector3(-20, -90, 0)}],
		[0.75, {"hips": Vector3(0, -0.06, 0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(-4, 0, 0),
			"hand_l": Vector3(-0.2, -0.2, 0.5), "hand_r": Vector3(-0.2, -0.2, 0.5), "wrist_l": Vector3(-30, -90, 0), "wrist_r": Vector3(-30, -90, 0), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"out"],
	]})
	K.reg_pair("whip_lash", {"length": 0.75, "events": [[0.52, &"release"], [0.58, &"impact"], [0.85, &"recover"]], "keys": [
		[0.3, {"hand_r": Vector3(0.45, 0.55, -0.35), "elbow_r": Vector3(1, -0.2, -0.4), "wrist_r": Vector3(-40, 0, 0), "fist_r": 0.0, "chest": Vector3(-8, -26, -6), "spine": Vector3(-4, -10, 0),
			"hips_rot": Vector3(0, -10, 0), "hand_l": Vector3(-0.1, -0.25, 0.6), "wrist_l": Vector3(-40, 80, 0), "fist_l": 0.0, "head": Vector3(0, 20, 0)}, &"inout"],
		[0.52, {"hand_r": Vector3(-0.05, 0.25, 0.95), "elbow_r": Vector3(0.4, -1, 0.2), "wrist_r": Vector3(30, 70, 0), "chest": Vector3(8, 22, 4), "spine": Vector3(4, 8, 0),
			"hips_rot": Vector3(0, 10, 0), "head": Vector3(0, -16, 0)}, &"snap"],
		[0.66, {"hand_r": Vector3(-0.25, -0.35, 0.8), "wrist_r": Vector3(45, 80, 0), "chest": Vector3(10, 26, 6)}, &"out"],
	]})
	K.reg(&"arm_circle", {"length": 0.9, "events": [[0.55, &"release"], [0.85, &"recover"]], "keys": [
		[0.2, {"hand_r": Vector3(0.75, -0.1, 0.25), "hand_l": Vector3(-0.1, -0.3, 0.55), "chest": Vector3(0, -30, 0), "spine": Vector3(0, -10, 0), "hips_rot": Vector3(0, -10, 0),
			"elbow_r": Vector3(0, -1, -0.3), "wrist_r": Vector3(-30, 80, 0), "fist_r": 0.0, "fist_l": 0.0, "head": Vector3(0, 20, 0)}, &"inout"],
		[0.45, {"hand_r": Vector3(0.15, 0.05, 0.95), "hand_l": Vector3(0.6, -0.1, 0.4), "chest": Vector3(0, 0, 0), "spine": Vector3(0, 0, 0), "hips_rot": Vector3(0, 0, 0),
			"elbow_r": K.ELBOW_DOWN, "elbow_l": Vector3(0, -1, -0.3), "head": Vector3(0, 0, 0)}],
		[0.65, {"hand_r": Vector3(-0.55, 0.0, 0.7), "hand_l": Vector3(0.8, -0.05, 0.1), "chest": Vector3(0, 32, 0), "spine": Vector3(0, 10, 0), "hips_rot": Vector3(0, 10, 0),
			"head": Vector3(0, -20, 0)}, &"out"],
	]})
	# Charge (fire / air): compressed hold at the hip, released as a two-hand thrust.
	K.reg(&"charge_hold", {"length": 1.0, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(4, -18, 0), "spine": Vector3(2, -8, 0), "hand_l": Vector3(-0.05, -0.55, 0.1), "hand_r": Vector3(0.05, -0.5, 0.0),
			"elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "wrist_l": Vector3(-30, 80, 0), "wrist_r": Vector3(-30, -80, 0), "fist_l": 0.5, "fist_r": 0.5}],
		[0.5, {"chest": Vector3(5, -19, 0), "hand_l": Vector3(-0.06, -0.54, 0.11)}],
	]})
	K.reg(&"charge_release", {"length": 0.55, "events": [[0.35, &"release"], [0.8, &"recover"]], "keys": [
		[0.0, {"chest": Vector3(4, -18, 0), "spine": Vector3(2, -8, 0), "hand_l": Vector3(-0.05, -0.55, 0.1), "hand_r": Vector3(0.05, -0.5, 0.0),
			"elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "wrist_l": Vector3(-30, 80, 0), "wrist_r": Vector3(-30, -80, 0), "fist_l": 0.5, "fist_r": 0.5}],
		[0.35, {"hips": Vector3(0, -0.1, 0.1), "chest": Vector3(8, 8, 0), "spine": Vector3(6, 4, 0), "hand_l": Vector3(-0.2, 0.0, 0.95), "hand_r": Vector3(-0.2, -0.05, 0.95),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "wrist_l": Vector3(-75, 90, 0), "wrist_r": Vector3(-75, 90, 0), "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0, 0, 0.35), "foot_r": Vector3(0.06, 0, -0.2)}, &"snap"],
		[0.65, {"hips": Vector3(0, -0.1, 0.08), "hand_l": Vector3(-0.18, -0.02, 0.9), "hand_r": Vector3(-0.18, -0.07, 0.9)}],
	]})


static func _spins() -> void:
	K.reg(&"spin_attack", {"length": 0.85, "events": [[0.35, &"release"], [0.4, &"impact"], [0.6, &"impact"], [0.88, &"recover"]], "keys": [
		[0.15, {"hips": Vector3(0, -0.12, 0), "hips_rot": Vector3(0, 30, 0), "chest": Vector3(0, 20, 0), "hand_l": Vector3(-0.3, -0.3, 0.4), "hand_r": Vector3(-0.4, -0.35, 0.35),
			"fist_l": 1.0, "fist_r": 1.0}, &"out"],
		[0.4, {"hips_rot": Vector3(0, -150, 0), "chest": Vector3(0, -20, 0), "hand_l": Vector3(0.95, 0.0, 0.1), "hand_r": Vector3(0.95, 0.05, 0.1), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"foot_rot_l": Vector3(0, 40, 0), "foot_rot_r": Vector3(0, 40, 0), "head": Vector3(0, 20, 0)}],
		[0.65, {"hips_rot": Vector3(0, -300, 0), "chest": Vector3(0, -20, 0), "hand_l": Vector3(0.95, 0.0, 0.1), "hand_r": Vector3(0.95, 0.05, 0.1)}],
		[0.85, {"hips_rot": Vector3(0, -360, 0), "chest": Vector3(0, 0, 0), "hips": Vector3(0, -0.1, 0), "hand_l": Vector3(-0.2, -0.15, 0.42), "hand_r": Vector3(-0.22, -0.2, 0.38),
			"foot_rot_l": Vector3(0, 10, 0), "foot_rot_r": Vector3(0, 10, 0)}, &"out"],
	]})
	K.reg(&"tornado_spin", {"length": 1.3, "events": [[0.2, &"release"], [0.85, &"recover"]], "plants": [[0.82, "l", 0.8], [0.84, "r", 0.8]], "keys": [
		[0.12, {"hips": Vector3(0, -0.18, 0), "hips_rot": Vector3(0, 40, 0), "chest": Vector3(0, 20, 0), "hand_l": Vector3(0.3, -0.6, 0.3), "hand_r": Vector3(0.3, -0.6, 0.3),
			"wrist_l": Vector3(-30, -80, 0), "wrist_r": Vector3(-30, -80, 0), "fist_l": 0.0, "fist_r": 0.0}, &"out"],
		[0.3, {"hips": Vector3(0, 0.05, 0), "hips_rot": Vector3(0, -180, 0), "chest": Vector3(-6, -30, 0), "hand_l": Vector3(0.5, 0.55, 0.2), "hand_r": Vector3(0.5, 0.55, 0.2),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "feet_hips": 0.6, "foot_l": Vector3(0.05, 0.25, 0.1), "foot_r": Vector3(0.05, 0.15, -0.05), "head": Vector3(-14, 0, 0)}],
		[0.5, {"hips_rot": Vector3(0, -420, 0), "hand_l": Vector3(0.7, 0.3, 0.1), "hand_r": Vector3(0.7, 0.3, 0.1)}],
		[0.7, {"hips": Vector3(0, 0.02, 0), "hips_rot": Vector3(0, -640, 0), "hand_l": Vector3(0.6, 0.45, 0.2), "hand_r": Vector3(0.6, 0.45, 0.2)}],
		[0.85, {"hips": Vector3(0, -0.16, 0), "hips_rot": Vector3(0, -720, 0), "chest": Vector3(4, 0, 0), "feet_hips": 0.0, "foot_l": Vector3(0.05, 0, 0.0), "foot_r": Vector3(0.05, 0, 0.0),
			"hand_l": Vector3(0.4, -0.5, 0.3), "hand_r": Vector3(0.4, -0.5, 0.3), "head": Vector3(0, 0, 0)}, &"out"],
	]})
	K.reg(&"leap_attack", {"length": 1.05, "events": [[0.18, &"takeoff"], [0.66, &"impact"], [0.9, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.18, Vector3(0, 0, 0.2)], [0.42, Vector3(0, 1.0, 2.0)], [0.66, Vector3(0, 0.0, 3.6)], [1.0, Vector3(0, 0, 3.8)]],
		"plants": [[0.66, "l", 1.3], [0.67, "r", 1.3]], "meta": {"travel": 3.8}, "keys": [
		[0.15, {"hips": Vector3(0, -0.22, 0.05), "spine": Vector3(20, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_l": Vector3(0.3, -0.65, -0.4), "hand_r": Vector3(0.3, -0.65, -0.4), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "fist_l": 1.0, "fist_r": 1.0}, &"out"],
		[0.42, {"hips": Vector3(0, 0.0, 0), "spine": Vector3(-14, 0, 0), "chest": Vector3(-18, 0, 0), "head": Vector3(-6, 0, 0),
			"hand_l": Vector3(0.05, 0.95, 0.15), "hand_r": Vector3(0.05, 0.95, 0.15), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.3, 0.25), "foot_r": Vector3(0.04, 0.2, -0.3), "foot_rot_r": Vector3(-40, 0, 0)}],
		[0.66, {"hips": Vector3(0, -0.4, 0.1), "spine": Vector3(38, 0, 0), "chest": Vector3(16, 0, 0), "head": Vector3(-24, 0, 0), "feet_hips": 0.0,
			"hand_l": Vector3(0.0, -0.75, 0.6), "hand_r": Vector3(0.0, -0.75, 0.6), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"foot_l": Vector3(0.18, 0, 0.25), "foot_r": Vector3(0.2, 0, -0.2), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT}, &"in"],
		[0.82, {"hips": Vector3(0, -0.34, 0.08), "spine": Vector3(30, 0, 0)}],
	]})
