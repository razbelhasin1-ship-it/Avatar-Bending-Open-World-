#!/usr/bin/env python3
"""Generates the fire burn-mark textures used by FireMarks (src/fx/fire/fire_marks.gd).

    python3 src/fx/fire/textures/gen_fire_marks.py

Outputs (next to this script):
  burn_albedo.png / burn_emission.png   round char mark (soot core, scorched rim, ragged edge)
  ring_albedo.png / ring_emission.png   scorched ring band (Fire Ring, Inferno)
Albedo: RGBA (alpha = coverage). Emission: RGB embers along cracks (cooled by the decal).
Deterministic (fixed seeds), numpy + pillow only.
"""
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def value_noise(shape, cells, seed):
    """Smooth tileable value noise in [-1, 1] with `cells` lattice cells across."""
    rng = np.random.default_rng(seed)
    lat = rng.uniform(-1.0, 1.0, (cells + 1, cells + 1))
    lat[-1, :] = lat[0, :]
    lat[:, -1] = lat[:, 0]
    h, w = shape
    y = np.linspace(0, cells, h, endpoint=False)
    x = np.linspace(0, cells, w, endpoint=False)
    yi = np.floor(y).astype(int)
    xi = np.floor(x).astype(int)
    fy = y - yi
    fx = x - xi
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = lat[np.ix_(yi, xi)]
    b = lat[np.ix_(yi, xi + 1)]
    c = lat[np.ix_(yi + 1, xi)]
    d = lat[np.ix_(yi + 1, xi + 1)]
    fx2 = fx[None, :]
    fy2 = fy[:, None]
    return (a * (1 - fx2) + b * fx2) * (1 - fy2) + (c * (1 - fx2) + d * fx2) * fy2


def fbm(shape, base_cells, octaves, seed):
    out = np.zeros(shape)
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        out += value_noise(shape, base_cells * (2 ** o), seed + o * 101) * amp
        total += amp
        amp *= 0.5
    return out / total


def cellular(shape, points, seed):
    """Distance-to-second-minus-first (crack network), normalised to [0, 1]."""
    rng = np.random.default_rng(seed)
    h, w = shape
    pts = rng.uniform(0, 1, (points, 2))
    yy, xx = np.mgrid[0:h, 0:w]
    u = (xx + 0.5) / w
    v = (yy + 0.5) / h
    d1 = np.full(shape, 9.0)
    d2 = np.full(shape, 9.0)
    for px, py in pts:
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                d = np.sqrt((u - px - ox) ** 2 + (v - py - oy) ** 2)
                m = d < d1
                d2 = np.where(m, d1, np.minimum(d2, d))
                d1 = np.where(m, d, d1)
    c = d2 - d1
    return np.clip(c / (c.max() + 1e-6), 0, 1)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def make(shape_kind, size):
    shp = (size, size)
    yy, xx = np.mgrid[0:size, 0:size]
    u = (xx + 0.5) / size * 2 - 1
    v = (yy + 0.5) / size * 2 - 1
    r = np.sqrt(u * u + v * v)
    ang = np.arctan2(v, u)
    # Angular wobble for a ragged outline (sampled from a 1D-ish ring of noise).
    ring_noise = fbm((1, 512), 8, 3, 71 if shape_kind == "burn" else 83)[0]
    idx = ((ang + math.pi) / (2 * math.pi) * 511).astype(int) % 512
    wob = ring_noise[idx]
    fine = fbm(shp, 24, 3, 5)
    cracks = cellular(shp, 70 if shape_kind == "burn" else 160, 19)
    if shape_kind == "burn":
        edge = 0.8 + 0.16 * wob + 0.04 * fine
        inside = 1 - smoothstep(edge - 0.22, edge, r)
        core = 1 - smoothstep(0.0, edge * 0.85, r)
    else:
        mid = 0.8 + 0.07 * wob
        half = 0.13 + 0.1 * fbm((1, 512), 16, 2, 91)[0][idx]
        d = np.abs(r - mid)
        inside = 1 - smoothstep(half * 0.6, half, d)
        core = 1 - smoothstep(0.0, half * 0.7, d)
    crack = np.clip(cracks * 2.2, 0, 1)
    soot = np.array([0.045, 0.04, 0.038])
    burnt = np.array([0.16, 0.1, 0.06])
    singe = np.array([0.36, 0.25, 0.14])
    k1 = np.clip(inside * 1.3, 0, 1)[..., None]
    c = singe * (1 - k1) + burnt * k1
    k2 = np.clip(core * 1.4 + (1 - crack) * 0.35, 0, 1)[..., None]
    c = c * (1 - k2) + soot * k2
    k3 = (0.5 + 0.5 * fine)[..., None]
    c = c * (1 - k3) + (c * 0.6) * k3
    a = inside * (0.55 + 0.45 * core) * (0.85 + 0.15 * crack)
    alb = np.concatenate([c, a[..., None]], axis=-1)
    alb[inside <= 0] = 0
    fleck = smoothstep(0.955, 0.995, 1 - crack) * core * 0.85
    fleck = np.maximum(fleck, smoothstep(0.42, 0.62, fbm(shp, 48, 2, 33)) * core * 0.7)
    fleck *= inside
    ember = np.array([1.0, 0.42, 0.08])[None, None, :] * fleck[..., None] + np.array([1.0, 0.75, 0.3])[None, None, :] * (fleck ** 2)[..., None] * 0.6
    emi = np.concatenate([np.clip(ember, 0, 1), np.ones((size, size, 1))], axis=-1)
    return alb, emi


def save(arr, name):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(HERE, name))
    print("wrote", name)


if __name__ == "__main__":
    for kind, size in (("burn", 256), ("ring", 512)):
        alb, emi = make(kind, size)
        save(alb, "%s_albedo.png" % kind)
        save(emi, "%s_emission.png" % kind)
