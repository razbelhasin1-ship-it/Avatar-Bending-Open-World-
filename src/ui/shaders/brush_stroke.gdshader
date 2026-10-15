// Procedural ink brush stroke filling its rect from left to right: a pressed, rounded
// head, a body with a slightly wandering centreline and ragged edges, and a dry tail where
// the bristles separate into streaks. `progress` reveals the stroke along its length
// (animated by BrushStroke); `seed` varies the shape per instance. No textures needed.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.91, 0.71, 0.32, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
// fraction of the rect height covered by the body
uniform float thickness : hint_range(0.05, 1.0) = 0.72;
// length fractions of the head swell and the dry tail
uniform float head : hint_range(0.0, 0.5) = 0.07;
uniform float tail : hint_range(0.0, 0.9) = 0.42;
uniform float dryness : hint_range(0.0, 1.0) = 0.65;
uniform float wobble : hint_range(0.0, 0.5) = 0.10;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
// ink density variation (darker pooling at the head)
uniform float pooling : hint_range(0.0, 1.0) = 0.35;
// mirror the stroke direction (tail on the left)
uniform bool flip = false;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + 17.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	if (flip) {
		uv.x = 1.0 - uv.x;
	}
	float x = uv.x;
	float s = seed * 13.17;
	// centreline wander
	float center = 0.5 + (fbm(vec2(x * 2.2 + s, s * 0.7)) - 0.5) * wobble * 2.0;
	// half thickness: rounded head, full body, tapering dry tail
	float h = thickness * 0.5;
	float head_t = clamp(x / max(head, 1e-3), 0.0, 1.0);
	h *= sqrt(1.0 - (1.0 - head_t) * (1.0 - head_t)) * 0.85 + 0.15 * step(0.001, head_t);
	float tail_t = smoothstep(1.0 - tail, 1.0, x);
	h *= 1.0 - tail_t * 0.72;
	h *= 1.0 + 0.08 * sin(x * 9.0 + s);
	// ragged edges, independent above/below the centreline
	float side = step(center, uv.y);
	float edge = fbm(vec2(x * 38.0 + s, side * 11.0 + s));
	h *= 1.0 - roughness * 0.22 + edge * roughness * 0.32;
	float d = abs(uv.y - center);
	float aa = max(fwidth(d), 1e-4) * 1.2;
	float body = 1.0 - smoothstep(h - aa, h + aa, d);
	// bristle streaks: long in x, fine in y (relative to the local thickness)
	float across = (uv.y - center) / max(h, 1e-3);
	float streak = vnoise(vec2(x * 3.0 + s, across * 7.0 + s * 3.0)) * 0.6 + vnoise(vec2(x * 7.0 - s, across * 17.0)) * 0.4;
	float dry = smoothstep(0.0, 1.0, tail_t * dryness * 1.35 + (1.0 - abs(across)) * 0.1 * dryness);
	float bristle = smoothstep(dry - 0.12, dry + 0.12, streak);
	float coverage = body * mix(1.0, bristle, step(0.001, dry));
	// small speckle gaps across the whole stroke (paper tooth)
	float tooth = smoothstep(0.08, 0.2, vnoise(UV * vec2(260.0, 60.0) + s));
	coverage *= mix(1.0, tooth, 0.35 * roughness);
	// reveal along the stroke with a soft leading edge
	float lead = progress * 1.12 - 0.06;
	float reveal = 1.0 - smoothstep(lead - 0.05, lead + 0.01, x);
	// ink density: darker where the brush pressed
	float dens = mix(1.0, 1.0 + pooling * 0.6, 1.0 - smoothstep(0.0, 0.3, x)) * mix(0.85, 1.0, edge);
	COLOR = vec4(tint.rgb * min(dens, 1.4), tint.a * coverage * reveal);
}
