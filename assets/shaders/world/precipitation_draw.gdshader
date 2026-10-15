// Draw pass for precipitation particles: camera-facing quads; streaks are stretched along the
// particle's velocity axis (TRANSFORM column 1), flakes are round soft dots. Lit by the
// current sun/sky colours (global uniforms) so snow glows at sunset and dims at night.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, world_vertex_coords;

global uniform vec4 world_sun_color;
global uniform vec4 world_sky_zenith;
global uniform vec4 world_sky_horizon;

uniform float softness = 0.5;
uniform float opacity = 0.8;
uniform float brightness = 1.0;

varying vec4 pcolor;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 1e-5 ? side / sl * width : INV_VIEW_MATRIX[0].xyz * width;
	vec2 q = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	VERTEX = center + side * q.x + axis * q.y;
	pcolor = COLOR;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	vec3 light = mix(world_sky_horizon.rgb, world_sky_zenith.rgb, 0.4) * 0.9 + world_sun_color.rgb * 0.35;
	vec3 col = pcolor.rgb;
	// embers (HDR colours > 1) stay emissive, everything else takes the scene light
	if (max(col.r, max(col.g, col.b)) <= 1.01) {
		col *= light * brightness;
	}
	ALBEDO = col;
	ALPHA = a * pcolor.a * opacity;
}
