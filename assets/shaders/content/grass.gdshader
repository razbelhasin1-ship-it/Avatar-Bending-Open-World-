// Grass, flowers, reeds and crops (MultiMesh clumps). Colour = vertex colour tinted by the
// instance colour (matched to the terrain's lush palette on the CPU) with a dark root and a light
// tip; normals are bent up so the clumps light like the ground they grow from (no seams at the
// fade distance). Wind: rolling gust waves across the field + per-blade flutter. Instances
// shrink into the ground over the distance band (veg_common.gdshaderinc).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, world_vertex_coords;

#include "res://assets/shaders/content/veg_common.gdshaderinc"

uniform vec4 tip_tint : source_color = vec4(1.0, 1.0, 0.82, 1.0);
uniform float tip_brightness = 1.3;
uniform float root_darkness = 0.55;
uniform float sway_amount = 1.0;
uniform float wave_strength = 0.7;
uniform vec4 shade_tint : source_color = vec4(0.55, 0.62, 0.80, 1.0);
uniform float translucency = 0.45;
uniform float up_normal = 0.7;

varying float v_h;
varying float v_wy;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float rnd = INSTANCE_CUSTOM.a;
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float vis = veg_rand_fade(origin, cam, INV_VIEW_MATRIX[3].xyz, rnd);
	float h = UV.x;
	if (vis <= 0.0) {
		VERTEX = origin;
	} else {
		vec3 rel = VERTEX - origin;
		VERTEX = origin + vec3(rel.x, rel.y * vis, rel.z);
		float ws = wind_strength * (1.0 + wind_gust * 0.7);
		float wave = sin(dot(origin.xz, wind_direction) * 0.16 - wind_time * 1.55 + rnd * 0.9) * 0.5 + 0.5;
		float sway = (0.3 + wave * wave * wave_strength) * ws * 0.03 * sway_amount;
		vec3 off = vec3(wind_direction.x, 0.0, wind_direction.y) * sway * h * h;
		float fl = sin(wind_time * 3.3 + rnd * 23.0 + VERTEX.x * 2.1) * 0.5 + sin(wind_time * 4.1 + VERTEX.z * 2.7) * 0.5;
		off.xz += vec2(fl, -fl * 0.7) * 0.035 * h * h * (0.4 + ws * 0.12) * sway_amount;
		off.y -= length(off.xz) * 0.35 * h;
		VERTEX += off;
	}
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * INSTANCE_CUSTOM.rgb, COLOR.a);
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), up_normal));
	v_h = h;
	v_wy = NORMAL.y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 c = mix(base * root_darkness, base * tip_tint.rgb * tip_brightness, smoothstep(0.0, 1.0, v_h));
	c = mix(c, vec3(0.88, 0.92, 1.0), world_snow_cover * 0.7 * v_h);
	c *= 1.0 - world_wetness * 0.2;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.08;
}

void light() {
	vec3 shade = veg_toon_shade(NORMAL, LIGHT, ATTENUATION, shade_tint.rgb, 0.22, 0.18);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * shade;
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.5) * translucency * v_h;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * back * smoothstep(0.0, 0.3, ATTENUATION) * vec3(1.0, 0.95, 0.55);
}
