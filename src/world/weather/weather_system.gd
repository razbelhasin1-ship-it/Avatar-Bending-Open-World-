class_name WeatherSystem
extends Node
## Per-region weather state machine with smooth transitions.
##
## States: clear, cloudy, snow, blizzard, rain, ash, fog (STATES). In auto mode the next state
## is drawn from the dominant region's table (REGION_TABLES) after a random hold time, and a
## state the region does not allow (e.g. blizzard after flying to the Fire Nation) is replaced
## quickly. `set_weather()` locks a state (quests, cinematics); `set_auto(true)` resumes.
## Every frame `update()` produces the blended parameters (`params`) used by the sky, fog,
## water, particles and snow refill, drives the global wind uniforms and emits
## Events.weather_changed when a new target state starts.

signal weather_changed(weather: StringName)

## Per-state parameters (all blended linearly during transitions).
const STATES := {
	&"clear": {"sky_fog": 0.0, "fog_floor": 0.0, "coverage": 0.25, "cloud_darkness": 0.0, "sun_mult": 1.0, "fog_mult": 1.0, "fog_tint": Color(0.8, 0.85, 0.9), "fog_tint_amount": 0.0,
			"ambient_mult": 1.0, "saturation_mult": 1.0, "haze_add": 0.0, "exposure_mult": 1.0, "fog_height_density": 0.0,
			"volumetric": 0.004, "cirrus": 0.35, "wind": 3.0, "gust": 0.25, "snow": 0.0, "blizzard": 0.0, "rain": 0.0, "ash": 0.0,
			"wetness": 0.0, "snow_cover": 0.0, "refill": 1.0, "waves": 0.55},
	&"cloudy": {"sky_fog": 0.08, "fog_floor": 0.0, "coverage": 0.72, "cloud_darkness": 0.22, "sun_mult": 0.55, "fog_mult": 1.35, "fog_tint": Color(0.70, 0.74, 0.80), "fog_tint_amount": 0.25,
			"ambient_mult": 1.2, "saturation_mult": 0.9, "haze_add": 0.1, "exposure_mult": 1.05, "fog_height_density": 0.0,
			"volumetric": 0.006, "cirrus": 0.1, "wind": 6.0, "gust": 0.4, "snow": 0.0, "blizzard": 0.0, "rain": 0.0, "ash": 0.0,
			"wetness": 0.0, "snow_cover": 0.0, "refill": 1.0, "waves": 0.8},
	&"snow": {"sky_fog": 0.55, "fog_floor": 0.0028, "coverage": 0.88, "cloud_darkness": 0.3, "sun_mult": 0.42, "fog_mult": 3.0, "fog_tint": Color(0.84, 0.88, 0.95), "fog_tint_amount": 0.55,
			"ambient_mult": 1.3, "saturation_mult": 0.85, "haze_add": 0.25, "exposure_mult": 1.05, "fog_height_density": 0.0,
			"volumetric": 0.012, "cirrus": 0.0, "wind": 4.0, "gust": 0.3, "snow": 1.0, "blizzard": 0.0, "rain": 0.0, "ash": 0.0,
			"wetness": 0.0, "snow_cover": 0.65, "refill": 3.5, "waves": 0.6},
	&"blizzard": {"sky_fog": 0.97, "fog_floor": 0.02, "coverage": 1.0, "cloud_darkness": 0.5, "sun_mult": 0.22, "fog_mult": 14.0, "fog_tint": Color(0.86, 0.90, 0.96), "fog_tint_amount": 0.85,
			"ambient_mult": 1.6, "saturation_mult": 0.7, "haze_add": 0.6, "exposure_mult": 1.0, "fog_height_density": 0.0,
			"volumetric": 0.035, "cirrus": 0.0, "wind": 17.0, "gust": 0.8, "snow": 0.35, "blizzard": 1.0, "rain": 0.0, "ash": 0.0,
			"wetness": 0.0, "snow_cover": 1.0, "refill": 9.0, "waves": 1.3},
	&"rain": {"sky_fog": 0.45, "fog_floor": 0.0016, "coverage": 0.95, "cloud_darkness": 0.55, "sun_mult": 0.35, "fog_mult": 2.4, "fog_tint": Color(0.55, 0.58, 0.62), "fog_tint_amount": 0.5,
			"ambient_mult": 1.25, "saturation_mult": 0.82, "haze_add": 0.3, "exposure_mult": 1.08, "fog_height_density": 0.0,
			"volumetric": 0.012, "cirrus": 0.0, "wind": 7.0, "gust": 0.55, "snow": 0.0, "blizzard": 0.0, "rain": 1.0, "ash": 0.0,
			"wetness": 1.0, "snow_cover": 0.0, "refill": 1.5, "waves": 1.0},
	&"ash": {"sky_fog": 0.5, "fog_floor": 0.003, "coverage": 0.7, "cloud_darkness": 0.45, "sun_mult": 0.55, "fog_mult": 3.2, "fog_tint": Color(0.56, 0.44, 0.38), "fog_tint_amount": 0.65,
			"ambient_mult": 1.1, "saturation_mult": 0.82, "haze_add": 0.35, "exposure_mult": 1.05, "fog_height_density": 0.0,
			"volumetric": 0.015, "cirrus": 0.0, "wind": 2.5, "gust": 0.2, "snow": 0.0, "blizzard": 0.0, "rain": 0.0, "ash": 1.0,
			"wetness": 0.0, "snow_cover": 0.0, "refill": 1.0, "waves": 0.5},
	&"fog": {"sky_fog": 0.8, "fog_floor": 0.011, "coverage": 0.55, "cloud_darkness": 0.1, "sun_mult": 0.6, "fog_mult": 5.0, "fog_tint": Color(0.82, 0.86, 0.90), "fog_tint_amount": 0.6,
			"ambient_mult": 1.25, "saturation_mult": 0.85, "haze_add": 0.5, "exposure_mult": 1.0, "fog_height_density": 0.06,
			"volumetric": 0.03, "cirrus": 0.0, "wind": 1.0, "gust": 0.1, "snow": 0.0, "blizzard": 0.0, "rain": 0.0, "ash": 0.0,
			"wetness": 0.2, "snow_cover": 0.0, "refill": 1.0, "waves": 0.35},
}

## Auto-weather odds per region (state -> weight). States missing from a table are not allowed there.
const REGION_TABLES := {
	&"water_tribe": {&"clear": 3.0, &"cloudy": 2.0, &"snow": 3.0, &"blizzard": 1.0, &"fog": 1.0},
	&"earth_kingdom": {&"clear": 5.0, &"cloudy": 3.0, &"rain": 2.0, &"fog": 1.0},
	&"fire_nation": {&"clear": 5.0, &"cloudy": 2.0, &"rain": 1.5, &"ash": 2.0},
	&"air_temple": {&"clear": 5.0, &"cloudy": 2.0, &"fog": 2.0, &"snow": 1.0},
	&"wilds": {&"clear": 4.0, &"cloudy": 3.0, &"rain": 1.0, &"fog": 1.0, &"snow": 1.0},
	&"ocean": {&"clear": 4.0, &"cloudy": 3.0, &"rain": 2.0, &"fog": 1.0},
}

## Real seconds a state holds before auto mode rolls the next one.
const HOLD_RANGE := Vector2(240.0, 720.0)
const AUTO_TRANSITION := Vector2(25.0, 50.0)

var current: StringName = &"clear"
var previous: StringName = &"clear"
## 0..1 progress of the transition previous -> current.
var blend: float = 1.0
var transition_time: float = 0.0
var auto: bool = true
## Blended parameters for this frame (keys of STATES entries).
var params: Dictionary = STATES[&"clear"].duplicate()
## Current wind: direction (normalised x/z), strength (m/s), gust (0..1).
var wind_dir := Vector2(0.8, 0.6)
var wind_speed: float = 3.0
var wind_gust: float = 0.0

var _hold: float = 300.0
var _snapshot: Dictionary = {}
var _wind_time: float = 0.0
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_hold = _rng.randf_range(HOLD_RANGE.x, HOLD_RANGE.y)


## Starts a transition to `weather` over `transition_s` seconds and locks auto mode.
func set_weather(weather: StringName, transition_s: float = 10.0) -> void:
	auto = false
	_begin(weather, transition_s)


## Resumes (true) or stops (false) the regional auto weather.
func set_auto(enabled: bool) -> void:
	auto = enabled
	_hold = _rng.randf_range(HOLD_RANGE.x, HOLD_RANGE.y) * 0.5


func _begin(weather: StringName, transition_s: float) -> void:
	if not STATES.has(weather):
		push_warning("WeatherSystem: unknown weather '%s'" % weather)
		return
	if weather == current and blend >= 1.0:
		return
	# start from what is visible right now
	_snapshot = params.duplicate()
	previous = current
	current = weather
	transition_time = maxf(transition_s, 0.0)
	blend = 0.0 if transition_time > 0.0 else 1.0
	_hold = _rng.randf_range(HOLD_RANGE.x, HOLD_RANGE.y)
	weather_changed.emit(current)
	Events.weather_changed.emit(current)



## True if `weather` may occur in `region` (auto mode).
static func is_allowed(weather: StringName, region: StringName) -> bool:
	return (REGION_TABLES.get(region, REGION_TABLES[&"wilds"]) as Dictionary).has(weather)


## Weighted random pick from a region table.
func roll(region: StringName) -> StringName:
	var table: Dictionary = REGION_TABLES.get(region, REGION_TABLES[&"wilds"])
	var total := 0.0
	for w: float in table.values():
		total += w
	var r := _rng.randf() * total
	for k: StringName in table:
		r -= float(table[k])
		if r <= 0.0:
			return k
	return &"clear"


## Advances transitions, auto weather and wind. Call once per frame.
func update(delta: float, region: StringName) -> void:
	_t += delta
	if blend < 1.0:
		blend = minf(blend + delta / maxf(transition_time, 0.001), 1.0)
	if auto:
		_hold -= delta
		if not is_allowed(current, region):
			_begin(roll(region), _rng.randf_range(AUTO_TRANSITION.x, AUTO_TRANSITION.y) * 0.6)
		elif _hold <= 0.0:
			var next := roll(region)
			if next == current:
				_hold = _rng.randf_range(HOLD_RANGE.x, HOLD_RANGE.y)
			else:
				_begin(next, _rng.randf_range(AUTO_TRANSITION.x, AUTO_TRANSITION.y))
	var from: Dictionary = _snapshot if not _snapshot.is_empty() else STATES[previous]
	params = _lerp_params(from, STATES[current], smoothstep(0.0, 1.0, blend))
	_update_wind(delta)


static func _lerp_params(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k: String in b:
		var va: Variant = a.get(k, b[k])
		var vb: Variant = b[k]
		if vb is Color:
			out[k] = (va as Color).lerp(vb, t)
		else:
			out[k] = lerpf(float(va), float(vb), t)
	return out


func _update_wind(delta: float) -> void:
	# slowly veering direction, gusts from layered sines (smooth, deterministic)
	var veer := sin(_t * 0.011) * 0.9 + sin(_t * 0.037 + 1.3) * 0.25
	wind_dir = Vector2(cos(0.65 + veer), sin(0.65 + veer))
	var g := (sin(_t * 0.9) * 0.5 + sin(_t * 2.3 + 0.7) * 0.3 + sin(_t * 0.31 + 2.0) * 0.2) * 0.5 + 0.5
	wind_gust = clampf(g * float(params["gust"]) * 1.3, 0.0, 1.0)
	wind_speed = float(params["wind"])
	_wind_time += delta * (0.6 + wind_speed * 0.09) * (1.0 + wind_gust * 0.5)
	WorldShaderGlobals.set_value(&"wind_direction", wind_dir)
	WorldShaderGlobals.set_value(&"wind_strength", wind_speed)
	WorldShaderGlobals.set_value(&"wind_gust", wind_gust)
	WorldShaderGlobals.set_value(&"wind_time", _wind_time)
	WorldShaderGlobals.set_value(&"world_wetness", float(params["wetness"]))
	WorldShaderGlobals.set_value(&"world_snow_cover", float(params["snow_cover"]))


## Wind velocity on the x/z plane (m/s) including the current gust.
func wind_velocity() -> Vector2:
	return wind_dir * wind_speed * (1.0 + wind_gust * 0.6)


## Sky/fog modifiers for SkyController.apply().
func sky_mods() -> Dictionary:
	var m := {}
	for k: String in ["coverage", "cloud_darkness", "sun_mult", "fog_mult", "fog_floor", "sky_fog", "fog_tint_amount", "ambient_mult",
			"saturation_mult", "haze_add", "exposure_mult", "fog_height_density", "volumetric", "cirrus"]:
		m[StringName(k)] = params[k]
	m[&"fog_tint"] = params["fog_tint"]
	return m


## Precipitation intensities for WeatherParticles.
func precipitation() -> Dictionary:
	return {&"snow": params["snow"], &"blizzard": params["blizzard"], &"rain": params["rain"], &"ash": params["ash"]}
