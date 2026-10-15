"""Authoring script for the four nation emblems (assets/ui/emblem_*.svg).

Run:  python3 assets/ui/authoring/make_emblems.py [preview_dir]
Writes the SVGs next to this folder (assets/ui/) and optional PNG previews.
Designs follow the show's emblems: water = circle with three rising curls over three
waves; earth = trapezoid with a centred spiral and the two step glyphs at the base;
air = three spirals in a triangle whose tails sweep around; fire = flame tongues
rising from a central spiral.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgkit import (Shape, arc, catmull, join, polygon, preview, profile, ring_shape, spiral, stroke, to_svg)  # noqa: E402

OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 512.0


def water() -> list:
	c = np.array([256.0, 256.0])
	R = 222.0
	ring_w = 24.0
	w = 19.0
	shapes = [ring_shape(c, R + ring_w * 0.5, R - ring_w * 0.5)]

	def P(x, y):
		return c + np.array([x, y]) * R

	def clipped(points, radius=0.975):
		pts = catmull([P(x, y) for x, y in points], 30)
		rel = (pts - c) / R
		inside = np.linalg.norm(rel, axis=1) <= radius
		idx = np.where(inside)[0]
		return pts[idx[0]:idx[-1] + 1]

	# Three rising curls (largest on the left), winding out counter-clockwise.
	s1 = spiral(P(-0.53, 0.02), 5, 0.36 * R, 2.15, 96, clockwise=False, power=0.92)
	shapes.append(stroke(s1, profile(w, tin=0.10, tout=0.04, min_in=0.5, min_out=0.95)))
	# The middle curl's outer arm sweeps left over the big curl to the ring.
	s2 = spiral(P(-0.03, -0.30), 4, 0.27 * R, 2.0, 268, clockwise=False, power=0.92)
	arm2 = catmull([s2[-1], P(-0.28, -0.53), P(-0.55, -0.53), P(-0.75, -0.48), P(-0.92, -0.39)], 24)
	shapes.append(stroke(join(s2, arm2), profile(w, tin=0.10, tout=0.04, min_in=0.5, min_out=0.95)))
	# The small curl's arm becomes the top arc meeting the ring above.
	s3 = spiral(P(0.42, -0.52), 3, 0.19 * R, 1.65, 262, clockwise=False, power=0.92)
	arm3 = catmull([s3[-1], P(0.14, -0.77), P(-0.12, -0.88), P(-0.36, -0.95)], 24)
	shapes.append(stroke(join(s3, arm3), profile(w, tin=0.10, tout=0.04, min_in=0.5, min_out=0.95)))
	# Crest line under the curls, then two waves rising to the right.
	lines = [
		[(-1.0, 0.24), (-0.80, 0.37), (-0.53, 0.40), (-0.24, 0.36), (0.0, 0.24), (0.21, 0.08), (0.45, -0.10), (0.67, -0.20), (1.0, -0.25)],
		[(-1.0, 0.50), (-0.70, 0.64), (-0.39, 0.66), (-0.09, 0.57), (0.21, 0.35), (0.52, 0.15), (0.82, 0.04), (1.0, 0.02)],
		[(-0.9, 0.75), (-0.6, 0.86), (-0.30, 0.88), (0.0, 0.80), (0.30, 0.60), (0.58, 0.40), (1.0, 0.28)],
	]
	for pts in lines:
		shapes.append(stroke(clipped(pts), lambda s: np.full_like(s, w), caps=False))
	return shapes


def earth() -> list:
	w = 21.0
	# Trapezoid outline with the open centre at the base (the two step glyphs sit on it).
	top_y, bot_y = 58.0, 466.0
	tl, tr = np.array([168.0, top_y]), np.array([344.0, top_y])
	bl, br = np.array([60.0, bot_y]), np.array([452.0, bot_y])
	gap_l, gap_r = 240.0, 272.0
	step_top = 360.0
	r = 18.0  # top corner rounding

	def corner(a, b, cpt, n=10):
		# quadratic rounding between a->corner->b
		pts = []
		for i in range(n + 1):
			t = i / n
			pts.append((1 - t) ** 2 * a + 2 * (1 - t) * t * cpt + t * t * b)
		return np.array(pts)

	dl = (tl - bl) / np.linalg.norm(tl - bl)
	dr_ = (tr - br) / np.linalg.norm(tr - br)
	outline = join(
		np.array([[gap_l, step_top - 2], [gap_l, bot_y]]),
		np.array([[gap_l, bot_y], bl + np.array([10, 0])]),
		corner(bl + np.array([10, 0]), bl + dl * 10, bl, 4),
		np.array([bl + dl * 10, tl - dl * r]),
		corner(tl - dl * r, tl + np.array([r, 0]), tl),
		np.array([tl + np.array([r, 0]), tr - np.array([r, 0])]),
		corner(tr - np.array([r, 0]), tr - dr_ * r, tr),
		np.array([tr - dr_ * r, br + dr_ * 10]),
		corner(br + dr_ * 10, br - np.array([10, 0]), br, 4),
		np.array([br - np.array([10, 0]), [gap_r, bot_y]]),
		np.array([[gap_r, bot_y], [gap_r, step_top - 2]]),
	)
	shapes = [stroke(outline, lambda s: np.full_like(s, w), step=1.0, caps=False)]
	# square-ish ends of the two vertical strokes
	shapes.append(polygon([[gap_l - w / 2, step_top - 2 - w / 2], [gap_l + w / 2, step_top - 2 - w / 2], [gap_l + w / 2, step_top + 6], [gap_l - w / 2, step_top + 6]]))
	shapes.append(polygon([[gap_r - w / 2, step_top - 2 - w / 2], [gap_r + w / 2, step_top - 2 - w / 2], [gap_r + w / 2, step_top + 6], [gap_r - w / 2, step_top + 6]]))

	# Step bars: two per side, attached to the central verticals (reads as a mirrored pair of "E").
	def bar(x0, x1, y):
		return polygon([[x0, y - w / 2], [x1, y - w / 2], [x1, y + w / 2], [x0, y + w / 2]])
	bar_y = [step_top, 413.0]
	shapes.append(bar(118.0, gap_l, bar_y[0]))
	shapes.append(bar(104.0, gap_l, bar_y[1]))
	shapes.append(bar(gap_r, 394.0, bar_y[0]))
	shapes.append(bar(gap_r, 408.0, bar_y[1]))

	# Spiral in the upper middle: winds clockwise out and ends low on the right.
	sc = np.array([258.0, 210.0])
	sp = spiral(sc, 4, 112, 2.05, 50, clockwise=True, power=0.9)
	shapes.append(stroke(sp, profile(w, tin=0.07, tout=0.03, min_in=0.55, min_out=0.85)))
	return shapes


def air() -> list:
	c = np.array([256.0, 258.0])
	Rc, rs = 120.0, 90.0
	w = 21.0
	shapes = []
	for base in (210.0, 330.0, 90.0):
		a = math.radians(base)
		pc = c + Rc * np.array([math.cos(a), math.sin(a)])
		sp = spiral(pc, 4, rs, 2.05, base, clockwise=True, power=1.0)
		tail = arc(c, Rc + rs, base, base + 62.0, 60, r1=Rc + rs + 4)
		shapes.append(stroke(join(sp, tail), profile(w, tin=0.08, tout=0.14, min_in=0.55, min_out=0.12)))
	return shapes


def fire() -> list:
	w = 23.0

	def T(pts):
		# coordinates traced on an 800 px sketch -> 512 canvas
		p = np.asarray(pts, dtype=float)
		return (p - np.array([408.0, 400.0])) * 0.66 + np.array([256.0, 258.0])

	def line(pts, prof, n=26):
		return stroke(catmull(T(pts), n), prof)

	tip = lambda wm, tin=0.18, tout=0.18, mi=0.06, mo=0.06: profile(w * wm, tin=tin, tout=tout, min_in=mi, min_out=mo)
	shapes = []
	# Left lick "<": two strokes meeting in a sharp tip.
	shapes.append(line([(118, 328), (168, 352), (226, 388), (256, 418), (272, 452)], tip(1.0, 0.3, 0.05, 0.08, 0.8)))
	shapes.append(line([(118, 328), (142, 392), (114, 470), (106, 560), (124, 630), (184, 690)], tip(1.0, 0.3, 0.3)))
	# Right lick ">": inner edge down to the spiral, outer edge down the right side.
	shapes.append(line([(642, 194), (598, 236), (548, 300), (512, 368), (500, 420), (512, 452)], tip(1.0, 0.3, 0.06, 0.08, 0.8)))
	shapes.append(line([(642, 194), (606, 258), (612, 330), (660, 400), (704, 480), (706, 568), (668, 640), (614, 674)], tip(1.0, 0.3, 0.3)))
	# Outer bowl: from the inner-left flame tip around the base up into the inner-right flame.
	shapes.append(line([(206, 414), (200, 500), (210, 600), (262, 680), (350, 726), (450, 738), (548, 716), (612, 664), (618, 590), (594, 500), (570, 420), (566, 318)], tip(1.05, 0.12, 0.2, 0.08, 0.06)))
	# Centre: spiral whose outer arm rises into the tall tongue (left edge) ...
	sc = T([(392, 578)])[0]
	sp = spiral(sc, 3.0, 92, 2.25, 205, clockwise=True, power=0.85)
	left_edge = catmull([sp[-1]] + list(T([(266, 400), (290, 300), (350, 220), (390, 150), (412, 58)])), 26)
	shapes.append(stroke(join(sp, left_edge), profile(w, tin=0.06, tout=0.2, min_in=0.5, min_out=0.06)))
	# ... and its right edge curving back down into the spiral.
	shapes.append(line([(412, 58), (466, 130), (490, 220), (476, 300), (452, 360), (466, 408), (502, 452), (528, 520)], tip(1.0, 0.2, 0.06, 0.06, 0.9)))
	# Inner flame of the tall tongue.
	shapes.append(line([(292, 470), (318, 380), (362, 296), (404, 236), (436, 186)], tip(0.9, 0.08, 0.35, 0.9, 0.06)))
	return shapes


EMBLEMS = {"water": water, "earth": earth, "air": air, "fire": fire}

if __name__ == "__main__":
	prev_dir = sys.argv[1] if len(sys.argv) > 1 else ""
	colors = {"water": (30, 50, 140), "earth": (30, 110, 30), "air": (40, 150, 180), "fire": (160, 20, 20)}
	for name, fn in EMBLEMS.items():
		shapes = fn()
		with open(os.path.join(OUT, "emblem_%s.svg" % name), "w") as f:
			f.write(to_svg(shapes))
		if prev_dir:
			preview(shapes, color=colors[name], bg=(255, 255, 255)).save(os.path.join(prev_dir, "emblem_%s.png" % name))
	print("emblems written to", OUT)
