// World heightmap sampling for shaders (terrain, water shore depth, vegetation, snow...).
//
// Bind WorldData.get_height_texture() to `world_height_map` (or call
// WorldData.apply_height_uniforms(material)). The texture is FORMAT_RG8 holding the raw
// uint16 height code (R = low byte, G = high byte). It must be read with texelFetch
// only: filtered sampling would blend the two bytes independently.
//
// world_height(xz) reproduces WorldHeightfield.sample() / WorldData.get_height():
// identical texel-centre convention and interpolation order, so CPU and GPU agree exactly
// at texel centres (odd world coordinates on the 2 m grid) and to float32 precision elsewhere.
//
//   #include "res://src/world/data/world_height.gdshaderinc"
//   void vertex() { VERTEX.y = world_height((MODEL_MATRIX * vec4(VERTEX, 1.0)).xz); }

uniform sampler2D world_height_map : filter_nearest, repeat_disable;

const float WH_ORIGIN = -4096.0;     // WorldConstants.WORLD_MIN
const float WH_TEXEL = 2.0;          // WorldConstants.TEXEL_SIZE
const int WH_SIZE = 4096;            // WorldConstants.HEIGHTMAP_SIZE
const float WH_MIN = -256.0;         // WorldConstants.HEIGHT_MIN
const float WH_SCALE = 0.03125;      // WorldConstants.HEIGHT_SCALE

// Height (metres) of heightmap texel t (clamped to the map).
float world_height_texel(ivec2 t) {
	ivec2 c = clamp(t, ivec2(0), ivec2(WH_SIZE - 1));
	vec2 rg = texelFetch(world_height_map, c, 0).rg;
	float raw = floor(rg.r * 255.0 + 0.5) + floor(rg.g * 255.0 + 0.5) * 256.0;
	return raw * WH_SCALE + WH_MIN;
}

// Bilinear terrain height at world position xz (metres).
float world_height(vec2 xz) {
	vec2 uv = clamp((xz - WH_ORIGIN) / WH_TEXEL - 0.5, vec2(0.0), vec2(float(WH_SIZE) - 1.0));
	ivec2 i0 = ivec2(floor(uv));
	ivec2 i1 = min(i0 + ivec2(1), ivec2(WH_SIZE - 1));
	vec2 f = uv - vec2(i0);
	float h00 = world_height_texel(i0);
	float h10 = world_height_texel(ivec2(i1.x, i0.y));
	float h01 = world_height_texel(ivec2(i0.x, i1.y));
	float h11 = world_height_texel(i1);
	float a = h00 + (h10 - h00) * f.x;
	float b = h01 + (h11 - h01) * f.x;
	return a + (b - a) * f.y;
}

// Terrain normal from central differences one texel apart (matches WorldData.get_normal()).
vec3 world_normal(vec2 xz) {
	float e = WH_TEXEL;
	float hx = world_height(xz + vec2(e, 0.0)) - world_height(xz - vec2(e, 0.0));
	float hz = world_height(xz + vec2(0.0, e)) - world_height(xz - vec2(0.0, e));
	return normalize(vec3(-hx, 2.0 * e, -hz));
}

// UV of a world position on any texture that covers the whole world (splat, biome, map...).
vec2 world_uv(vec2 xz) {
	return (xz - WH_ORIGIN) / (WH_TEXEL * float(WH_SIZE));
}
