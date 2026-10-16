// Ice crystals (shards, ice walls, frozen water): faceted, bright toon bands,
// sharp highlights, cool inner glow and a white fresnel rim. Opaque (cheap).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.38, 0.7, 0.93, 1.0);
uniform vec4 core_color : source_color = vec4(0.82, 0.95, 1.0, 1.0);
uniform float glow = 0.16;
uniform float hit_flash = 0.0;
// 0..1 shatter fade (dims and whitens).
uniform float frost = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	vec3 c = mix(base_color.rgb, core_color.rgb, clamp(fres * 1.1 + frost, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.1;
	SPECULAR = 0.9;
	EMISSION = base_color.rgb * glow + vec3(0.85, 0.96, 1.0) * fres * 0.35 + vec3(1.0) * hit_flash;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.04, 0.04, ndl + 0.1);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(0.5, 1.0, lit) * ATTENUATION;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(0.93, 0.95, dot(NORMAL, h));
	SPECULAR_LIGHT += LIGHT_COLOR * spec * 0.6 * lit * ATTENUATION;
}
