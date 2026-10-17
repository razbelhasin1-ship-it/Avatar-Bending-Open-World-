class_name FireClips
extends RefCounted
## Firebending body motion for the Fire techniques (Northern Shaolin: long bow
## stances, snapping fists, high extended kicks, spins, breath driving every
## strike), registered into AnimLibrary (docs/modules/characters.md "Clips"):
##
##   fire_burst_blast    inhale and sink with both fists chambered, stomp into a horse stance
##                       and throw both palms outward: the explosion (&"gather", &"release")
##   fire_ring_kick      coil, spin on the left foot with the right leg sweeping at hip height,
##                       land in a low stance (&"release" when the leg passes the front)
##   jet_step_launch     crouch, palms pushed down, explode upward (&"takeoff")
##   jet_hover           (loop) feet together pointing down, arms out, palms pushing down
##   fire_whip_lash      right hand circles back over the head and lashes down across the body
##                       (&"windup" the fist ignites, &"release" the whip leaves the hand,
##                       &"impact" the crack)
##   inferno_spin        sink + breathe, rise spinning twice with the arms wide (&"spin",
##                       &"pulse" x4), stomp into horse and thrust both palms out (&"release")
##   lightning_charge    (loop) long front stance, both arms tracing slow opposed circles
##   lightning_release   the right arm thrusts forward, two fingers extended (&"release")
##   fire_blaze_hold     (loop, upper) a growing fireball cupped at the right hip, breath pulse
##   fire_blaze_release  step in and drive the fireball out with both palms (&"release")
## FireClips.ensure() is called by the Fire kit (registry load) and by every Fire
## ability, so rig-less casters get the clip events too.

const K = preload("res://src/characters/anim/clips/clip_kit.gd")

## Wide horse stance (feet out, toes out, knees out).
const HORSE := {"foot_l": Vector3(0.28, 0, 0.02), "foot_r": Vector3(0.28, 0, -0.02), "foot_rot_l": Vector3(0, 22, 0), "foot_rot_r": Vector3(0, 22, 0),
	"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}
## Long front (bow) stance: left foot forward, right foot back and turned out.
const BOW := {"foot_l": Vector3(0.06, 0, 0.42), "foot_r": Vector3(0.14, 0, -0.38), "foot_rot_l": Vector3(0, 6, 0), "foot_rot_r": Vector3(0, 42, 0),
	"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT}
## Palm forward, fingers up.
const PALM := Vector3(-80, 90, 0)
## Palm down, fingers forward (arms low).
const PALM_DOWN := Vector3(-75, 90, 0)

static var _done := false


static func ensure() -> void:
	if _done:
		return
	_done = true
	_burst()
	_ring()
	_jet()
	_whip()
	_inferno()
	_lightning()
	_blaze()


static func _m(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k: String in b:
		out[k] = b[k]
	return out


static func _burst() -> void:
	K.reg(&"fire_burst_blast", {"length": 0.72, "events": [[0.12, &"gather"], [0.36, &"release"], [0.74, &"recover"]],
		"plants": [[0.34, "l", 1.2], [0.35, "r", 1.2]], "keys": [
		# Inhale: sink, fists chambered at the ribs, chest folds over them, chin down.
		[0.2, {"hips": Vector3(0, -0.14, -0.02), "spine": Vector3(14, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(6, 0, 0),
			"foot_l": Vector3(0.12, 0.0, 0.04), "foot_r": Vector3(0.12, 0.0, -0.04), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(0.04, -0.5, -0.06), "hand_r": Vector3(0.04, -0.5, -0.06), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, -80, 0), "wrist_r": Vector3(0, -80, 0),
			"clav_l": Vector3(-6, -8, 0), "clav_r": Vector3(-6, -8, 0)}, &"inout"],
		# Release: stomp into a wide horse stance, chest opens, both palms thrown out and down.
		[0.36, _m(HORSE, {"hips": Vector3(0, -0.24, 0.0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_l": Vector3(0.82, -0.32, 0.4), "hand_r": Vector3(0.82, -0.32, 0.4), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"fist_l": 0.0, "fist_r": 0.0, "wrist_l": PALM, "wrist_r": PALM, "clav_l": Vector3(8, 10, 0), "clav_r": Vector3(8, 10, 0)}), &"snap"],
		[0.6, _m(HORSE, {"hips": Vector3(0, -0.22, 0.0), "chest": Vector3(-6, 0, 0), "hand_l": Vector3(0.78, -0.36, 0.38), "hand_r": Vector3(0.78, -0.36, 0.38)})],
	]})


static func _ring() -> void:
	K.reg(&"fire_ring_kick", {"length": 0.92, "events": [[0.46, &"release"], [0.86, &"recover"]],
		"plants": [[0.84, "r", 1.3]], "keys": [
		# Coil: twist left on bent knees, arms wound to the left.
		[0.16, {"hips": Vector3(0, -0.16, 0.0), "hips_rot": Vector3(4, 48, 0), "spine": Vector3(8, 10, 0), "chest": Vector3(6, 26, 0), "head": Vector3(-8, -50, 0),
			"foot_l": Vector3(0.06, 0.0, 0.08), "foot_r": Vector3(0.2, 0.0, -0.12), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT, "foot_rot_r": Vector3(0, 30, 0),
			"hand_l": Vector3(0.62, -0.3, -0.25), "hand_r": Vector3(-0.1, -0.35, 0.5), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_DOWN,
			"fist_l": 1.0, "fist_r": 1.0}, &"out"],
		# Spin: pivot on the left foot, the right leg chambers and rises.
		[0.32, {"hips": Vector3(0, -0.08, 0.0), "hips_rot": Vector3(-6, -100, 0), "chest": Vector3(-4, 10, 0), "head": Vector3(-6, -20, 0),
			"foot_r": Vector3(0.45, 0.42, 0.1), "knee_r": Vector3(0.6, 0.6, 0.4), "foot_l": Vector3(0.04, 0.0, 0.0), "knee_l": K.KNEE_FWD,
			"hand_l": Vector3(0.85, -0.05, 0.1), "hand_r": Vector3(0.8, -0.05, 0.1), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}],
		# Release: the leg extended at hip height whips through the front, arms flung wide.
		[0.46, {"hips": Vector3(0, -0.06, 0.0), "hips_rot": Vector3(-14, -200, 0), "spine": Vector3(-8, 0, 0), "chest": Vector3(-6, 18, 0), "head": Vector3(0, -18, 0),
			"foot_r": Vector3(0.95, 0.62, -0.05), "knee_r": Vector3(0.2, 1.0, 0.0), "foot_rot_r": Vector3(-10, -40, 60),
			"hand_l": Vector3(0.95, 0.05, 0.05), "hand_r": Vector3(0.9, 0.0, 0.05), "wrist_l": PALM, "wrist_r": PALM, "fist_l": 0.0, "fist_r": 0.0}, &"snap"],
		[0.64, {"hips": Vector3(0, -0.12, 0.0), "hips_rot": Vector3(-4, -300, 0), "foot_r": Vector3(0.5, 0.3, -0.2), "chest": Vector3(0, 10, 0), "head": Vector3(-4, 0, 0)}],
		# Land low, fists back on guard, facing the front again.
		[0.84, {"hips": Vector3(0, -0.2, 0.0), "hips_rot": Vector3(2, -360, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(4, 0, 0), "head": Vector3(-6, 0, 0),
			"foot_r": Vector3(0.18, 0.0, -0.22), "foot_l": Vector3(0.06, 0.0, 0.2), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(-0.2, -0.15, 0.45), "hand_r": Vector3(0.02, -0.46, -0.1), "elbow_r": K.ELBOW_BACK, "fist_l": 1.0, "fist_r": 1.0}, &"out"],
	]})


static func _jet() -> void:
	K.reg(&"jet_step_launch", {"length": 0.5, "events": [[0.34, &"takeoff"], [0.9, &"recover"]], "plants": [[0.3, "l", 1.1], [0.3, "r", 1.1]], "keys": [
		# Crouch: palms pushed down by the hips, head up to the destination.
		[0.26, {"hips": Vector3(0, -0.32, 0.02), "spine": Vector3(22, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(-26, 0, 0),
			"foot_l": Vector3(0.1, 0.0, 0.06), "foot_r": Vector3(0.1, 0.0, -0.06), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
			"hand_l": Vector3(0.32, -0.88, 0.08), "hand_r": Vector3(0.32, -0.88, 0.08), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN, "fist_l": 0.0, "fist_r": 0.0}, &"inout"],
		# Takeoff: the body extends, legs together pointing down, palms drive the flame down.
		[0.4, {"hips": Vector3(0, 0.0, 0.0), "spine": Vector3(-6, 0, 0), "chest": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0),
			"foot_l": Vector3(0.02, 0.06, -0.04), "foot_r": Vector3(0.02, 0.04, -0.02), "foot_rot_l": Vector3(-45, 0, 0), "foot_rot_r": Vector3(-45, 0, 0),
			"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
			"hand_l": Vector3(0.42, -0.9, -0.12), "hand_r": Vector3(0.42, -0.9, -0.12), "wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN}, &"snap"],
		[0.8, {"hips": Vector3(0, 0.02, 0.0), "foot_l": Vector3(0.04, 0.16, 0.06), "foot_r": Vector3(0.04, 0.1, -0.04),
			"hand_l": Vector3(0.55, -0.7, -0.05), "hand_r": Vector3(0.55, -0.7, -0.05)}],
	]})
	# Hovering on two jets: feet together pointing down, arms out and low, palms pushing down.
	K.reg(&"jet_hover", {"length": 0.8, "loop": true, "keys": [
		[0.0, {"hips": Vector3(0, 0.0, 0.0), "hips_rot": Vector3(4, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(-2, 0, 0), "head": Vector3(-10, 0, 0),
			"foot_l": Vector3(0.03, 0.14, 0.02), "foot_r": Vector3(0.03, 0.08, -0.06), "foot_rot_l": Vector3(-50, 0, 0), "foot_rot_r": Vector3(-50, 0, 0),
			"knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD, "feet_hips": 0.0,
			"hand_l": Vector3(0.62, -0.68, 0.0), "hand_r": Vector3(0.62, -0.68, 0.0), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": PALM_DOWN, "wrist_r": PALM_DOWN, "fist_l": 0.0, "fist_r": 0.0}],
		[0.5, {"hips_rot": Vector3(6, 0, 0), "foot_l": Vector3(0.03, 0.1, -0.02), "foot_r": Vector3(0.03, 0.12, -0.02),
			"hand_l": Vector3(0.64, -0.64, 0.04), "hand_r": Vector3(0.6, -0.7, -0.02)}],
	]})


static func _whip() -> void:
	K.reg(&"fire_whip_lash", {"length": 0.95, "events": [[0.08, &"windup"], [0.34, &"release"], [0.5, &"impact"], [0.84, &"recover"]],
		"plants": [[0.44, "l", 1.2]], "keys": [
		# Wind-up: weight back on the right leg, the right hand circles back above the head.
		[0.2, {"hips": Vector3(0, -0.08, -0.08), "hips_rot": Vector3(0, -24, 0), "spine": Vector3(-6, -6, 0), "chest": Vector3(-12, -28, 0), "head": Vector3(-4, 26, 0),
			"foot_l": Vector3(0.06, 0.0, 0.26), "foot_r": Vector3(0.12, 0.0, -0.3), "foot_rot_r": Vector3(0, 40, 0), "knee_r": K.KNEE_OUT,
			"hand_r": Vector3(0.38, 0.62, -0.36), "elbow_r": K.ELBOW_OUT, "wrist_r": Vector3(-20, 0, 0), "fist_r": 0.6,
			"hand_l": Vector3(-0.2, -0.12, 0.55), "elbow_l": K.ELBOW_DOWN, "fist_l": 0.0, "wrist_l": PALM}, &"inout"],
		# The hand passes over the head: the whip uncoils.
		[0.34, {"hips_rot": Vector3(0, -6, 0), "chest": Vector3(-14, -6, 0), "hand_r": Vector3(0.14, 0.82, 0.22), "wrist_r": Vector3(-30, 0, 0)}],
		# Crack: step into the bow stance, the arm cuts down across the body.
		[0.5, _m(BOW, {"hips": Vector3(0, -0.2, 0.12), "hips_rot": Vector3(4, 26, 0), "spine": Vector3(14, 10, 0), "chest": Vector3(12, 34, 0), "head": Vector3(-14, -30, 0),
			"hand_r": Vector3(-0.42, -0.42, 0.82), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(20, 0, 0), "fist_r": 1.0,
			"hand_l": Vector3(0.04, -0.46, -0.1), "elbow_l": K.ELBOW_BACK, "fist_l": 1.0}), &"snap"],
		[0.72, _m(BOW, {"hips": Vector3(0, -0.18, 0.1), "chest": Vector3(10, 30, 0), "hand_r": Vector3(-0.46, -0.5, 0.74)})],
	]})


static func _inferno() -> void:
	var wide := {"hand_l": Vector3(1.0, 0.08, 0.0), "hand_r": Vector3(1.0, 0.08, 0.0), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
		"wrist_l": PALM, "wrist_r": PALM, "fist_l": 0.0, "fist_r": 0.0}
	K.reg(&"inferno_spin", {"length": 1.9, "events": [[0.1, &"gather"], [0.2, &"spin"], [0.32, &"pulse"], [0.44, &"pulse"], [0.56, &"pulse"], [0.66, &"pulse"],
		[0.76, &"release"], [0.94, &"recover"]],
		"plants": [[0.72, "l", 1.4], [0.73, "r", 1.4]], "keys": [
		# Sink and breathe in: fists chambered, head bowed.
		[0.1, {"hips": Vector3(0, -0.28, -0.02), "spine": Vector3(18, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(14, 0, 0),
			"foot_l": Vector3(0.16, 0.0, 0.04), "foot_r": Vector3(0.16, 0.0, -0.04), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT,
			"hand_l": Vector3(0.04, -0.5, -0.08), "hand_r": Vector3(0.04, -0.5, -0.08), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK,
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, -80, 0), "wrist_r": Vector3(0, -80, 0)}, &"inout"],
		# Rise into the spin, arms flung wide.
		[0.22, _m(wide, {"hips": Vector3(0, -0.04, 0.0), "hips_rot": Vector3(0, -120, 0), "spine": Vector3(-6, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-14, 0, 0),
			"foot_l": Vector3(0.04, 0.0, 0.0), "foot_r": Vector3(0.1, 0.06, -0.04), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD})],
		[0.38, _m(wide, {"hips": Vector3(0, -0.02, 0.0), "hips_rot": Vector3(0, -330, 0), "chest": Vector3(-12, 0, 0), "hand_l": Vector3(1.0, 0.18, -0.05), "hand_r": Vector3(1.0, -0.02, 0.05)})],
		[0.54, _m(wide, {"hips": Vector3(0, -0.04, 0.0), "hips_rot": Vector3(0, -540, 0), "chest": Vector3(-10, 0, 0), "hand_l": Vector3(1.0, -0.02, 0.05), "hand_r": Vector3(1.0, 0.18, -0.05)})],
		# Pull it in: the spin ends low, fists drawn back to the ribs.
		[0.66, {"hips": Vector3(0, -0.2, 0.0), "hips_rot": Vector3(0, -700, 0), "spine": Vector3(12, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(4, 0, 0),
			"hand_l": Vector3(0.04, -0.5, -0.08), "hand_r": Vector3(0.04, -0.5, -0.08), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "fist_l": 1.0, "fist_r": 1.0,
			"wrist_l": Vector3(0, -80, 0), "wrist_r": Vector3(0, -80, 0)}, &"in"],
		# Release: stomp into a deep horse stance and drive both palms out.
		[0.76, _m(HORSE, {"hips": Vector3(0, -0.32, 0.0), "hips_rot": Vector3(0, -720, 0), "spine": Vector3(-6, 0, 0), "chest": Vector3(-14, 0, 0), "head": Vector3(-16, 0, 0),
			"hand_l": Vector3(0.9, -0.12, 0.3), "hand_r": Vector3(0.9, -0.12, 0.3), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": PALM, "wrist_r": PALM, "fist_l": 0.0, "fist_r": 0.0, "clav_l": Vector3(10, 8, 0), "clav_r": Vector3(10, 8, 0)}), &"snap"],
		[0.9, _m(HORSE, {"hips": Vector3(0, -0.3, 0.0), "hips_rot": Vector3(0, -720, 0), "chest": Vector3(-10, 0, 0),
			"hand_l": Vector3(0.86, -0.18, 0.28), "hand_r": Vector3(0.86, -0.18, 0.28)})],
	]})


static func _lightning() -> void:
	# The lightning kata: rooted in a long stance, the arms trace slow opposed circles
	# (separating the energies); fingers extended, wrists soft.
	var stance := _m(BOW, {"hips": Vector3(0, -0.16, 0.02), "hips_rot": Vector3(0, -16, 0), "spine": Vector3(4, 0, 0), "head": Vector3(-6, 14, 0),
		"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0})
	K.reg(&"lightning_charge", {"length": 1.6, "loop": true, "keys": [
		[0.0, _m(stance, {"chest": Vector3(2, -10, 0), "hand_r": Vector3(0.12, 0.34, 0.62), "hand_l": Vector3(0.3, -0.62, -0.12),
			"wrist_r": Vector3(-60, 90, 0), "wrist_l": Vector3(-30, 60, 0)})],
		[0.25, _m(stance, {"chest": Vector3(4, -18, 0), "hand_r": Vector3(0.72, 0.36, 0.12), "hand_l": Vector3(0.14, -0.6, 0.48),
			"wrist_r": Vector3(-40, 60, 0), "wrist_l": Vector3(-50, 90, 0)})],
		[0.5, _m(stance, {"chest": Vector3(2, -10, 0), "hand_l": Vector3(0.12, 0.34, 0.62), "hand_r": Vector3(0.3, -0.62, -0.12),
			"wrist_l": Vector3(-60, 90, 0), "wrist_r": Vector3(-30, 60, 0)})],
		[0.75, _m(stance, {"chest": Vector3(0, -2, 0), "hand_l": Vector3(0.72, 0.36, 0.12), "hand_r": Vector3(0.14, -0.6, 0.48),
			"wrist_l": Vector3(-40, 60, 0), "wrist_r": Vector3(-50, 90, 0)})],
	]})
	K.reg(&"lightning_release", {"length": 0.75, "events": [[0.22, &"release"], [0.74, &"recover"]], "plants": [[0.2, "l", 1.1]], "keys": [
		# Gather both hands at the chest for an instant.
		[0.1, _m(stance, {"chest": Vector3(4, -20, 0), "hand_r": Vector3(-0.1, -0.2, 0.3), "hand_l": Vector3(-0.08, -0.16, 0.32),
			"wrist_r": Vector3(-20, 0, 0), "wrist_l": Vector3(-20, 0, 0)}), &"inout"],
		# Release: the right arm shoots forward, fingers pointing; the left fist pulls to the hip.
		[0.22, _m(BOW, {"hips": Vector3(0, -0.2, 0.12), "hips_rot": Vector3(2, 18, 0), "spine": Vector3(8, 6, 0), "chest": Vector3(6, 30, 0), "head": Vector3(-10, -26, 0),
			"foot_l": Vector3(0.06, 0, 0.5), "hand_r": Vector3(-0.1, 0.06, 1.02), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(-8, 90, 0), "fist_r": 0.15,
			"clav_r": Vector3(0, 20, 0), "hand_l": Vector3(0.04, -0.48, -0.12), "elbow_l": K.ELBOW_BACK, "fist_l": 1.0}), &"snap"],
		[0.5, _m(BOW, {"hips": Vector3(0, -0.19, 0.1), "foot_l": Vector3(0.06, 0, 0.48), "chest": Vector3(6, 28, 0), "hand_r": Vector3(-0.1, 0.04, 0.98)})],
	]})


static func _blaze() -> void:
	# Blaze Charge: the fireball is cupped between both hands at the right hip and
	# grows with every breath (chest rises and sinks), the left foot forward.
	K.reg(&"fire_blaze_hold", {"length": 0.9, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(6, -30, 0), "spine": Vector3(4, -10, 0), "head": Vector3(-6, 26, 0),
			"hand_r": Vector3(0.16, -0.5, 0.06), "hand_l": Vector3(-0.12, -0.36, 0.3), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_BACK,
			"wrist_r": Vector3(-30, 180, 0), "wrist_l": Vector3(-20, 0, 0), "fist_l": 0.15, "fist_r": 0.15}],
		[0.5, {"chest": Vector3(2, -32, 0), "spine": Vector3(2, -11, 0), "hand_r": Vector3(0.17, -0.48, 0.07), "hand_l": Vector3(-0.11, -0.33, 0.31)}],
	]})
	K.reg(&"fire_blaze_release", {"length": 0.62, "events": [[0.34, &"release"], [0.8, &"recover"]], "plants": [[0.3, "l", 1.3]], "keys": [
		[0.0, {"chest": Vector3(6, -30, 0), "spine": Vector3(4, -10, 0), "hand_r": Vector3(0.16, -0.5, 0.06), "hand_l": Vector3(-0.12, -0.36, 0.3),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_BACK, "fist_l": 0.15, "fist_r": 0.15}],
		# Drive: step into a long bow stance, hips and shoulders snap square, both palms out.
		[0.34, _m(BOW, {"hips": Vector3(0, -0.2, 0.16), "hips_rot": Vector3(4, 10, 0), "spine": Vector3(10, 4, 0), "chest": Vector3(10, 14, 0), "head": Vector3(-14, -8, 0),
			"foot_l": Vector3(0.06, 0, 0.5), "hand_l": Vector3(-0.16, 0.02, 1.0), "hand_r": Vector3(-0.22, -0.06, 0.98), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": PALM, "wrist_r": PALM, "fist_l": 0.0, "fist_r": 0.0}), &"snap"],
		[0.62, _m(BOW, {"hips": Vector3(0, -0.18, 0.13), "foot_l": Vector3(0.06, 0, 0.48), "hand_l": Vector3(-0.14, 0.0, 0.92), "hand_r": Vector3(-0.2, -0.08, 0.9)})],
	]})
