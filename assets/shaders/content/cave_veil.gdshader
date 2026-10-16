// Darkness inside a cave mouth: an opaque-centred black veil whose edges and bottom feather into
// the rock, hiding the terrain surface that cuts through the tunnel. Single-sided (faces out of
// the cave) so from inside the tunnel the entrance shows the outside world.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec4 darkness : source_color = vec4(0.012, 0.012, 0.016, 1.0);

void fragment() {
	vec2 p = UV;
	float side = smoothstep(0.0, 0.18, p.x) * smoothstep(1.0, 0.82, p.x);
	float top = smoothstep(1.0, 0.8, p.y);
	ALBEDO = darkness.rgb;
	ALPHA = clamp(side * top * 1.15, 0.0, 1.0) * darkness.a;
}
