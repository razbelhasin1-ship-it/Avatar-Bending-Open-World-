"""Road and ferry path finding (Dijkstra on a coarse 8-connected grid)."""
from __future__ import annotations

import numpy as np
from scipy import ndimage
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

from . import grid

_OFFS = [(0, 1), (1, 0), (1, 1), (1, -1)]


class GridGraph:
    def __init__(self, n: int):
        self.n = n
        self.cell = grid.cell_size(n)
        idx = np.arange(n * n).reshape(n, n)
        src, dst, length = [], [], []
        for dz, dx in _OFFS:   # dz in {0, 1}; the reverse directions come from the undirected solve
            a = idx[0: n - dz, max(0, -dx): n - max(0, dx)]
            b = idx[dz: n, max(0, dx): n - max(0, -dx)]
            src.append(a.ravel())
            dst.append(b.ravel())
            length.append(np.full(a.size, self.cell * np.hypot(dz, dx)))
        self.src = np.concatenate(src)
        self.dst = np.concatenate(dst)
        self.length = np.concatenate(length)

    def solve(self, weights: np.ndarray, a: int, b: int) -> list[int]:
        ok = np.isfinite(weights)
        g = csr_matrix((weights[ok], (self.src[ok], self.dst[ok])), shape=(self.n * self.n, self.n * self.n))
        dist, pred = dijkstra(g, directed=False, indices=a, return_predecessors=True)
        if not np.isfinite(dist[b]):
            return []
        path = [b]
        while path[-1] != a:
            path.append(int(pred[path[-1]]))
            if path[-1] < 0:
                return []
        return path[::-1]

    def node(self, x: float, z: float) -> int:
        i, j = grid.to_index(x, z, self.n)
        return j * self.n + i

    def coords(self, nodes) -> np.ndarray:
        nodes = np.asarray(nodes)
        j, i = np.divmod(nodes, self.n)
        ax = grid.axis(self.n)
        return np.column_stack([ax[i], ax[j]])


class RoadRouter:
    """Finds natural-looking road paths: gentle grades, no water, avoids city interiors."""

    def __init__(self, h_full: np.ndarray, forbid_full: np.ndarray, penalty_full: np.ndarray, n: int = 512):
        f = h_full.shape[0] // n
        self.g = GridGraph(n)
        self.h = grid.downsample_mean(h_full, f).ravel()
        forbid = grid.downsample_mean(forbid_full.astype(np.float32), f) > 0.35
        self.forbid = forbid.ravel()
        self.penalty = grid.downsample_mean(penalty_full.astype(np.float32), f).ravel()
        self.bonus = np.zeros(n * n, dtype=np.float64)
        rough = ndimage.generic_gradient_magnitude(grid.downsample_mean(h_full, f), ndimage.sobel) / (8 * self.g.cell)
        self.rough = rough.ravel()

    def weights(self) -> np.ndarray:
        g = self.g
        dh = np.abs(self.h[g.dst] - self.h[g.src])
        grade = dh / g.length
        w = g.length * (1.0 + 30.0 * grade ** 2 + 900.0 * np.maximum(grade - 0.14, 0.0) ** 2)
        side = 0.5 * (self.rough[g.src] + self.rough[g.dst])
        w *= 1.0 + 2.5 * np.maximum(side - 0.25, 0.0)
        pen = 0.5 * (self.penalty[g.src] + self.penalty[g.dst])
        w *= 1.0 + 6.0 * pen
        w *= 1.0 - 0.45 * np.minimum(0.5 * (self.bonus[g.src] + self.bonus[g.dst]), 1.0)
        bad = self.forbid[g.src] | self.forbid[g.dst] | (self.h[g.src] < 0.8) | (self.h[g.dst] < 0.8)
        w[bad] = np.inf
        return w

    def route(self, a, b) -> np.ndarray:
        na, nb = self.g.node(*a), self.g.node(*b)
        # endpoints may sit on penalised/forbidden cells (gates): open a small neighbourhood
        saved = {}
        for nd in (na, nb):
            j, i = divmod(nd, self.g.n)
            for dj in range(-2, 3):
                for di in range(-2, 3):
                    k = (j + dj) * self.g.n + (i + di)
                    if 0 <= k < self.forbid.size:
                        saved[k] = (self.forbid[k], self.penalty[k])
                        self.forbid[k] = False
                        self.penalty[k] = 0.0
        path = self.g.solve(self.weights(), na, nb)
        for k, (fb, pn) in saved.items():
            self.forbid[k] = fb
            self.penalty[k] = pn
        if not path:
            return np.array([a, b], dtype=np.float64)
        self.bonus[np.asarray(path)] = 1.0
        pts = self.g.coords(path)
        pts[0] = a
        pts[-1] = b
        return pts


def smooth_path(pts: np.ndarray, cell: float) -> np.ndarray:
    p = grid.simplify_rdp(pts, cell * 0.55)
    p = grid.chaikin(p, 3)
    return p


class FerryRouter:
    def __init__(self, h_full: np.ndarray, n: int = 512):
        f = h_full.shape[0] // n
        self.g = GridGraph(n)
        hc = grid.downsample_mean(h_full, f)
        water = hc < -2.5
        dist_land = ndimage.distance_transform_edt(water) * self.g.cell
        self.water = water.ravel()
        self.near = np.exp(-dist_land.ravel() / 140.0)

    def route(self, a, b) -> np.ndarray:
        g = self.g
        w = g.length * (1.0 + 5.0 * 0.5 * (self.near[g.src] + self.near[g.dst]))
        w[~(self.water[g.src] & self.water[g.dst])] = np.inf
        na = self._nearest_water(a)
        nb = self._nearest_water(b)
        path = g.solve(w, na, nb)
        if not path:
            return np.array([a, b], dtype=np.float64)
        pts = g.coords(path)
        return np.vstack([[a], pts, [b]])

    def _nearest_water(self, p) -> int:
        n = self.g.n
        i, j = grid.to_index(p[0], p[1], n)
        best, bd = j * n + i, 1e18
        for dj in range(-12, 13):
            for di in range(-12, 13):
                jj, ii = j + dj, i + di
                if 0 <= jj < n and 0 <= ii < n and self.water[jj * n + ii]:
                    d = di * di + dj * dj
                    if d < bd:
                        bd, best = d, jj * n + ii
        return best
