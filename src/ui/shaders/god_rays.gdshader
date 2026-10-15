// Screen-space crepuscular rays for the menu panorama: marches toward the sun's screen
// position over a blurred mip of the screen, accumulating bright sky so shafts appear only
// where light passes between peaks and clouds. Additive; cheap (8 taps on a low mip).
shader_type canvas_item;
render_mode blend_add;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 sun_uv = vec2(0.6, 0.35);
uniform vec3 ray_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float intensity = 0.35;
uniform float threshold = 0.72;
uniform float decay = 0.9;
uniform float length_scale = 0.55;
uniform float visible = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 to_sun = sun_uv - uv;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 d = to_sun * length_scale / 8.0;
	float acc = 0.0;
	float w = 1.0;
	vec2 p = uv;
	for (int i = 0; i < 8; i++) {
		p += d;
		vec3 s = textureLod(screen_tex, clamp(p, vec2(0.001), vec2(0.999)), 3.0).rgb;
		float lum = dot(s, vec3(0.299, 0.587, 0.114));
		acc += smoothstep(threshold, threshold + 0.25, lum) * w;
		w *= decay;
	}
	acc /= 5.0;
	vec2 dd = to_sun;
	dd.x /= aspect;
	float dist = length(dd);
	float falloff = exp(-dist * 2.2);
	COLOR = vec4(ray_color * acc * falloff * intensity * visible, 1.0);
}
