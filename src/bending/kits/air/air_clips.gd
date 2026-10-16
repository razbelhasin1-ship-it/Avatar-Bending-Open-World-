class_name AirClips
extends RefCounted
## Airbending body motion for the Air techniques (Ba Gua: circle walking, spins,
## palms that gather and release, light leaps), registered into AnimLibrary
## (docs/modules/characters.md "Clips"):
##
##   air_push_gather     (loop) rooted, sunk, both palms hold a ball of air at the chest that
##                       slowly orbits (the charge)
##   air_push_release    pull the ball in, then stomp into a wide horse stance and throw both
##                       palms out to the sides: the radial gust (&"gather", &"release")
##   air_scooter_ride    (loop) crouched on the ball of air, arms out for balance
##   air_combo_kick      Air Combo step 2: pivot and hook the right leg round low through the
##                       front (&"impact": the low wide gust leaves the foot)
##   wind_blade_kick     coil, spin on the left foot, the right leg cuts a high crescent through
##                       the front (&"release": the blade leaves the foot), land on guard
##   wind_blade_air      aerial front flip ending in a chopping axe kick (&"release")
##   air_tornado_cast    sink and coil, two fast spins with the arms rising (&"gather",
##                       &"release": the vortex forms), stir the vortex with circling palms,
##                       throw both palms to the sky (&"impact": the release), settle
##   air_dive            (loop) falling hard: knees tucked, both arms raised for the slam
##   air_slam_land       drop onto one knee driving the palm into the ground (&"impact")
##   vortex_ward_hold    (loop, upper) both palms circling around the body, guiding the wind
## AirClips.ensure() runs from the Air kit (registry load) and every Air ability,
## so rig-less casters get the same clip events.

const K = preload("res://src/characters/anim/clips/clip_kit.gd")

## Wide horse stance (feet out, toes out, knees out).
const HORSE := {"foot_l": Vector3(0.3, 0, 0.02), "foot_r": Vector3(0.3, 0, -0.02), "foot_rot_l": Vector3(0, 24, 0), "foot_rot_r": Vector3(0, 24, 0),
	"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}
## Palm forward, fingers up.
const PALM := Vector3(-80, 90, 0)
## Palm down, fingers forward.
const PALM_DOWN := Vector3(-75, 90, 0)

static var _done := false


static func ensure() -> void:
	if _done:
		return
	_done = true
	_push()
	_scooter()
	_combo_kick()
	_blade()
	_tornado()
	_slam()
	_ward()


static func _m(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k: String in b:
		out[k] = b[k]
	return out


static func _push() -> void:
	# Holding the ball: left palm above, right palm below, a slow orbit of the hands and torso.
	var hold := {"hips": Vector3(0, -0.13, -0.02), "spine": Vector3(6, 0, 0), "chest": Vector3(2, -8, 0), "head": Vector3(-4, 8, 0),
		"foot_l": Vector3(0.15, 0, 0.07), "foot_r": Vector3(0.15, 0, -0.07), "foot_rot_l": Vector3(0, 16, 0), "foot_rot_r": Vector3(0, 16, 0),
		"knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT,
		"hand_l": Vector3(-0.12, -0.08, 0.56), "hand_r": Vector3(-0.12, -0.46, 0.5), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
		"wrist_l": Vector3(-10, -80, 0), "wrist_r": Vector3(-10, 80, 0), "fist_l": 0.0, "fist_r": 0.0}
	K.reg(&"air_push_gather", {"length": 1.1, "loop": true, "keys": [
		[0.0, hold],
		[0.25, {"chest": Vector3(2, 0, 0), "head": Vector3(-4, 0, 0), "hand_l": Vector3(0.06, -0.22, 0.6), "hand_r": Vector3(-0.3, -0.3, 0.46)}],
		[0.5, {"chest": Vector3(2, 8, 0), "head": Vector3(-4, -8, 0), "hand_l": Vector3(-0.12, -0.46, 0.5), "hand_r": Vector3(-0.12, -0.08, 0.56),
			"wrist_l": Vector3(-10, 80, 0), "wrist_r": Vector3(-10, -80, 0)}],
		[0.75, {"chest": Vector3(2, 0, 0), "head": Vector3(-4, 0, 0), "hand_l": Vector3(-0.3, -0.3, 0.46), "hand_r": Vector3(0.06, -0.22, 0.6)}],
	]})
	K.reg(&"air_push_release", {"length": 0.62, "events": [[0.16, &"gather"], [0.3, &"release"], [0.72, &"recover"]],
		"plants": [[0.29, "l", 1.2], [0.3, "r", 1.2]], "keys": [
		# Pull the air in: sink, both palms drawn to the chest, elbows wide, chin down.
		[0.15, {"hips": Vector3(0, -0.2, -0.04), "spine": Vector3(14, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(4, 0, 0),
			"foot_l": Vector3(0.2, 0.0, 0.05), "foot_r": Vector3(0.2, 0.0, -0.05), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(-0.06, -0.36, 0.24), "hand_r": Vector3(-0.06, -0.42, 0.22), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(-10, -80, 0), "wrist_r": Vector3(-10, 80, 0), "fist_l": 0.0, "fist_r": 0.0,
			"clav_l": Vector3(-6, -8, 0), "clav_r": Vector3(-6, -8, 0)}, &"inout"],
		# Release: stomp into a wide horse stance, chest opens, both palms thrown out to the sides.
		[0.3, _m(HORSE, {"hips": Vector3(0, -0.28, 0.02), "spine": Vector3(-2, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-10, 0, 0),
			"hand_l": Vector3(0.94, -0.1, 0.3), "hand_r": Vector3(0.94, -0.1, 0.3), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": PALM, "wrist_r": PALM, "clav_l": Vector3(8, 10, 0), "clav_r": Vector3(8, 10, 0)}), &"snap"],
		[0.56, _m(HORSE, {"hips": Vector3(0, -0.25, 0.0), "chest": Vector3(-6, 0, 0), "head": Vector3(-6, 0, 0),
			"hand_l": Vector3(0.86, -0.22, 0.34), "hand_r": Vector3(0.86, -0.22, 0.34)})],
	]})


static func _scooter() -> void:
	# Crouched on the ball, weight over the toes, leading arm forward, trailing arm out back.
	var ride := {"hips": Vector3(0, -0.3, 0.0), "hips_rot": Vector3(8, 0, 0), "spine": Vector3(20, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(-28, 0, 0),
		"foot_l": Vector3(0.05, 0.0, 0.1), "foot_r": Vector3(0.07, 0.0, -0.08), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
		"foot_rot_l": Vector3(0, 8, 0), "foot_rot_r": Vector3(0, 16, 0),
		"hand_l": Vector3(0.62, -0.3, 0.45), "hand_r": Vector3(0.76, -0.24, -0.22), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
		"wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN, "fist_l": 0.0, "fist_r": 0.0}
	K.reg(&"air_scooter_ride", {"length": 0.9, "loop": true, "keys": [
		[0.0, ride],
		[0.5, {"hips": Vector3(0, -0.34, 0.0), "spine": Vector3(22, 0, 0), "hand_l": Vector3(0.66, -0.25, 0.42), "hand_r": Vector3(0.72, -0.3, -0.24)}],
	]})


static func _combo_kick() -> void:
	# Air Combo step 2: pivot on the left foot, the right leg hooks round low through the
	# front (the wide low gust leaves the foot), land back on guard.
	K.reg(&"air_combo_kick", {"length": 0.62, "events": [[0.42, &"impact"], [0.8, &"recover"]], "plants": [[0.86, "r", 0.7]], "keys": [
		[0.18, {"hips": Vector3(0, -0.12, 0.0), "hips_rot": Vector3(-4, -70, 0), "chest": Vector3(2, 18, 0), "head": Vector3(-6, 40, 0),
			"foot_l": Vector3(0.04, 0.0, 0.04), "knee_l": K.KNEE_FWD, "foot_r": Vector3(0.3, 0.3, 0.12), "knee_r": Vector3(0.6, 0.5, 0.5),
			"hand_l": Vector3(0.6, -0.2, 0.25), "hand_r": Vector3(0.5, -0.3, -0.2), "fist_l": 0.0, "fist_r": 0.0, "wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN}, &"out"],
		[0.42, {"hips": Vector3(0, -0.1, 0.0), "hips_rot": Vector3(-10, -200, 12), "spine": Vector3(-4, 0, 6), "chest": Vector3(-4, 16, 0), "head": Vector3(0, -24, 0),
			"foot_r": Vector3(0.92, 0.5, 0.0), "knee_r": Vector3(0.2, 1.0, 0.0), "foot_rot_r": Vector3(-10, -40, 50),
			"hand_l": Vector3(0.92, -0.05, 0.1), "hand_r": Vector3(0.88, -0.1, 0.1), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"snap"],
		[0.62, {"hips": Vector3(0, -0.14, 0.0), "hips_rot": Vector3(-4, -300, 0), "foot_r": Vector3(0.4, 0.2, -0.2), "chest": Vector3(0, 8, 0), "head": Vector3(-4, 0, 0)}],
		[0.88, {"hips": Vector3(0, -0.12, 0.0), "hips_rot": Vector3(0, -360, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(2, 0, 0), "head": Vector3(-4, 0, 0),
			"foot_r": Vector3(0.12, 0.0, -0.16), "foot_l": Vector3(0.05, 0.0, 0.14), "hand_l": Vector3(-0.18, -0.2, 0.46), "hand_r": Vector3(0.05, -0.36, 0.3)}, &"out"],
	]})


static func _blade() -> void:
	K.reg(&"wind_blade_kick", {"length": 0.72, "events": [[0.44, &"release"], [0.84, &"recover"]],
		"plants": [[0.84, "r", 1.0]], "keys": [
		# Coil: twist left, both blade-hands wound to the left, weight on the left foot.
		[0.12, {"hips": Vector3(0, -0.14, 0.0), "hips_rot": Vector3(4, 50, 0), "spine": Vector3(8, 10, 0), "chest": Vector3(6, 24, 0), "head": Vector3(-6, -42, 0),
			"foot_l": Vector3(0.06, 0.0, 0.08), "foot_r": Vector3(0.18, 0.0, -0.15), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT, "foot_rot_r": Vector3(0, 30, 0),
			"hand_l": Vector3(0.56, -0.28, -0.22), "hand_r": Vector3(-0.12, -0.3, 0.52), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_DOWN,
			"fist_l": 0.0, "fist_r": 0.0, "wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN}, &"out"],
		# Spin on the left foot, the right knee chambers high.
		[0.3, {"hips": Vector3(0, -0.04, 0.0), "hips_rot": Vector3(-8, -110, 0), "chest": Vector3(-4, 10, 0), "head": Vector3(-6, -20, 0),
			"foot_r": Vector3(0.42, 0.52, 0.14), "knee_r": Vector3(0.6, 0.6, 0.4), "foot_l": Vector3(0.04, 0.0, 0.0), "knee_l": K.KNEE_FWD,
			"hand_l": Vector3(0.86, 0.0, 0.1), "hand_r": Vector3(0.82, 0.0, 0.1), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}],
		# Release: the leg extended high whips through the front, the arms cut the other way.
		[0.44, {"hips": Vector3(0, -0.02, 0.0), "hips_rot": Vector3(-16, -200, 22), "spine": Vector3(-8, 0, 12), "chest": Vector3(-8, 18, 0), "head": Vector3(0, -20, -10),
			"foot_r": Vector3(0.95, 1.02, 0.05), "knee_r": Vector3(0.2, 1.0, 0.0), "foot_rot_r": Vector3(-10, -40, 60),
			"hand_l": Vector3(0.95, 0.1, 0.05), "hand_r": Vector3(0.9, 0.06, 0.05), "wrist_l": PALM, "wrist_r": PALM}, &"snap"],
		[0.62, {"hips": Vector3(0, -0.1, 0.0), "hips_rot": Vector3(-4, -300, 0), "foot_r": Vector3(0.5, 0.32, -0.2), "chest": Vector3(0, 10, 0), "head": Vector3(-4, 0, 0)}],
		# Land light on guard, facing the front again.
		[0.84, {"hips": Vector3(0, -0.16, 0.0), "hips_rot": Vector3(2, -360, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(4, 0, 0), "head": Vector3(-6, 0, 0),
			"foot_r": Vector3(0.16, 0.0, -0.2), "foot_l": Vector3(0.06, 0.0, 0.2), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(-0.18, -0.15, 0.48), "hand_r": Vector3(0.1, -0.38, 0.24), "wrist_l": PALM, "wrist_r": PALM_DOWN}, &"out"],
	]})
	K.reg(&"wind_blade_air", {"length": 0.62, "events": [[0.46, &"release"], [0.86, &"recover"]], "keys": [
		# Tuck into the flip.
		[0.1, {"hips": Vector3(0, 0.0, 0.0), "spine": Vector3(18, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(10, 0, 0),
			"hand_l": Vector3(0.25, -0.3, 0.45), "hand_r": Vector3(0.25, -0.3, 0.45), "fist_l": 0.3, "fist_r": 0.3,
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.35, 0.3), "foot_r": Vector3(0.02, 0.32, 0.28), "knee_l": Vector3(0.1, 0.5, 1), "knee_r": Vector3(0.1, 0.5, 1)}, &"out"],
		[0.28, {"hips_rot": Vector3(170, 0, 0), "spine": Vector3(26, 0, 0), "chest": Vector3(20, 0, 0), "head": Vector3(20, 0, 0),
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.5, 0.42), "foot_r": Vector3(0.02, 0.48, 0.4)}],
		# Out of the flip the right leg opens high ...
		[0.4, {"hips_rot": Vector3(310, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(-4, 0, 0), "head": Vector3(-14, 0, 0), "feet_hips": 1.0,
			"foot_r": Vector3(0.02, 0.9, 0.62), "knee_r": Vector3(0.0, 1.0, 0.3), "foot_l": Vector3(0.02, 0.2, -0.1),
			"hand_l": Vector3(0.8, 0.2, 0.1), "hand_r": Vector3(0.8, 0.2, 0.1), "fist_l": 0.0, "fist_r": 0.0}],
		# ... and chops down through the front: the blade.
		[0.46, {"hips_rot": Vector3(360, 0, 0), "spine": Vector3(14, 0, 0), "chest": Vector3(8, 0, 0), "head": Vector3(-16, 0, 0), "feet_hips": 1.0,
			"foot_r": Vector3(0.02, 0.3, 0.9), "knee_r": Vector3(0.0, 1.0, 0.1), "foot_rot_r": Vector3(30, 0, 0), "foot_l": Vector3(0.02, 0.12, -0.16),
			"hand_l": Vector3(0.75, -0.25, -0.2), "hand_r": Vector3(0.75, -0.25, -0.2), "wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN}, &"snap"],
		[0.86, {"hips_rot": Vector3(360, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(-2, 0, 0), "head": Vector3(-8, 0, 0), "feet_hips": 0.0,
			"foot_l": Vector3(0.03, 0.22, 0.08), "foot_r": Vector3(0.05, 0.14, -0.08), "hand_l": Vector3(0.62, -0.15, 0.15), "hand_r": Vector3(0.62, -0.15, 0.15)}, &"out"],
	]})


static func _tornado() -> void:
	var keys: Array = [
		# Sink and coil to the right, both palms swept low.
		[0.05, {"hips": Vector3(0, -0.22, 0.0), "hips_rot": Vector3(0, 40, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 20, 0), "head": Vector3(-6, -30, 0),
			"foot_l": Vector3(0.2, 0.0, 0.06), "foot_r": Vector3(0.2, 0.0, -0.06), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(0.55, -0.62, 0.25), "hand_r": Vector3(0.32, -0.66, 0.4), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN, "fist_l": 0.0, "fist_r": 0.0}, &"out"],
		# Two fast spins on the balls of the feet, the arms rising and wide.
		[0.12, {"hips": Vector3(0, -0.04, 0.0), "hips_rot": Vector3(0, -300, 0), "chest": Vector3(-4, -10, 0), "head": Vector3(-12, 0, 0),
			"foot_l": Vector3(0.08, 0.04, 0.02), "foot_r": Vector3(0.08, 0.04, -0.02),
			"hand_l": Vector3(0.85, 0.25, 0.1), "hand_r": Vector3(0.85, 0.25, 0.1), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}],
		# Release: both palms driven forward at the spot the vortex forms.
		[0.2, _m(HORSE, {"hips": Vector3(0, -0.2, 0.06), "hips_rot": Vector3(0, -720, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(2, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_l": Vector3(-0.1, 0.1, 0.95), "hand_r": Vector3(-0.1, 0.06, 0.95), "wrist_l": PALM, "wrist_r": PALM}), &"snap"],
	]
	# Stir the vortex: both palms trace the same circle in front at chest height.
	var t0 := 0.3
	for i in 7:
		var a := float(i) * PI * 0.5
		var c := cos(a) * 0.28
		var s := sin(a) * 0.24
		keys.append([t0 + float(i) * 0.08, _m(HORSE, {"hips": Vector3(sin(a) * 0.02, -0.2, 0.04), "hips_rot": Vector3(0, -720 + sin(a) * 12.0, 0),
			"chest": Vector3(-2, cos(a) * 10.0, 0), "head": Vector3(-14, cos(a) * 6.0, 0),
			"hand_l": Vector3(0.12 - c, 0.12 + s, 0.86), "hand_r": Vector3(0.12 + c, 0.12 + s, 0.86), "wrist_l": PALM, "wrist_r": PALM,
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN})])
	# Release the captured: palms thrown up and out to the sky, chest open.
	keys.append([0.86, _m(HORSE, {"hips": Vector3(0, -0.14, 0.0), "hips_rot": Vector3(0, -720, 0), "spine": Vector3(-6, 0, 0), "chest": Vector3(-14, 0, 0),
		"head": Vector3(-22, 0, 0), "hand_l": Vector3(0.55, 0.85, 0.35), "hand_r": Vector3(0.55, 0.85, 0.35), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
		"wrist_l": PALM, "wrist_r": PALM}), &"snap"])
	keys.append([0.96, {"hips": Vector3(0, -0.1, 0.0), "hips_rot": Vector3(0, -720, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(0, 0, 0), "head": Vector3(-4, 0, 0),
		"foot_l": Vector3(0.12, 0, 0.04), "foot_r": Vector3(0.12, 0, -0.04), "hand_l": Vector3(0.3, -0.55, 0.3), "hand_r": Vector3(0.3, -0.55, 0.3)}, &"out"])
	K.reg(&"air_tornado_cast", {"length": 2.6, "events": [[0.06, &"gather"], [0.2, &"release"], [0.86, &"impact"], [0.93, &"recover"]],
		"plants": [[0.2, "l", 1.0], [0.21, "r", 1.0]], "keys": keys})


static func _slam() -> void:
	K.reg(&"air_dive", {"length": 0.5, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0, 0.0, 0.0), "hips_rot": Vector3(-6, 0, 0), "spine": Vector3(-8, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(14, 0, 0),
			"foot_l": Vector3(0.05, 0.32, 0.16), "foot_r": Vector3(0.05, 0.26, 0.08), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
			"hand_l": Vector3(0.24, 0.92, 0.12), "hand_r": Vector3(0.24, 0.92, 0.12), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN, "fist_l": 0.6, "fist_r": 0.6}],
		[0.5, {"hand_l": Vector3(0.3, 0.88, 0.16), "hand_r": Vector3(0.3, 0.88, 0.16), "foot_l": Vector3(0.05, 0.34, 0.14)}],
	]})
	K.reg(&"air_slam_land", {"length": 0.7, "events": [[0.1, &"impact"], [0.74, &"recover"]],
		"plants": [[0.08, "l", 1.4], [0.09, "r", 1.2]], "keys": [
		# Land on one knee, the right palm driven into the ground, the left arm swept back.
		[0.1, {"hips": Vector3(0, -0.56, 0.04), "spine": Vector3(32, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(-22, 0, 0),
			"foot_l": Vector3(0.12, 0.0, 0.32), "foot_r": Vector3(0.14, 0.0, -0.34), "knee_l": K.KNEE_FWD, "knee_r": Vector3(0.2, -0.4, 1.0),
			"foot_rot_r": Vector3(-30, 10, 0),
			"hand_r": Vector3(0.12, -0.98, 0.42), "hand_l": Vector3(0.72, -0.3, -0.32), "elbow_r": K.ELBOW_OUT, "elbow_l": K.ELBOW_DOWN,
			"wrist_r": PALM_DOWN, "wrist_l": PALM_DOWN, "fist_l": 0.0, "fist_r": 0.0}, &"snap"],
		[0.42, {"hips": Vector3(0, -0.52, 0.04), "spine": Vector3(28, 0, 0), "hand_r": Vector3(0.14, -0.95, 0.44), "head": Vector3(-18, 0, 0)}],
		[0.74, {"hips": Vector3(0, -0.14, 0.0), "spine": Vector3(6, 0, 0), "chest": Vector3(2, 0, 0), "head": Vector3(-4, 0, 0),
			"foot_l": Vector3(0.08, 0.0, 0.1), "foot_r": Vector3(0.1, 0.0, -0.1), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
			"hand_r": Vector3(0.1, -0.4, 0.4), "hand_l": Vector3(-0.15, -0.2, 0.45)}, &"out"],
	]})


static func _ward() -> void:
	# Palms circle around the body in opposite arcs (upper body: the legs keep walking).
	K.reg(&"vortex_ward_hold", {"length": 1.0, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(2, -14, 0), "spine": Vector3(2, -6, 0), "hand_l": Vector3(0.75, -0.1, 0.4), "hand_r": Vector3(0.1, -0.45, 0.6),
			"wrist_l": PALM, "wrist_r": PALM_DOWN, "fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_OUT}],
		[0.25, {"chest": Vector3(2, 0, 0), "spine": Vector3(2, 0, 0), "hand_l": Vector3(0.45, 0.2, 0.6), "hand_r": Vector3(0.45, -0.55, 0.45)}],
		[0.5, {"chest": Vector3(2, 14, 0), "spine": Vector3(2, 6, 0), "hand_r": Vector3(0.75, -0.1, 0.4), "hand_l": Vector3(0.1, -0.45, 0.6),
			"wrist_r": PALM, "wrist_l": PALM_DOWN, "elbow_r": K.ELBOW_DOWN, "elbow_l": K.ELBOW_OUT}],
		[0.75, {"chest": Vector3(2, 0, 0), "spine": Vector3(2, 0, 0), "hand_r": Vector3(0.45, 0.2, 0.6), "hand_l": Vector3(0.45, -0.55, 0.45)}],
	]})
