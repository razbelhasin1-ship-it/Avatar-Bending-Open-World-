class_name RigStyles
extends RefCounted
## Movement styles: gait parameters (interpolated across walk / run / sprint
## reference speeds) and the looping idle / combat-stance clips. Each element
## style follows the martial art the show based it on:
##   air   - Ba Gua: light, bouncy, on the balls of the feet, airy trailing arms.
##   earth - Hung Gar: low, wide, heavy rooted steps, fists, little bounce.
##   fire  - Northern Shaolin: forward-weighted, aggressive, tight punchy arms.
##   water - Tai Chi: smooth gliding steps, weight shifting, floating arms.
## plus civilian, soldier, elder and child locomotion.
##
## Array values are [walk, run, sprint]. Distances are in leg lengths, angles
## in degrees, cadence in gait cycles (two steps) per second.

const DEFAULT := &"civilian"

const DATA := {
	&"civilian": {
		"speeds": [1.4, 4.4, 7.2], "cadence": [0.92, 1.36, 1.56], "duty": [0.61, 0.36, 0.28],
		"lift": [0.07, 0.17, 0.22], "bob": [0.012, 0.03, 0.035], "sway": [0.014, 0.006, 0.003],
		"hip_yaw": [6.0, 9.0, 11.0], "hip_roll": [4.0, 4.0, 3.0], "lean": [2.0, 9.0, 15.0],
		"arm_swing": [0.17, 0.36, 0.5], "arm_bend": [0.12, 0.58, 0.72], "arm_out": 0.1,
		"width": 0.0, "toe_out": 7.0, "heel": 0.0, "crouch": 0.0, "head": -2.0,
		"weight": 1.0, "idle": &"idle_civilian", "stance": &"stance_civilian",
	},
	&"air": {
		"speeds": [1.5, 4.8, 7.8], "cadence": [1.0, 1.42, 1.58], "duty": [0.56, 0.31, 0.24],
		"lift": [0.1, 0.22, 0.26], "bob": [0.022, 0.045, 0.045], "sway": [0.01, 0.005, 0.002],
		"hip_yaw": [8.0, 10.0, 10.0], "hip_roll": [3.0, 3.0, 2.0], "lean": [1.0, 10.0, 18.0],
		"arm_swing": [0.14, 0.24, 0.3], "arm_bend": [0.2, 0.35, 0.4], "arm_out": 0.2, "arm_trail": 0.25,
		"width": -0.01, "toe_out": 4.0, "heel": 0.55, "crouch": 0.0, "head": -4.0,
		"weight": 0.55, "idle": &"idle_air", "stance": &"stance_air",
	},
	&"earth": {
		"speeds": [1.3, 4.0, 6.6], "cadence": [0.84, 1.26, 1.46], "duty": [0.66, 0.42, 0.33],
		"lift": [0.05, 0.13, 0.17], "bob": [0.008, 0.02, 0.025], "sway": [0.022, 0.012, 0.006],
		"hip_yaw": [5.0, 7.0, 8.0], "hip_roll": [2.0, 2.0, 2.0], "lean": [4.0, 9.0, 13.0],
		"arm_swing": [0.11, 0.26, 0.38], "arm_bend": [0.45, 0.75, 0.8], "arm_out": 0.18, "fist": 1.0,
		"width": 0.07, "toe_out": 14.0, "heel": 0.0, "crouch": 0.04, "head": 0.0, "plant_drop": 0.018,
		"weight": 1.3, "idle": &"idle_earth", "stance": &"stance_earth",
	},
	&"fire": {
		"speeds": [1.5, 4.7, 7.6], "cadence": [0.98, 1.42, 1.6], "duty": [0.6, 0.34, 0.26],
		"lift": [0.07, 0.17, 0.22], "bob": [0.01, 0.03, 0.035], "sway": [0.01, 0.004, 0.002],
		"hip_yaw": [7.0, 11.0, 13.0], "hip_roll": [3.0, 3.0, 2.0], "lean": [5.0, 14.0, 20.0],
		"arm_swing": [0.16, 0.42, 0.55], "arm_bend": [0.35, 0.75, 0.8], "arm_out": 0.08, "fist": 1.0,
		"width": 0.0, "toe_out": 6.0, "heel": 0.15, "crouch": 0.01, "head": 3.0,
		"weight": 1.0, "idle": &"idle_fire", "stance": &"stance_fire",
	},
	&"water": {
		"speeds": [1.35, 4.4, 7.2], "cadence": [0.86, 1.32, 1.5], "duty": [0.64, 0.38, 0.3],
		"lift": [0.05, 0.14, 0.19], "bob": [0.006, 0.02, 0.025], "sway": [0.022, 0.009, 0.004],
		"hip_yaw": [7.0, 8.0, 9.0], "hip_roll": [3.0, 3.0, 2.0], "lean": [2.0, 9.0, 15.0],
		"arm_swing": [0.12, 0.3, 0.42], "arm_bend": [0.3, 0.5, 0.62], "arm_out": 0.22, "arm_float": 0.12,
		"width": 0.01, "toe_out": 8.0, "heel": 0.0, "crouch": 0.02, "head": -2.0,
		"weight": 0.85, "idle": &"idle_water", "stance": &"stance_water",
	},
	&"soldier": {
		"speeds": [1.5, 4.3, 7.0], "cadence": [0.96, 1.36, 1.54], "duty": [0.62, 0.37, 0.29],
		"lift": [0.07, 0.15, 0.2], "bob": [0.01, 0.028, 0.032], "sway": [0.008, 0.004, 0.002],
		"hip_yaw": [4.0, 7.0, 9.0], "hip_roll": [3.0, 3.0, 2.0], "lean": [0.0, 8.0, 14.0],
		"arm_swing": [0.2, 0.36, 0.48], "arm_bend": [0.05, 0.55, 0.7], "arm_out": 0.07, "fist": 0.9,
		"width": 0.0, "toe_out": 5.0, "heel": 0.0, "crouch": 0.0, "head": 0.0, "chest_out": 4.0,
		"weight": 1.1, "idle": &"idle_soldier", "stance": &"stance_soldier",
	},
	&"elder": {
		"speeds": [0.95, 2.4, 3.6], "cadence": [0.78, 1.05, 1.2], "duty": [0.68, 0.48, 0.4],
		"lift": [0.04, 0.09, 0.11], "bob": [0.006, 0.014, 0.018], "sway": [0.018, 0.012, 0.01],
		"hip_yaw": [4.0, 5.0, 6.0], "hip_roll": [2.0, 2.0, 2.0], "lean": [12.0, 18.0, 22.0],
		"arm_swing": [0.03, 0.15, 0.22], "arm_bend": [0.3, 0.6, 0.7], "arm_out": 0.08, "hands_back": 1.0,
		"width": 0.02, "toe_out": 12.0, "heel": 0.0, "crouch": 0.03, "head": -14.0,
		"weight": 0.8, "idle": &"idle_elder", "stance": &"stance_civilian",
	},
	&"child": {
		"speeds": [1.2, 3.6, 5.6], "cadence": [1.1, 1.6, 1.8], "duty": [0.58, 0.33, 0.27],
		"lift": [0.1, 0.22, 0.26], "bob": [0.02, 0.045, 0.05], "sway": [0.014, 0.006, 0.004],
		"hip_yaw": [7.0, 9.0, 10.0], "hip_roll": [4.0, 4.0, 3.0], "lean": [1.0, 9.0, 14.0],
		"arm_swing": [0.22, 0.42, 0.52], "arm_bend": [0.15, 0.55, 0.65], "arm_out": 0.14,
		"width": 0.0, "toe_out": 5.0, "heel": 0.2, "crouch": 0.0, "head": -5.0,
		"weight": 0.6, "idle": &"idle_child", "stance": &"stance_civilian",
	},
}


static func has_style(style: StringName) -> bool:
	return DATA.has(style)


static func get_style(style: StringName) -> Dictionary:
	return DATA.get(style, DATA[DEFAULT])


## Interpolates a [walk, run, sprint] parameter at `speed` (m/s, model scale).
static func param(st: Dictionary, key: String, speed: float) -> float:
	var arr: Array = st[key]
	var sp: Array = st["speeds"]
	var w := float(sp[0])
	var r := float(sp[1])
	var s := float(sp[2])
	if speed <= w:
		return float(arr[0])
	if speed <= r:
		return lerpf(float(arr[0]), float(arr[1]), smoothstep(w, r, speed))
	return lerpf(float(arr[1]), float(arr[2]), smoothstep(r, s, minf(speed, s)))
