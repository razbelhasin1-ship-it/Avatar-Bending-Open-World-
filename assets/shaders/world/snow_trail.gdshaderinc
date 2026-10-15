// Snow trail sampling (footprints, landing craters) for the terrain shader.
// The trail map is a toroidal window (repeat-wrapped) of `trail_window.z` metres centred on
// trail_window.xy; texel (i, j) covers world [i, i + 1) * texel (mod size). Channels:
//   R  compression depth / trail_max_depth     G  raised rim 0..1     B  loose scatter 0..1
// Requires `splat_map` (snow presence) to be declared before this include.

uniform sampler2D trail_map : filter_linear, repeat_enable, hint_default_black;
// x, z centre, size (m), enabled (0/1)
uniform vec4 trail_window = vec4(0.0, 0.0, 32.0, 0.0);
uniform float trail_texel = 0.032;
uniform float trail_max_depth = 0.5;
uniform float trail_rim_height = 0.08;
// loose chunks (B) raise the surface by up to this much (m)
uniform float trail_scatter_height = 0.035;

float trail_fade(vec2 xz) {
	vec2 d = abs(xz - trail_window.xy) / (trail_window.z * 0.5);
	return trail_window.w * (1.0 - smoothstep(0.86, 0.97, max(d.x, d.y)));
}

float trail_disp(vec4 t) {
	return -t.r * trail_max_depth + (t.g * trail_rim_height + t.b * trail_scatter_height) * (1.0 - smoothstep(0.0, 0.1, t.r));
}

// Vertical displacement (m, negative = pressed down) at xz for a mesh of vertex spacing
// `spacing`, low-pass filtered to that spacing (5 taps) so sharp print features never turn
// into faceted spikes; the fragment normal restores the full-resolution detail.
float trail_displacement(vec2 xz, float spacing) {
	float f = trail_fade(xz);
	if (f <= 0.0) {
		return 0.0;
	}
	vec2 uv = xz / trail_window.z;
	float r = max(spacing * 0.45, trail_texel) / trail_window.z;
	float d = trail_disp(textureLod(trail_map, uv, 0.0)) * 0.4;
	d += trail_disp(textureLod(trail_map, uv + vec2(r, 0.0), 0.0)) * 0.15;
	d += trail_disp(textureLod(trail_map, uv - vec2(r, 0.0), 0.0)) * 0.15;
	d += trail_disp(textureLod(trail_map, uv + vec2(0.0, r), 0.0)) * 0.15;
	d += trail_disp(textureLod(trail_map, uv - vec2(0.0, r), 0.0)) * 0.15;
	float snow = smoothstep(0.12, 0.35, textureLod(splat_map, (xz + 4096.0) / 8192.0, 0.0).r);
	return d * f * snow;
}

// Trail channels at xz (rgb, a = window fade) and the displacement gradient (dm/dm in x, z).
void trail_fragment(vec2 xz, out vec4 tr, out vec2 grad) {
	tr = vec4(0.0);
	grad = vec2(0.0);
	float f = trail_fade(xz);
	if (f <= 0.0) {
		return;
	}
	vec2 uv = xz / trail_window.z;
	// 1.5-texel stencil: wide enough that bilinear facets do not show in the shading
	float e = trail_texel * 1.5;
	float du = e / trail_window.z;
	vec4 c = texture(trail_map, uv);
	float dxp = trail_disp(texture(trail_map, uv + vec2(du, 0.0)));
	float dxm = trail_disp(texture(trail_map, uv - vec2(du, 0.0)));
	float dzp = trail_disp(texture(trail_map, uv + vec2(0.0, du)));
	float dzm = trail_disp(texture(trail_map, uv - vec2(0.0, du)));
	grad = vec2(dxp - dxm, dzp - dzm) / (2.0 * e) * f;
	float gl = length(grad);
	grad *= gl > 2.2 ? 2.2 / gl : 1.0;
	tr = vec4(c.rgb, f);
}
