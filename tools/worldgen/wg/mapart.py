"""Painterly parchment-style world map for the in-game map screen (no baked text)."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

from . import grid
from . import noise as nz
from .classify import B
from .grid import smoothstep

PAPER = np.array([239, 227, 200], dtype=np.float64)
INK = np.array([62, 44, 30], dtype=np.float64)

TINTS = {
    "GRASSLAND": (184, 186, 128), "FOREST": (128, 150, 98), "FARMLAND": (214, 196, 128), "SNOW": (243, 243, 236),
    "ICE": (214, 230, 236), "TUNDRA": (200, 199, 172), "ROCK": (180, 164, 140), "MOUNTAIN": (170, 148, 120),
    "VOLCANIC": (102, 78, 66), "ASH": (150, 138, 128), "BEACH": (232, 214, 166), "TEMPLE": (220, 192, 128),
    "CITY": (186, 132, 98), "OCEAN": (150, 186, 190),
}


def _hillshade(h, cell, az, alt):
    gz, gx = np.gradient(h.astype(np.float64), cell)
    slope = np.pi / 2 - np.arctan(np.hypot(gx, gz) * 1.6)
    aspect = np.arctan2(-gx, gz)
    a = np.radians(360 - az + 90)
    e = np.radians(alt)
    return np.clip(np.sin(e) * np.sin(slope) + np.cos(e) * np.cos(slope) * np.cos(a - aspect), 0, 1)


def _to_px(x, z, size):
    return ((x + 4096.0) / 8192.0 * size, (z + 4096.0) / 8192.0 * size)


def render(h4096: np.ndarray, biome2048: np.ndarray, data: dict, seed: int, size: int = 2048) -> Image.Image:
    f = h4096.shape[0] // size
    h = grid.downsample_mean(h4096, f)
    biome = biome2048 if biome2048.shape[0] == size else biome2048[:: biome2048.shape[0] // size, :: biome2048.shape[0] // size]
    cell = 8192.0 / size
    X, Z = grid.mesh(size)
    land = h > 0.0
    # ---------------- paper ----------------
    stains = nz.fbm(X, Z, 1 / 1800, seed + 1, 4)
    fibres = nz.fbm(X * 3.0, Z * 0.6, 1 / 30, seed + 2, 2)
    paper = PAPER[None, None, :] * (1.0 + stains[..., None] * 0.045 + fibres[..., None] * 0.012)
    u = np.abs(X / 4096.0)
    v = np.abs(Z / 4096.0)
    vign = smoothstep(0.72, 1.02, np.maximum(u, v)) * 0.22 + smoothstep(0.5, 1.4, np.hypot(u, v)) * 0.1
    paper *= (1.0 - vign[..., None])
    # ---------------- land tints (watercolour) ----------------
    tint = np.zeros((size, size, 3))
    for name, col in TINTS.items():
        tint[biome == B[name]] = col
    tint = ndimage.gaussian_filter(tint, sigma=(2.2, 2.2, 0))
    wash = nz.fbm(X, Z, 1 / 260, seed + 3, 3)[..., None] * 0.06
    tint = tint * (1.0 + wash)
    # watercolour edge pooling: darken where the tint changes
    edge = ndimage.gaussian_gradient_magnitude(tint.mean(axis=-1), 1.5)
    tint *= (1.0 - np.clip(edge / 40.0, 0, 0.18))[..., None]
    # ---------------- relief ----------------
    hs = (_hillshade(h, cell, 315, 42) * 0.6 + _hillshade(h, cell, 260, 55) * 0.25 + _hillshade(h, cell, 20, 60) * 0.15)
    relief = 0.62 + 0.55 * hs
    relief = np.where(land, relief, 1.0)
    land_rgb = tint * relief[..., None]
    land_rgb = land_rgb * 0.82 + paper * 0.18 * (land_rgb / 255.0 + 0.4)
    # forest stipple
    forest = ndimage.gaussian_filter((biome == B["FOREST"]).astype(np.float64), 1.0)
    dots = (nz.perlin(X, Z, 1 / 14, seed + 4) > 0.42) & (forest > 0.6)
    land_rgb[dots] *= 0.8
    # farmland furrows
    farm = biome == B["FARMLAND"]
    furrow = (np.sin((X * 0.8 + Z * 0.35) / 9.0) > 0.6) & farm
    land_rgb[furrow] *= 0.93
    # ---------------- water ----------------
    sea_d = ndimage.distance_transform_edt(~land) * cell
    deep = smoothstep(0, 1600, sea_d)
    water = np.array([170, 198, 196])[None, None, :] * (1 - deep[..., None]) + np.array([118, 158, 170])[None, None, :] * deep[..., None]
    water = water * (1.0 + nz.fbm(X, Z, 1 / 500, seed + 5, 3)[..., None] * 0.05)
    water = water * 0.75 + paper * 0.25 * (water / 200.0 + 0.3)
    # concentric coastline ripples (classic chart style)
    ripple = np.zeros((size, size))
    for k, dd in enumerate((26.0, 64.0, 118.0, 190.0)):
        ripple += np.exp(-((sea_d - dd) / 5.5) ** 2) * (0.5 - k * 0.1)
    water = water * (1.0 - ripple[..., None] * 0.35)
    rgb = np.where(land[..., None], land_rgb, water)
    # contour lines on land
    for step, strength in ((100.0, 0.10), (500.0, 0.2)):
        frac = np.abs(((h / step) + 0.5) % 1.0 - 0.5) * step
        grad = np.hypot(*np.gradient(h, cell)) + 1e-3
        line = smoothstep(1.2, 0.0, frac / grad / cell * 2.0) * land * (h > 40)
        rgb = rgb * (1.0 - line[..., None] * strength) + INK * line[..., None] * strength * 0.3
    # coastline ink
    coast = ndimage.binary_dilation(land, iterations=1) & ~ndimage.binary_erosion(land, iterations=1)
    coast_f = ndimage.gaussian_filter(coast.astype(np.float64), 0.7)
    coast_f = np.clip(coast_f * 1.8, 0, 1)
    rgb = rgb * (1 - coast_f[..., None] * 0.85) + INK * coast_f[..., None] * 0.85
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    # ---------------- vector overlay (supersampled) ----------------
    ss = 2
    over = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(over)
    for lk in data.get("lakes", []):
        poly = [_to_px(p[0], p[1], size * ss) for p in lk["polygon"]]
        fill = (226, 236, 238, 235) if lk.get("frozen") else (150, 186, 192, 240)
        dr.polygon(poly, fill=fill, outline=(62, 44, 30, 230))
    for c in data.get("canals", []):
        pts = [_to_px(p[0], p[1], size * ss) for p in c["points"]]
        dr.line(pts, fill=(130, 170, 182, 255), width=3)
    for rd in data.get("roads", []):
        pts = [_to_px(p[0], p[2], size * ss) for p in rd["points"]]
        main = rd.get("kind") == "main"
        col = (128, 40, 26, 240) if main else (104, 66, 40, 220)
        if main:   # pale casing under main roads keeps them readable on dark relief
            dr.line(pts, fill=(239, 227, 200, 150), width=9, joint="curve")
        _dashed(dr, pts, col, width=6 if main else 3, dash=18 if main else 7, gap=6 if main else 7)
    for fr in data.get("ferries", []):
        pts = [_to_px(p[0], p[1], size * ss) for p in fr["points"]]
        _dashed(dr, pts, (62, 44, 30, 150), width=3, dash=5, gap=12)
    for city in data.get("cities", []):
        _draw_city(dr, city, size * ss)
    for v in data.get("villages", []):
        x, _, z = v["center"]
        px, pz = _to_px(x, z, size * ss)
        r = max(5.0, v["radius"] / 8192.0 * size * ss * 0.8)
        dr.ellipse([px - r, pz - r, px + r, pz + r], fill=(176, 110, 76, 230), outline=(62, 44, 30, 255), width=2)
    _compass(dr, _to_px(-3420, -1650, size * ss), 120)
    over = over.resize((size, size), Image.LANCZOS)
    img = Image.alpha_composite(img.convert("RGBA"), over).convert("RGB")
    img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=40, threshold=2))
    # final paper grain multiply
    grain = (1.0 + nz.fbm(X * 4, Z * 4, 1 / 40, seed + 6, 2) * 0.025)[..., None]
    out = np.asarray(img).astype(np.float64) * grain
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def _dashed(dr, pts, col, width, dash, gap):
    if len(pts) < 2:
        return
    acc = 0.0
    on = True
    seg_left = dash
    cur = pts[0]
    for nxt in pts[1:]:
        dx, dz = nxt[0] - cur[0], nxt[1] - cur[1]
        ln = math.hypot(dx, dz)
        pos = 0.0
        while pos < ln:
            step = min(seg_left, ln - pos)
            a = (cur[0] + dx * pos / ln, cur[1] + dz * pos / ln)
            b = (cur[0] + dx * (pos + step) / ln, cur[1] + dz * (pos + step) / ln)
            if on:
                dr.line([a, b], fill=col, width=width)
            pos += step
            seg_left -= step
            if seg_left <= 1e-6:
                on = not on
                seg_left = dash if on else gap
        cur = nxt
        acc += ln


def _draw_city(dr, city, size):
    cx, cz = city.get("ring_center", [city["center"][0], city["center"][2]])
    px, pz = _to_px(cx, cz, size)
    scale = size / 8192.0
    fill = (180, 108, 74, 140)
    for t in city.get("tiers", []):
        ro = t["r_outer"] * scale
        ri = t["r_inner"] * scale
        if t.get("arc"):
            a0, a1 = t["arc"]
            # PIL angles: 0 = +x, clockwise; bearing 0 = north (-z) => pil = bearing - 90
            dr.arc([px - ro, pz - ro, px + ro, pz + ro], a0 - 90, a1 - 90, fill=(98, 60, 40, 230), width=3)
            for rr in np.linspace(ri, ro, 4):
                dr.arc([px - rr, pz - rr, px + rr, pz + rr], a0 - 90, a1 - 90, fill=fill, width=max(2, int((ro - ri) / 3)))
        else:
            dr.ellipse([px - ro, pz - ro, px + ro, pz + ro], outline=(98, 60, 40, 230), width=3)
    if city["id"] == "ba_sing_se":
        for w in city.get("walls", []):
            r = w["radius"] * scale
            dr.ellipse([px - r, pz - r, px + r, pz + r], outline=(70, 46, 32, 255), width=5 if w["radius"] > 600 else 3)
    if city.get("sea_wall"):
        pts = [_to_px(p[0], p[1], size) for p in city["sea_wall"]["points"]]
        dr.line(pts, fill=(70, 46, 32, 255), width=6)
    pal = city.get("palace")
    if pal:
        x, _, z = pal["position"]
        qx, qz = _to_px(x, z, size)
        r = 7
        dr.rectangle([qx - r, qz - r, qx + r, qz + r], fill=(150, 40, 28, 255), outline=(62, 44, 30, 255), width=2)


def _compass(dr, c, r):
    cx, cz = c
    col = (62, 44, 30, 200)
    dr.ellipse([cx - r * 0.55, cz - r * 0.55, cx + r * 0.55, cz + r * 0.55], outline=col, width=3)
    dr.ellipse([cx - r * 0.62, cz - r * 0.62, cx + r * 0.62, cz + r * 0.62], outline=(62, 44, 30, 120), width=2)
    for k in range(8):
        a = math.radians(k * 45)
        long = r if k % 2 == 0 else r * 0.55
        tip = (cx + math.sin(a) * long, cz - math.cos(a) * long)
        left = (cx + math.sin(a - 0.5) * r * 0.14, cz - math.cos(a - 0.5) * r * 0.14)
        right = (cx + math.sin(a + 0.5) * r * 0.14, cz - math.cos(a + 0.5) * r * 0.14)
        fill = (128, 46, 30, 230) if k == 0 else ((62, 44, 30, 200) if k % 2 == 0 else (62, 44, 30, 120))
        dr.polygon([left, tip, right, (cx, cz)], fill=fill)
