// Shared vegetation helpers: world wind (globals from WorldShaderGlobals), per-instance distance
// LOD (dithered by a per-instance random so near trees hand over to far impostors tree by tree),
// toon lighting. Used with `render_mode world_vertex_coords` on MultiMesh instances whose
// INSTANCE_CUSTOM = (tint.rgb, random 0..1).
//
// Vertex attributes (GeoBuilder): COLOR.rgb albedo, COLOR.a tint mask (1 = takes the instance
// tint), UV.x sway weight (0 at the base .. 1 at tips), UV.y foliage weight (0 wood/rock .. 1
// leaves: flutter + translucency), UV2.x cap weight (snow/moss/ash colour of the material),
// UV2.y ember weight (glowing cracks). All weights interpolate linearly.

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wind_gust;
global uniform float wind_time;
global uniform float world_snow_cover;
global uniform float world_wetness;

// Per-instance distance band (metres from the MAIN camera, also in shadow passes).
// Hidden beyond fade_out_end (dithered over fade_band before it) ...
uniform float fade_out_end = 100000.0;
// ... and nearer than fade_in_end (0 = off), the complementary band for far impostors.
uniform float fade_in_end = 0.0;
uniform float fade_band = 24.0;
uniform float fade_in_band = 24.0;
// LOD1 materials cast the shadows of the near LOD0 trees too (LOD0 MultiMeshes do not cast):
// in shadow passes the fade-in (near) cut is ignored.
uniform bool shadow_ignores_fade_in = false;
// Instances farther than this from the camera cast no shadow (cheap distant forests).
uniform float shadow_max_distance = 100000.0;

// `cam` = MAIN_CAM_INV_VIEW_MATRIX[3].xyz (the player camera even in shadow passes),
// `view_pos` = INV_VIEW_MATRIX[3].xyz (differs from cam only in shadow passes).
float veg_rand_fade(vec3 origin, vec3 cam, vec3 view_pos, float rnd) {
	// returns > 0 when the instance is visible (value = shrink factor 0..1 within the band)
	float d = distance(origin, cam);
	float x_out = (d - (fade_out_end - fade_band)) / fade_band;
	float vis = clamp((rnd - x_out) * 6.0, 0.0, 1.0);
	bool shadow_pass = distance(view_pos, cam) > 0.5;
	if (shadow_pass && d > shadow_max_distance) {
		return 0.0;
	}
	if (fade_in_end > 0.0 && !(shadow_pass && shadow_ignores_fade_in)) {
		float x_in = (d - (fade_in_end - fade_in_band)) / fade_in_band;
		vis = min(vis, clamp((x_in - rnd) * 6.0, 0.0, 1.0));
	}
	return vis;
}

// Whole-tree sway + leaf flutter, in world space. `h` = metres above the instance origin.
vec3 veg_wind_offset(vec3 origin, vec3 wpos, float sway, float leaf, float rnd, float amount, float flutter_amt) {
	float ws = wind_strength * (1.0 + wind_gust * 0.8);
	float phase = dot(origin.xz, vec2(0.071, 0.053)) + rnd * 6.2831;
	float gust_wave = sin(wind_time * 0.35 + dot(origin.xz, wind_direction) * 0.02) * 0.5 + 0.5;
	float bend = (0.55 + 0.45 * sin(wind_time * 0.9 + phase)) * (0.6 + 0.4 * gust_wave);
	float k = sway * sway * amount * ws * 0.01;
	vec3 off = vec3(wind_direction.x, 0.0, wind_direction.y) * bend * k;
	off.y -= k * bend * 0.15;
	// flutter (leaves): small high-frequency motion per vertex position
	float f = sin(wind_time * 5.3 + dot(wpos, vec3(1.7, 2.3, 1.9)) + rnd * 13.0);
	off += vec3(f, f * 0.6, -f * 0.8) * leaf * flutter_amt * (0.3 + ws * 0.08) * sway;
	return off;
}

// Toon terminator shared by foliage and grass (matches assets/shaders/toon.gdshader).
// `fill` = shadow-side fill of this light: 1 for the sun, distance-attenuated for point lights.
vec3 veg_toon_shade(vec3 n, vec3 l, float atten, vec3 shade_tint, float softness, float offset, float fill) {
	float ndl = dot(n, l);
	float lit = smoothstep(-softness, softness, ndl + offset);
	lit *= smoothstep(0.0, 0.3, atten);
	return mix(shade_tint * 0.40 * fill, vec3(1.0), lit);
}
