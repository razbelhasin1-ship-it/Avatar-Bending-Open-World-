// Lightning bolt ribbon (Lightning Generation, charge arcs). UV.x runs along the
// bolt (0 hand .. 1 tip), UV.y across it. A white-hot core with a blue-violet
// glow, flickering, additive (reads on any background without filling it).
// `reveal` grows the bolt from the hand (0..1), `fade` dims it out.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.42, 0.62, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.58, 0.32, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float fade = 0.0;
uniform float reveal = 1.0;
uniform float flicker = 1.0;
uniform float seed = 0.0;

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.05, 0.3, across);
	float glow = pow(1.0 - smoothstep(0.0, 1.0, across), 1.6);
	float fl = mix(1.0, 0.55 + 0.45 * step(0.35, fract(sin(floor(TIME * 38.0) + seed * 17.0 + UV.x * 3.0) * 43758.5453)), flicker);
	float shown = 1.0 - smoothstep(reveal - 0.02, reveal + 0.02, UV.x);
	vec3 col = mix(edge_color.rgb, glow_color.rgb, glow) * glow + core_color.rgb * core * 1.8;
	float k = intensity * fl * (1.0 - fade) * shown * COLOR.a;
	ALBEDO = col * k;
	ALPHA = clamp(max(core, glow * 0.85) * k, 0.0, 1.0);
}
