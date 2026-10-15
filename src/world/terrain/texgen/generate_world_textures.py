#!/usr/bin/env python3
"""Generates the small tiling textures used by the world renderer (worldrender module).

Output (all seamlessly tiling, deterministic):
  assets/textures/world/noise.png        512^2 RGBA  R fbm, G cellular F1, B ridged fbm, A fine grain
  assets/textures/world/detail.png       512^2 RGBA  painterly height patterns:
                                                     R rock strata+cracks, G grass strokes,
                                                     B flagstone paving, A wind ripples (sand/snow)
  assets/textures/world/detail_nrm_a.png 512^2 RGBA  tangent-space XY normals: RG rock, BA grass
  assets/textures/world/detail_nrm_b.png 512^2 RGBA  RG paving, BA ripples
  assets/textures/world/water_nrm.png    256^2 RGBA  RG normal XY of a capillary wave field, B height, A foam cells
  assets/textures/world/clouds.png       512^2 RGBA  R billow fbm, G worley billows, B wispy streaks, A fine fbm

Usage: python3 src/world/terrain/texgen/generate_world_textures.py
Only numpy and pillow are needed.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "world")
RNG = np.random.default_rng(4711)


# --- periodic primitives ------------------------------------------------------------------------

def value_noise(size, period, rng):
    """Periodic gradient (Perlin) noise in 0..1; `period` lattice cells across `size` px."""
    ang = rng.random((period, period)) * 2 * np.pi
    gx = np.cos(ang)
    gy = np.sin(ang)
    c = np.arange(size) * period / size
    i0 = np.floor(c).astype(int)
    f = c - i0
    u = f * f * f * (f * (f * 6 - 15) + 10)
    i1 = (i0 + 1) % period
    i0 = i0 % period
    fy = f[:, None]
    fx = f[None, :]

    def dot(iy, ix, ox, oy):
        return gx[np.ix_(iy, ix)] * (fx - ox) + gy[np.ix_(iy, ix)] * (fy - oy)

    n00 = dot(i0, i0, 0, 0)
    n10 = dot(i0, i1, 1, 0)
    n01 = dot(i1, i0, 0, 1)
    n11 = dot(i1, i1, 1, 1)
    ux = u[None, :]
    uy = u[:, None]
    n = (n00 * (1 - ux) + n10 * ux) * (1 - uy) + (n01 * (1 - ux) + n11 * ux) * uy
    return np.clip(n * 0.75 + 0.5, 0.0, 1.0)


def fbm(size, base_period, octaves, rng, gain=0.5):
    out = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    p = base_period
    for _ in range(octaves):
        out += value_noise(size, p, rng) * amp
        norm += amp
        amp *= gain
        p *= 2
    return out / norm


def worley(size, cells, rng, second=False):
    """Periodic Worley noise: distance to nearest (F1) or F2-F1 feature point, in cell units."""
    pts = rng.random((cells, cells, 2))
    yy, xx = np.mgrid[0:size, 0:size] * (cells / size)
    ci = np.floor(xx).astype(int)
    cj = np.floor(yy).astype(int)
    d1 = np.full((size, size), 9.0)
    d2 = np.full((size, size), 9.0)
    ids = np.zeros((size, size), dtype=np.int64)
    for oj in (-1, 0, 1):
        for oi in (-1, 0, 1):
            ni = ci + oi
            nj = cj + oj
            p = pts[nj % cells, ni % cells]
            dx = ni + p[..., 0] - xx
            dy = nj + p[..., 1] - yy
            d = np.sqrt(dx * dx + dy * dy)
            idv = (nj % cells) * cells + (ni % cells)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            ids = np.where(closer, idv, ids)
            d1 = np.where(closer, d, d1)
    if second:
        return d1, d2, ids
    return d1


def warp(img, dx, dy, strength):
    """Periodic domain warp (nearest-neighbour lookup with bilinear blend)."""
    size = img.shape[0]
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    sx = (xx + dx * strength) % size
    sy = (yy + dy * strength) % size
    x0 = np.floor(sx).astype(int)
    y0 = np.floor(sy).astype(int)
    fx = sx - x0
    fy = sy - y0
    x1 = (x0 + 1) % size
    y1 = (y0 + 1) % size
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy)
            + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)


def blur(img, passes=1):
    for _ in range(passes):
        img = (img + np.roll(img, 1, 0) + np.roll(img, -1, 0) + np.roll(img, 1, 1) + np.roll(img, -1, 1)) / 5.0
    return img


def normalize01(a):
    lo, hi = np.percentile(a, 0.05), np.percentile(a, 99.95)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def normals_xy(height, strength):
    """Tangent-space normal XY (0..1 encoded) from a periodic height field (central differences)."""
    hx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * strength
    hy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * strength
    n = np.stack([-hx, -hy, np.ones_like(height)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n[..., 0] * 0.5 + 0.5, n[..., 1] * 0.5 + 0.5


def save_rgba(name, channels):
    arr = np.stack([np.clip(c, 0, 1) for c in channels], -1)
    img = Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), "RGBA")
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "KB")


# --- textures ---------------------------------------------------------------------------------

def make_noise():
    s = 512
    r = fbm(s, 4, 6, RNG)
    g = worley(s, 12, RNG)
    rid = np.zeros((s, s))
    amp = 1.0
    p = 4
    for _ in range(5):
        v = 1.0 - np.abs(value_noise(s, p, RNG) * 2.0 - 1.0)
        rid += v * v * amp
        amp *= 0.5
        p *= 2
    a = blur(RNG.random((s, s)), 1)
    save_rgba("noise.png", [normalize01(r), normalize01(g), normalize01(rid), normalize01(a)])


def make_detail():
    s = 512
    # rock: horizontal strata (warped) + cracks + chips
    n1 = fbm(s, 4, 5, RNG)
    n2 = fbm(s, 8, 4, RNG)
    yy = np.mgrid[0:s, 0:s][0] / s
    strata = np.sin((yy * 9.0 + n1 * 1.6) * 2 * np.pi) * 0.5 + 0.5
    strata = np.round(strata * 4.0) / 4.0 * 0.6 + strata * 0.4      # painterly banding
    f1, f2, _ = worley(s, 10, RNG, second=True)
    cracks = np.clip((f2 - f1) * 6.0, 0, 1)
    rock = strata * 0.45 + n2 * 0.35 + cracks * 0.35
    rock = normalize01(blur(rock, 1))
    # grass: elongated brush strokes (anisotropic noise, stretched along y) in clumps
    st = value_noise(s, 64, RNG)
    st = warp(st, fbm(s, 8, 3, RNG) - 0.5, fbm(s, 8, 3, RNG) - 0.5, 18.0)
    st2 = np.zeros((s, s))
    for k in range(6):  # vertical smear = stroke direction
        st2 += np.roll(st, k * 2, 0)
    clumps = 1.0 - worley(s, 14, RNG)
    grass = normalize01(st2 / 6.0 * 0.6 + clumps * 0.4 + fbm(s, 16, 3, RNG) * 0.2)
    # flagstones: irregular cells, darker mortar gaps, slight per-stone tilt variation
    f1, f2, ids = worley(s, 7, RNG, second=True)
    edge = np.clip((f2 - f1) * 7.0, 0, 1)
    stone_h = RNG.random(49)[ids] * 0.25 + 0.6
    paving = edge ** 0.45 * stone_h + fbm(s, 32, 3, RNG) * 0.12
    paving = normalize01(paving)
    # wind ripples (sand dunes / wind-packed snow)
    xx = np.mgrid[0:s, 0:s][1] / s
    wn = fbm(s, 4, 4, RNG)
    rip = np.sin((xx * 22.0 + yy * 3.0 + wn * 2.4) * 2 * np.pi)
    rip = np.sign(rip) * np.abs(rip) ** 0.7 * 0.5 + 0.5
    ripples = normalize01(rip * 0.8 + fbm(s, 16, 3, RNG) * 0.2)
    save_rgba("detail.png", [rock, grass, paving, ripples])
    rx, ry = normals_xy(rock, 6.0)
    gx, gy = normals_xy(grass, 4.0)
    px, py = normals_xy(paving, 5.0)
    sx, sy = normals_xy(ripples, 3.0)
    save_rgba("detail_nrm_a.png", [rx, ry, gx, gy])
    save_rgba("detail_nrm_b.png", [px, py, sx, sy])


def make_water():
    s = 256
    yy, xx = np.mgrid[0:s, 0:s] / s
    h = np.zeros((s, s))
    for k in range(40):
        # integer wave vectors keep the field periodic
        kx, ky = RNG.integers(-9, 10, 2)
        if kx == 0 and ky == 0:
            continue
        amp = 1.0 / (np.hypot(kx, ky) ** 1.2)
        ph = RNG.random() * 2 * np.pi
        h += np.sin((kx * xx + ky * yy) * 2 * np.pi + ph) * amp
    h = normalize01(h)
    nx, ny = normals_xy(h, 10.0)
    f1, f2, _ = worley(s, 9, RNG, second=True)
    foam = 1.0 - np.clip((f2 - f1) * 4.0, 0, 1)
    save_rgba("water_nrm.png", [nx, ny, h, normalize01(foam)])


def make_clouds():
    s = 512
    billow = np.zeros((s, s))
    amp = 1.0
    p = 3
    for _ in range(6):
        billow += np.abs(value_noise(s, p, RNG) * 2 - 1) * amp
        amp *= 0.55
        p *= 2
    billow = normalize01(billow)
    w = 1.0 - worley(s, 6, RNG)
    w = normalize01(w * 0.7 + (1.0 - worley(s, 13, RNG)) * 0.3)
    # wisps: noise smeared along x
    base = fbm(s, 6, 5, RNG)
    wisp = np.zeros((s, s))
    for k in range(10):
        wisp += np.roll(base, k * 3, 1)
    wisp = normalize01(wisp)
    fine = normalize01(fbm(s, 16, 4, RNG))
    save_rgba("clouds.png", [billow, w, wisp, fine])


def main():
    os.makedirs(OUT, exist_ok=True)
    make_noise()
    make_detail()
    make_water()
    make_clouds()
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".png"))
    print("total %.2f MB" % (total / 1048576.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
