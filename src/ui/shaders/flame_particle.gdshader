// Stylised fire particle (UI previews): additive camera-facing tongue with a noisy, upward
// licking silhouette. Colour comes from the particle colour ramp (white-yellow core ->
// orange -> deep red); INSTANCE_CUSTOM.y is the age used to shrink and redden the lick.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float intensity = 1.6;
uniform float stretch = 1.4;

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
	q.y = q.y / stretch + 0.25;
	float n = texture(noise_tex, UV * vec2(0.6, 0.9) + vec2(seed * 3.7, seed * 1.9 - TIME * 0.9)).r;
	// teardrop: wide at the bottom, licking to a point at the top
	float w = mix(0.95, 0.25, clamp(-q.y * 0.5 + 0.5, 0.0, 1.0));
	float d = length(vec2(q.x / max(w, 0.05), q.y));
	float shape = smoothstep(1.0, 0.25, d + (n - 0.5) * 0.9);
	float core = smoothstep(0.55, 0.0, d);
	vec3 col = pcol.rgb * (0.8 + core * 0.8);
	ALBEDO = col * intensity;
	ALPHA = clamp(shape * pcol.a, 0.0, 1.0);
}
