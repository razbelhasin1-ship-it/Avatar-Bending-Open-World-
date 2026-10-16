// Ink outline pass for near vegetation (next_pass of the vegetation material). Applies the same
// wind and LOD displacement as vegetation.gdshader (uniforms must match: VegetationMaterials sets
// both), then inflates the hull along the normal; the line takes a darkened tint of the surface
// colour (painterly coloured ink) and fades out with distance.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, world_vertex_coords, shadows_disabled;

#include "res://assets/shaders/content/veg_common.gdshaderinc"

uniform float sway_amount = 0.3;
uniform float flutter = 0.03;
uniform float width = 1.0;
uniform float max_distance = 45.0;
uniform float darken = 0.22;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float rnd = INSTANCE_CUSTOM.a;
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float vis = veg_rand_fade(origin, cam, INV_VIEW_MATRIX[3].xyz, rnd);
	float leaf = clamp(UV.y, 0.0, 1.0);
	if (vis <= 0.0) {
		VERTEX = origin;
	} else {
		VERTEX = origin + (VERTEX - origin) * vis;
		float size = length(MODEL_MATRIX[1].xyz);
		VERTEX += veg_wind_offset(origin, VERTEX, UV.x, leaf, rnd, sway_amount * size, flutter);
		float dist = distance(VERTEX, cam);
		float fade = 1.0 - smoothstep(max_distance * 0.55, max_distance, dist);
		VERTEX += normalize(NORMAL) * width * 0.0026 * clamp(dist, 0.5, max_distance) * fade;
	}
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * INSTANCE_CUSTOM.rgb, COLOR.a);
}

void fragment() {
	ALBEDO = COLOR.rgb * darken;
}
