// perf_polish: the ink outline pass (assets/shaders/outline.gdshader) with the same screen-door
// fade as toon_dither.gdshader, so a faded occluder's outline fades with it.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, blend_mix;

uniform vec4 outline_color : source_color = vec4(0.07, 0.055, 0.06, 1.0);
// Width in "screen-ish" units; 1.0 ≈ 1.5 px at 1080p.
uniform float width = 1.0;
uniform float max_distance = 60.0;
uniform float dither_fade : hint_range(0.0, 1.0) = 0.0;

float occlusion_bayer4(vec2 fc) {
	int i = (int(mod(fc.y, 4.0)) * 4) + int(mod(fc.x, 4.0));
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = -view_pos.z;
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fade = 1.0 - smoothstep(max_distance * 0.6, max_distance, dist);
	float w = width * 0.0024 * clamp(dist, 0.5, max_distance) * fade;
	view_pos.xyz += view_n * w;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	if (dither_fade > 0.001 && occlusion_bayer4(FRAGCOORD.xy) < dither_fade) {
		discard;
	}
	ALBEDO = outline_color.rgb;
}
