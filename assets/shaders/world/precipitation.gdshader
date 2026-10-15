// Precipitation particles (snow, blizzard, rain, ash) that live in a box wrapped around the
// camera: they never run out or pile up when the camera moves, drift with the global wind,
// and hide below the terrain (no snow falling inside hills). Draw pass: precipitation_draw.
shader_type particles;
render_mode disable_velocity;

#include "res://src/world/data/world_height.gdshaderinc"

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wind_gust;

uniform vec3 camera_pos = vec3(0.0);
uniform vec3 box_size = vec3(40.0, 24.0, 40.0);
uniform float fall_speed = 1.2;
// how much of the wind velocity the particle follows (snow 1, rain 0.35)
uniform float wind_follow = 1.0;
uniform float turbulence = 0.6;
// streak length factor along velocity (0 = round flake)
uniform float streak = 0.0;
uniform float size_min = 0.03;
uniform float size_max = 0.06;
uniform vec4 tint : source_color = vec4(1.0);
// fraction of particles that are glowing embers (ash fall)
uniform float ember_fraction = 0.0;
uniform bool has_world = true;

float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

uint hash_u(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

vec3 wind_vel() {
	return vec3(wind_direction.x, 0.0, wind_direction.y) * wind_strength * (1.0 + wind_gust * 0.6) * wind_follow;
}

void start() {
	uint seed = hash_u(NUMBER + RANDOM_SEED);
	vec3 r = vec3(rand_from_seed(seed), rand_from_seed(seed), rand_from_seed(seed));
	TRANSFORM[3].xyz = camera_pos + (r - 0.5) * box_size;
	float size = mix(size_min, size_max, rand_from_seed(seed));
	CUSTOM = vec4(size, rand_from_seed(seed) * 6.2831853, rand_from_seed(seed), 0.0);
	VELOCITY = vec3(0.0, -fall_speed * mix(0.75, 1.25, rand_from_seed(seed)), 0.0);
	COLOR = tint;
	if (rand_from_seed(seed) < ember_fraction) {
		COLOR = vec4(3.2, 1.1, 0.25, 1.0);
		CUSTOM.w = 1.0;
	}
}

void process() {
	vec3 pos = TRANSFORM[3].xyz;
	float phase = CUSTOM.y + TIME * (1.0 + CUSTOM.z);
	vec3 sway = vec3(sin(phase), 0.0, cos(phase * 0.8)) * turbulence;
	vec3 vel = VELOCITY + wind_vel() + sway;
	pos += vel * DELTA;
	// wrap around the camera box
	vec3 rel = pos - camera_pos;
	rel = mod(rel + box_size * 0.5, box_size) - box_size * 0.5;
	pos = camera_pos + rel;
	// fade near the box faces so wrapping never pops, and below the terrain
	vec3 edge = 1.0 - smoothstep(vec3(0.38), vec3(0.5), abs(rel) / box_size);
	float fade = edge.x * edge.y * edge.z;
	if (has_world && pos.y < world_height(pos.xz) - 0.1) {
		fade = 0.0;
	}
	float size = CUSTOM.x;
	vec3 axis = streak > 0.0 ? normalize(vel) * max(length(vel) * streak, size) : vec3(0.0, size, 0.0);
	TRANSFORM[0] = vec4(size, 0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(axis, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, size, 0.0);
	TRANSFORM[3] = vec4(pos, 1.0);
	vec4 base = CUSTOM.w > 0.5 ? vec4(3.2, 1.1 + 0.4 * sin(phase * 3.0), 0.25, 1.0) : tint;
	COLOR = vec4(base.rgb, base.a * fade);
}
