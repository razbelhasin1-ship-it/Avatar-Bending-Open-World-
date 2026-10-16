// Bent water mass for large shapes (wave crests, vortex sheets, columns):
// a saturated blue body (darker inside the curl / on back faces), a lighter
// rim, crisp white foam caps where the mesh says so (vertex COLOR.r, or
// `foam_floor` for meshes without colours) with streaks flowing toward the
// crest, a soft wobble; `freeze` turns it to ice, `glow` lifts the emission,
// `fade` and COLOR.a fade it out.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.03, 0.25, 0.62, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.15, 0.56, 0.92, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.99, 1.0, 1.0);
uniform float opacity = 0.93;
uniform float flow = 1.3;
uniform float foam = 1.0;
// Meshes without vertex colours (COLOR = white) use this foam weight instead.
uniform float vertex_foam = 1.0;
uniform float foam_floor = 0.15;
uniform float fade = 1.0;
uniform float freeze = 0.0;
uniform float glow = 0.0;
uniform float wobble = 0.06;
// UV scale of the streak noise (bigger shapes want more streaks).
uniform vec2 streak_scale = vec2(4.0, 1.2);

void vertex() {
	float n = textureLod(noise_tex, UV * vec2(3.0, 1.0) + vec2(TIME * 0.05, -TIME * flow * 0.35), 0.0).r;
	VERTEX += NORMAL * (n - 0.5) * wobble * (1.0 - freeze);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 2.5);
	float n = texture(noise_tex, vec2(UV.x * streak_scale.x, UV.y * streak_scale.y - TIME * flow)).r;
	float n2 = texture(noise_tex, vec2(UV.x * streak_scale.x * 2.3 + 0.37, UV.y * streak_scale.y * 2.0 - TIME * flow * 1.7)).r;
	float fw = mix(foam_floor, COLOR.r, vertex_foam);
	// Foam: broken caps where the profile foams, thin streaks elsewhere.
	float f = fw * (0.55 + n * 0.75) + smoothstep(0.66, 0.78, n2) * (0.12 + 0.55 * fw);
	f *= foam;
	float cap = smoothstep(0.55, 0.63, f);
	float veil = smoothstep(0.3, 0.55, f) * 0.35;
	// Body: deep in the middle, lighter at grazing angles; the inside of the curl is darker.
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, clamp(fres * 1.1 + n * 0.25, 0.0, 1.0));
	if (!FRONT_FACING) {
		water *= 0.8;
	}
	vec3 col = mix(water, foam_color.rgb, max(cap, veil));
	vec3 ice = mix(vec3(0.6, 0.82, 0.96), vec3(0.92, 0.98, 1.0), clamp(fres + n * 0.35, 0.0, 1.0));
	ALBEDO = mix(col, ice, freeze);
	ROUGHNESS = mix(0.12, 0.25, freeze);
	SPECULAR = 0.5;
	EMISSION = mix(water * 0.1, vec3(0.18, 0.26, 0.32), freeze) + shallow_color.rgb * glow + foam_color.rgb * cap * 0.06;
	float a = opacity * (0.82 + 0.18 * max(cap, fres));
	ALPHA = clamp(mix(a, 0.97, freeze) * COLOR.a * fade, 0.0, 1.0);
}
