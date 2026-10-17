shader_type canvas_item;
// World map paper: the painted parchment map (WorldData.get_map_texture) where the player has
// explored, and an old, faded, sepia-washed chart elsewhere (coastlines still readable). The
// edge between them is broken up with paper noise so it reads like ink soaking into paper.

uniform sampler2D reveal_tex : filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float fog_strength = 1.0;
uniform vec4 paper : source_color = vec4(0.88, 0.82, 0.70, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float r = texture(reveal_tex, UV).r;
	float n = texture(noise_tex, UV * 7.0).r * 0.65 + texture(noise_tex, UV * 23.0).r * 0.35;
	float k = smoothstep(0.32, 0.68, r + (n - 0.5) * 0.42);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 aged = mix(vec3(g) * vec3(1.02, 0.97, 0.86), c.rgb, 0.2);
	aged = mix(aged, paper.rgb, 0.5);
	// a faint brown ink line where the explored edge runs
	float edge = smoothstep(0.0, 0.5, k) * smoothstep(1.0, 0.5, k);
	vec3 col = mix(aged, c.rgb, mix(1.0, k, fog_strength));
	col = mix(col, col * vec3(0.78, 0.68, 0.56), edge * 0.35 * fog_strength);
	COLOR = vec4(col, c.a);
}
