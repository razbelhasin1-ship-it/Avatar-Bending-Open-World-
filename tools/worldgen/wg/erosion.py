"""Hydraulic (droplet) and thermal erosion, vectorised with numpy.

The droplet model follows Hans Theobald Beyer's "Implementation of a method for
hydraulic erosion" (2015): each droplet carries water and sediment downhill with
inertia, erodes with a radial brush while under capacity and deposits on its
bilinear footprint when over capacity. Thousands of droplets are advanced in
lock-step; their height changes are accumulated with np.bincount each step, which
is deterministic (sequential summation) for a given seed.

Heights are processed in units of "cells" (metres / cell size) so the classic
dimensionless parameters behave the same at any resolution.
"""
from __future__ import annotations

import numpy as np


class DropletParams:
    inertia = 0.08
    capacity = 4.0
    min_capacity = 0.005
    deposit = 0.3
    erode = 0.25
    evaporate = 0.02
    gravity = 4.0
    max_steps = 52
    radius = 3
    max_erode_per_step = 0.12   # cells, per droplet
    max_cell_change = 0.04      # cells, per step over all droplets (keeps parallel droplets from digging pits)


def _brush(radius: int):
    offs = []
    w = []
    for dz in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            d = np.hypot(dx, dz)
            if d < radius:
                offs.append((dz, dx))
                w.append(radius - d)
    w = np.asarray(w, dtype=np.float64)
    return np.asarray(offs, dtype=np.int64), w / w.sum()


def droplet_erosion(h_m: np.ndarray, cell: float, erodibility: np.ndarray, droplets: int, seed: int,
                    params: DropletParams | None = None, batch: int = 25_000,
                    flux_out: np.ndarray | None = None) -> np.ndarray:
    """Returns the eroded height field (metres). Optionally accumulates water flux into flux_out."""
    p = params or DropletParams()
    rng = np.random.default_rng(seed)
    hgt, wid = h_m.shape
    h = (h_m.astype(np.float64) / cell).ravel().copy()
    er = erodibility.astype(np.float64).ravel()
    offs, bw = _brush(p.radius)
    k = len(bw)
    size = hgt * wid
    remaining = droplets
    while remaining > 0:
        n = min(batch, remaining)
        remaining -= n
        # spawn proportional to erodibility (rejection sampling)
        px = rng.uniform(1, wid - 2, n * 3)
        pz = rng.uniform(1, hgt - 2, n * 3)
        keep = er[pz.astype(np.int64) * wid + px.astype(np.int64)] > rng.uniform(0.05, 1.0, n * 3)
        px = px[keep][:n]
        pz = pz[keep][:n]
        n = len(px)
        if n == 0:
            continue
        dx = np.zeros(n)
        dz = np.zeros(n)
        speed = np.ones(n)
        water = np.ones(n)
        sed = np.zeros(n)
        alive = np.ones(n, dtype=bool)
        for _ in range(p.max_steps):
            ix = px.astype(np.int64)
            iz = pz.astype(np.int64)
            fx = px - ix
            fz = pz - iz
            i00 = iz * wid + ix
            h00 = h[i00]
            h10 = h[i00 + 1]
            h01 = h[i00 + wid]
            h11 = h[i00 + wid + 1]
            gx = (h10 - h00) * (1 - fz) + (h11 - h01) * fz
            gz = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
            hcur = h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz
            dx = dx * p.inertia - gx * (1 - p.inertia)
            dz = dz * p.inertia - gz * (1 - p.inertia)
            ln = np.hypot(dx, dz)
            stuck = ln < 1e-9
            if stuck.any():
                a = rng.uniform(0, 2 * np.pi, int(stuck.sum()))
                dx[stuck] = np.cos(a)
                dz[stuck] = np.sin(a)
                ln[stuck] = 1.0
            dx /= ln
            dz /= ln
            npx = px + dx
            npz = pz + dz
            out = (npx < 1) | (npx >= wid - 2) | (npz < 1) | (npz >= hgt - 2)
            alive &= ~out
            npx = np.clip(npx, 1, wid - 2.001)
            npz = np.clip(npz, 1, hgt - 2.001)
            jx = npx.astype(np.int64)
            jz = npz.astype(np.int64)
            gfx = npx - jx
            gfz = npz - jz
            j00 = jz * wid + jx
            hnew = (h[j00] * (1 - gfx) * (1 - gfz) + h[j00 + 1] * gfx * (1 - gfz)
                    + h[j00 + wid] * (1 - gfx) * gfz + h[j00 + wid + 1] * gfx * gfz)
            dh = hnew - hcur
            cap = np.maximum(-dh * speed * water * p.capacity, p.min_capacity)
            depositing = (sed > cap) | (dh > 0)
            dep = np.where(dh > 0, np.minimum(dh, sed), (sed - cap) * p.deposit)
            dep = np.where(depositing & alive, np.maximum(dep, 0), 0.0)
            ero = np.where(~depositing & alive, np.minimum((cap - sed) * p.erode, -dh), 0.0)
            ero = np.clip(ero, 0, p.max_erode_per_step) * er[i00]
            sed += ero - dep
            # deposit on the bilinear footprint of the old position
            dep_idx = np.concatenate([i00, i00 + 1, i00 + wid, i00 + wid + 1])
            dep_w = np.concatenate([dep * (1 - fx) * (1 - fz), dep * fx * (1 - fz), dep * (1 - fx) * fz, dep * fx * fz])
            # erode with the radial brush around the old cell
            bz = np.clip(iz[:, None] + offs[None, :, 0], 0, hgt - 1)
            bx = np.clip(ix[:, None] + offs[None, :, 1], 0, wid - 1)
            ero_idx = (bz * wid + bx).ravel()
            ero_w = (ero[:, None] * bw[None, :]).ravel()
            delta = np.bincount(dep_idx, weights=dep_w, minlength=size)
            delta -= np.bincount(ero_idx, weights=ero_w, minlength=size)
            np.clip(delta, -p.max_cell_change, p.max_cell_change * 2.0, out=delta)
            h += delta
            if flux_out is not None:
                flux_out.ravel()[:] += np.bincount(i00[alive], weights=water[alive], minlength=size)
            speed = np.sqrt(np.maximum(speed * speed - dh * p.gravity, 0.0))
            water *= 1 - p.evaporate
            px, pz = npx, npz
            if not alive.any():
                break
    return (h.reshape(hgt, wid) * cell).astype(np.float32)


def thermal_erosion(h_m: np.ndarray, cell: float, talus_deg: float, iterations: int, rate: float = 0.25,
                    mask: np.ndarray | None = None) -> np.ndarray:
    """Moves material down slopes steeper than the talus angle (4-neighbour, vectorised)."""
    h = h_m.astype(np.float64).copy()
    talus = np.tan(np.radians(talus_deg)) * cell
    m = 1.0 if mask is None else mask.astype(np.float64)
    for _ in range(iterations):
        delta = np.zeros_like(h)
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            nb = np.roll(h, shift, axis=axis)
            diff = h - nb
            move = np.where(diff > talus, (diff - talus) * rate * 0.5, 0.0) * m
            delta -= move
            delta += np.roll(move, -shift, axis=axis)
        h += delta
    return h.astype(np.float32)
