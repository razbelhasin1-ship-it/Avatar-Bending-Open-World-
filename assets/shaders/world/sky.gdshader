// Painterly sky of the open world (worldrender SkyController drives every uniform).
// Gradient + horizon haze, sun disc with a soft halo and sunset glow, phased moon, rotating
// star field, two animated cloud layers (billowy cumulus with stepped "brush" shading and
// high wispy cirrus). The radiance/ambient pass skips stars and fine cloud detail.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.23, 0.44, 0.77);
uniform vec3 horizon_color : source_color = vec3(0.73, 0.83, 0.91);
uniform vec3 ground_color : source_color = vec3(0.35, 0.40, 0.45);
uniform float gradient_curve = 0.55;
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_visible = 1.0;
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.8, 0.5);
uniform float sun_glow = 0.5;
uniform float sun_size = 0.035;
uniform vec3 moon_dir = vec3(0.0, -0.7, -0.7);
uniform vec3 moon_color : source_color = vec3(0.9, 0.93, 1.0);
uniform float moon_visible = 0.0;
uniform float moon_size = 0.05;
// 0 = new, 0.5 = full, 1 = new again
uniform float moon_phase = 0.45;
uniform float stars = 0.0;
// arctic aurora curtains in the northern sky (0 = off)
uniform float aurora = 0.0;
uniform mat3 star_rotation = mat3(1.0);
uniform float haze = 0.4;
uniform vec3 haze_color : source_color = vec3(0.8, 0.85, 0.9);
// clouds
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage = 0.4;
uniform float cloud_softness = 0.18;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.6, 0.66, 0.78);
uniform float cloud_darkness = 0.0;
uniform float cirrus = 0.35;
uniform vec2 cloud_offset = vec2(0.0);
uniform float sky_time = 0.0;
uniform float sky_energy = 1.0;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 sky_gradient(vec3 dir) {
	float up = max(dir.y, 0.0);
	vec3 col = mix(horizon_color, zenith_color, pow(up, gradient_curve));
	// below the horizon fade into the ground/sea tone
	col = mix(col, ground_color, smoothstep(0.0, -0.18, dir.y));
	return col;
}

float star_field(vec3 dir) {
	vec3 d = star_rotation * dir;
	float acc = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 90.0 : 190.0;
		vec3 p = d * scale;
		vec3 cell = floor(p);
		vec3 f = fract(p) - 0.5;
		float h = hash13(cell + float(layer) * 17.0);
		float thresh = layer == 0 ? 0.965 : 0.985;
		if (h > thresh) {
			vec3 jitter = vec3(hash13(cell + 1.3), hash13(cell + 2.7), hash13(cell + 5.1)) - 0.5;
			float r = length(f - jitter * 0.6);
			float bright = (h - thresh) / (1.0 - thresh);
			float tw = 0.75 + 0.25 * sin(sky_time * (1.5 + h * 4.0) + h * 40.0);
			acc += smoothstep(0.12 + bright * 0.06, 0.0, r) * (0.35 + bright) * tw;
		}
	}
	// a faint milky band across the sky (two planar projections, no polar pinching)
	float band = exp(-pow(d.y * 3.2 + d.x * 0.6, 2.0) * 2.0);
	float dust = mix(texture(cloud_tex, d.xy * 1.3 + 0.3).r, texture(cloud_tex, d.zy * 1.3 + 0.7).r, abs(d.x));
	acc += band * 0.07 * dust;
	return acc;
}

// Aurora: folded curtains hanging over the northern horizon, green at the hem fading to violet,
// with vertical rays drifting slowly.
vec3 aurora_light(vec3 dir) {
	if (dir.y <= 0.0) {
		return vec3(0.0);
	}
	float az = atan(dir.x, -dir.z);
	float north = smoothstep(1.7, 0.4, abs(az));
	float x = az * 2.6;
	float fold = sin(x * 2.1 + sky_time * 0.03) * 0.05 + (textureLod(cloud_tex, vec2(x * 0.11 + sky_time * 0.002, 0.27), 0.0).r - 0.5) * 0.16;
	float h = dir.y - (0.16 + fold);
	float hem = smoothstep(-0.02, 0.012, h);
	float curtain = hem * exp(-max(h, 0.0) / 0.2);
	float rays = textureLod(cloud_tex, vec2(x * 1.7 + sky_time * 0.006, 0.61), 0.0).b * 0.7 + 0.3;
	vec3 col = mix(vec3(0.15, 0.95, 0.55), vec3(0.50, 0.32, 0.95), smoothstep(0.02, 0.3, h));
	return col * curtain * rays * north;
}

// Cloud density and lighting for one view direction (plane projection).
vec4 clouds(vec3 dir, vec3 light_dir, bool detail) {
	// no early return: textures below must be sampled in uniform control flow
	float above = step(0.005, dir.y);
	vec2 p = dir.xz / (max(dir.y, 0.005) + 0.12);
	vec2 uv = p * 0.22 + cloud_offset;
	float base = texture(cloud_tex, uv).r * 0.62 + texture(cloud_tex, uv * 0.47 + 0.21).g * 0.38;
	if (detail) {
		base = base * 0.82 + texture(cloud_tex, uv * 2.3 - cloud_offset * 0.6).a * 0.18;
	}
	float thr = 1.0 - cloud_coverage;
	float dens = smoothstep(thr - cloud_softness * 0.5, thr + cloud_softness, base);
	// fake self shadow: density sampled towards the light
	vec2 ld = normalize(light_dir.xz + vec2(1e-4)) * 0.035;
	float toward = texture(cloud_tex, uv + ld).r * 0.62 + texture(cloud_tex, (uv + ld) * 0.47 + 0.21).g * 0.38;
	float lit = clamp(0.55 + (base - toward) * 6.0, 0.0, 1.0);
	lit = mix(lit, floor(lit * 3.0 + 0.5) / 3.0, 0.45);   // painterly stepped shading
	// silver lining towards the sun
	float rim = pow(max(dot(dir, light_dir), 0.0), 6.0) * (1.0 - dens) * 2.0;
	vec3 col = mix(cloud_shade, cloud_lit, clamp(lit + rim, 0.0, 1.0));
	col *= 1.0 - cloud_darkness * 0.6 * dens;
	float horizon_fade = smoothstep(0.0, 0.12, dir.y);
	// cirrus streaks high above
	float ci = 0.0;
	if (cirrus > 0.0) {
		vec2 cuv = p * 0.07 + cloud_offset * 0.35 + vec2(0.0, 0.31);
		ci = smoothstep(0.55, 0.9, texture(cloud_tex, cuv).b) * cirrus * smoothstep(0.08, 0.35, dir.y) * (1.0 - stars * 0.85);
	}
	float a = clamp(dens * horizon_fade + ci * (1.0 - dens) * 0.6, 0.0, 1.0) * above;
	vec3 ccol = mix(cloud_lit * 1.02, col, dens / max(a, 1e-3) * horizon_fade);
	return vec4(ccol, a);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = sky_gradient(dir);
	float sd = dot(dir, normalize(sun_dir));
	// sunset/sunrise glow hugging the horizon around the sun
	float glow = pow(max(sd, 0.0), 4.0) * sun_glow;
	glow += pow(max(sd, 0.0), 32.0) * sun_glow * 1.5;
	col += sun_glow_color * glow * (0.5 + 0.5 * smoothstep(0.35, 0.0, abs(dir.y)));
	bool cube = AT_CUBEMAP_PASS;
	vec3 light_dir = sun_visible > 0.01 ? normalize(sun_dir) : normalize(moon_dir);
	if (!cube && stars > 0.001) {
		col += vec3(0.92, 0.95, 1.0) * star_field(dir) * stars * smoothstep(-0.02, 0.15, dir.y);
	}
	if (aurora > 0.001) {
		col += aurora_light(dir) * aurora * 0.55;
	}
	// moon disc with phase terminator and soft craters
	if (moon_visible > 0.001) {
		vec3 md = normalize(moon_dir);
		float ang = acos(clamp(dot(dir, md), -1.0, 1.0));
		if (ang < moon_size * 3.0) {
			vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
			vec3 upv = cross(right, md);
			vec2 q = vec2(dot(dir - md, right), dot(dir - md, upv)) / moon_size;
			float r = length(q);
			float disc = smoothstep(1.0, 0.94, r);
			float z = sqrt(max(1.0 - r * r, 0.0));
			vec3 sn = vec3(q, z);
			float ph = (moon_phase - 0.5) * 6.2831853;
			vec3 ldir = normalize(vec3(sin(ph), 0.15, -cos(ph)));
			float illum = smoothstep(-0.06, 0.12, dot(sn, ldir));
			float crater = textureLod(cloud_tex, q * 0.18 + 0.5, 0.0).g;
			vec3 mcol = moon_color * mix(0.72, 1.0, crater) * (0.04 + illum);
			col = mix(col, mcol * 1.6, disc * moon_visible);
			col += moon_color * exp(-ang / moon_size * 1.3) * 0.12 * moon_visible;
		}
	}
	// sun disc + halo
	float sun_ang = acos(clamp(sd, -1.0, 1.0));
	float disc = smoothstep(sun_size, sun_size * 0.82, sun_ang) * sun_visible;
	float halo = exp(-sun_ang / (sun_size * 2.2)) * 0.6 * sun_visible;
	col += sun_color * halo;
	col = mix(col, sun_color * 4.0, disc);
	// clouds
	vec4 cl = clouds(dir, light_dir, !cube);
	col = mix(col, cl.rgb * (1.0 + glow * 0.4), cl.a);
	// horizon haze band (matches the distance fog colour)
	float hb = exp(-abs(dir.y) * 9.0) * haze;
	col = mix(col, haze_color, clamp(hb, 0.0, 1.0));
	COLOR = col * sky_energy;
}
