shader_type spatial;
// Soft pulsing glint billboard for quest props and markers (additive, unshaded; works on
// Forward+, Mobile and Compatibility).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float strength = 1.0;
uniform float speed = 2.2;

void vertex() {
	// camera-facing quad, size from the model scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float pulse = 0.65 + 0.35 * sin(TIME * speed);
	float core = exp(-r * r * 9.0);
	float halo = exp(-r * r * 2.6) * 0.35;
	float star = max(0.0, 1.0 - abs(p.x) * 9.0) * max(0.0, 1.0 - abs(p.y) * 1.2)
		+ max(0.0, 1.0 - abs(p.y) * 9.0) * max(0.0, 1.0 - abs(p.x) * 1.2);
	float a = (core + halo + star * 0.45 * pulse) * pulse * strength * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = tint.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
