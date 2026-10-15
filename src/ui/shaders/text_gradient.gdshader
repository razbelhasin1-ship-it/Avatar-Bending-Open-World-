// Vertical metallic gradient for display text (title lockups): top/mid/bottom colours
// across `height` px of the label, a thin bright band that slowly travels down the
// letters, and faint grain so large letters read as gilded, not flat.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(1.0, 0.93, 0.70, 1.0);
uniform vec4 mid_color : source_color = vec4(0.93, 0.72, 0.34, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.66, 0.44, 0.18, 1.0);
uniform float y0 = 0.0;
uniform float height = 160.0;
uniform float shine = 0.25;
uniform float shine_speed = 0.08;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float t = clamp((local_pos.y - y0) / height, 0.0, 1.0);
	vec3 col = t < 0.5 ? mix(top_color.rgb, mid_color.rgb, t * 2.0) : mix(mid_color.rgb, bottom_color.rgb, (t - 0.5) * 2.0);
	float band = fract(TIME * shine_speed);
	float d = abs((t + local_pos.x * 0.0006) - (band * 1.6 - 0.3));
	col += vec3(1.0, 0.95, 0.85) * smoothstep(0.06, 0.0, d) * shine;
	col *= 0.94 + 0.06 * hash(floor(local_pos * 0.5));
	COLOR = vec4(col, tex.a * COLOR.a);
}
