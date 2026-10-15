// Painterly mountain ranges for the main-menu panorama: grass/forest on gentle low
// slopes, rock on steep faces, snow above a noisy snow line; soft two-band toon light with
// a warm rim where ridges catch the low sun. Atmospheric perspective comes from the
// Environment fog plus a per-layer `layer_haze` tint so ranges separate into planes.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 grass_color : source_color = vec3(0.32, 0.42, 0.26);
uniform vec3 rock_color : source_color = vec3(0.42, 0.38, 0.36);
uniform vec3 snow_color : source_color = vec3(0.95, 0.94, 0.96);
uniform float snow_line = 300.0;
uniform float snow_soft = 40.0;
uniform vec3 haze_color : source_color = vec3(0.55, 0.62, 0.78);
uniform float layer_haze : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.75, 0.45);
uniform float rim_strength = 0.6;
uniform vec3 sun_dir = vec3(0.2, 0.15, -1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.0021).r;
	float n2 = texture(noise_tex, wpos.xz * 0.011 + 0.37).g;
	float slope = clamp(wnrm.y, 0.0, 1.0);
	float rocky = smoothstep(0.86, 0.62, slope + (n2 - 0.5) * 0.18);
	vec3 col = mix(grass_color * (0.85 + n * 0.3), rock_color * (0.88 + n2 * 0.25), rocky);
	// darker forest bands low down
	col *= mix(0.78, 1.0, smoothstep(0.0, snow_line * 0.45, wpos.y + (n - 0.5) * 30.0));
	float sline = snow_line + (n - 0.5) * snow_soft * 3.0;
	float snow = smoothstep(sline - snow_soft, sline + snow_soft, wpos.y) * smoothstep(0.42, 0.68, slope + n2 * 0.15);
	col = mix(col, snow_color, snow);
	col = mix(col, haze_color, layer_haze);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	// warm rim on silhouettes facing the sun (back light)
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = pow(1.0 - clamp(dot(wnrm, v), 0.0, 1.0), 3.0);
	float toward = clamp(dot(-v, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	EMISSION = rim_color * fres * toward * rim_strength * (1.0 - layer_haze * 0.6) * (0.4 + snow);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.05, 0.2, ndl) * 0.7 + smoothstep(0.35, 0.6, ndl) * 0.3;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band * 0.9;
}
