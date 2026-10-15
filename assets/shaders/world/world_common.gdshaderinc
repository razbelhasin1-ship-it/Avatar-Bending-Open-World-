// Shared helpers for the world shaders (terrain, water, clouds, weather).
// Hash/noise functions are cheap ALU versions; tiling textures live in assets/textures/world.

float wc_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 wc_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float wc_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(wc_hash12(i), wc_hash12(i + vec2(1.0, 0.0)), u.x),
			mix(wc_hash12(i + vec2(0.0, 1.0)), wc_hash12(i + vec2(1.0)), u.x), u.y);
}

// sRGB-authored palette colour to linear.
vec3 wc_lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

float wc_luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Painterly two-tone ramp: dark -> light with a soft band around `mid`.
vec3 wc_ramp(vec3 dark, vec3 light, float v, float mid, float soft) {
	return mix(dark, light, smoothstep(mid - soft, mid + soft, v));
}

// Height-aware blend weight sharpening (classic height blend): returns the new weight of a
// layer given its base weight and pattern height, against the max of the competing layers.
float wc_hblend(float w, float h, float depth) {
	return w * (1.0 + h * depth);
}
