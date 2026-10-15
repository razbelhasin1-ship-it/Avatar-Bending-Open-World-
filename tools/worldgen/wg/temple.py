"""Southern Air Temple: spire terraces, pinnacles with suspended bridges and the switchback pass."""
from __future__ import annotations

import math

import numpy as np

from . import grid, layout
from .grid import smoothstep
from .shapes import Field, ring_layout
from .cities import _p3, _r2, _tiers_json, _ramps_json

# Pinnacles beside the spire that carry suspended bridges: (bearing, distance from temple centre, radius)
PINNACLES = [
    {"id": "west_pinnacle", "bearing": -96.0, "distance": 318.0, "radius": 26.0, "top": 782.0,
     "bridge": "Bridge of Drifting Prayers", "bridge_id": "at_bridge_west"},
    {"id": "east_pinnacle", "bearing": 104.0, "distance": 296.0, "radius": 24.0, "top": 782.0,
     "bridge": "Windchime Span", "bridge_id": "at_bridge_east"},
]


def _raise_pillar(f: Field, cx, cz, radius, top, flare=0.22):
    """Raises a near-vertical rock column whose sides flare out gently toward the base."""
    rows, cols, X, Z = f.win(cx, cz, radius + 220)
    r = np.hypot(X - cx, Z - cz)
    hw = f.h[rows, cols].astype(np.float64)
    side = top - np.maximum(r - radius, 0.0) / flare
    target = np.where(r < radius, top, side)
    f.h[rows, cols] = np.maximum(hw, target).astype(np.float32)
    f.locked[rows, cols] |= r < radius


def build_air_temple(f: Field) -> dict:
    cfg = layout.AIR_TEMPLE
    c = cfg["center"]
    ring_layout(f, c, cfg["tiers"], cfg["ramp_bearings"], cfg["ramp_width"], cfg["ramp_length"], cfg["blend"],
                paved=0.0)
    rows, cols, X, Z = f.win(c[0], c[1], 230)
    r = np.hypot(X - c[0], Z - c[1])
    f.temple[rows, cols] = np.maximum(f.temple[rows, cols], (r < 214).astype(np.float32) * (f.h[rows, cols] > 755))
    bridges = []
    for p in PINNACLES:
        pos = layout.polar(c, p["bearing"], p["distance"])
        _raise_pillar(f, pos[0], pos[1], p["radius"], p["top"])
        pr, pc, px, pz = f.win(pos[0], pos[1], p["radius"])
        f.temple[pr, pc] = np.maximum(f.temple[pr, pc], (np.hypot(px - pos[0], pz - pos[1]) < p["radius"]) * 1.0)
        a = layout.polar(c, p["bearing"], 150.0)
        b = layout.polar(c, p["bearing"], p["distance"] - p["radius"] + 4)
        bridges.append({"id": p["bridge_id"], "name": p["bridge"], "kind": "suspended",
                        "a": _p3(f, *a), "b": _p3(f, *b, p["top"]), "width": 3.2,
                        "sag": _r2(math.hypot(b[0] - a[0], b[1] - a[1]) * 0.05)})
    rec = {
        "id": cfg["id"], "name": cfg["name"], "region": cfg["region"], "kind": "temple",
        "center": _p3(f, *c), "radius": 220.0, "layout": "rings", "ring_center": list(map(_r2, c)),
        "tiers": _tiers_json(cfg["tiers"]),
        "ramps": _ramps_json(cfg["ramp_bearings"], cfg["ramp_width"], cfg["ramp_length"]),
        "pinnacles": [{"id": p["id"], "position": _p3(f, *layout.polar(c, p["bearing"], p["distance"]), p["top"]),
                       "radius": p["radius"]} for p in PINNACLES],
        "bridges": [b["id"] for b in bridges],
        "gates": [{"id": "landing", "bearing": 0.0, "position": _p3(f, *layout.polar(c, -29.0, 214.0)), "width": 12.0}],
        "palace": {"position": _p3(f, *c), "radius": cfg["tiers"][0]["r_outer"], "height": cfg["tiers"][0]["height"]},
    }
    return {"city": rec, "bridges": bridges}


def switchback_road(f: Field) -> dict:
    """Builds the 'Pass of a Thousand Steps' as an explicit constant-grade switchback road."""
    p = layout.AIR_PASS
    bx, bz = p["bottom"]
    tx, tz = p["top"]
    vx, vz = tx - bx, tz - bz
    vlen = math.hypot(vx, vz)
    vx, vz = vx / vlen, vz / vlen
    ux, uz = -vz, vx
    n = p["legs"]
    a = p["face_width"] * 0.5 - 34.0
    verts = []
    for k in range(n + 1):
        side = -1.0 if k % 2 == 0 else 1.0
        v = vlen * k / n
        u = side * a
        if k == n:
            u = 0.0
        verts.append((bx + ux * u + vx * v, bz + uz * u + vz * v))
    # Insert points close to each corner so smoothing only rounds the hairpins locally
    dense = [verts[0]]
    for i in range(1, len(verts)):
        p0 = np.array(verts[i - 1])
        p1 = np.array(verts[i])
        seg = p1 - p0
        ln = np.linalg.norm(seg)
        cut = min(22.0, ln * 0.2)
        if i > 1:
            dense.append(tuple(p0 + seg / ln * cut))
        if i < len(verts) - 1:
            dense.append(tuple(p1 - seg / ln * cut))
        dense.append(tuple(p1))
    pts = grid.chaikin(np.array(dense), 3)
    pts = grid.resample_polyline(pts, 1.0)
    s = grid.polyline_lengths(pts)
    h0 = float(grid.sample_bilinear(f.h, pts[:1, 0], pts[:1, 1])[0])
    h1 = p["top_height"]
    hs = h0 + (h1 - h0) * s / s[-1]
    samples = np.column_stack([pts[:, 0], pts[:, 1], hs])
    return {
        "id": "air_pass_switchbacks", "samples": samples, "half_width": p["road_width"] * 0.5, "paved": True,
        "grade": round((h1 - h0) / s[-1], 4), "length": round(float(s[-1]), 1),
        "anchors": {"air_pass:bottom": (float(pts[0, 0]), float(pts[0, 1])),
                    "air_pass:top": (float(pts[-1, 0]), float(pts[-1, 1]))},
    }
