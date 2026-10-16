// Emissive parts of kit buildings and props: lantern paper, brazier coals, fire bowls, spirit
// stones. Vertex colour = glow colour; brightness rises at dusk/night (world_sun_color) and
// flickers gently (per world position, so lanterns do not pulse in sync). UV.y = flicker amount.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

global uniform vec4 world_sun_color;

uniform float day_energy = 0.6;
uniform float night_energy = 2.6;
uniform float flicker = 0.18;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float sun = clamp(dot(world_sun_color.rgb, vec3(0.3, 0.5, 0.2)), 0.0, 1.0);
	float night = 1.0 - smoothstep(0.05, 0.5, sun);
	float ph = dot(floor(v_wpos * 0.5), vec3(12.9898, 78.233, 37.719));
	float f = 1.0 + flicker * UV.y * (sin(TIME * 7.3 + ph) * 0.6 + sin(TIME * 13.1 + ph * 1.7) * 0.4);
	ALBEDO = COLOR.rgb * 0.6;
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
	EMISSION = COLOR.rgb * mix(day_energy, night_energy, night) * f;
}
