// Shared wave + ripple maths for the world water (ocean, lakes, canals).
// The Gerstner sum here is mirrored on the CPU by WaterWaves.height_at() (keep in sync).

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float world_time;

// wave_params: x amplitude scale (m), y choppiness, z wavelength scale, w speed scale
uniform vec4 wave_params = vec4(0.6, 0.7, 1.0, 1.0);
// splash ripples: xy = world x/z, z = start time (world_time), w = strength (0 = unused)
uniform vec4 ripples[16];

const int WAVE_COUNT = 4;
const float WAVE_LEN[4] = float[4](42.0, 23.0, 13.0, 7.5);
const float WAVE_AMP[4] = float[4](0.42, 0.24, 0.12, 0.06);
const float WAVE_ANGLE[4] = float[4](0.0, 0.55, -0.42, 1.1);

vec2 wave_dir(int i) {
	vec2 w = normalize(wind_direction + vec2(1e-4, 0.0));
	float a = WAVE_ANGLE[i];
	return vec2(w.x * cos(a) - w.y * sin(a), w.x * sin(a) + w.y * cos(a));
}

// Gerstner displacement (xyz) at world xz. `amp_mask` fades waves (distance, shallows).
vec3 gerstner(vec2 xz, float amp_mask) {
	vec3 d = vec3(0.0);
	for (int i = 0; i < WAVE_COUNT; i++) {
		float len = WAVE_LEN[i] * wave_params.z;
		float k = 6.2831853 / len;
		float c = sqrt(9.8 / k) * wave_params.w;
		vec2 dir = wave_dir(i);
		float a0 = max(WAVE_AMP[i] * wave_params.x, 1e-4);
		float f = k * (dot(dir, xz) - c * world_time);
		float q = min(wave_params.y / (k * a0 * float(WAVE_COUNT)), 1.0);
		d.xz += dir * (q * a0 * cos(f) * amp_mask);
		d.y += a0 * amp_mask * sin(f);
	}
	return d;
}

// Analytic normal of the Gerstner surface (world space).
vec3 gerstner_normal(vec2 xz, float amp_mask) {
	vec3 n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < WAVE_COUNT; i++) {
		float len = WAVE_LEN[i] * wave_params.z;
		float k = 6.2831853 / len;
		float c = sqrt(9.8 / k) * wave_params.w;
		vec2 dir = wave_dir(i);
		float a = WAVE_AMP[i] * wave_params.x * amp_mask;
		float f = k * (dot(dir, xz) - c * world_time);
		float wa = k * a;
		n.xz -= dir * (wa * cos(f));
	}
	return normalize(n);
}

// Expanding splash rings: returns (normal offset x, normal offset z, foam).
vec3 ripple_field(vec2 xz) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) {
			continue;
		}
		float t = world_time - r.z;
		if (t < 0.0 || t > 6.0) {
			continue;
		}
		vec2 dv = xz - r.xy;
		float dist = length(dv);
		float radius = t * (2.2 + r.w * 1.2);
		float band = dist - radius;
		float env = exp(-band * band * 0.9) * exp(-t * 0.65) * r.w;
		float wave = sin(band * 5.5) * env;
		vec2 dirv = dist > 1e-3 ? dv / dist : vec2(0.0);
		acc.xy += dirv * wave * 0.5;
		acc.z += env * smoothstep(0.6, 0.0, abs(band)) * 0.8 + smoothstep(1.2 + r.w, 0.0, dist) * exp(-t * 1.5) * r.w;
	}
	return acc;
}
