class_name BendingClips
extends RefCounted
## Extra HumanoidRig clips the bending kits need, registered into AnimLibrary
## (characters module convention, see docs/modules/characters.md "Clips"):
##   air_dash, air_glide (loop), air_jump_flip, water_skate (loop),
##   earth_slide_fwd, earth_hold (loop, upper), water_gather_hold (loop, upper),
##   flame_sweep_kick, fire_guard_hold (loop, upper).
## Call BendingClips.ensure() before playing them (PlayerVisual does).

const K = preload("res://src/characters/anim/clips/clip_kit.gd")

static var _done := false


static func ensure() -> void:
	if _done:
		return
	_done = true
	_air()
	_water()
	_earth()
	_fire()


static func _air() -> void:
	# Wind-assisted dash: body pitched into the motion, arms swept back, legs tucked.
	K.reg(&"air_dash", {"length": 0.5, "events": [[0.05, &"dodge"], [0.82, &"recover"]], "plants": [[0.86, "l", 0.5], [0.9, "r", 0.5]], "keys": [
		[0.12, {"hips": Vector3(0, -0.08, 0.06), "hips_rot": Vector3(14, 0, 0), "spine": Vector3(22, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(-26, 0, 0),
			"hand_l": Vector3(0.3, -0.42, -0.62), "hand_r": Vector3(0.3, -0.42, -0.62), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK,
			"wrist_l": Vector3(-25, 0, 0), "wrist_r": Vector3(-25, 0, 0), "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0.0, 0.3, 0.18), "foot_r": Vector3(0.04, 0.42, -0.3), "foot_rot_l": Vector3(-30, 4, 0), "foot_rot_r": Vector3(-55, 6, 0),
			"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD}, &"snap"],
		[0.6, {"hips": Vector3(0, -0.06, 0.05), "hips_rot": Vector3(10, 0, 0), "spine": Vector3(18, 0, 0), "hand_l": Vector3(0.38, -0.35, -0.55), "hand_r": Vector3(0.36, -0.38, -0.58),
			"foot_l": Vector3(0.0, 0.26, 0.2), "foot_r": Vector3(0.04, 0.36, -0.24)}],
		[0.86, {"hips": Vector3(0, -0.14, 0.02), "spine": Vector3(12, 0, 0), "chest": Vector3(4, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_l": Vector3(0.35, -0.55, 0.15), "hand_r": Vector3(0.35, -0.55, 0.15), "foot_l": Vector3(0.0, 0.0, 0.12), "foot_r": Vector3(0.05, 0.0, -0.12),
			"foot_rot_l": Vector3(0, 4, 0), "foot_rot_r": Vector3(0, 6, 0)}, &"out"],
	]})
	# Gliding on the wind: arms spread like wings, legs trailing together.
	K.reg(&"air_glide", {"length": 1.6, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0, 0.0, 0.0), "hips_rot": Vector3(16, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(2, 0, 0), "head": Vector3(-26, 0, 0),
			"hand_l": Vector3(0.95, 0.12, 0.12), "hand_r": Vector3(0.95, 0.1, 0.1), "elbow_l": Vector3(0, -1, -0.2), "elbow_r": Vector3(0, -1, -0.2),
			"wrist_l": Vector3(-10, 0, 0), "wrist_r": Vector3(-10, 0, 0), "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(-0.02, 0.22, -0.22), "foot_r": Vector3(0.0, 0.28, -0.3), "foot_rot_l": Vector3(-55, 0, 0), "foot_rot_r": Vector3(-60, 0, 0),
			"knee_l": Vector3(0.1, -0.2, 1.0), "knee_r": Vector3(0.1, -0.2, 1.0)}],
		[0.5, {"hand_l": Vector3(0.95, 0.04, 0.16), "hand_r": Vector3(0.95, 0.18, 0.06), "chest": Vector3(2, 0, -4), "hips_rot": Vector3(16, 0, -3)}],
	]})
	# Air jump: tucked front somersault on the wind.
	K.reg(&"air_jump_flip", {"length": 0.6, "keys": [
		[0.1, {"hips": Vector3(0, 0.0, 0.0), "spine": Vector3(18, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(10, 0, 0),
			"hand_l": Vector3(0.25, -0.3, 0.45), "hand_r": Vector3(0.25, -0.3, 0.45), "fist_l": 0.4, "fist_r": 0.4,
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.35, 0.3), "foot_r": Vector3(0.02, 0.32, 0.28), "knee_l": Vector3(0.1, 0.5, 1), "knee_r": Vector3(0.1, 0.5, 1)}, &"out"],
		[0.32, {"hips": Vector3(0, 0.05, 0.0), "hips_rot": Vector3(150, 0, 0), "spine": Vector3(30, 0, 0), "chest": Vector3(24, 0, 0), "head": Vector3(26, 0, 0),
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.55, 0.45), "foot_r": Vector3(0.02, 0.52, 0.44), "hand_l": Vector3(0.1, -0.4, 0.42), "hand_r": Vector3(0.1, -0.4, 0.42)}],
		[0.58, {"hips_rot": Vector3(280, 0, 0), "feet_hips": 1.0, "foot_l": Vector3(0.0, 0.5, 0.38), "foot_r": Vector3(0.02, 0.48, 0.36)}],
		[0.85, {"hips": Vector3(0, 0.0, 0.0), "hips_rot": Vector3(360, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0),
			"feet_hips": 0.0, "foot_l": Vector3(0.02, 0.26, 0.1), "foot_r": Vector3(0.04, 0.14, -0.12), "hand_l": Vector3(0.6, -0.1, 0.1), "hand_r": Vector3(0.6, -0.1, 0.1),
			"fist_l": 0.0, "fist_r": 0.0}, &"out"],
	]})


static func _water() -> void:
	# Skating on ice/snow: low, long alternating push-offs, arms flowing.
	K.reg(&"water_skate", {"length": 1.15, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0.05, -0.16, 0.0), "hips_rot": Vector3(8, 14, -5), "spine": Vector3(12, -6, 3), "chest": Vector3(6, -10, 4), "head": Vector3(-10, 18, 0),
			"foot_l": Vector3(0.04, 0.0, 0.12), "foot_r": Vector3(0.32, 0.05, -0.38), "foot_rot_l": Vector3(0, 6, 0), "foot_rot_r": Vector3(-8, -28, 6),
			"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(0.2, -0.32, 0.5), "hand_r": Vector3(0.48, -0.5, -0.25), "wrist_l": Vector3(-30, 80, 0), "wrist_r": Vector3(-20, 60, 0),
			"fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": Vector3(0.6, -0.6, -0.6)}],
		[0.25, {"hips": Vector3(0.0, -0.12, 0.0), "hips_rot": Vector3(8, 0, 0), "foot_l": Vector3(0.04, 0.0, 0.05), "foot_r": Vector3(0.08, 0.14, -0.05),
			"chest": Vector3(6, 0, 0), "hand_l": Vector3(0.32, -0.42, 0.25), "hand_r": Vector3(0.32, -0.42, 0.25)}],
		[0.5, {"hips": Vector3(-0.05, -0.16, 0.0), "hips_rot": Vector3(8, -14, 5), "spine": Vector3(12, 6, -3), "chest": Vector3(6, 10, -4), "head": Vector3(-10, -18, 0),
			"foot_r": Vector3(0.04, 0.0, 0.12), "foot_l": Vector3(0.32, 0.05, -0.38), "foot_rot_r": Vector3(0, 6, 0), "foot_rot_l": Vector3(-8, -28, 6),
			"knee_r": K.KNEE_FWD, "knee_l": K.KNEE_OUT,
			"hand_r": Vector3(0.2, -0.32, 0.5), "hand_l": Vector3(0.48, -0.5, -0.25), "wrist_r": Vector3(-30, 80, 0), "wrist_l": Vector3(-20, 60, 0),
			"elbow_r": K.ELBOW_DOWN, "elbow_l": Vector3(0.6, -0.6, -0.6)}],
		[0.75, {"hips": Vector3(0.0, -0.12, 0.0), "hips_rot": Vector3(8, 0, 0), "foot_r": Vector3(0.04, 0.0, 0.05), "foot_l": Vector3(0.08, 0.14, -0.05),
			"chest": Vector3(6, 0, 0), "hand_l": Vector3(0.32, -0.42, 0.25), "hand_r": Vector3(0.32, -0.42, 0.25)}],
	]})
	# Gathering water around the body while charging a torrent.
	K.reg(&"water_gather_hold", {"length": 1.5, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(4, -12, 0), "spine": Vector3(2, -6, 0), "hand_l": Vector3(0.55, -0.35, 0.35), "hand_r": Vector3(0.2, -0.55, 0.05),
			"wrist_l": Vector3(-40, 70, 0), "wrist_r": Vector3(-40, -60, 0), "fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_DOWN}],
		[0.25, {"chest": Vector3(4, 0, 0), "hand_l": Vector3(0.35, -0.2, 0.55), "hand_r": Vector3(0.35, -0.2, 0.55)}],
		[0.5, {"chest": Vector3(4, 12, 0), "spine": Vector3(2, 6, 0), "hand_r": Vector3(0.55, -0.35, 0.35), "hand_l": Vector3(0.2, -0.55, 0.05),
			"wrist_r": Vector3(-40, 70, 0), "wrist_l": Vector3(-40, -60, 0), "elbow_r": K.ELBOW_OUT, "elbow_l": K.ELBOW_DOWN}],
		[0.75, {"chest": Vector3(4, 0, 0), "hand_l": Vector3(0.3, -0.5, 0.3), "hand_r": Vector3(0.3, -0.5, 0.3)}],
	]})


static func _earth() -> void:
	# Forward earth slide: low lunge riding the ground, guard up.
	K.reg(&"earth_slide_fwd", {"length": 0.55, "events": [[0.05, &"dodge"], [0.85, &"recover"]], "plants": [[0.1, "l", 1.3], [0.82, "r", 1.1]], "keys": [
		[0.15, {"hips": Vector3(0, -0.3, 0.06), "hips_rot": Vector3(4, 10, 0), "spine": Vector3(8, -6, 0), "chest": Vector3(4, -10, 0), "head": Vector3(-8, 10, 0),
			"foot_l": Vector3(0.1, 0.0, 0.48), "foot_r": Vector3(0.14, 0.0, -0.42), "foot_rot_l": Vector3(0, 10, 0), "foot_rot_r": Vector3(0, 40, 0),
			"knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(-0.15, -0.22, 0.48), "hand_r": Vector3(0.05, -0.38, 0.32), "fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"snap"],
		[0.7, {"hips": Vector3(0, -0.28, 0.04), "foot_l": Vector3(0.1, 0.0, 0.42), "foot_r": Vector3(0.14, 0.0, -0.38)}],
	]})
	# Holding a lifted boulder overhead, ready to hurl.
	K.reg(&"earth_hold", {"length": 1.6, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(-8, -14, 0), "spine": Vector3(-4, -6, 0), "head": Vector3(6, 10, 0),
			"hand_l": Vector3(-0.1, 0.62, 0.42), "hand_r": Vector3(-0.05, 0.58, 0.38), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(-60, -20, 0), "wrist_r": Vector3(-60, 20, 0), "fist_l": 0.25, "fist_r": 0.25, "clav_l": Vector3(14, 0, 0), "clav_r": Vector3(14, 0, 0)}],
		[0.5, {"chest": Vector3(-9, -15, 0), "hand_l": Vector3(-0.1, 0.65, 0.4), "hand_r": Vector3(-0.05, 0.6, 0.36)}],
	]})


static func _fire() -> void:
	# Low spinning sweep kick: crouch, the right leg sweeps a wide arc along the
	# ground (the flame wave is spawned at "impact"), ends facing forward.
	K.reg(&"flame_sweep_kick", {"length": 0.8, "events": [[0.46, &"impact"], [0.86, &"recover"]], "plants": [[0.9, "r", 1.0]], "keys": [
		[0.16, {"hips": Vector3(0, -0.36, 0.0), "hips_rot": Vector3(10, 40, 0), "spine": Vector3(18, 10, 0), "chest": Vector3(10, 10, 0), "head": Vector3(-14, -40, 0),
			"hand_l": Vector3(0.35, -0.92, 0.35), "hand_r": Vector3(0.45, -0.55, -0.1), "fist_l": 0.0, "fist_r": 1.0, "wrist_l": Vector3(-70, 0, 0),
			"foot_r": Vector3(0.45, 0.02, 0.15), "foot_l": Vector3(0.05, 0.0, 0.0), "knee_l": K.KNEE_OUT, "knee_r": Vector3(0.6, 0.6, 0.4)}, &"out"],
		[0.32, {"hips": Vector3(0, -0.46, 0.0), "hips_rot": Vector3(12, -40, 0), "foot_r": Vector3(0.85, 0.04, -0.2), "knee_r": Vector3(0.2, 1.0, 0.0),
			"chest": Vector3(12, 30, 0), "head": Vector3(-10, -20, 0), "hand_l": Vector3(0.25, -0.95, 0.4)}],
		[0.46, {"hips": Vector3(0, -0.5, 0.0), "hips_rot": Vector3(12, -110, 0), "foot_r": Vector3(0.2, 0.05, -0.9), "knee_r": Vector3(0.2, 1.0, 0.0),
			"chest": Vector3(12, 40, 0), "spine": Vector3(16, 20, 0), "head": Vector3(-10, 10, 0), "foot_rot_r": Vector3(0, -60, 70)}, &"snap"],
		[0.64, {"hips": Vector3(0, -0.46, 0.0), "hips_rot": Vector3(10, -190, 0), "foot_r": Vector3(-0.7, 0.05, -0.35), "chest": Vector3(10, 30, 0), "head": Vector3(-10, 30, 0)}],
		[0.84, {"hips": Vector3(0, -0.24, 0.0), "hips_rot": Vector3(4, -360, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(4, 0, 0), "head": Vector3(-4, 0, 0),
			"foot_r": Vector3(0.12, 0.0, -0.2), "hand_l": Vector3(-0.2, -0.2, 0.45), "hand_r": Vector3(0.1, -0.4, 0.2), "fist_l": 1.0}, &"out"],
	]})
	# Flame Guard: forearms crossed high in front, fists burning.
	K.reg(&"fire_guard_hold", {"length": 0.8, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(6, -10, 0), "spine": Vector3(4, -4, 0), "hand_l": Vector3(-0.32, -0.02, 0.48), "hand_r": Vector3(-0.3, 0.08, 0.5),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 90, 0), "wrist_r": Vector3(0, 90, 0)}],
		[0.5, {"chest": Vector3(7, -11, 0), "hand_l": Vector3(-0.31, -0.0, 0.5)}],
	]})
