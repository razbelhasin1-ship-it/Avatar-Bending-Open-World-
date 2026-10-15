class_name ClipsElements
extends RefCounted
## Element-flavoured strikes and combos (body language per martial art):
##   air_*   Ba Gua palms, circular entries, light steps
##   earth_* Hung Gar: heavy horizontal fists, stomps, rooted horse stance
##   fire_*  Northern Shaolin: fast snapping fists, long extended kicks
##   water_* Tai Chi: continuous arcs, pushes, whips
## Combos: combo_<style>_1..N (single hits, chain on input) and combo_<style>
## (the whole chain in one clip, one &"impact" per hit).

const K = preload("res://src/characters/anim/clips/clip_kit.gd")


static func register_all() -> void:
	var air := _air()
	var earth := _earth()
	var fire := _fire()
	var water := _water()
	for pair: Array in [["air", air], ["earth", earth], ["fire", fire], ["water", water]]:
		var hits: Array = pair[1]
		for i in hits.size():
			K.reg(StringName("combo_%s_%d" % [pair[0], i + 1]), hits[i])
		K.reg(StringName("combo_%s" % pair[0]), K.chain(hits, {"meta": {"hits": hits.size()}}))
	# Element names for the generic moves (same motion, element-specific name).
	for a: Array in [[&"earth_wall", &"wall_raise"], [&"earth_stomp_r", &"stomp_r"], [&"earth_stomp_l", &"stomp_l"],
			[&"earth_slam", &"ground_slam"], [&"water_whip_r", &"whip_lash_r"], [&"water_whip_l", &"whip_lash_l"],
			[&"water_draw", &"draw_up"], [&"air_spin", &"spin_attack"], [&"air_tornado", &"tornado_spin"],
			[&"air_charge_release", &"charge_release"], [&"fire_spin_kick_r", &"roundhouse_r"], [&"fire_spin_kick_l", &"roundhouse_l"],
			[&"fire_charge_hold", &"charge_hold_fire"], [&"air_charge_hold", &"charge_hold_air"], [&"fire_flip_kick", &"flip_kick"],
			[&"earth_shield", &"shield_raise"]]:
		AnimLibrary.alias(a[0], a[1])


static func _air() -> Array:
	var palm := {"length": 0.45, "mask": &"upper", "events": [[0.45, &"release"], [0.48, &"impact"], [0.8, &"recover"]], "plants": [[0.4, "r", 0.5]], "keys": [
		[0.2, {"hand_r": Vector3(0.35, -0.55, 0.3), "elbow_r": K.ELBOW_OUT, "wrist_r": Vector3(-20, 90, 0), "fist_r": 0.0, "chest": Vector3(0, -16, 0), "hips_rot": Vector3(0, -8, 0)}, &"inout"],
		[0.46, {"hand_r": Vector3(-0.1, 0.02, 0.95), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(-82, 90, 0), "chest": Vector3(2, 22, 0), "hips_rot": Vector3(0, 12, 0),
			"clav_r": Vector3(0, 14, 0), "hand_l": Vector3(-0.35, -0.3, 0.35), "wrist_l": Vector3(-30, 60, 0), "fist_l": 0.0}, &"snap"],
		[0.66, {"hand_r": Vector3(-0.08, 0.0, 0.88)}],
	]}
	K.reg_pair("air_jab", palm)
	K.reg(&"air_blast", {"length": 0.6, "events": [[0.45, &"release"], [0.82, &"recover"]], "plants": [[0.42, "l", 0.6]], "keys": [
		[0.25, {"hips": Vector3(0, -0.05, -0.05), "chest": Vector3(-8, -30, 0), "spine": Vector3(-2, -10, 0), "hand_l": Vector3(0.1, -0.2, 0.15), "hand_r": Vector3(0.3, -0.25, 0.05),
			"wrist_l": Vector3(-30, 60, 0), "wrist_r": Vector3(-30, 60, 0), "fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK,
			"foot_l": Vector3(0.0, 0.1, 0.05)}, &"inout"],
		[0.46, {"hips": Vector3(0, -0.1, 0.12), "chest": Vector3(6, 10, 0), "spine": Vector3(4, 4, 0), "hand_l": Vector3(-0.18, 0.05, 0.95), "hand_r": Vector3(-0.22, -0.05, 0.92),
			"wrist_l": Vector3(-82, 90, 0), "wrist_r": Vector3(-82, 90, 0), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"foot_l": Vector3(0.0, 0.0, 0.4), "foot_r": Vector3(0.06, 0, -0.18), "foot_rot_r": Vector3(0, 30, 0)}, &"snap"],
		[0.7, {"hips": Vector3(0, -0.09, 0.1), "hand_l": Vector3(-0.14, 0.0, 0.88), "hand_r": Vector3(-0.18, -0.08, 0.86)}],
	]})
	K.reg(&"air_sweep", {"length": 0.85, "events": [[0.45, &"release"], [0.85, &"recover"]], "keys": [
		[0.18, {"hips": Vector3(0, -0.3, 0), "hips_rot": Vector3(0, 40, 0), "chest": Vector3(4, 20, 0), "hand_r": Vector3(0.7, -0.35, 0.3), "hand_l": Vector3(0.6, -0.3, -0.1),
			"foot_r": Vector3(0.35, 0.0, 0.1), "knee_r": K.KNEE_OUT, "fist_l": 0.0, "fist_r": 0.0, "wrist_r": Vector3(-20, 80, 0)}, &"out"],
		[0.45, {"hips": Vector3(0, -0.42, 0), "hips_rot": Vector3(0, -120, 0), "spine": Vector3(16, 0, 0), "chest": Vector3(8, -10, 0), "foot_r": Vector3(0.55, 0.05, -0.2),
			"foot_l": Vector3(0.1, 0, 0.0), "knee_l": K.KNEE_OUT, "hand_r": Vector3(0.9, -0.1, 0.0), "hand_l": Vector3(0.85, -0.1, 0.1), "head": Vector3(-10, 30, 0)}],
		[0.75, {"hips": Vector3(0, -0.25, 0), "hips_rot": Vector3(0, -360, 0), "chest": Vector3(0, 0, 0), "foot_r": Vector3(0.15, 0, -0.05), "hand_r": Vector3(-0.3, -0.3, 0.45),
			"hand_l": Vector3(-0.05, -0.15, 0.6), "head": Vector3(0, 0, 0)}, &"out"],
	]})
	K.reg(&"charge_hold_air", {"length": 1.4, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"hand_l": Vector3(-0.15, -0.05, 0.55), "hand_r": Vector3(-0.15, -0.45, 0.5), "wrist_l": Vector3(-10, -80, 0), "wrist_r": Vector3(-10, 80, 0), "fist_l": 0.0, "fist_r": 0.0,
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "chest": Vector3(2, 0, 0)}],
		[0.25, {"hand_l": Vector3(0.05, -0.25, 0.6), "hand_r": Vector3(-0.35, -0.25, 0.45)}],
		[0.5, {"hand_l": Vector3(-0.15, -0.45, 0.5), "hand_r": Vector3(-0.15, -0.05, 0.55), "wrist_l": Vector3(-10, 80, 0), "wrist_r": Vector3(-10, -80, 0)}],
		[0.75, {"hand_l": Vector3(-0.35, -0.25, 0.45), "hand_r": Vector3(0.05, -0.25, 0.6)}],
	]})
	# Combo: palm L, palm R with a turning step, spinning two-hand push.
	var h1 := {"length": 0.4, "mask": &"upper", "events": [[0.5, &"impact"]], "keys": [
		[0.15, {"hand_l": Vector3(0.3, -0.5, 0.3), "wrist_l": Vector3(-20, 90, 0), "fist_l": 0.0, "chest": Vector3(0, 14, 0)}],
		[0.5, {"hand_l": Vector3(-0.1, 0.0, 0.95), "wrist_l": Vector3(-82, 90, 0), "elbow_l": K.ELBOW_DOWN, "chest": Vector3(2, -22, 0), "clav_l": Vector3(0, 14, 0),
			"hand_r": Vector3(-0.35, -0.3, 0.35), "fist_r": 0.0}, &"snap"],
		[0.85, {"hand_l": Vector3(-0.15, -0.15, 0.7), "chest": Vector3(0, -12, 0)}],
	]}
	var h2 := {"length": 0.42, "mask": &"full", "events": [[0.5, &"impact"]], "plants": [[0.45, "r", 0.5]], "keys": [
		[0.15, {"hand_r": Vector3(0.35, -0.5, 0.25), "wrist_r": Vector3(-20, 90, 0), "fist_r": 0.0, "chest": Vector3(0, -16, 0), "hand_l": Vector3(-0.25, -0.3, 0.45)}],
		[0.5, {"hand_r": Vector3(-0.1, 0.02, 0.95), "wrist_r": Vector3(-82, 90, 0), "elbow_r": K.ELBOW_DOWN, "chest": Vector3(2, 24, 0), "clav_r": Vector3(0, 14, 0),
			"hips": Vector3(0, -0.06, 0.1), "foot_r": Vector3(0.0, 0, 0.32), "hand_l": Vector3(-0.4, -0.35, 0.3)}, &"snap"],
		[0.85, {"hand_r": Vector3(-0.15, -0.15, 0.7), "chest": Vector3(0, 12, 0)}],
	]}
	var h3 := {"length": 0.7, "mask": &"full", "events": [[0.62, &"release"], [0.64, &"impact"]], "keys": [
		[0.3, {"hips_rot": Vector3(0, -180, 0), "hips": Vector3(0, -0.12, 0.05), "chest": Vector3(0, -20, 0), "hand_l": Vector3(0.6, -0.2, 0.2), "hand_r": Vector3(0.6, -0.2, 0.2),
			"head": Vector3(0, 30, 0), "foot_r": Vector3(0.0, 0.1, 0.15)}],
		[0.62, {"hips_rot": Vector3(0, -360, 0), "hips": Vector3(0, -0.1, 0.12), "chest": Vector3(6, 0, 0), "head": Vector3(0, 0, 0),
			"hand_l": Vector3(-0.18, 0.05, 0.95), "hand_r": Vector3(-0.2, -0.05, 0.93), "wrist_l": Vector3(-82, 90, 0), "wrist_r": Vector3(-82, 90, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "foot_r": Vector3(0.0, 0.0, 0.35), "foot_l": Vector3(0.05, 0, -0.15)}, &"snap"],
	]}
	return [h1, h2, h3]


static func _earth() -> Array:
	var horse := {"foot_l": Vector3(0.26, 0, 0.0), "foot_r": Vector3(0.26, 0, 0.0), "foot_rot_l": Vector3(0, 22, 0), "foot_rot_r": Vector3(0, 22, 0),
		"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}
	# Heavy horizontal fist with a stomp (launches a rock).
	var punch := {"length": 0.6, "events": [[0.42, &"stomp"], [0.46, &"release"], [0.48, &"impact"], [0.82, &"recover"]], "plants": [[0.42, "r", 1.4]], "keys": [
		[0.25, {"hips": Vector3(0, -0.08, 0), "hips_rot": Vector3(0, -16, 0), "chest": Vector3(-4, -18, 0), "hand_r": Vector3(0.05, -0.45, -0.18), "elbow_r": K.ELBOW_BACK,
			"fist_r": 1.0, "wrist_r": Vector3(10, -80, 0), "hand_l": Vector3(-0.05, -0.2, 0.6), "fist_l": 1.0, "foot_r": Vector3(0.12, 0.3, 0.05), "knee_r": Vector3(0.6, 0.3, 1)}, &"inout"],
		[0.46, {"hips": Vector3(0, -0.16, 0.04), "hips_rot": Vector3(2, 14, 0), "chest": Vector3(6, 18, 0), "spine": Vector3(4, 6, 0), "hand_r": Vector3(-0.15, -0.08, 0.98),
			"elbow_r": Vector3(0.6, -1, 0), "wrist_r": Vector3(0, 90, 0), "clav_r": Vector3(-2, 14, 0), "hand_l": Vector3(0.05, -0.48, -0.1), "elbow_l": K.ELBOW_BACK,
			"foot_r": Vector3(0.28, 0.0, 0.08), "foot_rot_r": Vector3(0, 25, 0), "knee_r": K.KNEE_OUT, "head": Vector3(-4, -14, 0)}, &"snap"],
		[0.7, {"hips": Vector3(0, -0.15, 0.03), "hand_r": Vector3(-0.12, -0.1, 0.92)}],
	]}
	K.reg_pair("earth_jab", punch)
	K.reg_alias([&"earth_raise"], {"length": 0.8, "events": [[0.3, &"stomp"], [0.55, &"release"], [0.85, &"recover"]], "plants": [[0.3, "r", 1.4]], "keys": [
		[0.3, _merge(horse, {"hips": Vector3(0, -0.24, 0), "spine": Vector3(26, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(-20, 0, 0),
			"hand_l": Vector3(0.0, -0.85, 0.45), "hand_r": Vector3(0.0, -0.85, 0.45), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 1.0, "fist_r": 1.0,
			"wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0)}), &"inout"],
		[0.55, _merge(horse, {"hips": Vector3(0, -0.1, 0.02), "spine": Vector3(-6, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_l": Vector3(0.0, 0.25, 0.6), "hand_r": Vector3(0.0, 0.25, 0.6), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}), &"snap"],
		[0.75, {"hips": Vector3(0, -0.12, 0.0), "hand_l": Vector3(0.0, 0.2, 0.58), "hand_r": Vector3(0.0, 0.2, 0.58)}],
	]})
	K.reg(&"earth_throw", {"length": 1.0, "events": [[0.25, &"stomp"], [0.45, &"lift"], [0.7, &"release"], [0.9, &"recover"]], "plants": [[0.25, "l", 1.3]], "keys": [
		[0.25, _merge(horse, {"hips": Vector3(0, -0.22, 0), "spine": Vector3(24, 0, 0), "hand_l": Vector3(0.1, -0.85, 0.35), "hand_r": Vector3(0.1, -0.85, 0.35),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.6, "fist_r": 0.6, "wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0)}), &"inout"],
		[0.5, {"hips": Vector3(0, -0.08, -0.04), "spine": Vector3(-10, 0, 0), "chest": Vector3(-16, 0, 0), "head": Vector3(-10, 0, 0),
			"hand_l": Vector3(0.1, 0.85, 0.15), "hand_r": Vector3(0.1, 0.85, 0.15), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "wrist_l": Vector3(-40, -80, 0), "wrist_r": Vector3(-40, -80, 0),
			"fist_l": 0.2, "fist_r": 0.2}],
		[0.7, {"hips": Vector3(0, -0.15, 0.12), "spine": Vector3(16, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-14, 0, 0), "hand_l": Vector3(-0.1, 0.05, 0.95), "hand_r": Vector3(-0.1, 0.05, 0.95),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "wrist_l": Vector3(-70, 90, 0), "wrist_r": Vector3(-70, 90, 0), "foot_l": Vector3(0.12, 0, 0.35), "foot_r": Vector3(0.2, 0, -0.1)}, &"snap"],
		[0.85, {"hips": Vector3(0, -0.14, 0.1)}],
	]})
	var p2 := K.mirror(punch)
	var finisher := {"length": 0.8, "events": [[0.3, &"stomp"], [0.56, &"impact"], [0.6, &"release"]], "plants": [[0.3, "l", 1.4]], "keys": [
		[0.3, _merge(horse, {"hips": Vector3(0, -0.24, 0), "spine": Vector3(24, 0, 0), "chest": Vector3(12, 0, 0), "hand_l": Vector3(0.0, -0.85, 0.42),
			"hand_r": Vector3(0.0, -0.85, 0.42), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 1.0, "fist_r": 1.0}), &"inout"],
		[0.56, _merge(horse, {"hips": Vector3(0, -0.08, 0.04), "spine": Vector3(-6, 0, 0), "chest": Vector3(-12, 0, 0), "hand_l": Vector3(0.0, 0.3, 0.6), "hand_r": Vector3(0.0, 0.3, 0.6),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "wrist_l": Vector3(0, -80, 0), "wrist_r": Vector3(0, -80, 0)}), &"snap"],
	]}
	return [punch, p2, finisher]


static func _fire() -> Array:
	var jab := {"length": 0.32, "mask": &"upper", "events": [[0.4, &"release"], [0.43, &"impact"], [0.72, &"recover"]], "keys": [
		[0.18, {"hand_r": Vector3(0.02, -0.42, -0.06), "elbow_r": K.ELBOW_BACK, "fist_r": 1.0, "wrist_r": Vector3(0, -80, 0), "chest": Vector3(6, -6, 0)}, &"out"],
		[0.4, {"hand_r": Vector3(-0.14, 0.04, 1.0), "elbow_r": K.ELBOW_DOWN, "fist_r": 1.0, "wrist_r": Vector3(0, 88, 0), "chest": Vector3(10, 24, 0), "spine": Vector3(6, 8, 0),
			"clav_r": Vector3(0, 18, 0), "head": Vector3(-8, -16, 0), "hand_l": Vector3(0.04, -0.44, -0.1), "elbow_l": K.ELBOW_BACK, "fist_l": 1.0}, &"snap"],
		[0.6, {"hand_r": Vector3(-0.12, 0.02, 0.94)}],
	]}
	K.reg_pair("fire_jab", jab)
	K.reg_pair("fire_kick", {"length": 0.62, "events": [[0.4, &"release"], [0.42, &"impact"], [0.8, &"recover"]], "plants": [[0.9, "r", 1.0]], "keys": [
		[0.22, {"foot_r": Vector3(0.0, 0.5, 0.3), "knee_r": Vector3(0.05, 0.4, 1.0), "hips_rot": Vector3(-4, 0, 0), "hand_l": Vector3(-0.15, -0.1, 0.5), "hand_r": Vector3(0.1, -0.4, -0.1),
			"fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_BACK}, &"out"],
		[0.42, {"foot_r": Vector3(-0.05, 1.05, 0.75), "knee_r": Vector3(0.0, 1.0, 0.2), "foot_rot_r": Vector3(-20, 0, 0), "hips_rot": Vector3(-18, 4, 0), "spine": Vector3(-12, 0, 0),
			"chest": Vector3(-6, 0, 0), "head": Vector3(16, 0, 0), "hand_r": Vector3(0.4, -0.5, -0.3), "hand_l": Vector3(-0.1, 0.0, 0.6)}, &"snap"],
		[0.62, {"foot_r": Vector3(0.0, 0.45, 0.28), "knee_r": Vector3(0.05, 0.4, 1.0), "hips_rot": Vector3(-5, 0, 0)}, &"out"],
	]})
	K.reg(&"charge_hold_fire", {"length": 0.6, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(8, -22, 0), "spine": Vector3(4, -8, 0), "hand_l": Vector3(-0.08, -0.5, 0.1), "hand_r": Vector3(0.04, -0.52, -0.02),
			"elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "wrist_l": Vector3(0, 80, 0), "wrist_r": Vector3(0, -80, 0), "fist_l": 1.0, "fist_r": 1.0, "head": Vector3(-6, 10, 0)}],
		[0.5, {"chest": Vector3(9, -23, 0), "hand_l": Vector3(-0.08, -0.51, 0.11), "hand_r": Vector3(0.04, -0.51, -0.01)}],
	]})
	K.reg(&"fire_charge_release", {"length": 0.5, "events": [[0.36, &"release"], [0.8, &"recover"]], "keys": [
		[0.0, {"chest": Vector3(8, -22, 0), "spine": Vector3(4, -8, 0), "hand_l": Vector3(-0.08, -0.5, 0.1), "hand_r": Vector3(0.04, -0.52, -0.02),
			"elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "fist_l": 1.0, "fist_r": 1.0}],
		[0.36, {"hips": Vector3(0, -0.12, 0.12), "chest": Vector3(14, 6, 0), "spine": Vector3(8, 2, 0), "head": Vector3(-14, 0, 0),
			"hand_l": Vector3(-0.22, 0.0, 0.98), "hand_r": Vector3(-0.22, -0.06, 0.98), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": Vector3(0, 90, 0), "wrist_r": Vector3(0, 90, 0), "foot_l": Vector3(0, 0, 0.4), "foot_r": Vector3(0.1, 0, -0.25)}, &"snap"],
		[0.6, {"hips": Vector3(0, -0.12, 0.1), "hand_l": Vector3(-0.2, -0.02, 0.92), "hand_r": Vector3(-0.2, -0.08, 0.92)}],
	]})
	K.reg(&"fire_breath", {"length": 1.2, "events": [[0.35, &"inhale"], [0.45, &"release"], [0.85, &"recover"]], "keys": [
		[0.3, {"chest": Vector3(-12, 0, 0), "head": Vector3(-14, 0, 0), "clav_l": Vector3(10, 0, 0), "clav_r": Vector3(10, 0, 0), "hand_l": Vector3(0.05, -0.55, 0.1),
			"hand_r": Vector3(0.05, -0.55, 0.1), "fist_l": 1.0, "fist_r": 1.0, "elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "mouth": 0.0}, &"inout"],
		[0.45, {"chest": Vector3(12, 0, 0), "head": Vector3(-4, 0, 0), "hips": Vector3(0, -0.08, 0.06), "mouth": 1.0}, &"snap"],
		[0.8, {"chest": Vector3(10, 0, 0), "mouth": 0.9}],
	]})
	var j2 := K.mirror(jab)
	j2["length"] = 0.32
	var kick := {"length": 0.6, "mask": &"full", "events": [[0.45, &"impact"]], "keys": [
		[0.2, {"foot_r": Vector3(0.0, 0.55, 0.3), "knee_r": Vector3(0.05, 0.4, 1.0), "hand_l": Vector3(-0.15, -0.1, 0.5), "hand_r": Vector3(0.1, -0.4, -0.1), "fist_l": 1.0, "fist_r": 1.0}],
		[0.45, {"foot_r": Vector3(-0.05, 1.05, 0.75), "knee_r": Vector3(0.0, 1.0, 0.2), "hips_rot": Vector3(-18, 4, 0), "spine": Vector3(-10, 0, 0), "head": Vector3(14, 0, 0),
			"hand_r": Vector3(0.4, -0.5, -0.3), "hand_l": Vector3(-0.1, 0.0, 0.6)}, &"snap"],
		[0.85, {"foot_r": Vector3(0.0, 0.2, 0.3), "hips_rot": Vector3(-4, 0, 0)}],
	]}
	var spin_fist := {"length": 0.55, "mask": &"full", "events": [[0.62, &"release"], [0.64, &"impact"]], "keys": [
		[0.35, {"hips_rot": Vector3(0, 150, 0), "chest": Vector3(0, 30, 0), "head": Vector3(0, -40, 0), "foot_r": Vector3(0.0, 0, 0.0), "hand_l": Vector3(0.0, -0.4, 0.0), "hand_r": Vector3(0.0, -0.4, 0.0)}],
		[0.64, {"hips_rot": Vector3(0, 340, 0), "chest": Vector3(12, 20, 0), "head": Vector3(-6, -20, 0), "hips": Vector3(0, -0.12, 0.12), "hand_l": Vector3(-0.2, 0.0, 0.98),
			"hand_r": Vector3(-0.2, -0.06, 0.98), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "fist_l": 1.0, "fist_r": 1.0, "wrist_l": Vector3(0, 90, 0), "wrist_r": Vector3(0, 90, 0),
			"foot_l": Vector3(0, 0, 0.35), "foot_r": Vector3(0.1, 0, -0.2)}, &"snap"],
	]}
	return [jab, j2, kick, spin_fist]


static func _water() -> Array:
	var push := {"length": 0.6, "mask": &"upper", "events": [[0.55, &"release"], [0.85, &"recover"]], "keys": [
		[0.3, {"hand_r": Vector3(0.25, 0.1, 0.35), "elbow_r": K.ELBOW_OUT, "wrist_r": Vector3(-10, 70, 0), "fist_r": 0.0, "chest": Vector3(-4, -16, 0), "hips_rot": Vector3(0, -6, 0)}, &"inout"],
		[0.56, {"hand_r": Vector3(-0.1, -0.12, 0.93), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(-60, 90, 0), "chest": Vector3(4, 18, 0), "hips_rot": Vector3(0, 8, 0), "clav_r": Vector3(0, 12, 0)}, &"out"],
		[0.75, {"hand_r": Vector3(-0.06, -0.2, 0.86), "wrist_r": Vector3(-40, 90, 0)}],
	]}
	K.reg_pair("water_jab", push)
	K.reg_alias([&"water_surge"], {"length": 0.85, "events": [[0.55, &"release"], [0.88, &"recover"]], "plants": [[0.5, "l", 0.7]], "keys": [
		[0.3, {"hips": Vector3(0, -0.1, -0.08), "chest": Vector3(-8, 0, 0), "hand_l": Vector3(0.2, -0.25, 0.25), "hand_r": Vector3(0.2, -0.25, 0.25), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT,
			"wrist_l": Vector3(20, 80, 0), "wrist_r": Vector3(20, 80, 0), "fist_l": 0.0, "fist_r": 0.0, "foot_l": Vector3(0.05, 0, 0.12), "foot_r": Vector3(0.08, 0, -0.15)}, &"inout"],
		[0.55, {"hips": Vector3(0, -0.12, 0.14), "chest": Vector3(8, 0, 0), "hand_l": Vector3(-0.05, -0.15, 0.95), "hand_r": Vector3(-0.05, -0.15, 0.95), "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN,
			"wrist_l": Vector3(-60, 90, 0), "wrist_r": Vector3(-60, 90, 0), "foot_l": Vector3(0.05, 0, 0.4)}, &"out"],
		[0.8, {"hips": Vector3(0, -0.11, 0.12), "hand_l": Vector3(0.0, -0.2, 0.88), "hand_r": Vector3(0.0, -0.2, 0.88)}],
	]})
	K.reg(&"water_shield", {"length": 1.0, "events": [[0.6, &"release"]], "hold": true, "keys": [
		[0.25, {"hips": Vector3(0, -0.12, 0), "hand_l": Vector3(0.5, -0.6, 0.3), "hand_r": Vector3(0.5, -0.6, 0.3), "wrist_l": Vector3(10, -70, 0), "wrist_r": Vector3(10, -70, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.0, "fist_r": 0.0}, &"inout"],
		[0.6, {"hips": Vector3(0, -0.1, 0), "chest": Vector3(-6, 0, 0), "hand_l": Vector3(0.2, 0.3, 0.55), "hand_r": Vector3(0.2, 0.3, 0.55), "wrist_l": Vector3(-50, 90, 0), "wrist_r": Vector3(-50, 90, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}, &"out"],
		[1.0, {"hand_l": Vector3(0.22, 0.28, 0.56), "hand_r": Vector3(0.22, 0.28, 0.56)}],
	]})
	K.reg(&"water_heal_loop", {"length": 2.4, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"spine": Vector3(14, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(10, 0, 0), "hand_l": Vector3(-0.15, -0.5, 0.6), "hand_r": Vector3(-0.05, -0.55, 0.62),
			"wrist_l": Vector3(-10, 90, 0), "wrist_r": Vector3(-10, 90, 0), "fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}],
		[0.5, {"hand_l": Vector3(-0.1, -0.55, 0.62), "hand_r": Vector3(-0.1, -0.5, 0.6)}],
	]})
	var w1 := {"length": 0.55, "mask": &"upper", "events": [[0.6, &"impact"]], "keys": [
		[0.3, {"hand_r": Vector3(0.45, 0.5, -0.3), "elbow_r": Vector3(1, -0.2, -0.4), "wrist_r": Vector3(-40, 0, 0), "fist_r": 0.0, "chest": Vector3(-8, -24, -6)}, &"inout"],
		[0.6, {"hand_r": Vector3(-0.05, 0.2, 0.95), "elbow_r": Vector3(0.4, -1, 0.2), "wrist_r": Vector3(30, 70, 0), "chest": Vector3(8, 22, 4)}, &"snap"],
		[0.9, {"hand_r": Vector3(-0.2, -0.3, 0.8), "chest": Vector3(6, 16, 0)}],
	]}
	var w2 := K.mirror(w1)
	var w3 := {"length": 0.75, "mask": &"full", "events": [[0.6, &"release"], [0.62, &"impact"]], "keys": [
		[0.3, {"hips": Vector3(0, -0.12, -0.06), "chest": Vector3(-6, 0, 0), "hand_l": Vector3(0.3, -0.55, 0.3), "hand_r": Vector3(0.3, -0.55, 0.3), "wrist_l": Vector3(10, 80, 0),
			"wrist_r": Vector3(10, 80, 0), "fist_l": 0.0, "fist_r": 0.0, "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT}, &"inout"],
		[0.6, {"hips": Vector3(0, -0.12, 0.14), "chest": Vector3(8, 0, 0), "hand_l": Vector3(-0.05, -0.1, 0.95), "hand_r": Vector3(-0.05, -0.1, 0.95), "elbow_l": K.ELBOW_DOWN,
			"elbow_r": K.ELBOW_DOWN, "wrist_l": Vector3(-60, 90, 0), "wrist_r": Vector3(-60, 90, 0), "foot_l": Vector3(0.05, 0, 0.4), "foot_r": Vector3(0.08, 0, -0.12)}, &"out"],
	]}
	return [w1, w2, w3]


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var c := a.duplicate()
	for k: String in b:
		c[k] = b[k]
	return c
