// Ground disc of a preview stage: lit (receives the character's shadow), tinted per
// element, fading to transparent at the rim so the stage melts into the card painting.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled;

uniform vec4 color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 edge_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float radius = 3.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float r = length(lpos.xz) / radius;
	float n = texture(noise_tex, lpos.xz * 0.25).r;
	vec3 c = mix(color.rgb, edge_color.rgb, smoothstep(0.2, 1.0, r + (n - 0.5) * 0.3));
	ALBEDO = c * (0.88 + n * 0.24);
	ROUGHNESS = 1.0;
	ALPHA = smoothstep(1.0, 0.55, r + (n - 0.5) * 0.25);
}
