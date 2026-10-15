// Volcanic smoke puffs (worldrender VolcanoSmoke): camera-facing soft billows with a noisy,
// painterly silhouette, lit by the current sun/sky and glowing orange near the vent.
// Particle COLOR.a carries the life fade; INSTANCE_CUSTOM.y is the particle's age fraction
// (ParticleProcessMaterial convention); INSTANCE_ID seeds the per-puff noise.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

global uniform vec3 world_sun_direction;
global uniform vec4 world_sun_color;
global uniform vec4 world_sky_zenith;
global uniform vec4 world_sky_horizon;
global uniform vec4 world_fog_color;

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 smoke_dark : source_color = vec3(0.20, 0.18, 0.18);
uniform vec3 smoke_light : source_color = vec3(0.56, 0.50, 0.47);
uniform vec3 glow_color : source_color = vec3(1.0, 0.42, 0.12);
uniform float glow_strength = 2.4;

varying float age;
varying vec4 pcol;
varying float seed;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	seed = fract(float(INSTANCE_ID) * 0.6180339);
	pcol = COLOR;
	// billboard keeping the particle's scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
			INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	vec2 nuv = UV * 0.6 + vec2(seed * 7.13, seed * 3.71) + vec2(age * 0.08, -age * 0.12);
	float n = texture(cloud_tex, nuv).r * 0.6 + texture(cloud_tex, nuv * 2.3).g * 0.4;
	float shape = smoothstep(1.0, 0.45, r + (n - 0.5) * 0.7);
	if (shape <= 0.002) {
		discard;
	}
	// lit from the sun side of the billow (fake normal from the disc coordinates)
	vec3 nrm = normalize(INV_VIEW_MATRIX[0].xyz * q.x + INV_VIEW_MATRIX[1].xyz * -q.y + INV_VIEW_MATRIX[2].xyz * 0.8);
	float lit = clamp(dot(nrm, normalize(world_sun_direction)) * 0.5 + 0.5, 0.0, 1.0);
	lit = mix(lit, floor(lit * 3.0 + 0.5) / 3.0, 0.4);
	vec3 amb = mix(world_sky_horizon.rgb, world_sky_zenith.rgb, 0.5);
	vec3 col = mix(smoke_dark, smoke_light, lit * (0.6 + n * 0.4)) * (amb * 0.8 + world_sun_color.rgb * 0.45 * lit);
	// lava glow lights the underside of young puffs
	float glow = (1.0 - smoothstep(0.0, 0.35, age)) * smoothstep(-0.2, 0.9, q.y);
	col += glow_color * glow * glow_strength * 0.35;
	// distance haze
	float dist = length(VERTEX);
	col = mix(col, world_fog_color.rgb, smoothstep(1500.0, 9000.0, dist) * 0.6);
	ALBEDO = col;
	ALPHA = shape * pcol.a * (0.55 + n * 0.45);
}
