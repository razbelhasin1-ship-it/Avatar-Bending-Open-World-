"""Tiny vector kit for authoring the UI SVGs (emblems, icons).

Shapes are built from tapered strokes: a centre polyline (sampled from Catmull-Rom
splines, spirals, arcs) is offset by a width profile into a filled polygon with round
caps, which reads like a confident brush/ink line. Everything is emitted as plain
filled <path>s (single colour, white) so Godot can tint the imported texture with
`modulate`, and previewed with Pillow so shapes can be iterated without Godot.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

V = np.ndarray


def catmull(points, samples_per_seg: int = 24, closed: bool = False) -> V:
	"""Centripetal-ish uniform Catmull-Rom through `points` -> (N, 2) array."""
	p = np.asarray(points, dtype=float)
	if closed:
		p = np.vstack([p[-1], p, p[0], p[1]])
	else:
		p = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
	out = []
	for i in range(1, len(p) - 2):
		p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
		for k in range(samples_per_seg):
			t = k / samples_per_seg
			t2, t3 = t * t, t * t * t
			out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
					+ (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
	if not closed:
		out.append(p[-2])
	return np.array(out)


def spiral(center, r_in: float, r_out: float, turns: float, end_angle_deg: float, clockwise: bool = True,
		samples: int = 220, power: float = 1.0) -> V:
	"""Spiral from the inner tip (r_in) out to r_out, ENDING at end_angle (screen degrees,
	0 = +x, 90 = +y/down). clockwise=True means the angle increases while moving outward
	(clockwise on screen because y points down)."""
	c = np.asarray(center, dtype=float)
	end = math.radians(end_angle_deg)
	span = turns * 2 * math.pi
	pts = []
	for i in range(samples + 1):
		t = i / samples
		ang = end - span * (1 - t) if clockwise else end + span * (1 - t)
		r = r_in + (r_out - r_in) * (t ** power)
		pts.append(c + r * np.array([math.cos(ang), math.sin(ang)]))
	return np.array(pts)


def arc(center, radius: float, a0_deg: float, a1_deg: float, samples: int = 80, r1: float | None = None) -> V:
	c = np.asarray(center, dtype=float)
	r1 = radius if r1 is None else r1
	pts = []
	for i in range(samples + 1):
		t = i / samples
		a = math.radians(a0_deg + (a1_deg - a0_deg) * t)
		r = radius + (r1 - radius) * t
		pts.append(c + r * np.array([math.cos(a), math.sin(a)]))
	return np.array(pts)


def join(*parts) -> V:
	out = [np.asarray(parts[0], dtype=float)]
	for p in parts[1:]:
		p = np.asarray(p, dtype=float)
		if np.linalg.norm(out[-1][-1] - p[0]) < 1e-6:
			p = p[1:]
		out.append(p)
	return np.vstack(out)


def resample(pts: V, step: float = 2.0) -> V:
	pts = np.asarray(pts, dtype=float)
	seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
	keep = np.concatenate([[True], seg > 1e-9])
	pts = pts[keep]
	seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
	s = np.concatenate([[0.0], np.cumsum(seg)])
	n = max(2, int(math.ceil(s[-1] / step)) + 1)
	ss = np.linspace(0, s[-1], n)
	x = np.interp(ss, s, pts[:, 0])
	y = np.interp(ss, s, pts[:, 1])
	return np.stack([x, y], axis=1)


def smoothstep(e0: float, e1: float, x):
	t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3 - 2 * t)


def profile(w: float, tin: float = 0.12, tout: float = 0.18, min_in: float = 0.35, min_out: float = 0.35,
		belly: float = 0.0):
	"""Width profile: ramps from w*min_in over the first `tin` of the length, to w*min_out
	over the last `tout`; `belly` adds a little swell in the middle."""
	def f(s):
		a = min_in + (1 - min_in) * smoothstep(0, max(tin, 1e-4), s)
		b = min_out + (1 - min_out) * smoothstep(0, max(tout, 1e-4), 1 - s)
		swell = 1 + belly * np.sin(np.pi * s)
		return w * a * b * swell
	return f


@dataclass
class Shape:
	"""A filled polygon (list of rings; first ring is the outline, others are holes when
	evenodd is used)."""
	rings: list = field(default_factory=list)
	evenodd: bool = False


def stroke(pts, width_fn, step: float = 1.5, caps: bool = True) -> Shape:
	pts = resample(pts, step)
	n = len(pts)
	d = np.gradient(pts, axis=0)
	d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
	nrm = np.stack([-d[:, 1], d[:, 0]], axis=1)
	seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
	s = np.concatenate([[0.0], np.cumsum(seg)])
	s /= max(s[-1], 1e-9)
	w = np.asarray(width_fn(s), dtype=float) * 0.5
	left = pts + nrm * w[:, None]
	right = pts - nrm * w[:, None]
	ring = list(left)
	if caps:
		ring += _cap(pts[-1], d[-1], w[-1], forward=True)
	ring += list(right[::-1])
	if caps:
		ring += _cap(pts[0], -d[0], w[0], forward=True)
	return Shape([np.array(ring)])


def _cap(p, d, r, forward=True, n=10):
	if r < 0.4:
		return []
	nrm = np.array([-d[1], d[0]])
	out = []
	for i in range(1, n):
		a = math.pi * i / n
		out.append(p + nrm * r * math.cos(a) - d * (-r * math.sin(a)))
	return out


def ring_shape(center, r_out: float, r_in: float, samples: int = 256) -> Shape:
	c = np.asarray(center, dtype=float)
	ang = np.linspace(0, 2 * math.pi, samples, endpoint=False)
	outer = c + np.stack([np.cos(ang), np.sin(ang)], axis=1) * r_out
	inner = c + np.stack([np.cos(ang[::-1]), np.sin(ang[::-1])], axis=1) * r_in
	return Shape([outer, inner], evenodd=True)


def polygon(points) -> Shape:
	return Shape([np.asarray(points, dtype=float)])


def round_rect(x, y, w, h, r, samples: int = 8) -> Shape:
	pts = []
	for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
		for i in range(samples + 1):
			a = math.radians(a0 + 90 * i / samples)
			pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
	return Shape([np.array(pts)])


def circle(center, r, samples: int = 96) -> Shape:
	c = np.asarray(center, dtype=float)
	ang = np.linspace(0, 2 * math.pi, samples, endpoint=False)
	return Shape([c + np.stack([np.cos(ang), np.sin(ang)], axis=1) * r])


def transform(shape: Shape, scale: float = 1.0, offset=(0.0, 0.0), rotate_deg: float = 0.0, pivot=(0.0, 0.0)) -> Shape:
	a = math.radians(rotate_deg)
	rot = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
	pv = np.asarray(pivot, dtype=float)
	rings = [((r - pv) @ rot.T) * scale + pv * scale + np.asarray(offset) for r in shape.rings]
	return Shape(rings, shape.evenodd)


# --- Output -------------------------------------------------------------------------------

def _ring_d(r) -> str:
	parts = ["M%.1f,%.1f" % (r[0][0], r[0][1])]
	parts += ["L%.1f,%.1f" % (p[0], p[1]) for p in r[1:]]
	return " ".join(parts) + " Z"


def to_svg(shapes, size: int = 512, color: str = "#ffffff") -> str:
	out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (size, size, size, size)]
	for sh in shapes:
		d = " ".join(_ring_d(r) for r in sh.rings)
		rule = ' fill-rule="evenodd"' if sh.evenodd else ""
		out.append('<path fill="%s"%s d="%s"/>' % (color, rule, d))
	out.append("</svg>")
	return "\n".join(out) + "\n"


def preview(shapes, size: int = 512, ss: int = 3, color=(30, 30, 30), bg=(240, 232, 214)):
	from PIL import Image, ImageDraw
	big = Image.new("L", (size * ss, size * ss), 0)
	dr = ImageDraw.Draw(big)
	for sh in shapes:
		if sh.evenodd and len(sh.rings) > 1:
			mask = Image.new("L", big.size, 0)
			md = ImageDraw.Draw(mask)
			for r in sh.rings:
				tmp = Image.new("L", big.size, 0)
				ImageDraw.Draw(tmp).polygon([tuple(p * ss) for p in r], fill=255)
				mask = Image.fromarray(np.bitwise_xor(np.asarray(mask), np.asarray(tmp)))
			big = Image.fromarray(np.maximum(np.asarray(big), np.asarray(mask)))
			dr = ImageDraw.Draw(big)
		else:
			for r in sh.rings:
				dr.polygon([tuple(p * ss) for p in r], fill=255)
	alpha = big.resize((size, size), Image.LANCZOS)
	img = Image.new("RGB", (size, size), bg)
	fg = Image.new("RGB", (size, size), color)
	img.paste(fg, (0, 0), alpha)
	return img
