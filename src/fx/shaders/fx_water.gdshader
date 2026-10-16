// Bent water: translucent body with fresnel rim, flowing highlights and foam,
// a gentle wobble, and a `freeze` blend that turns it into milky ice.
// Used by WaterStream tubes, water balls and splashes. COLOR.a fades the tail.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.10, 0.40, 0.80, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.45, 0.82, 0.98, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float freeze = 0.0;
uniform float opacity = 0.8;
uniform float flow_speed = 2.2;
uniform float wobble = 0.03;
uniform float foam_amount = 1.0;

void vertex() {
	float n = textureLod(noise_tex, UV * vec2(2.0, 1.0) + vec2(TIME * flow_speed * 0.3, 0.0), 0.0).r;
	VERTEX += NORMAL * (n - 0.5) * wobble * (1.0 - freeze);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float n = texture(noise_tex, vec2(UV.x * 3.0 - TIME * flow_speed, UV.y)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 7.0 - TIME * flow_speed * 1.7, UV.y * 2.0 + 0.3)).r;
	float foam = (smoothstep(0.66, 0.8, n2) * 0.75 + smoothstep(0.72, 1.0, fres) * 0.55) * foam_amount;
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, clamp(fres * 0.9 + n * 0.35, 0.0, 1.0));
	water = mix(water, foam_color.rgb, clamp(foam, 0.0, 1.0));
	vec3 ice = mix(vec3(0.70, 0.88, 0.98), vec3(0.97, 1.0, 1.0), clamp(fres + n * 0.35, 0.0, 1.0));
	ALBEDO = mix(water, ice, freeze);
	ROUGHNESS = mix(0.06, 0.22, freeze);
	SPECULAR = 0.75;
	EMISSION = mix(shallow_color.rgb * 0.16, vec3(0.22, 0.32, 0.38), freeze) + foam_color.rgb * clamp(foam, 0.0, 1.0) * 0.12;
	ALPHA = clamp(mix(opacity * (0.72 + 0.28 * fres + foam * 0.2), 0.96, freeze) * COLOR.a, 0.0, 1.0);
}
