// Banners, flags, awnings and tent cloth from the building kit: two-sided toon cloth that ripples
// in the world wind (globals from WorldShaderGlobals). UV.x = distance from the fixed edge
// (0 pinned .. 1 free), UV.y = across the cloth. Vertex colour = cloth colour (emblem stripes
// are baked in colours).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wind_gust;
global uniform float wind_time;
global uniform float world_wetness;
// Airbending gusts (bending_air): air_impulse_at(p).
#include "res://src/fx/air/air_wind.gdshaderinc"

uniform float amplitude = 0.16;
uniform float stiffness = 1.0;
uniform vec4 shade_tint : source_color = vec4(0.55, 0.55, 0.75, 1.0);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float free = clamp(UV.x, 0.0, 1.0);
	float ws = wind_strength * (1.0 + wind_gust * 0.9);
	float wave = sin(wind_time * 3.2 - UV.x * 5.0 + dot(wp.xz, vec2(0.37, 0.21)))
			+ 0.5 * sin(wind_time * 5.1 - UV.x * 9.0 + UV.y * 3.0 + wp.y);
	// ripple along the local normal, plus a drift with the wind (in local space)
	vec3 wind_local = (inverse(MODEL_MATRIX) * vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xyz;
	float a = amplitude * free * (0.4 + ws * 0.09) / stiffness;
	VERTEX += NORMAL * wave * a;
	VERTEX += wind_local * free * free * ws * 0.025 / stiffness;
	// Airbending gusts snap the cloth out and make it flap harder.
	vec3 air = air_impulse_at(wp);
	float airs = length(air);
	if (airs > 0.01) {
		vec3 air_local = (inverse(MODEL_MATRIX) * vec4(air, 0.0)).xyz;
		VERTEX += air_local * free * free * 0.028 / stiffness;
		VERTEX += NORMAL * wave * a * clamp(airs * 0.06, 0.0, 1.6);
	}
}

void fragment() {
	vec3 c = COLOR.rgb * (1.0 - world_wetness * 0.2);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.05;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.12, 0.12, ndl + 0.05) * smoothstep(0.0, 0.3, ATTENUATION);
	float fill = LIGHT_IS_DIRECTIONAL ? 1.0 : clamp(ATTENUATION * 4.0, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(shade_tint.rgb * 0.45 * fill, vec3(1.0), lit);
	// light shining through thin cloth
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.0) * 0.35;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * back * smoothstep(0.0, 0.3, ATTENUATION);
}
