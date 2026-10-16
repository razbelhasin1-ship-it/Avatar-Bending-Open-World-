class_name EarthClips
extends RefCounted
## Earthbending body motion for the Earth techniques (Hung Gar: rooted horse
## stance, knee-high chambers, heavy stomps, low fists driven into and lifted
## out of the ground), registered into AnimLibrary (docs/modules/characters.md
## "Clips"):
##
##   earth_pillar_raise   chamber the knee, stomp into horse stance, double uppercut (&"stomp", &"release")
##   earth_stomp_quake    knee to the chest, arms high, stomp + both fists hammered down (&"impact")
##   earth_spikes_drive   coil back, lunge and drive both claws down-forward into the ground (&"release")
##   earth_grab_clench    reach out with an open claw, clench and yank it to the hip (&"release", &"grab")
##   earth_armor_don      double stomp, sweep the plates up, cross-slam the chest (&"gather", &"armor")
##   earth_armor_shed     crouch, arms crossed, burst outward (&"release")
##   earthquake_slam      palms to the ground, rise on the toes fists overhead, slam both fists down (&"gather", &"lift", &"impact", &"pulse")
## EarthClips.ensure() is called by the Earth kit (registry load) and by every
## Earth ability, so rig-less casters get the clip events too.

const K = preload("res://src/characters/anim/clips/clip_kit.gd")

const HORSE := {"foot_l": Vector3(0.3, 0, 0.0), "foot_r": Vector3(0.3, 0, 0.0), "foot_rot_l": Vector3(0, 24, 0), "foot_rot_r": Vector3(0, 24, 0),
	"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}

static var _done := false


static func ensure() -> void:
	if _done:
		return
	_done = true
	_pillar()
	_stomp()
	_spikes()
	_grab()
	_armor()
	_quake()


static func _m(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k: String in b:
		out[k] = b[k]
	return out


static func _pillar() -> void:
	K.reg(&"earth_pillar_raise", {"length": 0.9, "events": [[0.32, &"stomp"], [0.42, &"release"], [0.78, &"recover"]],
		"plants": [[0.32, "r", 1.5]], "keys": [
		# Chamber: weight on the left leg, right knee drawn high, fists at the hips.
		[0.14, {"hips": Vector3(-0.06, -0.04, -0.02), "hips_rot": Vector3(0, 8, 0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-6, 6, 0), "head": Vector3(-6, -6, 0),
			"foot_r": Vector3(0.06, 0.44, 0.14), "knee_r": Vector3(0.25, 0.4, 1.0), "foot_rot_r": Vector3(-20, 10, 0),
			"foot_l": Vector3(0.06, 0.0, 0.0), "knee_l": K.KNEE_OUT,
			"hand_l": Vector3(0.05, -0.52, -0.1), "hand_r": Vector3(0.05, -0.52, -0.1), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(10, -80, 0), "wrist_r": Vector3(10, -80, 0)}, &"inout"],
		# Stomp: the foot slams down into a wide horse stance, fists driven down in front of the knees.
		[0.32, _m(HORSE, {"hips": Vector3(0, -0.3, 0.03), "spine": Vector3(20, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-18, 0, 0),
			"hand_l": Vector3(0.08, -0.86, 0.42), "hand_r": Vector3(0.08, -0.86, 0.42), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0)}), &"in"],
		# Release: a double uppercut - the column erupts.
		[0.42, _m(HORSE, {"hips": Vector3(0, -0.17, 0.05), "spine": Vector3(-6, 0, 0), "chest": Vector3(-12, 0, 0), "head": Vector3(-10, 0, 0),
			"hand_l": Vector3(0.02, 0.32, 0.66), "hand_r": Vector3(0.02, 0.32, 0.66), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": Vector3(0, -80, 0), "wrist_r": Vector3(0, -80, 0), "clav_l": Vector3(10, 0, 0), "clav_r": Vector3(10, 0, 0)}), &"snap"],
		[0.62, {"hips": Vector3(0, -0.19, 0.04), "hand_l": Vector3(0.02, 0.26, 0.62), "hand_r": Vector3(0.02, 0.26, 0.62), "chest": Vector3(-9, 0, 0)}],
	]})


static func _stomp() -> void:
	K.reg(&"earth_stomp_quake", {"length": 0.9, "events": [[0.38, &"impact"], [0.8, &"recover"]],
		"plants": [[0.38, "r", 1.7]], "keys": [
		# Gather: knee to the chest on the left leg, both fists raised high.
		[0.17, {"hips": Vector3(-0.05, 0.03, -0.02), "spine": Vector3(-8, 0, 0), "chest": Vector3(-14, 0, 0), "head": Vector3(-6, 0, 0),
			"foot_r": Vector3(0.08, 0.56, 0.16), "knee_r": Vector3(0.3, 0.5, 1.0), "foot_rot_r": Vector3(-25, 15, 0),
			"foot_l": Vector3(0.05, 0.0, 0.0), "knee_l": K.KNEE_FWD,
			"hand_l": Vector3(0.38, 0.72, 0.18), "hand_r": Vector3(0.38, 0.72, 0.18), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(-20, -80, 0), "wrist_r": Vector3(-20, -80, 0)}, &"out"],
		[0.31, {"hips": Vector3(-0.02, -0.06, 0.0), "foot_r": Vector3(0.14, 0.28, 0.08), "spine": Vector3(4, 0, 0), "chest": Vector3(0, 0, 0),
			"hand_l": Vector3(0.36, 0.25, 0.32), "hand_r": Vector3(0.36, 0.25, 0.32)}, &"in"],
		# Impact: deep horse stance, both fists hammered down beside the knees.
		[0.38, _m(HORSE, {"foot_l": Vector3(0.33, 0, 0.0), "foot_r": Vector3(0.33, 0, 0.0), "hips": Vector3(0, -0.36, 0.0), "spine": Vector3(24, 0, 0),
			"chest": Vector3(12, 0, 0), "head": Vector3(-22, 0, 0),
			"hand_l": Vector3(0.28, -0.92, 0.3), "hand_r": Vector3(0.28, -0.92, 0.3), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0)}), &"snap"],
		[0.56, {"hips": Vector3(0, -0.34, 0.0), "spine": Vector3(21, 0, 0), "hand_l": Vector3(0.28, -0.9, 0.32), "hand_r": Vector3(0.28, -0.9, 0.32)}],
		[0.72, {"hips": Vector3(0, -0.24, 0.0), "spine": Vector3(12, 0, 0), "head": Vector3(-10, 0, 0)}],
	]})


static func _spikes() -> void:
	K.reg(&"earth_spikes_drive", {"length": 0.95, "events": [[0.4, &"release"], [0.82, &"recover"]],
		"plants": [[0.14, "r", 1.0], [0.4, "l", 1.6]], "keys": [
		# Coil: step back on the right foot, both hands cocked at the right hip.
		[0.18, {"hips": Vector3(0, -0.13, -0.08), "hips_rot": Vector3(0, -28, 0), "spine": Vector3(2, -8, 0), "chest": Vector3(-4, -24, 0), "head": Vector3(-4, 26, 0),
			"foot_r": Vector3(0.12, 0.0, -0.36), "foot_l": Vector3(0.06, 0.0, 0.16), "foot_rot_r": Vector3(0, 40, 0), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT,
			"hand_r": Vector3(0.18, -0.55, -0.12), "hand_l": Vector3(-0.28, -0.5, 0.08), "elbow_r": K.ELBOW_BACK, "elbow_l": K.ELBOW_DOWN,
			"fist_l": 0.6, "fist_r": 0.6, "wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0)}, &"inout"],
		# Release: lunge on the left foot and drive both claws down into the ground ahead.
		[0.4, {"hips": Vector3(0, -0.33, 0.18), "hips_rot": Vector3(8, 8, 0), "spine": Vector3(30, 0, 0), "chest": Vector3(14, 6, 0), "head": Vector3(-28, 0, 0),
			"foot_l": Vector3(0.1, 0.0, 0.56), "foot_r": Vector3(0.16, 0.0, -0.42), "foot_rot_r": Vector3(0, 35, 0), "foot_rot_l": Vector3(0, 8, 0),
			"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(-0.04, -0.78, 0.62), "hand_r": Vector3(0.06, -0.8, 0.6), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(-55, 90, 0), "wrist_r": Vector3(-55, 90, 0), "fist_l": 0.45, "fist_r": 0.45}, &"snap"],
		[0.64, {"hips": Vector3(0, -0.3, 0.15), "spine": Vector3(26, 0, 0), "hand_l": Vector3(-0.04, -0.76, 0.6), "hand_r": Vector3(0.06, -0.78, 0.58)}],
	]})


static func _grab() -> void:
	K.reg(&"earth_grab_clench", {"length": 1.05, "events": [[0.3, &"release"], [0.55, &"grab"], [0.85, &"recover"]],
		"plants": [[0.22, "l", 1.0], [0.55, "r", 1.3]], "keys": [
		# Reach: step in, the right arm shoots out low with an open claw.
		[0.18, {"hips": Vector3(0, -0.12, 0.08), "hips_rot": Vector3(0, 12, 0), "chest": Vector3(6, 20, 0), "head": Vector3(-8, -18, 0),
			"foot_l": Vector3(0.08, 0.0, 0.34), "foot_r": Vector3(0.14, 0.0, -0.22), "foot_rot_r": Vector3(0, 30, 0), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT,
			"hand_r": Vector3(-0.06, -0.22, 0.98), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(-25, 0, 0), "fist_r": 0.0, "clav_r": Vector3(0, 16, 0),
			"hand_l": Vector3(-0.22, -0.3, 0.36), "elbow_l": K.ELBOW_DOWN, "fist_l": 1.0}, &"out"],
		[0.3, {"hand_r": Vector3(-0.06, -0.26, 1.02), "wrist_r": Vector3(-35, 0, 0), "fist_r": 0.0}],
		# Grab: the claw clenches and yanks down to the hip, the bender sinks into the pull.
		[0.55, _m(HORSE, {"hips": Vector3(0, -0.24, -0.03), "hips_rot": Vector3(0, -8, 0), "chest": Vector3(8, -14, 0), "spine": Vector3(8, 0, 0), "head": Vector3(-14, 8, 0),
			"hand_r": Vector3(0.1, -0.56, 0.1), "elbow_r": K.ELBOW_BACK, "wrist_r": Vector3(10, -80, 0), "fist_r": 1.0, "clav_r": Vector3(0, -6, 0),
			"hand_l": Vector3(-0.1, -0.35, 0.45), "fist_l": 1.0}), &"snap"],
		[0.74, {"hips": Vector3(0, -0.22, -0.02), "hand_r": Vector3(0.1, -0.54, 0.12)}],
	]})


static func _armor() -> void:
	K.reg(&"earth_armor_don", {"length": 1.15, "events": [[0.24, &"gather"], [0.66, &"armor"], [0.86, &"recover"]],
		"plants": [[0.24, "l", 1.4], [0.26, "r", 1.4]], "keys": [
		[0.11, {"hips": Vector3(0, -0.1, 0.0), "head": Vector3(10, 0, 0), "hand_l": Vector3(0.05, -0.5, -0.1), "hand_r": Vector3(0.05, -0.5, -0.1),
			"elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "fist_l": 1.0, "fist_r": 1.0}, &"inout"],
		# Double stomp into the horse stance, palms down by the knees: the plates tear loose.
		[0.24, _m(HORSE, {"hips": Vector3(0, -0.3, 0.0), "spine": Vector3(20, 0, 0), "chest": Vector3(8, 0, 0), "head": Vector3(-16, 0, 0),
			"hand_l": Vector3(0.18, -0.86, 0.3), "hand_r": Vector3(0.18, -0.86, 0.3), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0), "fist_l": 0.6, "fist_r": 0.6}), &"snap"],
		# Sweep up and around: the plates rise.
		[0.48, _m(HORSE, {"hips": Vector3(0, -0.18, 0.0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-14, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_l": Vector3(0.78, 0.28, 0.32), "hand_r": Vector3(0.78, 0.28, 0.32), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": Vector3(-30, -90, 0), "wrist_r": Vector3(-30, -90, 0), "fist_l": 0.3, "fist_r": 0.3}), &"inout"],
		# Armor: fists cross-slam onto the chest, plates lock on.
		[0.66, _m(HORSE, {"hips": Vector3(0, -0.24, 0.02), "spine": Vector3(6, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(-6, 0, 0),
			"hand_l": Vector3(-0.36, -0.16, 0.26), "hand_r": Vector3(-0.36, -0.12, 0.28), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 90, 0), "wrist_r": Vector3(0, 90, 0)}), &"snap"],
		# Power stance: fists out at the sides.
		[0.8, _m(HORSE, {"hips": Vector3(0, -0.22, 0.0), "chest": Vector3(-6, 0, 0), "head": Vector3(-4, 0, 0),
			"hand_l": Vector3(0.46, -0.56, 0.2), "hand_r": Vector3(0.46, -0.56, 0.2), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(10, -80, 0), "wrist_r": Vector3(10, -80, 0)}), &"out"],
	]})
	K.reg(&"earth_armor_shed", {"length": 0.65, "events": [[0.36, &"release"], [0.8, &"recover"]], "plants": [[0.36, "r", 1.2]], "keys": [
		[0.2, {"hips": Vector3(0, -0.26, 0.0), "spine": Vector3(16, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_l": Vector3(-0.3, -0.34, 0.3), "hand_r": Vector3(-0.3, -0.32, 0.32), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"fist_l": 1.0, "fist_r": 1.0}, &"inout"],
		[0.36, _m(HORSE, {"hips": Vector3(0, -0.14, 0.0), "spine": Vector3(-6, 0, 0), "chest": Vector3(-14, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_l": Vector3(0.95, 0.06, -0.05), "hand_r": Vector3(0.95, 0.06, -0.05), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": Vector3(-40, 90, 0), "wrist_r": Vector3(-40, 90, 0), "fist_l": 0.0, "fist_r": 0.0}), &"snap"],
		[0.56, {"hips": Vector3(0, -0.15, 0.0), "hand_l": Vector3(0.9, 0.0, 0.0), "hand_r": Vector3(0.9, 0.0, 0.0)}],
	]})


static func _quake() -> void:
	K.reg(&"earthquake_slam", {"length": 1.7, "events": [[0.12, &"gather"], [0.4, &"lift"], [0.56, &"impact"], [0.72, &"pulse"], [0.88, &"recover"]],
		"plants": [[0.1, "l", 1.0], [0.56, "l", 1.8], [0.565, "r", 1.8]], "keys": [
		# Gather: crouch, both palms pressed to the ground - the earth starts to tremble.
		[0.12, _m(HORSE, {"hips": Vector3(0, -0.44, 0.04), "spine": Vector3(44, 0, 0), "chest": Vector3(18, 0, 0), "head": Vector3(-30, 0, 0),
			"hand_l": Vector3(0.14, -0.98, 0.52), "hand_r": Vector3(0.14, -0.98, 0.52), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(60, 0, 0), "wrist_r": Vector3(60, 0, 0), "fist_l": 0.0, "fist_r": 0.0}), &"inout"],
		[0.26, _m(HORSE, {"hips": Vector3(0, -0.42, 0.04), "spine": Vector3(40, 0, 0), "hand_l": Vector3(0.16, -0.96, 0.5), "hand_r": Vector3(0.16, -0.96, 0.5)})],
		# Lift: rise tall with both fists overhead, the ground heaving around.
		[0.4, {"hips": Vector3(0, 0.03, -0.02), "spine": Vector3(-10, 0, 0), "chest": Vector3(-18, 0, 0), "head": Vector3(-12, 0, 0),
			"foot_l": Vector3(0.16, 0.04, 0.0), "foot_r": Vector3(0.16, 0.04, 0.0), "foot_rot_l": Vector3(-14, 12, 0), "foot_rot_r": Vector3(-14, 12, 0),
			"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
			"hand_l": Vector3(0.14, 0.98, 0.12), "hand_r": Vector3(0.14, 0.98, 0.12), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(-20, -80, 0), "wrist_r": Vector3(-20, -80, 0)}, &"out"],
		# Impact: drop onto the right knee and drive the right fist into the ground,
		# the left arm flung back for balance (the iconic earthquake punch).
		[0.56, {"hips": Vector3(0.02, -0.6, 0.06), "hips_rot": Vector3(6, -10, 0), "spine": Vector3(38, 6, 0), "chest": Vector3(16, 10, 0), "head": Vector3(-26, -8, 0),
			"foot_l": Vector3(0.16, 0.0, 0.42), "foot_r": Vector3(0.18, 0.0, -0.46), "foot_rot_l": Vector3(0, 12, 0), "foot_rot_r": Vector3(-35, 20, 0),
			"knee_l": Vector3(0.3, 0.2, 1.0), "knee_r": Vector3(0.2, -0.6, 1.0), "toe_r": 40.0,
			"hand_r": Vector3(0.02, -0.92, 0.6), "elbow_r": K.ELBOW_OUT, "wrist_r": Vector3(20, -80, 0), "fist_r": 1.0, "clav_r": Vector3(-6, 14, 0),
			"hand_l": Vector3(0.5, -0.38, -0.6), "elbow_l": K.ELBOW_DOWN, "wrist_l": Vector3(-30, 60, 0), "fist_l": 0.3}, &"in"],
		[0.72, {"hips": Vector3(0.02, -0.58, 0.05), "spine": Vector3(36, 6, 0), "hand_r": Vector3(0.02, -0.91, 0.61), "hand_l": Vector3(0.5, -0.4, -0.58)}],
		[0.84, {"hips": Vector3(0, -0.36, 0.04), "spine": Vector3(20, 0, 0), "chest": Vector3(8, 0, 0), "head": Vector3(-14, 0, 0),
			"foot_l": Vector3(0.2, 0.0, 0.2), "foot_r": Vector3(0.22, 0.0, -0.2), "knee_r": K.KNEE_OUT, "toe_r": 0.0}],
	]})
