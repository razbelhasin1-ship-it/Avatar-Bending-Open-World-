// Heat shimmer: a camera-facing quad that refracts what is behind it with
// rising noise (over fires, explosions, a full Blaze Charge). Uses the screen
// texture, so it is only spawned where that is cheap (Forward+, effects >= high);
// everything still reads without it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float strength = 0.012;
uniform float opacity = 1.0;
uniform float rise = 0.9;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// q.y: -1 top .. 1 bottom. Strongest low in the column, fading to the top and the sides.
	float side = 1.0 - smoothstep(0.4, 1.0, abs(q.x));
	float vert = (1.0 - smoothstep(0.75, 1.0, q.y)) * (0.3 + 0.7 * smoothstep(-1.0, 0.3, q.y));
	float mask = side * vert * opacity;
	float nx = texture(noise_tex, UV * vec2(1.6, 1.1) + vec2(0.0, TIME * rise)).r - 0.5;
	float ny = texture(noise_tex, UV * vec2(1.3, 0.9) + vec2(0.37, TIME * rise * 1.3)).r - 0.5;
	vec2 suv = SCREEN_UV + vec2(nx, ny) * strength * mask;
	ALBEDO = texture(screen_tex, suv).rgb;
	ALPHA = clamp(mask * 1.5, 0.0, 1.0);
}
