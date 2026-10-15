"""Quick-look preview images (hillshade + hypsometric tint) for iterating on geography."""
from __future__ import annotations

import numpy as np
from PIL import Image


def hillshade(h: np.ndarray, cell: float, azimuth: float = 315.0, altitude: float = 40.0, z: float = 1.0) -> np.ndarray:
    gy, gx = np.gradient(h.astype(np.float64) * z, cell)
    slope = np.pi / 2 - np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    az = np.radians(360 - azimuth + 90)
    alt = np.radians(altitude)
    shaded = np.sin(alt) * np.sin(slope) + np.cos(alt) * np.cos(slope) * np.cos(az - aspect)
    return np.clip(shaded, 0, 1)


def hypso(h: np.ndarray) -> np.ndarray:
    stops = [
        (-200, (18, 40, 78)), (-60, (30, 70, 120)), (-10, (60, 120, 165)), (-0.01, (110, 170, 200)),
        (0.0, (205, 195, 150)), (8, (120, 150, 80)), (60, (95, 135, 70)), (180, (140, 140, 90)),
        (350, (150, 120, 90)), (600, (165, 160, 155)), (850, (235, 235, 240)), (1100, (255, 255, 255)),
    ]
    hs = np.array([s[0] for s in stops], dtype=np.float64)
    cols = np.array([s[1] for s in stops], dtype=np.float64)
    out = np.zeros(h.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(h, hs, cols[:, c])
    return out


def save_preview(h: np.ndarray, cell: float, path: str, size: int = 1024) -> None:
    rgb = hypso(h)
    sh = hillshade(h, cell, z=1.5)
    land = (h > 0)[..., None]
    rgb = np.where(land, rgb * (0.35 + 0.85 * sh[..., None]), rgb * (0.8 + 0.2 * sh[..., None]))
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
    if img.size[0] != size:
        img = img.resize((size, size), Image.LANCZOS)
    img.save(path)


def save_gray(a: np.ndarray, path: str, lo=None, hi=None, size: int = 1024) -> None:
    lo = float(np.min(a)) if lo is None else lo
    hi = float(np.max(a)) if hi is None else hi
    g = np.clip((a - lo) / max(1e-6, hi - lo), 0, 1) * 255
    img = Image.fromarray(g.astype(np.uint8))
    if img.size[0] != size:
        img = img.resize((size, size), Image.LANCZOS)
    img.save(path)


def save_labels(a: np.ndarray, palette: dict, path: str, size: int = 1024) -> None:
    out = np.zeros(a.shape + (3,), dtype=np.uint8)
    for k, col in palette.items():
        out[a == k] = col
    img = Image.fromarray(out)
    if img.size[0] != size:
        img = img.resize((size, size), Image.NEAREST)
    img.save(path)
