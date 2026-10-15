// Bent water stream (UI previews): translucent tube with a bright fresnel rim, flowing
// highlights and a toon-stepped body so it reads like the show's waterbending.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform vec4 deep : source_color = vec4(0.12, 0.42, 0.78, 1.0);
uniform vec4 light : source_color = vec4(0.62, 0.88, 1.0, 1.0);
uniform vec4 foam : source_color = vec4(0.95, 0.99, 1.0, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float flow = 1.4;
uniform float opacity = 0.86;

void fragment() {
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float n = texture(noise_tex, vec2(UV.x * 2.0 - TIME * flow * 0.4, UV.y)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 5.0 - TIME * flow, UV.y * 2.0 + 0.3)).g;
	float lit = clamp(dot(normalize(NORMAL), normalize(vec3(0.3, 0.8, 0.5))) * 0.5 + 0.5, 0.0, 1.0);
	lit = floor(lit * 3.0 + 0.5) / 3.0;
	vec3 col = mix(deep.rgb, light.rgb, lit * 0.8 + n * 0.2);
	col = mix(col, foam.rgb, smoothstep(0.55, 0.85, fres) * 0.85 + smoothstep(0.7, 0.92, n2) * 0.6);
	float head = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.94, UV.x);
	ALBEDO = col;
	ALPHA = clamp((0.55 + fres * 0.45) * opacity * head * COLOR.a, 0.0, 1.0);
}
