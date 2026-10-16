class_name LocomotionProfile
extends Resource
## Per-element movement feel (docs/GAME_DESIGN.md §3). The numbers below are the
## design table; relationships matter more than absolutes: air fastest/lightest,
## earth heaviest/most stable, fire aggressive, water smooth and gliding.
##
##   var p := LocomotionProfile.for_element(ElementDefs.Element.AIR)
##   p.jump_height()        # 3.49 m (v^2 / 2g)
##
## Speeds are m/s, accelerations m/s^2, turn rates deg/s.

@export var element: int = ElementDefs.Element.NONE
@export var walk_speed := 3.0
@export var run_speed := 6.5
@export var sprint_speed := 9.0
## Water only: sprint speed while skating on snow/ice (0 = cannot skate).
@export var skate_speed := 0.0
@export var accel := 24.0
@export var decel := 24.0
## Facing turn rate (deg/s) and the velocity "carve" rate while running.
@export var turn_rate := 600.0
## Extra exponential smoothing of the facing target (s, 0 = none). Water: smoothed turns.
@export var turn_smoothing := 0.0
@export var jump_velocity := 6.0
## Second jump in the air (Air only, 0 = none).
@export var air_jump_velocity := 0.0
@export var air_jumps := 0
@export var gravity_scale := 1.0
## Gravity multiplier while falling (snappier arcs; 1 = symmetric).
@export var fall_gravity_mult := 1.15
## Fraction of ground acceleration available in the air.
@export var air_control := 0.5
## Air only: hold jump while falling to glide (max fall speed, forward speed).
@export var glide_fall_speed := 0.0
@export var glide_speed := 0.0
@export var knockback_mult := 1.0
@export var coyote_time := 0.12
@export var jump_buffer := 0.15
@export var max_slope_deg := 40.0
@export var step_height := 0.38
## Deep snow slows walking by up to this fraction (WorldData.get_snow_depth).
@export var snow_slow_max := 0.3
## Water: deep snow does not slow the sprint (skating / riding the snow).
@export var snow_ignored_when_sprinting := false
## Landing style: &"cushion" (air), &"quake" (earth), &"normal", &"spray" (water).
@export var landing: StringName = &"normal"
## Earth: falls higher than this (m) trigger a small quake on landing.
@export var quake_fall_height := 4.0
## Dodge (design table; the dodge ability reads these).
@export var dodge_distance := 4.0
@export var dodge_duration := 0.34
@export var dodge_iframes := 0.25
@export var dodge_in_air := false
@export var dodge_poise_armor := false
## HumanoidRig preset + animation style for this element's bender.
@export var rig_preset: StringName = &"water_tribe"
@export var rig_style: StringName = &"water"
## Swimming speeds (all elements) and wading slowdown at waist depth.
@export var swim_speed := 3.0
@export var swim_sprint_speed := 4.6
@export var wade_slow_max := 0.45

const G := 9.8

const TABLE := {
	ElementDefs.Element.AIR: {
		"walk_speed": 3.4, "run_speed": 7.6, "sprint_speed": 11.5, "accel": 42.0, "decel": 30.0,
		"turn_rate": 900.0, "jump_velocity": 7.4, "air_jump_velocity": 6.5, "air_jumps": 1,
		"gravity_scale": 0.8, "fall_gravity_mult": 1.0, "air_control": 0.85, "glide_fall_speed": 2.2, "glide_speed": 9.0,
		"knockback_mult": 1.3, "landing": &"cushion", "dodge_distance": 7.0, "dodge_duration": 0.36,
		"dodge_iframes": 0.32, "dodge_in_air": true, "rig_preset": &"air_nomad", "rig_style": &"air",
		"swim_speed": 3.4, "swim_sprint_speed": 5.0,
	},
	ElementDefs.Element.EARTH: {
		"walk_speed": 2.8, "run_speed": 5.6, "sprint_speed": 7.6, "accel": 16.0, "decel": 28.0,
		"turn_rate": 380.0, "jump_velocity": 5.0, "gravity_scale": 1.3, "fall_gravity_mult": 1.25, "air_control": 0.2,
		"knockback_mult": 0.4, "landing": &"quake", "dodge_distance": 3.0, "dodge_duration": 0.42,
		"dodge_iframes": 0.0, "dodge_poise_armor": true, "rig_preset": &"earth_kingdom", "rig_style": &"earth",
		"swim_speed": 2.6, "swim_sprint_speed": 3.8,
	},
	ElementDefs.Element.FIRE: {
		"walk_speed": 3.1, "run_speed": 6.9, "sprint_speed": 9.6, "accel": 32.0, "decel": 24.0,
		"turn_rate": 650.0, "jump_velocity": 6.3, "gravity_scale": 1.0, "fall_gravity_mult": 1.2, "air_control": 0.5,
		"knockback_mult": 1.0, "landing": &"normal", "dodge_distance": 4.5, "dodge_duration": 0.26,
		"dodge_iframes": 0.2, "rig_preset": &"fire_nation", "rig_style": &"fire",
	},
	ElementDefs.Element.WATER: {
		"walk_speed": 3.0, "run_speed": 6.5, "sprint_speed": 9.2, "skate_speed": 12.0, "accel": 20.0, "decel": 12.0,
		"turn_rate": 520.0, "turn_smoothing": 0.035, "jump_velocity": 6.0, "gravity_scale": 1.0, "fall_gravity_mult": 1.1,
		"air_control": 0.55, "knockback_mult": 0.9, "landing": &"spray", "snow_ignored_when_sprinting": true,
		"dodge_distance": 4.0, "dodge_duration": 0.36, "dodge_iframes": 0.26, "rig_preset": &"water_tribe", "rig_style": &"water",
		"swim_speed": 3.8, "swim_sprint_speed": 5.6,
	},
}

static var _cache: Dictionary = {}


## Shared, read-only profile for an element (falls back to water).
static func for_element(e: int) -> LocomotionProfile:
	if not TABLE.has(e):
		e = ElementDefs.Element.WATER
	if _cache.has(e):
		return _cache[e]
	var p := LocomotionProfile.new()
	p.element = e
	var d: Dictionary = TABLE[e]
	for k: String in d:
		p.set(k, d[k])
	_cache[e] = p
	return p


## Effective gravity (m/s^2) while rising.
func gravity() -> float:
	return G * gravity_scale


## Apex height of a standing jump (m).
func jump_height() -> float:
	return jump_velocity * jump_velocity / (2.0 * gravity())


## Extra height gained by the air jump from its start (m).
func air_jump_height() -> float:
	return air_jump_velocity * air_jump_velocity / (2.0 * gravity()) if air_jumps > 0 else 0.0


func can_glide() -> bool:
	return glide_fall_speed > 0.0


func can_skate() -> bool:
	return skate_speed > 0.0


## Ground target speed for a stick magnitude (0..1) and sprint flag.
func target_speed(magnitude: float, sprinting: bool) -> float:
	var m := clampf(magnitude, 0.0, 1.0)
	if m < 0.05:
		return 0.0
	if sprinting and m > 0.5:
		return sprint_speed
	if m <= 0.5:
		return walk_speed * (m / 0.5)
	return lerpf(walk_speed, run_speed, (m - 0.5) / 0.5)
