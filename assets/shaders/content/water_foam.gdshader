// Plunge-pool foam under a waterfall: a disc whose foam blotches stream outward from the impact
// point and thin out at the rim. UV = position in the disc (-1..1).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

global uniform vec4 world_sun_color;
global uniform float world_time;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(0.93, 0.97, 1.0, 1.0);
uniform float intensity = 1.0;

void fragment() {
	vec2 p = UV;
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = world_time;
	vec4 n1 = texture(noise_tex, vec2(a * 0.32, r * 0.9 - t * 0.35));
	vec4 n2 = texture(noise_tex, vec2(a * 0.71 + 0.3, r * 1.7 - t * 0.6) * 1.3);
	float blot = smoothstep(0.45, 0.7, n1.r * 0.55 + n2.g * 0.55 + (1.0 - r) * 0.35);
	float rim = 1.0 - smoothstep(0.55, 1.0, r);
	float core = 1.0 - smoothstep(0.0, 0.35, r);
	float day = clamp(dot(world_sun_color.rgb, vec3(0.3, 0.5, 0.2)) * 1.4 + 0.25, 0.25, 1.1);
	ALBEDO = foam_color.rgb * day;
	ALPHA = clamp((blot * rim + core * 0.8) * intensity, 0.0, 0.95);
}
