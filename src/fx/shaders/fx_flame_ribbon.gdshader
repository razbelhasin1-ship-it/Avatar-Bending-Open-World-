// Flame on a ribbon strip (kick arcs, the Flame Sweep wave, fire trails).
// UV.x runs along the strip (0 tail .. 1 head), UV.y across it (0 = base,
// 1 = flame tips). `head` sweeps the visible window along the strip; tongues
// lick upward from the base with crisp toon bands.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.72, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.56, 0.12, 1.0);
uniform vec4 edge_color : source_color = vec4(0.88, 0.17, 0.05, 1.0);
// Visible window: head position (0..1.3) and tail length along UV.x.
uniform float head = 1.0;
uniform float tail = 1.0;
// 0..1 burn-out (shrinks tongues, cools colours).
uniform float fade = 0.0;
uniform float scroll_speed = 2.2;
uniform float tongue_scale = 5.0;
uniform float emission_boost = 1.5;
uniform float opacity = 1.0;
// 1: the strip is symmetric across (UV.y 0..1 both edges thin), 0: base at UV.y = 0.
uniform float symmetric = 0.0;

void fragment() {
	float along = UV.x;
	float across = mix(UV.y, abs(UV.y * 2.0 - 1.0), symmetric);
	float win = smoothstep(head - tail, head - tail * 0.55, along) * (1.0 - smoothstep(head - 0.04, head + 0.01, along));
	float n1 = texture(noise_tex, vec2(along * tongue_scale * 0.35, across * 0.6 - TIME * scroll_speed)).r;
	float n2 = texture(noise_tex, vec2(along * tongue_scale * 0.9 + 0.37, across * 1.2 - TIME * scroll_speed * 1.7)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	// Height profile: full at the base, tongues reach up with noise.
	float h = 1.0 - across;
	float f = h * 0.95 + (n - 0.5) * 0.9 * (0.35 + across);
	f *= win;
	f -= fade * 0.45;
	float aa = max(fwidth(f) * 1.2, 0.01);
	float a_edge = smoothstep(0.14 - aa, 0.14 + aa, f);
	float b_mid = smoothstep(0.34 - aa, 0.34 + aa, f);
	float b_core = smoothstep(0.58 - aa, 0.58 + aa, f);
	vec3 col = mix(edge_color.rgb, mid_color.rgb, b_mid);
	col = mix(col, core_color.rgb, b_core);
	ALBEDO = col * mix(1.0, emission_boost, b_mid);
	ALPHA = clamp(a_edge * opacity * COLOR.a, 0.0, 1.0);
}
