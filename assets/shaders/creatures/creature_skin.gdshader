// Creature body surface: toon shading + vertex color tint + marking bands +
// procedural surface pattern (fur strokes, scales, belly plates, feathers, shell).
// Built by CreatureMaterials (src/creatures/core/creature_materials.gd).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://assets/shaders/creatures/creature_common.gdshaderinc"

// 0 none, 1 fur strokes, 2 scales, 3 feathers, 4 shell plates, 5 smooth skin (subtle mottling)
uniform int pattern = 0;
// Pattern cells per meter.
uniform float pattern_scale = 8.0;
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.15;
// Draws plate seams inside the ventral band (dragon/komodo belly).
uniform float plate_spacing = 0.0;
uniform vec4 plate_line : source_color = vec4(0.55, 0.32, 0.12, 1.0);
// Darkens the underside slightly (ambient occlusion feel), 0..1.
uniform float belly_shade : hint_range(0.0, 1.0) = 0.12;

varying vec3 v_obj_normal;

void vertex() {
	v_obj_normal = NORMAL;
}

float scales_pattern(vec2 p) {
	// Overlapping arcs, rows offset by half a cell.
	float row = floor(p.y);
	vec2 q = vec2(p.x + 0.5 * mod(row, 2.0), p.y);
	vec2 f = fract(q) - vec2(0.5, 0.0);
	float d = length(f * vec2(1.0, 1.35));
	float d2 = length((f - vec2(sign(f.x) * 0.5, 0.5)) * vec2(1.0, 1.35));
	float edge = smoothstep(0.40, 0.5, min(d, d2 + 0.02));
	return edge;
}

void fragment() {
	vec3 c = albedo.rgb * COLOR.rgb;
	vec3 m = creature_mark_mask(UV);
	c = creature_apply_marks(c, m);
	vec2 p = UV2 * pattern_scale;
	if (pattern == 1) {
		float n = creature_vnoise(vec2(p.x * 1.6, p.y * 0.35));
		float n2 = creature_vnoise(vec2(p.x * 3.7 + 7.0, p.y * 0.8));
		c *= 1.0 - pattern_strength * smoothstep(0.45, 0.85, n * 0.65 + n2 * 0.35);
	} else if (pattern == 2) {
		float e = scales_pattern(p);
		c *= 1.0 - pattern_strength * e;
		c *= 1.0 + pattern_strength * 0.35 * (1.0 - e) * fract(p.y);
	} else if (pattern == 3) {
		float row = floor(p.y);
		vec2 q = vec2(p.x * 0.8 + 0.5 * mod(row, 2.0), p.y);
		vec2 f = fract(q);
		float edge = smoothstep(0.75, 1.0, f.y) * (0.6 + 0.4 * smoothstep(0.2, 0.5, abs(f.x - 0.5)));
		c *= 1.0 - pattern_strength * edge;
	} else if (pattern == 4) {
		vec2 q = p * vec2(1.0, 1.15);
		vec2 g = fract(q) - 0.5;
		float edge = smoothstep(0.38, 0.48, max(abs(g.x), abs(g.y)));
		c *= 1.0 - pattern_strength * edge;
	} else if (pattern == 5) {
		float n = creature_vnoise(p * 0.7);
		c *= 1.0 - pattern_strength * smoothstep(0.55, 0.9, n);
	}
	if (plate_spacing > 0.0 && m.y > 0.01) {
		float s = fract(UV2.y / plate_spacing);
		float seam = smoothstep(0.86, 0.94, s) * (1.0 - smoothstep(0.96, 1.0, s));
		c = mix(c, plate_line.rgb, seam * m.y * 0.85);
		c *= mix(1.0, 0.86 + 0.14 * s, m.y);
	}
	c *= 1.0 - belly_shade * smoothstep(0.1, -0.8, v_obj_normal.y);
	ALBEDO = creature_status(c);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	EMISSION = emission.rgb * emission_energy + creature_flash();
}
