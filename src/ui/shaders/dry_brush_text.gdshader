// Dry-brush calligraphy for large brush glyphs (水善 土强 火烈 气和): erodes the glyph
// coverage with streaky noise running along a brush direction so strokes look painted on
// paper, with darker ink pooling inside the stroke. `reveal` wipes the glyph in.
shader_type canvas_item;

uniform vec4 ink : source_color = vec4(0.94, 0.89, 0.78, 1.0);
uniform float dryness : hint_range(0.0, 1.0) = 0.45;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform float glyph_height = 260.0;

varying vec2 local_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float cov = texture(TEXTURE, UV).a;
	vec2 p = local_pos / glyph_height;
	// streaks along a diagonal brush direction
	vec2 dir = normalize(vec2(1.0, 0.35));
	float along = dot(p, dir);
	float across = dot(p, vec2(-dir.y, dir.x));
	float streak = vnoise(vec2(along * 3.0 + seed, across * 60.0)) * 0.65 + vnoise(vec2(along * 9.0, across * 140.0 + seed)) * 0.35;
	float edge = smoothstep(0.15, 0.85, cov);
	float dry = smoothstep(dryness * 0.75, dryness * 0.75 + 0.2, streak + (cov - 0.6) * 0.8);
	float a = cov * mix(1.0, dry, dryness);
	// reveal top-left to bottom-right like a stroke being drawn
	float r = (p.x * 0.6 + p.y * 0.4);
	float rv = 1.0 - smoothstep(reveal * 1.4 - 0.15, reveal * 1.4, r + vnoise(p * 9.0 + seed) * 0.12);
	vec3 col = ink.rgb * mix(0.82, 1.0, streak);
	COLOR = vec4(col, a * rv * ink.a * COLOR.a);
}
