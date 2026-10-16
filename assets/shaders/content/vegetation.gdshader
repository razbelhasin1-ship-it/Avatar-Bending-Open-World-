// Toon vegetation, rocks and ice for MultiMesh instances (trees, shrubs, boulders, impostors).
// Soft two-tone shading like assets/shaders/toon.gdshader, foliage translucency, wind sway from the
// world wind globals, per-instance distance LOD (see veg_common.gdshaderinc), snow/wetness from
// the weather globals. Materials are created by VegetationMaterials (src/world/vegetation/).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, world_vertex_coords;

#include "res://assets/shaders/content/veg_common.gdshaderinc"

// Tip displacement (m) per 10 m/s of wind for a sway weight of 1, scaled by instance size.
uniform float sway_amount = 0.3;
uniform float flutter = 0.03;
uniform vec4 shade_tint : source_color = vec4(0.50, 0.58, 0.82, 1.0);
uniform float band_softness = 0.16;
uniform float band_offset = 0.12;
uniform float translucency = 0.35;
uniform float rim_strength = 0.22;
// Colour of kind-3 vertices (snow caps on pines/rocks, moss, ash dust): per material.
uniform vec4 cap_color : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform vec4 ember_color : source_color = vec4(1.0, 0.28, 0.04, 1.0);
uniform float ember_energy = 1.3;
// How strongly falling snow (world_snow_cover) whitens up-facing parts.
uniform float snow_receptive = 1.0;
// Extra brightness of ice (kind 0 with high specular) — 0 for wood/rock.
uniform float gloss = 0.0;

varying vec3 v_wnormal;
varying vec3 v_wpos;
varying vec2 v_cap_ember;
varying float v_leaf;

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
	}
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * INSTANCE_CUSTOM.rgb, COLOR.a);
	v_wnormal = NORMAL;
	v_wpos = VERTEX;
	v_cap_ember = UV2;
	v_leaf = leaf;
}

void fragment() {
	vec3 c = mix(COLOR.rgb, cap_color.rgb, clamp(v_cap_ember.x, 0.0, 1.0));
	float up = clamp(v_wnormal.y, 0.0, 1.0);
	c = mix(c, vec3(0.90, 0.94, 1.0), world_snow_cover * snow_receptive * smoothstep(0.35, 0.8, up));
	c *= 1.0 - world_wetness * 0.22 * (1.0 - v_leaf * 0.5);
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.35, gloss);
	SPECULAR = mix(0.12, 0.5, gloss);
	METALLIC = 0.0;
	if (v_cap_ember.y > 0.01) {
		// glowing cracks: two warped sine fields, lit where either crosses zero
		vec3 q = v_wpos * 1.6;
		float a = abs(sin(q.x * 1.3 + sin(q.z * 1.1 + q.y * 0.7) * 2.0));
		float b = abs(sin(q.z * 1.7 + sin(q.x * 0.9 - q.y * 1.3) * 2.0));
		float crack = (1.0 - smoothstep(0.0, 0.14, min(a, b))) * clamp(v_cap_ember.y * 1.4, 0.0, 1.0);
		float pulse = 0.75 + 0.25 * sin(TIME * 1.7 + dot(v_wpos, vec3(0.3, 0.5, 0.2)));
		ALBEDO = mix(ALBEDO, ember_color.rgb * 0.25, crack * 0.6);
		EMISSION = ember_color.rgb * ember_energy * pulse * crack;
	}
}

void light() {
	vec3 shade = veg_toon_shade(NORMAL, LIGHT, ATTENUATION, shade_tint.rgb, band_softness, band_offset);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * shade;
	float att = smoothstep(0.0, 0.3, ATTENUATION);
	// light through leaves when looking towards the sun
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * translucency * v_leaf;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * back * att * vec3(1.0, 0.96, 0.62);
	float rim = smoothstep(0.5, 0.82, 1.0 - max(dot(NORMAL, VIEW), 0.0));
	SPECULAR_LIGHT += LIGHT_COLOR / PI * rim * rim_strength * max(att, 0.3) * ALBEDO;
	if (gloss > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float spec = smoothstep(0.96, 0.98, dot(NORMAL, h));
		SPECULAR_LIGHT += LIGHT_COLOR / PI * spec * gloss * att;
	}
}
