// Main-menu sea: three scrolling layers of the world water normal texture (rg = slope),
// calmer with distance so the horizon stays clean, deep-to-shallow colour, physically based
// sky reflection and a sharp sun glitter path from the engine's specular.
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.04, 0.12, 0.18);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.28, 0.33);
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 0.03;
uniform float wave_speed = 0.018;
uniform float strength = 0.55;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	vec2 uv = wpos.xz * wave_scale;
	vec2 t = vec2(TIME * wave_speed, TIME * wave_speed * 0.6);
	vec2 d1 = texture(normal_tex, uv + t).rg * 2.0 - 1.0;
	vec2 d2 = texture(normal_tex, uv * 0.37 - t * 0.7 + 0.31).rg * 2.0 - 1.0;
	vec2 d3 = texture(normal_tex, uv * 0.11 + t * 0.3 + 0.7).rg * 2.0 - 1.0;
	float calm = 1.0 - smoothstep(120.0, 3000.0, dist);
	vec2 dn = (d1 + d2 * 0.8 + d3 * 0.7) * strength * (0.3 + 0.7 * calm);
	NORMAL_MAP = normalize(vec3(dn, 1.0)) * 0.5 + 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow_color, deep_color, clamp(fres * 1.5 + (1.0 - calm) * 0.5, 0.0, 1.0));
	ROUGHNESS = mix(0.04, 0.14, calm);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
