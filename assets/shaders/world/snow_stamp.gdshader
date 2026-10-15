// Stamps one snow print into the trail map (worldrender SnowTrails), max-blended with the
// current content (read from the back buffer the item copies right before drawing).
// The rect is the print's bounding square, rotated so local +y (UV down) points forward.
// COLOR = (depth 0..1 of trail_max_depth, rim 0..1, scatter 0..1, kind / 4):
//   kind 0 boot print, 1 paw print (heavy creatures), 2 landing crater.
// Output channels: R depth, G raised rim, B loose scatter, A 1.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

float sd_ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return (length(q) - 1.0) * min(r.x, r.y);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec4 old = texture(screen_tex, SCREEN_UV);
	vec4 c = COLOR;
	int kind = int(c.a * 4.0 + 0.5);
	// local coordinates: the rect spans [-1, 1]; prints are drawn at 0.62 of the rect so the
	// rim and scatter fit inside it
	vec2 q = (UV - 0.5) * 2.0;
	float depth = 0.0;
	float rim = 0.0;
	float scatter = 0.0;
	if (kind == 2) {
		// landing crater: irregular bowl + thick raised lip + scattered chunks
		float ang = atan(q.y, q.x);
		float wob = 1.0 + 0.045 * sin(ang * 5.0 + c.r * 13.0) + 0.025 * sin(ang * 11.0 + 1.7);
		float r = length(q) / (0.55 * wob);
		depth = c.r * clamp(1.0 - pow(r, 2.6), 0.0, 1.0);
		float lip = exp(-pow((r - 1.06) / 0.2, 2.0));
		rim = c.g * lip * 1.0;
		float ring = smoothstep(0.95, 1.15, r) * smoothstep(1.85, 1.3, r);
		vec2 cell = floor(q * 30.0);
		float chunks = step(0.7, hash12(cell)) * smoothstep(0.5, 0.15, length(fract(q * 30.0) - 0.5));
		scatter = c.b * ring * chunks;
	} else {
		vec2 p = q / 0.62;
		float sd;
		if (kind == 1) {
			// paw: main pad + four toes + claw nicks
			sd = sd_ellipse(p, vec2(0.0, -0.18), vec2(0.42, 0.34));
			for (int i = 0; i < 4; i++) {
				float x = (float(i) - 1.5) * 0.27;
				vec2 tc = vec2(x, 0.38 - abs(x) * 0.35);
				sd = min(sd, sd_ellipse(p, tc, vec2(0.12, 0.16)));
				sd = min(sd, sd_ellipse(p, tc + vec2(0.0, 0.24), vec2(0.035, 0.07)));
			}
		} else {
			// boot: forefoot + heel joined by a narrow waist
			float fore = sd_ellipse(p, vec2(0.02, 0.32), vec2(0.36, 0.54));
			float heel = sd_ellipse(p, vec2(0.0, -0.60), vec2(0.27, 0.32));
			float waist = sd_ellipse(p, vec2(0.04, -0.16), vec2(0.19, 0.42));
			sd = min(min(fore, heel), waist);
		}
		// soft walls: snow crumbles at the edge (also keeps normals smooth)
		float inside = smoothstep(0.10, -0.09, sd);
		// heel strike and toe push-off are a little deeper; faint tread on the sole
		float profile = kind == 0 ? 0.86 + 0.14 * smoothstep(0.2, 0.75, abs(p.y)) : 1.0;
		float tread = kind == 0 ? 0.94 + 0.06 * step(0.5, fract(p.y * 4.5)) : 1.0;
		depth = c.r * inside * profile * tread;
		rim = c.g * exp(-pow(max(sd - 0.02, 0.0) / 0.16, 2.0)) * (1.0 - inside * 0.85);
		// kicked-out snow ahead of fast steps (scatter is >0 for running prints)
		float ahead = smoothstep(0.0, 0.35, p.y - 0.6) * smoothstep(1.55, 0.9, p.y) * smoothstep(0.75, 0.2, abs(p.x));
		scatter = c.b * ahead * step(0.55, hash12(floor(q * 22.0)));
	}
	float r_new = max(old.r, depth);
	// a fresh print presses down any older rim it lands on
	float g_new = max(old.g, rim) * (1.0 - smoothstep(0.0, 0.08, depth));
	float b_new = max(old.b, scatter) * (1.0 - smoothstep(0.0, 0.2, depth));
	COLOR = vec4(r_new, g_new, b_new, 1.0);
}
