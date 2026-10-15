// Modal backdrop: blurred (screen mip) and dimmed copy of the scene behind, warmed toward
// ink so overlays sit on lacquer rather than plain black. Works on every renderer.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float dim = 0.55;
uniform float blur_lod = 2.6;
uniform vec4 ink : source_color = vec4(0.106, 0.082, 0.071, 1.0);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	c = mix(c, ink.rgb, dim);
	// soft vignette
	vec2 q = SCREEN_UV - 0.5;
	c *= 1.0 - dot(q, q) * 0.9;
	COLOR = vec4(c, COLOR.a);
}
