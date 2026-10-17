// The Inferno's spiral flame ribbons (FireVortexFx). The banded flame-ribbon look
// (white-gold core, orange body, red tips; both edges of the strip burn) plus the
// camera proximity fade of fx_flame_wall: the column widens around the bender, so the
// player's camera is often a metre from a ribbon - it thins out there instead of
// filling the screen. UV.x runs along the strip, UV.y across it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 edge_color : source_color = vec4(0.88, 0.17, 0.05, 1.0);
uniform float fade = 0.0;
uniform float scroll_speed = 3.2;
uniform float tongue_scale = 4.0;
uniform float emission_boost = 1.15;
uniform float opacity = 1.0;
// Tail of the strip (UV.x below this) thins out: the spiral rises out of the base ring.
uniform float tail = 0.18;
uniform float near_start = 6.0;
uniform float near_end = 2.4;

varying float v_depth;

void vertex() {
	v_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float n1 = texture(noise_tex, vec2(along * tongue_scale * 0.7, across * 0.32 - TIME * scroll_speed)).r;
	float n2 = texture(noise_tex, vec2(along * tongue_scale * 1.7 + 0.37, across * 0.7 - TIME * scroll_speed * 1.7)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float h = 1.0 - across;
	float f = h * 0.95 + (n - 0.5) * 0.9 * (0.35 + across);
	f *= smoothstep(0.0, tail, along) * (1.0 - smoothstep(0.9, 1.0, along) * 0.6);
	f -= fade * 0.45;
	float aa = max(fwidth(f) * 1.2, 0.01);
	float a_edge = smoothstep(0.14 - aa, 0.14 + aa, f);
	float b_mid = smoothstep(0.34 - aa, 0.34 + aa, f);
	float b_core = smoothstep(0.66 - aa, 0.66 + aa, f);
	vec3 col = mix(edge_color.rgb, mid_color.rgb, b_mid);
	col = mix(col, core_color.rgb, b_core);
	float near = smoothstep(near_end, near_start, v_depth);
	ALBEDO = col * mix(1.0, emission_boost, b_mid);
	ALPHA = clamp(a_edge * opacity * near * COLOR.a, 0.0, 1.0);
}
