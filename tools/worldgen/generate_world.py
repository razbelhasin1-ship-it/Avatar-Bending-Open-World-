#!/usr/bin/env python3
"""Offline world generator for Avatar: The Four Nations.

Bakes one connected 8192 x 8192 m world centred on the origin (north = -Z, 1 unit = 1 m,
sea level y = 0) into assets/world/:

    heightmap.r16.zlib   4096^2 uint16 LE heights (2 m texels), zlib stream (Godot COMPRESSION_DEFLATE)
    splat.png            2048^2 RGBA terrain material weights (snow, rock, lush, sand/ash)
    biome.png            2048^2 L8 WorldData.Biome ids
    region.png           1024^2 L8 region index (see world.json "regions")
    roads.png            4096^2 L8 road coverage
    ground.png           2048^2 RGBA hints (paved road, settlement paving, farmland, wetness)
    map.jpg              2048^2 painterly parchment map (no text)
    world.json           metadata, cities, villages, roads, ports, ferries, lakes, canals,
                         waterfalls, bridges, arches, POIs, spawns, arrival cameras

Usage:
    python3 tools/worldgen/generate_world.py [--seed 1337] [--out assets/world] [--quick]

Deterministic for a given seed. Runs in about 3-6 minutes on 4 cores (numpy/scipy/pillow only).
Format details: docs/modules/worlddata.md.
"""
from __future__ import annotations

import argparse
import math
import os
import sys
import time

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from wg import grid, layout, terrain, erosion, shapes, cities, temple, features, routes, classify, export, mapart, preview  # noqa: E402
from wg import noise as nz  # noqa: E402
from wg.grid import smoothstep  # noqa: E402

FINAL_RES = 4096
MAP_RES = 2048


class Clock:
    def __init__(self):
        self.t0 = time.time()
        self.last = self.t0

    def lap(self, what: str) -> None:
        now = time.time()
        print(f"[worldgen] {what:<38s} {now - self.last:6.1f}s  (total {now - self.t0:6.1f}s)", flush=True)
        self.last = now


def r2(v) -> float:
    return round(float(v), 2)


def add_detail(h4: np.ndarray, slope1024: np.ndarray, territory1024: np.ndarray, seed: int) -> np.ndarray:
    """Fine relief that the 8 m erosion grid cannot hold: rocky crags on steep ground, ripples elsewhere."""
    n = h4.shape[0]
    out = h4.copy()
    sl = grid.resample(slope1024.astype(np.float32), n, order=1)
    arctic = grid.resample((territory1024 == terrain.T_WATER).astype(np.float32), n, order=1)
    step = 512
    ax = grid.axis(n)
    for j0 in range(0, n, step):
        zs = ax[j0:j0 + step]
        X, Z = np.meshgrid(ax, zs, indexing="xy")
        s = sl[j0:j0 + step]
        amp_rock = 1.8 * smoothstep(18.0, 42.0, s) * (1.0 - 0.5 * arctic[j0:j0 + step])
        amp_soft = 0.14 * (1.0 - 0.6 * arctic[j0:j0 + step])
        rk = nz.ridged(X, Z, 1 / 46, seed + 801, 3, sharpness=2.0) - 0.35
        fb = nz.fbm(X, Z, 1 / 17, seed + 802, 2)
        land = h4[j0:j0 + step] > 0.5
        out[j0:j0 + step] += np.where(land, rk * amp_rock * 2.0 + fb * amp_soft, 0.0)
    return out.astype(np.float32)


def resolve_anchor(key, anchors):
    if isinstance(key, tuple):
        return key
    if key not in anchors:
        raise KeyError(f"unknown road anchor {key}")
    return anchors[key]


def grade_limit(hs: np.ndarray, ds: float, grade: float) -> np.ndarray:
    """Clamps a road profile to a maximum grade (average of forward and backward passes)."""
    fw = hs.copy()
    for i in range(1, len(fw)):
        fw[i] = min(max(fw[i], fw[i - 1] - grade * ds), fw[i - 1] + grade * ds)
    bw = hs.copy()
    for i in range(len(bw) - 2, -1, -1):
        bw[i] = min(max(bw[i], bw[i + 1] - grade * ds), bw[i + 1] + grade * ds)
    return 0.5 * (fw + bw)


def build_roads(f: shapes.Field, anchors: dict, forbid: np.ndarray, extra: list, clock: Clock):
    router = routes.RoadRouter(f.h, forbid, f.locked, n=1024)
    out_flat = []
    out_json = []
    for rd in layout.ROADS:
        pts_all = []
        wps = [resolve_anchor(w, anchors) for w in rd["waypoints"]]
        for a, b in zip(wps[:-1], wps[1:]):
            seg = router.route(a, b)
            if pts_all:
                seg = seg[1:]
            pts_all.extend(seg.tolist())
        pts = routes.smooth_path(np.asarray(pts_all), router.g.cell)
        pts = grid.resample_polyline(pts, 1.0)
        hs = grid.sample_bilinear(f.h, pts[:, 0], pts[:, 1])
        hs = ndimage.uniform_filter1d(hs, size=31, mode="nearest")
        hs = grade_limit(hs, 1.0, 0.15)
        hs = ndimage.uniform_filter1d(hs, size=21, mode="nearest")
        main = rd["kind"] == "main"
        samples = np.column_stack([pts, hs])
        out_flat.append({"samples": samples, "half_width": 4.0 if main else 2.6, "paved": main})
        out_json.append(_road_json(rd["id"], rd["name"], rd["kind"], samples, 8.0 if main else 5.2,
                                   "stone" if main else "dirt"))
    for e in extra:
        out_flat.append(e)
        out_json.append(_road_json(e["id"], "Pass of a Thousand Steps (switchbacks)", "main", e["samples"],
                                   e["half_width"] * 2, "stone", grade=e.get("grade")))
    clock.lap("roads: routed %d" % len(out_json))
    return out_flat, out_json


def _road_json(rid, name, kind, samples, width, surface, grade=None):
    pts2 = grid.simplify_rdp(samples[:, :2], 1.2)
    # keep the matching heights for the simplified points
    tree = {(round(p[0], 3), round(p[1], 3)): i for i, p in enumerate(samples[:, :2])}
    out = []
    for p in pts2:
        i = tree.get((round(p[0], 3), round(p[1], 3)))
        y = samples[i, 2] if i is not None else samples[np.argmin(np.hypot(samples[:, 0] - p[0], samples[:, 1] - p[1])), 2]
        out.append([r2(p[0]), r2(y), r2(p[1])])
    length = float(grid.polyline_lengths(samples[:, :2])[-1])
    d = {"id": rid, "name": name, "kind": kind, "width": width, "surface": surface, "points": out,
         "length": round(length, 1)}
    if grade is not None:
        d["grade"] = grade
    return d


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "assets", "world"))
    ap.add_argument("--preview", default=os.path.join(HERE, "preview"))
    ap.add_argument("--droplets", type=int, default=700_000)
    ap.add_argument("--quick", action="store_true", help="fewer erosion droplets (fast iteration)")
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    pv = os.path.abspath(args.preview)
    os.makedirs(out, exist_ok=True)
    os.makedirs(pv, exist_ok=True)
    seed = args.seed
    clock = Clock()

    # 1. coarse base terrain ----------------------------------------------------------
    base = terrain.Base(1024, seed)
    terrain.build_coast(base)
    clock.lap("coast + territories")
    terrain.build_elevation(base)
    clock.lap("base elevation")
    preview.save_preview(base.h, base.cell, os.path.join(pv, "01_base.png"))

    # 2. erosion -------------------------------------------------------------------------------
    flux = np.zeros_like(base.h, dtype=np.float64)
    drops = args.droplets // (4 if args.quick else 1)
    h = erosion.droplet_erosion(base.h, base.cell, base.erodibility, drops, seed + 7, flux_out=flux)
    clock.lap(f"hydraulic erosion ({drops} droplets)")
    h = erosion.thermal_erosion(h, base.cell, 38.0, 30, mask=base.erodibility > 0.05)
    h = np.where(base.h <= 0, np.minimum(h, -0.5), h)          # erosion never raises the sea floor into land
    h = terrain.enforce_peaks(h, base.X, base.Z)
    clock.lap("thermal erosion + summits")
    preview.save_preview(h, base.cell, os.path.join(pv, "02_eroded.png"))

    # 3. upsample + detail ------------------------------------------------------------
    gz, gx = np.gradient(h.astype(np.float64), base.cell)
    slope1024 = np.degrees(np.arctan(np.hypot(gx, gz)))
    h4 = grid.resample(h, FINAL_RES, order=3)
    h4 = add_detail(h4, slope1024, base.territory, seed)
    clock.lap("upsample to 4096 + detail")

    # 4. shaped features ----------------------------------------------------------------
    f = shapes.Field(h4, seed)
    recs_cities = []
    anchors = {}
    canals = []
    bridges = []
    extra_lakes = []
    nwt = cities.build_nwt(f)
    recs_cities.append(nwt["city"])
    canals += nwt["canals"]
    for g in nwt["city"]["gates"]:
        anchors[f"northern_water_tribe:{g['id']}"] = (g["position"][0], g["position"][2])
    so = nwt["city"]["spirit_oasis"]
    extra_lakes.append({"id": "nwt_spirit_pond", "name": "Spirit Pond", "center": [so["position"][0], so["pond_level"], so["position"][2]],
                        "radius": so["pond_radius"] * 1.25, "level": so["pond_level"], "frozen": False,
                        "polygon": [[r2(so["position"][0] + math.sin(a) * so["pond_radius"]), r2(so["position"][2] + math.cos(a) * so["pond_radius"])]
                                    for a in np.linspace(0, 2 * math.pi, 24, endpoint=False)]})
    bss = cities.build_ba_sing_se(f)
    recs_cities.append(bss["city"])
    for g in bss["city"]["gates"]:
        anchors[f"ba_sing_se:{g['id']}"] = (g["outside"][0], g["outside"][2])
    om = cities.build_omashu(f)
    recs_cities.append(om["city"])
    bridges += om["bridges"]
    anchors.update(om["anchors"])
    fc = cities.build_fire_capital(f)
    recs_cities.append(fc["city"])
    anchors.update(fc["anchors"])
    fh = cities.build_fire_harbor(f)
    recs_cities.append(fh["city"])
    anchors.update(fh["anchors"])
    at = temple.build_air_temple(f)
    recs_cities.append(at["city"])
    bridges += at["bridges"]
    clock.lap("cities")
    villages, v_anchors = features.build_villages(f)
    anchors.update(v_anchors)
    lakes = features.build_lakes(f)
    falls, pools = features.build_waterfalls(f)
    lakes += pools + extra_lakes
    clock.lap("villages, lakes, waterfalls")

    # 5. roads ------------------------------------------------------------------------------
    sw = temple.switchback_road(f)
    anchors.update(sw["anchors"])
    lake_mask = np.zeros(f.h.shape, dtype=bool)
    for lk in lakes:
        poly = [(p[0], p[1]) for p in lk["polygon"]]
        lake_mask |= terrain.polygon_mask(poly, FINAL_RES)
    forbid = (f.h < 0.5) | lake_mask
    road_flat, road_json = build_roads(f, anchors, forbid, [sw], clock)
    road_cover, road_paved = shapes.flatten_roads(f, road_flat)
    clock.lap("road flattening")

    # 6. arches, ports, ferries ------------------------------------------------------------
    arches = features.build_arches(f)
    ports = features.build_ports(f)
    ferries = features.build_ferries(ports, routes.FerryRouter(f.h))
    clock.lap("arches, ports, ferries")

    # 7. regions + POIs + spawns --------------------------------------------------------
    h1024 = grid.downsample_mean(f.h, FINAL_RES // 1024)
    lake1024 = grid.downsample_mean(lake_mask.astype(np.float32), FINAL_RES // 1024) > 0.5
    regions = classify.region_map(h1024, base.territory, lake1024)

    def region_at(x, z):
        i, j = grid.to_index(x, z, 1024)
        return layout.REGION_IDS[int(regions[j, i])]

    refs = _poi_refs(f, recs_cities, villages, lakes, ports, falls, bridges, arches, anchors)
    poi_list = features.build_pois(f, refs, region_at)
    features.underground(f, poi_list)
    for p in poi_list:   # pads placed for later POIs may have nudged earlier ones: re-ground all
        x, _, z = p["position"]
        p["position"][1] = r2(grid.sample_bilinear(f.h, np.array([x]), np.array([z]))[0])
    spawns, cams = features.build_spawns(f)
    clock.lap("POIs, spawns, cameras")

    # 8. classification ----------------------------------------------------------------------
    masks = {"settlement": f.settlement, "farmland": f.farmland, "temple": f.temple, "grass_patch": f.grass_patch}
    cl = classify.Classifier(f.h, masks, base.territory, flux, lakes, seed, n=2048)
    biome = cl.classify()
    splat = cl.splat()
    ground = cl.ground(road_paved)
    clock.lap("biomes + splat")

    # 9. export ---------------------------------------------------------------------------
    hm = export.write_heightmap(os.path.join(out, "heightmap.r16.zlib"), f.h)
    sizes = {"heightmap.r16.zlib": hm["compressed_size"]}
    sizes["biome.png"] = export.write_png(os.path.join(out, "biome.png"), biome, "L")
    sizes["splat.png"] = export.write_png(os.path.join(out, "splat.png"), splat, "RGBA")
    sizes["region.png"] = export.write_png(os.path.join(out, "region.png"), regions, "L")
    sizes["roads.png"] = export.write_png(os.path.join(out, "roads.png"), road_cover, "L")
    sizes["ground.png"] = export.write_png(os.path.join(out, "ground.png"), ground, "RGBA")
    data = {
        "version": 1,
        "seed": seed,
        "generator": "tools/worldgen/generate_world.py",
        "world": {"size": 8192.0, "min": [-4096.0, -4096.0], "max": [4096.0, 4096.0], "sea_level": 0.0,
                  "north": "-Z", "units": "metres"},
        "heightmap": {"file": "heightmap.r16.zlib", "width": FINAL_RES, "height": FINAL_RES, "texel_size": 2.0,
                      "format": "u16le", "compression": "deflate(zlib)", "raw_size": hm["raw_size"],
                      "height_min": export.HEIGHT_MIN, "height_scale": export.HEIGHT_SCALE,
                      "height_max": export.HEIGHT_MAX,
                      "decode": "height = raw * height_scale + height_min; texel (i,j) centre at "
                                "x = -4096 + (i + 0.5) * 2, z = -4096 + (j + 0.5) * 2"},
        "maps": {
            "splat": {"file": "splat.png", "size": 2048, "channels": ["snow", "rock", "lush", "sand_ash"]},
            "biome": {"file": "biome.png", "size": 2048, "values": "WorldData.Biome"},
            "region": {"file": "region.png", "size": 1024, "values": "index into regions"},
            "roads": {"file": "roads.png", "size": 4096, "channels": ["coverage"]},
            "ground": {"file": "ground.png", "size": 2048, "channels": ["paved_road", "settlement", "farmland", "wetness"]},
            "map_image": {"file": "map.jpg", "size": MAP_RES, "covers": "whole world, uv = (pos.xz + 4096) / 8192"},
        },
        "biomes": classify.BIOMES,
        "regions": [{"index": i, "id": rid, "name": layout.REGION_NAMES[rid]} for i, rid in enumerate(layout.REGION_IDS)],
        "cities": recs_cities,
        "villages": villages,
        "roads": road_json,
        "ports": ports,
        "ferries": ferries,
        "lakes": lakes,
        "canals": canals,
        "waterfalls": falls,
        "bridges": bridges,
        "arches": arches,
        "pois": poi_list,
        "spawns": spawns,
        "arrival_cameras": cams,
    }
    img = mapart.render(f.h, biome, data, seed, MAP_RES)
    map_path = os.path.join(out, "map.jpg")
    img.save(map_path, quality=88, optimize=True, progressive=False)
    sizes["map.jpg"] = os.path.getsize(map_path)
    sizes["world.json"] = export.write_json(os.path.join(out, "world.json"), data)
    for name in ("heightmap.r16.zlib", "biome.png", "splat.png", "region.png", "roads.png", "ground.png", "map.jpg"):
        export.write_keep_import(os.path.join(out, name))
    clock.lap("export")
    total = sum(sizes.values())
    for k, v in sizes.items():
        print(f"[worldgen]   {k:<22s} {v / 1e6:7.2f} MB")
    print(f"[worldgen]   {'TOTAL':<22s} {total / 1e6:7.2f} MB   pois={len(poi_list)} roads={len(road_json)} lakes={len(lakes)}")

    # 10. previews ------------------------------------------------------------------------
    preview.save_preview(grid.downsample_mean(f.h, 4), 8.0, os.path.join(pv, "03_final.png"))
    pal = {i: c for i, c in enumerate([(40, 70, 120), (230, 210, 160), (245, 245, 250), (190, 220, 235), (190, 190, 160),
                                       (140, 180, 90), (60, 120, 60), (220, 200, 110), (130, 120, 110), (150, 130, 110),
                                       (90, 40, 30), (110, 105, 100), (240, 190, 90), (200, 90, 60)])}
    preview.save_labels(biome, pal, os.path.join(pv, "04_biomes.png"))
    preview.save_labels(regions, {0: (20, 40, 80), 1: (200, 220, 255), 2: (90, 160, 70), 3: (200, 60, 40),
                                  4: (240, 200, 80), 5: (150, 150, 150)}, os.path.join(pv, "05_regions.png"), 512)
    from PIL import Image
    Image.fromarray((splat * 255).astype(np.uint8), "RGBA").convert("RGB").resize((1024, 1024)).save(os.path.join(pv, "06_splat.png"))
    img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(pv, "07_map.jpg"), quality=90)
    clock.lap("previews")
    return 0


def _poi_refs(f, recs_cities, villages, lakes, ports, falls, bridges, arches, anchors) -> dict:
    by = {c["id"]: c for c in recs_cities}
    refs = {}

    def ground(x, z):
        return (x, float(grid.sample_bilinear(f.h, np.array([x]), np.array([z]))[0]), z)

    nwt = by["northern_water_tribe"]
    so = nwt["spirit_oasis"]
    refs["oasis:northern_water_tribe"] = ground(so["position"][0], so["position"][2] + so["pond_radius"] + 7.0)
    q = layout.NWT["harbor_center"]
    refs["seawall_east:northern_water_tribe"] = ground(*layout.polar(q, 116.0, 345.0))
    for lk in lakes:
        cx, lv, cz = lk["center"]
        if lk["frozen"]:
            refs[f"lake:{lk['id']}"] = (cx, lv, cz)
        p = lk["polygon"][0]
        dx, dz = p[0] - cx, p[1] - cz
        ln = max(math.hypot(dx, dz), 1e-3)
        sx, sz = p[0] + dx / ln * 9.0, p[1] + dz / ln * 9.0
        refs[f"lakeshore:{lk['id']}"] = ground(sx, sz)
        if not lk["frozen"]:
            refs[f"lake:{lk['id']}"] = ground(sx, sz)
    for v in villages:
        refs[f"village:{v['id']}"] = tuple(v["center"])
    for p in ports:
        refs[f"port:{p['id']}"] = tuple(p["quay"])
    for w in falls:
        bx, _, bz = w["bottom"]
        tx, _, tz = w["top"]
        dx, dz = bx - tx, bz - tz
        ln = max(math.hypot(dx, dz), 1e-3)
        refs[f"waterfall:{w['id']}"] = ground(bx + dx / ln * 32.0, bz + dz / ln * 32.0) if not w["frozen"] else ground(bx, bz)
    for b in bridges:
        refs[f"bridge:{b['id']}"] = tuple(b["a"])
    for a in arches:
        refs[f"arch:{a['id']}"] = tuple(a["a"])
    om = layout.OMASHU
    refs["omashu_market"] = ground(*layout.polar(om["center"], 160.0, 172.0))
    for g in by["ba_sing_se"]["gates"]:
        refs[f"bss_gate:{g['id']}"] = tuple(g["outside"])
    c = layout.FIRE_CAPITAL["center"]
    refs["fire_plaza"] = ground(*layout.polar(c, 180.0, 100.0))
    refs["fire_training"] = ground(*layout.polar(c, 60.0, 205.0))
    gz = layout.fire_gorge()
    refs["fire_gorge"] = ground(*layout.polar(c, gz["bearing"], (gz["r_in"] + gz["r_out"]) * 0.5))
    refs["fire_rim"] = _ring_max(f, c, 460.0, 600.0, 280.0, 330.0)
    refs["volcano_rim"] = _ring_max(f, (-1650.0, 3480.0), 80.0, 150.0, -180.0, 180.0)
    t = layout.AIR_TEMPLE["center"]
    refs["temple_core"] = ground(*layout.polar(t, 180.0, 70.0))
    refs["temple_landing"] = ground(*layout.polar(t, 20.0, 188.0))
    refs["temple_courts"] = ground(*layout.polar(t, 120.0, 80.0))
    refs["temple_leap"] = ground(*layout.polar(t, 140.0, 155.0))
    for pin in temple.PINNACLES:
        x, z = layout.polar(t, pin["bearing"], pin["distance"])
        refs[f"pinnacle:{pin['id']}"] = ground(x, z)
    for k, v in anchors.items():
        refs[f"anchor:{k}"] = ground(*v)
    return refs


def _ring_max(f, center, r0, r1, b0, b1):
    rows, cols, X, Z = f.win(center[0], center[1], r1 + 4)
    dx, dz = X - center[0], Z - center[1]
    r = np.hypot(dx, dz)
    b = np.degrees(np.arctan2(dx, -dz)) % 360.0
    lo, hi = b0 % 360.0, b1 % 360.0
    in_b = (b >= lo) & (b <= hi) if lo <= hi else ((b >= lo) | (b <= hi))
    if b1 - b0 >= 360:
        in_b = np.ones_like(r, dtype=bool)
    hw = np.where((r > r0) & (r < r1) & in_b, f.h[rows, cols], -1e9)
    j, i = np.unravel_index(int(np.argmax(hw)), hw.shape)
    return (float(X[j, i]), float(hw[j, i]), float(Z[j, i]))


if __name__ == "__main__":
    sys.exit(main())
