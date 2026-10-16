// Night glows of the settlements: camera-facing additive sprites at lantern, brazier and lit
// window positions (one MultiMesh per streamed cell; INSTANCE_CUSTOM.rgb = glow colour,
// .a = size multiplier). Invisible by day (the quad collapses, no fragments); at dusk and night
// they fade in and grow slightly with distance so a lit city still sparkles from kilometres.
// Works on Forward+, Mobile and Compatibility.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

global uniform vec4 world_sun_color;

uniform float base_size = 0.45;
uniform float grow = 0.009;
uniform float max_size = 14.0;
uniform float intensity = 1.6;

varying vec3 v_col;
varying float v_night;

void vertex() {
	float sun = clamp(dot(world_sun_color.rgb, vec3(0.3, 0.5, 0.2)), 0.0, 1.0);
	v_night = 1.0 - smoothstep(0.06, 0.42, sun);
	vec3 center = MODEL_MATRIX[3].xyz;
	float dist = length(center - CAMERA_POSITION_WORLD);
	float size = min(base_size + dist * grow, max_size) * max(INSTANCE_CUSTOM.a, 0.2);
	// day: collapse the quad (no fragments at all)
	size *= step(0.01, v_night);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
	v_col = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float core = exp(-r2 * 7.0);
	// the halo reaches exactly zero at the inscribed circle: no square edges
	float halo = max(exp(-r2 * 2.5) - 0.0821, 0.0) * 0.38;
	ALBEDO = v_col * intensity * (core + halo) * v_night;
	ALPHA = 1.0;
}
