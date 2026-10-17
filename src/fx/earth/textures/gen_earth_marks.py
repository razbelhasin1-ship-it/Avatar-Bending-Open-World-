#!/usr/bin/env python3
"""Generates the earthbending ground-mark textures (EarthMarks):

  crater_albedo.png / crater_normal.png    radial cracks, crushed centre, raised rim
  fissure_albedo.png / fissure_normal.png  a long jagged crack with side branches (u = along)
  furrow_albedo.png / furrow_normal.png    plough marks of a slide (u = along the slide)

Albedo RGB is a neutral luminance multiplier (EarthMarks tints it with the ground
palette through Decal.modulate), alpha is coverage. Normals are tangent-space
(OpenGL convention, +Y up) derived from a height field. Deterministic (fixed seeds).

    python3 src/fx/earth/textures/gen_earth_marks.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter

OUT = os.path.dirname(os.path.abspath(__file__))


def smooth_noise(shape, sigma, rng):
    n = gaussian_filter(rng.standard_normal(shape), sigma, mode="wrap")
    n -= n.min()
    n /= max(n.max(), 1e-6)
    return n


def stroke_mask(size, strokes, scale=2):
    """Antialiased mask of polylines [(points, widths)] drawn at `scale`x and downsampled."""
    w, h = size
    img = Image.new("L", (w * scale, h * scale), 0)
    d = ImageDraw.Draw(img)
    for pts, widths in strokes:
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            wd = max(1, int(round(widths[i] * scale)))
            d.line([(x0 * scale, y0 * scale), (x1 * scale, y1 * scale)], fill=255, width=wd)
            r = wd / 2.0
            d.ellipse([x1 * scale - r, y1 * scale - r, x1 * scale + r, y1 * scale + r], fill=255)
    img = img.filter(ImageFilter.GaussianBlur(scale * 0.45)).resize((w, h), Image.LANCZOS)
    return np.asarray(img, dtype=np.float32) / 255.0


def crack_walk(rng, start, angle, length, width, step=3.0, wander=0.32, branch_p=0.05, depth=2, taper=True):
    """Random-walk crack polyline (+ branches). Returns a list of (points, widths)."""
    out = []
    pts = [start]
    widths = []
    x, y = start
    a = angle
    n = max(2, int(length / step))
    for s in range(n):
        a += rng.uniform(-wander, wander)
        x += math.cos(a) * step
        y += math.sin(a) * step
        pts.append((x, y))
        u = s / n
        widths.append(width * ((1.0 - u) if taper else 1.0) + 0.6)
        if depth > 0 and rng.random() < branch_p:
            out += crack_walk(rng, (x, y), a + rng.uniform(-1.0, 1.0), length * rng.uniform(0.25, 0.45),
                              widths[-1] * 0.7, step, wander, branch_p * 0.6, depth - 1)
    out.append((pts, widths))
    return out


def normals_from_height(hf, strength):
    gy, gx = np.gradient(hf)
    nx = -gx * strength
    ny = gy * strength  # image rows go down; OpenGL normal maps have +Y up
    nz = np.ones_like(hf)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], axis=-1)
    return ((n * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)


def save(name, lum, alpha, height, strength):
    rgba = np.zeros(lum.shape + (4,), dtype=np.uint8)
    l8 = (np.clip(lum, 0, 1) * 255).astype(np.uint8)
    rgba[..., 0] = l8
    rgba[..., 1] = l8
    rgba[..., 2] = l8
    rgba[..., 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name + "_albedo.png"))
    Image.fromarray(normals_from_height(height, strength), "RGB").save(os.path.join(OUT, name + "_normal.png"))


def angular_crack(rng, start, angle, length, width, step=7.0, wander=0.16, kink_p=0.18, branch_p=0.035, depth=1):
    """Straight-ish crack segments with sharp kinks (shattered ground, not roots)."""
    out = []
    pts = [start]
    widths = []
    x, y = start
    a = angle
    n = max(2, int(length / step))
    for s in range(n):
        if rng.random() < kink_p:
            a += rng.uniform(-0.55, 0.55)
        else:
            a += rng.uniform(-wander, wander) * 0.5
        st = step * rng.uniform(0.7, 1.3)
        x += math.cos(a) * st
        y += math.sin(a) * st
        pts.append((x, y))
        u = s / n
        widths.append(width * (1.0 - u) ** 0.8 + 0.7)
        if depth > 0 and rng.random() < branch_p:
            out += angular_crack(rng, (x, y), a + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1), length * rng.uniform(0.2, 0.35),
                                 widths[-1] * 0.6, step * 0.8, wander, kink_p, 0.0, depth - 1)
    out.append((pts, widths))
    return out


def crater():
    S = 256
    rng = np.random.default_rng(7)
    prng = __import__("random").Random(7)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    u = (xx + 0.5) / S * 2 - 1
    v = (yy + 0.5) / S * 2 - 1
    r = np.sqrt(u * u + v * v)
    noise = smooth_noise((S, S), 6, rng)
    fine = smooth_noise((S, S), 1.5, rng)
    rc = 0.2 + (noise - 0.5) * 0.06
    centre = np.clip(1.0 - r / rc, 0, 1) ** 0.5
    rim = np.exp(-((r - (0.3 + (noise - 0.5) * 0.06)) / 0.06) ** 2) * (0.55 + 0.45 * fine)
    strokes = []
    c = S / 2
    n_main = 8
    angles = []
    ends = []
    for i in range(n_main):
        a = 2 * math.pi * i / n_main + prng.uniform(-0.3, 0.3)
        angles.append(a)
        r0 = S * 0.05
        start = (c + math.cos(a) * r0, c + math.sin(a) * r0)
        cr = angular_crack(prng, start, a, S * prng.uniform(0.3, 0.44), prng.uniform(5.0, 7.0), 7.0, 0.16, 0.2, 0.05, 1)
        strokes += cr
    # Concentric fractures joining neighbouring radial cracks: polygonal plates.
    for ring_r, w in ((0.13, 2.6), (0.24, 2.0)):
        for i in range(n_main):
            if prng.random() < 0.35:
                continue
            a0 = angles[i]
            a1 = angles[(i + 1) % n_main]
            if a1 < a0:
                a1 += 2 * math.pi
            rr0 = S * ring_r * prng.uniform(0.85, 1.15)
            rr1 = S * ring_r * prng.uniform(0.85, 1.15)
            mid = (a0 + a1) * 0.5 + prng.uniform(-0.15, 0.15)
            rm = (rr0 + rr1) * 0.5 * prng.uniform(0.9, 1.12)
            pts = [(c + math.cos(a0) * rr0, c + math.sin(a0) * rr0), (c + math.cos(mid) * rm, c + math.sin(mid) * rm),
                   (c + math.cos(a1) * rr1, c + math.sin(a1) * rr1)]
            strokes.append((pts, [w, w * 0.8]))
    crack = stroke_mask((S, S), strokes)
    crack = np.clip(crack * 1.3, 0, 1)
    outer = np.clip((0.98 - r) / 0.2, 0, 1)
    dust = np.clip(1.0 - r / 0.8, 0, 1) * (0.5 + 0.5 * noise)
    lum = np.ones_like(r)
    lum = lum * (1 - 0.5 * centre) * (1 - 0.88 * crack) + rim * 0.08
    lum = lum * (0.9 + 0.1 * fine)
    alpha = np.maximum.reduce([crack * 0.97, centre * 0.7, rim * 0.4, dust * 0.22]) * outer
    height = -crack * 1.0 - centre * 0.5 + rim * 0.35 + fine * 0.06
    save("crater", lum, alpha, gaussian_filter(height, 0.8), 5.0)


def fissure():
    W, H = 512, 128
    prng = __import__("random").Random(11)
    rng = np.random.default_rng(11)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    noise = smooth_noise((H, W), 5, rng)
    fine = smooth_noise((H, W), 1.4, rng)
    strokes = []
    # Main crack: a wandering line along u, widest in the middle.
    pts = []
    widths = []
    y = H / 2
    n = 64
    wn = smooth_noise((n + 1,), 2.5, rng)
    for i in range(n + 1):
        x = 10 + (W - 20) * i / n + prng.uniform(-2.0, 2.0)
        y += prng.uniform(-5.0, 5.0) if prng.random() < 0.6 else prng.uniform(-1.0, 1.0)
        y = min(max(y, H * 0.32), H * 0.68)
        pts.append((x, y))
        t = i / n
        widths.append(2.0 + 10.0 * math.sin(math.pi * t) ** 0.7 * (0.75 + 0.5 * wn[i]))
    strokes.append((pts, widths))
    # Side branches.
    for i in range(14):
        k = prng.randint(6, n - 6)
        x0, y0 = pts[k]
        side = -1 if prng.random() < 0.5 else 1
        a = (math.pi / 2 if side > 0 else -math.pi / 2) + prng.uniform(-0.9, 0.9)
        strokes += angular_crack(prng, (x0, y0), a, prng.uniform(14, 36), widths[k] * 0.4, 5.0, 0.16, 0.25, 0.0, 0)
    crack = np.clip(stroke_mask((W, H), strokes) * 1.25, 0, 1)
    edge = np.clip(gaussian_filter(crack, 5.0) * 3.0, 0, 1)
    ends = np.clip(np.minimum(xx, W - xx) / 26.0, 0, 1)
    lum = (1 - 0.88 * crack) * (1 - 0.25 * edge) * (0.88 + 0.12 * fine) + edge * 0.05 * noise
    alpha = np.maximum(crack * 0.97, edge * 0.5) * ends
    height = -crack * 1.0 - edge * 0.25 + fine * 0.05
    save("fissure", lum, alpha, gaussian_filter(height, 0.8), 6.0)


def furrow():
    W, H = 256, 64
    prng = __import__("random").Random(5)
    rng = np.random.default_rng(5)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    fine = smooth_noise((H, W), 1.3, rng)
    noise = smooth_noise((H, W), 4, rng)
    strokes = []
    for lane in (0.3, 0.5, 0.7):
        pts = []
        wd = []
        y = H * lane + prng.uniform(-2, 2)
        for i in range(41):
            x = 8 + (W - 16) * i / 40
            y += prng.uniform(-0.8, 0.8)
            pts.append((x, y))
            wd.append(1.5 + 3.5 * (i / 40) * prng.uniform(0.8, 1.1))
        strokes.append((pts, wd))
    groove = np.clip(stroke_mask((W, H), strokes) * 1.2, 0, 1)
    ridge = np.clip(gaussian_filter(groove, 2.6) * 2.4 - groove, 0, 1)
    along = np.clip(xx / W, 0, 1)
    ends = np.clip(xx / 30.0, 0, 1) * np.clip((W - xx) / 10.0, 0, 1)
    heap = np.exp(-(((xx - W * 0.93) / 14.0) ** 2 + ((yy - H * 0.5) / 18.0) ** 2))
    lum = (1 - 0.7 * groove) * (0.9 + 0.1 * fine) + ridge * 0.1
    alpha = np.maximum.reduce([groove * 0.85, ridge * 0.45 * (0.6 + 0.4 * noise), heap * 0.55]) * ends * (0.55 + 0.45 * along)
    height = -groove * 0.8 + ridge * 0.35 + heap * 0.6 + fine * 0.05
    save("furrow", lum, alpha, gaussian_filter(height, 0.7), 5.0)


if __name__ == "__main__":
    crater()
    fissure()
    furrow()
    print("earth mark textures written to", OUT)
