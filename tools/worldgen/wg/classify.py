"""Regions, biomes, splat weights and ground hint maps from the final terrain."""
from __future__ import annotations

import numpy as np
from scipy import ndimage

from . import grid, layout
from . import noise as nz
from .grid import smoothstep
from .terrain import polygon_mask, T_OCEAN, T_WATER, T_EARTH, T_FIRE, T_AIR, T_WILDS

BIOMES = ["OCEAN", "BEACH", "SNOW", "ICE", "TUNDRA", "GRASSLAND", "FOREST", "FARMLAND", "ROCK", "MOUNTAIN",
          "VOLCANIC", "ASH", "TEMPLE", "CITY"]
B = {name: i for i, name in enumerate(BIOMES)}


def region_map(h1024: np.ndarray, territory1024: np.ndarray, lake_mask1024: np.ndarray) -> np.ndarray:
    """Final region ids (index into layout.REGION_IDS) at 1024^2: land keeps its territory,
    water within 260 m of a nation's coast belongs to it, the rest is open sea."""
    land = (h1024 > 0.0) | lake_mask1024
    terr = territory1024.copy()
    terr[~land] = T_OCEAN
    # land cells created after territory assignment (reclaimed quays...) take the nearest code
    missing = land & (terr == T_OCEAN)
    known = terr != T_OCEAN
    idx = ndimage.distance_transform_edt(~known, return_distances=False, return_indices=True)
    nearest = terr[idx[0], idx[1]]
    terr[missing] = nearest[missing]
    dist = ndimage.distance_transform_edt(~land) * grid.cell_size(h1024.shape[0])
    out = np.where(land, terr, np.where(dist < 260.0, nearest, T_OCEAN))
    return out.astype(np.uint8)


def noisy_polygon_mask(poly, n, X, Z, amp: float, seed: int) -> np.ndarray:
    """Polygon mask with an organic, noise-displaced outline (amp in metres)."""
    m = polygon_mask(poly, n)
    cell = grid.cell_size(n)
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    i0, j0 = grid.to_index(min(xs) - amp * 1.5, min(zs) - amp * 1.5, n)
    i1, j1 = grid.to_index(max(xs) + amp * 1.5, max(zs) + amp * 1.5, n)
    sl = (slice(j0, j1 + 1), slice(i0, i1 + 1))
    sub = m[sl]
    sdf = (ndimage.distance_transform_edt(sub) - ndimage.distance_transform_edt(~sub)) * cell
    out = np.zeros_like(m)
    out[sl] = (sdf + nz.fbm(X[sl], Z[sl], 1 / 220, seed, 4) * amp) > 0
    return out


class Classifier:
    def __init__(self, h4096: np.ndarray, masks: dict, territory1024: np.ndarray, flux1024: np.ndarray,
                 lakes: list, seed: int, n: int = 2048):
        self.n = n
        self.seed = seed
        f = h4096.shape[0] // n
        self.h = grid.downsample_mean(h4096, f).astype(np.float32)
        self.cell = grid.cell_size(n)
        gz, gx = np.gradient(self.h.astype(np.float64), self.cell)
        self.slope = np.degrees(np.arctan(np.hypot(gx, gz))).astype(np.float32)
        self.masks = {k: grid.downsample_mean(v.astype(np.float32), f) for k, v in masks.items()}
        self.terr = np.kron(territory1024, np.ones((n // 1024, n // 1024), dtype=np.uint8)) if n >= 1024 \
            else territory1024[:: 1024 // n, :: 1024 // n]
        self.X, self.Z = grid.mesh(n)
        flux = np.log1p(np.maximum(flux1024, 0.0))
        flux = flux / max(np.percentile(flux, 99.5), 1e-6)
        self.flux = np.clip(grid.resample(flux.astype(np.float32), n, order=1), 0, 1)
        self.lakes = lakes

    def lake_masks(self):
        water = np.zeros((self.n, self.n), dtype=bool)
        frozen = np.zeros((self.n, self.n), dtype=bool)
        for lk in self.lakes:
            poly = [(p[0], p[1]) for p in lk["polygon"]]
            m = polygon_mask(poly, self.n) & (self.h < lk["level"] + 0.3)
            if lk["frozen"]:
                frozen |= polygon_mask(poly, self.n)
            else:
                water |= m
        return water, frozen

    def classify(self):
        n, h, sl, terr, s = self.n, self.h, self.slope, self.terr, self.seed
        X, Z = self.X, self.Z
        lake_water, lake_frozen = self.lake_masks()
        sea = (h <= 0.0) & ~lake_frozen
        land = ~sea & ~lake_water
        coast = ndimage.distance_transform_edt(land) * self.cell
        n1 = nz.fbm(X, Z, 1 / 420, s + 701, 4)
        n2 = nz.fbm(X, Z, 1 / 140, s + 702, 3)
        wet = np.clip(self.flux * 1.3 + smoothstep(120, 0, ndimage.distance_transform_edt(~lake_water) * self.cell) * 0.6, 0, 1)
        biome = np.full((n, n), B["GRASSLAND"], dtype=np.uint8)
        arctic = (terr == T_WATER) | ((terr == T_WILDS) & (Z < -1600))
        earth = terr == T_EARTH
        fire = terr == T_FIRE
        air = terr == T_AIR
        wild = (terr == T_WILDS) & ~arctic

        # ---------------- Arctic ----------------
        biome[arctic] = B["SNOW"]
        ice = np.zeros((n, n), dtype=bool)
        for pts, width in layout.GLACIERS:
            dist, _, _ = grid.polyline_distance(X, Z, pts)
            ice |= dist < width * (0.32 + 0.08 * n2)
        for poly in layout.ICE_SHELVES:
            ice |= polygon_mask(poly, n) & (h < 30) & (coast < 520)
        strait = polygon_mask(layout.FROZEN_STRAIT, n) & (terr == T_WILDS)
        ice |= strait & (n2 > -0.25)
        ice |= arctic & (h < 5.0) & (coast < 40)
        biome[arctic & ice] = B["ICE"]
        biome[strait & ~ice] = B["TUNDRA"]
        biome[arctic & (sl > 36) & (n1 > -0.4)] = B["ROCK"]
        biome[arctic & (h > 380) & (sl > 26)] = B["MOUNTAIN"]

        # ---------------- Earth Kingdom ----------------
        n3 = nz.fbm(*nz.warp(X, Z, 1 / 1200, 300, s + 704), 1 / 1100, s + 703, 4)
        tundra = earth & (Z < -1250 + n3 * 260 + n2 * 40)
        biome[earth] = B["GRASSLAND"]
        forest_bias = smoothstep(700, 1500, Z) * 0.45 + smoothstep(-900, -300, Z) * 0.1
        moist = n3 * 0.75 + n1 * 0.2 + wet * 0.55 + forest_bias - 0.12
        for cx, cz, rad in layout.PLATEAUS:   # dry rocky plateaus
            moist -= smoothstep(rad, rad * 0.5, np.hypot(X - cx, Z - cz)) * 0.8
        biome[earth & (moist > 0.28) & (sl < 30)] = B["FOREST"]
        biome[tundra] = B["TUNDRA"]
        biome[tundra & (h > 160)] = B["SNOW"]
        farm = np.zeros((n, n), dtype=bool)
        for k, poly in enumerate(layout.FARMLAND_ZONES):
            farm |= noisy_polygon_mask(poly, n, X, Z, 90.0, s + 720 + k)
        farm = (farm & (sl < 7.5) & (h > 2.0)) | (self.masks["farmland"] > 0.5)
        biome[earth & farm] = B["FARMLAND"]
        biome[earth & (sl > 34)] = B["ROCK"]
        for cx, cz, rad in layout.PLATEAUS:
            plat = np.hypot(X - cx, Z - cz) < rad * 0.95
            biome[earth & plat & (sl > 22)] = B["ROCK"]
        biome[earth & (h > 380) & (sl > 18)] = B["MOUNTAIN"]
        biome[earth & (h > 560 + n1 * 50) & (sl < 42)] = B["SNOW"]

        # ---------------- Fire Nation ----------------
        biome[fire] = B["FOREST"]
        biome[fire & (moist < -0.05)] = B["GRASSLAND"]
        lava = np.zeros((n, n), dtype=bool)
        for k, poly in enumerate(layout.LAVA_FIELDS):
            lava |= noisy_polygon_mask(poly, n, X, Z, 160.0, s + 730 + k)
        vx, vz = -1650, 3480
        rv = np.hypot(X - vx, Z - vz)
        lava |= fire & (rv < 420) & (h > 90 + n1 * 30)
        ashp = np.zeros((n, n), dtype=bool)
        for k, poly in enumerate(layout.ASH_PLAINS):
            ashp |= noisy_polygon_mask(poly, n, X, Z, 120.0, s + 740 + k)
        cx, cz = layout.FIRE_CAPITAL["center"]
        rc = np.hypot(X - cx, Z - cz)
        ashp |= fire & (rc > layout.FIRE_CAPITAL["floor_radius"] + 5) & (rc < 760) & (h > 170 + n1 * 30)
        ashp |= fire & (rv < 260) & (h > 230)
        biome[fire & ashp] = B["ASH"]
        biome[fire & lava] = B["VOLCANIC"]
        biome[fire & (sl > 38) & ~lava] = B["ROCK"]
        tea = noisy_polygon_mask(layout.FARMLAND_ZONES[3], n, X, Z, 70.0, s + 723) & (sl < 14)
        biome[fire & tea] = B["FARMLAND"]

        # ---------------- Southern Air Temple ----------------
        biome[air] = B["GRASSLAND"]
        biome[air & (h < 420) & (moist > 0.05) & (sl < 32)] = B["FOREST"]
        biome[air & (h > 330) & (sl > 22)] = B["MOUNTAIN"]
        biome[air & (sl > 40)] = B["ROCK"]
        biome[air & (h > 840 + n1 * 50) & (sl < 46)] = B["SNOW"]
        biome[air & (h > 720 + n1 * 60) & (sl < 30)] = B["SNOW"]

        # ---------------- Wild islands ----------------
        biome[wild] = B["GRASSLAND"]
        biome[wild & (sl > 34)] = B["ROCK"]

        # ---------------- Coasts, settlements, water ----------------
        beach = land & (coast < 34 + n2 * 12) & (h < 3.2) & (sl < 16) & ~arctic
        biome[beach] = B["BEACH"]
        biome[(self.masks["settlement"] > 0.55)] = B["CITY"]
        biome[(self.masks["temple"] > 0.5)] = B["TEMPLE"]
        biome[(self.masks["grass_patch"] > 0.5)] = B["GRASSLAND"]
        biome[lake_frozen & (h > 0)] = B["ICE"]
        biome[sea | lake_water] = B["OCEAN"]
        self.biome = biome
        self.coast = coast
        self.wet = wet
        self.lake_water = lake_water
        self.sea = sea
        return biome

    def splat(self) -> np.ndarray:
        """RGBA weights: R snow/ice, G rock/cliff, B lush grass/forest floor, A sand/ash.
        The remainder (1 - sum) is bare soil / dry grass."""
        b, sl, h = self.biome, self.slope, self.h
        n2 = nz.fbm(self.X, self.Z, 1 / 90, self.seed + 711, 3) * 0.5 + 0.5
        snow = np.zeros_like(h)
        rock = smoothstep(26.0, 44.0, sl)
        lush = np.zeros_like(h)
        sand = np.zeros_like(h)
        for name, (sn, rk, lu, sa) in {
            "SNOW": (1.0, 0.0, 0.0, 0.0), "ICE": (0.9, 0.0, 0.0, 0.0), "TUNDRA": (0.35, 0.05, 0.15, 0.0),
            "GRASSLAND": (0.0, 0.0, 0.62, 0.0), "FOREST": (0.0, 0.0, 0.92, 0.0), "FARMLAND": (0.0, 0.0, 0.45, 0.0),
            "ROCK": (0.0, 0.85, 0.0, 0.0), "MOUNTAIN": (0.12, 0.6, 0.0, 0.0), "VOLCANIC": (0.0, 0.7, 0.0, 0.25),
            "ASH": (0.0, 0.15, 0.0, 0.85), "BEACH": (0.0, 0.0, 0.0, 1.0), "TEMPLE": (0.0, 0.35, 0.25, 0.0),
            "CITY": (0.0, 0.3, 0.1, 0.1), "OCEAN": (0.0, 0.2, 0.0, 0.6),
        }.items():
            m = b == B[name]
            snow[m] = np.maximum(snow[m], sn)
            rock[m] = np.maximum(rock[m], rk)
            lush[m] = lu
            sand[m] = sa
        # snow cover on high ground (regional snowlines), none on cliffs
        terr = self.terr
        arctic = (terr == T_WATER) | ((terr == T_WILDS) & (self.Z < -1600))
        snowline = np.full(h.shape, 1e5, dtype=np.float32)
        snowline[arctic] = -60.0
        snowline[terr == T_EARTH] = 520.0
        snowline[terr == T_AIR] = 640.0
        snowline += nz.fbm(self.X, self.Z, 1 / 300, self.seed + 712, 3) * 50.0
        cover = smoothstep(snowline - 60.0, snowline + 140.0, h) * (1.0 - 0.75 * smoothstep(60.0, 82.0, sl))
        cap = smoothstep(snowline + 120.0, snowline + 260.0, h) * 0.9
        cover = np.maximum(cover, cap)        # summit snow caps cling even to steep faces
        cover *= (b != B["CITY"]) & (b != B["TEMPLE"]) & (b != B["OCEAN"])
        snow = np.maximum(snow, cover * 0.95)
        rock = rock * (1.0 - 0.85 * cover)    # snow buries the rock it covers
        lush[arctic & (b != B["GRASSLAND"])] *= 0.1
        # variation and transitions
        lush *= 0.75 + 0.5 * n2
        lush += self.wet * 0.25 * (lush > 0)
        snow *= 1.0 - 0.6 * smoothstep(32.0, 50.0, sl)
        tundra = b == B["TUNDRA"]
        snow[tundra] *= smoothstep(0.3, 0.7, n2[tundra]) * 1.6
        w = np.stack([snow, rock, lush, sand], axis=-1)
        w = ndimage.gaussian_filter(w, sigma=(1.2, 1.2, 0))
        total = w.sum(axis=-1, keepdims=True)
        w = np.where(total > 1.0, w / np.maximum(total, 1e-6), w)
        return np.clip(w, 0, 1)

    def ground(self, roads_paved4096: np.ndarray) -> np.ndarray:
        """RGBA hints: R paved road, G settlement paving, B farmland, A wetness."""
        f = roads_paved4096.shape[0] // self.n
        paved = grid.downsample_mean(roads_paved4096, f)
        settle = self.masks["settlement"] * (self.biome != B["OCEAN"])
        farm = (self.biome == B["FARMLAND"]).astype(np.float32)
        farm = ndimage.gaussian_filter(farm, 0.8)
        wet = np.clip(self.wet, 0, 1)
        return np.clip(np.stack([paved, settle, farm, wet], axis=-1), 0, 1)
