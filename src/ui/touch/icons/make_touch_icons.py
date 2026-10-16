"""Authoring script for the touch-control glyphs (src/ui/touch/icons/touch_*.svg).

Run:  python3 src/ui/touch/icons/make_touch_icons.py [preview_dir]
Same brush/ink kit as the HUD icons (assets/ui/authoring/svgkit.py): single-colour white
silhouettes on a 128 px canvas, tinted in Godot. The touch buttons draw these inside
their lacquer discs; the Strike button uses the element emblem instead.
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "assets", "ui", "authoring"))
from svgkit import (Shape, arc, catmull, circle, polygon, preview, profile, ring_shape, round_rect,  # noqa: E402
		stroke, to_svg)


def const(w):
	return lambda s: np.full_like(s, w)


def chevron(cx, cy, w, h, width, up=True):
	sgn = -1 if up else 1
	return stroke(np.array([(cx - w, cy - sgn * h * 0.5), (cx, cy + sgn * h * 0.5), (cx + w, cy - sgn * h * 0.5)]),
			profile(width, 0.25, 0.25, 0.55, 0.55), step=1.0)


def touch_jump():
	# two rising chevrons over a ground stroke (leap)
	return [chevron(64, 36, 34, 30, 15), chevron(64, 66, 30, 26, 12),
			stroke(catmull([(22, 106), (64, 100), (106, 106)], 12), profile(9, 0.3, 0.3, 0.2, 0.2))]


def touch_descend():
	return [chevron(64, 58, 34, 30, 15, up=False), chevron(64, 86, 30, 26, 12, up=False),
			stroke(catmull([(22, 24), (64, 18), (106, 24)], 12), profile(9, 0.3, 0.3, 0.2, 0.2))]


def touch_dodge():
	# a body-length swoosh ending in an arrow head, with trailing speed strokes
	s = [stroke(catmull([(14, 92), (40, 76), (70, 70), (100, 64)], 16), profile(14, 0.4, 0.1, 0.1, 0.9)),
			polygon([(92, 44), (124, 62), (96, 86)])]
	for y, x0, x1, w in ((40, 18, 62, 8), (56, 8, 44, 7), (106, 34, 70, 6)):
		s.append(stroke(np.array([(x0, y), (x1, y)]), profile(w, 0.5, 0.3, 0.1, 0.5)))
	return s


def touch_heavy():
	# gathered core + rays + an open charge arc (hold to charge)
	s = [circle((64, 64), 17)]
	for i in range(6):
		a = math.radians(i * 60 - 90)
		p0 = (64 + 26 * math.cos(a), 64 + 26 * math.sin(a))
		p1 = (64 + 44 * math.cos(a), 64 + 44 * math.sin(a))
		s.append(stroke(np.array([p0, p1]), profile(12, 0.1, 0.9, 1.0, 0.15)))
	s.append(stroke(arc((64, 64), 57, -60, 200, 90), profile(7, 0.2, 0.6, 0.2, 1.0)))
	return s


def touch_defend():
	# guard crest: a shield outline with a raised forearm stroke inside
	outer = catmull([(64, 8), (88, 18), (112, 18), (110, 62), (92, 98), (64, 122), (36, 98), (18, 62), (16, 18), (40, 18)], 10, closed=True)
	inner = catmull([(64, 24), (84, 32), (98, 32), (96, 62), (82, 90), (64, 106), (46, 90), (32, 62), (30, 32), (44, 32)], 10, closed=True)
	return [Shape([outer, inner], evenodd=True),
			stroke(catmull([(64, 36), (66, 64), (64, 94)], 8), profile(13, 0.2, 0.3, 0.5, 0.3))]


def touch_pause():
	return [stroke(np.array([(46, 26), (46, 102)]), profile(20, 0.12, 0.12, 0.6, 0.6)),
			stroke(np.array([(82, 26), (82, 102)]), profile(20, 0.12, 0.12, 0.6, 0.6))]


def touch_lock():
	# reticle: open ring, four inward ticks, centre diamond
	s = []
	for a0 in (20, 110, 200, 290):
		s.append(stroke(arc((64, 64), 46, a0, a0 + 50, 30), profile(9, 0.3, 0.3, 0.4, 0.4)))
	for i in range(4):
		a = math.radians(i * 90 - 90)
		p0 = (64 + 60 * math.cos(a), 64 + 60 * math.sin(a))
		p1 = (64 + 34 * math.cos(a), 64 + 34 * math.sin(a))
		s.append(stroke(np.array([p0, p1]), profile(10, 0.1, 0.8, 1.0, 0.2)))
	s.append(polygon([(64, 52), (76, 64), (64, 76), (52, 64)]))
	return s


def touch_map():
	# folded map: three panels, the middle one pierced by a marker
	left = polygon([(10, 26), (44, 14), (44, 104), (10, 116)])
	right = polygon([(88, 26), (118, 14), (118, 104), (88, 116)])
	mid = np.array([(50, 14), (82, 26), (82, 116), (50, 104)], float)
	pin = np.array([(66, 40), (76, 54), (66, 82), (56, 54)], float)
	return [left, right, Shape([mid, pin], evenodd=True)]


def touch_journal():
	# bound book with a ribbon
	outer = round_rect(18, 12, 92, 104, 10).rings[0]
	inner = round_rect(34, 24, 66, 80, 4).rings[0][::-1]
	return [Shape([outer, inner], evenodd=True), polygon([(56, 104), (72, 104), (72, 124), (64, 116), (56, 124)]),
			stroke(np.array([(44, 46), (90, 46)]), const(7)), stroke(np.array([(44, 62), (84, 62)]), const(7))]


def touch_interact():
	# open palm: palm pad, four fingers, thumb
	s = [polygon(catmull([(36, 70), (40, 112), (64, 124), (92, 112), (98, 72), (64, 62)], 12, closed=True))]
	for x, top, w in ((42, 26, 13), (58, 12, 14), (74, 14, 14), (90, 28, 12)):
		s.append(stroke(np.array([(x, 78), (x + (x - 66) * 0.08, top)]), profile(w, 0.1, 0.25, 1.0, 0.75)))
	s.append(stroke(catmull([(38, 92), (24, 74), (14, 56)], 10), profile(13, 0.1, 0.3, 1.0, 0.7)))
	return s


def touch_dismount():
	# saddle line with an arrow leaping off it, down and to the side
	return [stroke(catmull([(10, 40), (40, 52), (70, 40)], 12), profile(11, 0.3, 0.3, 0.3, 0.3)),
			stroke(catmull([(48, 30), (78, 22), (100, 50), (100, 86)], 16), profile(12, 0.3, 0.1, 0.3, 1.0)),
			polygon([(80, 82), (120, 82), (100, 118)])]


def touch_call():
	# paw print inside a calling arc
	s = [Shape([np.array([(64 + 20 * math.cos(a), 84 + 17 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 64, endpoint=False)])])]
	for x, y, r in ((38, 62, 9), (54, 46, 10), (74, 46, 10), (90, 62, 9)):
		s.append(circle((x, y), r))
	s.append(stroke(arc((64, 64), 58, 200, 340, 60), profile(7, 0.25, 0.25, 0.2, 0.2)))
	return s


ICONS = {
	"touch_jump": touch_jump, "touch_descend": touch_descend, "touch_dodge": touch_dodge, "touch_heavy": touch_heavy,
	"touch_defend": touch_defend, "touch_pause": touch_pause, "touch_lock": touch_lock, "touch_map": touch_map,
	"touch_journal": touch_journal, "touch_interact": touch_interact, "touch_dismount": touch_dismount,
	"touch_call": touch_call,
}

if __name__ == "__main__":
	prev_dir = sys.argv[1] if len(sys.argv) > 1 else ""
	sheet = None
	if prev_dir:
		from PIL import Image
		cols = 6
		rows = (len(ICONS) + cols - 1) // cols
		sheet = Image.new("RGB", (cols * 136, rows * 136), (40, 32, 28))
	for i, (name, fn) in enumerate(ICONS.items()):
		shapes = fn()
		with open(os.path.join(HERE, "%s.svg" % name), "w") as f:
			f.write(to_svg(shapes, size=128))
		if sheet is not None:
			img = preview(shapes, size=128, color=(240, 228, 200), bg=(40, 32, 28))
			sheet.paste(img, ((i % cols) * 136 + 4, (i // cols) * 136 + 4))
	if sheet is not None:
		os.makedirs(prev_dir, exist_ok=True)
		sheet.save(os.path.join(prev_dir, "touch_icons.png"))
	print("touch icons written to", HERE)
