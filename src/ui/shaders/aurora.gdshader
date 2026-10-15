// Painted aurora curtains for the Water Tribe backdrop (2D): folded green-to-violet
// ribbons with vertical rays, drifting slowly. Additive over the night sky.
shader_type canvas_item;
render_mode blend_add;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float intensity = 0.8;
uniform vec4 low_color : source_color = vec4(0.2, 0.95, 0.6, 1.0);
uniform vec4 high_color : source_color = vec4(0.55, 0.35, 0.95, 1.0);

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.02;
	float fold = sin(uv.x * 7.0 + t * 6.0) * 0.06 + (texture(noise_tex, vec2(uv.x * 0.6 + t, 0.3)).r - 0.5) * 0.25;
	float band_y = 0.55 + fold;
	float h = band_y - uv.y;
	float hem = smoothstep(-0.03, 0.02, h);
	float curtain = hem * exp(-max(h, 0.0) / 0.22);
	float rays = texture(noise_tex, vec2(uv.x * 4.0 + t * 2.0, 0.6)).b * 0.7 + 0.3;
	float second = exp(-abs(uv.y - (0.32 + fold * 0.6)) / 0.06) * 0.35 * rays;
	vec3 col = mix(low_color.rgb, high_color.rgb, smoothstep(0.0, 0.35, h));
	float a = (curtain * rays + second) * intensity * smoothstep(0.0, 0.15, uv.x) * smoothstep(1.0, 0.85, uv.x);
	COLOR = vec4(col * a, 1.0);
}
