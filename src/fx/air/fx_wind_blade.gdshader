// Wind Blade: a crescent of compressed air with a hard white cutting edge, a pale
// translucent body behind it, fast streaks racing along the arc and tips that taper
// out. UV.x along the crescent (0 tip .. 1 tip), UV.y across (0 inner .. 1 leading edge).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 body_color : source_color = vec4(0.72, 0.88, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.42, 0.62, 0.86, 1.0);
uniform float opacity = 1.0;
uniform float progress = 0.0;
uniform float scroll = 6.0;

void fragment() {
	float tip = pow(sin(clamp(UV.x, 0.0, 1.0) * 3.14159), 0.7);
	float y = UV.y;
	// Cutting edge: a crisp bright line just behind the leading edge.
	float edge = smoothstep(0.62, 0.8, y) * (1.0 - smoothstep(0.86, 0.98, y));
	float body = smoothstep(0.0, 0.7, y) * (1.0 - smoothstep(0.92, 1.0, y));
	float n = texture(noise_tex, vec2(UV.x * 3.0 - TIME * scroll * 0.3, y * 0.7)).r;
	float streak = smoothstep(0.55, 0.9, sin((UV.x * 18.0 + y * 2.0) * 6.2831 - TIME * scroll * 5.0 + n * 4.0));
	vec3 col = mix(edge_color.rgb, body_color.rgb, body);
	col = mix(col, core_color.rgb, clamp(edge * 1.3 + streak * 0.35 * body, 0.0, 1.0));
	float keep = clamp((n * 0.6 + 0.6 - progress * 1.3) * 4.0, 0.0, 1.0);
	float a = (body * (0.32 + 0.25 * n) + edge * 0.95 + streak * body * 0.25) * tip * keep;
	float d = length(VERTEX);
	a *= smoothstep(0.3, 0.9, d);
	ALBEDO = col;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
