// Inverted-hull ink outline for creatures (same look as assets/shaders/outline.gdshader)
// with an extra `push` so the line can sit in the middle of shell fur instead of
// hugging the skin. Vertex COLOR.a (fur amount) scales the push.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, blend_mix;

uniform vec4 outline_color : source_color = vec4(0.07, 0.055, 0.06, 1.0);
// Width in "screen-ish" units; 1.0 ~ 1.5 px at 1080p.
uniform float width = 1.0;
uniform float max_distance = 90.0;
// Extra offset in meters along the normal (fur).
uniform float push = 0.0;
// Must match the skin material's mane flutter so the line follows the hair.
uniform float flutter = 0.0;
uniform float flutter_freq = 2.2;

void vertex() {
	vec3 v = VERTEX + NORMAL * push * COLOR.a;
	if (flutter > 0.0) {
		float ph = TIME * flutter_freq + UV2.y * 2.5 + UV.x * 6.2831;
		v += (NORMAL * sin(ph) + vec3(0.0, 0.35, 0.0) * sin(ph * 0.7 + 1.3)) * flutter * COLOR.a;
	}
	vec4 view_pos = MODELVIEW_MATRIX * vec4(v, 1.0);
	float dist = -view_pos.z;
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fade = 1.0 - smoothstep(max_distance * 0.6, max_distance, dist);
	float w = width * 0.0024 * clamp(dist, 0.5, max_distance) * fade;
	view_pos.xyz += view_n * w;
	POSITION = PROJECTION_MATRIX * view_pos;
}

// Screen-door fade while it occludes the player (perf_polish OccluderFader), same slot as the
// skin shaders (creature_common.gdshaderinc).
instance uniform float occlusion_fade : hint_range(0.0, 1.0), instance_index(3) = 0.0;

float creature_bayer4(vec2 fc) {
	int i = (int(mod(fc.y, 4.0)) * 4) + int(mod(fc.x, 4.0));
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	if (occlusion_fade > 0.001 && creature_bayer4(FRAGCOORD.xy) < occlusion_fade) {
		discard;
	}
	ALBEDO = outline_color.rgb;
}
