class_name AtmospherePalettes
extends RefCounted
## Art-directed atmosphere palettes per region and time-of-day phase, plus blending helpers.
##
## A palette ("state") is a flat Dictionary of the keys in KEYS (Colors are sRGB, floats are
## linear). `for_region(region, sun_elevation_deg)` blends the region's four phase keyframes
## (night, twilight, golden, day) by sun elevation; `blend(states, weights)` mixes regions.
## Regions: water_tribe (cool, white-blue, low sun), earth_kingdom (green-gold), fire_nation
## (warm red-orange haze), air_temple (crisp high-altitude light), wilds, ocean.

const KEYS := [&"zenith", &"horizon", &"ground", &"sun", &"sun_energy", &"glow", &"glow_strength",
		&"ambient", &"ambient_energy", &"fog", &"fog_density", &"cloud_lit", &"cloud_shade", &"coverage",
		&"haze", &"exposure", &"saturation", &"moon_energy", &"stars", &"fog_height_density", &"aurora"]

## Sun elevation (degrees) at which each phase keyframe applies.
const PHASE_ELEVATION := {&"night": -14.0, &"twilight": -5.0, &"golden": 4.0, &"day": 22.0}
const PHASES := [&"night", &"twilight", &"golden", &"day"]

## Peak noon sun elevation per region (degrees). Low arctic sun gives long golden light.
const SUN_MAX_ELEVATION := {&"water_tribe": 32.0, &"earth_kingdom": 58.0, &"fire_nation": 66.0,
		&"air_temple": 55.0, &"wilds": 50.0, &"ocean": 55.0}

static var _cache: Dictionary = {}


static func _phase(base: Dictionary, over: Dictionary) -> Dictionary:
	var d := base.duplicate()
	for k in over:
		d[k] = over[k]
	return d


static func _base() -> Dictionary:
	return {
		&"zenith": Color(0.23, 0.44, 0.77), &"horizon": Color(0.73, 0.83, 0.91), &"ground": Color(0.32, 0.38, 0.44),
		&"sun": Color(1.0, 0.95, 0.86), &"sun_energy": 1.45, &"glow": Color(1.0, 0.86, 0.62), &"glow_strength": 0.35,
		&"ambient": Color(0.62, 0.70, 0.84), &"ambient_energy": 0.45, &"fog": Color(0.74, 0.82, 0.90),
		&"fog_density": 0.00014, &"cloud_lit": Color(1.0, 0.99, 0.96), &"cloud_shade": Color(0.62, 0.68, 0.80),
		&"coverage": 0.38, &"haze": 0.35, &"exposure": 1.0, &"saturation": 1.05, &"moon_energy": 0.0,
		&"stars": 0.0, &"fog_height_density": 0.0, &"aurora": 0.0,
	}


static func _night_base(day: Dictionary) -> Dictionary:
	return _phase(day, {
		&"zenith": Color(0.020, 0.035, 0.10), &"horizon": Color(0.07, 0.12, 0.24), &"ground": Color(0.03, 0.05, 0.09),
		&"sun_energy": 0.0, &"glow_strength": 0.0, &"ambient": Color(0.22, 0.30, 0.52), &"ambient_energy": 0.32,
		&"fog": Color(0.06, 0.09, 0.17), &"cloud_lit": Color(0.28, 0.34, 0.48), &"cloud_shade": Color(0.07, 0.09, 0.16),
		&"haze": 0.2, &"exposure": 1.25, &"saturation": 0.95, &"moon_energy": 0.32, &"stars": 1.0,
	})


## Raw keyframes of a region: {night, twilight, golden, day}.
static func region_keyframes(region: StringName) -> Dictionary:
	if _cache.has(region):
		return _cache[region]
	var day := _base()
	var golden: Dictionary
	var twilight: Dictionary
	var night: Dictionary
	match region:
		&"water_tribe":
			day = _phase(day, {&"zenith": Color(0.26, 0.50, 0.84), &"horizon": Color(0.80, 0.88, 0.96),
					&"ground": Color(0.55, 0.63, 0.72), &"sun": Color(1.0, 0.95, 0.88), &"sun_energy": 1.35,
					&"ambient": Color(0.62, 0.74, 0.94), &"ambient_energy": 0.5, &"fog": Color(0.80, 0.87, 0.95),
					&"fog_density": 0.00017, &"cloud_shade": Color(0.66, 0.74, 0.88), &"coverage": 0.42, &"saturation": 1.0})
			golden = _phase(day, {&"zenith": Color(0.32, 0.45, 0.72), &"horizon": Color(1.0, 0.80, 0.70),
					&"sun": Color(1.0, 0.82, 0.64), &"sun_energy": 1.05, &"glow": Color(1.0, 0.70, 0.55), &"glow_strength": 0.75,
					&"ambient": Color(0.70, 0.70, 0.84), &"fog": Color(0.94, 0.82, 0.80), &"cloud_lit": Color(1.0, 0.82, 0.72),
					&"cloud_shade": Color(0.56, 0.52, 0.70), &"exposure": 1.05})
			twilight = _phase(golden, {&"zenith": Color(0.10, 0.16, 0.36), &"horizon": Color(0.62, 0.50, 0.62),
					&"sun_energy": 0.0, &"glow": Color(0.95, 0.55, 0.50), &"glow_strength": 0.6, &"ambient": Color(0.40, 0.45, 0.66),
					&"ambient_energy": 0.42, &"fog": Color(0.42, 0.42, 0.56), &"cloud_lit": Color(0.80, 0.56, 0.62),
					&"cloud_shade": Color(0.25, 0.26, 0.42), &"exposure": 1.15, &"moon_energy": 0.12, &"stars": 0.3, &"aurora": 0.2})
			night = _phase(_night_base(day), {&"horizon": Color(0.08, 0.15, 0.30), &"ambient": Color(0.25, 0.35, 0.60),
					&"ambient_energy": 0.4, &"moon_energy": 0.4, &"fog": Color(0.07, 0.11, 0.21), &"aurora": 1.0})
		&"fire_nation":
			day = _phase(day, {&"zenith": Color(0.30, 0.47, 0.74), &"horizon": Color(0.95, 0.82, 0.64),
					&"ground": Color(0.40, 0.32, 0.28), &"sun": Color(1.0, 0.91, 0.76), &"sun_energy": 1.35,
					&"glow": Color(1.0, 0.75, 0.45), &"glow_strength": 0.45, &"ambient": Color(0.76, 0.66, 0.60),
					&"ambient_energy": 0.45, &"fog": Color(0.86, 0.75, 0.62), &"fog_density": 0.00016,
					&"cloud_lit": Color(1.0, 0.93, 0.84), &"cloud_shade": Color(0.66, 0.54, 0.52), &"coverage": 0.3,
					&"haze": 0.45, &"saturation": 1.1, &"fog_height_density": 0.0})
			golden = _phase(day, {&"zenith": Color(0.34, 0.36, 0.58), &"horizon": Color(1.0, 0.56, 0.28),
					&"sun": Color(1.0, 0.58, 0.30), &"sun_energy": 1.1, &"glow": Color(1.0, 0.45, 0.18), &"glow_strength": 0.9,
					&"ambient": Color(0.74, 0.52, 0.48), &"fog": Color(0.96, 0.56, 0.32), &"cloud_lit": Color(1.0, 0.62, 0.36),
					&"cloud_shade": Color(0.52, 0.34, 0.40), &"exposure": 1.05, &"saturation": 1.08})
			twilight = _phase(golden, {&"zenith": Color(0.12, 0.10, 0.26), &"horizon": Color(0.66, 0.30, 0.22),
					&"sun_energy": 0.0, &"glow": Color(0.95, 0.35, 0.18), &"glow_strength": 0.7, &"ambient": Color(0.46, 0.34, 0.42),
					&"ambient_energy": 0.4, &"fog": Color(0.42, 0.22, 0.20), &"cloud_lit": Color(0.78, 0.38, 0.30),
					&"cloud_shade": Color(0.22, 0.14, 0.22), &"exposure": 1.15, &"moon_energy": 0.1, &"stars": 0.25})
			night = _phase(_night_base(day), {&"zenith": Color(0.04, 0.025, 0.07), &"horizon": Color(0.20, 0.08, 0.07),
					&"ambient": Color(0.36, 0.25, 0.36), &"fog": Color(0.17, 0.07, 0.06), &"fog_density": 0.00024,
					&"cloud_lit": Color(0.40, 0.20, 0.18), &"cloud_shade": Color(0.10, 0.05, 0.08)})
		&"air_temple":
			day = _phase(day, {&"zenith": Color(0.11, 0.33, 0.80), &"horizon": Color(0.70, 0.84, 0.97),
					&"ground": Color(0.70, 0.78, 0.88), &"sun": Color(1.0, 0.98, 0.94), &"sun_energy": 1.4,
					&"ambient": Color(0.62, 0.73, 0.92), &"ambient_energy": 0.47, &"fog": Color(0.76, 0.86, 0.97),
					&"fog_density": 0.00008, &"cloud_shade": Color(0.66, 0.73, 0.86), &"coverage": 0.3, &"haze": 0.25,
					&"saturation": 1.08})
			golden = _phase(day, {&"zenith": Color(0.22, 0.34, 0.68), &"horizon": Color(1.0, 0.78, 0.55),
					&"sun": Color(1.0, 0.78, 0.52), &"sun_energy": 1.15, &"glow": Color(1.0, 0.62, 0.36), &"glow_strength": 0.8,
					&"ambient": Color(0.72, 0.66, 0.74), &"fog": Color(0.96, 0.78, 0.62), &"cloud_lit": Color(1.0, 0.80, 0.60),
					&"cloud_shade": Color(0.56, 0.48, 0.62), &"exposure": 1.05})
			twilight = _phase(golden, {&"zenith": Color(0.08, 0.13, 0.36), &"horizon": Color(0.70, 0.50, 0.55),
					&"sun_energy": 0.0, &"glow": Color(0.96, 0.52, 0.40), &"glow_strength": 0.65, &"ambient": Color(0.40, 0.42, 0.62),
					&"ambient_energy": 0.42, &"fog": Color(0.44, 0.40, 0.54), &"cloud_lit": Color(0.86, 0.56, 0.56),
					&"cloud_shade": Color(0.25, 0.25, 0.42), &"exposure": 1.15, &"moon_energy": 0.12, &"stars": 0.35})
			night = _phase(_night_base(day), {&"zenith": Color(0.015, 0.03, 0.10), &"stars": 1.2})
		_:
			# earth_kingdom, wilds and ocean share the green-gold continental light
			if region == &"ocean":
				day = _phase(day, {&"horizon": Color(0.72, 0.84, 0.93), &"fog": Color(0.72, 0.82, 0.92), &"coverage": 0.42})
			else:
				day = _phase(day, {&"horizon": Color(0.76, 0.85, 0.90), &"fog": Color(0.76, 0.83, 0.88),
						&"ambient": Color(0.64, 0.71, 0.80), &"saturation": 1.08})
			golden = _phase(day, {&"zenith": Color(0.30, 0.42, 0.68), &"horizon": Color(1.0, 0.74, 0.46),
					&"sun": Color(1.0, 0.72, 0.44), &"sun_energy": 1.1, &"glow": Color(1.0, 0.58, 0.28), &"glow_strength": 0.85,
					&"ambient": Color(0.72, 0.62, 0.62), &"ambient_energy": 0.5, &"fog": Color(0.93, 0.74, 0.56),
					&"cloud_lit": Color(1.0, 0.76, 0.52), &"cloud_shade": Color(0.55, 0.46, 0.58), &"exposure": 1.05,
					&"saturation": 1.12})
			twilight = _phase(golden, {&"zenith": Color(0.11, 0.15, 0.34), &"horizon": Color(0.64, 0.42, 0.46),
					&"sun_energy": 0.0, &"glow": Color(0.95, 0.46, 0.30), &"glow_strength": 0.7, &"ambient": Color(0.40, 0.40, 0.58),
					&"ambient_energy": 0.38, &"fog": Color(0.40, 0.36, 0.48), &"cloud_lit": Color(0.80, 0.48, 0.46),
					&"cloud_shade": Color(0.24, 0.22, 0.36), &"exposure": 1.15, &"moon_energy": 0.1, &"stars": 0.3})
			night = _night_base(day)
	var out := {&"night": night, &"twilight": twilight, &"golden": golden, &"day": day}
	_cache[region] = out
	return out


## Region palette at a sun elevation (degrees): piecewise-linear between phase keyframes.
static func for_region(region: StringName, sun_elevation: float) -> Dictionary:
	var kf := region_keyframes(region)
	if sun_elevation <= PHASE_ELEVATION[&"night"]:
		return kf[&"night"]
	if sun_elevation >= PHASE_ELEVATION[&"day"]:
		return kf[&"day"]
	for i in PHASES.size() - 1:
		var a: StringName = PHASES[i]
		var b: StringName = PHASES[i + 1]
		var ea: float = PHASE_ELEVATION[a]
		var eb: float = PHASE_ELEVATION[b]
		if sun_elevation <= eb:
			var t := smoothstep(0.0, 1.0, (sun_elevation - ea) / (eb - ea))
			return lerp_state(kf[a], kf[b], t)
	return kf[&"day"]


## Linear mix of two states (all KEYS).
static func lerp_state(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in KEYS:
		var va: Variant = a[k]
		var vb: Variant = b[k]
		if va is Color:
			out[k] = (va as Color).lerp(vb, t)
		else:
			out[k] = lerpf(va, vb, t)
	return out


## Weighted mix of several states (weights need not be normalised).
static func blend(states: Array, weights: PackedFloat32Array) -> Dictionary:
	var total := 0.0
	for w in weights:
		total += w
	if states.is_empty() or total <= 0.0:
		return _base()
	var out := {}
	for k in KEYS:
		var first: Variant = states[0][k]
		if first is Color:
			var c := Color(0, 0, 0, 0)
			for i in states.size():
				c += (states[i][k] as Color) * (weights[i] / total)
			out[k] = c
		else:
			var f := 0.0
			for i in states.size():
				f += float(states[i][k]) * (weights[i] / total)
			out[k] = f
	return out


## Region-weighted peak sun elevation (degrees).
static func sun_max_elevation(region_weights: Dictionary) -> float:
	var total := 0.0
	var acc := 0.0
	for r: StringName in region_weights:
		var w: float = region_weights[r]
		acc += float(SUN_MAX_ELEVATION.get(r, 55.0)) * w
		total += w
	return acc / total if total > 0.0 else 55.0
