class_name ClipsReactions
extends RefCounted
## Built-in dodges, defense (block / parry) and hit reactions (flinch,
## stagger, knockback, knockdown -> down loop -> getup, launch -> tumble, death).
## Root tracks give the travel a controller should apply (root_motion option).

const K = preload("res://src/characters/anim/clips/clip_kit.gd")


static func register_all() -> void:
	_dodges()
	_defense()
	_hits()
	_down()


static func _dodges() -> void:
	K.reg(&"dodge_roll", {"length": 0.74, "events": [[0.06, &"dodge"], [0.82, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.15, Vector3(0, 0, 0.35)], [0.78, Vector3(0, 0, 2.5)], [1.0, Vector3(0, 0, 2.75)]],
		"plants": [[0.8, "l", 0.8], [0.86, "r", 0.7]], "meta": {"travel": 2.75}, "keys": [
		[0.14, {"hips": Vector3(0, -0.34, 0.12), "spine": Vector3(26, 0, 0), "chest": Vector3(20, 0, 0), "head": Vector3(22, 0, 0),
			"hand_l": Vector3(0.12, -0.55, 0.6), "hand_r": Vector3(0.12, -0.55, 0.6), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"foot_l": Vector3(0, 0, 0.18), "foot_r": Vector3(0.04, 0, -0.22), "fist_l": 0.3, "fist_r": 0.3}, &"out"],
		[0.32, {"hips": Vector3(0, -0.64, 0.25), "hips_rot": Vector3(125, 0, 0), "spine": Vector3(38, 0, 0), "chest": Vector3(32, 0, 0), "head": Vector3(34, 0, 0),
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.5, 0.42), "foot_r": Vector3(0.02, 0.46, 0.4), "knee_l": Vector3(0.1, 0.4, 1), "knee_r": Vector3(0.1, 0.4, 1),
			"hand_l": Vector3(0.1, -0.35, 0.42), "hand_r": Vector3(0.1, -0.35, 0.42)}],
		[0.56, {"hips": Vector3(0, -0.6, 0.2), "hips_rot": Vector3(250, 0, 0), "feet_hips": 1.0, "foot_l": Vector3(0.0, 0.52, 0.45), "foot_r": Vector3(0.02, 0.48, 0.42)}],
		[0.8, {"hips": Vector3(0, -0.3, 0.06), "hips_rot": Vector3(360, 0, 0), "spine": Vector3(22, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(-6, 0, 0),
			"feet_hips": 0.0, "foot_l": Vector3(0, 0, 0.12), "foot_r": Vector3(0.05, 0, -0.18), "hand_l": Vector3(0.3, -0.6, 0.3), "hand_r": Vector3(0.3, -0.6, 0.3)}, &"out"],
	]})
	K.reg_pair("dodge_side", {"length": 0.46, "events": [[0.05, &"dodge"], [0.8, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.6, Vector3(1.6, 0, 0)], [1.0, Vector3(1.8, 0, 0)]], "plants": [[0.55, "r", 0.9], [0.7, "l", 0.7]], "meta": {"travel": 1.8}, "keys": [
		[0.12, {"hips": Vector3(-0.04, -0.16, 0), "hips_rot": Vector3(0, 0, 8), "chest": Vector3(0, 0, 10), "foot_r": Vector3(0.12, 0, 0), "foot_l": Vector3(-0.02, 0.0, 0.0)}, &"out"],
		[0.4, {"hips": Vector3(0.06, -0.1, 0), "hips_rot": Vector3(0, 0, -12), "spine": Vector3(0, 0, -8), "chest": Vector3(4, 0, -12), "head": Vector3(0, 0, 10),
			"foot_r": Vector3(0.18, 0.22, 0.0), "foot_l": Vector3(0.04, 0.3, 0.0), "foot_rot_r": Vector3(-20, 0, 10), "foot_rot_l": Vector3(-25, 0, -10),
			"hand_l": Vector3(0.5, -0.4, 0.2), "hand_r": Vector3(0.6, -0.25, 0.1), "elbow_l": Vector3(1, -0.5, -0.2), "elbow_r": Vector3(1, -0.5, -0.2)}],
		[0.62, {"hips": Vector3(0.02, -0.2, 0), "hips_rot": Vector3(0, 0, -4), "chest": Vector3(8, 0, -4), "foot_r": Vector3(0.16, 0, 0.0), "foot_l": Vector3(0.0, 0.0, 0.0),
			"hand_l": Vector3(0.3, -0.6, 0.3), "hand_r": Vector3(0.45, -0.55, 0.2)}, &"out"],
	]})
	K.reg(&"dodge_back", {"length": 0.5, "events": [[0.05, &"dodge"], [0.8, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.6, Vector3(0, 0.0, -1.5)], [1.0, Vector3(0, 0, -1.7)]], "plants": [[0.62, "l", 0.8], [0.7, "r", 0.8]], "meta": {"travel": 1.7}, "keys": [
		[0.15, {"hips": Vector3(0, -0.18, 0.04), "spine": Vector3(12, 0, 0), "chest": Vector3(10, 0, 0), "hand_l": Vector3(0.2, -0.5, 0.5), "hand_r": Vector3(0.2, -0.5, 0.5)}, &"out"],
		[0.42, {"hips": Vector3(0, -0.04, -0.06), "spine": Vector3(-8, 0, 0), "chest": Vector3(-12, 0, 0), "head": Vector3(10, 0, 0),
			"foot_l": Vector3(0, 0.22, 0.12), "foot_r": Vector3(0.02, 0.28, 0.05), "foot_rot_l": Vector3(-25, 0, 0), "foot_rot_r": Vector3(-30, 0, 0),
			"hand_l": Vector3(0.45, -0.2, 0.45), "hand_r": Vector3(0.45, -0.2, 0.45), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0}],
		[0.66, {"hips": Vector3(0, -0.22, -0.02), "spine": Vector3(14, 0, 0), "foot_l": Vector3(0.0, 0, 0.1), "foot_r": Vector3(0.04, 0, -0.14)}, &"out"],
	]})
	# Air flip: tucked back flip (Ba Gua evasive, lands on the balls of the feet).
	K.reg(&"dodge_flip", {"length": 0.78, "events": [[0.06, &"dodge"], [0.85, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.45, Vector3(0, 1.1, -1.0)], [0.8, Vector3(0, 0.0, -2.1)], [1.0, Vector3(0, 0, -2.2)]], "plants": [[0.82, "l", 0.6], [0.84, "r", 0.6]], "keys": [
		[0.12, {"hips": Vector3(0, -0.2, 0.02), "spine": Vector3(10, 0, 0), "hand_l": Vector3(0.25, -0.4, -0.3), "hand_r": Vector3(0.25, -0.4, -0.3), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK}, &"out"],
		[0.3, {"hips": Vector3(0, 0.05, 0), "hips_rot": Vector3(-120, 0, 0), "spine": Vector3(-10, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(10, 0, 0),
			"feet_hips": 1.0, "foot_l": Vector3(0.0, 0.55, 0.4), "foot_r": Vector3(0.02, 0.52, 0.42), "knee_l": Vector3(0.1, 0.5, 1), "knee_r": Vector3(0.1, 0.5, 1),
			"hand_l": Vector3(0.1, -0.5, 0.45), "hand_r": Vector3(0.1, -0.5, 0.45), "fist_l": 0.6, "fist_r": 0.6}],
		[0.55, {"hips_rot": Vector3(-250, 0, 0), "feet_hips": 1.0, "foot_l": Vector3(0.0, 0.5, 0.35), "foot_r": Vector3(0.02, 0.5, 0.36)}],
		[0.8, {"hips": Vector3(0, -0.2, 0.0), "hips_rot": Vector3(-360, 0, 0), "spine": Vector3(16, 0, 0), "chest": Vector3(0, 0, 0), "head": Vector3(-6, 0, 0), "feet_hips": 0.0,
			"foot_l": Vector3(0.02, 0.0, 0.08), "foot_r": Vector3(0.04, 0.0, -0.1), "hand_l": Vector3(0.6, -0.1, 0.2), "hand_r": Vector3(0.6, -0.1, 0.2), "fist_l": 0.0, "fist_r": 0.0}, &"out"],
	]})
	# Earth: low sidestep slide, feet stay on the ground, arms guard the body.
	K.reg_pair("dodge_earth_slide", {"length": 0.55, "events": [[0.05, &"dodge"], [0.85, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.7, Vector3(1.5, 0, 0)], [1.0, Vector3(1.6, 0, 0)]], "plants": [[0.15, "r", 1.3], [0.7, "l", 1.1]], "keys": [
		[0.15, {"hips": Vector3(0.04, -0.2, 0), "hips_rot": Vector3(0, 0, -6), "chest": Vector3(-4, -8, -4), "foot_r": Vector3(0.36, 0, 0.0), "foot_l": Vector3(0.1, 0, 0),
			"foot_rot_r": Vector3(0, 30, 0), "knee_r": K.KNEE_OUT, "knee_l": K.KNEE_OUT,
			"hand_l": Vector3(-0.1, -0.25, 0.5), "hand_r": Vector3(0.1, -0.35, 0.45), "fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"snap"],
		[0.7, {"hips": Vector3(0.0, -0.2, 0), "foot_r": Vector3(0.3, 0, 0), "foot_l": Vector3(0.3, 0, 0), "chest": Vector3(-5, 0, 0)}],
	]})
	# Water: smooth low slide (as if gliding on a thin water sheet).
	K.reg_pair("dodge_water_slide", {"length": 0.62, "events": [[0.05, &"dodge"], [0.85, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.75, Vector3(2.0, 0, 0.3)], [1.0, Vector3(2.2, 0, 0.3)]], "keys": [
		[0.2, {"hips": Vector3(0.0, -0.3, 0), "hips_rot": Vector3(0, 20, -10), "spine": Vector3(10, 0, -6), "chest": Vector3(6, 10, -10),
			"foot_r": Vector3(0.3, 0, 0.2), "foot_l": Vector3(0.1, 0, -0.2), "foot_rot_r": Vector3(10, 40, 0), "foot_rot_l": Vector3(0, 30, 0),
			"hand_r": Vector3(0.7, -0.35, 0.3), "hand_l": Vector3(0.1, -0.2, 0.6), "wrist_r": Vector3(-30, 80, 0), "wrist_l": Vector3(-30, 80, 0), "fist_l": 0.0, "fist_r": 0.0}, &"inout"],
		[0.6, {"hips": Vector3(0.0, -0.26, 0), "hand_r": Vector3(0.75, -0.2, 0.1), "hand_l": Vector3(0.3, -0.3, 0.5)}],
	]})
	# Fire: explosive burst step (short, sharp, forward-weighted).
	K.reg(&"dodge_fire_burst", {"length": 0.36, "events": [[0.05, &"dodge"], [0.3, &"burst"], [0.85, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.5, Vector3(0, 0, 2.2)], [1.0, Vector3(0, 0, 2.4)]], "plants": [[0.55, "l", 1.0]], "keys": [
		[0.2, {"hips": Vector3(0, -0.14, 0.1), "hips_rot": Vector3(12, 0, 0), "spine": Vector3(14, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_l": Vector3(0.3, -0.65, -0.45), "hand_r": Vector3(0.3, -0.65, -0.45), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "fist_l": 1.0, "fist_r": 1.0,
			"foot_l": Vector3(0, 0.12, 0.3), "foot_r": Vector3(0.04, 0.2, -0.45), "foot_rot_r": Vector3(-50, 10, 0)}, &"snap"],
		[0.6, {"hips": Vector3(0, -0.12, 0.06), "spine": Vector3(10, 0, 0), "foot_l": Vector3(0, 0, 0.32), "foot_r": Vector3(0.06, 0, -0.25)}, &"out"],
	]})


static func _defense() -> void:
	K.reg(&"block_hold", {"length": 1.6, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"spine": Vector3(6, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(6, 0, 0),
			"hand_l": Vector3(-0.3, 0.06, 0.38), "hand_r": Vector3(-0.32, 0.0, 0.4), "elbow_l": Vector3(0.4, -1, 0), "elbow_r": Vector3(0.4, -1, 0),
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 30, 0), "wrist_r": Vector3(0, 30, 0)}],
		[0.5, {"chest": Vector3(7, 0, 0), "hand_l": Vector3(-0.3, 0.07, 0.39)}],
	]})
	K.reg(&"block_hold_air", {"length": 2.0, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(0, 0, 0), "hand_l": Vector3(-0.1, 0.0, 0.62), "hand_r": Vector3(-0.35, -0.25, 0.5), "wrist_l": Vector3(-60, 20, 0), "wrist_r": Vector3(-60, 20, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0}],
		[0.5, {"hand_l": Vector3(-0.2, 0.1, 0.6), "hand_r": Vector3(-0.2, -0.35, 0.52)}],
	]})
	K.reg(&"block_hold_earth", {"length": 1.6, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"spine": Vector3(8, 0, 0), "chest": Vector3(4, 0, 0), "head": Vector3(10, 0, 0),
			"hand_l": Vector3(-0.25, 0.15, 0.28), "hand_r": Vector3(-0.25, 0.1, 0.3), "elbow_l": Vector3(0.6, -1, 0.3), "elbow_r": Vector3(0.6, -1, 0.3),
			"fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 60, 0), "wrist_r": Vector3(0, 60, 0)}],
	]})
	K.reg(&"block_hold_water", {"length": 2.4, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(2, 0, 0), "hand_l": Vector3(-0.05, -0.1, 0.62), "hand_r": Vector3(-0.15, -0.3, 0.55), "wrist_l": Vector3(-40, 70, 0), "wrist_r": Vector3(-40, 70, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0}],
		[0.5, {"hand_l": Vector3(-0.15, -0.3, 0.56), "hand_r": Vector3(-0.05, -0.12, 0.62)}],
	]})
	K.reg(&"block_impact", {"length": 0.32, "mask": &"upper", "events": [[0.05, &"impact"]], "keys": [
		[0.15, {"spine": Vector3(-4, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(-8, 0, 0), "hips": Vector3(0, -0.03, -0.04),
			"hand_l": Vector3(-0.3, 0.1, 0.3), "hand_r": Vector3(-0.32, 0.04, 0.32), "elbow_l": Vector3(0.4, -1, 0), "elbow_r": Vector3(0.4, -1, 0), "fist_l": 1.0, "fist_r": 1.0}, &"snap"],
		[0.6, {"spine": Vector3(6, 0, 0), "chest": Vector3(6, 0, 0), "hand_l": Vector3(-0.3, 0.06, 0.38), "hand_r": Vector3(-0.32, 0.0, 0.4)}],
	]})
	K.reg_pair("parry", {"length": 0.42, "mask": &"upper", "events": [[0.3, &"parry"]], "keys": [
		[0.2, {"chest": Vector3(0, -16, 0), "hand_r": Vector3(-0.35, -0.15, 0.45), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(-20, 40, 0), "fist_r": 0.2}, &"out"],
		[0.35, {"chest": Vector3(0, 14, 0), "hand_r": Vector3(0.45, 0.15, 0.6), "elbow_r": Vector3(0.3, -1, 0), "wrist_r": Vector3(-50, 40, 0), "fist_r": 0.0}, &"snap"],
		[0.6, {"chest": Vector3(0, 8, 0), "hand_r": Vector3(0.4, 0.1, 0.55)}],
	]})


static func _hits() -> void:
	# Upper-body flinch clips (play_reaction(&"flinch") uses an additive version instead).
	K.reg(&"flinch_front", {"length": 0.36, "mask": &"upper", "events": [[0.05, &"impact"]], "keys": [
		[0.12, {"spine": Vector3(-6, 0, 0), "chest": Vector3(-12, 0, 0), "head": Vector3(-16, 0, 0), "clav_l": Vector3(10, 0, 0), "clav_r": Vector3(10, 0, 0)}, &"snap"]]})
	K.reg(&"flinch_back", {"length": 0.36, "mask": &"upper", "events": [[0.05, &"impact"]], "keys": [
		[0.12, {"spine": Vector3(8, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(14, 0, 0), "clav_l": Vector3(8, 0, 0), "clav_r": Vector3(8, 0, 0)}, &"snap"]]})
	K.reg(&"flinch_left", {"length": 0.36, "mask": &"upper", "events": [[0.05, &"impact"]], "keys": [
		[0.12, {"chest": Vector3(0, -12, -10), "head": Vector3(0, -14, -12), "clav_l": Vector3(12, 0, 0)}, &"snap"]]})
	K.reg(&"flinch_right", {"length": 0.36, "mask": &"upper", "events": [[0.05, &"impact"]], "keys": [
		[0.12, {"chest": Vector3(0, 12, 10), "head": Vector3(0, 14, 12), "clav_r": Vector3(12, 0, 0)}, &"snap"]]})
	var stag := {"length": 0.7, "events": [[0.04, &"impact"], [0.85, &"recover"]], "root": [[0.0, Vector3.ZERO], [0.5, Vector3(0, 0, -0.55)], [1.0, Vector3(0, 0, -0.6)]],
		"plants": [[0.42, "r", 0.9], [0.6, "l", 0.8]], "keys": [
		[0.1, {"hips": Vector3(0, -0.05, -0.08), "hips_rot": Vector3(-8, 0, 0), "spine": Vector3(-10, 0, 0), "chest": Vector3(-18, 0, 0), "head": Vector3(-22, 0, 0),
			"hand_l": Vector3(0.3, -0.5, 0.4), "hand_r": Vector3(0.35, -0.45, 0.35), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.3, "fist_r": 0.3}, &"snap"],
		[0.35, {"hips": Vector3(0, -0.12, -0.12), "spine": Vector3(6, 0, 0), "chest": Vector3(4, 0, 0), "head": Vector3(-4, 0, 0),
			"foot_r": Vector3(0.05, 0.1, -0.3), "foot_l": Vector3(0, 0, 0.05)}],
		[0.6, {"hips": Vector3(0, -0.1, -0.05), "foot_r": Vector3(0.05, 0, -0.28), "spine": Vector3(10, 0, 0), "chest": Vector3(6, 0, 0)}, &"out"],
	]}
	K.reg(&"stagger_front", stag)
	var stag_b := {"length": 0.7, "events": [[0.04, &"impact"], [0.85, &"recover"]], "root": [[0.0, Vector3.ZERO], [0.5, Vector3(0, 0, 0.5)], [1.0, Vector3(0, 0, 0.55)]],
		"plants": [[0.42, "l", 0.9]], "keys": [
		[0.1, {"hips": Vector3(0, -0.06, 0.08), "spine": Vector3(16, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(18, 0, 0),
			"hand_l": Vector3(0.45, -0.4, -0.1), "hand_r": Vector3(0.5, -0.35, -0.1), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT}, &"snap"],
		[0.38, {"hips": Vector3(0, -0.14, 0.1), "foot_l": Vector3(0, 0.12, 0.3), "foot_r": Vector3(0.04, 0, -0.04), "spine": Vector3(20, 0, 0)}],
		[0.62, {"hips": Vector3(0, -0.1, 0.05), "foot_l": Vector3(0, 0, 0.3), "spine": Vector3(10, 0, 0), "chest": Vector3(4, 0, 0)}, &"out"],
	]}
	K.reg(&"stagger_back", stag_b)
	var stag_side := {"length": 0.65, "events": [[0.04, &"impact"], [0.85, &"recover"]], "root": [[0.0, Vector3.ZERO], [0.5, Vector3(0.45, 0, 0)], [1.0, Vector3(0.5, 0, 0)]],
		"plants": [[0.4, "r", 0.9]], "keys": [
		[0.1, {"hips": Vector3(0.05, -0.06, 0), "hips_rot": Vector3(0, 0, -8), "spine": Vector3(0, 6, 10), "chest": Vector3(0, 14, 16), "head": Vector3(0, 18, 18),
			"hand_l": Vector3(0.25, -0.4, 0.45), "hand_r": Vector3(0.55, -0.4, 0.1), "elbow_r": K.ELBOW_OUT}, &"snap"],
		[0.38, {"hips": Vector3(0.1, -0.12, 0), "foot_r": Vector3(0.3, 0.1, 0.0), "chest": Vector3(0, 6, 4)}],
		[0.62, {"hips": Vector3(0.06, -0.1, 0), "foot_r": Vector3(0.28, 0, 0.0), "chest": Vector3(4, 0, 0)}, &"out"],
	]}
	# A hit from the left pushes the body to the right.
	K.reg(&"stagger_left", stag_side)
	K.reg(&"stagger_right", K.mirror(stag_side))
	K.reg(&"knockback_back", {"length": 0.95, "events": [[0.03, &"impact"], [0.88, &"recover"]],
		"root": [[0.0, Vector3.ZERO], [0.6, Vector3(0, 0, -1.6)], [1.0, Vector3(0, 0, -1.8)]], "plants": [[0.3, "r", 1.0], [0.48, "l", 1.0], [0.62, "r", 0.8]], "keys": [
		[0.08, {"hips": Vector3(0, -0.06, -0.12), "hips_rot": Vector3(-10, 0, 0), "spine": Vector3(-14, 0, 0), "chest": Vector3(-20, 0, 0), "head": Vector3(-25, 0, 0),
			"hand_l": Vector3(0.5, -0.1, 0.5), "hand_r": Vector3(0.55, -0.05, 0.45), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0, 0.1, 0.12), "foot_r": Vector3(0, 0, -0.1)}, &"snap"],
		[0.3, {"hips": Vector3(0, -0.2, -0.1), "foot_r": Vector3(0.06, 0, -0.35), "foot_l": Vector3(0, 0.12, 0.15)}],
		[0.55, {"hips": Vector3(0, -0.22, -0.05), "spine": Vector3(16, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-6, 0, 0),
			"foot_l": Vector3(0.02, 0, -0.1), "foot_r": Vector3(0.06, 0, -0.2), "hand_l": Vector3(0.3, -0.6, 0.35), "hand_r": Vector3(0.3, -0.6, 0.3)}, &"out"],
	]})


static func _down() -> void:
	# Knocked onto the back; ends in the down pose (then_state knocked_down).
	var down := {"hips": Vector3(0, -0.92, -0.3), "hips_rot": Vector3(-88, 0, 0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-2, 0, 0), "head": Vector3(14, 8, 0),
		"feet_hips": 1.0, "foot_l": Vector3(0.12, 0.0, 0.08), "foot_r": Vector3(0.06, 0.2, 0.25), "knee_l": Vector3(0.2, 0, 1), "knee_r": Vector3(0.2, 0, 1),
		"foot_rot_l": Vector3(20, 12, 0), "foot_rot_r": Vector3(10, 8, 0),
		"hand_l": Vector3(0.62, 0.05, -0.1), "hand_r": Vector3(0.45, -0.75, 0.3), "elbow_l": Vector3(0.2, -1, -0.5), "elbow_r": K.ELBOW_OUT, "fist_l": 0.3, "fist_r": 0.4}
	K.reg(&"knockdown_back", {"length": 1.0, "events": [[0.03, &"impact"], [0.55, &"ground_hit"]], "then_state": &"knocked_down", "hold": true,
		"root": [[0.0, Vector3.ZERO], [0.55, Vector3(0, 0, -1.2)], [1.0, Vector3(0, 0, -1.3)]], "keys": [
		[0.1, {"hips": Vector3(0, -0.08, -0.12), "hips_rot": Vector3(-12, 0, 0), "spine": Vector3(-16, 0, 0), "chest": Vector3(-20, 0, 0), "head": Vector3(-24, 0, 0),
			"hand_l": Vector3(0.6, 0.2, 0.35), "hand_r": Vector3(0.6, 0.25, 0.3), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0, 0.15, 0.25), "foot_r": Vector3(0.02, 0, 0.0)}, &"snap"],
		[0.32, {"hips": Vector3(0, -0.4, -0.25), "hips_rot": Vector3(-40, 0, 0), "spine": Vector3(-8, 0, 0), "head": Vector3(20, 0, 0),
			"feet_hips": 0.6, "foot_l": Vector3(0, 0.45, 0.4), "foot_r": Vector3(0.04, 0.3, 0.3)}, &"in"],
		[0.55, down, &"in"],
		[0.72, {"hips": Vector3(0, -0.88, -0.3), "head": Vector3(6, 0, 0), "foot_r": Vector3(0.06, 0.32, 0.3)}, &"out"],
		[1.0, down, &"inout"],
	]})
	K.reg(&"knockdown_front", {"length": 1.0, "events": [[0.03, &"impact"], [0.5, &"ground_hit"]], "then_state": &"knocked_down", "hold": true,
		"root": [[0.0, Vector3.ZERO], [0.5, Vector3(0, 0, 0.9)], [1.0, Vector3(0, 0, 1.0)]], "keys": [
		[0.1, {"hips": Vector3(0, -0.06, 0.12), "spine": Vector3(18, 0, 0), "chest": Vector3(16, 0, 0), "head": Vector3(20, 0, 0),
			"hand_l": Vector3(0.4, -0.3, -0.2), "hand_r": Vector3(0.45, -0.25, -0.2), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT}, &"snap"],
		[0.3, {"hips": Vector3(0, -0.35, 0.2), "hips_rot": Vector3(40, 0, 0), "hand_l": Vector3(0.2, -0.2, 0.8), "hand_r": Vector3(0.2, -0.2, 0.8), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"feet_hips": 0.5, "foot_l": Vector3(0, 0.2, -0.2), "foot_r": Vector3(0, 0.3, -0.3), "fist_l": 0.0, "fist_r": 0.0}, &"in"],
		[0.5, {"hips": Vector3(0, -0.8, 0.25), "hips_rot": Vector3(85, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-30, 0, 0),
			"feet_hips": 1.0, "foot_l": Vector3(0, 0.05, -0.05), "foot_r": Vector3(0.04, 0.1, -0.1), "hand_l": Vector3(0.3, 0.1, 0.5), "hand_r": Vector3(0.35, 0.1, 0.45)}, &"in"],
		[0.75, {"hips": Vector3(0, -0.82, 0.0), "hips_rot": Vector3(30, 0, 60), "feet_hips": 1.0}],
		[1.0, down, &"inout"],
	]})
	K.reg(&"down_loop", {"length": 2.6, "loop": true, "keys": [
		[0.0, down],
		[0.5, {"chest": Vector3(-4, 0, 0), "head": Vector3(10, 10, 0)}],
	]})
	K.reg(&"getup", {"length": 1.1, "events": [[0.9, &"recover"]], "plants": [[0.62, "l", 0.8], [0.8, "r", 0.8]], "keys": [
		[0.0, down],
		[0.25, {"hips": Vector3(0, -0.72, -0.25), "hips_rot": Vector3(-55, 0, 0), "spine": Vector3(20, 0, 0), "chest": Vector3(20, 0, 0), "head": Vector3(0, 0, 0),
			"feet_hips": 1.0, "foot_l": Vector3(0.1, 0.35, 0.45), "foot_r": Vector3(0.06, 0.3, 0.45),
			"hand_l": Vector3(0.45, -0.85, -0.3), "hand_r": Vector3(0.45, -0.85, -0.3), "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK}],
		[0.55, {"hips": Vector3(0, -0.55, -0.1), "hips_rot": Vector3(0, 0, 0), "spine": Vector3(40, 0, 0), "chest": Vector3(15, 0, 0), "head": Vector3(-20, 0, 0),
			"feet_hips": 0.0, "foot_l": Vector3(0.1, 0, 0.15), "foot_r": Vector3(0.1, 0, -0.15), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_FWD,
			"hand_l": Vector3(0.3, -0.7, 0.5), "hand_r": Vector3(0.35, -0.85, 0.2)}, &"inout"],
		[0.8, {"hips": Vector3(0, -0.15, 0.0), "spine": Vector3(14, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(-6, 0, 0), "foot_l": Vector3(0.04, 0, 0.05), "foot_r": Vector3(0.04, 0, -0.05)}, &"out"],
	]})
	K.reg(&"launch", {"length": 0.5, "events": [[0.03, &"impact"]], "then_state": &"tumbling", "hold": true, "keys": [
		[0.15, {"hips": Vector3(0, 0.05, -0.05), "hips_rot": Vector3(-25, 0, 0), "spine": Vector3(-15, 0, 0), "chest": Vector3(-20, 0, 0), "head": Vector3(-25, 0, 0),
			"hand_l": Vector3(0.7, 0.4, 0.2), "hand_r": Vector3(0.65, 0.5, 0.1), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0,
			"feet_hips": 1.0, "foot_l": Vector3(0, 0.2, 0.25), "foot_r": Vector3(0.05, 0.05, -0.1)}, &"snap"],
		[1.0, {"hips_rot": Vector3(-70, 0, 10), "spine": Vector3(-10, 0, 0), "feet_hips": 1.0, "foot_l": Vector3(0, 0.35, 0.35), "foot_r": Vector3(0.05, 0.15, 0.1)}],
	]})
	K.reg(&"air_tumble", {"length": 0.9, "loop": true, "keys": [
		[0.0, {"hips_rot": Vector3(-70, 0, 10), "spine": Vector3(-10, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(10, 0, 0),
			"hand_l": Vector3(0.7, 0.3, 0.1), "hand_r": Vector3(0.6, 0.45, 0.0), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0,
			"feet_hips": 1.0, "foot_l": Vector3(0, 0.35, 0.35), "foot_r": Vector3(0.05, 0.15, 0.1)}],
		[0.5, {"hips_rot": Vector3(-80, 0, -10), "hand_l": Vector3(0.6, 0.45, 0.0), "hand_r": Vector3(0.7, 0.3, 0.1), "foot_l": Vector3(0, 0.15, 0.1), "foot_r": Vector3(0.05, 0.35, 0.35)}],
	]})
	K.reg(&"knockdown_land", {"length": 0.6, "events": [[0.05, &"ground_hit"]], "then_state": &"knocked_down", "hold": true, "keys": [
		[0.0, {"hips": Vector3(0, -0.6, -0.2), "hips_rot": Vector3(-70, 0, 0), "feet_hips": 1.0, "foot_l": Vector3(0, 0.3, 0.3), "foot_r": Vector3(0.05, 0.2, 0.2)}],
		[0.3, {"hips": Vector3(0, -0.86, -0.3), "hips_rot": Vector3(-92, 0, 0), "head": Vector3(25, 0, 0), "feet_hips": 1.0, "foot_l": Vector3(0.1, 0.25, 0.3), "foot_r": Vector3(0.06, 0.35, 0.35)}, &"in"],
		[1.0, down, &"out"],
	]})
	var dead := down.duplicate()
	dead["head"] = Vector3(4, 25, 0)
	dead["hand_r"] = Vector3(0.7, -0.2, 0.0)
	dead["foot_r"] = Vector3(0.1, 0.02, 0.05)
	dead["fist_l"] = 0.1
	dead["fist_r"] = 0.1
	K.reg(&"death_front", {"length": 1.4, "events": [[0.03, &"impact"], [0.55, &"ground_hit"]], "then_state": &"dead", "hold": true, "keys": [
		[0.12, {"hips": Vector3(0, -0.05, -0.1), "spine": Vector3(-16, 0, 0), "chest": Vector3(-22, 0, 0), "head": Vector3(-28, 0, 0),
			"hand_l": Vector3(0.4, -0.2, 0.5), "hand_r": Vector3(-0.2, -0.3, 0.45), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 0.0, "fist_r": 0.0}, &"snap"],
		[0.3, {"hips": Vector3(0, -0.4, -0.1), "spine": Vector3(25, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(20, 0, 0), "foot_l": Vector3(0, 0, 0.2), "foot_r": Vector3(0.1, 0, -0.1)}, &"in"],
		[0.55, {"hips": Vector3(0, -0.84, -0.25), "hips_rot": Vector3(-70, 0, 0), "spine": Vector3(-10, 0, 0), "head": Vector3(20, 0, 0),
			"feet_hips": 1.0, "foot_l": Vector3(0.1, 0.1, 0.2), "foot_r": Vector3(0.06, 0.2, 0.25), "hand_l": Vector3(0.6, 0.1, 0.0), "hand_r": Vector3(0.5, -0.5, 0.3)}, &"in"],
		[1.0, dead, &"out"],
	]})
	K.reg(&"death_back", {"length": 1.4, "events": [[0.03, &"impact"], [0.55, &"ground_hit"]], "then_state": &"dead", "state_clip": &"dead_loop_prone", "hold": true, "keys": [
		[0.12, {"hips": Vector3(0, -0.05, 0.1), "spine": Vector3(18, 0, 0), "chest": Vector3(20, 0, 0), "head": Vector3(12, 0, 0), "hand_l": Vector3(0.45, -0.3, -0.2), "hand_r": Vector3(0.5, -0.3, -0.2)}, &"snap"],
		[0.35, {"hips": Vector3(0, -0.4, 0.15), "spine": Vector3(30, 0, 0), "foot_l": Vector3(0, 0, -0.2), "foot_r": Vector3(0.1, 0.1, 0.0)}, &"in"],
		[0.55, {"hips": Vector3(0, -0.8, 0.2), "hips_rot": Vector3(80, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-25, 30, 0), "feet_hips": 1.0, "foot_l": Vector3(0.1, 0.0, -0.05), "foot_r": Vector3(0.1, 0.1, 0.0),
			"hand_l": Vector3(0.5, 0.2, 0.4), "hand_r": Vector3(0.6, 0.1, 0.3)}, &"in"],
		[1.0, {"hips": Vector3(0, -0.92, 0.22), "hips_rot": Vector3(88, 0, 0), "chest": Vector3(-6, 0, 0), "head": Vector3(-20, 40, 0), "feet_hips": 1.0,
			"foot_l": Vector3(0.12, 0.0, 0.0), "foot_r": Vector3(0.05, 0.08, -0.05), "hand_l": Vector3(0.55, 0.3, 0.3), "hand_r": Vector3(0.7, -0.1, 0.1), "fist_l": 0.1, "fist_r": 0.1}, &"out"],
	]})
	K.reg(&"dead_loop", {"length": 4.0, "loop": true, "keys": [[0.0, dead]]})
	K.reg(&"dead_loop_prone", {"length": 4.0, "loop": true, "keys": [[0.0, {"hips": Vector3(0, -0.92, 0.22), "hips_rot": Vector3(88, 0, 0), "chest": Vector3(-6, 0, 0),
		"head": Vector3(-20, 40, 0), "feet_hips": 1.0, "foot_l": Vector3(0.12, 0.0, 0.0), "foot_r": Vector3(0.05, 0.08, -0.05), "hand_l": Vector3(0.55, 0.3, 0.3),
		"hand_r": Vector3(0.7, -0.1, 0.1), "fist_l": 0.1, "fist_r": 0.1}]]})
