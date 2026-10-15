"""Deterministic vectorised 2D gradient noise.

Uses an integer hash (no permutation table, so no visible tiling at any
frequency). All functions take world coordinates in metres plus a frequency in
cycles per metre and return float32 arrays roughly in [-1, 1].
"""
from __future__ import annotations

import numpy as np

_GRAD = np.array(
    [[np.cos(a), np.sin(a)] for a in np.linspace(0.0, 2.0 * np.pi, 16, endpoint=False)],
    dtype=np.float32,
)


def _hash(ix: np.ndarray, iz: np.ndarray, seed: int) -> np.ndarray:
    h = ix.astype(np.uint32) * np.uint32(0x8DA6B343)
    h ^= iz.astype(np.uint32) * np.uint32(0xD8163841)
    h ^= np.uint32((seed * 0x9E3779B1) & 0xFFFFFFFF)
    h ^= h >> np.uint32(13)
    h *= np.uint32(0x5BD1E995)
    h ^= h >> np.uint32(15)
    return h


def perlin(x: np.ndarray, z: np.ndarray, freq: float, seed: int) -> np.ndarray:
    """Single octave of gradient noise (~[-1, 1])."""
    with np.errstate(over="ignore"):
        fx = np.asarray(x, dtype=np.float64) * freq
        fz = np.asarray(z, dtype=np.float64) * freq
        x0 = np.floor(fx)
        z0 = np.floor(fz)
        tx = (fx - x0).astype(np.float32)
        tz = (fz - z0).astype(np.float32)
        ix = x0.astype(np.int64)
        iz = z0.astype(np.int64)
        g00 = _GRAD[_hash(ix, iz, seed) & np.uint32(15)]
        g10 = _GRAD[_hash(ix + 1, iz, seed) & np.uint32(15)]
        g01 = _GRAD[_hash(ix, iz + 1, seed) & np.uint32(15)]
        g11 = _GRAD[_hash(ix + 1, iz + 1, seed) & np.uint32(15)]
    d00 = g00[..., 0] * tx + g00[..., 1] * tz
    d10 = g10[..., 0] * (tx - 1.0) + g10[..., 1] * tz
    d01 = g01[..., 0] * tx + g01[..., 1] * (tz - 1.0)
    d11 = g11[..., 0] * (tx - 1.0) + g11[..., 1] * (tz - 1.0)
    u = tx * tx * tx * (tx * (tx * 6.0 - 15.0) + 10.0)
    v = tz * tz * tz * (tz * (tz * 6.0 - 15.0) + 10.0)
    a = d00 + (d10 - d00) * u
    b = d01 + (d11 - d01) * u
    return ((a + (b - a) * v) * 1.4142).astype(np.float32)


def fbm(x, z, freq: float, seed: int, octaves: int = 5, lacunarity: float = 2.0, gain: float = 0.5) -> np.ndarray:
    """Fractal Brownian motion, normalised to ~[-1, 1]."""
    total = np.zeros(np.shape(x), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    f = freq
    for o in range(octaves):
        total += perlin(x, z, f, seed + o * 1013) * amp
        norm += amp
        amp *= gain
        f *= lacunarity
    return total / norm


def ridged(x, z, freq: float, seed: int, octaves: int = 6, lacunarity: float = 2.0, gain: float = 0.5,
           sharpness: float = 2.0) -> np.ndarray:
    """Ridged multifractal in [0, 1]: sharp crests, each octave weighted by the previous one."""
    total = np.zeros(np.shape(x), dtype=np.float32)
    weight = np.ones(np.shape(x), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    f = freq
    for o in range(octaves):
        n = 1.0 - np.abs(perlin(x, z, f, seed + o * 7919))
        n = n ** sharpness
        n *= weight
        weight = np.clip(n * 1.6, 0.0, 1.0)
        total += n * amp
        norm += amp
        amp *= gain
        f *= lacunarity
    return total / norm


def warp(x, z, freq: float, amount: float, seed: int, octaves: int = 3):
    """Domain warp: returns displaced coordinates (x', z')."""
    wx = fbm(x, z, freq, seed + 31, octaves)
    wz = fbm(x, z, freq, seed + 57, octaves)
    return x + wx * amount, z + wz * amount


def terrace(h: np.ndarray, step: float, sharp: float = 0.75) -> np.ndarray:
    """Soft terracing: flat treads with steep risers (sharp in 0..1)."""
    k = h / step
    base = np.floor(k)
    f = k - base
    # Smooth riser: most of the step stays flat, rise compressed into (1 - sharp)
    s = np.clip((f - sharp) / max(1e-4, 1.0 - sharp), 0.0, 1.0)
    s = s * s * (3.0 - 2.0 * s)
    return (base + s) * step
