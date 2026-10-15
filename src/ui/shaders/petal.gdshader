// Drifting petals/leaves (UI panoramas): a pointed-oval silhouette with a soft midrib,
// tinted by the particle colour, flipping (scale x oscillation) as it tumbles.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform vec3 shade : source_color = vec3(0.75, 0.55, 0.55);

varying vec4 pcol;
varying float flip;

void vertex() {
	pcol = COLOR;
	float ph = float(INSTANCE_ID) * 1.618 + TIME * (1.5 + fract(float(INSTANCE_ID) * 0.37) * 2.5);
	flip = sin(ph);
	mat4 bb = mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz) * (0.25 + 0.75 * abs(flip)),
			INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float ang = INSTANCE_CUSTOM.x;
	mat4 rot = mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * rot;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// pointed oval: narrow at both ends
	float w = 0.55 * (1.0 - q.y * q.y);
	float a = smoothstep(w + 0.06, w - 0.02, abs(q.x));
	if (a < 0.3) {
		discard;
	}
	float rib = smoothstep(0.08, 0.0, abs(q.x)) * 0.25;
	vec3 col = mix(pcol.rgb, shade * pcol.rgb, (q.y * 0.5 + 0.5) * 0.6 + rib);
	col *= 0.85 + 0.15 * abs(flip);
	ALBEDO = col;
}
