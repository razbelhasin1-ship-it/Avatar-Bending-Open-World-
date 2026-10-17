// Airbending wind impulses for world shaders (vegetation sway, grass, cloth): up to four
// short-lived gusts written every frame by AirWindField (src/fx/air/air_wind_field.gd) into
// global uniforms registered by WorldShaderGlobals. Each slot i is two columns:
//   air_impulse_a[i] = (centre.xyz, radius m)
//   air_impulse_b[i] = (dir.x, dir.z, mode, strength)   mode 0 directional, 1 radial, 2 vortex
// strength is an extra wind speed in m/s (it swings negative while the plants spring back).
// air_impulse_on is 0 while no slot is live, so the cost is one uniform branch.

global uniform mat4 air_impulse_a;
global uniform mat4 air_impulse_b;
global uniform float air_impulse_on;

vec3 air_impulse_slot(vec4 a, vec4 b, vec3 p) {
	if (abs(b.w) < 0.01) {
		return vec3(0.0);
	}
	vec3 d = p - a.xyz;
	float dist = length(d.xz);
	float r = max(a.w, 0.2);
	float fall = 1.0 - smoothstep(r * 0.4, r, dist);
	fall *= 1.0 - smoothstep(4.0, 10.0, abs(d.y));
	vec2 radial = dist > 0.05 ? d.xz / dist : vec2(0.0);
	vec2 dir2 = b.xy;
	if (b.z > 1.5) {
		// vortex: swirl around the centre and draw in (b.x = spin sign)
		dir2 = vec2(-radial.y, radial.x) * sign(b.x + 0.0001) - radial * 0.55;
	} else if (b.z > 0.5) {
		dir2 = radial;
	}
	return vec3(dir2.x, 0.0, dir2.y) * b.w * fall;
}

// Horizontal wind (m/s) the airbending impulses add at world point `p`.
vec3 air_impulse_at(vec3 p) {
	if (air_impulse_on < 0.5) {
		return vec3(0.0);
	}
	return air_impulse_slot(air_impulse_a[0], air_impulse_b[0], p) + air_impulse_slot(air_impulse_a[1], air_impulse_b[1], p)
			+ air_impulse_slot(air_impulse_a[2], air_impulse_b[2], p) + air_impulse_slot(air_impulse_a[3], air_impulse_b[3], p);
}
