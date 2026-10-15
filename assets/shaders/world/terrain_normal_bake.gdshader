// One-shot GPU bake of the world terrain normal map (worldrender TerrainNormalBaker).
// Output pixel (i, j) of an N x N target holds the normal at the world point under that
// pixel's centre, from central differences of the exact bilinear height (world_normal()).
// Encoding: R = n.x * 0.5 + 0.5, G = n.z * 0.5 + 0.5 (n.y is reconstructed).
shader_type canvas_item;
render_mode blend_disabled;

#include "res://src/world/data/world_height.gdshaderinc"

uniform float out_size = 4096.0;

void fragment() {
	vec2 pix = floor(UV * out_size) + 0.5;
	vec2 xz = WH_ORIGIN + pix * (WH_TEXEL * float(WH_SIZE) / out_size);
	float e = max(WH_TEXEL, WH_TEXEL * float(WH_SIZE) / out_size);
	float hx = world_height(xz + vec2(e, 0.0)) - world_height(xz - vec2(e, 0.0));
	float hz = world_height(xz + vec2(0.0, e)) - world_height(xz - vec2(0.0, e));
	vec3 n = normalize(vec3(-hx, 2.0 * e, -hz));
	COLOR = vec4(n.x * 0.5 + 0.5, n.z * 0.5 + 0.5, n.y, 1.0);
}
