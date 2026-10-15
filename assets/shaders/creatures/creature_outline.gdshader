// Inverted-hull ink outline for creatures (same look as assets/shaders/outline.gdshader)
// with an extra `push` so the line can sit in the middle of shell fur instead of
// hugging the skin. Vertex COLOR.a (fur amount) scales the push.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, blend_mix;

uniform vec4 outline_color : source_color = vec4(0.07, 0.055, 0.06, 1.0);
// Width in "screen-ish" units; 1.0 ~ 1.5 px at 1080p.
uniform float width = 1.0;
uniform float max_distance = 90.0;
// Extra offset in meters along the normal (fur).
uniform float push = 0.0;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * push * COLOR.a, 1.0);
	float dist = -view_pos.z;
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fade = 1.0 - smoothstep(max_distance * 0.6, max_distance, dist);
	float w = width * 0.0024 * clamp(dist, 0.5, max_distance) * fade;
	view_pos.xyz += view_n * w;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
