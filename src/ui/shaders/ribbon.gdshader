// Ribbon / tube strips for bending previews (air currents, water streams).
// UV.x runs along the ribbon (0 = tail, 1 = head), UV.y across it. Air mode: soft additive
// streaks with flowing gaps. Water mode: translucent body with a bright rim and moving
// highlights. COLOR.a (per vertex) fades the strip.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float water = 0.0;
uniform float flow_speed = 1.6;
uniform float streaks = 3.0;
uniform float opacity = 0.8;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float n = texture(noise_tex, vec2(along * 1.4 - TIME * flow_speed * 0.25, UV.y * 0.7)).r;
	float n2 = texture(noise_tex, vec2(along * 3.1 - TIME * flow_speed * 0.6, UV.y * 1.9 + 0.37)).g;
	// head bright, tail fading
	float fade = smoothstep(0.0, 0.35, along) * smoothstep(1.0, 0.93, along);
	float a_air = smoothstep(1.0, 0.25, across) * (0.35 + 0.65 * smoothstep(0.3, 0.7, n + 0.25 * sin(along * streaks * 6.28 - TIME * flow_speed * 4.0)));
	float body = smoothstep(1.0, 0.82, across);
	float rim = smoothstep(0.55, 0.95, across) * body;
	float shine = smoothstep(0.62, 0.9, n2) * (1.0 - across);
	vec3 water_col = mix(tint.rgb, rim_tint.rgb, clamp(rim * 0.9 + shine * 0.8, 0.0, 1.0));
	vec3 col = mix(tint.rgb, water_col, water);
	float a = mix(a_air, body * (0.62 + rim * 0.35 + shine * 0.3), water);
	ALBEDO = col;
	ALPHA = clamp(a * fade * opacity * COLOR.a, 0.0, 1.0);
}
