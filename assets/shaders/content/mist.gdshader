// Soft billboard puff for waterfall mist, steam vents and spirit motes (GPUParticles3D draw pass).
// Particle COLOR (from the process material colour ramp) fades the puff over its life.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

global uniform vec4 world_sun_color;
global uniform vec4 world_sky_horizon;

uniform vec4 tint : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float glow = 0.0;

void vertex() {
	// camera-facing billboard keeping the particle scale
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mv = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = mv;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = dot(p, p);
	float puff = exp(-r * 3.2);
	float day = clamp(dot(world_sun_color.rgb, vec3(0.3, 0.5, 0.2)) * 1.3 + 0.3, 0.3, 1.1);
	vec3 col = mix(tint.rgb * day, tint.rgb * (1.0 + glow), glow > 0.0 ? 1.0 : 0.0);
	col = mix(col, world_sky_horizon.rgb, 0.15);
	ALBEDO = col;
	EMISSION = tint.rgb * glow * puff;
	ALPHA = puff * COLOR.a * tint.a;
}
