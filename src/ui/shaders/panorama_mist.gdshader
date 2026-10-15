// Drifting mist / cloud banks of the main-menu panorama: wide camera-facing cards with a
// noisy, painterly top edge, a soft base and a warm side toward the sun. UV.x scrolls so
// banks drift; COLOR.a of the mesh (per card) scales opacity.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 lit_color : source_color = vec3(1.0, 0.86, 0.72);
uniform vec3 shade_color : source_color = vec3(0.62, 0.64, 0.76);
uniform float opacity = 0.7;
uniform float drift = 0.004;
uniform float tiling = 3.0;
uniform float seed = 0.0;
uniform float sun_side = 0.6;

void fragment() {
	vec2 uv = UV;
	float x = uv.x * tiling + TIME * drift + seed;
	float n = texture(cloud_tex, vec2(x * 0.35, uv.y * 0.6 + seed * 0.3)).r * 0.65 + texture(cloud_tex, vec2(x * 1.1, uv.y * 1.3 + seed)).g * 0.35;
	// billowing top edge
	float top = 0.38 + n * 0.5;
	float body = smoothstep(top, top - 0.28, 1.0 - uv.y);
	float base = smoothstep(0.0, 0.25, 1.0 - uv.y);
	float ends = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	float a = body * base * ends * opacity * COLOR.a;
	// lit from the sun side, shaded toward the base
	float lit = clamp((1.0 - uv.y) * 0.9 + n * 0.4, 0.0, 1.0);
	lit = mix(lit, mix(lit, 1.0, 0.4), sun_side * uv.x);
	ALBEDO = mix(shade_color, lit_color, lit);
	ALPHA = clamp(a, 0.0, 1.0);
}
