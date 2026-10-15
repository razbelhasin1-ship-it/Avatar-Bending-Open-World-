// Clipmap terrain of the baked world (worldrender module).
//
// Vertex: every clipmap piece is a grid in cell units scaled by the level spacing s. Heights
// come from the shared include (bit-identical bilinear formula to WorldData.get_height), plus
// snow-trail displacement near the focus. Odd vertices geomorph towards the next coarser
// level in the outer part of each ring, so levels meet without cracks or popping.
// Fragment: painterly biome/splat layering with regional palettes, slope rock with triplanar
// cliffs, world-space macro variation, near-field detail patterns + normals, snow trails.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://src/world/data/world_height.gdshaderinc"
#include "res://assets/shaders/world/world_common.gdshaderinc"

global uniform float world_wetness;
global uniform float world_snow_cover;

// Geometry clipmap
uniform vec3 clip_center = vec3(0.0);
uniform float grid_origin = 1.0;
uniform float morph_start = 40.0;
uniform float morph_end = 60.0;

// World maps
uniform sampler2D world_normal_map : filter_linear_mipmap_anisotropic, repeat_disable;
// false until TerrainNormalBaker delivered the baked map (then shading reads it instead of
// differencing the heightmap per pixel)
uniform bool use_normal_map = false;
uniform sampler2D splat_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D biome_map : filter_nearest, repeat_disable;
uniform sampler2D region_map : filter_nearest, repeat_disable;
uniform sampler2D ground_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D road_map : filter_linear_mipmap, repeat_disable;
uniform bool has_world = true;

#include "res://assets/shaders/world/snow_trail.gdshaderinc"

// Tiling detail
uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_distance = 140.0;
uniform float detail_strength = 1.0;

varying vec3 world_pos;
// slope of the ~16 m blurred terrain normal (layer selection), interpolated per vertex
varying float soft_slope;

// Regional palettes (sRGB), index: 0 water tribe, 1 earth kingdom (+ wilds/ocean), 2 fire nation, 3 air temple
const vec3 GRASS_D[4] = vec3[4](vec3(0.40, 0.44, 0.35), vec3(0.27, 0.43, 0.15), vec3(0.09, 0.29, 0.13), vec3(0.28, 0.44, 0.26));
const vec3 GRASS_L[4] = vec3[4](vec3(0.60, 0.61, 0.48), vec3(0.60, 0.70, 0.29), vec3(0.27, 0.52, 0.21), vec3(0.55, 0.68, 0.41));
const vec3 ROCK_D[4] = vec3[4](vec3(0.27, 0.32, 0.41), vec3(0.38, 0.32, 0.27), vec3(0.13, 0.11, 0.11), vec3(0.37, 0.34, 0.33));
const vec3 ROCK_L[4] = vec3[4](vec3(0.58, 0.64, 0.72), vec3(0.70, 0.61, 0.48), vec3(0.38, 0.31, 0.29), vec3(0.72, 0.66, 0.58));
const vec3 SOIL[4] = vec3[4](vec3(0.44, 0.44, 0.45), vec3(0.55, 0.44, 0.30), vec3(0.33, 0.26, 0.22), vec3(0.57, 0.51, 0.41));
const vec3 SAND[4] = vec3[4](vec3(0.74, 0.74, 0.72), vec3(0.89, 0.81, 0.61), vec3(0.19, 0.17, 0.18), vec3(0.82, 0.76, 0.62));
const vec3 PAVE[4] = vec3[4](vec3(0.80, 0.87, 0.94), vec3(0.68, 0.64, 0.55), vec3(0.52, 0.42, 0.38), vec3(0.88, 0.82, 0.68));

// Visible surface height: terrain (exact WorldData.get_height formula) + snow trail.
float surface_height(vec2 xz, float spacing) {
	float base = 0.0;
	if (has_world) {
		// levels with >= 2 m spacing have every vertex on a texel centre, where the bilinear
		// formula returns the stored texel exactly: one fetch instead of four
		if (spacing >= 2.0) {
			base = world_height_texel(ivec2(round((xz - WH_ORIGIN) / WH_TEXEL - 0.5)));
		} else {
			base = world_height(xz);
		}
	}
	return base + trail_displacement(xz, spacing);
}

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = round((wp.xz - grid_origin) / s);
	wp.xz = g * s + grid_origin;
	vec2 odd = abs(g - 2.0 * floor(g * 0.5));
	float d = max(abs(wp.x - clip_center.x), abs(wp.z - clip_center.z)) / s;
	float m = clamp((d - morph_start) / (morph_end - morph_start), 0.0, 1.0);
	float h = surface_height(wp.xz, s);
	if (m > 0.0 && odd.x + odd.y > 0.5) {
		// coarse-level surface at this vertex: midpoint of the coarse edge / (0,0)-(2,2) diagonal
		vec2 o = odd * s;
		float hc = 0.5 * (surface_height(wp.xz - o, s * 2.0) + surface_height(wp.xz + o, s * 2.0));
		h = mix(h, hc, m);
	}
	wp.y = h;
	VERTEX = vec3((wp.x - MODEL_MATRIX[3].x) / s, h - MODEL_MATRIX[3].y, (wp.z - MODEL_MATRIX[3].z) / s);
	world_pos = wp;
	// real vertex normals (shadow normal-offset bias, lighting before the fragment override);
	// pre-scaled because the (s, 1, s) model scale is undone by the normal matrix
	vec3 vn = vec3(0.0, 1.0, 0.0);
	soft_slope = 0.0;
	if (has_world) {
		if (use_normal_map) {
			vec2 uvn = world_uv(wp.xz);
			vec2 nxz = textureLod(world_normal_map, uvn, max(log2(s * 0.5), 0.0)).rg * 2.0 - 1.0;
			vn = vec3(nxz.x, sqrt(max(1.0 - dot(nxz, nxz), 0.0)), nxz.y);
			vec2 sxz = textureLod(world_normal_map, uvn, max(3.0, log2(s * 0.5))).rg * 2.0 - 1.0;
			soft_slope = 1.0 - sqrt(max(1.0 - dot(sxz, sxz), 0.0));
		} else {
			vn = world_normal(wp.xz);
			soft_slope = 1.0 - vn.y;
		}
	}
	NORMAL = normalize(vec3(vn.x * s, vn.y, vn.z * s));
}

vec3 terrain_normal(vec2 xz, vec2 uv, float dist) {
	if (!use_normal_map) {
		return world_normal(xz);
	}
	// distant terrain reads smoother (painterly): bias the normal map towards softer mips
	float bias = clamp(log2(dist / 220.0), 0.0, 2.5);
	vec2 nxz = texture(world_normal_map, uv, bias).rg * 2.0 - 1.0;
	return normalize(vec3(nxz.x, sqrt(max(1.0 - dot(nxz, nxz), 0.0)), nxz.y));
}

// Region weights (water tribe, earth kingdom, fire nation, air temple), bilinear over 4 texels.
vec4 region_weights(vec2 xz) {
	vec2 t = (xz - WH_ORIGIN) / 8.0 - 0.5;
	ivec2 i0 = ivec2(floor(t));
	vec2 f = smoothstep(0.0, 1.0, fract(t));
	vec4 acc = vec4(0.0);
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		int id = int(texelFetch(region_map, clamp(i0 + o, ivec2(0), ivec2(1023)), 0).r * 255.0 + 0.5);
		float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		vec4 r = id == 1 ? vec4(1, 0, 0, 0) : (id == 3 ? vec4(0, 0, 1, 0) : (id == 4 ? vec4(0, 0, 0, 1) : vec4(0, 1, 0, 0)));
		acc += r * w;
	}
	return acc;
}

vec3 pal4(vec3 a, vec3 b, vec3 c, vec3 d, vec4 rw) {
	return a * rw.x + b * rw.y + c * rw.z + d * rw.w;
}

// Biome class weights over 4 texels: lush variant (grass, forest, farm, tundra) and flags
// (ice, paved temple/city, volcanic/ash, beach).
void biome_weights(vec2 xz, out vec4 lush, out vec4 flags) {
	vec2 t = (xz - WH_ORIGIN) / 4.0 - 0.5;
	ivec2 i0 = ivec2(floor(t));
	vec2 f = smoothstep(0.0, 1.0, fract(t));
	lush = vec4(0.0);
	flags = vec4(0.0);
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		int id = int(texelFetch(biome_map, clamp(i0 + o, ivec2(0), ivec2(2047)), 0).r * 255.0 + 0.5);
		float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		lush += w * (id == 6 ? vec4(0, 1, 0, 0) : (id == 7 ? vec4(0, 0, 1, 0) : ((id == 4 || id == 2) ? vec4(0, 0, 0, 1) : vec4(1, 0, 0, 0))));
		flags += w * vec4(float(id == 3), float(id == 12 || id == 13), float(id == 10 || id == 11), float(id == 1));
	}
}

// Detail pattern sampled with two scales/rotations (hides tiling); returns pattern in 0..1.
float pattern2(vec2 p, int ch) {
	vec4 a = texture(detail_tex, p);
	vec4 b = texture(detail_tex, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 0.37 + 0.31);
	return mix(a[ch], b[ch], 0.35);
}

void fragment() {
	vec3 wp = world_pos;
	float dist = length(wp - CAMERA_POSITION_WORLD);
	vec2 uv = world_uv(wp.xz);
	float near = (1.0 - smoothstep(detail_distance * 0.55, detail_distance, dist)) * detail_strength;

	vec3 n = has_world ? terrain_normal(wp.xz, uv, dist) : vec3(0.0, 1.0, 0.0);
	// layer selection uses a ~16 m blurred slope so terraced talus slopes do not flip between
	// rock and soil every few metres (contour banding); lighting keeps the sharp normal
	float slope = has_world ? soft_slope : 0.0;

	// world-space macro variation ("brush strokes" at several scales)
	vec4 nz_big = texture(noise_tex, wp.xz * (1.0 / 900.0));
	vec4 nz_mid = texture(noise_tex, wp.xz * (1.0 / 140.0) + 0.37);
	vec4 nz_sml = texture(noise_tex, wp.xz * (1.0 / 23.0) + 0.71);
	float macro = nz_big.r * 0.55 + nz_mid.r * 0.45;
	float edge_n = nz_sml.r - 0.5 + (nz_mid.b - 0.5) * 0.5;

	vec4 sp = has_world ? texture(splat_map, uv) : vec4(0.0, 0.0, 0.7, 0.0);
	vec4 gr = has_world ? texture(ground_map, uv) : vec4(0.0);
	float road = has_world ? texture(road_map, uv).r : 0.0;
	vec4 rw = has_world ? region_weights(wp.xz + (nz_mid.rg - 0.5) * 24.0) : vec4(0, 1, 0, 0);
	vec4 lushv;
	vec4 flags;
	if (has_world) {
		biome_weights(wp.xz + (nz_sml.gr - 0.5) * 5.0, lushv, flags);
	} else {
		lushv = vec4(1, 0, 0, 0);
		flags = vec4(0.0);
	}

	// --- detail patterns (near) -----------------------------------------------------------
	vec2 pxz = wp.xz;
	float p_grass = 0.5;
	float p_rock = 0.5;
	float p_pave = 0.5;
	float p_rip = 0.5;
	vec2 dn_grass = vec2(0.0);
	vec2 dn_rock = vec2(0.0);
	vec2 dn_pave = vec2(0.0);
	vec2 dn_rip = vec2(0.0);
	float tri = smoothstep(0.30, 0.55, slope);
	vec3 tri_w = pow(abs(n), vec3(4.0));
	tri_w /= (tri_w.x + tri_w.y + tri_w.z);
	if (near > 0.001) {
		p_grass = pattern2(pxz * (1.0 / 2.6), 1);
		p_pave = texture(detail_tex, pxz * (1.0 / 3.4)).b;
		p_rip = pattern2(pxz * (1.0 / 5.0), 3);
		vec4 na = texture(detail_nrm_a, pxz * (1.0 / 2.6));
		vec4 nb = texture(detail_nrm_b, pxz * (1.0 / 3.4));
		dn_grass = (na.ba * 2.0 - 1.0);
		dn_pave = (nb.rg * 2.0 - 1.0);
		dn_rip = (texture(detail_nrm_b, pxz * (1.0 / 5.0)).ba * 2.0 - 1.0);
		if (tri > 0.01) {
			// triplanar rock on cliffs: project on the three axes
			float rx = texture(detail_tex, wp.zy * (1.0 / 6.0)).r;
			float ry = texture(detail_tex, wp.xz * (1.0 / 6.0)).r;
			float rz = texture(detail_tex, wp.xy * (1.0 / 6.0)).r;
			p_rock = rx * tri_w.x + ry * tri_w.y + rz * tri_w.z;
			vec2 nx = texture(detail_nrm_a, wp.zy * (1.0 / 6.0)).rg * 2.0 - 1.0;
			vec2 ny = texture(detail_nrm_a, wp.xz * (1.0 / 6.0)).rg * 2.0 - 1.0;
			vec2 nzv = texture(detail_nrm_a, wp.xy * (1.0 / 6.0)).rg * 2.0 - 1.0;
			// perturb in world space per projection (x: zy plane, y: xz plane, z: xy plane)
			vec3 pert = vec3(0.0, nx.y, nx.x) * tri_w.x + vec3(ny.x, 0.0, ny.y) * tri_w.y + vec3(nzv.x, nzv.y, 0.0) * tri_w.z;
			dn_rock = pert.xz;
			n = normalize(n + pert * 0.55 * near * tri);
		} else {
			p_rock = pattern2(pxz * (1.0 / 6.0), 0);
			dn_rock = texture(detail_nrm_a, pxz * (1.0 / 6.0)).rg * 2.0 - 1.0;
		}
		p_grass = mix(0.5, p_grass, near);
		p_rock = mix(0.5, p_rock, near);
		p_pave = mix(0.5, p_pave, near);
		p_rip = mix(0.5, p_rip, near);
	}
	// mid-distance cliff streaks (erosion gullies running downhill) keep cliffs readable when
	// the fine pattern has faded; gentle rock only gets the macro variation
	float streak = texture(noise_tex, vec2((wp.x + wp.z) * (1.0 / 55.0), wp.y * (1.0 / 420.0))).b;
	float strata = mix(0.5, streak, tri * 0.8);

	// --- palettes ----------------------------------------------------------------------------
	vec3 grass_d = pal4(GRASS_D[0], GRASS_D[1], GRASS_D[2], GRASS_D[3], rw);
	vec3 grass_l = pal4(GRASS_L[0], GRASS_L[1], GRASS_L[2], GRASS_L[3], rw);
	// lush variants: forest floor, farmland crops, tundra moss
	vec3 forest_d = mix(vec3(0.13, 0.21, 0.10), vec3(0.05, 0.20, 0.09), rw.z);
	vec3 forest_l = mix(vec3(0.30, 0.37, 0.17), vec3(0.15, 0.35, 0.13), rw.z);
	vec3 tundra_d = vec3(0.47, 0.47, 0.37);
	vec3 tundra_l = vec3(0.66, 0.64, 0.50);
	float lsum = max(lushv.x + lushv.y + lushv.z + lushv.w, 1e-3);
	vec3 lush_d = (grass_d * (lushv.x + lushv.z) + forest_d * lushv.y + tundra_d * lushv.w) / lsum;
	vec3 lush_l = (grass_l * (lushv.x + lushv.z) + forest_l * lushv.y + tundra_l * lushv.w) / lsum;
	// warm/cool macro hue drift of vegetation
	lush_d = mix(lush_d, lush_d * vec3(1.12, 1.0, 0.78), smoothstep(0.35, 0.8, nz_big.r) * 0.6);
	lush_l = mix(lush_l, lush_l * vec3(1.10, 1.02, 0.80), smoothstep(0.4, 0.85, nz_big.r) * 0.7);
	vec3 rock_d = pal4(ROCK_D[0], ROCK_D[1], ROCK_D[2], ROCK_D[3], rw);
	vec3 rock_l = pal4(ROCK_L[0], ROCK_L[1], ROCK_L[2], ROCK_L[3], rw);
	vec3 soil = pal4(SOIL[0], SOIL[1], SOIL[2], SOIL[3], rw);
	vec3 sand = pal4(SAND[0], SAND[1], SAND[2], SAND[3], rw);
	vec3 volc_sand = vec3(0.21, 0.19, 0.20);
	sand = mix(sand, volc_sand, clamp(flags.z * 1.5, 0.0, 1.0));
	soil = mix(soil, vec3(0.30, 0.26, 0.25), flags.z);
	vec3 pave = pal4(PAVE[0], PAVE[1], PAVE[2], PAVE[3], rw);

	// --- layer composition ---------------------------------------------------------------------
	// soil / dry ground
	vec3 col = soil * (0.86 + 0.24 * macro) * (0.92 + 0.16 * p_rip);
	// lush (grass / forest floor / tundra), height-blended with the grass strokes
	float w_lush = clamp(sp.b * 1.25 + (p_grass - 0.5) * 0.45 + edge_n * 0.25, 0.0, 1.0);
	w_lush = smoothstep(0.25, 0.6, w_lush);
	vec3 lush = wc_ramp(lush_d, lush_l, p_grass * 0.3 + macro * 0.7, 0.5, 0.36);
	col = mix(col, lush, w_lush);
	// farmland: patchwork of plots (gold / green / fallow) with furrows close up
	float farm = clamp(gr.b + lushv.z * 0.6, 0.0, 1.0) * (1.0 - flags.y);
	if (farm > 0.01) {
		vec2 plot = floor((wp.xz + (nz_mid.rg - 0.5) * 18.0) / vec2(46.0, 34.0));
		float ph = wc_hash12(plot);
		vec3 crop = ph < 0.38 ? vec3(0.80, 0.70, 0.36) : (ph < 0.74 ? vec3(0.50, 0.63, 0.26) : (ph < 0.92 ? vec3(0.64, 0.71, 0.33) : vec3(0.68, 0.58, 0.40)));
		crop *= 0.94 + 0.12 * wc_hash12(plot + 3.0);
		vec2 fdir = wc_hash12(plot + 7.0) < 0.5 ? vec2(0.94, 0.34) : vec2(-0.34, 0.94);
		float furrow = sin(dot(wp.xz, fdir) * 2.3) * 0.5 + 0.5;
		crop *= mix(1.0, 0.82 + 0.26 * furrow, near * 0.9 + 0.1);
		// darker field borders (hedges / paths)
		vec2 fp = fract((wp.xz + (nz_mid.rg - 0.5) * 18.0) / vec2(46.0, 34.0));
		float border = 1.0 - smoothstep(0.0, 0.035, min(min(fp.x, 1.0 - fp.x), min(fp.y, 1.0 - fp.y)));
		crop = mix(crop, lush_d, border * 0.55);
		col = mix(col, crop, smoothstep(0.25, 0.6, farm));
	}
	// sand / black sand / ash
	float w_sand = smoothstep(0.25, 0.6, sp.a + (p_rip - 0.5) * 0.3 + edge_n * 0.2);
	vec3 sand_c = sand * (0.88 + 0.2 * p_rip) * (0.92 + 0.12 * macro);
	col = mix(col, sand_c, w_sand);
	// rock & cliffs (splat rock + steep slopes), height-blended with the rock pattern
	float slope_rock = smoothstep(0.18, 0.42, slope + edge_n * 0.1);
	float w_rock = max(sp.g, slope_rock);
	w_rock = smoothstep(0.35, 0.65, w_rock + (p_rock - 0.5) * 0.5 + edge_n * 0.15);
	float rock_v = mix(strata, p_rock, near * 0.75) * 0.7 + macro * 0.3;
	vec3 rock = wc_ramp(rock_d, rock_l, rock_v, 0.48, 0.3);
	// darker crevices, lighter top faces (painterly modelling)
	rock *= 0.88 + 0.24 * smoothstep(0.55, 0.95, 1.3 - slope);
	col = mix(col, rock, w_rock);
	// roads: dirt tracks and paved roads (stone flags)
	float w_road = smoothstep(0.3, 0.75, road + edge_n * 0.15);
	if (w_road > 0.001) {
		float paved = smoothstep(0.35, 0.6, gr.r);
		vec3 dirt = mix(vec3(0.50, 0.40, 0.28), vec3(0.67, 0.56, 0.41), p_rip * 0.6 + macro * 0.4);
		vec3 flag = pave * mix(0.82, 1.04, p_pave) * (0.92 + 0.1 * macro);
		col = mix(col, mix(dirt, flag, paved), w_road);
		n = normalize(n + vec3(dn_pave.x, 0.0, dn_pave.y) * 0.35 * near * paved * w_road);
	}
	// settlement paving / temple stone
	float w_pave = clamp(gr.g * 0.9 + flags.y * 0.9, 0.0, 1.0);
	w_pave = smoothstep(0.3, 0.65, w_pave + edge_n * 0.1);
	if (w_pave > 0.001) {
		vec3 stone = pave * mix(0.86, 1.03, p_pave) * (0.93 + 0.09 * macro);
		col = mix(col, stone, w_pave);
		n = normalize(n + vec3(dn_pave.x, 0.0, dn_pave.y) * 0.22 * near * w_pave);
	}
	// ground normal detail (grass / ripples) where not rock
	if (tri < 0.01) {
		n = normalize(n + vec3(dn_rock.x, 0.0, dn_rock.y) * 0.45 * near * w_rock);
	}
	// glacier / sea ice
	float w_ice = smoothstep(0.3, 0.7, flags.x);
	vec3 ice = mix(vec3(0.48, 0.70, 0.86), vec3(0.78, 0.90, 0.97), smoothstep(0.3, 0.8, p_rip * 0.4 + macro * 0.6));
	col = mix(col, ice, w_ice);
	// snow: a crisp layer that settles in rock crevices first, thins on steep faces
	float snow_raw = sp.r + edge_n * 0.14 + world_snow_cover * 0.4 * smoothstep(0.55, 0.85, n.y);
	snow_raw -= (p_rock - 0.5) * 0.35 * w_rock + smoothstep(0.45, 0.75, slope) * 0.18;
	float w_snow = smoothstep(0.16, 0.40, snow_raw);
	vec3 snow = mix(vec3(0.85, 0.90, 0.98), vec3(0.97, 0.98, 1.0), smoothstep(0.25, 0.85, macro * 0.8 + p_rip * 0.2));
	float rough = mix(0.92, 0.95, w_rock);
	float spec = 0.12;
	// --- snow trail (footprints / landings) -----------------------------------------------------
	vec4 tr = vec4(0.0);
	vec2 tgrad = vec2(0.0);
	if (w_snow > 0.01) {
		trail_fragment(wp.xz, tr, tgrad);
		if (tr.a > 0.0) {
			vec3 packed = vec3(0.58, 0.68, 0.86);
			snow = mix(snow, packed, smoothstep(0.02, 0.45, tr.r) * 0.8 * tr.a);
			snow *= 1.0 + tr.g * 0.06 * tr.a;
			float lumps = smoothstep(0.5, 0.8, texture(detail_tex, wp.xz * 1.7).g);
			snow = mix(snow, vec3(0.99, 1.0, 1.0), tr.b * lumps * 0.5 * tr.a);
			n = normalize(n + vec3(-tgrad.x, 0.0, -tgrad.y) * w_snow);
		}
	}
	col = mix(col, snow, w_snow);
	// wind-packed snow: only a whisper of the ripple relief, broad soft undulation instead
	// ground relief (sand ripples / grass strokes) only where no snow lies on top; snow gets a
	// faint wind-packed relief instead
	vec2 soft_dn = mix(dn_rip, dn_grass, w_lush) * (1.0 - w_rock) * (1.0 - w_pave) * (1.0 - w_snow);
	n = normalize(n + vec3(soft_dn.x, 0.0, soft_dn.y) * 0.16 * near);
	n = normalize(n + vec3(dn_rip.x, 0.0, dn_rip.y) * 0.04 * near * w_snow);
	rough = mix(rough, 0.6, w_snow);
	spec = mix(spec, 0.5, w_snow);
	rough = mix(rough, 0.25, w_ice);
	spec = mix(spec, 0.8, w_ice);
	// wetness: drainage lines / shores and rain
	float wet = clamp(gr.a * 0.6 + world_wetness * (1.0 - w_snow) * smoothstep(0.4, 0.9, n.y), 0.0, 1.0);
	col *= 1.0 - wet * 0.32;
	rough = mix(rough, 0.35, wet * (1.0 - w_snow));
	spec = mix(spec, 0.6, wet * (1.0 - w_snow));

	ALBEDO = wc_lin(clamp(col, 0.0, 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = spec;
	// snow sparkle: tiny sparse glints that change with the view (consumed in light())
	float glint = 0.0;
	if (w_snow > 0.01 && dist < 30.0) {
		vec2 gp = wp.xz * 38.0;
		vec2 gc = floor(gp);
		vec2 gf = fract(gp) - 0.5 - (wc_hash22(gc) - 0.5) * 0.6;
		float on = step(0.992, wc_hash12(gc + floor(dot(VIEW, vec3(9.0, 5.0, 7.0)) * 3.0)));
		glint = on * smoothstep(0.16, 0.0, length(gf)) * (1.0 - smoothstep(12.0, 30.0, dist)) * w_snow;
	}
	BACKLIGHT = vec3(glint);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// painterly wrap: soft terminator band, slightly lifted shadow side
	float diff = smoothstep(-0.06, 0.45, ndl);
	diff = mix(diff, clamp(ndl, 0.0, 1.0), 0.45);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float gloss = 1.0 - ROUGHNESS;
	float sp = pow(max(dot(NORMAL, h), 0.0), mix(6.0, 220.0, gloss * gloss)) * gloss * gloss;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (sp * SPECULAR_AMOUNT * 0.5 + BACKLIGHT.r * 1.6 * step(0.0, ndl)) / PI;
}
