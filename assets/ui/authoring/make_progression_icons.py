"""Authoring script for the Journey Book icons (progression_ui module):
tab icons (icon_skills, icon_map, icon_journal, icon_bag, icon_character), ui_close and the
world-map glyphs (map_*.svg).

Run:  python3 assets/ui/authoring/make_progression_icons.py [preview_dir]
Same conventions as make_icons.py: single-colour white silhouettes on a 128 px canvas, drawn
with the svgkit tapered-stroke kit so they share the brush / ink character of the UI.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgkit import (Shape, arc, catmull, circle, polygon, preview, profile, ring_shape, round_rect, spiral,  # noqa: E402
		stroke, to_svg)

OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def const(w):
	return lambda s: np.full_like(s, w)


def brush(points, w, tin=0.15, tout=0.2, mn=0.35, mo=0.3, samples=20):
	return stroke(catmull(points, samples), profile(w, tin, tout, mn, mo))


def line(p0, p1, w):
	return stroke(np.array([p0, p1]), const(w))


# --- tab icons ------------------------------------------------------------------------------------

def icon_skills():
	# three interlocking brush swirls (the turning of chi) around a still centre
	s = []
	for i in range(3):
		a = i * 120.0
		sp = spiral((64, 64), 6, 46, 0.62, a + 200, clockwise=True)
		s.append(stroke(sp, profile(15, 0.08, 0.35, 0.25, 0.08)))
	s.append(circle((64, 64), 9))
	return s


def icon_map():
	# folded chart: three panels in a zigzag with a dashed route and a destination mark
	panels = [
		polygon([(10, 26), (46, 14), (46, 104), (10, 116)]),
		polygon([(50, 14), (80, 26), (80, 116), (50, 104)]),
		polygon([(84, 26), (118, 14), (118, 104), (84, 116)]),
	]
	holes = []
	pts = [(22, 92), (36, 74), (58, 80), (70, 60), (94, 56), (104, 38)]
	for i in range(len(pts) - 1):
		a, b = np.array(pts[i], float), np.array(pts[i + 1], float)
		mid = (a + b) * 0.5
		holes.append(circle(tuple(mid), 3.2, 16))
	ring = [p.rings[0] for p in panels]
	out = [Shape([r] + [h.rings[0][::-1] for h in holes if _inside(h.rings[0][0], r)], evenodd=True) for r in ring]
	return out


def _inside(p, ring):
	x, y = p
	inside = False
	n = len(ring)
	for i in range(n):
		x1, y1 = ring[i]
		x2, y2 = ring[(i + 1) % n]
		if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-9) + x1:
			inside = not inside
	return inside


def icon_journal():
	# an open bound journal: two pages, the spine, and lines of brushed text
	left = polygon([(8, 30), (60, 22), (60, 112), (8, 118)])
	right = polygon([(68, 22), (120, 30), (120, 118), (68, 112)])
	s = []
	for page, x0, x1, sign in ((left, 18, 52, 1), (right, 76, 110, -1)):
		holes = []
		for k in range(4):
			y = 44 + k * 16
			yy = y + (0 if sign > 0 else 0)
			holes.append(np.array([(x0, yy), (x1, yy - sign * 1.5), (x1, yy + 5 - sign * 1.5), (x0, yy + 5)])[::-1])
		s.append(Shape([page.rings[0]] + holes, evenodd=True))
	s.append(polygon([(61, 18), (67, 18), (67, 116), (61, 116)]))
	return s


def icon_bag():
	# traveller's pouch: rounded sack, gathered neck, tie cord with a tassel
	body = catmull([(64, 40), (100, 52), (114, 88), (96, 118), (64, 122), (32, 118), (14, 88), (28, 52), (64, 40)], 14)
	neck = polygon([(44, 22), (84, 22), (78, 44), (50, 44)])
	s = [polygon(body), neck]
	s.append(brush([(34, 42), (64, 48), (94, 42)], 9, 0.2, 0.2, 0.6, 0.6))
	s.append(brush([(92, 44), (104, 62), (100, 78)], 6, 0.2, 0.4, 0.8, 0.3))
	return s


def icon_character():
	# bust in a bender's robe: head with a topknot, shoulders, crossed collar
	head = circle((64, 40), 20)
	knot = circle((64, 14), 9)
	body = catmull([(16, 124), (20, 92), (40, 72), (64, 68), (88, 72), (108, 92), (112, 124)], 14)
	collar_l = np.array([(46, 76), (64, 104), (58, 108), (40, 80)])[::-1]
	collar_r = np.array([(82, 76), (88, 80), (70, 108), (64, 104)])[::-1]
	bust = Shape([np.vstack([body, [(16, 124)]]), collar_l, collar_r], evenodd=True)
	return [head, knot, bust]


def icon_padlock():
	# padlock: shackle arch over a rounded body with a keyhole
	s = [stroke(arc((64, 52), 26, 180, 360, 40), const(13))]
	s.append(polygon([(32, 50), (45, 50), (45, 62), (32, 62)]))
	s.append(polygon([(83, 50), (96, 50), (96, 62), (83, 62)]))
	body = round_rect(22, 58, 84, 62, 12).rings[0]
	hole = circle((64, 80), 9, 32).rings[0][::-1]
	slot = np.array([(60, 91), (68, 91), (70, 106), (58, 106)])[::-1]
	return s + [Shape([body, hole, slot], evenodd=True)]


def ui_close():
	return [brush([(26, 24), (64, 62), (104, 104)], 15, 0.15, 0.25, 0.5, 0.25),
			brush([(102, 26), (64, 64), (24, 106)], 15, 0.15, 0.25, 0.5, 0.25)]


# --- map glyphs -----------------------------------------------------------------------------------

def map_shrine():
	# small shrine: swept roof, two pillars, a step
	roof = catmull([(8, 50), (30, 40), (64, 18), (98, 40), (120, 50), (100, 50), (64, 34), (28, 50)], 10, closed=True)
	return [polygon(roof), polygon([(30, 50), (98, 50), (94, 60), (34, 60)]),
			polygon([(38, 60), (50, 60), (50, 108), (38, 108)]), polygon([(78, 60), (90, 60), (90, 108), (78, 108)]),
			polygon([(20, 108), (108, 108), (114, 120), (14, 120)])]


def map_port():
	# anchor
	s = [ring_shape((64, 20), 14, 7, 64), polygon([(58, 32), (70, 32), (70, 112), (58, 112)]),
		polygon([(36, 46), (92, 46), (92, 56), (36, 56)])]
	s.append(stroke(arc((64, 74), 44, 20, 160, 60), profile(12, 0.2, 0.2, 0.5, 0.5)))
	s.append(polygon([(104, 72), (122, 98), (96, 92)]))
	s.append(polygon([(24, 72), (6, 98), (32, 92)]))
	return s


def _eave_roof(x0, x1, y_eave, y_ridge, lift=8.0):
	"""Sweeping East Asian roof: curved slopes with upturned eave tips."""
	cx = (x0 + x1) * 0.5
	w = x1 - x0
	top = catmull([(x0 - 4, y_eave - lift), (x0 + w * 0.18, y_eave), (cx - w * 0.12, y_ridge + 3), (cx, y_ridge),
		(cx + w * 0.12, y_ridge + 3), (x1 - w * 0.18, y_eave), (x1 + 4, y_eave - lift)], 10)
	bottom = np.array([(x1 - w * 0.12, y_eave + 7), (x0 + w * 0.12, y_eave + 7)])
	return polygon(np.vstack([top, bottom]))


def map_city():
	# walled city: crenellated wall with a gate, a two-tier gatehouse with sweeping roofs
	wall_outer = np.array([(6, 122), (6, 84), (122, 84), (122, 122)])
	gate = np.vstack([np.array([(52, 122)]), arc((64, 106), 12, 180, 360, 20), np.array([(76, 122)])])[::-1]
	s = [Shape([wall_outer, gate], evenodd=True)]
	for x in range(8, 122, 16):
		s.append(polygon([(x, 84), (x + 9, 84), (x + 9, 76), (x, 76)]))
	s.append(_eave_roof(30, 98, 62, 46, 9))
	s.append(polygon([(40, 68), (88, 68), (88, 76), (40, 76)]))
	s.append(_eave_roof(40, 88, 34, 14, 8))
	s.append(polygon([(48, 40), (80, 40), (80, 50), (48, 50)]))
	return s


def map_village():
	# two houses with straight hip roofs and upturned eave tips
	def house(x0, x1, y_eave, y_ridge, y_floor):
		cx = (x0 + x1) * 0.5
		w = x1 - x0
		roof = polygon([(x0 - 4, y_eave - 6), (x0 + 6, y_eave - 2), (cx - w * 0.1, y_ridge), (cx + w * 0.1, y_ridge),
			(x1 - 6, y_eave - 2), (x1 + 4, y_eave - 6), (x1 - 4, y_eave + 4), (x0 + 4, y_eave + 4)])
		walls = polygon([(x0 + 8, y_eave + 4), (x1 - 8, y_eave + 4), (x1 - 8, y_floor), (x0 + 8, y_floor)])
		return [roof, walls]
	return house(8, 72, 60, 30, 116) + house(64, 122, 78, 54, 116)


def map_training():
	# sparring circle with crossed staves
	return [ring_shape((64, 64), 58, 48), line((30, 30), (98, 98), 11), line((98, 30), (30, 98), 11), circle((64, 64), 12)]


def map_cave():
	mound = catmull([(4, 120), (16, 70), (44, 34), (84, 30), (112, 66), (124, 120)], 14)
	mouth = np.vstack([np.array([(40, 120)]), arc((64, 98), 24, 180, 360, 30), np.array([(88, 120)])])[::-1]
	return [Shape([np.vstack([mound, [(4, 120)]]), mouth], evenodd=True)]


def map_landmark():
	# a peak with a snow line
	mtn = np.array([(4, 120), (50, 20), (64, 36), (76, 26), (124, 120)])
	snow = np.array([(36, 50), (48, 58), (58, 50), (66, 62), (78, 52), (88, 56), (76, 26), (64, 36), (50, 20)])[::-1]
	return [Shape([mtn, snow], evenodd=True)]


def map_vista():
	# sun rising over two hills
	s = [stroke(arc((64, 78), 30, 180, 360, 50), const(12))]
	for a in (200, 235, 270, 305, 340):
		r = math.radians(a)
		d = np.array([math.cos(r), math.sin(r)])
		s.append(line(tuple(np.array([64, 78]) + d * 40), tuple(np.array([64, 78]) + d * 56), 8))
	s.append(polygon(catmull([(2, 120), (30, 90), (64, 104), (98, 86), (126, 120)], 12)))
	return s


def map_spirit():
	sp = spiral((60, 66), 4, 44, 1.6, 300, clockwise=True)
	s = [stroke(sp, profile(13, 0.08, 0.3, 0.2, 0.3))]
	s.append(polygon([(104, 6), (110, 22), (124, 28), (110, 34), (104, 50), (98, 34), (84, 28), (98, 22)]))
	return s


def map_waterfall():
	s = [polygon([(6, 8), (122, 8), (122, 24), (6, 24)])]
	for x in (34, 54, 74, 94):
		s.append(brush([(x, 26), (x + 2, 70), (x - 2, 106)], 9, 0.1, 0.4, 0.9, 0.3))
	s.append(stroke(catmull([(10, 112), (40, 104), (64, 116), (90, 104), (118, 112)], 12), profile(9, 0.2, 0.2, 0.4, 0.4)))
	return s


def map_ruin():
	# two broken pillars of a fallen gate on a plinth, a fallen beam between them
	s = [polygon([(6, 108), (122, 108), (116, 122), (12, 122)])]
	s.append(polygon([(20, 108), (38, 108), (38, 30), (32, 22), (26, 32), (20, 26)]))
	s.append(polygon([(86, 108), (104, 108), (104, 58), (98, 50), (92, 60), (86, 54)]))
	s.append(polygon([(42, 94), (118, 80), (120, 90), (44, 104)]))
	return s


def map_camp():
	# tent with a flap and a pole
	tent = np.array([(6, 116), (64, 20), (122, 116)])
	flap = np.array([(54, 116), (64, 72), (74, 116)])[::-1]
	return [Shape([tent, flap], evenodd=True), line((64, 22), (64, 6), 7), polygon([(64, 6), (88, 12), (64, 18)])]


def map_resource():
	# faceted crystal
	outer = np.array([(64, 6), (108, 44), (64, 122), (20, 44)])
	facet = np.array([(64, 26), (90, 46), (64, 98), (38, 46)])[::-1]
	return [Shape([outer, facet], evenodd=True), polygon([(64, 38), (78, 48), (64, 82), (50, 48)])]


def map_bridge():
	deck = polygon([(4, 50), (124, 50), (124, 62), (4, 62)])
	arch_outer = np.vstack([np.array([(10, 62), (118, 62), (118, 116)]), arc((64, 116), 42, 0, -180, 40), np.array([(10, 116)])])
	s = [deck, Shape([arch_outer[::-1]])]
	for x in (14, 40, 64, 88, 114):
		s.append(polygon([(x - 3, 30), (x + 3, 30), (x + 3, 50), (x - 3, 50)]))
	s.append(polygon([(8, 28), (120, 28), (120, 34), (8, 34)]))
	return s


def map_player():
	# arrowhead pointing up (rotated by the player's heading in game)
	return [polygon([(64, 4), (112, 118), (64, 92), (16, 118)])]


def map_unknown():
	# a dotted ring: a place not found yet
	s = []
	for i in range(10):
		a0 = i * 36.0
		s.append(stroke(arc((64, 64), 46, a0, a0 + 20, 12), const(12)))
	s.append(circle((64, 64), 10))
	return s


def map_giver():
	# round seal with an exclamation cut out: a quest is offered here
	ang = np.linspace(0, 2 * math.pi, 96, endpoint=False)
	disc = np.stack([64 + 58 * np.cos(ang), 64 + 58 * np.sin(ang)], axis=1)
	bar = np.array([(56, 24), (72, 24), (68, 78), (60, 78)])[::-1]
	dot = np.stack([64 + 9 * np.cos(ang), 98 + 9 * np.sin(ang)], axis=1)[::-1]
	return [Shape([disc, bar, dot], evenodd=True)]


def map_travel():
	# a gate (paifang) with a wind swirl: fast travel point
	s = [polygon([(6, 24), (122, 24), (114, 36), (14, 36)]), polygon([(18, 44), (110, 44), (110, 52), (18, 52)]),
		polygon([(28, 36), (40, 36), (40, 122), (28, 122)]), polygon([(88, 36), (100, 36), (100, 122), (88, 122)])]
	s.append(stroke(spiral((64, 86), 3, 18, 1.1, 0, clockwise=True), profile(7, 0.1, 0.3, 0.3, 0.3)))
	return s


ICONS = {
	"icon_skills": icon_skills, "icon_map": icon_map, "icon_journal": icon_journal, "icon_bag": icon_bag,
	"icon_character": icon_character, "icon_padlock": icon_padlock, "ui_close": ui_close,
	"map_shrine": map_shrine, "map_port": map_port, "map_city": map_city, "map_village": map_village,
	"map_training": map_training, "map_cave": map_cave, "map_landmark": map_landmark, "map_vista": map_vista,
	"map_spirit": map_spirit, "map_waterfall": map_waterfall, "map_ruin": map_ruin, "map_camp": map_camp,
	"map_resource": map_resource, "map_bridge": map_bridge, "map_player": map_player, "map_unknown": map_unknown,
	"map_giver": map_giver, "map_travel": map_travel,
}

if __name__ == "__main__":
	prev_dir = sys.argv[1] if len(sys.argv) > 1 else ""
	sheet = None
	if prev_dir:
		from PIL import Image
		cols = 8
		rows = (len(ICONS) + cols - 1) // cols
		sheet = Image.new("RGB", (cols * 136, rows * 136), (40, 32, 28))
	for i, (name, fn) in enumerate(ICONS.items()):
		shapes = fn()
		with open(os.path.join(OUT, "%s.svg" % name), "w") as f:
			f.write(to_svg(shapes, size=128))
		if sheet is not None:
			img = preview(shapes, size=128, color=(240, 228, 200), bg=(40, 32, 28))
			sheet.paste(img, ((i % cols) * 136 + 4, (i // cols) * 136 + 4))
	if sheet is not None:
		sheet.save(os.path.join(prev_dir, "progression_icons.png"))
	print("icons written to", OUT)
