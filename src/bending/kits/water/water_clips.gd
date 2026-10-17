class_name WaterClips
extends RefCounted
## Waterbending body motion for the Water techniques (Tai Chi: continuous
## circles, push-pull, weight shifting from the back foot to the front foot),
## registered into AnimLibrary (docs/modules/characters.md "Clips").
##
##   water_surge_heave   scoop low, circle the water overhead on the back foot, step in and drive it down
##   water_ice_wall      sink into a horse stance, lift both palms, clench: the wall freezes
##   water_ice_trap      low sweeping palm along the ground, rising fist clench on &"freeze"
##   water_wave_ride     (loop) surf stance riding the wave, arms balancing
##   water_wave_crash    from the ride: step down and push the crest forward
##   water_jet_open      (hold) palms stacked forward, the jet pours out on &"release"
##   water_heal_channel  (hold) cupped glowing water pressed to the chest, head bowed
##   tidal_torrent       gather low, rise, spin with the vortex, rear back, drive it forward
##   water_torrent_hold  (loop, upper) a slow two-hand circle keeping the gathered torrent turning
## WaterClips.ensure() is called by the Water kit (registry load) and by every
## Water ability before playing a clip, so rig-less casters get the events too.

const K = preload("res://src/characters/anim/clips/clip_kit.gd")

static var _done := false


static func ensure() -> void:
	if _done:
		return
	_done = true
	_surge()
	_ice()
	_wave()
	_jet_heal()
	_tidal()


static func _surge() -> void:
	K.reg(&"water_surge_heave", {"length": 1.25, "events": [[0.3, &"gather"], [0.6, &"release"], [0.86, &"recover"]],
		"plants": [[0.12, "r", 0.6], [0.58, "l", 1.2]], "keys": [
		# Sink and reach down to scoop the water up from the ground in front.
		[0.16, {"hips": Vector3(0, -0.26, -0.04), "hips_rot": Vector3(0, 18, 0), "spine": Vector3(26, 0, 0), "chest": Vector3(8, 16, 0),
			"head": Vector3(-20, -10, 0), "hand_l": Vector3(0.32, -0.88, 0.42), "hand_r": Vector3(0.18, -0.92, 0.48),
			"wrist_l": Vector3(20, -80, 0), "wrist_r": Vector3(20, -80, 0), "elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0.08, 0, 0.22), "foot_r": Vector3(0.12, 0, -0.2), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT}, &"inout"],
		# Weight rolls onto the back foot as the arms circle out and up (the mass rises).
		[0.34, {"hips": Vector3(0, -0.12, -0.14), "hips_rot": Vector3(0, -6, 0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-10, -8, 0),
			"head": Vector3(-6, 0, 0), "hand_l": Vector3(0.85, 0.15, 0.25), "hand_r": Vector3(0.85, 0.2, 0.2),
			"wrist_l": Vector3(-10, -60, 0), "wrist_r": Vector3(-10, -60, 0), "elbow_l": Vector3(0.2, -1, -0.3), "elbow_r": Vector3(0.2, -1, -0.3),
			"foot_l": Vector3(0.08, 0.06, 0.3), "foot_r": Vector3(0.12, 0, -0.24)}, &"inout"],
		# Overhead: the whole wave hangs above the bender, chest open, back arched.
		[0.48, {"hips": Vector3(0, -0.06, -0.16), "spine": Vector3(-10, 0, 0), "chest": Vector3(-16, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_l": Vector3(0.35, 0.92, 0.2), "hand_r": Vector3(0.35, 0.92, 0.2), "wrist_l": Vector3(-40, 90, 0), "wrist_r": Vector3(-40, 90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "foot_l": Vector3(0.08, 0.1, 0.34)}, &"out"],
		# Step in and drive both palms down-forward: the wave crashes.
		[0.6, {"hips": Vector3(0, -0.3, 0.2), "hips_rot": Vector3(4, 0, 0), "spine": Vector3(28, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(-24, 0, 0),
			"hand_l": Vector3(-0.02, -0.32, 0.98), "hand_r": Vector3(-0.02, -0.36, 0.98), "wrist_l": Vector3(-70, 90, 0), "wrist_r": Vector3(-70, 90, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "foot_l": Vector3(0.1, 0, 0.55), "foot_r": Vector3(0.12, 0, -0.32),
			"foot_rot_r": Vector3(0, 30, 0), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT}, &"snap"],
		[0.8, {"hips": Vector3(0, -0.26, 0.17), "spine": Vector3(22, 0, 0), "hand_l": Vector3(0.0, -0.42, 0.9), "hand_r": Vector3(0.0, -0.45, 0.9)}],
	]})


static func _ice() -> void:
	var horse := {"foot_l": Vector3(0.26, 0, 0.0), "foot_r": Vector3(0.26, 0, 0.0), "foot_rot_l": Vector3(0, 20, 0), "foot_rot_r": Vector3(0, 20, 0),
		"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}
	K.reg(&"water_ice_wall", {"length": 0.95, "events": [[0.2, &"gather"], [0.5, &"release"], [0.82, &"recover"]],
		"plants": [[0.18, "l", 0.9], [0.2, "r", 0.9]], "keys": [
		# Sink into a horse stance, palms up near the ground (gathering the water).
		[0.2, _merge(horse, {"hips": Vector3(0, -0.3, 0.0), "spine": Vector3(24, 0, 0), "chest": Vector3(8, 0, 0), "head": Vector3(-18, 0, 0),
			"hand_l": Vector3(0.18, -0.86, 0.5), "hand_r": Vector3(0.18, -0.86, 0.5), "wrist_l": Vector3(20, -90, 0), "wrist_r": Vector3(20, -90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.0, "fist_r": 0.0}), &"inout"],
		# Lift: both palms rise in front, the water climbs into a sheet.
		[0.44, _merge(horse, {"hips": Vector3(0, -0.12, 0.04), "spine": Vector3(-2, 0, 0), "chest": Vector3(-8, 0, 0), "head": Vector3(-6, 0, 0),
			"hand_l": Vector3(0.12, 0.45, 0.62), "hand_r": Vector3(0.12, 0.45, 0.62), "wrist_l": Vector3(-20, -90, 0), "wrist_r": Vector3(-20, -90, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN}), &"out"],
		# Clench: fists snap shut and pull back an inch, the sheet freezes solid.
		[0.52, _merge(horse, {"hips": Vector3(0, -0.16, 0.02), "chest": Vector3(-4, 0, 0), "hand_l": Vector3(0.14, 0.35, 0.5), "hand_r": Vector3(0.14, 0.35, 0.5),
			"wrist_l": Vector3(0, -90, 0), "wrist_r": Vector3(0, -90, 0), "fist_l": 1.0, "fist_r": 1.0}), &"snap"],
		[0.8, _merge(horse, {"hips": Vector3(0, -0.15, 0.02), "hand_l": Vector3(0.1, 0.2, 0.48), "hand_r": Vector3(0.1, 0.2, 0.48)})],
	]})
	K.reg(&"water_ice_trap", {"length": 0.9, "events": [[0.4, &"release"], [0.7, &"freeze"], [0.86, &"recover"]],
		"plants": [[0.38, "r", 1.0]], "keys": [
		# Coil: turn away, right palm low behind the hip.
		[0.18, {"hips": Vector3(0, -0.18, -0.05), "hips_rot": Vector3(0, -24, 0), "spine": Vector3(12, -10, 0), "chest": Vector3(6, -22, 0), "head": Vector3(-8, 26, 0),
			"hand_r": Vector3(0.38, -0.7, -0.22), "elbow_r": K.ELBOW_OUT, "wrist_r": Vector3(-10, -70, 0), "fist_r": 0.0,
			"hand_l": Vector3(-0.15, -0.25, 0.55), "wrist_l": Vector3(-40, 80, 0), "fist_l": 0.0, "foot_r": Vector3(0.1, 0.12, -0.05)}, &"inout"],
		# Low lunge: the palm skims the ground toward the target (water snakes away).
		[0.4, {"hips": Vector3(0, -0.36, 0.14), "hips_rot": Vector3(4, 14, 0), "spine": Vector3(32, 4, 0), "chest": Vector3(10, 18, 0), "head": Vector3(-26, -10, 0),
			"hand_r": Vector3(0.02, -0.82, 0.78), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(-30, 90, 0),
			"hand_l": Vector3(0.45, -0.5, -0.2), "foot_r": Vector3(0.12, 0, 0.5), "foot_l": Vector3(0.14, 0, -0.26), "foot_rot_l": Vector3(0, 30, 0),
			"knee_r": K.KNEE_FWD, "knee_l": K.KNEE_OUT}, &"snap"],
		[0.6, {"hips": Vector3(0, -0.24, 0.1), "spine": Vector3(14, 0, 0), "chest": Vector3(4, 10, 0), "head": Vector3(-12, -6, 0),
			"hand_r": Vector3(0.0, -0.3, 0.82), "wrist_r": Vector3(-10, 90, 0), "fist_r": 0.3}, &"inout"],
		# The clench: the fist closes and lifts, the water around the target freezes.
		[0.72, {"hips": Vector3(0, -0.2, 0.08), "spine": Vector3(8, 0, 0), "chest": Vector3(-2, 8, 0),
			"hand_r": Vector3(-0.02, 0.05, 0.72), "elbow_r": K.ELBOW_DOWN, "wrist_r": Vector3(0, 90, 0), "fist_r": 1.0, "hand_l": Vector3(0.3, -0.5, 0.0), "fist_l": 1.0}, &"snap"],
		[0.86, {"hips": Vector3(0, -0.18, 0.06), "hand_r": Vector3(-0.04, -0.05, 0.66)}],
	]})


static func _wave() -> void:
	var ride := {"hips": Vector3(0, -0.24, 0.0), "hips_rot": Vector3(4, 32, 0), "spine": Vector3(12, -12, 0), "chest": Vector3(4, -16, 0), "head": Vector3(-8, -26, 0),
		"foot_l": Vector3(0.12, 0, 0.36), "foot_r": Vector3(0.14, 0, -0.34), "foot_rot_l": Vector3(0, 10, 0), "foot_rot_r": Vector3(0, 40, 0),
		"knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT,
		"hand_l": Vector3(0.62, -0.2, 0.5), "hand_r": Vector3(0.66, -0.3, -0.3), "wrist_l": Vector3(-20, 80, 0), "wrist_r": Vector3(-20, 60, 0),
		"elbow_l": K.ELBOW_DOWN, "elbow_r": Vector3(0.4, -1, -0.4), "fist_l": 0.0, "fist_r": 0.0}
	K.reg(&"water_wave_ride", {"length": 1.4, "loop": true, "blend_in": 0.12, "keys": [
		[0.0, ride],
		[0.5, _merge(ride, {"hips": Vector3(0, -0.29, 0.03), "spine": Vector3(15, -10, 0), "hand_l": Vector3(0.6, -0.05, 0.55), "hand_r": Vector3(0.7, -0.18, -0.36),
			"wrist_l": Vector3(-30, 70, 0)})],
	]})
	K.reg(&"water_wave_crash", {"length": 0.7, "events": [[0.42, &"release"], [0.84, &"recover"]], "plants": [[0.4, "l", 1.3]], "keys": [
		[0.0, ride],
		[0.24, _merge(ride, {"hips": Vector3(0, -0.14, -0.06), "hips_rot": Vector3(0, 10, 0), "chest": Vector3(-10, -6, 0),
			"hand_l": Vector3(0.3, 0.6, 0.3), "hand_r": Vector3(0.3, 0.62, 0.25), "wrist_l": Vector3(-40, 90, 0), "wrist_r": Vector3(-40, 90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT}), &"inout"],
		[0.42, {"hips": Vector3(0, -0.3, 0.18), "hips_rot": Vector3(4, 0, 0), "spine": Vector3(26, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(-22, 0, 0),
			"hand_l": Vector3(-0.04, -0.3, 0.98), "hand_r": Vector3(-0.04, -0.34, 0.98), "wrist_l": Vector3(-70, 90, 0), "wrist_r": Vector3(-70, 90, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "foot_l": Vector3(0.1, 0, 0.5), "foot_r": Vector3(0.12, 0, -0.3),
			"foot_rot_l": Vector3(0, 0, 0), "knee_l": K.KNEE_FWD}, &"snap"],
		[0.75, {"hips": Vector3(0, -0.22, 0.12), "hand_l": Vector3(0.0, -0.4, 0.88), "hand_r": Vector3(0.0, -0.42, 0.88)}],
	]})


static func _jet_heal() -> void:
	# Jet: the back hand stacks behind the front palm, both driving forward.
	K.reg(&"water_jet_open", {"length": 0.5, "hold": true, "events": [[0.55, &"release"]], "plants": [[0.5, "l", 0.9]], "keys": [
		[0.25, {"hips": Vector3(0, -0.1, -0.06), "hips_rot": Vector3(0, -12, 0), "chest": Vector3(-4, -20, 0), "spine": Vector3(0, -6, 0),
			"hand_l": Vector3(0.2, -0.45, 0.15), "hand_r": Vector3(0.28, -0.48, 0.02), "wrist_l": Vector3(-20, 80, 0), "wrist_r": Vector3(-20, 80, 0),
			"elbow_l": K.ELBOW_BACK, "elbow_r": K.ELBOW_BACK, "fist_l": 0.0, "fist_r": 0.0}, &"inout"],
		[0.55, {"hips": Vector3(0, -0.2, 0.12), "hips_rot": Vector3(0, 8, 0), "spine": Vector3(10, 2, 0), "chest": Vector3(6, 10, 0), "head": Vector3(-10, -8, 0),
			"hand_l": Vector3(-0.22, -0.02, 0.98), "hand_r": Vector3(-0.42, -0.08, 0.74), "wrist_l": Vector3(-82, 90, 0), "wrist_r": Vector3(-75, 90, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "clav_l": Vector3(0, 12, 0),
			"foot_l": Vector3(0.1, 0, 0.42), "foot_r": Vector3(0.12, 0, -0.26), "foot_rot_r": Vector3(0, 35, 0), "knee_r": K.KNEE_OUT}, &"snap"],
		[1.0, {"hips": Vector3(0, -0.21, 0.12), "hand_l": Vector3(-0.22, -0.03, 0.97), "hand_r": Vector3(-0.42, -0.09, 0.73)}],
	]})
	# Healing: rooted low stance, both hands cupping glowing water against the chest.
	K.reg(&"water_heal_channel", {"length": 0.9, "hold": true, "events": [[0.45, &"gather"], [0.7, &"release"]], "keys": [
		[0.3, {"hips": Vector3(0, -0.16, 0), "spine": Vector3(16, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(-10, 0, 0),
			"hand_l": Vector3(0.3, -0.75, 0.42), "hand_r": Vector3(0.3, -0.75, 0.42), "wrist_l": Vector3(20, -90, 0), "wrist_r": Vector3(20, -90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.0, "fist_r": 0.0,
			"foot_l": Vector3(0.18, 0, 0.06), "foot_r": Vector3(0.18, 0, -0.06), "knee_l": K.KNEE_OUT, "knee_r": K.KNEE_OUT}, &"inout"],
		[0.7, {"hips": Vector3(0, -0.22, 0), "spine": Vector3(12, 0, 0), "chest": Vector3(2, 0, 0), "head": Vector3(22, 0, 0),
			"hand_l": Vector3(-0.32, -0.42, 0.34), "hand_r": Vector3(-0.3, -0.5, 0.3), "wrist_l": Vector3(30, 60, 0), "wrist_r": Vector3(30, 60, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "foot_l": Vector3(0.2, 0, 0.06), "foot_r": Vector3(0.2, 0, -0.06)}, &"out"],
		[1.0, {"hips": Vector3(0, -0.23, 0), "hand_l": Vector3(-0.31, -0.43, 0.35), "hand_r": Vector3(-0.29, -0.51, 0.31), "head": Vector3(24, 0, 0)}],
	]})
	# Torrent gather (heavy hold): slow two-hand circle around the torso.
	K.reg(&"water_torrent_hold", {"length": 1.6, "loop": true, "mask": &"upper", "keys": [
		[0.0, {"chest": Vector3(4, -18, 0), "spine": Vector3(2, -8, 0), "hand_l": Vector3(0.7, -0.15, 0.35), "hand_r": Vector3(0.1, -0.6, 0.25),
			"wrist_l": Vector3(-30, 70, 0), "wrist_r": Vector3(10, -80, 0), "fist_l": 0.0, "fist_r": 0.0, "elbow_l": Vector3(0.3, -1, -0.2), "elbow_r": K.ELBOW_OUT}],
		[0.25, {"chest": Vector3(2, 0, 0), "spine": Vector3(0, 0, 0), "hand_l": Vector3(0.2, 0.15, 0.6), "hand_r": Vector3(0.25, -0.4, 0.55)}],
		[0.5, {"chest": Vector3(4, 18, 0), "spine": Vector3(2, 8, 0), "hand_r": Vector3(0.7, -0.15, 0.35), "hand_l": Vector3(0.1, -0.6, 0.25),
			"wrist_r": Vector3(-30, 70, 0), "wrist_l": Vector3(10, -80, 0), "elbow_r": Vector3(0.3, -1, -0.2), "elbow_l": K.ELBOW_OUT}],
		[0.75, {"chest": Vector3(2, 0, 0), "spine": Vector3(0, 0, 0), "hand_r": Vector3(0.2, 0.15, 0.6), "hand_l": Vector3(0.25, -0.4, 0.55)}],
	]})


static func _tidal() -> void:
	var horse := {"foot_l": Vector3(0.28, 0, 0.0), "foot_r": Vector3(0.28, 0, 0.0), "foot_rot_l": Vector3(0, 20, 0), "foot_rot_r": Vector3(0, 20, 0),
		"knee_l": Vector3(0.9, 0, 0.7), "knee_r": Vector3(0.9, 0, 0.7)}
	K.reg(&"tidal_torrent", {"length": 3.0, "blend_in": 0.1,
		"events": [[0.1, &"gather"], [0.26, &"rise"], [0.74, &"release"], [0.9, &"recover"]],
		"plants": [[0.1, "l", 1.0], [0.11, "r", 1.0], [0.74, "l", 1.4]], "keys": [
		# Sink: the water of the whole area is called in, palms up, low.
		[0.1, _merge(horse, {"hips": Vector3(0, -0.36, 0), "spine": Vector3(28, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-20, 0, 0),
			"hand_l": Vector3(0.62, -0.78, 0.3), "hand_r": Vector3(0.62, -0.78, 0.3), "wrist_l": Vector3(20, -90, 0), "wrist_r": Vector3(20, -90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "fist_l": 0.0, "fist_r": 0.0}), &"inout"],
		# Rise with it: chest opens to the sky, arms sweep overhead.
		[0.26, {"hips": Vector3(0, -0.04, 0), "spine": Vector3(-8, 0, 0), "chest": Vector3(-18, 0, 0), "head": Vector3(-24, 0, 0),
			"hand_l": Vector3(0.62, 0.78, 0.12), "hand_r": Vector3(0.62, 0.78, 0.12), "wrist_l": Vector3(-30, 90, 0), "wrist_r": Vector3(-30, 90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "foot_l": Vector3(0.14, 0, 0.04), "foot_r": Vector3(0.14, 0, -0.04)}, &"out"],
		# Turn with the vortex: arms spread, the body revolves on the water column.
		[0.42, {"hips": Vector3(0, -0.1, 0), "hips_rot": Vector3(0, -180, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(-4, -20, 0), "head": Vector3(-10, 20, 0),
			"hand_l": Vector3(0.95, 0.25, 0.1), "hand_r": Vector3(0.95, 0.05, 0.15), "wrist_l": Vector3(-20, 60, 0), "wrist_r": Vector3(-20, 60, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "feet_hips": 0.7, "foot_l": Vector3(0.1, 0.05, 0.08), "foot_r": Vector3(0.1, 0.0, -0.08)}],
		[0.58, {"hips": Vector3(0, -0.08, 0), "hips_rot": Vector3(0, -360, 0), "chest": Vector3(-4, -20, 0), "head": Vector3(-10, 20, 0),
			"hand_l": Vector3(0.95, 0.05, 0.15), "hand_r": Vector3(0.95, 0.25, 0.1), "feet_hips": 0.7}],
		# Rear back over the right shoulder: the vortex coils behind the bender.
		[0.68, {"hips": Vector3(0, -0.12, -0.12), "hips_rot": Vector3(0, -380, 0), "spine": Vector3(-6, -10, 0), "chest": Vector3(-14, -26, 0), "head": Vector3(-10, 20, 0),
			"hand_l": Vector3(0.2, 0.7, -0.1), "hand_r": Vector3(0.5, 0.65, -0.3), "wrist_l": Vector3(-40, 90, 0), "wrist_r": Vector3(-40, 90, 0),
			"elbow_l": K.ELBOW_OUT, "elbow_r": K.ELBOW_OUT, "feet_hips": 0.0, "foot_l": Vector3(0.1, 0.08, 0.2), "foot_r": Vector3(0.12, 0, -0.2)}, &"inout"],
		# Drive it forward: big step, both palms down-forward.
		[0.74, {"hips": Vector3(0, -0.34, 0.22), "hips_rot": Vector3(4, -360, 0), "spine": Vector3(30, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(-26, 0, 0),
			"hand_l": Vector3(-0.04, -0.28, 1.0), "hand_r": Vector3(-0.04, -0.32, 1.0), "wrist_l": Vector3(-72, 90, 0), "wrist_r": Vector3(-72, 90, 0),
			"elbow_l": K.ELBOW_DOWN, "elbow_r": K.ELBOW_DOWN, "foot_l": Vector3(0.1, 0, 0.58), "foot_r": Vector3(0.14, 0, -0.34),
			"foot_rot_r": Vector3(0, 30, 0), "knee_l": K.KNEE_FWD, "knee_r": K.KNEE_OUT}, &"snap"],
		[0.9, {"hips": Vector3(0, -0.3, 0.18), "hips_rot": Vector3(2, -360, 0), "spine": Vector3(24, 0, 0), "hand_l": Vector3(0.0, -0.4, 0.92), "hand_r": Vector3(0.0, -0.44, 0.92)}],
	]})


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var c := a.duplicate()
	for k: String in b:
		c[k] = b[k]
	return c
