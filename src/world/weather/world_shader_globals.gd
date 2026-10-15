class_name WorldShaderGlobals
extends RefCounted
## Global shader uniforms owned by the world renderer (registered at runtime, never in
## project.godot). Any shader may declare them with `global uniform <type> <name>;` once
## `WorldShaderGlobals.ensure()` has run (WorldRenderer calls it in _init; vegetation, cloth,
## particle or water materials created before a WorldRenderer exists must call it first,
## otherwise the shader fails to compile with "global uniform does not exist").
##
## | name                 | type  | meaning                                                         |
## | wind_direction       | vec2  | normalised x/z direction the wind blows towards                 |
## | wind_strength        | float | mean wind speed in m/s (calm 1, breezy 5, blizzard 18)          |
## | wind_gust            | float | 0..1 current gust intensity (multiply sway amplitude by 1 + gust) |
## | wind_time            | float | monotonically increasing sway phase (speeds up with wind); use  |
## |                      |       | sin(wind_time * f + dot(world_xz, k)) instead of TIME           |
## | world_wetness        | float | 0..1 rain wetness (darken/gloss surfaces)                       |
## | world_snow_cover     | float | 0..1 fresh snow accumulation during snowfall (whiten up-faces)  |
## | world_sun_direction  | vec3  | unit vector towards the sun (below horizon at night)            |
## | world_sun_color      | vec4  | linear sun colour * intensity (0 at night)                      |
## | world_moon_direction | vec3  | unit vector towards the moon                                    |
## | world_sky_zenith     | vec4  | current sky colour overhead (linear)                            |
## | world_sky_horizon    | vec4  | current sky colour at the horizon (linear, = fog colour family) |
## | world_fog_color      | vec4  | current distance-fog colour (linear)                            |
## | world_time_of_day    | float | hours 0..24                                                     |
## | world_time           | float | seconds of unpaused world time (cloud/water animation clock)    |

const VEC2 := RenderingServer.GLOBAL_VAR_TYPE_VEC2
const VEC3 := RenderingServer.GLOBAL_VAR_TYPE_VEC3
const FLOAT := RenderingServer.GLOBAL_VAR_TYPE_FLOAT
const COLOR := RenderingServer.GLOBAL_VAR_TYPE_COLOR

const DEFAULTS := {
	&"wind_direction": [VEC2, Vector2(0.8, 0.6)],
	&"wind_strength": [FLOAT, 3.0],
	&"wind_gust": [FLOAT, 0.0],
	&"wind_time": [FLOAT, 0.0],
	&"world_wetness": [FLOAT, 0.0],
	&"world_snow_cover": [FLOAT, 0.0],
	&"world_sun_direction": [VEC3, Vector3(0.3, 0.8, 0.5)],
	&"world_sun_color": [COLOR, Color(1.0, 0.95, 0.88)],
	&"world_moon_direction": [VEC3, Vector3(-0.3, -0.8, -0.5)],
	&"world_sky_zenith": [COLOR, Color(0.2, 0.4, 0.8)],
	&"world_sky_horizon": [COLOR, Color(0.65, 0.75, 0.88)],
	&"world_fog_color": [COLOR, Color(0.65, 0.75, 0.88)],
	&"world_time_of_day": [FLOAT, 9.0],
	&"world_time": [FLOAT, 0.0],
}


static var _registered := false
static var _values: Dictionary = {}


## Registers every global uniform once per run. Cheap; call as often as needed.
static func ensure() -> void:
	if _registered:
		return
	_registered = true
	for uname: StringName in DEFAULTS:
		var spec: Array = DEFAULTS[uname]
		RenderingServer.global_shader_parameter_add(uname, spec[0], spec[1])
		_values[uname] = spec[1]


static func set_value(uname: StringName, value: Variant) -> void:
	_values[uname] = value
	RenderingServer.global_shader_parameter_set(uname, value)


## Last value set through this helper (the RenderingServer getter is editor-only).
static func get_value(uname: StringName) -> Variant:
	return _values.get(uname)
