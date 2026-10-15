// Flock bird (BirdFlock): one MultiMesh draw for a whole flock. Wings are flapped in
// the vertex shader from per-instance custom data:
//   INSTANCE_CUSTOM.x = flap phase (0..1), .y = flap amount (0 = glide, 1 = flapping),
//   .z = flap speed (cycles/s).
// Mesh vertex COLOR: r = wing factor (0 body, 0..1 along the wing), g = side (0 left, 1 right),
// b = part (0 body, 0.5 beak/feet, 1 wing tip band).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

#include "res://assets/shaders/creatures/creature_common.gdshaderinc"

uniform vec4 body_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform vec4 wing_color : source_color = vec4(0.72, 0.74, 0.78, 1.0);
uniform vec4 tip_color : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform vec4 beak_color : source_color = vec4(0.95, 0.75, 0.2, 1.0);
uniform vec4 belly_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flap_angle = 0.9;

varying float v_wing;
varying float v_part;
varying float v_belly;

void vertex() {
	float wing = COLOR.r;
	float side = COLOR.g * 2.0 - 1.0;
	v_wing = wing;
	v_part = COLOR.b;
	v_belly = clamp(-NORMAL.y, 0.0, 1.0);
	if (wing > 0.0) {
		float ph = TIME * INSTANCE_CUSTOM.z + INSTANCE_CUSTOM.x * 6.2831;
		float flap = INSTANCE_CUSTOM.y;
		float ang = sin(ph) * flap_angle * flap + mix(0.12, 0.0, flap);
		// Outer wing lags and bends more (whip).
		float a = side * ang * (0.75 + 0.5 * wing) + side * sin(ph - 0.7) * 0.25 * flap * wing;
		float c = cos(a);
		float s = sin(a);
		vec3 v = VERTEX;
		VERTEX.x = v.x * c - v.y * s;
		VERTEX.y = v.x * s + v.y * c;
		vec3 n = NORMAL;
		NORMAL.x = n.x * c - n.y * s;
		NORMAL.y = n.x * s + n.y * c;
	}
}

void fragment() {
	vec3 c = mix(body_color.rgb, belly_color.rgb, smoothstep(0.3, 0.8, v_belly) * step(v_wing, 0.001));
	c = mix(c, wing_color.rgb, step(0.001, v_wing));
	c = mix(c, tip_color.rgb, step(0.78, v_wing));
	c = mix(c, beak_color.rgb, step(0.4, v_part) * step(v_part, 0.6));
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
