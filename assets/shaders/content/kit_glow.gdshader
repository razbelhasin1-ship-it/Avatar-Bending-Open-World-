// Emissive parts of kit buildings and props: lantern paper, brazier coals, fire bowls, spirit
// stones. Vertex colour = glow colour; brightness rises at dusk/night (world_sun_color) and
// flickers gently (per world position, so lanterns do not pulse in sync). UV.y = flicker amount.
//
// World fires that are out (put out by water / wind, or not lit yet) are listed by WorldFires in
// fire_mask: xyz = the flame's base (coal bed / wick), w = its radius. w > 0 (braziers, torches,
// campfires): the flame geometry above the base collapses into the bed and the coals go dark;
// w < 0 (lanterns): the paper / glass just goes dark. Only the few fires near the player are
// listed (fire_mask_count), so the loop is short.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

global uniform vec4 world_sun_color;

uniform float day_energy = 0.6;
uniform float night_energy = 2.6;
uniform float flicker = 0.18;
uniform vec4 fire_mask[32];
uniform int fire_mask_count = 0;

varying vec3 v_wpos;
varying float v_out;
varying float v_char;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_out = 0.0;
	v_char = 0.0;
	for (int i = 0; i < fire_mask_count; i++) {
		vec4 m = fire_mask[i];
		float r = abs(m.w);
		if (m.w > 0.0) {
			vec2 d = v_wpos.xz - m.xz;
			if (dot(d, d) < r * r && v_wpos.y > m.y - 0.3 && v_wpos.y < m.y + 2.4) {
				v_out = 1.0;
				v_char = 1.0;
				if (v_wpos.y > m.y + 0.01) {
					vec3 w = vec3(v_wpos.x, m.y + 0.01, v_wpos.z);
					VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
					v_wpos = w;
				}
			}
		} else if (distance(v_wpos, m.xyz) < r + 0.06) {
			v_out = 1.0;
		}
	}
}

void fragment() {
	float sun = clamp(dot(world_sun_color.rgb, vec3(0.3, 0.5, 0.2)), 0.0, 1.0);
	float night = 1.0 - smoothstep(0.05, 0.5, sun);
	float ph = dot(floor(v_wpos * 0.5), vec3(12.9898, 78.233, 37.719));
	float f = 1.0 + flicker * UV.y * (sin(TIME * 7.3 + ph) * 0.6 + sin(TIME * 13.1 + ph * 1.7) * 0.4);
	float lit = 1.0 - clamp(v_out, 0.0, 1.0);
	// out: charred coals (fires) or unlit paper / glass (lanterns)
	vec3 cold = mix(COLOR.rgb * 0.32, vec3(0.045, 0.035, 0.03), clamp(v_char, 0.0, 1.0));
	ALBEDO = mix(cold, COLOR.rgb * 0.6, lit);
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
	EMISSION = COLOR.rgb * mix(day_energy, night_energy, night) * f * lit;
}
