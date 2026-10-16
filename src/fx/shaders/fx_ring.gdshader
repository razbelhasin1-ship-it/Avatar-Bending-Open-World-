// Expanding ground ring / shockwave on a flat quad (impacts, stomps, sweeps,
// landing puffs). `progress` 0..1 drives radius, thinning and fade.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress = 0.0;
uniform float width = 0.16;
uniform float opacity = 0.8;
// Faint fill inside the ring (dust disc).
uniform float fill = 0.25;
uniform float seed = 0.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float ang = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float n = textureLod(noise_tex, vec2(ang * 3.0 + seed, progress * 0.6 + seed * 0.3), 0.0).r;
	float rr = mix(0.08, 0.92, sqrt(clamp(progress, 0.0, 1.0)));
	float w = width * mix(1.2, 0.45, progress);
	float d = abs(r - rr) / max(w, 0.001) + (n - 0.5) * 0.9;
	float ring = 1.0 - smoothstep(0.55, 1.0, d);
	float inside = (1.0 - smoothstep(0.0, rr, r)) * fill * (1.0 - progress);
	float fade = 1.0 - smoothstep(0.55, 1.0, progress);
	vec3 col = mix(inner_color.rgb, color.rgb, ring);
	ALBEDO = col;
	ALPHA = clamp((ring + inside) * fade * opacity * COLOR.a * step(r, 1.0), 0.0, 1.0);
}
