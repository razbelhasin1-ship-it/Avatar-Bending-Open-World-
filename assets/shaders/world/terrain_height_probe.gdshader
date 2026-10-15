// GPU self-check (worldrender playtests): evaluates world_height() — the exact function the
// terrain vertex shader uses — on a grid of probe points and encodes millimetres in RGB8 so
// the CPU can compare against WorldData.get_height after a readback.
shader_type canvas_item;
render_mode blend_disabled;

#include "res://src/world/data/world_height.gdshaderinc"

uniform vec2 probe_origin = vec2(0.0);
uniform float probe_step = 37.3;
uniform float probe_size = 64.0;

void fragment() {
	vec2 pix = floor(UV * probe_size);
	vec2 xz = probe_origin + pix * probe_step + vec2(0.37, 0.71) * fract(pix * 0.61803);
	float h = world_height(xz);
	float mm = floor((h + 300.0) * 1000.0 + 0.5);
	float b2 = floor(mm / 65536.0);
	float b1 = floor((mm - b2 * 65536.0) / 256.0);
	float b0 = mm - b2 * 65536.0 - b1 * 256.0;
	COLOR = vec4(b0 / 255.0, b1 / 255.0, b2 / 255.0, 1.0);
}
