// Airbending currents: pale streaks on ribbon strips (gusts, swirls, shields,
// dash trails). UV.x along the ribbon (0 tail .. 1 head), UV.y across. `head`
// moves the visible window so a static mesh reads as a travelling current.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(0.97, 0.99, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.56, 0.74, 0.88, 1.0);
uniform float head = 1.0;
uniform float tail = 0.7;
uniform float opacity = 0.85;
uniform float flow = 2.4;
uniform float streaks = 9.0;
// Loop mode (shields, swirls): ignore the window, stream continuously.
uniform float looping = 0.0;

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float win = smoothstep(head - tail, head - tail * 0.35, along) * (1.0 - smoothstep(head - 0.05, head, along));
	win = mix(win, 1.0, looping);
	float n = texture(noise_tex, vec2(along * 1.7 - TIME * flow * 0.35, UV.y * 0.45)).r;
	float s = sin(along * streaks * 6.2831 - TIME * flow * 5.0 + n * 4.0);
	float streak = smoothstep(-0.2, 0.9, s) * 0.55 + smoothstep(0.35, 0.75, n) * 0.45;
	float body = 1.0 - smoothstep(0.25, 1.0, across);
	// Darker hairline near the edges keeps the current readable on bright snow/sky.
	float line = (1.0 - smoothstep(0.0, 0.12, abs(across - 0.62))) * 0.6;
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(body * 1.3 - line, 0.0, 1.0));
	ALBEDO = col;
	float a = (body * (0.3 + 0.7 * streak) + line * 0.5) * win;
	ALPHA = clamp(a * opacity * COLOR.a, 0.0, 1.0);
}
