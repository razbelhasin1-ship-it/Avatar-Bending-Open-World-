"""Base elevation: landmass signed distance, coasts, sea floor, mountains, volcanoes.

Produces the coarse (default 1024^2, 8 m/texel) elevation that is eroded before
being upsampled. Full-resolution shaped features (cities, roads...) live in
shapes.py.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from . import grid, layout
from . import noise as nz
from .grid import smoothstep, lerp

# Territory codes used during generation (match layout.REGION_IDS order)
T_OCEAN, T_WATER, T_EARTH, T_FIRE, T_AIR, T_WILDS = range(6)


def _poly_pixels(poly, n):
    return [grid.to_pixel(x, z, n) for x, z in poly]


def ellipse_poly(cx, cz, rx, rz, rot_deg, segs=96):
    r = math.radians(rot_deg)
    cr, sr = math.cos(r), math.sin(r)
    pts = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        ex, ez = rx * math.cos(a), rz * math.sin(a)
        pts.append((cx + ex * cr - ez * sr, cz + ex * sr + ez * cr))
    return pts


def ellipse_dist(X, Z, cx, cz, rx, rz, rot_deg):
    """Normalised elliptical distance (1 on the ellipse boundary)."""
    r = math.radians(rot_deg)
    cr, sr = math.cos(r), math.sin(r)
    dx, dz = X - cx, Z - cz
    u = dx * cr + dz * sr
    v = -dx * sr + dz * cr
    return np.sqrt((u / rx) ** 2 + (v / rz) ** 2)


def polygon_mask(poly, n) -> np.ndarray:
    img = Image.new("L", (n, n), 0)
    ImageDraw.Draw(img).polygon(_poly_pixels(poly, n), fill=255)
    return np.asarray(img) > 127


def rasterize_land(n: int) -> tuple[np.ndarray, np.ndarray]:
    """Binary land mask and territory map at resolution n (before coastline noise)."""
    land = Image.new("L", (n, n), 0)
    terr = Image.new("L", (n, n), T_OCEAN)
    dl = ImageDraw.Draw(land)
    dt = ImageDraw.Draw(terr)
    for poly, t in ((layout.ARCTIC, T_WATER), (layout.EARTH_KINGDOM, T_EARTH), (layout.FIRE_MAIN, T_FIRE)):
        dl.polygon(_poly_pixels(poly, n), fill=255)
        dt.polygon(_poly_pixels(poly, n), fill=t)
    dl.polygon(_poly_pixels(layout.FROZEN_STRAIT, n), fill=255)
    dt.polygon(_poly_pixels(layout.FROZEN_STRAIT, n), fill=T_WILDS)
    air_poly = list(layout.AIR_BOUNDARY) + [(4100, 4100), (900, 4100)]
    air_a = polygon_mask(air_poly, n)
    for cx, cz, rx, rz, rot, kind in layout.ISLANDS:
        poly = ellipse_poly(cx, cz, rx, rz, rot)
        dl.polygon(_poly_pixels(poly, n), fill=255)
        dt.polygon(_poly_pixels(poly, n), fill=T_FIRE if kind == "fire" else T_WILDS)
    for cx, cz, rx, rz, rot in layout.BAYS:
        dl.polygon(_poly_pixels(ellipse_poly(cx, cz, rx, rz, rot), n), fill=0)
    land_a = np.asarray(land) > 127
    terr_a = np.asarray(terr).copy()
    terr_a[(terr_a == T_EARTH) & air_a] = T_AIR
    return land_a, terr_a


def signed_distance(mask: np.ndarray, cell: float) -> np.ndarray:
    """Signed distance in metres, positive inside the mask."""
    d_in = ndimage.distance_transform_edt(mask) * cell
    d_out = ndimage.distance_transform_edt(~mask) * cell
    return (d_in - d_out).astype(np.float32)


class Base:
    """Coarse base terrain and the fields derived while building it."""

    def __init__(self, n: int, seed: int):
        self.n = n
        self.seed = seed
        self.cell = grid.cell_size(n)
        self.X, self.Z = grid.mesh(n)
        self.h = np.zeros((n, n), dtype=np.float32)
        self.sdf = None          # noisy coast distance (m), + on land
        self.territory = None    # T_* codes (land), propagated into near-shore water
        self.cliff = None        # 0..1 coast cliffiness
        self.erodibility = None  # 0..1 erosion strength multiplier
        self.precise = None      # 0..1: 1 where the authored layout must not be disturbed


def precise_damp(X, Z) -> np.ndarray:
    damp = np.ones(X.shape, dtype=np.float32)
    for cx, cz, r in layout.PRECISE_COAST:
        dd = np.hypot(X - cx, Z - cz)
        damp = np.minimum(damp, 0.08 + 0.92 * smoothstep(r * 0.5, r, dd))
    return damp


def build_coast(b: Base) -> None:
    n, X, Z, s = b.n, b.X, b.Z, b.seed
    hi = n * 2
    land_hi, terr_hi = rasterize_land(hi)
    sdf_hi = signed_distance(land_hi, grid.cell_size(hi))
    sdf = grid.downsample_mean(sdf_hi, 2).astype(np.float32)
    terr = terr_hi[::2, ::2]
    # Multi-scale coast noise on warped coordinates, region specific, damped where precision matters
    wx, wz = nz.warp(X, Z, 1 / 2200, 520, s + 1)
    big = nz.fbm(wx, wz, 1 / 2600, s + 2, octaves=3)
    mid = nz.fbm(wx, wz, 1 / 720, s + 3, octaves=3)
    small = nz.fbm(wx, wz, 1 / 210, s + 4, octaves=3)
    fj = nz.ridged(wx, wz, 1 / 650, s + 5, octaves=3, sharpness=3.0)
    scale = np.full((n, n), 1.0, dtype=np.float32)
    scale[terr == T_WATER] = 1.25
    scale[terr == T_FIRE] = 0.85
    scale[terr == T_WILDS] = 0.55
    scale[terr == T_AIR] = 0.9
    scale = ndimage.gaussian_filter(scale, 14)
    arctic = ndimage.gaussian_filter((terr == T_WATER).astype(np.float32), 10)
    damp = precise_damp(X, Z)
    b.precise = 1.0 - damp
    noise = (big * 420 + mid * 150 + small * 38) * scale - fj * 200 * arctic + 40 * arctic
    sdf = sdf + noise * damp
    # nothing but deep sea near the world border
    border = np.minimum(np.minimum(X - grid.WORLD_MIN, -grid.WORLD_MIN - X), np.minimum(Z - grid.WORLD_MIN, -grid.WORLD_MIN - Z))
    sdf = np.minimum(sdf, border - 260.0)
    b.sdf = sdf.astype(np.float32)
    land = b.sdf > 0
    t_land = terr.copy()
    idx = ndimage.distance_transform_edt(t_land == T_OCEAN, return_distances=False, return_indices=True)
    nearest = t_land[idx[0], idx[1]]
    dist_land = ndimage.distance_transform_edt(~land) * b.cell
    b.territory = np.where(land | (dist_land < 260.0), nearest, T_OCEAN).astype(np.uint8)
    # Coast cliffiness
    cn = nz.fbm(X, Z, 1 / 1300, s + 6, octaves=3) * 0.5 + 0.5
    bias = np.zeros((n, n), dtype=np.float32)
    bias[b.territory == T_WATER] = 0.6
    bias[b.territory == T_AIR] = 0.55
    bias[b.territory == T_EARTH] = 0.05
    bias[b.territory == T_FIRE] = 0.05
    bias[b.territory == T_WILDS] = 0.3
    bias = ndimage.gaussian_filter(bias, 10)
    cliff = np.clip((cn - 0.55) * 2.6 + bias, 0.0, 1.0)
    for cx, cz, r in layout.PRECISE_COAST:   # harbours / beaches stay gentle
        cliff *= smoothstep(r * 0.4, r * 0.9, np.hypot(X - cx, Z - cz))
    b.cliff = cliff.astype(np.float32)


def _range_field(X, Z, s) -> np.ndarray:
    out = np.zeros(X.shape, dtype=np.float32)
    wx, wz = nz.warp(X, Z, 1 / 1600, 380, s + 21)
    along = nz.fbm(X, Z, 1 / 1400, s + 22, 2) * 0.5 + 0.5
    for k, (pts, hw, peak, wl) in enumerate(layout.RANGES):
        pts_a = np.asarray(pts, dtype=np.float64)
        x0, z0 = pts_a.min(axis=0) - hw - 400
        x1, z1 = pts_a.max(axis=0) + hw + 400
        box = (wx > x0) & (wx < x1) & (wz > z0) & (wz < z1)
        if not box.any():
            continue
        rows = np.where(box.any(axis=1))[0]
        cols = np.where(box.any(axis=0))[0]
        sl = (slice(rows[0], rows[-1] + 1), slice(cols[0], cols[-1] + 1))
        dist, _, _ = grid.polyline_distance(wx[sl], wz[sl], pts)
        m = smoothstep(hw, 0.0, dist)
        r = nz.ridged(wx[sl], wz[sl], 1.0 / wl, s + 100 + k, octaves=7, sharpness=2.3)
        crag = nz.ridged(wx[sl], wz[sl], 1.0 / 210.0, s + 150 + k, octaves=4, sharpness=2.5)
        prof = m ** 1.35 * (0.18 + 0.95 * r + 0.18 * crag) * (0.75 + 0.5 * along[sl])
        out[sl] = smooth_max(out[sl], peak * prof, 40.0)
    for k, (cx, cz, height, rad) in enumerate(layout.PEAKS):
        dd = np.hypot(wx - cx, wz - cz) / (rad * 1.25)
        t = np.clip(1 - dd, 0, 1)
        massif = (t * t * (3 - 2 * t)) ** 1.15          # broad shoulders, rounded summit
        if not massif.any():
            continue
        r = nz.ridged(wx, wz, 1 / 240, s + 200 + k, octaves=6, sharpness=2.3)
        out = smooth_max(out, height * massif * (0.5 + 0.5 * r), 30.0)
    return out


def sharpen_mountains(h: np.ndarray, cell: float) -> np.ndarray:
    """Unsharp-masks high ground so crests and gullies stay crisp after erosion/upsampling."""
    blur = ndimage.gaussian_filter(h, 2.0)
    w = smoothstep(180.0, 450.0, h)
    return (h + 0.9 * (h - blur) * w).astype(np.float32)


def smooth_max(a, b, k: float):
    """Polynomial smooth maximum (no creases where two fields meet)."""
    hh = np.clip(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
    return (b + (a - b) * hh + k * hh * (1.0 - hh)).astype(np.float32)


def build_elevation(b: Base) -> None:
    n, X, Z, s = b.n, b.X, b.Z, b.seed
    d = b.sdf
    terr = b.territory
    land = d > 0
    w = {t: ndimage.gaussian_filter((terr == t).astype(np.float32), 6) for t in range(6)}

    # --- coast + inland rise -------------------------------------------------------
    c = b.cliff
    cliff_h = lerp(1.2, 24.0, c)
    cliff_w = lerp(110.0, 22.0, c)
    rise = cliff_h * smoothstep(0.0, cliff_w, d)
    gain = 48 * w[T_EARTH] + 230 * w[T_WATER] + 60 * w[T_FIRE] + 220 * w[T_AIR] + 30 * w[T_WILDS]
    length = 900 * w[T_EARTH] + 800 * w[T_WATER] + 450 * w[T_FIRE] + 600 * w[T_AIR] + 160 * w[T_WILDS] + 1.0
    inland = gain * (1.0 - np.exp(-np.maximum(d, 0) / length))
    tundra = smoothstep(-1050.0, -1450.0, Z) * w[T_EARTH]
    inland = inland * (1.0 - 0.65 * tundra)
    region_var = nz.fbm(X, Z, 1 / 2600, s + 10, 2) * 0.5 + 0.5          # some districts hillier than others
    hills_amp = (62 * w[T_EARTH] + 34 * w[T_WATER] + 55 * w[T_FIRE] + 70 * w[T_AIR] + 26 * w[T_WILDS]) * (1 - 0.7 * tundra)
    hills_amp *= 0.45 + 0.9 * region_var
    wx, wz = nz.warp(X, Z, 1 / 1500, 320, s + 11)
    hills = nz.fbm(wx, wz, 1 / 760, s + 12, octaves=6) * hills_amp
    hills += (nz.ridged(wx, wz, 1 / 1100, s + 14, octaves=4, sharpness=1.6) - 0.42) * hills_amp * 0.9
    hills += (np.abs(nz.fbm(wx, wz, 1 / 300, s + 13, octaves=3)) - 0.25) * hills_amp * 0.4
    land_h = rise + (inland + hills * smoothstep(0, 320, d)) * smoothstep(0.0, 140.0, d)

    # --- mountain ranges ---------------------------------------------------------------
    mt = _range_field(X, Z, s)
    air_base = smoothstep(0.1, 0.9, ndimage.gaussian_filter(w[T_AIR], 22))
    mt = np.maximum(mt, air_base * (230 + 140 * (nz.fbm(wx, wz, 1 / 900, s + 31, 4) * 0.5 + 0.5)))
    land_h = land_h + mt * smoothstep(0.0, 90.0, d)

    # --- Omashu's mountain: the city crowns its summit --------------------------------
    ocx, ocz = layout.OMASHU["center"]
    rom = np.hypot(X - ocx, Z - ocz) * (1.0 + 0.12 * nz.fbm(X, Z, 1 / 400, s + 35, 3))
    mount = 168.0 * (1.0 - smoothstep(330.0, 1150.0, rom)) ** 1.3 + nz.ridged(X, Z, 1 / 230, s + 36, 4) * 26.0 * \
        smoothstep(380.0, 600.0, rom) * (1.0 - smoothstep(900.0, 1300.0, rom))
    land_h = np.where(rom < 1400.0, smooth_max(land_h, mount, 25.0), land_h)

    # --- Earth Kingdom plateaus and canyons ---------------------------------------
    land_h = _plateaus_and_canyons(b, land_h, d)

    # --- Ba Sing Se plain (irregular outline) ---------------------------------------
    cx, cz = layout.BA_SING_SE["center"]
    dd = np.hypot(X - cx, Z - cz) + nz.fbm(X, Z, 1 / 700, s + 60, 3) * 260
    plain = 57.0 + nz.fbm(X, Z, 1 / 900, s + 61, 3) * 5.0 + np.clip(((X - cx) - (Z - cz)) / 1400.0, -1, 1) * 9.0
    plain_w = smoothstep(1250.0, 790.0, dd) ** 1.5
    plain_w = np.maximum(plain_w, smoothstep(820.0, 735.0, np.hypot(X - cx, Z - cz)))
    land_h = lerp(land_h, plain, plain_w)

    # --- Fire Nation volcanoes ----------------------------------------------------------
    land_h = _fire_caldera(b, land_h, d)
    land_h = _volcano_island(b, land_h)

    # --- small islands with character -----------------------------------------------
    land_h = _islands(b, land_h, d)

    # --- Air Temple spire + pass face -------------------------------------------------
    land_h, spire_w = _air_spire(b, land_h)

    # --- Arctic: ice shelves, glaciers, crevasses; frozen strait ------------------------
    land_h = _arctic(b, land_h, d)
    land_h = _strait(b, land_h, d)

    # --- sea floor --------------------------------------------------------------------
    sd = ndimage.gaussian_filter(np.maximum(-d, 0), 5)
    depth = 2.5 * smoothstep(0, 80, sd) + 30.0 * smoothstep(40, 520, sd) + 170.0 * smoothstep(380, 1700, sd)
    depth += c * 16.0 * smoothstep(0, 50, sd)
    depth += (nz.fbm(X, Z, 1 / 650, s + 71, 4) * 0.5 + 0.5) * 22.0 * smoothstep(200, 1000, sd)
    sea_h = -depth
    b.h = np.where(land, np.maximum(land_h, 0.05), sea_h).astype(np.float32)

    # Erosion strength: lower on ice, none at sea, none in planned city plains / spire
    arctic_er = 0.3 + 0.55 * smoothstep(140.0, 380.0, b.h)      # glaciated ranges get carved too
    er = 1.0 * w[T_EARTH] + arctic_er * w[T_WATER] + 0.85 * w[T_FIRE] + 1.0 * w[T_AIR] + 0.6 * w[T_WILDS]
    er *= smoothstep(-5, 25, d)
    er *= 1.0 - plain_w
    er *= 1.0 - spire_w
    for city in (layout.FIRE_CAPITAL, layout.OMASHU):
        ccx, ccz = city["center"]
        er *= smoothstep(320.0, 520.0, np.hypot(X - ccx, Z - ccz))
    px, pz = layout.NWT["harbor_center"]
    er *= smoothstep(760.0, 950.0, np.hypot(X - px, Z - pz))
    b.erodibility = np.clip(er, 0, 1).astype(np.float32)


def enforce_peaks(h: np.ndarray, X: np.ndarray, Z: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Raises each named summit (layout.PEAKS) to its authored height after erosion wore it down.
    `mask` (0..1) keeps the bumps off shaped areas (temple spire, cities, plains)."""
    out = h.copy()
    for cx, cz, target, rad in layout.PEAKS:
        r = np.hypot(X - cx, Z - cz)
        near = r < rad * 0.55
        if not near.any():
            continue
        local = np.where(near, out, -1e9)
        j, i = np.unravel_index(int(np.argmax(local)), local.shape)
        cur = float(out[j, i])
        if cur >= target:
            continue
        rr = np.hypot(X - X[j, i], Z - Z[j, i]) / rad
        t = np.clip(1.0 - rr, 0.0, 1.0)
        bump = t * t * (3.0 - 2.0 * t) * mask
        out = out + (target - cur) * bump
    return out.astype(np.float32)


def carve_channel(h, X, Z, pts, half_width, floor_start, floor_end, wall_width, terraces=0, seed=0):
    """Carves a valley/canyon whose floor descends linearly along the polyline."""
    dist, seg, t = grid.polyline_distance(X, Z, pts)
    s_cum = grid.polyline_lengths(pts)
    seg_len = np.diff(s_cum)
    along = (s_cum[seg] + t * seg_len[seg]) / max(s_cum[-1], 1e-6)
    floor = lerp(floor_start, floor_end, along)
    wall = smoothstep(half_width, half_width + wall_width, dist)
    if terraces:
        wall = nz.terrace(wall * terraces, 1.0, 0.55) / terraces
    target = floor + (h - floor) * wall
    return np.minimum(h, target)


def _plateaus_and_canyons(b: Base, land_h, d):
    X, Z, s = b.X, b.Z, b.seed
    for cx, cz, rad in layout.PLATEAUS:
        wx, wz = nz.warp(X, Z, 1 / 700, 160, s + 40)
        dd = np.hypot(wx - cx, wz - cz) / rad
        m = smoothstep(1.0, 0.6, dd) * smoothstep(0, 240, d)
        base = 45 + 150 * np.clip(nz.fbm(wx, wz, 1 / 760, s + 41, octaves=3) * 0.9 + 0.5, 0, 1) * m
        base += nz.fbm(X, Z, 1 / 140, s + 42, 3) * 5
        mesa = nz.terrace(base, 52.0, 0.88)
        land_h = np.where(m > 0, lerp(land_h, mesa, smoothstep(0.0, 0.5, m)), land_h)
    for k, (pts, width, depth) in enumerate(layout.CANYONS):
        wpx, wpz = nz.warp(X, Z, 1 / 380, 40, s + 50 + k)
        start_floor = 46.0 if k == 0 else 40.0
        land_h = carve_channel(land_h, wpx, wpz, pts, width * 0.5, start_floor, 1.5, 38.0, terraces=3)
    return land_h


def _fire_caldera(b: Base, land_h, d):
    cfg = layout.FIRE_CAPITAL
    X, Z, s = b.X, b.Z, b.seed
    cx, cz = cfg["center"]
    hx, hz = layout.fire_gorge()["gate"]
    gorge_bearing = math.atan2(hx - cx, hz - cz)
    dx, dz = X - cx, Z - cz
    r = np.hypot(dx, dz)
    ang = np.arctan2(dx, dz)
    ca, sa = np.cos(ang), np.sin(ang)
    rim_lo, rim_hi = cfg["rim_height"]
    rim_var = nz.fbm(ca * 500, sa * 500, 1 / 260, s + 81, 4) * 0.5 + 0.5
    rim = rim_lo + (rim_hi - rim_lo) * rim_var
    floor_r = cfg["floor_radius"]
    rim_r = cfg["rim_radius"] + nz.fbm(ca * 500, sa * 500, 1 / 300, s + 83, 3) * 28
    base_r = 1080 + nz.fbm(ca * 600, sa * 600, 1 / 400, s + 84, 3) * 230
    floor_h = 112.0
    inner = floor_h + (rim - floor_h) * smoothstep(floor_r - 5, rim_r, r) ** 0.62
    t_out = np.clip((r - rim_r) / np.maximum(base_r - rim_r, 1.0), 0, 1)
    gullies = nz.ridged(ang * 330.0, r * 0.12, 1 / 60, s + 85, 3, sharpness=1.5)
    outer = rim * (1 - t_out) ** 1.35
    outer = outer - gullies * 26 * np.sin(np.pi * t_out) + nz.fbm(X, Z, 1 / 180, s + 86, 3) * 10 * t_out
    prof = np.where(r < rim_r, inner, outer)
    # Gorge through the rim toward the harbour (the "Dragon's Throat")
    g = layout.fire_gorge()
    da = np.angle(np.exp(1j * (ang - gorge_bearing)))
    across = np.abs(np.sin(da)) * r
    along_ok = np.cos(da) > 0
    t_g = np.clip((r - g["r_in"]) / (g["r_out"] - g["r_in"]), 0, 1)
    gorge_floor = lerp(g["floor_in"], g["floor_out"], t_g)
    gw = smoothstep(70.0, 26.0, across) * along_ok * smoothstep(floor_r - 30, floor_r + 5, r)
    gw *= smoothstep(g["r_out"] + 160, g["r_out"] + 40, r)
    prof = np.where(gw > 0, lerp(prof, np.minimum(prof, gorge_floor), gw), prof)
    w = smoothstep(base_r + 120, base_r - 200, r) * smoothstep(-20.0, 80.0, d)
    w = np.where(r < rim_r + 60, smoothstep(-60.0, 5.0, d), w)
    return lerp(land_h, np.maximum(prof, 1.0), w)


def _volcano_island(b: Base, land_h):
    X, Z, s = b.X, b.Z, b.seed
    cx, cz = -1650, 3480
    r = np.hypot(X - cx, Z - cz)
    ang = np.arctan2(X - cx, Z - cz)
    gullies = nz.ridged(ang * 160.0, r * 0.12, 1 / 45, s + 91, 3, sharpness=1.4)
    t = np.clip(r / 480.0, 0, 1)
    cone = 440.0 * (1 - t) ** 1.2 - gullies * 22 * np.sin(np.pi * t)
    crater = 320.0 + 22.0 * smoothstep(40, 100, r)
    prof = np.where(r < 100, np.minimum(cone, crater), cone)
    w = smoothstep(540.0, 380.0, r)
    return lerp(land_h, np.maximum(prof, 0.5), w)


def _islands(b: Base, land_h, d):
    X, Z, s = b.X, b.Z, b.seed
    specs = {
        (-2700, -1300): ("crag", 95.0), (-2050, 300): ("hill", 70.0), (2700, -2230): ("hill", 45.0),
        (-3600, -600): ("stack", 135.0), (-1800, -2200): ("low", 12.0), (350, 2960): ("atoll", 4.0),
        (-3400, 1240): ("hill", 75.0),
    }
    for (cx, cz), (kind, height) in specs.items():
        r = np.hypot(X - cx, Z - cz)
        m = smoothstep(560.0, 380.0, r)
        if not m.any():
            continue
        dd = np.maximum(d, 0)
        if kind == "atoll":
            prof = 1.0 + 3.0 * smoothstep(0, 40, dd) + nz.fbm(X, Z, 1 / 60, s + 300, 2) * 1.0
            lagoon = smoothstep(120.0, 90.0, r)
            prof = lerp(prof, -5.5, lagoon)
        elif kind == "stack":
            prof = height * smoothstep(0, 45, dd) ** 0.6 * (0.8 + 0.2 * nz.fbm(X, Z, 1 / 90, s + 301, 3))
        elif kind == "crag":
            prof = height * smoothstep(0, 150, dd) * (0.6 + 0.4 * nz.ridged(X, Z, 1 / 160, s + 302, 4))
        elif kind == "low":
            prof = height * smoothstep(0, 80, dd)
        else:
            prof = height * smoothstep(0, 260, dd) ** 1.2 * (0.75 + 0.25 * nz.fbm(X, Z, 1 / 200, s + 303, 3))
        land_h = lerp(land_h, prof, m)
    return land_h


def _air_spire(b: Base, land_h):
    """Southern Air Temple spire (flat top, sheer cliffs) and the pass face below it."""
    X, Z, s = b.X, b.Z, b.seed
    cfg = layout.AIR_TEMPLE
    cx, cz = cfg["center"]
    top = cfg["tiers"][-1]["height"]
    r = np.hypot(X - cx, Z - cz)
    ang = np.arctan2(X - cx, Z - cz)
    edge = 220.0 + nz.fbm(np.cos(ang) * 300, np.sin(ang) * 300, 1 / 150, s + 400, 3) * 18
    drop = cfg["spire_drop"]
    cliff = top - drop * smoothstep(edge, edge + 150.0, r) ** 0.55
    ridges = nz.ridged(ang * 160.0, r * 0.15, 1 / 50, s + 401, 3, sharpness=1.6)
    cliff -= ridges * 18 * smoothstep(edge, edge + 60, r)
    moat = top - drop - 40 + 220 * smoothstep(edge + 180, edge + 620, r)
    surround = np.minimum(land_h, moat)
    w = smoothstep(edge + 700.0, edge + 400.0, r)
    out = lerp(land_h, surround, w)
    out = np.where(r < edge + 200, np.maximum(cliff, np.minimum(out, cliff)) * 0 + cliff, out)
    out = lerp(out, np.minimum(out, cliff), smoothstep(edge + 260, edge + 180, r))
    # Pass face: an inclined mountainside that the switchback road climbs
    p = layout.AIR_PASS
    bx, bz = p["bottom"]
    tx, tz = p["top"]
    vx, vz = tx - bx, tz - bz
    vlen = math.hypot(vx, vz)
    ux, uz = vx / vlen, vz / vlen
    along = ((X - bx) * ux + (Z - bz) * uz) / vlen
    across = (X - bx) * (-uz) + (Z - bz) * ux
    hw = p["face_width"] * 0.5
    plane = p["bottom_height"] - 20 + (p["top_height"] - p["bottom_height"] + 20) * np.clip(along, 0, 1.0)
    plane += nz.fbm(X, Z, 1 / 120, s + 410, 3) * 5
    fw = smoothstep(hw + 170, hw + 20, np.abs(across)) * smoothstep(-0.18, 0.04, along) * smoothstep(1.12, 0.97, along)
    out = lerp(out, plane, fw)
    spire_w = np.maximum(smoothstep(edge + 200, edge + 60, r), fw)
    return out, np.clip(spire_w, 0, 1).astype(np.float32)


def _arctic(b: Base, land_h, d):
    X, Z, s = b.X, b.Z, b.seed
    n = b.n
    out = land_h
    for k, poly in enumerate(layout.ICE_SHELVES):
        m = ndimage.gaussian_filter(polygon_mask(poly, n).astype(np.float32), 8)
        m = m * smoothstep(560.0, 280.0, d)
        shelf = 19.0 + nz.fbm(X, Z, 1 / 300, s + 120 + k, 3) * 2.5
        shelf = shelf * smoothstep(0.0, 12.0, d)
        out = lerp(out, shelf, m)
    blur = ndimage.gaussian_filter(out, 8)
    for k, (pts, width) in enumerate(layout.GLACIERS):
        wx, wz = nz.warp(X, Z, 1 / 600, 90, s + 130 + k)
        dist, _, _ = grid.polyline_distance(wx, wz, pts)
        g = smoothstep(width * 0.8, width * 0.25, dist) * smoothstep(0, 60, d)
        u = np.clip(dist / (width * 0.8), 0, 1)
        surface = blur - 30.0 * (1 - u ** 2) + nz.fbm(X, Z, 1 / 140, s + 140 + k, 2) * 1.5
        out = lerp(out, np.maximum(surface, 10.0), g)
    for k, poly in enumerate(layout.CREVASSE_FIELDS):
        m = ndimage.gaussian_filter(polygon_mask(poly, n).astype(np.float32), 12) * smoothstep(0, 150, d)
        wx, wz = nz.warp(X, Z, 1 / 500, 120, s + 155 + k)
        cr = nz.ridged(wx * 0.45, wz * 1.6, 1 / 150, s + 150 + k, 3, sharpness=4.0)
        out = out + m * (cr * 32.0 - 6.0)
    return out


def _strait(b: Base, land_h, d):
    X, Z, s = b.X, b.Z, b.seed
    m = ndimage.gaussian_filter(polygon_mask(layout.FROZEN_STRAIT, b.n).astype(np.float32), 5)
    m *= smoothstep(-2280.0, -2120.0, Z) * smoothstep(-1720.0, -1880.0, Z) + 0.0
    m = np.maximum(m, 0)
    wx, wz = nz.warp(X, Z, 1 / 400, 80, s + 160)
    ridges = nz.ridged(wx * 1.4, wz * 0.6, 1 / 110, s + 161, 3, sharpness=3.5)
    pack = 3.0 + ridges * 7.0 + nz.fbm(X, Z, 1 / 200, s + 162, 2) * 1.5
    pack = pack * smoothstep(0, 25, d)
    return lerp(land_h, pack, m * smoothstep(0, 10, d))
