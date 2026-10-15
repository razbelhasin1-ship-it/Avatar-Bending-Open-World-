"""World <-> grid coordinates.

The world is a square of WORLD_SIZE metres centred on the origin. Every raster
in the generator uses the *texel-centre* convention: texel (i, j) of an N x N
grid covers [x0 + i*c, x0 + (i+1)*c) and its sample lives at its centre
x = WORLD_MIN + (i + 0.5) * c, with c = WORLD_SIZE / N. Column i grows east
(+X), row j grows south (+Z), so row 0 is the northern edge (-Z).
"""
from __future__ import annotations

import numpy as np
from scipy import ndimage

WORLD_SIZE = 8192.0
WORLD_MIN = -WORLD_SIZE / 2.0


def cell_size(n: int) -> float:
    return WORLD_SIZE / n


def axis(n: int) -> np.ndarray:
    """Texel-centre world coordinates along one axis (float64)."""
    c = cell_size(n)
    return WORLD_MIN + (np.arange(n, dtype=np.float64) + 0.5) * c


def mesh(n: int) -> tuple[np.ndarray, np.ndarray]:
    """(X, Z) float64 coordinate grids of shape (n, n) indexed [row=z, col=x]."""
    a = axis(n)
    return np.meshgrid(a, a, indexing="xy")


def to_pixel(x: float, z: float, n: int) -> tuple[float, float]:
    """World position -> continuous pixel coordinates (texel centres at .0)."""
    c = cell_size(n)
    return (x - WORLD_MIN) / c - 0.5, (z - WORLD_MIN) / c - 0.5


def to_index(x: float, z: float, n: int) -> tuple[int, int]:
    """World position -> nearest texel (col, row), clamped."""
    px, pz = to_pixel(x, z, n)
    return int(np.clip(round(px), 0, n - 1)), int(np.clip(round(pz), 0, n - 1))


def window(n: int, cx: float, cz: float, radius: float):
    """Slice window of texels whose centres lie within the square |x-cx|,|z-cz| <= radius.

    Returns (rows_slice, cols_slice, X, Z) with X/Z the world coordinates of the
    window texels (float64), or None when the window is empty.
    """
    c = cell_size(n)
    i0 = int(np.floor((cx - radius - WORLD_MIN) / c - 0.5))
    i1 = int(np.ceil((cx + radius - WORLD_MIN) / c - 0.5)) + 1
    j0 = int(np.floor((cz - radius - WORLD_MIN) / c - 0.5))
    j1 = int(np.ceil((cz + radius - WORLD_MIN) / c - 0.5)) + 1
    i0, j0 = max(i0, 0), max(j0, 0)
    i1, j1 = min(i1, n), min(j1, n)
    if i1 <= i0 or j1 <= j0:
        return None
    xs = WORLD_MIN + (np.arange(i0, i1) + 0.5) * c
    zs = WORLD_MIN + (np.arange(j0, j1) + 0.5) * c
    X, Z = np.meshgrid(xs, zs, indexing="xy")
    return slice(j0, j1), slice(i0, i1), X, Z


def resample(a: np.ndarray, n: int, order: int = 3) -> np.ndarray:
    """Resamples a square texel-centre raster to n x n (keeps the texel-centre alignment)."""
    m = a.shape[0]
    if m == n:
        return a.copy()
    # Texel centre i of the output maps to continuous input coordinate:
    #   (i + 0.5) * m / n - 0.5
    src = (np.arange(n, dtype=np.float64) + 0.5) * (m / n) - 0.5
    zz, xx = np.meshgrid(src, src, indexing="ij")
    out = ndimage.map_coordinates(a.astype(np.float32), [zz, xx], order=order, mode="nearest", prefilter=order > 1)
    return out.astype(a.dtype if a.dtype.kind == "f" else np.float32)


def downsample_mean(a: np.ndarray, factor: int) -> np.ndarray:
    n = a.shape[0] // factor
    return a[: n * factor, : n * factor].reshape(n, factor, n, factor).mean(axis=(1, 3))


def sample_bilinear(a: np.ndarray, x, z) -> np.ndarray:
    """Bilinear sample of raster `a` at world positions (arrays), clamped at the edges."""
    n = a.shape[0]
    px, pz = to_pixel(np.asarray(x, dtype=np.float64), np.asarray(z, dtype=np.float64), n)
    px = np.clip(px, 0, n - 1)
    pz = np.clip(pz, 0, n - 1)
    i0 = np.floor(px).astype(np.int64)
    j0 = np.floor(pz).astype(np.int64)
    i1 = np.minimum(i0 + 1, n - 1)
    j1 = np.minimum(j0 + 1, n - 1)
    fx = px - i0
    fz = pz - j0
    a00 = a[j0, i0]
    a10 = a[j0, i1]
    a01 = a[j1, i0]
    a11 = a[j1, i1]
    top = a00 + (a10 - a00) * fx
    bot = a01 + (a11 - a01) * fx
    return top + (bot - top) * fz


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def smootherstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def lerp(a, b, t):
    return a + (b - a) * t


def polyline_distance(X: np.ndarray, Z: np.ndarray, pts) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Distance from each (X,Z) to a polyline.

    Returns (dist, seg_index, t) where t is the parameter along the closest
    segment (0..1). Works on arbitrary shaped arrays.
    """
    pts = np.asarray(pts, dtype=np.float64)
    best = np.full(X.shape, np.inf)
    seg = np.zeros(X.shape, dtype=np.int32)
    tt = np.zeros(X.shape)
    for k in range(len(pts) - 1):
        ax, az = pts[k]
        bx, bz = pts[k + 1]
        dx, dz = bx - ax, bz - az
        ll = dx * dx + dz * dz
        if ll < 1e-9:
            continue
        t = np.clip(((X - ax) * dx + (Z - az) * dz) / ll, 0.0, 1.0)
        px = ax + t * dx
        pz = az + t * dz
        d = np.hypot(X - px, Z - pz)
        m = d < best
        best = np.where(m, d, best)
        seg = np.where(m, k, seg)
        tt = np.where(m, t, tt)
    return best, seg, tt


def polyline_lengths(pts) -> np.ndarray:
    pts = np.asarray(pts, dtype=np.float64)
    seg = np.hypot(np.diff(pts[:, 0]), np.diff(pts[:, 1]))
    return np.concatenate([[0.0], np.cumsum(seg)])


def resample_polyline(pts, spacing: float) -> np.ndarray:
    """Resamples a polyline to roughly uniform spacing (keeps end points)."""
    pts = np.asarray(pts, dtype=np.float64)
    s = polyline_lengths(pts)
    total = s[-1]
    if total < 1e-6:
        return pts.copy()
    n = max(2, int(np.ceil(total / spacing)) + 1)
    t = np.linspace(0.0, total, n)
    x = np.interp(t, s, pts[:, 0])
    z = np.interp(t, s, pts[:, 1])
    return np.stack([x, z], axis=1)


def chaikin(pts, iterations: int = 2) -> np.ndarray:
    """Chaikin corner cutting (keeps end points)."""
    p = np.asarray(pts, dtype=np.float64)
    for _ in range(iterations):
        if len(p) < 3:
            return p
        q = 0.75 * p[:-1] + 0.25 * p[1:]
        r = 0.25 * p[:-1] + 0.75 * p[1:]
        mid = np.empty((2 * (len(p) - 1), 2))
        mid[0::2] = q
        mid[1::2] = r
        p = np.vstack([p[:1], mid[1:-1], p[-1:]])
    return p


def simplify_rdp(pts, eps: float) -> np.ndarray:
    """Ramer-Douglas-Peucker polyline simplification."""
    pts = np.asarray(pts, dtype=np.float64)
    if len(pts) < 3:
        return pts
    keep = np.zeros(len(pts), dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        ax, az = pts[a]
        bx, bz = pts[b]
        dx, dz = bx - ax, bz - az
        ll = np.hypot(dx, dz)
        seg = pts[a + 1 : b]
        if ll < 1e-9:
            d = np.hypot(seg[:, 0] - ax, seg[:, 1] - az)
        else:
            d = np.abs(dx * (seg[:, 1] - az) - dz * (seg[:, 0] - ax)) / ll
        k = int(np.argmax(d))
        if d[k] > eps:
            m = a + 1 + k
            keep[m] = True
            stack.append((a, m))
            stack.append((m, b))
    return pts[keep]
