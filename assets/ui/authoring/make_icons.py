"""Authoring script for the UI icon set (assets/ui/icon_*.svg, ability_*.svg, ui_*.svg).

Run:  python3 assets/ui/authoring/make_icons.py [preview_dir]
All icons are single-colour white silhouettes on a 128 px canvas (tinted in Godot via
`modulate`/`self_modulate`), drawn with the same tapered-stroke kit as the emblems so
they share the brush/ink character.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgkit import (Shape, arc, catmull, circle, join, polygon, preview, profile, ring_shape, round_rect, spiral,
		stroke, to_svg, transform)  # noqa: E402

OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = 128.0


def const(w):
	return lambda s: np.full_like(s, w)


def leaf(p0, p1, width, bend=0.0, samples=40):
	"""Pointed leaf/petal from p0 (base) to p1 (tip)."""
	p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
	d = p1 - p0
	L = np.linalg.norm(d)
	t = d / L
	n = np.array([-t[1], t[0]])
	pts_l, pts_r = [], []
	for i in range(samples + 1):
		u = i / samples
		half = width * 0.5 * math.sin(math.pi * u) ** 0.8 * (1.0 - 0.25 * u)
		center = p0 + d * u + n * bend * L * math.sin(math.pi * u)
		pts_l.append(center + n * half)
		pts_r.append(center - n * half)
	return polygon(pts_l + pts_r[::-1])


def star(center, r_out, r_in, points, rot_deg=-90.0):
	c = np.asarray(center, float)
	pts = []
	for i in range(points * 2):
		r = r_out if i % 2 == 0 else r_in
		a = math.radians(rot_deg + 180.0 * i / points)
		pts.append(c + r * np.array([math.cos(a), math.sin(a)]))
	return polygon(pts)


# --- HUD / notification icons ---------------------------------------------------------------

def icon_health():
	# lotus bud: tall centre petal, two side petals, a short stem cradle
	return [
		leaf((64, 112), (64, 14), 46),
		leaf((60, 112), (16, 46), 34, bend=0.12),
		leaf((68, 112), (112, 46), 34, bend=-0.12),
		stroke(catmull([(30, 108), (64, 120), (98, 108)], 20), profile(9, 0.3, 0.3, 0.3, 0.3)),
	]


def icon_chi():
	# yin-yang: ring, one filled half (with a hole), a dot in the other half
	ang = np.linspace(-math.pi / 2, math.pi / 2, 60)
	big = [(64 + 46 * math.cos(a), 64 + 46 * math.sin(a)) for a in ang]
	lower = [(64 + 23 * math.cos(a), 87 + 23 * math.sin(a)) for a in np.linspace(math.pi / 2, 3 * math.pi / 2, 40)]
	upper = [(64 + 23 * math.cos(a), 41 + 23 * math.sin(a)) for a in np.linspace(math.pi / 2, -math.pi / 2, 40)]
	half = np.array(big + lower + upper)
	hole = np.array([(64 + 7 * math.cos(a), 41 + 7 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 32, endpoint=False)])[::-1]
	return [ring_shape((64, 64), 58, 50), Shape([half, hole], evenodd=True), circle((64, 87), 7)]


def icon_focus():
	# focus: concentric target with four ticks
	s = [ring_shape((64, 64), 40, 31), polygon([(64, 46), (82, 64), (64, 82), (46, 64)])]
	for a in (0, 90, 180, 270):
		r = math.radians(a)
		d = np.array([math.cos(r), math.sin(r)])
		n = np.array([-d[1], d[0]])
		p0, p1 = np.array([64.0, 64.0]) + d * 44, np.array([64.0, 64.0]) + d * 62
		s.append(polygon([p0 + n * 6, p1 + n * 2, p1 - n * 2, p0 - n * 6]))
	return s


def icon_quest():
	# rolled scroll
	body = round_rect(28, 22, 72, 84, 6)
	shapes = [body]
	shapes.append(round_rect(18, 12, 92, 18, 9))
	shapes.append(round_rect(18, 98, 92, 18, 9))
	return shapes + [polygon([(40, 44), (88, 44), (88, 50), (40, 50)]), polygon([(40, 60), (88, 60), (88, 66), (40, 66)]),
			polygon([(40, 76), (74, 76), (74, 82), (40, 82)])]


def icon_quest_evenodd():
	# scroll with the text lines cut out (single path, evenodd)
	outer = round_rect(28, 22, 72, 84, 6).rings[0]
	lines = [np.array([(40, 44), (88, 44), (88, 50), (40, 50)])[::-1], np.array([(40, 60), (88, 60), (88, 66), (40, 66)])[::-1],
			np.array([(40, 76), (74, 76), (74, 82), (40, 82)])[::-1]]
	return [Shape([outer] + lines, evenodd=True), round_rect(18, 12, 92, 18, 9), round_rect(18, 98, 92, 18, 9)]


def icon_marker():
	outer = np.array([(64, 6), (110, 52), (64, 122), (18, 52)])
	inner = np.array([(64, 30), (86, 52), (64, 86), (42, 52)])[::-1]
	return [Shape([outer, inner], evenodd=True)]


def icon_discovery():
	return [star((64, 64), 60, 16, 4), star((64, 64), 40, 14, 4, rot_deg=-45), circle((64, 64), 9)]


def icon_unlock():
	# white lotus Pai Sho tile: ring + eight petals
	s = [ring_shape((64, 64), 60, 52)]
	for i in range(8):
		a = math.radians(i * 45 - 90)
		tip = (64 + 42 * math.cos(a), 64 + 42 * math.sin(a))
		s.append(leaf((64, 64), tip, 18))
	s.append(circle((64, 64), 9))
	return s


def icon_warning():
	tri = np.array([(64, 8), (122, 114), (6, 114)])
	bar = np.array([(58, 42), (70, 42), (68, 82), (60, 82)])[::-1]
	dot = np.array([(58, 92), (70, 92), (70, 104), (58, 104)])[::-1]
	return [Shape([tri, bar, dot], evenodd=True)]


def icon_info():
	ang = np.linspace(0, 2 * math.pi, 96, endpoint=False)
	disc = np.stack([64 + 58 * np.cos(ang), 64 + 58 * np.sin(ang)], axis=1)
	bar = np.array([(57, 52), (71, 52), (71, 98), (57, 98)])[::-1]
	dot = np.stack([64 + 8 * np.cos(ang), 36 + 8 * np.sin(ang)], axis=1)[::-1]
	return [Shape([disc, bar, dot], evenodd=True)]


def icon_lock():
	s = []
	L, t, m = 34, 9, 8
	for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
		cx = 64 - sx * (64 - m)
		cy = 64 - sy * (64 - m)
		s.append(polygon([(cx, cy), (cx + sx * L, cy), (cx + sx * L, cy + sy * t), (cx + sx * t, cy + sy * t), (cx + sx * t, cy + sy * L), (cx, cy + sy * L)]))
	s.append(polygon([(64, 50), (78, 64), (64, 78), (50, 64)]))
	return s


def icon_paw():
	s = [Shape([np.array([(64 + 26 * math.cos(a), 88 + 22 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 64, endpoint=False)])])]
	for x, y, r in ((30, 56, 12), (50, 36, 13), (78, 36, 13), (98, 56, 12)):
		s.append(circle((x, y), r))
	return s


def icon_save():
	# brush seal (chop) with a downward stroke: "saved"
	outer = round_rect(14, 14, 100, 100, 14).rings[0]
	inner = round_rect(26, 26, 76, 76, 8).rings[0][::-1]
	return [Shape([outer, inner], evenodd=True), polygon([(56, 34), (72, 34), (72, 70), (86, 70), (64, 94), (42, 70), (56, 70)])]


# --- Technique icons (generic, used by previews/mock data; bending may ship its own) -------

def ability_blast():
	s = [circle((64, 64), 22)]
	for i in range(8):
		a = math.radians(i * 45 + 22.5)
		p0 = (64 + 30 * math.cos(a), 64 + 30 * math.sin(a))
		p1 = (64 + 60 * math.cos(a), 64 + 60 * math.sin(a))
		s.append(stroke(np.array([p0, p1]), profile(13, 0.1, 0.9, 1.0, 0.1)))
	return s


def ability_wall():
	return [
		polygon([(12, 118), (116, 118), (110, 86), (18, 86)]),
		polygon([(22, 80), (106, 80), (100, 50), (28, 50)]),
		polygon([(32, 44), (96, 44), (90, 26), (78, 14), (62, 22), (48, 10), (38, 24)]),
	]


def ability_wave():
	sp = spiral((70, 50), 3, 30, 1.6, 180, clockwise=False)
	body = catmull([sp[-1], (36, 74), (34, 96), (62, 110), (116, 110)], 20)
	return [stroke(join(sp, body), profile(15, 0.12, 0.06, 0.45, 0.9)),
			stroke(catmull([(8, 122), (64, 116), (122, 122)], 20), profile(7, 0.2, 0.2, 0.4, 0.4))]


def ability_shield():
	return [stroke(arc((64, 96), 54, 180, 360, 80), profile(14, 0.15, 0.15, 0.3, 0.3)),
			stroke(arc((64, 96), 32, 190, 350, 60), profile(10, 0.2, 0.2, 0.3, 0.3)),
			polygon([(8, 106), (120, 106), (120, 116), (8, 116)])]


def ability_spikes():
	return [polygon([(10, 118), (30, 36), (48, 118)]), polygon([(40, 118), (64, 8), (88, 118)]),
			polygon([(80, 118), (98, 46), (118, 118)])]


def ability_whirl():
	s = []
	for i, (y, rx) in enumerate(((22, 52), (44, 42), (64, 32), (82, 23), (98, 15))):
		pts = [(64 + rx * math.cos(a) + (i % 2) * 3, y + rx * 0.22 * math.sin(a)) for a in np.linspace(math.radians(200), math.radians(520), 60)]
		s.append(stroke(np.array(pts), profile(11 - i, 0.15, 0.25, 0.3, 0.2)))
	s.append(stroke(catmull([(64, 104), (60, 114), (66, 124)], 10), profile(8, 0.2, 0.5, 0.8, 0.2)))
	return s


def ability_flame():
	out = catmull([(64, 124), (24, 104), (20, 70), (36, 46), (44, 62), (50, 30), (64, 4), (70, 34), (84, 48), (92, 34), (106, 66), (104, 104), (64, 124)], 16)
	return [polygon(out)]


def ability_shards():
	s = []
	for x0, y0, x1, y1, w in ((14, 112, 70, 20, 20), (40, 120, 100, 34, 18), (70, 124, 118, 64, 15)):
		s.append(polygon([(x0, y0), (x0 + (x1 - x0) * 0.25 - w * 0.5, y0 + (y1 - y0) * 0.25), (x1, y1), (x0 + (x1 - x0) * 0.25 + w * 0.5, y0 + (y1 - y0) * 0.25)]))
	return s


def ability_sweep():
	outer = [(64 + 56 * math.cos(a), 70 + 56 * math.sin(a)) for a in np.linspace(math.radians(160), math.radians(380), 60)]
	inner = [(64 + 40 * math.cos(a), 80 + 40 * math.sin(a)) for a in np.linspace(math.radians(380), math.radians(160), 60)]
	return [polygon(outer + inner), polygon([(110, 78), (126, 66), (124, 92)])]


def ui_chevron():
	return [stroke(np.array([(40, 16), (90, 64)]), const(16)), stroke(np.array([(90, 64), (40, 112)]), const(16))]


def ui_check():
	return [stroke(np.array([(18, 66), (50, 98)]), const(16)), stroke(np.array([(50, 98), (110, 28)]), const(16))]


def ui_diamond():
	return [polygon([(64, 4), (124, 64), (64, 124), (4, 64)])]


def ui_corner():
	# ruyi cloud corner: a curl at the corner with tails running along both edges
	sp = spiral((34, 34), 3, 18, 1.5, 135, clockwise=True)
	top = catmull([sp[-1], (16, 24)], 4)
	s = [stroke(sp, profile(7, 0.15, 0.05, 0.4, 1.0))]
	s.append(stroke(catmull([(6, 124), (6, 70), (8, 40), (20, 22), (40, 8), (70, 6), (124, 6)], 20), profile(6, 0.25, 0.25, 0.1, 0.1)))
	s.append(stroke(catmull([(16, 96), (16, 62), (24, 46)], 12), profile(4, 0.3, 0.3, 0.1, 0.5)))
	s.append(stroke(catmull([(96, 16), (62, 16), (46, 24)], 12), profile(4, 0.3, 0.3, 0.1, 0.5)))
	return s


ICONS = {
	"icon_health": icon_health, "icon_chi": icon_chi, "icon_focus": icon_focus, "icon_quest": icon_quest_evenodd,
	"icon_marker": icon_marker, "icon_discovery": icon_discovery, "icon_unlock": icon_unlock, "icon_warning": icon_warning,
	"icon_info": icon_info, "icon_lock": icon_lock, "icon_paw": icon_paw, "icon_save": icon_save,
	"ability_blast": ability_blast, "ability_wall": ability_wall, "ability_wave": ability_wave, "ability_shield": ability_shield,
	"ability_spikes": ability_spikes, "ability_whirl": ability_whirl, "ability_flame": ability_flame,
	"ability_shards": ability_shards, "ability_sweep": ability_sweep,
	"ui_chevron": ui_chevron, "ui_check": ui_check, "ui_diamond": ui_diamond, "ui_corner": ui_corner,
}

if __name__ == "__main__":
	prev_dir = sys.argv[1] if len(sys.argv) > 1 else ""
	sheet = None
	if prev_dir:
		from PIL import Image
		cols = 7
		rows = (len(ICONS) + cols - 1) // cols
		sheet = Image.new("RGB", (cols * 136, rows * 136), (40, 32, 28))
	for i, (name, fn) in enumerate(ICONS.items()):
		shapes = fn()
		with open(os.path.join(OUT, "%s.svg" % name), "w") as f:
			f.write(to_svg(shapes, size=128))
		if sheet is not None:
			img = preview(shapes, size=128, color=(240, 228, 200), bg=(40, 32, 28))
			sheet.paste(img, ((i % 7) * 136 + 4, (i // 7) * 136 + 4))
	if sheet is not None:
		sheet.save(os.path.join(prev_dir, "icons.png"))
	print("icons written to", OUT)
