// Wing membrane: toon shaded leathery skin with veins and sunlight shining through
// (`translucency` in the shared light model). Double sided.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

#include "res://assets/shaders/creatures/creature_common.gdshaderinc"

uniform vec4 vein_color : source_color = vec4(0.35, 0.06, 0.04, 1.0);
uniform float vein_scale = 1.6;

varying float v_edge;

void vertex() {
	v_edge = UV.y;
}

void fragment() {
	CREATURE_OCCLUSION_DISCARD
	vec3 c = albedo.rgb * COLOR.rgb;
	// Veins: branching lines along the membrane (UV2 = finger index, row).
	float vx = abs(fract(UV2.x * vein_scale * 0.5 + 0.13 * sin(UV2.y * 2.1)) - 0.5);
	float vn = creature_vnoise(UV2 * vec2(3.0, 5.0));
	float vein = (1.0 - smoothstep(0.015, 0.05, vx)) * (0.6 + 0.4 * vn);
	c = mix(c, vein_color.rgb, vein * 0.55 * (1.0 - v_edge * 0.5));
	// Darker scalloped trailing edge.
	c *= 1.0 - 0.25 * smoothstep(0.75, 1.0, v_edge);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = creature_status(c);
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
	EMISSION = creature_flash();
}
