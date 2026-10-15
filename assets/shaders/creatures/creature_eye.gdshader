// Stylized creature eye: sclera / iris / pupil drawn analytically from the eye-local
// direction MeshKit stores in UV (xy of the unit direction) and UV2.x (forwardness),
// plus an anime-style catchlight fixed in view space so eyes always feel alive.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 sclera : source_color = vec4(0.93, 0.91, 0.86, 1.0);
uniform vec4 iris : source_color = vec4(0.30, 0.19, 0.10, 1.0);
uniform vec4 iris_inner : source_color = vec4(0.55, 0.36, 0.18, 1.0);
uniform float iris_size = 0.78;
uniform float pupil_size = 0.42;
// Horizontal pupil scale: 1 = round, 0.25 = reptile slit.
uniform float pupil_slit = 1.0;
uniform float glow : hint_range(0.0, 8.0) = 0.0;
uniform float catchlight : hint_range(0.0, 2.0) = 1.0;
instance uniform float hit_flash : hint_range(0.0, 1.0), instance_index(2) = 0.0;

void fragment() {
	vec2 e = UV;
	float fwd = UV2.x;
	float r = length(e);
	vec3 c = sclera.rgb;
	float iris_m = 0.0;
	if (fwd > 0.0) {
		float aa = max(fwidth(r), 0.01);
		iris_m = 1.0 - smoothstep(iris_size - aa, iris_size + aa, r);
		vec3 ic = mix(iris_inner.rgb, iris.rgb, smoothstep(0.0, iris_size, r));
		c = mix(c, ic, iris_m);
		float pr = length(e * vec2(1.0 / max(pupil_slit, 0.05), 1.0));
		float pm = 1.0 - smoothstep(pupil_size - aa, pupil_size + aa, pr);
		c = mix(c, vec3(0.015, 0.012, 0.012), pm * iris_m);
	}
	ALBEDO = c;
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
	vec3 hl_dir = normalize(vec3(-0.42, 0.5, 1.0));
	float hl = smoothstep(0.955, 0.968, dot(NORMAL, hl_dir));
	float hl2 = smoothstep(0.988, 0.992, dot(NORMAL, normalize(vec3(0.35, -0.3, 1.0))));
	EMISSION = vec3(1.0) * (hl + hl2 * 0.6) * catchlight + iris.rgb * glow * iris_m + vec3(1.0, 0.95, 0.9) * hit_flash;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.1, 0.1, ndl + 0.1) * smoothstep(0.0, 0.25, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(vec3(0.45, 0.42, 0.55), vec3(1.0), lit);
}
