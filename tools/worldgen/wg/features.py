"""Villages, lakes, waterfalls, arches, ports, POIs, spawns and arrival cameras."""
from __future__ import annotations

import math

import numpy as np
from scipy import ndimage

from . import grid, layout, pois
from .cities import _p3, _r2
from .grid import smoothstep
from .shapes import Field, flatten_pad, carve_lake


def build_villages(f: Field) -> tuple[list, dict]:
    recs = []
    anchors = {}
    for v in layout.VILLAGES:
        cx, cz = v["center"]
        terr = v.get("terraces") or None
        hgt = flatten_pad(f, cx, cz, v["radius"], v.get("height"), blend=60.0, paved=0.7, terraces=terr)
        rec = {"id": v["id"], "name": v["name"], "region": v["region"], "kind": v["kind"],
               "center": _p3(f, cx, cz), "radius": v["radius"], "pad_height": _r2(hgt if hgt is not None else 0.0)}
        if terr:
            rec["terraces"] = [{"radius": r, "height": h} for r, h in terr]
        recs.append(rec)
        anchors[f"village:{v['id']}"] = (cx, cz)
    return recs, anchors


def build_lakes(f: Field) -> list:
    recs = []
    for k, (lid, name, cx, cz, rad, level, depth, frozen) in enumerate(layout.LAKES):
        info = carve_lake(f, lid, cx, cz, rad, level, depth, frozen, f.seed + 900 + k)
        recs.append({"id": lid, "name": name, "center": [cx, info["level"], cz], "radius": info["radius"],
                     "level": info["level"], "frozen": frozen, "polygon": info["polygon"]})
    return recs


def _drop_field(h, window_px):
    """Height above the lowest point within a square window (cliff detector)."""
    lo = ndimage.minimum_filter(h, size=window_px)
    return h - lo, lo


def build_waterfalls(f: Field) -> tuple[list, list]:
    """Finds a real cliff near each hint, notches the lip and carves a plunge pool."""
    falls = []
    pools = []
    for k, (wid, name, (hx, hz), rad, frozen) in enumerate(pois.WATERFALLS):
        rows, cols, X, Z = f.win(hx, hz, rad + 40)
        hw = f.h[rows, cols].astype(np.float64)
        drop, _ = _drop_field(hw, 19)   # ~36 m window at 2 m/texel
        ok = (np.hypot(X - hx, Z - hz) < rad) & ~f.locked[rows, cols] & (hw > 2.0)
        score = np.where(ok, drop, -1)
        j, i = np.unravel_index(int(np.argmax(score)), score.shape)
        top = (float(X[j, i]), float(Z[j, i]))
        # bottom: lowest point in the window around the lip
        j0, j1 = max(0, j - 9), min(hw.shape[0], j + 10)
        i0, i1 = max(0, i - 9), min(hw.shape[1], i + 10)
        sub = hw[j0:j1, i0:i1]
        bj, bi = np.unravel_index(int(np.argmin(sub)), sub.shape)
        bottom = (float(X[j0 + bj, i0 + bi]), float(Z[j0 + bj, i0 + bi]))
        top_h = float(hw[j, i])
        bot_h = float(sub[bj, bi])
        # extend the fall direction a little so the pool sits clear of the cliff foot
        dx, dz = bottom[0] - top[0], bottom[1] - top[1]
        ln = max(math.hypot(dx, dz), 1e-3)
        pool_c = (bottom[0] + dx / ln * 10.0, bottom[1] + dz / ln * 10.0)
        pool_level = None
        if not frozen:
            info = carve_lake(f, f"{wid}_pool", pool_c[0], pool_c[1], 16.0, None, 3.0, False, f.seed + 950 + k)
            pool_level = info["level"]
            pools.append({"id": f"{wid}_pool", "name": f"{name} Pool", "center": [_r2(pool_c[0]), info["level"], _r2(pool_c[1])],
                          "radius": info["radius"], "level": info["level"], "frozen": False, "polygon": info["polygon"]})
        # notch the lip: a shallow stream bed running back from the top
        bx, bz = top[0] - dx / ln * 40.0, top[1] - dz / ln * 40.0
        r2, c2, X2, Z2 = f.win((top[0] + bx) / 2, (top[1] + bz) / 2, 30)
        dist, _, t = grid.polyline_distance(X2, Z2, [(bx, bz), top])
        h2 = f.h[r2, c2].astype(np.float64)
        notch = 1.4 * smoothstep(5.0, 1.5, dist)
        f.h[r2, c2] = (h2 - notch).astype(np.float32)
        falls.append({"id": wid, "name": name, "frozen": frozen,
                      "top": [_r2(top[0]), _r2(top_h - 0.6), _r2(top[1])],
                      "bottom": [_r2(bottom[0]), _r2(pool_level if pool_level is not None else bot_h), _r2(bottom[1])],
                      "height": _r2(top_h - bot_h), "width": 9.0,
                      "pool": f"{wid}_pool" if not frozen else None})
    return falls, pools


def build_arches(f: Field) -> list:
    recs = []
    for aid, name, a, b, clearance in pois.ARCHES:
        if a == "canyon":
            pts = np.asarray(layout.CANYONS[0][0], dtype=np.float64)
            s = grid.polyline_lengths(pts)
            target = s[-1] * b
            k = int(np.searchsorted(s, target)) - 1
            k = max(0, min(k, len(pts) - 2))
            t = (target - s[k]) / max(s[k + 1] - s[k], 1e-6)
            c = pts[k] + (pts[k + 1] - pts[k]) * t
            d = pts[k + 1] - pts[k]
            d /= np.linalg.norm(d)
            nrm = np.array([-d[1], d[0]])
            half = layout.CANYONS[0][1] * 0.5 + 26.0
            a = tuple(c + nrm * half)
            b = tuple(c - nrm * half)
        pa = _p3(f, *a)
        pb = _p3(f, *b)
        recs.append({"id": aid, "name": name, "a": pa, "b": pb, "width": 9.0,
                     "apex_height": _r2(max(pa[1], pb[1]) + clearance)})
    return recs


def build_ports(f: Field) -> list:
    recs = []
    for p in layout.PORTS:
        dx, dz = p["dock"]
        # quay position: nearest dry cell; berth: nearest water cell deeper than 3 m
        rows, cols, X, Z = f.win(dx, dz, 120)
        hw = f.h[rows, cols]
        d = np.hypot(X - dx, Z - dz)
        land = np.where((hw > 0.5) & (hw < 8.0), d, np.inf)
        water = np.where(hw < -3.0, d, np.inf)
        lj, li = np.unravel_index(int(np.argmin(land)), land.shape)
        wj, wi = np.unravel_index(int(np.argmin(water)), water.shape)
        quay = (float(X[lj, li]), float(Z[lj, li]))
        berth = (float(X[wj, wi]), float(Z[wj, wi]))
        yaw = -math.atan2(berth[0] - quay[0], -(berth[1] - quay[1]))
        recs.append({"id": p["id"], "name": p["name"], "region": p["region"], "settlement": p["settlement"],
                     "quay": _p3(f, *quay), "berth": [_r2(berth[0]), 0.0, _r2(berth[1])],
                     "yaw": round(yaw, 4)})
    return recs


def build_ferries(ports: list, router) -> list:
    by_id = {p["id"]: p for p in ports}
    recs = []
    for fid, a, b in layout.FERRIES:
        pa, pb = by_id[a], by_id[b]
        pts = router.route((pa["berth"][0], pa["berth"][2]), (pb["berth"][0], pb["berth"][2]))
        pts = grid.chaikin(grid.simplify_rdp(pts, 20.0), 3)
        length = float(grid.polyline_lengths(pts)[-1])
        recs.append({"id": fid, "from": a, "to": b, "points": [[_r2(x), _r2(z)] for x, z in pts],
                     "length": round(length, 1), "duration": round(length / 9.0, 1)})
    return recs


# --------------------------------------------------------------------------------------
# POIs
# --------------------------------------------------------------------------------------

def _snap(f: Field, mode, x, z, radius):
    if mode in ("ground", "pad"):
        if mode == "pad" and not f.locked[grid.to_index(x, z, f.n)[1], grid.to_index(x, z, f.n)[0]]:
            flatten_pad(f, x, z, radius, None, blend=14.0, paved=0.35, lock=True)
        return x, z, None
    rows, cols, X, Z = f.win(x, z, 160)
    hw = f.h[rows, cols].astype(np.float64)
    d = np.hypot(X - x, Z - z)
    if mode == "max":
        s = np.where(d < 140, hw, -1e9)
        j, i = np.unravel_index(int(np.argmax(s)), s.shape)
        return float(X[j, i]), float(Z[j, i]), None
    if mode == "shore":
        s = np.where((hw > 0.4) & (hw < 3.5) & ~f.locked[rows, cols], d, np.inf)
        if not np.isfinite(s).any():
            return x, z, None
        j, i = np.unravel_index(int(np.argmin(s)), s.shape)
        return float(X[j, i]), float(Z[j, i]), None
    if mode == "cliff":
        gz, gx = np.gradient(hw, f.cell)
        slope = np.hypot(gx, gz)
        s = np.where((d < 160) & (hw > 6.0) & ~f.locked[rows, cols], slope, -1)
        j, i = np.unravel_index(int(np.argmax(s)), s.shape)
        # step downhill to the foot of the face (never into water)
        ux, uz = -gx[j, i], -gz[j, i]
        ln = max(math.hypot(ux, uz), 1e-6)
        ux, uz = ux / ln, uz / ln
        fx, fz = float(X[j, i]), float(Z[j, i])
        for _ in range(40):
            nx, nz = fx + ux * 2.0, fz + uz * 2.0
            hn = float(grid.sample_bilinear(f.h, np.array([nx]), np.array([nz]))[0])
            hc = float(grid.sample_bilinear(f.h, np.array([fx]), np.array([fz]))[0])
            if hc - hn < 0.35 or hn < 2.0:
                break
            fx, fz = nx, nz
        yaw = -math.atan2(ux, -uz)   # facing out of the cliff
        hn = float(grid.sample_bilinear(f.h, np.array([fx + ux * 3.0]), np.array([fz + uz * 3.0]))[0])
        if hn > 2.0:
            fx, fz = fx + ux * 3.0, fz + uz * 3.0
        return fx, fz, yaw
    return x, z, None


def build_pois(f: Field, refs: dict, region_at) -> list:
    out = []
    for pid, name, ptype, hint, snap, radius, desc in pois.POIS:
        yaw = None
        if isinstance(hint, str):
            key = hint[4:]
            if key not in refs:
                raise KeyError(f"POI {pid}: unknown reference {key}")
            ref = refs[key]
            x, z = ref[0], ref[-1] if len(ref) == 2 else ref[2]
            y = ref[1] if len(ref) == 3 else None
        else:
            x, z, yaw = _snap(f, snap, hint[0], hint[1], radius if snap == "pad" else 0)
            y = None
        pos = _p3(f, x, z, y)
        rec = {"id": pid, "name": name, "type": ptype, "position": pos, "region": region_at(pos[0], pos[2]),
               "radius": float(radius), "description": desc}
        if yaw is not None:
            rec["yaw"] = round(yaw, 4)
        out.append(rec)
    return out


def underground(f: Field, pois_list: list) -> None:
    """Gives cave POIs an underground passage descending into the rock behind the mouth."""
    for p in pois_list:
        if p["type"] != "cave" or "yaw" not in p:
            continue
        yaw = p["yaw"]
        ix, iz = math.sin(yaw), math.cos(yaw)   # inward = opposite of facing (-sin(yaw), -cos(yaw))
        x, y, z = p["position"]
        path = []
        for k in range(7):
            d = k * 22.0
            px, pz = x + ix * d, z + iz * d
            ground = float(grid.sample_bilinear(f.h, np.array([px]), np.array([pz]))[0])
            py = y - k * 2.2
            path.append([_r2(px), _r2(min(py, ground - 6.0 if k > 0 else y)), _r2(pz)])
        p["underground"] = True
        p["tunnel"] = path
        p["entrance"] = p["position"]


# --------------------------------------------------------------------------------------
# Spawns + arrival cameras
# --------------------------------------------------------------------------------------

def _look(pos, target):
    return {"position": [_r2(v) for v in pos], "look_at": [_r2(v) for v in target]}


def build_spawns(f: Field) -> tuple[dict, dict]:
    nwt_q = layout.NWT["harbor_center"]
    bss = layout.BA_SING_SE["center"]
    fire = layout.FIRE_CAPITAL["center"]
    air = layout.AIR_TEMPLE["center"]
    g = layout.fire_gorge()
    defs = {
        # element: (position xz, facing bearing, view description)
        "water": (layout.polar(nwt_q, 9.0, 515.0), 180.0),
        "earth": (layout.polar(bss, 252.0, 138.0), 270.0),
        "fire": (layout.polar(fire, g["bearing"] + 14.0, 128.0), g["bearing"]),
        "air": (layout.polar(air, 12.0, 100.0), 0.0),
    }
    spawns = {}
    cams = {}
    for el, ((x, z), bearing) in defs.items():
        y = float(grid.sample_bilinear(f.h, np.array([x]), np.array([z]))[0])
        yaw = -math.radians(bearing)
        fx, fz = layout.bearing_vec(bearing)
        spawns[el] = {"position": [_r2(x), _r2(y + 0.05), _r2(z)], "yaw": round(yaw, 4), "bearing": bearing}
        start = (x - fx * 640.0, y + 260.0, z - fz * 640.0)
        start_look = (x + fx * 260.0, y - 30.0, z + fz * 260.0)
        end = (x - fx * 7.0, y + 3.0, z - fz * 7.0)
        end_look = (x + fx * 60.0, y + 0.5, z + fz * 60.0)
        # keep the start camera above the terrain it flies over
        for t in np.linspace(0, 1, 24):
            px = start[0] + (end[0] - start[0]) * t
            pz = start[2] + (end[2] - start[2]) * t
            ground = float(grid.sample_bilinear(f.h, np.array([px]), np.array([pz]))[0])
            py = start[1] + (end[1] - start[1]) * t
            if py < ground + 25.0 and t < 0.9:
                start = (start[0], start[1] + (ground + 25.0 - py), start[2])
        cams[el] = {"start": _look(start, start_look), "end": _look(end, end_look), "duration": 8.0,
                    "fov_start": 58.0, "fov_end": 72.0}
    return spawns, cams
