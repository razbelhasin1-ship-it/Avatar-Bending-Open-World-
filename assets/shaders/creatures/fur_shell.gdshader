// Shell fur layer: the creature skin mesh redrawn offset along its normals; strands
// are cut out procedurally (alpha scissor, so no sorting). CreatureMaterials chains
// N of these as next_pass of the skin material (N scales with Settings.detail_level()).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://assets/shaders/creatures/creature_common.gdshaderinc"

// Normalized height of this shell (0 = skin, 1 = fur tips).
uniform float shell : hint_range(0.0, 1.0) = 0.5;
uniform float fur_length = 0.06;
// Strands per meter.
uniform float fur_density = 70.0;
// Model-space bend of the tips (fur combed back/down).
uniform vec3 comb = vec3(0.0, -0.35, 0.45);
// Strand root radius in cell units.
uniform float strand_width : hint_range(0.1, 0.9) = 0.62;
uniform float tip_lighten : hint_range(0.0, 0.5) = 0.08;
uniform float root_dark : hint_range(0.0, 0.6) = 0.12;

varying vec2 v_fur;
varying float v_fur_amount;

void vertex() {
	// COLOR.a scales fur length per vertex (0 on noses/pads).
	float h = shell * fur_length * COLOR.a;
	VERTEX += NORMAL * h + comb * (h * shell);
	v_fur = UV2 * fur_density;
	v_fur_amount = COLOR.a;
}

void fragment() {
	if (v_fur_amount < 0.05) {
		discard;
	}
	// Strand height field: clumpy value noise mixed with per-cell strand cones. Near
	// the skin almost everything is covered (no gaps at the silhouette); toward the
	// tips only strand centers survive, so the edge reads as soft fur.
	vec2 cell = floor(v_fur);
	vec2 f = fract(v_fur) - 0.5;
	vec2 off = (creature_hash22(cell) - 0.5) * 0.4;
	float cone = 1.0 - clamp(length(f - off) / (0.5 * strand_width + 0.2), 0.0, 1.0);
	float clump = creature_vnoise(v_fur * 0.35 + 3.7);
	float len = mix(0.55, 1.0, creature_hash12(cell + 17.0));
	float h = (cone * 0.7 + clump * 0.45) * len;
	if (h < shell * 0.92 + 0.04) {
		discard;
	}
	vec3 c = albedo.rgb * COLOR.rgb;
	c = creature_apply_marks(c, creature_mark_mask(UV));
	c *= mix(1.0 - root_dark, 1.0 + tip_lighten, shell);
	ALBEDO = creature_status(c);
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	EMISSION = creature_flash();
}
