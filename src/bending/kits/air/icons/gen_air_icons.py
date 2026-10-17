#!/usr/bin/env python3
"""Generates the Air technique icons (white glyphs on transparent, 128x128, like
assets/ui/ability_*.svg): Air Push, Air Scooter, Wind Blade, Vortex Ward, Air Tornado.
Run from the project root: python3 src/bending/kits/air/icons/gen_air_icons.py"""
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">\n'
STROKE = 'fill="none" stroke="#ffffff" stroke-linecap="round" stroke-linejoin="round"'


def arc(cx, cy, r, a0, a1, steps=24, squash=1.0):
    pts = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * squash))
    return pts


def path(pts, w):
    d = "M" + " L".join("%.1f,%.1f" % p for p in pts)
    return '<path %s stroke-width="%.1f" d="%s"/>\n' % (STROKE, w, d)


def spiral(cx, cy, r0, r1, a0, turns, steps=60, squash=1.0):
    pts = []
    for i in range(steps + 1):
        u = i / steps
        a = math.radians(a0) + u * turns * math.tau
        r = r0 + (r1 - r0) * u
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * squash))
    return pts


def write(name, body):
    with open(os.path.join(OUT, name), "w") as f:
        f.write(HEAD + body + "</svg>\n")


def push():
    b = '<circle cx="64" cy="64" r="11" fill="#ffffff"/>\n'
    # Three rings of wind bursting outward, broken into gusts.
    for k, (r, w) in enumerate([(26, 7.0), (40, 6.0), (54, 5.0)]):
        for s in range(4):
            a0 = s * 90 + 12 + k * 22
            b += path(arc(64, 64, r, a0, a0 + 58 - k * 6), w)
    return b


def scooter():
    b = ""
    # The ball: outer circle + inner swirl.
    b += path(arc(64, 74, 34, 0, 360, 48), 7.0)
    b += path(spiral(64, 74, 4, 26, -90, 1.3), 5.5)
    # Motion streaks trailing behind.
    for i, y in enumerate([58, 74, 90]):
        b += path([(8 + i * 3, y), (22 + i * 2, y)], 5.0)
    # Spin arrows on top.
    b += path(arc(64, 74, 46, 200, 250), 5.0)
    b += path(arc(64, 74, 46, 20, 70), 5.0)
    return b


def blade():
    b = ""
    # Crescent: two arcs meeting at sharp tips (filled).
    outer = arc(64, 92, 56, 205, 335, 32)
    inner = arc(64, 104, 50, 335, 205, 32)
    d = "M" + " L".join("%.1f,%.1f" % p for p in outer + inner) + " Z"
    b += '<path fill="#ffffff" d="%s"/>\n' % d
    # Speed lines below the blade.
    for i, (x0, x1, y) in enumerate([(30, 98, 76), (42, 86, 92), (52, 76, 106)]):
        b += path([(x0, y), (x1, y)], 5.0 - i)
    return b


def ward():
    b = ""
    b += path(arc(64, 64, 40, 0, 360, 48), 6.0)
    # Bands whirling around the sphere (squashed ellipses at angles).
    b += path(arc(64, 64, 54, 200, 340, 32, 0.38), 6.0)
    b += path(arc(64, 64, 54, 20, 160, 32, 0.38), 6.0)
    b += path(spiral(64, 64, 6, 24, 0, 1.1), 5.0)
    return b


def tornado():
    b = ""
    # Stacked strokes narrowing to the ground, offset to read as a twisting funnel.
    rows = [(18, 50, 7.0), (32, 42, 6.5), (46, 33, 6.0), (60, 25, 5.5), (74, 18, 5.0), (88, 12, 4.5), (102, 7, 4.0)]
    for i, (y, half, w) in enumerate(rows):
        off = math.sin(i * 0.9) * 6.0
        b += path(arc(64 + off, y, half, 160, 380, 28, 0.32), w)
    b += path([(60, 112), (64, 120), (70, 113)], 4.0)
    return b


write("ability_air_push.svg", push())
write("ability_air_scooter.svg", scooter())
write("ability_wind_blade.svg", blade())
write("ability_vortex_ward.svg", ward())
write("ability_air_tornado.svg", tornado())
print("wrote 5 icons to", OUT)
