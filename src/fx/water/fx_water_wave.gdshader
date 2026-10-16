// Bent water mass for large shapes (wave crests, vortex sheets, columns):
// saturated blue body with lighter fresnel edges, foam bands that flow up the
// face toward the crest (vertex COLOR.r = foam weight from the mesh profile),
// banded toon foam, a soft wobble, `freeze` turns it to ice, `glow` lifts the
// emission (healing water), `fade` and COLOR.a fade it out.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.03, 0.26, 0.62, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.2, 0.6, 0.92, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.99, 1.0, 1.0);
uniform float opacity = 0.9;
uniform float flow = 1.3;
uniform float foam = 1.0;
uniform float fade = 1.0;
uniform float freeze = 0.0;
uniform float glow = 0.0;
uniform float wobble = 0.07;
// UV scale of the streak noise (bigger shapes want more streaks).
uniform vec2 streak_scale = vec2(4.0, 1.2);

void vertex() {
	float n = textureLod(noise_tex, UV * vec2(3.0, 1.0) + vec2(TIME * 0.05, -TIME * flow * 0.35), 0.0).r;
	VERTEX += NORMAL * (n - 0.5) * wobble * (1.0 - freeze);
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float n = texture(noise_tex, vec2(UV.x * streak_scale.x, UV.y * streak_scale.y - TIME * flow)).r;
	float n2 = texture(noise_tex, vec2(UV.x * streak_scale.x * 2.3 + 0.37, UV.y * streak_scale.y * 2.0 - TIME * flow * 1.7)).r;
	float streak = smoothstep(0.62, 0.74, n2);
	float fw = COLOR.r;
	float f = clamp(fw * (0.45 + n * 0.9) + streak * (0.25 + 0.5 * fw) + smoothstep(0.8, 1.0, fres) * 0.2, 0.0, 1.0) * foam;
	// Two toon bands of foam: solid white caps and a softer veil.
	float cap = smoothstep(0.52, 0.6, f);
	float veil = smoothstep(0.28, 0.5, f) * 0.45;
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, clamp(fres * 0.85 + n * 0.35, 0.0, 1.0));
	vec3 col = mix(water, foam_color.rgb, max(cap, veil));
	vec3 ice = mix(vec3(0.66, 0.86, 0.98), vec3(0.96, 1.0, 1.0), clamp(fres + n * 0.4, 0.0, 1.0));
	ALBEDO = mix(col, ice, freeze);
	ROUGHNESS = mix(0.1, 0.25, freeze);
	SPECULAR = 0.55;
	EMISSION = mix(col * 0.14, vec3(0.2, 0.3, 0.36), freeze) + shallow_color.rgb * glow + foam_color.rgb * cap * 0.08;
	float a = opacity * (0.74 + 0.26 * max(cap, veil * 2.0) + fres * 0.18);
	ALPHA = clamp(mix(a, 0.97, freeze) * COLOR.a * fade, 0.0, 1.0);
}
