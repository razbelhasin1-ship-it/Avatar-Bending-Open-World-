// Soft billboard puff for smoke plumes and steam (UI panoramas / previews): noisy round
// silhouette, two-tone lighting from a fixed sun direction, optional glow at young age.
// Particle COLOR carries tint + life fade; INSTANCE_CUSTOM.y is the age (0..1).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 dark_color : source_color = vec3(0.22, 0.19, 0.19);
uniform vec3 light_color : source_color = vec3(0.70, 0.62, 0.56);
uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.15);
uniform float glow = 0.0;
uniform vec3 sun_dir = vec3(0.3, 0.6, -0.7);
uniform float alpha_scale = 1.0;

varying float age;
varying float seed;
varying vec4 pcol;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	seed = fract(float(INSTANCE_ID) * 0.6180339);
	pcol = COLOR;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
			INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	vec2 nuv = UV * 0.55 + vec2(seed * 7.1, seed * 3.3) + vec2(age * 0.1, -age * 0.15);
	float n = texture(noise_tex, nuv).r * 0.6 + texture(noise_tex, nuv * 2.4).g * 0.4;
	float shape = smoothstep(1.0, 0.4, r + (n - 0.5) * 0.75);
	vec3 nrm = normalize(INV_VIEW_MATRIX[0].xyz * q.x + INV_VIEW_MATRIX[1].xyz * -q.y + INV_VIEW_MATRIX[2].xyz * 0.8);
	float lit = clamp(dot(nrm, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	lit = mix(lit, floor(lit * 3.0 + 0.5) / 3.0, 0.35);
	vec3 col = mix(dark_color, light_color, lit * (0.7 + n * 0.3)) * pcol.rgb;
	col += glow_color * glow * (1.0 - smoothstep(0.0, 0.3, age)) * smoothstep(-0.3, 1.0, q.y);
	ALBEDO = col;
	ALPHA = clamp(shape * pcol.a * alpha_scale * (0.55 + n * 0.45), 0.0, 1.0);
}
