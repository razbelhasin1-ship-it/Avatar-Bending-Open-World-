// Standing walls of flame (Fire Ring, Fire Burst flash, the Inferno's ring and vortex
// base). The banded look of fx_flame_ribbon (white-gold core, orange body, red tips)
// with two differences that keep big walls readable: a thinner hot core at the base,
// and a fade when the wall passes close to the camera (a ring racing under the camera
// never floods the screen). UV.x runs along the wall, UV.y up it (0 = base).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 edge_color : source_color = vec4(0.88, 0.17, 0.05, 1.0);
uniform float fade = 0.0;
uniform float scroll_speed = 2.2;
uniform float tongue_scale = 14.2857;
uniform float emission_boost = 1.15;
uniform float opacity = 1.0;
// Core band threshold (higher = thinner white-hot base).
uniform float core_at = 0.7;
// Camera proximity fade: fully faded at near_end, untouched beyond near_start (m).
uniform float near_start = 4.0;
uniform float near_end = 1.6;

varying float v_depth;

void vertex() {
	v_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float along = UV.x;
	float across = UV.y;
	float n1 = texture(noise_tex, vec2(along * tongue_scale * 0.7, across * 0.32 - TIME * scroll_speed)).r;
	float n2 = texture(noise_tex, vec2(along * tongue_scale * 1.4 + 0.37, across * 0.7 - TIME * scroll_speed * 1.7)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float h = 1.0 - across;
	float f = h * 0.95 + (n - 0.5) * 0.9 * (0.35 + across);
	f -= fade * 0.45;
	float aa = max(fwidth(f) * 1.2, 0.01);
	float a_edge = smoothstep(0.14 - aa, 0.14 + aa, f);
	float b_mid = smoothstep(0.36 - aa, 0.36 + aa, f);
	float b_core = smoothstep(core_at - aa, core_at + aa, f);
	vec3 col = mix(edge_color.rgb, mid_color.rgb, b_mid);
	col = mix(col, core_color.rgb, b_core);
	float near = smoothstep(near_end, near_start, v_depth);
	ALBEDO = col * mix(1.0, emission_boost, b_mid);
	ALPHA = clamp(a_edge * opacity * near * COLOR.a, 0.0, 1.0);
}
