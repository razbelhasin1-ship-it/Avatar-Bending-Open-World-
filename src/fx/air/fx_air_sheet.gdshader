// Airbending wind sheets: shockwave bands, the tornado funnel, the scooter ball, the
// vortex ward and wind blades. Pale translucent body with crisp white streak lines that
// race around / up the surface, noise-eroded dissolve over `progress`, vertical fades,
// an optional view-angle rim for closed shapes and a near-camera fade (a funnel around
// the camera thins out instead of filling the screen).
// UV.x runs around / along the sheet, UV.y up / across it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(0.97, 0.99, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.6, 0.76, 0.9, 1.0);
uniform float opacity = 0.8;
// 0 fresh .. 1 gone (noise erosion).
uniform float progress = 0.0;
// Streak lines around UV.x, slanted by UV.y (spiral lines on funnels).
uniform float streaks = 7.0;
uniform float twist = 0.8;
uniform float scroll = 1.5;
// Body opacity between the lines.
uniform float body = 0.24;
uniform float line_sharp = 0.55;
uniform float fade_bottom = 0.12;
uniform float fade_top = 0.3;
uniform float rim = 0.0;
uniform float near_fade = 1.5;

void fragment() {
	vec2 uv = UV;
	float n = texture(noise_tex, vec2(uv.x * 1.7 + TIME * scroll * 0.11, uv.y * 0.9 - TIME * 0.17)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 3.1 - TIME * scroll * 0.07, uv.y * 1.6 + 0.37)).r;
	float s = sin((uv.x * streaks + uv.y * twist) * 6.2831 - TIME * scroll * 4.0 + n * 3.5);
	float line = smoothstep(line_sharp, 0.97, s) * smoothstep(0.25, 0.6, n2);
	float vfade = smoothstep(0.0, max(fade_bottom, 0.001), uv.y) * (1.0 - smoothstep(1.0 - max(fade_top, 0.001), 1.0, uv.y));
	float keep = clamp((n * 0.8 + 0.2 + 0.35 - progress * 1.4) * 4.0, 0.0, 1.0);
	float fres = 0.0;
	if (rim > 0.0) {
		fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2) * rim;
	}
	float wisps = smoothstep(0.45, 0.8, n) * 0.35;
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(line * 1.2 + fres * 0.5 + wisps, 0.0, 1.0));
	float a = (body * (0.55 + wisps) + line * 0.85 + fres) * vfade * keep;
	float d = length(VERTEX);
	a *= smoothstep(near_fade * 0.35, near_fade, d);
	ALBEDO = col;
	ALPHA = clamp(a * opacity * COLOR.a, 0.0, 1.0);
}
