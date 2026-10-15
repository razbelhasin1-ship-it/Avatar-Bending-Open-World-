// Stylized "animated series" shading for characters, creatures and props.
// Soft two-tone diffuse with a tinted shadow side, rim light and a tight toon
// specular. Use ToonMaterials.make() (src/core/toon_materials.gd) instead of
// creating this material by hand; it adds the outline pass and caches results.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_vertex_color = false;
uniform bool use_texture = false;
// Color multiplied into the albedo on the unlit side (adds a cool/warm tint).
uniform vec4 shade_tint : source_color = vec4(0.62, 0.58, 0.78, 1.0);
// Width of the light/shadow terminator (0 = hard edge).
uniform float band_softness : hint_range(0.0, 0.5) = 0.06;
// Shifts the terminator (positive = more lit area).
uniform float band_offset : hint_range(-0.5, 0.5) = 0.05;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_width : hint_range(0.0, 1.0) = 0.55;
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float specular_strength : hint_range(0.0, 2.0) = 0.08;
uniform float specular_size : hint_range(0.0, 1.0) = 0.12;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;
// 0..1 "wetness"/"frost" overlays driven by gameplay (soaked, frozen, burned).
uniform vec4 status_color : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float status_amount : hint_range(0.0, 1.0) = 0.0;
// Hit flash (set to 1 and tween to 0 on damage).
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_texture) {
		c *= texture(albedo_texture, UV).rgb;
	}
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	c = mix(c, status_color.rgb, status_amount * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	EMISSION = emission.rgb * emission_energy + vec3(1.0, 0.95, 0.9) * hit_flash * 1.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_softness, band_softness, ndl + band_offset);
	lit *= smoothstep(0.0, 0.25, ATTENUATION);
	// Shadow side keeps a tinted fraction of the light so forms read clearly.
	vec3 shade = mix(shade_tint.rgb * 0.35, vec3(1.0), lit);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * shade;
	// Toon specular
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(1.0 - specular_size * 0.2 - 0.01, 1.0 - specular_size * 0.2 + 0.01, dot(NORMAL, h));
	SPECULAR_LIGHT += LIGHT_COLOR / PI * spec * specular_strength * lit;
	// Rim light on the lit side, scaled by light so it stays dark at night.
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.12, 1.0 - max(dot(NORMAL, VIEW), 0.0));
	SPECULAR_LIGHT += LIGHT_COLOR / PI * rim * rim_strength * rim_color.rgb * max(lit, 0.25) * ALBEDO;
}
