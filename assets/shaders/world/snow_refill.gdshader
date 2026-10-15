// Trail map maintenance (worldrender SnowTrails):
//   mode 0 (refill): new = max(old - COLOR.rgb, 0)   -- snow slowly fills prints back in
//   mode 1 (clear):  new = 0                          -- strips that scrolled into the window
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int mode = 0;

void fragment() {
	if (mode == 1) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec4 old = texture(screen_tex, SCREEN_UV);
		COLOR = vec4(max(old.rgb - COLOR.rgb, vec3(0.0)), 1.0);
	}
}
