// Sea of clouds below the Air Temple peaks: a slab of cloud between slab_bottom and slab_top
// rendered from one plane by marching a few samples along the view ray through the slab.
// Clouds thin out where the terrain rises into them (no hard intersections), fade at the
// edge of the region mask and are lit by the current sun/sky (global uniforms).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

#include "res://src/world/data/world_height.gdshaderinc"

global uniform vec3 world_sun_direction;
global uniform vec4 world_sun_color;
global uniform vec4 world_sky_zenith;
global uniform vec4 world_sky_horizon;
global uniform vec4 world_fog_color;
global uniform vec2 wind_direction;
global uniform float world_time;

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform float slab_bottom = 545.0;
uniform float slab_top = 625.0;
uniform vec2 region_center = vec2(2500.0, 3150.0);
uniform float region_radius = 2300.0;
uniform float coverage = 0.62;
uniform float opacity = 1.0;
uniform vec3 lit_tint : source_color = vec3(1.0, 0.99, 0.97);
uniform vec3 shade_tint : source_color = vec3(0.62, 0.68, 0.82);

varying vec3 world_pos;

// Cloud density at p. Explicit LOD (no implicit derivatives: this runs inside the march loop)
// and the terrain height under p is passed in so the sun-ward sample reuses it.
float density(vec3 p, float ground, float lod) {
	vec2 drift = wind_direction * world_time * 0.6;
	vec2 uv = (p.xz + drift) / 1400.0;
	float base = textureLod(cloud_tex, uv, lod).r * 0.6 + textureLod(cloud_tex, uv * 2.7 + 0.37, lod).g * 0.4;
	float detail = textureLod(cloud_tex, (p.xz - drift * 1.7) / 260.0, lod + 1.0).a;
	// billows are tallest in the middle of the slab
	float h = (p.y - slab_bottom) / (slab_top - slab_bottom);
	float profile = smoothstep(0.0, 0.35, h) * smoothstep(1.0, 0.55, h);
	float d = base * 0.78 + detail * 0.22 - (1.0 - coverage);
	d = d * 2.6 * profile - (1.0 - profile) * 0.25;
	// thin out near the terrain so peaks poke through cleanly
	d *= smoothstep(0.0, 45.0, p.y - ground);
	// regional mask with ragged edge
	float rm = length(p.xz - region_center) / region_radius + (textureLod(cloud_tex, p.xz / 3000.0, lod).b - 0.5) * 0.35;
	d *= 1.0 - smoothstep(0.75, 1.0, rm);
	return clamp(d, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(world_pos - cam);
	// segment of the view ray inside the slab
	float t0;
	float t1;
	if (abs(dir.y) < 1e-4) {
		t0 = 0.0;
		t1 = 0.0;
	} else {
		float ta = (slab_bottom - cam.y) / dir.y;
		float tb = (slab_top - cam.y) / dir.y;
		t0 = max(min(ta, tb), 0.0);
		t1 = max(ta, tb);
	}
	t1 = min(t1, t0 + 900.0);
	float seg = max(t1 - t0, 0.0);
	vec3 sun = normalize(world_sun_direction);
	float trans = 1.0;
	vec3 acc = vec3(0.0);
	vec3 sky_amb = mix(world_sky_horizon.rgb, world_sky_zenith.rgb, 0.5);
	const int STEPS = 6;
	// mip level from the footprint of a pixel at the slab distance (2.7 m per texel)
	float lod = clamp(log2(max(t0 / 700.0 / 2.7, 1.0)), 0.0, 7.0);
	// fixed trip count, no break/continue: uniform control flow on every backend
	for (int i = 0; i < STEPS; i++) {
		float t = t0 + seg * (float(i) + 0.5) / float(STEPS);
		vec3 p = cam + dir * t;
		float ground = world_height(p.xz);
		float d = density(p, ground, lod);
		// light: brighter towards the slab top and on the sun side (stepped, painterly)
		float h = clamp((p.y - slab_bottom) / (slab_top - slab_bottom), 0.0, 1.0);
		float d_sun = density(p + sun * 22.0, ground, lod);
		float lit = clamp(0.35 + h * 0.6 - d_sun * 0.55, 0.0, 1.0);
		lit = mix(lit, floor(lit * 3.0 + 0.5) / 3.0, 0.4);
		vec3 c = mix(shade_tint * sky_amb * 1.4, lit_tint * (world_sun_color.rgb * 0.75 + sky_amb * 0.55), lit);
		float a = clamp(d * seg / float(STEPS) * 0.045, 0.0, 1.0);
		acc += c * a * trans;
		trans *= 1.0 - a;
	}
	float alpha = (1.0 - trans) * opacity;
	// distance haze: far cloud sea melts into the horizon colour
	float dist = length(world_pos - cam);
	vec3 col = acc / max(1.0 - trans, 1e-3);
	col = mix(col, world_fog_color.rgb, smoothstep(1500.0, 7000.0, dist) * 0.7);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
