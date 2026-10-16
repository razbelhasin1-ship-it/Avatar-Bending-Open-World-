// Falling water sheet of a waterfall (WaterfallBuilder). UV.x across the sheet (0..1), UV.y metres
// fallen from the lip. Streaks scroll down (accelerating), whiten into foam towards the bottom and
// at the lip, edges fade out. Colour picks up the current sky (world globals) so it sits in the
// toon scene at any hour. Cheap: two noise fetches, no refraction.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

global uniform vec4 world_sky_horizon;
global uniform vec4 world_sun_color;
global uniform float world_time;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.30, 0.55, 0.68, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float speed = 7.0;
uniform float fall_height = 60.0;
uniform float opacity = 0.9;
uniform float streak_scale = 1.0;

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float t = world_time;
	// accelerating flow: texture coordinate grows with sqrt-like fall
	float v = y / (6.0 * streak_scale) - t * speed / (6.0 * streak_scale) * (0.6 + 0.4 * clamp(y / 20.0, 0.0, 1.0));
	vec4 n1 = texture(noise_tex, vec2(x * 2.3 * streak_scale, v * 0.35));
	vec4 n2 = texture(noise_tex, vec2(x * 5.1 * streak_scale + 0.37, v * 0.9 + 0.21));
	float streak = smoothstep(0.42, 0.75, n1.r * 0.6 + n2.g * 0.5);
	float foam_bottom = smoothstep(fall_height * 0.75, fall_height, y);
	float foam_lip = 1.0 - smoothstep(0.0, 3.0, y);
	float foam = clamp(streak * 0.8 + foam_bottom * 0.9 + foam_lip * 0.6, 0.0, 1.0);
	float day = clamp(dot(world_sun_color.rgb, vec3(0.3, 0.5, 0.2)) * 1.4 + 0.25, 0.25, 1.1);
	vec3 base = mix(deep_color.rgb, world_sky_horizon.rgb * 0.8 + deep_color.rgb * 0.4, 0.35);
	vec3 col = mix(base, foam_color.rgb, foam) * day;
	float edge = smoothstep(0.0, 0.12, x) * smoothstep(1.0, 0.88, x);
	float ragged = smoothstep(0.0, 0.25, n2.b + edge * 0.8 - 0.3);
	ALBEDO = col;
	ALPHA = clamp(opacity * edge * ragged * (0.7 + 0.3 * foam), 0.0, 1.0);
}
