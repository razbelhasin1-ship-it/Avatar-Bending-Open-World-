// Soft camera-facing puffs for dust, snow, steam, spray and smoke particles.
// Noise-eroded edges dissolve with particle age (INSTANCE_CUSTOM.y); a fake
// top-light keeps them reading as volumes without scene lighting cost.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float softness = 0.35;
// 0 = soft dust, 1 = crisp toon cloud edge.
uniform float crisp = 0.4;
uniform float shade = 0.22;
uniform float opacity = 1.0;

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	v_seed = fract(float(INSTANCE_ID) * 0.7548777);
	float ang = INSTANCE_CUSTOM.x;
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float n = texture(noise_tex, UV * 0.6 + vec2(v_seed * 5.0, v_seed * 3.0)).r;
	float shape = r + (n - 0.5) * 0.55;
	float edge0 = mix(0.35, 0.78, crisp);
	float a = 1.0 - smoothstep(edge0 - softness * (1.0 - crisp), 0.86, shape);
	float dissolve = smoothstep(v_age * 1.05 - 0.12, v_age * 1.05 + 0.04, n * 0.85 + 0.15);
	float top = clamp(0.5 - uv.y * 0.5 + (n - 0.5) * 0.3, 0.0, 1.0);
	ALBEDO = COLOR.rgb * mix(1.0 - shade, 1.0, top);
	ALPHA = clamp(a * dissolve * COLOR.a * opacity, 0.0, 1.0);
}
