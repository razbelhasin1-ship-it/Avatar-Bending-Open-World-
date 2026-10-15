"""Full-resolution shaping operations on the final heightmap.

Every operation works on a local window of the 4096^2 grid so it stays cheap.
The same geometric definitions (rings, arcs, ramps) are exported to world.json,
so settlement builders can rebuild walls/stairs exactly where the terrain steps.
"""
from __future__ import annotations

import math

import numpy as np
from scipy import ndimage

from . import grid
from . import noise as nz
from .grid import smoothstep, smootherstep, lerp


class Field:
    """Final-resolution terrain plus bookkeeping masks."""

    def __init__(self, h: np.ndarray, seed: int):
        self.h = h.astype(np.float32)
        self.n = h.shape[0]
        self.cell = grid.cell_size(self.n)
        self.seed = seed
        self.settlement = np.zeros(h.shape, dtype=np.float32)   # 0..1 paved settlement ground
        self.farmland = np.zeros(h.shape, dtype=np.float32)     # 0..1 cultivated fields
        self.temple = np.zeros(h.shape, dtype=np.float32)       # 0..1 temple grounds
        self.grass_patch = np.zeros(h.shape, dtype=np.float32)  # 0..1 forced grass (spirit oasis)
        self.locked = np.zeros(h.shape, dtype=bool)             # cells later stages must not edit
        self.water_carves: list[dict] = []

    def win(self, cx: float, cz: float, radius: float):
        return grid.window(self.n, cx, cz, radius)


def bearing_deg(dx, dz):
    return np.degrees(np.arctan2(dx, -dz))


def wrap_deg(a):
    return (a + 180.0) % 360.0 - 180.0


def in_arc(bearing, arc):
    if arc is None:
        return np.ones(np.shape(bearing), dtype=bool)
    a0, a1 = arc
    if a1 - a0 >= 360:
        return np.ones(np.shape(bearing), dtype=bool)
    mid = (a0 + a1) * 0.5
    half = (a1 - a0) * 0.5
    return np.abs(wrap_deg(bearing - mid)) <= half


def ramp_profile(tiers, bearing: float, ramp_length: float):
    """Piecewise-linear height(r) along a radial ramp crossing every tier boundary at `bearing`."""
    ts = sorted([t for t in tiers if bool(in_arc(np.array([bearing]), t.get("arc"))[0])], key=lambda t: t["r_inner"])
    if not ts:
        return None
    knots_r = [ts[0]["r_inner"]]
    knots_h = [ts[0]["height"]]
    for a, b in zip(ts[:-1], ts[1:]):
        if abs(a["r_outer"] - b["r_inner"]) > 1.0:
            knots_r += [a["r_outer"], b["r_inner"]]
            knots_h += [a["height"], b["height"]]
            continue
        rb = a["r_outer"]
        half = min(ramp_length * 0.5, (a["r_outer"] - a["r_inner"]) * 0.45, (b["r_outer"] - b["r_inner"]) * 0.45)
        knots_r += [rb - half, rb + half]
        knots_h += [a["height"], b["height"]]
    knots_r.append(ts[-1]["r_outer"])
    knots_h.append(ts[-1]["height"])
    return np.asarray(knots_r, dtype=np.float64), np.asarray(knots_h, dtype=np.float64)


def ring_layout(f: Field, center, tiers, ramps=(), ramp_width=16.0, ramp_length=40.0, blend=120.0,
                keep_out=None, target_fn=None, paved=1.0, lock=True, blend_only_lower=False):
    """Flattens ring/arc tiers around `center` with radial ramps between them.

    tiers: [{"r_inner","r_outer","height","arc"(optional bearing range)}]
    keep_out(r, bearing) -> bool mask of cells that must not be blended (e.g. harbour water).
    target_fn(X, Z, r, bearing, target) -> target  lets callers add terrain details.
    Returns the boolean tier mask in window coordinates (rows, cols, mask).
    """
    cx, cz = center
    r_max = max(t["r_outer"] for t in tiers)
    w = f.win(cx, cz, r_max + blend + 20)
    rows, cols, X, Z = w
    dx, dz = X - cx, Z - cz
    r = np.hypot(dx, dz)
    b = bearing_deg(dx, dz)
    target = np.full(r.shape, np.nan)
    for t in tiers:
        m = (r >= t["r_inner"]) & (r < t["r_outer"]) & in_arc(b, t.get("arc"))
        target[m] = t["height"]
    inside = ~np.isnan(target)
    for rb in ramps:
        prof = ramp_profile(tiers, rb, ramp_length)
        if prof is None:
            continue
        da = np.radians(wrap_deg(b - rb))
        across = np.abs(np.sin(da) * r)
        zone = (across < ramp_width * 0.5 + 2.0) & (np.cos(da) > 0) & inside
        zone &= (r >= prof[0][0]) & (r <= prof[0][-1])
        if not zone.any():
            continue
        ramp_h = np.interp(r[zone], prof[0], prof[1])
        edge = smoothstep(ramp_width * 0.5 + 2.0, ramp_width * 0.5, across[zone])
        target[zone] = lerp(target[zone], ramp_h, edge)
    if target_fn is not None:
        target = target_fn(X, Z, r, b, target)
    inside = ~np.isnan(target)
    hw = f.h[rows, cols].astype(np.float64)
    dist, idx = ndimage.distance_transform_edt(~inside, sampling=f.cell, return_indices=True)
    near = target[idx[0], idx[1]]
    weight = 1.0 - smootherstep(0.0, blend, dist)
    if keep_out is not None:
        ko = keep_out(r, b)
        weight[ko & ~inside] = 0.0
    new = lerp(hw, near, weight)
    if blend_only_lower:
        new = np.where(inside, new, lerp(hw, np.minimum(hw, near), weight))
    f.h[rows, cols] = new.astype(np.float32)
    if paved:
        f.settlement[rows, cols] = np.maximum(f.settlement[rows, cols], inside * paved)
    if lock:
        f.locked[rows, cols] |= inside
    return rows, cols, inside


def flatten_pad(f: Field, cx, cz, radius, height=None, blend=50.0, paved=0.6, terraces=None, lock=True):
    """Flattens a round village/camp pad (optionally with concentric terraces). Returns the height used."""
    w = f.win(cx, cz, radius + blend + 10)
    if w is None:
        return height
    rows, cols, X, Z = w
    r = np.hypot(X - cx, Z - cz)
    hw = f.h[rows, cols].astype(np.float64)
    if height is None:
        core = r < radius
        height = float(np.median(hw[core])) if core.any() else float(hw.mean())
        height = max(height, 2.0)
    if terraces:
        target = np.full(r.shape, float(terraces[-1][1]))
        for rad, th in sorted(terraces, key=lambda t: -t[0]):
            target[r < rad] = th
        outer = max(t[0] for t in terraces)
    else:
        # irregular outline and a gentle undulation keep villages from looking stamped
        ang = np.arctan2(X - cx, Z - cz)
        wob = nz.fbm(np.cos(ang) * radius, np.sin(ang) * radius, 1.0 / max(radius * 0.7, 30), f.seed + int(cx) % 997, 2)
        r = r / (1.0 + 0.2 * wob)
        target = float(height) + nz.fbm(X, Z, 1 / 70, f.seed + 77, 2) * 0.35
        outer = radius
    weight = 1.0 - smootherstep(outer, outer + blend, r)
    f.h[rows, cols] = lerp(hw, target, weight).astype(np.float32)
    f.settlement[rows, cols] = np.maximum(f.settlement[rows, cols], (r < radius * 0.9) * paved)
    if lock:
        f.locked[rows, cols] |= r < outer
    return height


class LakeShape:
    """Irregular, elongated lake outline: u(x, z) < 1 inside, polygon() for export."""

    def __init__(self, cx, cz, radius, seed):
        rng = np.random.default_rng(seed)
        self.cx, self.cz, self.radius, self.seed = cx, cz, radius, seed
        self.rot = float(rng.uniform(0, math.pi))
        self.elong = float(rng.uniform(1.15, 1.7))

    def _local(self, dx, dz):
        c, s = math.cos(self.rot), math.sin(self.rot)
        a = dx * c + dz * s
        b = (-dx * s + dz * c) * self.elong
        return a, b

    def _wobble(self, theta):
        R = self.radius
        x, z = np.cos(theta) * R, np.sin(theta) * R
        return 0.24 * nz.fbm(x, z, 1.0 / max(R * 0.8, 40), self.seed, 3) + \
            0.08 * nz.fbm(x, z, 1.0 / max(R * 0.3, 20), self.seed + 5, 2)

    def u(self, X, Z):
        a, b = self._local(X - self.cx, Z - self.cz)
        rho = np.hypot(a, b)
        theta = np.arctan2(b, a)
        return rho / (self.radius * (1.0 + self._wobble(theta)))

    def polygon(self, segs=56):
        th = np.linspace(0, 2 * math.pi, segs, endpoint=False)
        rr = self.radius * (1.0 + self._wobble(th))
        a = rr * np.cos(th)
        b = rr * np.sin(th) / self.elong
        c, s = math.cos(self.rot), math.sin(self.rot)
        dx = a * c - b * s
        dz = a * s + b * c
        return [[round(float(self.cx + x), 2), round(float(self.cz + z), 2)] for x, z in zip(dx, dz)]


def carve_lake(f: Field, lake_id, cx, cz, radius, level, depth, frozen, seed):
    """Carves a natural lake: irregular outline, bowl-shaped bed and soft banks that close the shore.

    Returns its record (level, polygon, bounding radius)."""
    shape = LakeShape(cx, cz, radius, seed)
    rows, cols, X, Z = f.win(cx, cz, radius * 2.3 + 40)
    u = shape.u(X, Z)
    hw = f.h[rows, cols].astype(np.float64)
    if level is None:
        ring = (u > 1.0) & (u < 1.3)
        level = float(np.percentile(hw[ring], 22)) - 0.4
    level = float(level)
    inside = u < 1.0
    if frozen:
        bed = np.full(u.shape, level)
    else:
        bed = level - 0.35 - depth * np.clip(1.0 - u * u, 0, 1) ** 0.55
    new = np.where(inside, bed, hw)
    # banks: terrain above the shore is eased down onto it, hollows are filled so the lake stays closed
    bank = (u >= 1.0) & (u < 1.9)
    t = smoothstep(1.0, 1.9, u)
    shore = level + 0.45 + 2.2 * (u - 1.0)
    eased = shore + (hw - shore) * t
    new = np.where(bank, np.where(hw > shore, np.minimum(hw, eased), np.maximum(hw, lerp(shore, hw, t))), new)
    f.h[rows, cols] = new.astype(np.float32)
    f.locked[rows, cols] |= u < 1.15
    ext = float(np.max(np.hypot(np.array([p[0] for p in shape.polygon()]) - cx, np.array([p[1] for p in shape.polygon()]) - cz)))
    return {"level": round(level, 3), "polygon": shape.polygon(), "radius": round(ext * 1.05 + 4.0, 2)}


def carve_channel_flat(f: Field, pts, half_width, bed, wall_top=None, lock=True):
    """Carves a straight-walled channel (canal) of constant bed height along a polyline."""
    pts = np.asarray(pts, dtype=np.float64)
    x0, z0 = pts.min(axis=0)
    x1, z1 = pts.max(axis=0)
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    rad = max(x1 - x0, z1 - z0) / 2 + half_width + 8
    rows, cols, X, Z = f.win(cx, cz, rad)
    dist, _, _ = grid.polyline_distance(X, Z, pts)
    hw = f.h[rows, cols].astype(np.float64)
    m = dist < half_width
    new = np.where(m, bed, hw)
    f.h[rows, cols] = new.astype(np.float32)
    if lock:
        f.locked[rows, cols] |= dist < half_width + 2


def raise_sill(f: Field, pts, half_width, height):
    pts = np.asarray(pts, dtype=np.float64)
    x0, z0 = pts.min(axis=0)
    x1, z1 = pts.max(axis=0)
    rows, cols, X, Z = f.win((x0 + x1) / 2, (z0 + z1) / 2, max(x1 - x0, z1 - z0) / 2 + half_width + 30)
    dist, _, _ = grid.polyline_distance(X, Z, pts)
    hw = f.h[rows, cols].astype(np.float64)
    target = height - 4.0 * smoothstep(half_width, half_width + 25.0, dist)
    f.h[rows, cols] = np.where(dist < half_width + 25, np.maximum(hw, target), hw).astype(np.float32)


def flatten_roads(f: Field, roads, shoulder=7.0):
    """Flattens all road corridors at once and returns RGB coverage rasters (any, paved).

    roads: list of dicts with "samples" (N x 3 array of x, z, height at ~1 m spacing),
    "half_width" and "paved" (bool).
    """
    n = f.n
    rh = np.full((n, n), np.nan, dtype=np.float32)
    rw = np.zeros((n, n), dtype=np.float32)
    rp = np.zeros((n, n), dtype=np.uint8)
    for rd in roads:
        s = np.asarray(rd["samples"], dtype=np.float64)
        px, pz = grid.to_pixel(s[:, 0], s[:, 1], n)
        ix = np.clip(np.round(px).astype(np.int64), 0, n - 1)
        iz = np.clip(np.round(pz).astype(np.int64), 0, n - 1)
        rh[iz, ix] = s[:, 2]
        rw[iz, ix] = rd["half_width"]
        rp[iz, ix] = 1 if rd.get("paved") else 0
    has = ~np.isnan(rh)
    dist, idx = ndimage.distance_transform_edt(~has, sampling=f.cell, return_indices=True)
    near_h = rh[idx[0], idx[1]]
    near_w = rw[idx[0], idx[1]]
    near_p = rp[idx[0], idx[1]]
    reach = dist < near_w + shoulder
    weight = np.where(reach, 1.0 - smoothstep(near_w, near_w + shoulder, dist), 0.0)
    weight = np.where(f.locked, 0.0, weight)       # never cut into city tiers / lakes / canals
    f.h = np.where(reach, lerp(f.h, near_h, weight), f.h).astype(np.float32)
    cover = np.where(reach, smoothstep(near_w + 1.2, near_w - 1.2, dist), 0.0).astype(np.float32)
    paved = cover * near_p
    return cover, paved
