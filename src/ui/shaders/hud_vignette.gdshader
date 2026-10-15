// Low-health / damage vignette: red ink bleeding in from the screen edges with a
// heartbeat pulse. Never covers the centre (falloff starts well outside it).
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ink : source_color = vec4(0.45, 0.02, 0.02, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	q.x *= 1.15;
	float r = length(q);
	float n = texture(noise_tex, UV * 1.7 + vec2(TIME * 0.01, 0.0)).r;
	float beat = 0.75 + 0.25 * pow(abs(sin(TIME * 2.6)), 6.0);
	float edge = smoothstep(0.62, 1.35, r + (n - 0.5) * 0.35);
	float a = edge * (intensity * beat + hit_flash * 0.8);
	COLOR = vec4(ink.rgb, clamp(a, 0.0, 0.92));
}
