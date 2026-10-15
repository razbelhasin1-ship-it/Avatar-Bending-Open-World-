class_name ClipsCore
extends RefCounted
## Built-in idle + combat stance loops for every style, and airborne/landing
## clips. Units and conventions: see RigPose.

const K = preload("res://src/characters/anim/clips/clip_kit.gd")


static func register_all() -> void:
	_idles()
	_stances()
	_air_moves()


static func _idles() -> void:
	K.reg(&"idle_civilian", {"length": 4.2, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.012, -0.004, 0.0), "hips_rot": Vector3(0, 2, -2), "spine": Vector3(1, 0, 1), "head": Vector3(1, -2, 0),
			"hand_l": Vector3(0.12, -0.95, 0.05), "hand_r": Vector3(0.1, -0.95, 0.07), "fist_l": 0.3, "fist_r": 0.35,
			"foot_l": Vector3(0.03, 0, 0.03), "foot_r": Vector3(0.0, 0, -0.02), "foot_rot_l": Vector3(0, 10, 0), "foot_rot_r": Vector3(0, 6, 0)}],
		[0.5, {"hips": Vector3(0.018, -0.006, 0.0), "hips_rot": Vector3(0, 1, -2.6), "spine": Vector3(1.5, 1, 1.3), "head": Vector3(2, 4, -1),
			"hand_l": Vector3(0.12, -0.95, 0.06), "hand_r": Vector3(0.1, -0.94, 0.06)}],
	]})
	K.reg(&"idle_air", {"length": 3.0, "loop": true, "keys": [
		[0.0, {"hips": Vector3(-0.01, 0.0, 0.0), "hips_rot": Vector3(0, -4, 2), "spine": Vector3(-1, 2, -1), "chest": Vector3(-2, 3, 0), "head": Vector3(-3, -6, 3),
			"hand_l": Vector3(0.16, -0.9, 0.08), "hand_r": Vector3(0.16, -0.9, 0.05), "fist_l": 0.15, "fist_r": 0.15, "wrist_l": Vector3(-10, 0, 0), "wrist_r": Vector3(-10, 0, 0),
			"foot_l": Vector3(0.0, 0.0, 0.06), "foot_r": Vector3(0.02, 0.0, -0.04), "foot_rot_l": Vector3(0, 14, 0), "foot_rot_r": Vector3(0, 4, 0), "elbow_l": Vector3(0.6, -0.2, -1), "elbow_r": Vector3(0.6, -0.2, -1)}],
		[0.33, {"hips": Vector3(-0.012, 0.012, 0.0), "chest": Vector3(-3, 4, 0), "head": Vector3(-4, -3, 4), "hand_l": Vector3(0.18, -0.88, 0.1), "hand_r": Vector3(0.18, -0.89, 0.06)}],
		[0.66, {"hips": Vector3(-0.008, 0.002, 0.0), "chest": Vector3(-2, 2, 0), "head": Vector3(-2, -8, 2)}],
	]})
	K.reg(&"idle_earth", {"length": 4.6, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, -0.025, 0.0), "chest": Vector3(-4, 0, 0), "head": Vector3(-1, 0, 0),
			"hand_l": Vector3(0.0, -0.64, -0.05), "hand_r": Vector3(0.0, -0.64, -0.05), "elbow_l": Vector3(1.0, -0.1, -0.4), "elbow_r": Vector3(1.0, -0.1, -0.4),
			"fist_l": 0.9, "fist_r": 0.9, "wrist_l": Vector3(20, 0, 0), "wrist_r": Vector3(20, 0, 0),
			"foot_l": Vector3(0.12, 0, 0.0), "foot_r": Vector3(0.12, 0, 0.0), "foot_rot_l": Vector3(0, 16, 0), "foot_rot_r": Vector3(0, 16, 0), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT}],
		[0.5, {"hips": Vector3(0.0, -0.03, 0.0), "chest": Vector3(-5, 0, 0), "head": Vector3(-1, 2, 0)}],
	]})
	K.reg(&"idle_fire", {"length": 3.8, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, 0.0, 0.0), "chest": Vector3(-5, 0, 0), "head": Vector3(-4, 0, 0), "neck": Vector3(2, 0, 0),
			"hand_l": Vector3(-0.26, -0.66, -0.32), "hand_r": Vector3(-0.22, -0.68, -0.34), "elbow_l": Vector3(0.7, -0.4, -1.0), "elbow_r": Vector3(0.7, -0.4, -1.0),
			"fist_l": 0.5, "fist_r": 0.85, "clav_l": Vector3(0, -4, 0), "clav_r": Vector3(0, -4, 0),
			"foot_l": Vector3(0.05, 0, 0.0), "foot_r": Vector3(0.05, 0, 0.0), "foot_rot_l": Vector3(0, 10, 0), "foot_rot_r": Vector3(0, 10, 0)}],
		[0.5, {"chest": Vector3(-5.5, 1.5, 0), "head": Vector3(-4, 3, 0)}],
	]})
	K.reg(&"idle_water", {"length": 5.0, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.025, -0.01, 0.0), "hips_rot": Vector3(0, 3, -3), "spine": Vector3(0, -2, 2), "chest": Vector3(-1, -2, 1), "head": Vector3(0, 3, -2),
			"hand_l": Vector3(0.14, -0.9, 0.12), "hand_r": Vector3(0.12, -0.93, 0.06), "fist_l": 0.1, "fist_r": 0.2, "wrist_l": Vector3(-15, 10, 0),
			"foot_l": Vector3(0.03, 0, 0.06), "foot_r": Vector3(0.02, 0, -0.03), "foot_rot_l": Vector3(0, 12, 0), "foot_rot_r": Vector3(0, 8, 0)}],
		[0.5, {"hips": Vector3(0.015, -0.012, 0.0), "hips_rot": Vector3(0, 1, -2), "chest": Vector3(-1, 0, 1), "head": Vector3(0, -2, -1),
			"hand_l": Vector3(0.15, -0.88, 0.16), "hand_r": Vector3(0.13, -0.92, 0.09)}],
	]})
	K.reg(&"idle_soldier", {"length": 4.0, "loop": true, "keys": [
		[0.0, {"chest": Vector3(-4, 0, 0), "head": Vector3(-2, 0, 0), "hand_l": Vector3(0.08, -0.98, 0.0), "hand_r": Vector3(0.08, -0.98, 0.0),
			"fist_l": 0.85, "fist_r": 0.85, "foot_l": Vector3(0.0, 0, 0.0), "foot_r": Vector3(0.0, 0, 0.0), "foot_rot_l": Vector3(0, 12, 0), "foot_rot_r": Vector3(0, 12, 0)}],
		[0.5, {"chest": Vector3(-4.5, 0, 0), "head": Vector3(-2, 1.5, 0)}],
	]})
	K.reg(&"idle_elder", {"length": 5.2, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, -0.02, -0.02), "spine": Vector3(8, 0, 0), "chest": Vector3(12, 0, 1), "neck": Vector3(-6, 0, 0), "head": Vector3(-10, -2, 0),
			"hand_l": Vector3(-0.22, -0.62, -0.36), "hand_r": Vector3(-0.2, -0.64, -0.36), "elbow_l": Vector3(0.9, -0.3, -1), "elbow_r": Vector3(0.9, -0.3, -1),
			"fist_l": 0.4, "fist_r": 0.6, "foot_l": Vector3(0.03, 0, 0.02), "foot_r": Vector3(0.03, 0, -0.01), "foot_rot_l": Vector3(0, 14, 0), "foot_rot_r": Vector3(0, 12, 0),
			"knee_l": Vector3(0.2, 0, 1), "knee_r": Vector3(0.2, 0, 1)}],
		[0.5, {"hips": Vector3(0.01, -0.022, -0.02), "chest": Vector3(12.5, 2, 0), "head": Vector3(-11, 3, 1)}],
	]})
	K.reg(&"idle_child", {"length": 2.4, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.015, 0.0, 0.0), "hips_rot": Vector3(0, 4, -3), "head": Vector3(-4, 6, -3), "chest": Vector3(-2, 2, 0),
			"hand_l": Vector3(0.16, -0.9, 0.08), "hand_r": Vector3(0.2, -0.86, 0.04), "fist_l": 0.2, "fist_r": 0.2,
			"foot_l": Vector3(0.0, 0, 0.02), "foot_r": Vector3(0.03, 0, -0.03), "foot_rot_l": Vector3(0, 6, 0), "foot_rot_r": Vector3(0, 16, 0)}],
		[0.5, {"hips": Vector3(-0.012, 0.01, 0.0), "hips_rot": Vector3(0, -4, 3), "head": Vector3(-5, -5, 3), "hand_l": Vector3(0.22, -0.84, 0.02), "hand_r": Vector3(0.15, -0.9, 0.09)}],
	]})


static func _stances() -> void:
	# Air - Ba Gua: light, staggered, open palms circling in front.
	K.reg(&"stance_air", {"length": 2.4, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, -0.06, -0.02), "hips_rot": Vector3(0, 18, 0), "spine": Vector3(-2, -6, 0), "chest": Vector3(-2, -10, 0), "head": Vector3(-2, -6, 0),
			"hand_l": Vector3(-0.05, -0.12, 0.66), "hand_r": Vector3(-0.42, -0.3, 0.36), "elbow_l": K.ELBOW_DOWN, "elbow_r": Vector3(0.4, -1, -0.2),
			"wrist_l": Vector3(-55, -20, 0), "wrist_r": Vector3(-30, 60, 0), "fist_l": 0.0, "fist_r": 0.05,
			"foot_l": Vector3(-0.02, 0.0, 0.26), "foot_r": Vector3(0.1, 0.0, -0.2), "foot_rot_l": Vector3(0, 0, 0), "foot_rot_r": Vector3(0, 38, 0),
			"knee_l": Vector3(0.1, 0, 1), "knee_r": Vector3(0.5, 0, 1)}],
		[0.33, {"hips": Vector3(0.01, -0.045, -0.03), "hand_l": Vector3(0.05, -0.05, 0.6), "hand_r": Vector3(-0.36, -0.22, 0.4)}],
		[0.66, {"hips": Vector3(-0.01, -0.065, -0.015), "hand_l": Vector3(-0.08, -0.2, 0.62), "hand_r": Vector3(-0.44, -0.36, 0.3)}],
	]})
	# Earth - Hung Gar horse stance: wide, low, fists chambered and forward.
	K.reg(&"stance_earth", {"length": 3.0, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, -0.15, -0.02), "hips_rot": Vector3(-3, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(-4, 0, 0),
			"hand_l": Vector3(-0.02, -0.28, 0.56), "hand_r": Vector3(0.04, -0.52, -0.06), "elbow_l": Vector3(0.4, -1, 0), "elbow_r": K.ELBOW_BACK,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 80, 0), "wrist_r": Vector3(10, -70, 0), "clav_l": Vector3(-2, 4, 0),
			"foot_l": Vector3(0.3, 0, 0.0), "foot_r": Vector3(0.3, 0, 0.0), "foot_rot_l": Vector3(0, 22, 0), "foot_rot_r": Vector3(0, 22, 0),
			"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}],
		[0.5, {"hips": Vector3(0.0, -0.158, -0.02), "chest": Vector3(-6.5, 0, 0), "hand_l": Vector3(-0.02, -0.29, 0.57)}],
	]})
	# Fire - Northern Shaolin bow stance: forward weight, lead fist out, rear chambered.
	K.reg(&"stance_fire", {"length": 1.6, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, -0.09, 0.07), "hips_rot": Vector3(4, -24, 0), "spine": Vector3(4, 8, 0), "chest": Vector3(6, 14, 0), "head": Vector3(-6, 4, 0),
			"hand_l": Vector3(-0.08, 0.02, 0.76), "hand_r": Vector3(0.02, -0.44, -0.08), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_BACK,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 70, 0), "wrist_r": Vector3(0, -80, 0),
			"foot_l": Vector3(-0.02, 0, 0.42), "foot_r": Vector3(0.12, 0, -0.3), "foot_rot_l": Vector3(0, -6, 0), "foot_rot_r": Vector3(0, 40, 0),
			"knee_l": Vector3(0.1, 0, 1), "knee_r": Vector3(0.5, 0, 1)}],
		[0.5, {"hips": Vector3(0.0, -0.1, 0.08), "hand_l": Vector3(-0.08, 0.0, 0.78), "chest": Vector3(7, 14, 0)}],
	]})
	# Water - Tai Chi: soft knees, palms floating in slow circles, weight shifting.
	K.reg(&"stance_water", {"length": 4.0, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.03, -0.07, 0.0), "hips_rot": Vector3(0, 8, -2), "spine": Vector3(0, -3, 1), "chest": Vector3(-1, -4, 1), "head": Vector3(-1, -3, 0),
			"hand_l": Vector3(-0.08, -0.2, 0.58), "hand_r": Vector3(-0.1, -0.42, 0.42), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": Vector3(-25, 70, 0), "wrist_r": Vector3(-15, 80, 0), "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0.06, 0, 0.16), "foot_r": Vector3(0.08, 0, -0.12), "foot_rot_l": Vector3(0, 4, 0), "foot_rot_r": Vector3(0, 30, 0)}],
		[0.25, {"hips": Vector3(0.0, -0.08, 0.02), "hand_l": Vector3(0.06, -0.3, 0.52), "hand_r": Vector3(-0.2, -0.3, 0.5)}],
		[0.5, {"hips": Vector3(-0.03, -0.07, 0.0), "hips_rot": Vector3(0, 4, 2), "hand_l": Vector3(-0.04, -0.42, 0.44), "hand_r": Vector3(-0.06, -0.18, 0.58)}],
		[0.75, {"hips": Vector3(0.0, -0.065, -0.01), "hand_l": Vector3(-0.2, -0.3, 0.5), "hand_r": Vector3(0.05, -0.3, 0.52)}],
	]})
	K.reg(&"stance_soldier", {"length": 2.0, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, -0.05, 0.0), "hips_rot": Vector3(0, -12, 0), "chest": Vector3(4, 12, 0), "head": Vector3(-3, 0, 0),
			"hand_l": Vector3(-0.15, -0.14, 0.5), "hand_r": Vector3(-0.2, -0.24, 0.32), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 60, 0), "wrist_r": Vector3(0, 60, 0),
			"foot_l": Vector3(0.0, 0, 0.2), "foot_r": Vector3(0.08, 0, -0.16), "foot_rot_l": Vector3(0, 0, 0), "foot_rot_r": Vector3(0, 30, 0)}],
		[0.5, {"hips": Vector3(0.0, -0.06, 0.0)}],
	]})
	K.reg(&"stance_civilian", {"length": 1.8, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.0, -0.04, -0.02), "spine": Vector3(6, 0, 0), "chest": Vector3(6, 6, 0), "head": Vector3(-6, 0, 0),
			"hand_l": Vector3(-0.2, -0.08, 0.36), "hand_r": Vector3(-0.24, -0.16, 0.3), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 40, 0), "wrist_r": Vector3(0, 40, 0),
			"foot_l": Vector3(0.0, 0, 0.12), "foot_r": Vector3(0.05, 0, -0.1), "foot_rot_l": Vector3(0, 5, 0), "foot_rot_r": Vector3(0, 25, 0)}],
		[0.5, {"hips": Vector3(0.0, -0.05, -0.02), "hand_l": Vector3(-0.2, -0.1, 0.38)}],
	]})


static func _air_moves() -> void:
	K.reg(&"jump_start", {"length": 0.22, "mask": &"full", "events": [[0.7, &"takeoff"]], "keys": [
		[0.45, {"hips": Vector3(0, -0.14, 0.02), "spine": Vector3(14, 0, 0), "chest": Vector3(8, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_l": Vector3(0.2, -0.75, -0.35), "hand_r": Vector3(0.2, -0.75, -0.35), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK}, &"out"],
		[1.0, {"hips": Vector3(0, 0.04, 0.0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(-4, 0, 0),
			"hand_l": Vector3(0.15, 0.3, 0.5), "hand_r": Vector3(0.15, 0.3, 0.5), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"foot_l": Vector3(0, 0.04, -0.05), "foot_r": Vector3(0, 0.0, -0.08), "foot_rot_l": Vector3(-30, 6, 0), "foot_rot_r": Vector3(-35, 6, 0)}, &"snap"],
	], "hold": true})
	K.reg(&"jump_air", {"length": 1.2, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0, 0.0, 0.0), "spine": Vector3(4, 0, 0), "chest": Vector3(-2, 0, 0), "head": Vector3(-6, 0, 0),
			"hand_l": Vector3(0.3, -0.25, 0.3), "hand_r": Vector3(0.32, -0.2, 0.28), "elbow_l": Vector3(0.8, -0.6, 0), "elbow_r": Vector3(0.8, -0.6, 0),
			"fist_l": 0.3, "fist_r": 0.3,
			"foot_l": Vector3(0.02, 0.26, 0.1), "foot_r": Vector3(0.04, 0.12, -0.12), "foot_rot_l": Vector3(-20, 5, 0), "foot_rot_r": Vector3(-30, 8, 0),
			"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD}],
		[0.5, {"hand_l": Vector3(0.34, -0.2, 0.26), "hand_r": Vector3(0.3, -0.26, 0.3), "foot_l": Vector3(0.02, 0.24, 0.08), "foot_r": Vector3(0.04, 0.14, -0.1)}],
	]})
	K.reg(&"jump_air_air", {"length": 1.0, "loop": true, "keys": [
		[0.0, {"spine": Vector3(-4, 0, 0), "chest": Vector3(-8, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_l": Vector3(0.6, -0.1, 0.1), "hand_r": Vector3(0.6, -0.1, 0.1), "elbow_l": Vector3(0, -1, -0.3), "elbow_r": Vector3(0, -1, -0.3),
			"fist_l": 0.0, "fist_r": 0.0, "wrist_l": Vector3(-30, 0, 0), "wrist_r": Vector3(-30, 0, 0),
			"foot_l": Vector3(0.02, 0.32, 0.12), "foot_r": Vector3(0.03, 0.2, -0.18), "foot_rot_l": Vector3(-25, 5, 0), "foot_rot_r": Vector3(-40, 8, 0)}],
		[0.5, {"hand_l": Vector3(0.62, -0.05, 0.05), "hand_r": Vector3(0.62, -0.05, 0.05), "foot_l": Vector3(0.02, 0.3, 0.1)}],
	]})
	K.reg(&"fall", {"length": 0.9, "loop": true, "keys": [
		[0.0, {"spine": Vector3(-6, 0, 0), "chest": Vector3(-8, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_l": Vector3(0.75, 0.25, 0.1), "hand_r": Vector3(0.7, 0.35, 0.05), "elbow_l": Vector3(0, -1, -0.4), "elbow_r": Vector3(0, -1, -0.4),
			"fist_l": 0.0, "fist_r": 0.0, "wrist_l": Vector3(-25, 0, 0), "wrist_r": Vector3(-25, 0, 0),
			"foot_l": Vector3(0.06, 0.18, 0.12), "foot_r": Vector3(0.08, 0.08, -0.08), "foot_rot_l": Vector3(-15, 8, 0), "foot_rot_r": Vector3(-30, 8, 0)}],
		[0.5, {"hand_l": Vector3(0.7, 0.4, 0.0), "hand_r": Vector3(0.75, 0.2, 0.12), "foot_l": Vector3(0.06, 0.1, -0.06), "foot_r": Vector3(0.08, 0.2, 0.12)}],
	]})
	K.reg(&"land_light", {"length": 0.42, "mask": &"full", "events": [[0.05, &"impact"]], "plants": [[0.02, "l", 0.8], [0.06, "r", 0.8]], "keys": [
		[0.25, {"hips": Vector3(0, -0.12, 0.02), "spine": Vector3(12, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(-10, 0, 0),
			"hand_l": Vector3(0.3, -0.6, 0.25), "hand_r": Vector3(0.3, -0.6, 0.25), "elbow_l": Vector3(0.7, -1, 0), "elbow_r": Vector3(0.7, -1, 0)}, &"snap"],
	]})
	K.reg(&"land_heavy", {"length": 0.85, "mask": &"full", "events": [[0.04, &"impact"]], "plants": [[0.03, "l", 1.3], [0.04, "r", 1.3]], "keys": [
		[0.18, {"hips": Vector3(0, -0.34, 0.05), "spine": Vector3(26, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(-20, 0, 0),
			"hand_l": Vector3(0.25, -0.8, 0.45), "hand_r": Vector3(0.1, -0.55, 0.3), "elbow_l": Vector3(0.6, -1, 0), "elbow_r": Vector3(0.6, -1, 0),
			"foot_l": Vector3(0.06, 0, 0.08), "foot_r": Vector3(0.08, 0, -0.06), "fist_r": 1.0, "fist_l": 0.2, "wrist_l": Vector3(-60, 0, 0)}, &"snap"],
		[0.55, {"hips": Vector3(0, -0.3, 0.04), "spine": Vector3(22, 0, 0)}],
	]})
