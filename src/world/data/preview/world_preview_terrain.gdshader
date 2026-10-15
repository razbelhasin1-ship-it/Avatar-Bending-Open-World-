// Preview terrain material for the baked world (dev overview scene, map captures).
// Colours come from the biome/splat/ground/road maps; normals from the 2 m heightmap via the
// shared include, so lighting is crisp even on the coarse overview mesh.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/world/data/world_height.gdshaderinc"

uniform sampler2D splat_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D biome_map : filter_nearest, repeat_disable;
uniform sampler2D region_map : filter_nearest, repeat_disable;
uniform sampler2D ground_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D road_map : filter_linear_mipmap, repeat_disable;
// Displace vertices on the GPU from the heightmap (detail patches) instead of using mesh heights.
uniform bool gpu_displace = false;
// Fragments inside this world-space rect (x0, z0, x1, z1) are discarded (a detail patch covers them).
uniform vec4 hole_rect = vec4(0.0);

varying vec3 world_pos;

const vec3 BIOME_COL[14] = vec3[14](
	vec3(0.55, 0.52, 0.40),  // OCEAN (sea bed)
	vec3(0.86, 0.78, 0.56),  // BEACH
	vec3(0.93, 0.95, 0.99),  // SNOW
	vec3(0.72, 0.86, 0.95),  // ICE
	vec3(0.60, 0.60, 0.47),  // TUNDRA
	vec3(0.40, 0.57, 0.22),  // GRASSLAND
	vec3(0.17, 0.34, 0.14),  // FOREST
	vec3(0.70, 0.62, 0.30),  // FARMLAND
	vec3(0.47, 0.43, 0.39),  // ROCK
	vec3(0.50, 0.45, 0.40),  // MOUNTAIN
	vec3(0.15, 0.12, 0.12),  // VOLCANIC
	vec3(0.34, 0.31, 0.30),  // ASH
	vec3(0.86, 0.78, 0.60),  // TEMPLE
	vec3(0.70, 0.62, 0.52)   // CITY
);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (gpu_displace) {
		wp.y = world_height(wp.xz);
		VERTEX.y = wp.y - MODEL_MATRIX[3].y;
	}
	world_pos = wp;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0)), u.x), u.y);
}

void fragment() {
	if (hole_rect.z > hole_rect.x && world_pos.x > hole_rect.x && world_pos.x < hole_rect.z
			&& world_pos.z > hole_rect.y && world_pos.z < hole_rect.w) {
		discard;
	}
	vec2 uv = world_uv(world_pos.xz);
	ivec2 bt = clamp(ivec2(uv * 2048.0), ivec2(0), ivec2(2047));
	int biome = int(texelFetch(biome_map, bt, 0).r * 255.0 + 0.5);
	int region = int(texelFetch(region_map, clamp(ivec2(uv * 1024.0), ivec2(0), ivec2(1023)), 0).r * 255.0 + 0.5);
	vec4 sp = texture(splat_map, uv);
	vec4 gr = texture(ground_map, uv);
	float road = texture(road_map, uv).r;
	float n1 = vnoise(world_pos.xz * 0.05) * 0.6 + vnoise(world_pos.xz * 0.21) * 0.4;
	vec3 base = BIOME_COL[clamp(biome, 0, 13)];
	vec3 soil = mix(vec3(0.46, 0.38, 0.27), base, 0.55);
	vec3 lush = biome == 6 ? vec3(0.15, 0.32, 0.13) : (biome == 7 ? vec3(0.62, 0.60, 0.28) : vec3(0.36, 0.55, 0.20));
	if (region == 3 && biome != 7) {
		lush = mix(lush, vec3(0.10, 0.36, 0.16), 0.5);   // tropical Fire Nation greens
	}
	if (region == 4) {
		lush = mix(lush, vec3(0.34, 0.52, 0.30), 0.4);   // cool alpine meadows
	}
	vec3 sand = (biome == 11 || biome == 10 || region == 3) ? vec3(0.22, 0.20, 0.20) : vec3(0.86, 0.78, 0.56);
	vec3 rock = region == 3 ? vec3(0.27, 0.23, 0.22) : (region == 1 ? vec3(0.42, 0.44, 0.48) : vec3(0.50, 0.45, 0.40));
	vec3 snow = biome == 3 ? vec3(0.70, 0.85, 0.95) : vec3(0.94, 0.96, 1.0);
	float rest = clamp(1.0 - (sp.r + sp.g + sp.b + sp.a), 0.0, 1.0);
	vec3 col = soil * rest + snow * sp.r + rock * sp.g + lush * sp.b + sand * sp.a;
	col *= 0.9 + 0.2 * n1;
	if (biome == 13 || biome == 12) {
		col = mix(col, base * (0.92 + 0.12 * vnoise(world_pos.xz * 0.5)), 0.85);
	}
	col = mix(col, vec3(0.66, 0.60, 0.52), clamp(gr.g * 0.6, 0.0, 1.0));
	vec3 road_col = gr.r > 0.4 ? vec3(0.62, 0.58, 0.52) : vec3(0.52, 0.42, 0.30);
	col = mix(col, road_col, smoothstep(0.25, 0.75, road));
	if (biome == 7) {
		float furrow = smoothstep(0.35, 0.65, sin(dot(world_pos.xz, vec2(0.9, 0.4)) * 1.3) * 0.5 + 0.5);
		col *= 0.9 + 0.12 * furrow;
	}
	vec3 n = world_normal(world_pos.xz);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = biome == 3 ? 0.35 : 0.92;
	SPECULAR = biome == 3 ? 0.6 : 0.25;
}
