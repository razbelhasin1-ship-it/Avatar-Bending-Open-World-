// Shared code for creature shaders: the project toon light model (mirrors
// assets/shaders/toon.gdshader so creatures sit beside characters and props),
// per-instance hit flash / status overlay, and analytic marking bands.
//
// Marking bands (crisp at any distance, no texture resolution limits):
// MeshKit writes UV = (u around the section, part_row + v along the part). The marking
// texture holds one row per part; per texel along v:
//   R = half width of the dorsal band  (centered at u = 0, top)
//   G = half width of the ventral band (centered at u = 0.5, belly)
//   B = half width of the lateral pair (centered at u = 0.5 -+ A ... see below)
//   A = distance of the lateral pair centers from the top (u units, 0..0.5)

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade_tint : source_color = vec4(0.62, 0.58, 0.78, 1.0);
uniform float band_softness : hint_range(0.0, 0.5) = 0.06;
uniform float band_offset : hint_range(-0.5, 0.5) = 0.05;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_width : hint_range(0.0, 1.0) = 0.55;
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float specular_strength : hint_range(0.0, 2.0) = 0.08;
uniform float specular_size : hint_range(0.0, 1.0) = 0.12;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;
// Light passing through thin parts (wing membranes, ears) when lit from behind.
uniform float translucency : hint_range(0.0, 2.0) = 0.0;
uniform vec4 translucency_color : source_color = vec4(1.0, 0.45, 0.2, 1.0);

uniform sampler2D mark_tex : filter_linear, repeat_disable, hint_default_black;
uniform float mark_rows = 1.0;
uniform vec4 mark_color0 : source_color = vec4(0.42, 0.27, 0.16, 1.0);
uniform vec4 mark_color1 : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform vec4 mark_color2 : source_color = vec4(0.9, 0.88, 0.82, 1.0);
uniform float mark_soft : hint_range(0.0, 0.05) = 0.004;

// Per-instance gameplay overlays (one MeshInstance3D per creature).
// Explicit indices keep the layout identical across every creature shader.
instance uniform vec4 status_color : source_color, instance_index(0) = vec4(0.6, 0.85, 1.0, 1.0);
instance uniform float status_amount : hint_range(0.0, 1.0), instance_index(1) = 0.0;
instance uniform float hit_flash : hint_range(0.0, 1.0), instance_index(2) = 0.0;

// Returns the band masks (dorsal, ventral, lateral) at a UV.
vec3 creature_mark_mask(vec2 uv) {
	float row = floor(uv.y);
	float v = uv.y - row;
	vec4 mk = texture(mark_tex, vec2(v, (row + 0.5) / max(mark_rows, 1.0)));
	float aa = max(fwidth(uv.x) * 0.75, mark_soft);
	float u = uv.x;
	float d0 = abs(fract(u + 0.5) - 0.5);
	float d1 = abs(u - 0.5);
	float d2 = min(abs(u - mk.a), abs(u - (1.0 - mk.a)));
	vec3 d = vec3(d0, d1, d2);
	vec3 w = mk.rgb;
	return (1.0 - smoothstep(w - aa, w + aa, d)) * step(vec3(0.0005), w);
}

vec3 creature_apply_marks(vec3 c, vec3 m) {
	c = mix(c, mark_color1.rgb, m.y);
	c = mix(c, mark_color2.rgb, m.z);
	c = mix(c, mark_color0.rgb, m.x);
	return c;
}

vec3 creature_status(vec3 c) {
	return mix(c, status_color.rgb, status_amount * 0.6);
}

vec3 creature_flash() {
	return vec3(1.0, 0.95, 0.9) * hit_flash * 1.5;
}

float creature_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 creature_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float creature_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = creature_hash12(i);
	float b = creature_hash12(i + vec2(1.0, 0.0));
	float c = creature_hash12(i + vec2(0.0, 1.0));
	float d = creature_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_softness, band_softness, ndl + band_offset);
	lit *= smoothstep(0.0, 0.25, ATTENUATION);
	vec3 shade = mix(shade_tint.rgb * 0.35, vec3(1.0), lit);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * shade;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(1.0 - specular_size * 0.2 - 0.01, 1.0 - specular_size * 0.2 + 0.01, dot(NORMAL, h));
	SPECULAR_LIGHT += LIGHT_COLOR / PI * spec * specular_strength * lit;
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.12, 1.0 - max(dot(NORMAL, VIEW), 0.0));
	SPECULAR_LIGHT += LIGHT_COLOR / PI * rim * rim_strength * rim_color.rgb * max(lit, 0.25) * ALBEDO;
	if (translucency > 0.0) {
		float back = max(0.0, -ndl) * smoothstep(0.0, 0.25, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * translucency_color.rgb * translucency * back;
	}
}
