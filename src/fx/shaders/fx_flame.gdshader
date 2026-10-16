// Stylized "animated series" flame: crisp bands (white-gold core, orange body,
// red tips) shaped as a licking teardrop and animated by scrolling noise.
// Used on camera-facing quads (particles: age from INSTANCE_CUSTOM.y shrinks and
// cools them) and on static billboards (fireball cores, hand flames).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 edge_color : source_color = vec4(0.88, 0.17, 0.05, 1.0);
// 1 = camera-facing quad (particles / sprites).
uniform float billboard = 1.0;
// Overall heat: grows core and size (charge, explosions).
uniform float intensity = 1.0;
uniform float scroll_speed = 1.7;
// HDR boost so Environment glow blooms the core.
uniform float emission_boost = 1.15;
// 0 = round puff, 1 = tall licking tongue.
uniform float tongue = 0.6;
uniform float opacity = 1.0;
// Static sprites: seed per material instance (particles use INSTANCE_ID).
uniform float seed = 0.0;
// Static sprites: 0..1 "age" set from script (fade-out).
uniform float age = 0.0;

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = max(INSTANCE_CUSTOM.y, age);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + seed);
	if (billboard > 0.5) {
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// t: 0 at the bottom of the quad, 1 at the top.
	float t = clamp(1.0 - UV.y, 0.0, 1.0);
	float heat = intensity * (1.0 - v_age * 0.8);
	float width = mix(1.0, 1.0 - 0.55 * t, tongue);
	vec2 q = vec2(uv.x / max(width, 0.2), (uv.y + 0.18 * tongue) * mix(1.0, 0.82, tongue));
	float d = length(q);
	float n1 = texture(noise_tex, vec2(UV.x * 0.8 + v_seed * 3.1, UV.y * 0.7 + TIME * scroll_speed + v_seed * 7.0)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 1.9 - v_seed * 2.3, UV.y * 1.6 + TIME * scroll_speed * 1.9 + v_seed)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float f = 1.0 - d + (n - 0.5) * (0.55 + 0.6 * t * tongue);
	f *= 0.7 + 0.3 * clamp(heat, 0.0, 1.5);
	f -= v_age * 0.35;
	float aa = max(fwidth(f) * 1.2, 0.01);
	float a_edge = smoothstep(0.16 - aa, 0.16 + aa, f);
	float b_mid = smoothstep(0.36 - aa, 0.36 + aa, f);
	float b_core = smoothstep(0.58 - aa, 0.58 + aa, f + 0.08 * (heat - 1.0));
	vec3 col = mix(edge_color.rgb, mid_color.rgb, b_mid);
	col = mix(col, core_color.rgb, b_core);
	ALBEDO = col * mix(1.0, emission_boost, b_mid);
	ALPHA = clamp(a_edge * opacity * COLOR.a, 0.0, 1.0);
}
