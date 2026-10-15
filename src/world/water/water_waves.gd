class_name WaterWaves
extends RefCounted
## CPU mirror of the Gerstner swell in assets/shaders/world/water_common.gdshaderinc, so
## gameplay (buoyancy, boats, bending pulls) can ask for the visible ocean surface height.

const LENGTHS := [42.0, 23.0, 13.0, 7.5]
const AMPS := [0.42, 0.24, 0.12, 0.06]
const ANGLES := [0.0, 0.55, -0.42, 1.1]

## x amplitude scale (m), y choppiness, z wavelength scale, w speed scale (= shader wave_params).
var params := Vector4(0.6, 0.7, 1.0, 1.0)
var wind_direction := Vector2(0.8, 0.6)


## Vertical Gerstner offset (m) at x/z at time `t` (world_time seconds), before distance/shallow
## fading. Ignores the small horizontal drift of the surface (error < 5 % of the amplitude).
func height_at(x: float, z: float, t: float, amp_mask: float = 1.0) -> float:
	var w := wind_direction.normalized() if wind_direction.length() > 0.0001 else Vector2(1, 0)
	var h := 0.0
	for i in LENGTHS.size():
		var length: float = LENGTHS[i] * params.z
		var k := TAU / length
		var c := sqrt(9.8 / k) * params.w
		var a: float = ANGLES[i]
		var dir := Vector2(w.x * cos(a) - w.y * sin(a), w.x * sin(a) + w.y * cos(a))
		var amp: float = AMPS[i] * params.x * amp_mask
		h += amp * sin(k * (dir.dot(Vector2(x, z)) - c * t))
	return h


## Largest possible crest height (m) for the current params.
func max_amplitude() -> float:
	var s := 0.0
	for a: float in AMPS:
		s += a
	return s * params.x
