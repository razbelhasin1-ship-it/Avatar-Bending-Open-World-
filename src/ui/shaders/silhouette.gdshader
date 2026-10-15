// Flat ink silhouette for the show-intro motif (bender rendered as a black cut-out).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.04, 0.03, 0.03, 1.0);

void fragment() {
	ALBEDO = ink.rgb;
}
