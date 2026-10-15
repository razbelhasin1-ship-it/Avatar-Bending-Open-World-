class_name RigHeadShape
extends RefCounted
## Analytic stylized head surface: point(theta, phi) on a deformed ellipsoid
## (round cranium, tapered jaw, soft chin). theta is the azimuth (0 = front/-Z,
## increasing toward the character's right/+X), phi the polar angle from the
## crown (0) to the bottom (PI). Face features and hair are placed with the same
## function so they hug the head exactly.

var c := Vector3.ZERO
var hw := 0.09
var hh := 0.13
var hdf := 0.10
var hdb := 0.115
var jaw := 0.6
var cheek := 0.0
## Effective radius used to convert face-space meters into angles.
var r_face := 0.1


static func from_def(d: RigSkeletonDef) -> RigHeadShape:
	var s := RigHeadShape.new()
	var head_h: float = d.p["head_h"]
	s.c = d.p["skull_c"]
	s.hw = head_h * 0.5 * float(d.p["head_w"]) * 0.74
	s.hh = head_h * 0.5
	s.hdf = head_h * 0.5 * 0.80
	s.hdb = head_h * 0.5 * 0.86
	s.jaw = d.p["jaw"]
	s.cheek = 0.06 if d.p["age"] == "child" else 0.025
	s.r_face = (s.hw + s.hdf) * 0.5
	return s


func point(th: float, ph: float, lift: float = 0.0) -> Vector3:
	var sp := sin(ph)
	var sx := sp * sin(th)
	var sy := cos(ph)
	var sz := -sp * cos(th)
	var x := sx * hw
	var y := sy * hh
	var z := sz * (hdf if sz < 0.0 else hdb)
	var lower := smoothstep(0.2, -0.92, sy)
	x *= lerpf(1.0, jaw, pow(lower, 1.5))
	if sz < 0.0:
		z *= lerpf(1.0, 0.86, lower)
		# Chin: pushed slightly forward and down for a defined jaw line.
		var chin := smoothstep(-0.5, -0.92, sy) * clampf(-sz * 2.5, 0.0, 1.0)
		z -= hdf * 0.07 * chin
		y -= hh * 0.04 * chin
		# Cheeks: a soft widening just below the eye line on the front half.
		x *= 1.0 + cheek * exp(-pow((sy + 0.25) / 0.28, 2.0)) * clampf(-sz * 1.6, 0.0, 1.0)
		# Slightly flatter face plane.
		z *= 1.0 - 0.06 * clampf(1.0 - absf(sx) * 2.0, 0.0, 1.0) * smoothstep(0.6, -0.2, sy)
	else:
		z *= lerpf(1.0, 0.58, smoothstep(-0.05, -0.85, sy))
	y *= lerpf(1.0, 0.95, smoothstep(0.55, 1.0, sy))
	var p := c + Vector3(x, y, z)
	if lift != 0.0:
		p += normal(th, ph) * lift
	return p


func normal(th: float, ph: float) -> Vector3:
	var e := 0.01
	var dth := point(th + e, ph) - point(th - e, ph)
	var ph0 := ph - e
	var ph1 := ph + e
	var dph := point(th, ph1) - point(th, ph0)
	var n := dth.cross(dph)
	if absf(sin(ph)) < 0.02 or n.length_squared() < 1e-14:
		return (point(th, ph) - c).normalized()
	return n.normalized()


## Face-space mapping: (u, v) meters around (th0, ph0), u = viewer's right,
## v = up. Returns [pos, normal].
func face_surf(th0: float, ph0: float, u: float, v: float, lift: float) -> Array:
	var th := th0 - u / r_face
	var ph := ph0 - v / r_face
	var n := normal(th, ph)
	return [point(th, ph) + n * lift, n]


## Polar angle where the head surface sits at model-space height y (front).
func phi_at_height(y: float, th: float = 0.0) -> float:
	var lo := 0.0
	var hi := PI
	for i in 24:
		var mid := (lo + hi) * 0.5
		if point(th, mid).y > y:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5
