// Resource bar for the HUD (health / chi): ink-brushed fill with a ragged leading edge,
// a lighter "recent damage" trail, a lacquer track and a soft top sheen. Draw on a
// ColorRect sized to the bar.
shader_type canvas_item;

uniform float value : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_a : source_color = vec4(0.80, 0.20, 0.14, 1.0);
uniform vec4 fill_b : source_color = vec4(0.98, 0.42, 0.26, 1.0);
uniform vec4 trail_color : source_color = vec4(1.0, 0.92, 0.75, 0.85);
uniform vec4 track : source_color = vec4(0.07, 0.055, 0.045, 0.82);
uniform float flash = 0.0;
uniform float pulse = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	// ragged brush edge on the leading end, varying along the height
	float rag = (vnoise(vec2(uv.y * 9.0 + seed, TIME * 0.6)) - 0.5) * 0.018;
	float edge_v = value + rag;
	float edge_t = trail + rag;
	float aa = fwidth(uv.x) * 1.5;
	float in_fill = 1.0 - smoothstep(edge_v - aa, edge_v + aa, uv.x);
	float in_trail = (1.0 - smoothstep(edge_t - aa, edge_t + aa, uv.x)) * (1.0 - in_fill);
	// fill: horizontal gradient, bristle streaks, top sheen
	float streak = vnoise(vec2(uv.x * 30.0 + seed, uv.y * 4.0)) * 0.12;
	vec3 f = mix(fill_a.rgb, fill_b.rgb, uv.x * 0.6 + 0.2);
	f *= 0.9 + streak + (1.0 - uv.y) * 0.18;
	f += vec3(1.0) * smoothstep(0.35, 0.0, uv.y) * 0.12;
	f = mix(f, vec3(1.0), flash * 0.6);
	f *= 1.0 + pulse * 0.25 * (0.5 + 0.5 * sin(TIME * 9.0));
	vec3 col = track.rgb;
	float a = track.a;
	col = mix(col, trail_color.rgb, in_trail * trail_color.a);
	col = mix(col, f, in_fill);
	a = max(a, max(in_fill, in_trail * trail_color.a));
	// inner shadow at the track edges
	float border = smoothstep(0.0, 0.12, uv.y) * smoothstep(1.0, 0.82, uv.y);
	col *= mix(0.75, 1.0, border);
	COLOR = vec4(col, a * COLOR.a);
}
