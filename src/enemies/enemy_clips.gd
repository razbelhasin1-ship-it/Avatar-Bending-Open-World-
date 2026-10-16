class_name EnemyClips
extends RefCounted
## Weapon clips for enemies (AnimLibrary format, docs/modules/characters.md):
## one-handed slash / backslash (club, cutlass), two-handed overhead smash, fast
## knife slash, lunge stab, throw, spear thrust, shield guard + bash, bow shot
## (draw, full-draw hold, release), surrender kneel and a "spotted" call.
##
## Every attack clip has an anticipation key (`windup` in the archetype data):
## EnemyVisual plays the clip up to it and HOLDS it for the telegraph, then the
## strike runs on. Events: &"release" / &"impact" (gameplay), &"recover".

const K = preload("res://src/characters/anim/clips/clip_kit.gd")

static var _done := false


static func ensure() -> void:
	if _done:
		return
	_done = true
	_one_handed()
	_heavy()
	_spear_shield()
	_bow()
	_life()


static func _one_handed() -> void:
	var guard_l := Vector3(-0.08, -0.22, 0.52)
	# Diagonal slash, high right -> low left (club, cutlass).
	K.reg_pair("enemy_slash", {"length": 0.78, "events": [[0.43, &"release"], [0.45, &"impact"], [0.8, &"recover"]], "keys": [
		[0.3, {"hand_r": Vector3(0.34, 0.58, -0.08), "elbow_r": Vector3(1.0, 0.35, -0.4), "wrist_r": Vector3(0, 0, -50), "fist_r": 1.0,
			"chest": Vector3(-6, -30, 0), "spine": Vector3(-2, -8, 0), "hips_rot": Vector3(0, -12, 0), "head": Vector3(2, 26, 0),
			"hand_l": guard_l, "elbow_l": K.ELBOW_DOWN, "fist_l": 0.6}, &"inout"],
		[0.45, {"hand_r": Vector3(-0.24, -0.14, 0.9), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 25, 105),
			"chest": Vector3(8, 28, 0), "spine": Vector3(6, 10, 0), "hips_rot": Vector3(0, 14, 0), "head": Vector3(-4, -22, 0),
			"hand_l": Vector3(0.12, -0.5, 0.05)}, &"snap"],
		[0.62, {"hand_r": Vector3(-0.46, -0.52, 0.5), "chest": Vector3(8, 32, 0), "wrist_r": Vector3(0, 30, 140)}, &"out"],
	]})
	# Return slash, low left -> right (the second hit of a combo).
	K.reg_pair("enemy_backslash", {"length": 0.72, "events": [[0.43, &"release"], [0.45, &"impact"], [0.8, &"recover"]], "keys": [
		[0.26, {"hand_r": Vector3(-0.48, -0.22, 0.45), "elbow_r": Vector3(0.6, -0.6, -0.4), "wrist_r": Vector3(0, 70, 95), "fist_r": 1.0,
			"chest": Vector3(4, 30, 0), "hips_rot": Vector3(0, 12, 0), "head": Vector3(0, -24, 0), "hand_l": guard_l, "fist_l": 0.6}, &"inout"],
		[0.45, {"hand_r": Vector3(0.55, -0.04, 0.72), "elbow_r": Vector3(0.6, -1.0, 0.0), "wrist_r": Vector3(0, 90, 100),
			"chest": Vector3(2, -26, 0), "spine": Vector3(2, -8, 0), "hips_rot": Vector3(0, -12, 0), "head": Vector3(0, 22, 0),
			"hand_l": Vector3(-0.2, -0.3, 0.4)}, &"snap"],
		[0.62, {"hand_r": Vector3(0.72, -0.25, 0.3), "chest": Vector3(2, -30, 0)}, &"out"],
	]})
	# Fast knife slash (skirmishers; mirrored for the left knife).
	K.reg_pair("enemy_knife_slash", {"length": 0.52, "events": [[0.4, &"release"], [0.42, &"impact"], [0.78, &"recover"]], "keys": [
		[0.28, {"hand_r": Vector3(0.36, 0.18, 0.12), "elbow_r": Vector3(1.0, 0.0, -0.5), "wrist_r": Vector3(0, 20, -20), "fist_r": 1.0,
			"chest": Vector3(2, -24, 0), "hips_rot": Vector3(0, -8, 0), "head": Vector3(0, 18, 0), "hips": Vector3(0, -0.06, 0),
			"hand_l": Vector3(-0.1, -0.2, 0.45), "fist_l": 1.0}, &"inout"],
		[0.42, {"hand_r": Vector3(-0.3, -0.1, 0.88), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 40, 100),
			"chest": Vector3(6, 24, 0), "hips_rot": Vector3(0, 10, 0), "head": Vector3(-2, -16, 0), "hips": Vector3(0, -0.08, 0.04)}, &"snap"],
		[0.58, {"hand_r": Vector3(-0.44, -0.32, 0.55), "chest": Vector3(6, 26, 0)}, &"out"],
	]})
	# Lunging stab: low chamber, explosive straight thrust with a long front step.
	K.reg_pair("enemy_stab", {"length": 0.75, "events": [[0.46, &"release"], [0.48, &"impact"], [0.82, &"recover"]],
		"plants": [[0.47, "l", 1.1]], "keys": [
		[0.3, {"hand_r": Vector3(0.12, -0.42, -0.22), "elbow_r": K.ELBOW_BACK, "wrist_r": Vector3(0, 0, 80), "fist_r": 1.0,
			"hips": Vector3(0, -0.14, -0.02), "spine": Vector3(16, -6, 0), "chest": Vector3(6, -18, 0), "head": Vector3(-14, 12, 0),
			"hand_l": Vector3(-0.15, -0.15, 0.55), "fist_l": 0.3, "foot_l": Vector3(0.02, 0.05, 0.1)}, &"inout"],
		[0.48, {"hand_r": Vector3(-0.08, -0.08, 1.0), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 0, 92),
			"hips": Vector3(0, -0.16, 0.14), "spine": Vector3(18, 6, 0), "chest": Vector3(8, 16, 0), "head": Vector3(-16, -10, 0),
			"hand_l": Vector3(0.2, -0.45, -0.1), "foot_l": Vector3(0.0, 0.0, 0.5), "foot_r": Vector3(0.06, 0.0, -0.32), "knee_l": K.KNEE_FWD}, &"snap"],
		[0.66, {"hand_r": Vector3(-0.06, -0.12, 0.92), "hips": Vector3(0, -0.15, 0.12), "foot_l": Vector3(0.0, 0.0, 0.48), "foot_r": Vector3(0.06, 0.0, -0.3)}],
	]})
	# Overhand throw (knives, rocks).
	K.reg_pair("enemy_throw", {"length": 0.68, "events": [[0.46, &"release"], [0.82, &"recover"]], "keys": [
		[0.32, {"hand_r": Vector3(0.28, 0.5, -0.36), "elbow_r": Vector3(1.0, 0.2, -0.5), "wrist_r": Vector3(0, 0, -40), "fist_r": 1.0,
			"chest": Vector3(-6, -32, 0), "hips_rot": Vector3(0, -14, 0), "head": Vector3(0, 30, 0),
			"hand_l": Vector3(-0.05, 0.05, 0.92), "elbow_l": K.ELBOW_DOWN, "fist_l": 0.2}, &"inout"],
		[0.46, {"hand_r": Vector3(-0.12, 0.12, 0.96), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 0, 90), "fist_r": 0.3,
			"chest": Vector3(8, 22, 0), "hips_rot": Vector3(0, 12, 0), "head": Vector3(-4, -16, 0), "hand_l": Vector3(0.2, -0.5, 0.0)}, &"snap"],
		[0.62, {"hand_r": Vector3(-0.3, -0.35, 0.7), "chest": Vector3(10, 26, 0)}, &"out"],
	]})


static func _heavy() -> void:
	# Two-handed overhead smash: big lean back, step, slam into the ground.
	K.reg(&"enemy_overhead", {"length": 1.05, "events": [[0.53, &"release"], [0.55, &"impact"], [0.88, &"recover"]],
		"plants": [[0.5, "l", 1.3]], "keys": [
		[0.36, {"hand_r": Vector3(-0.08, 0.95, -0.12), "hand_l": Vector3(-0.18, 0.92, -0.1), "elbow_r": K.ELBOW_OUT, "elbow_l": K.ELBOW_OUT,
			"wrist_r": Vector3(0, 0, -60), "wrist_l": Vector3(0, 0, -60), "fist_r": 1.0, "fist_l": 1.0,
			"spine": Vector3(-8, 0, 0), "chest": Vector3(-14, -6, 0), "head": Vector3(10, 4, 0), "hips": Vector3(0, 0.02, -0.02)}, &"inout"],
		[0.55, {"hand_r": Vector3(-0.12, -0.55, 0.82), "hand_l": Vector3(-0.22, -0.58, 0.76), "elbow_r": K.ELBOW_DOWN, "elbow_l": K.ELBOW_DOWN,
			"wrist_r": Vector3(0, 0, 75), "wrist_l": Vector3(0, 0, 75),
			"spine": Vector3(30, 0, 0), "chest": Vector3(18, 4, 0), "head": Vector3(-20, 0, 0), "hips": Vector3(0, -0.24, 0.08),
			"foot_l": Vector3(0.04, 0, 0.36), "foot_r": Vector3(0.08, 0, -0.18), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT}, &"in"],
		[0.74, {"hand_r": Vector3(-0.12, -0.6, 0.78), "hand_l": Vector3(-0.22, -0.62, 0.72), "spine": Vector3(26, 0, 0), "hips": Vector3(0, -0.22, 0.06),
			"foot_l": Vector3(0.04, 0, 0.34), "foot_r": Vector3(0.08, 0, -0.16)}],
	]})


static func _spear_shield() -> void:
	# Shield guard (upper body; legs keep walking): forearm across the chest, shield facing forward.
	var guard := {"hand_l": Vector3(-0.42, -0.1, 0.42), "elbow_l": Vector3(1.0, -0.3, 0.2), "wrist_l": Vector3(0, -90, 0), "fist_l": 1.0,
		"chest": Vector3(4, 10, 0), "head": Vector3(-4, -8, 0), "hand_r": Vector3(0.14, -0.5, 0.25), "elbow_r": Vector3(0.3, -1.0, -0.3), "fist_r": 1.0}
	K.reg(&"enemy_shield_guard", {"length": 1.4, "loop": true, "mask": &"upper", "keys": [[0.0, guard], [0.5, {"hand_l": Vector3(-0.42, -0.08, 0.43)}]]})
	# Shield bash: step in, punch the shield forward.
	K.reg(&"enemy_shield_bash", {"length": 0.66, "events": [[0.44, &"release"], [0.46, &"impact"], [0.82, &"recover"]],
		"plants": [[0.45, "l", 1.2]], "keys": [
		[0.3, {"hand_l": Vector3(-0.3, -0.12, 0.18), "elbow_l": Vector3(1.0, -0.2, -0.3), "wrist_l": Vector3(0, -90, 0), "fist_l": 1.0,
			"chest": Vector3(2, -16, 0), "hips_rot": Vector3(0, -8, 0), "head": Vector3(0, 14, 0), "hips": Vector3(0, -0.1, -0.03)}, &"inout"],
		[0.46, {"hand_l": Vector3(-0.38, -0.02, 0.72), "elbow_l": Vector3(1.0, -0.4, 0.3), "chest": Vector3(8, 22, 0), "spine": Vector3(8, 6, 0),
			"hips_rot": Vector3(0, 10, 0), "head": Vector3(-6, -14, 0), "hips": Vector3(0, -0.12, 0.1),
			"foot_l": Vector3(0.02, 0, 0.4), "foot_r": Vector3(0.06, 0, -0.22)}, &"snap"],
		[0.64, {"hand_l": Vector3(-0.38, -0.05, 0.66), "hips": Vector3(0, -0.1, 0.08)}],
	]})
	# Spear thrust: rear hand drives the spear forward from the hip (spear prop held level by the wrist).
	K.reg(&"enemy_thrust", {"length": 0.74, "events": [[0.46, &"release"], [0.48, &"impact"], [0.82, &"recover"]],
		"plants": [[0.47, "l", 1.0]], "keys": [
		[0.32, {"hand_r": Vector3(0.16, -0.42, -0.16), "elbow_r": K.ELBOW_BACK, "wrist_r": Vector3(0, 0, 40), "fist_r": 1.0,
			"hips": Vector3(0, -0.1, -0.03), "spine": Vector3(8, -10, 0), "chest": Vector3(2, -20, 0), "head": Vector3(-6, 16, 0),
			"hand_l": Vector3(-0.42, -0.1, 0.42), "elbow_l": Vector3(1.0, -0.3, 0.2), "wrist_l": Vector3(0, -90, 0)}, &"inout"],
		[0.48, {"hand_r": Vector3(-0.02, -0.18, 0.96), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 0, 92),
			"hips": Vector3(0, -0.12, 0.12), "spine": Vector3(10, 8, 0), "chest": Vector3(4, 18, 0), "head": Vector3(-8, -12, 0),
			"foot_l": Vector3(0.02, 0, 0.42), "foot_r": Vector3(0.06, 0, -0.26), "knee_l": K.KNEE_FWD}, &"snap"],
		[0.66, {"hand_r": Vector3(0.02, -0.25, 0.86), "hips": Vector3(0, -0.11, 0.1), "foot_l": Vector3(0.02, 0, 0.4), "foot_r": Vector3(0.06, 0, -0.24)}],
	]})


static func _bow() -> void:
	# Raise, draw to the cheek (anticipation/hold at 0.55), loose at 0.6, lower.
	var bow_arm := {"hand_l": Vector3(-0.04, 0.06, 0.96), "elbow_l": Vector3(0.6, -1.0, 0.0), "wrist_l": Vector3(0, 0, 0), "fist_l": 1.0}
	var drawn := bow_arm.duplicate()
	drawn.merge({"hand_r": Vector3(-0.22, 0.14, 0.05), "elbow_r": Vector3(1.0, 0.35, -1.0), "wrist_r": Vector3(0, 60, 0), "fist_r": 0.6,
		"chest": Vector3(0, 12, 0), "spine": Vector3(0, 4, 0), "head": Vector3(0, -14, 0)})
	var nocking := bow_arm.duplicate()
	nocking.merge({"hand_r": Vector3(-0.22, 0.04, 0.82), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 80, 0), "fist_r": 0.6,
		"chest": Vector3(0, 8, 0), "head": Vector3(0, -8, 0)})
	K.reg(&"enemy_bow_shot", {"length": 1.25, "events": [[0.3, &"nock"], [0.6, &"release"], [0.86, &"recover"]], "keys": [
		[0.25, nocking, &"inout"],
		[0.55, drawn, &"inout"],
		[0.6, {"hand_r": Vector3(-0.02, 0.18, -0.12), "elbow_r": Vector3(1.0, 0.3, -1.0), "fist_r": 0.0}, &"snap"],
		[0.78, {"hand_r": Vector3(0.05, 0.1, -0.1)}],
	]})


static func _life() -> void:
	# Surrender: drop to the knees, open hands raised, then stay there (looping kneel with a
	# nervous breath) until the enemy leaves.
	var kneel := {"hips": Vector3(0, -0.5, -0.02), "spine": Vector3(10, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(18, 0, 0),
		"foot_l": Vector3(0.04, 0.1, -0.38), "knee_l": Vector3(0.1, -1, 0.3), "foot_rot_l": Vector3(-60, 6, 0), "toe_l": 50.0,
		"foot_r": Vector3(0.04, 0.1, -0.4), "knee_r": Vector3(0.1, -1, 0.3), "foot_rot_r": Vector3(-60, 6, 0), "toe_r": 50.0,
		"hand_l": Vector3(0.32, 0.62, 0.12), "hand_r": Vector3(0.32, 0.62, 0.12), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
		"wrist_l": Vector3(-70, 90, 0), "wrist_r": Vector3(-70, 90, 0), "fist_l": 0.0, "fist_r": 0.0}
	K.reg(&"enemy_surrender", {"length": 1.0, "hold": true, "next": &"enemy_surrender_loop", "events": [[0.55, &"knee_down"]], "keys": [
		[0.55, kneel, &"inout"],
		[1.0, kneel],
	]})
	var kneel_b := kneel.duplicate()
	kneel_b.merge({"hips": Vector3(0, -0.51, -0.03), "chest": Vector3(9, 0, 0), "head": Vector3(24, 6, 0),
		"hand_l": Vector3(0.3, 0.58, 0.14), "hand_r": Vector3(0.33, 0.6, 0.1)}, true)
	K.reg(&"enemy_surrender_loop", {"length": 2.4, "loop": true, "keys": [[0.0, kneel, &"inout"], [0.5, kneel_b, &"inout"]]})
	# Spotted: a sharp point at the intruder + call (upper body).
	K.reg(&"enemy_spotted", {"length": 0.9, "mask": &"upper", "events": [[0.2, &"call"]], "keys": [
		[0.2, {"hand_r": Vector3(-0.02, 0.22, 0.96), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 60, 0), "fist_r": 0.7,
			"chest": Vector3(-4, 14, 0), "head": Vector3(-8, -10, 0), "hand_l": Vector3(0.2, -0.3, 0.3), "fist_l": 1.0}, &"snap"],
		[0.6, {"hand_r": Vector3(0.0, 0.2, 0.94)}],
	]})
	# Captain's war cry (phase change): fists down, chest out.
	K.reg(&"enemy_war_cry", {"length": 1.1, "events": [[0.35, &"burst"]], "keys": [
		[0.2, {"hips": Vector3(0, -0.12, 0), "spine": Vector3(14, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(10, 0, 0),
			"hand_l": Vector3(0.3, -0.6, 0.3), "hand_r": Vector3(0.3, -0.6, 0.3), "fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT}, &"inout"],
		[0.35, {"hips": Vector3(0, -0.16, 0), "spine": Vector3(-10, 0, 0), "chest": Vector3(-16, 0, 0), "head": Vector3(-20, 0, 0),
			"hand_l": Vector3(0.55, -0.45, -0.1), "hand_r": Vector3(0.55, -0.45, -0.1), "mouth": 1.0}, &"snap"],
		[0.8, {"hips": Vector3(0, -0.15, 0), "spine": Vector3(-8, 0, 0), "chest": Vector3(-12, 0, 0), "mouth": 0.6}],
	]})
