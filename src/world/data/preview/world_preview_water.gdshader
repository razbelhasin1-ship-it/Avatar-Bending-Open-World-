// Preview water for the baked world: depth-tinted, shore foam, gentle waves.
// Depth comes from the shared heightmap include, so shallows and beaches read correctly.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://src/world/data/world_height.gdshaderinc"

uniform float water_level = 0.0;
uniform vec3 shallow_color : source_color = vec3(0.18, 0.62, 0.64);
uniform vec3 deep_color : source_color = vec3(0.03, 0.17, 0.33);
uniform float depth_scale = 16.0;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// beyond the baked square the sea floor keeps sloping down from the edge texels
	vec2 inside_xz = clamp(world_pos.xz, vec2(WH_ORIGIN), vec2(-WH_ORIGIN));
	float outside = length(world_pos.xz - inside_xz);
	float ground = world_height(inside_xz) - outside * 0.3;
	float depth = water_level - ground;
	if (depth < -0.05) {
		discard;
	}
	float t = 1.0 - exp(-max(depth, 0.0) / depth_scale);
	vec3 col = mix(shallow_color, deep_color, t);
	float foam_n = vnoise(world_pos.xz * 0.35 + TIME * 0.3) * 0.5 + vnoise(world_pos.xz * 0.11 - TIME * 0.1) * 0.5;
	float foam = smoothstep(0.7, 0.0, depth) * smoothstep(0.35, 0.8, foam_n + 0.2);
	col = mix(col, vec3(0.85, 0.92, 0.94), foam * 0.85);
	vec2 w = world_pos.xz;
	float wx = sin(w.x * 0.07 + TIME * 0.9) * 0.5 + sin(w.x * 0.031 + w.y * 0.05 + TIME * 0.6) * 0.5;
	float wz = sin(w.y * 0.06 + TIME * 0.8) * 0.5 + sin(w.y * 0.027 - w.x * 0.04 + TIME * 0.5) * 0.5;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float wave = 0.06 * exp(-dist / 900.0);     // fade ripples with distance (no moire)
	vec3 n = normalize(vec3(wx * wave, 1.0, wz * wave));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.3, clamp(dist / 6000.0, 0.0, 1.0));
	SPECULAR = 0.55;
	ALPHA = t > 0.97 ? 1.0 : clamp(mix(0.55, 0.97, t) + foam * 0.4, 0.0, 1.0);
}
