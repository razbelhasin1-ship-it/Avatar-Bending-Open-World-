// Stylized world water (worldrender): camera-following ocean, lakes and canals.
// Gerstner swell (faded with distance and in the shallows), two scrolling capillary normal
// layers, splash ripples, depth colour from the heightmap water column and the scene depth
// (objects standing in water), refraction of the bed in shallows, fresnel sky reflection
// from the current sky palette (global uniforms), sharp sun glints, shoreline foam bands.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back;

#include "res://src/world/data/world_height.gdshaderinc"
#include "res://assets/shaders/world/water_common.gdshaderinc"

global uniform vec3 world_sun_direction;
global uniform vec4 world_sun_color;
global uniform vec4 world_sky_zenith;
global uniform vec4 world_sky_horizon;
global uniform vec4 world_fog_color;

uniform vec3 shallow_color : source_color = vec3(0.20, 0.62, 0.64);
uniform vec3 deep_color : source_color = vec3(0.03, 0.16, 0.30);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
uniform float depth_scale = 7.0;
uniform float foam_depth = 0.7;
uniform float reflect_strength = 0.85;
uniform float normal_strength = 0.55;
uniform float wave_fade_distance = 700.0;
uniform bool has_world = true;
// canals/lakes: no swell, flow from vertex COLOR (rg = direction * 0.5 + 0.5, b = speed)
uniform bool inland = false;
uniform bool use_screen = true;
uniform sampler2D water_nrm : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 world_pos;
varying float level;
varying float amp_mask;
varying vec2 flow;

// Bed height under the water; beyond the baked square the sea floor keeps sloping down.
float bed_height(vec2 xz) {
	if (!has_world) {
		return -30.0;
	}
	vec2 inside = clamp(xz, vec2(WH_ORIGIN + 1.0), vec2(-WH_ORIGIN - 1.0));
	return world_height(inside) - length(xz - inside) * 0.3;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	level = wp.y;
	flow = inland ? (COLOR.rg * 2.0 - 1.0) * COLOR.b : vec2(0.0);
	float dist = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float depth = level - bed_height(wp.xz);
	amp_mask = inland ? 0.0 : (1.0 - smoothstep(wave_fade_distance * 0.45, wave_fade_distance, dist)) * smoothstep(0.3, 6.0, depth);
	if (amp_mask > 0.0) {
		wp += gerstner(wp.xz, amp_mask);
	}
	VERTEX = wp - MODEL_MATRIX[3].xyz;
	world_pos = wp;
}

void fragment() {
	vec3 wp = world_pos;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 to_cam = cam - wp;
	float dist = length(to_cam);
	vec3 V = to_cam / dist;
	float depth = level - bed_height(wp.xz);

	// --- normal ---
	vec3 n = amp_mask > 0.0 ? gerstner_normal(wp.xz, amp_mask) : vec3(0.0, 1.0, 0.0);
	vec2 wdir = normalize(wind_direction + vec2(1e-4, 0.0));
	vec2 drift = inland ? flow * world_time * 0.25 : wdir * world_time * (0.03 + wind_strength * 0.004);
	vec2 uv1 = wp.xz / 7.0 + drift;
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * wp.xz / 17.0 - drift * 0.6;
	vec2 dn = (texture(water_nrm, uv1).rg * 2.0 - 1.0) + (texture(water_nrm, uv2).rg * 2.0 - 1.0) * 0.8;
	float near = 1.0 - smoothstep(30.0, 420.0, dist);
	float chop = inland ? 0.45 : 1.0;
	n = normalize(n + vec3(dn.x, 0.0, dn.y) * normal_strength * chop * mix(0.18, 1.0, near));
	vec3 rip = ripple_field(wp.xz);
	n = normalize(n + vec3(rip.x, 0.0, rip.y));
	float ndv = max(dot(n, V), 0.0);

	// --- water column / scene depth ---
	float thickness = max(depth, 0.0) / max(V.y, 0.12);
	float edge = 1.0;
	if (use_screen) {
		float zd = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, zd) * 2.0 - 1.0;
#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, zd);
#endif
		vec4 vpos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		vpos.xyz /= vpos.w;
		float behind = max(-vpos.z - (-VERTEX.z), 0.0);
		thickness = min(thickness, behind);
		edge = smoothstep(0.0, 0.25, behind);
	}
	float absorb = 1.0 - exp(-thickness / depth_scale);
	float deep_t = 1.0 - exp(-max(depth, 0.0) / (depth_scale * 2.5));

	// --- body colour, lit by sun + sky ---
	vec3 sun_dir = normalize(world_sun_direction);
	vec3 sun_col = world_sun_color.rgb;
	vec3 sky_z = world_sky_zenith.rgb;
	vec3 sky_h = world_sky_horizon.rgb;
	vec3 ambient = mix(sky_h, sky_z, 0.55);
	vec3 body = mix(shallow_color, deep_color, max(absorb, deep_t));
	vec3 light = ambient * 0.85 + sun_col * clamp(sun_dir.y + 0.1, 0.0, 1.0) * 0.32;
	vec3 col = body * light;
	// subsurface glow through wave crests facing the sun
	float sss = pow(max(dot(-V, sun_dir) * 0.5 + 0.5, 0.0), 3.0) * clamp(n.y * 0.5 + 0.2, 0.0, 1.0);
	col += shallow_color * sun_col * sss * 0.18 * (1.0 - deep_t * 0.5);
	if (use_screen) {
		vec2 ruv = SCREEN_UV + n.xz * 0.035 * clamp(thickness / 2.5, 0.0, 1.0) * near;
		vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
		vec3 tint = mix(vec3(1.0), shallow_color * 1.4, clamp(thickness / 1.5, 0.0, 1.0) * 0.7);
		col = mix(refr * tint, col, clamp(absorb * 1.15, 0.0, 1.0));
	}

	// --- reflection ---
	vec3 R = reflect(-V, n);
	float fres = 0.025 + 0.975 * pow(1.0 - ndv, 5.0);
	vec3 sky = mix(sky_h, sky_z, pow(clamp(R.y, 0.0, 1.0), 0.55));
	sky += sun_col * pow(max(dot(R, sun_dir), 0.0), 24.0) * 0.6;
	col = mix(col, sky, clamp(fres * reflect_strength, 0.0, 1.0));

	// --- sun glints (sharp, stylized) ---
	vec3 H = normalize(sun_dir + V);
	float nh = max(dot(n, H), 0.0);
	float glint = pow(nh, 900.0) * 40.0 + pow(nh, 90.0) * 0.6;
	col += sun_col * glint * smoothstep(-0.02, 0.05, sun_dir.y);

	// --- foam ---
	// lacy foam: small cells broken up by two drifting noise scales
	float fnoise = texture(noise_tex, wp.xz / 23.0 + drift * 0.2).r;
	float fbreak = texture(noise_tex, wp.xz / 5.5 - drift * 0.7).r;
	// fine lace, its cells warped by noise so no regular net shows
	float lace = texture(water_nrm, wp.xz / 0.95 + (vec2(fbreak, fnoise) - 0.5) * 0.9 + drift * 1.5).a;
	float ftex = lace * 0.3 + fbreak * 0.7;
	float shore = 1.0 - smoothstep(0.0, foam_depth, depth);
	// bands that run up the beach with the swell
	float bands = sin(depth * 5.5 - world_time * (inland ? 0.8 : 1.7) + fnoise * 5.0) * 0.5 + 0.5;
	float foam = shore * smoothstep(0.55, 0.85, ftex * 0.55 + bands * 0.5 + shore * 0.3);
	foam = max(foam, smoothstep(0.88, 1.0, shore + fnoise * 0.15));
	// whitecaps on steep crests in rough water
	if (!inland) {
		float crest = smoothstep(0.25, 0.7, (1.0 - n.y) * 6.0 * wave_params.x) * amp_mask;
		foam = max(foam, crest * smoothstep(0.5, 0.85, ftex));
	}
	// foam where objects stand in the water (scene depth)
	if (use_screen) {
		foam = max(foam, (1.0 - smoothstep(0.0, 0.45, thickness)) * smoothstep(0.35, 0.65, ftex + 0.2) * (1.0 - shore * 0.5));
	}
	foam = max(foam, clamp(rip.z * smoothstep(0.3, 0.7, ftex + 0.25), 0.0, 1.0));
	vec3 foam_lit = foam_color * (ambient * 0.9 + sun_col * clamp(sun_dir.y + 0.15, 0.0, 1.0) * 0.55);
	col = mix(col, foam_lit, clamp(foam, 0.0, 1.0) * 0.92);

	ALBEDO = col;
	float alpha = use_screen ? edge : mix(0.6, 0.97, max(absorb, deep_t));
	ALPHA = clamp(max(alpha, foam * 0.9) * smoothstep(-0.05, 0.02, depth), 0.0, 1.0);
}
