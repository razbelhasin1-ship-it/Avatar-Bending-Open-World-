"""Great cities: terrain shaping + the layout records exported to world.json.

Conventions in the records: positions are [x, y, z] metres (y = terrain height after
shaping), 2D points are [x, z], bearings are degrees from north clockwise
(0 = -Z, 90 = +X), radii are metres from the record's ring centre.
"""
from __future__ import annotations

import math

import numpy as np

from . import grid, layout
from . import noise as nz
from .grid import smoothstep, lerp
from .shapes import Field, ring_layout, flatten_pad, carve_channel_flat, raise_sill, carve_lake, wrap_deg


def _r2(v) -> float:
    return round(float(v), 2)


def _p3(f: Field, x, z, y=None):
    if y is None:
        y = float(grid.sample_bilinear(f.h, np.array([x]), np.array([z]))[0])
    return [_r2(x), _r2(y), _r2(z)]


def _tiers_json(tiers):
    out = []
    for t in tiers:
        d = {"id": t["id"], "name": t.get("name", t["id"]), "r_inner": t["r_inner"], "r_outer": t["r_outer"],
             "height": t["height"]}
        d["arc"] = list(t["arc"]) if t.get("arc") else None
        out.append(d)
    return out


def _ramps_json(bearings, width, length):
    return [{"bearing": _r2(b), "width": width, "length": length} for b in bearings]


def _carve_bay(f: Field, center, radius, depth):
    rows, cols, X, Z = f.win(center[0], center[1], radius + 10)
    r = np.hypot(X - center[0], Z - center[1])
    hw = f.h[rows, cols].astype(np.float64)
    bottom = depth - 1.5 * smoothstep(radius * 0.9, radius * 0.2, r)
    f.h[rows, cols] = np.where(r < radius, np.minimum(hw, bottom), hw).astype(np.float32)
    f.locked[rows, cols] |= r < radius


# --------------------------------------------------------------------------------------
# Northern Water Tribe
# --------------------------------------------------------------------------------------

def build_nwt(f: Field) -> dict:
    cfg = layout.NWT
    q = cfg["harbor_center"]
    bay_r = cfg["bay_radius"]
    _carve_bay(f, q, bay_r, cfg["bay_depth"])
    sw = cfg["sea_wall"]
    raise_sill(f, sw["points"], sw["thickness"] * 0.5 + 6, sw["base"])

    def keep_out(r, b):
        return r < bay_r + 1.0

    ring_layout(f, q, cfg["tiers"], cfg["ramp_bearings"], cfg["ramp_width"], cfg["ramp_length"], cfg["blend"],
                keep_out=keep_out)
    # Palace platform on the northern apex
    pal = cfg["palace"]
    ppos = layout.polar(q, pal["bearing"], pal["radius"])
    flatten_pad(f, ppos[0], ppos[1], pal["platform_radius"], pal["height"], blend=6.0, paved=1.0)
    # Canals: radial channels from the bay through the harbour tier (sea level) and up into the
    # middle tier (raised canal level, fed through "canal falls" at the tier wall), plus a ring canal.
    width = cfg["canal_width"]
    lv = cfg["canal_levels"]
    harbor_t = cfg["tiers"][0]
    middle_t = cfg["tiers"][1]
    rc = cfg["ring_canal"]
    canals = []
    falls = []
    for k, b in enumerate(cfg["canal_bearings"]):
        a = layout.polar(q, b, bay_r - 6)
        m = layout.polar(q, b, harbor_t["r_outer"])
        e = layout.polar(q, b, rc["radius"])
        canals.append({"id": f"nwt_canal_low_{k}", "points": [list(map(_r2, a)), list(map(_r2, m))], "width": width,
                       "level": lv["harbor"], "bed": lv["harbor"] - 3.0, "tier": "harbor"})
        canals.append({"id": f"nwt_canal_mid_{k}", "points": [list(map(_r2, m)), list(map(_r2, e))], "width": width,
                       "level": lv["middle"], "bed": lv["middle"] - 2.5, "tier": "middle"})
        falls.append({"id": f"nwt_canal_fall_{k}", "position": [_r2(m[0]), lv["middle"], _r2(m[1])],
                      "top": lv["middle"], "bottom": lv["harbor"], "bearing": _r2(b), "width": width})
    ring_pts = [list(map(_r2, layout.polar(q, b, rc["radius"]))) for b in np.linspace(rc["arc"][0], rc["arc"][1], 41)]
    canals.append({"id": "nwt_canal_ring", "points": ring_pts, "width": width, "level": lv["middle"],
                   "bed": lv["middle"] - 2.5, "tier": "middle"})
    for c in canals:
        carve_channel_flat(f, c["points"], c["width"] * 0.5, c["bed"])
    # Spirit oasis: warm grassy courtyard with a small pond in the palace tier
    so = cfg["spirit_oasis"]
    opos = layout.polar(q, so["bearing"], so["radius"])
    palace_h = cfg["tiers"][-1]["height"]
    rows, cols, X, Z = f.win(opos[0], opos[1], so["court_radius"] + 4)
    r = np.hypot(X - opos[0], Z - opos[1])
    f.grass_patch[rows, cols] = np.maximum(f.grass_patch[rows, cols], smoothstep(so["court_radius"], so["court_radius"] - 4, r))
    f.settlement[rows, cols] *= (r > so["court_radius"]).astype(np.float32)
    pond_level = palace_h - 0.35
    hw = f.h[rows, cols].astype(np.float64)
    bowl = pond_level - so["pond_depth"] * np.clip(1 - (r / so["pond_radius"]) ** 2, 0, 1) ** 0.5 - 0.15
    f.h[rows, cols] = np.where(r < so["pond_radius"], np.minimum(hw, bowl), hw).astype(np.float32)
    gates = []
    for g in cfg["gates"]:
        p = layout.polar(q, g["bearing"], g["radius"])
        gates.append({"id": g["id"], "position": _p3(f, *p), "bearing": g["bearing"], "width": 18.0})
    wall = {
        "points": [list(map(_r2, p)) for p in sw["points"]],
        "height": sw["height"], "thickness": sw["thickness"], "base": sw["base"],
        "gate": {"center": list(map(_r2, sw["gate"]["center"])), "width": sw["gate"]["width"]},
    }
    rec = {
        "id": cfg["id"], "name": cfg["name"], "region": cfg["region"], "kind": "capital",
        "center": _p3(f, *cfg["center"]), "radius": 760.0, "layout": "rings",
        "ring_center": list(map(_r2, q)),
        "tiers": _tiers_json(cfg["tiers"]),
        "ramps": _ramps_json(cfg["ramp_bearings"], cfg["ramp_width"], cfg["ramp_length"]),
        "gates": gates,
        "harbor": {"center": list(map(_r2, q)), "radius": bay_r, "floor": cfg["bay_depth"], "water_level": 0.0},
        "sea_wall": wall,
        "canals": [c["id"] for c in canals],
        "canal_falls": falls,
        "palace": {"position": _p3(f, *ppos), "radius": pal["platform_radius"], "height": pal["height"]},
        "spirit_oasis": {"position": _p3(f, *opos, palace_h), "radius": so["court_radius"],
                         "pond_radius": so["pond_radius"], "pond_level": _r2(pond_level)},
    }
    return {"city": rec, "canals": canals,
            "fountains": [{"id": "nwt_spirit_pond", "position": [_r2(opos[0]), _r2(pond_level), _r2(opos[1])],
                           "radius": so["pond_radius"], "kind": "water"}]}


# --------------------------------------------------------------------------------------
# Ba Sing Se
# --------------------------------------------------------------------------------------

def build_ba_sing_se(f: Field) -> dict:
    cfg = layout.BA_SING_SE
    c = cfg["center"]
    tiers = cfg["districts"]
    gates = cfg["gates"]
    s = f.seed

    def target_fn(X, Z, r, b, target):
        agr = (r >= 380) & (r < 700) & ~np.isnan(target)
        und = nz.fbm(X, Z, 1 / 260, s + 501, 3) * 1.1
        target = np.where(agr, target + und, target)
        return target

    rows, cols, inside = ring_layout(f, c, tiers, [g["bearing"] for g in gates], cfg["ramp_width"], cfg["ramp_length"],
                                     cfg["blend"], target_fn=target_fn, paved=0.0)
    # paved city inside the inner wall, farmland in the agrarian zone (except the avenues)
    win = f.win(c[0], c[1], 700 + cfg["blend"] + 20)
    _, _, X, Z = win
    r = np.hypot(X - c[0], Z - c[1])
    b = np.degrees(np.arctan2(X - c[0], -(Z - c[1])))
    avenue = np.zeros(r.shape, dtype=bool)
    for g in gates:
        da = np.radians(wrap_deg(b - g["bearing"]))
        avenue |= (np.abs(np.sin(da) * r) < 14) & (np.cos(da) > 0)
    f.settlement[rows, cols] = np.maximum(f.settlement[rows, cols], ((r < 380) | ((r < 715) & avenue)).astype(np.float32))
    f.farmland[rows, cols] = np.maximum(f.farmland[rows, cols], ((r > 395) & (r < 688) & ~avenue).astype(np.float32))
    gate_recs = []
    avenues = []
    for g in gates:
        outer = layout.polar(c, g["bearing"], 700)
        inner = layout.polar(c, g["bearing"], 380)
        outside = layout.polar(c, g["bearing"], 735)
        gate_recs.append({"id": g["id"], "bearing": g["bearing"], "position": _p3(f, *outer),
                          "inner_gate": _p3(f, *inner), "outside": _p3(f, *outside), "width": 26.0})
        pts = [layout.polar(c, g["bearing"], rr) for rr in (735, 700, 380, 262, 150, 58)]
        avenues.append({"gate": g["id"], "points": [_p3(f, *p) for p in pts], "width": 24.0})
    rec = {
        "id": cfg["id"], "name": cfg["name"], "region": cfg["region"], "kind": "capital",
        "center": _p3(f, *c), "radius": 720.0, "layout": "rings", "ring_center": list(map(_r2, c)),
        "base_height": cfg["base_height"],
        "tiers": _tiers_json(tiers),
        "districts": _tiers_json(tiers),
        "walls": [dict(w) for w in cfg["walls"]],
        "gates": gate_recs,
        "avenues": avenues,
        "ramps": _ramps_json([g["bearing"] for g in gates], cfg["ramp_width"], cfg["ramp_length"]),
        "palace": {"position": _p3(f, *c), "radius": tiers[0]["r_outer"], "height": tiers[0]["height"]},
    }
    return {"city": rec}


# --------------------------------------------------------------------------------------
# Omashu
# --------------------------------------------------------------------------------------

def build_omashu(f: Field) -> dict:
    cfg = layout.OMASHU
    c = cfg["center"]
    dist_tiers = cfg["districts"]
    ch = cfg["chasm"]
    rim = cfg["rim"]
    all_tiers = dist_tiers + [
        {"id": "chasm", "r_inner": ch["r_inner"], "r_outer": ch["r_outer"], "height": ch["floor"]},
        {"id": "rim", "r_inner": rim["r_inner"], "r_outer": rim["r_outer"], "height": rim["height"]},
    ]
    cw_b = cfg["causeway_bearing"]
    gate_h = dist_tiers[-1]["height"]

    def target_fn(X, Z, r, b, target):
        da = np.radians(wrap_deg(b - cw_b))
        across = np.abs(np.sin(da) * r)
        zone = (np.cos(da) > 0) & (r > ch["r_inner"] - 4) & (r < ch["r_outer"] + 4)
        cw = zone & (across < cfg["causeway_width"] * 0.5 + 6)
        t = np.clip((r - ch["r_inner"]) / (ch["r_outer"] - ch["r_inner"]), 0, 1)
        deck = lerp(gate_h, rim["height"], t)
        edge = smoothstep(cfg["causeway_width"] * 0.5 + 6, cfg["causeway_width"] * 0.5, across)
        target = np.where(cw, lerp(target, deck, edge), target)
        # rough, deep chasm floor
        chasm = (r >= ch["r_inner"]) & (r < ch["r_outer"]) & ~cw
        rough = ch["floor"] + nz.fbm(X, Z, 1 / 40, f.seed + 520, 3) * 5 + 10 * smoothstep(
            (ch["r_outer"] - ch["r_inner"]) * 0.35, 0, np.minimum(np.abs(r - ch["r_inner"]), np.abs(r - ch["r_outer"])))
        target = np.where(chasm, rough, target)
        return target

    # Ramps only inside the city (never down into the chasm)
    rows, cols, inside = ring_layout(f, c, all_tiers, [], cfg["ramp_width"], cfg["ramp_length"], cfg["blend"],
                                     target_fn=target_fn, paved=0.0)
    ring_layout(f, c, dist_tiers, cfg["ramp_bearings"], cfg["ramp_width"], cfg["ramp_length"], 1.0, paved=1.0)
    bridge_a = layout.polar(c, cfg["bridge_bearing"], rim["r_inner"] + 6)
    bridge_b = layout.polar(c, cfg["bridge_bearing"], ch["r_inner"] - 6)
    cw_a = layout.polar(c, cw_b, rim["r_inner"] + 4)
    cw_b_pos = layout.polar(c, cw_b, ch["r_inner"] - 4)
    rec = {
        "id": cfg["id"], "name": cfg["name"], "region": cfg["region"], "kind": "city",
        "center": _p3(f, *c), "radius": rim["r_outer"], "layout": "rings", "ring_center": list(map(_r2, c)),
        "tiers": _tiers_json(dist_tiers), "districts": _tiers_json(dist_tiers),
        "ramps": _ramps_json(cfg["ramp_bearings"], cfg["ramp_width"], cfg["ramp_length"]),
        "chasm": {"r_inner": ch["r_inner"], "r_outer": ch["r_outer"], "floor": ch["floor"]},
        "rim": {"r_inner": rim["r_inner"], "r_outer": rim["r_outer"], "height": rim["height"]},
        "gates": [
            {"id": "bridge", "bearing": cfg["bridge_bearing"], "position": _p3(f, *bridge_b), "width": 14.0},
            {"id": "causeway", "bearing": cw_b, "position": _p3(f, *cw_b_pos), "width": cfg["causeway_width"]},
        ],
        "bridges": ["omashu_great_bridge"],
        "causeway": {"a": _p3(f, *cw_a), "b": _p3(f, *cw_b_pos), "width": cfg["causeway_width"]},
        "palace": {"position": _p3(f, *c), "radius": dist_tiers[0]["r_outer"], "height": dist_tiers[0]["height"]},
    }
    bridge = {"id": "omashu_great_bridge", "name": "Great Bridge of Omashu", "kind": "stone",
              "a": _p3(f, *bridge_a, rim["height"]), "b": _p3(f, *bridge_b, gate_h), "width": 14.0,
              "deck_height": _r2((rim["height"] + gate_h) * 0.5)}
    outside = layout.polar(c, cfg["bridge_bearing"], rim["r_outer"] - 8)
    return {"city": rec, "bridges": [bridge], "anchors": {"omashu:bridge": outside,
                                                           "omashu:causeway": layout.polar(c, cw_b, rim["r_outer"] - 8)}}


# --------------------------------------------------------------------------------------
# Fire Nation capital + Crimson Harbor
# --------------------------------------------------------------------------------------

def build_fire_capital(f: Field) -> dict:
    cfg = layout.FIRE_CAPITAL
    c = cfg["center"]
    g = layout.fire_gorge()
    ramps = list(cfg["ramp_bearings"]) + [g["bearing"]]
    ring_layout(f, c, cfg["districts"], ramps, cfg["ramp_width"], cfg["ramp_length"], cfg["blend"], paved=1.0)
    g_in = layout.polar(c, g["bearing"], g["r_in"])
    g_out = layout.polar(c, g["bearing"], g["r_out"])
    rec = {
        "id": cfg["id"], "name": cfg["name"], "region": cfg["region"], "kind": "capital",
        "center": _p3(f, *c), "radius": cfg["rim_radius"], "layout": "rings", "ring_center": list(map(_r2, c)),
        "tiers": _tiers_json(cfg["districts"]), "districts": _tiers_json(cfg["districts"]),
        "ramps": _ramps_json(ramps, cfg["ramp_width"], cfg["ramp_length"]),
        "caldera": {"floor_radius": cfg["floor_radius"], "rim_radius": cfg["rim_radius"],
                    "rim_height_min": cfg["rim_height"][0], "rim_height_max": cfg["rim_height"][1]},
        "gorge": {"name": "The Dragon's Throat", "bearing": _r2(g["bearing"]), "width": g["width"],
                  "inner": _p3(f, *g_in), "outer": _p3(f, *g_out)},
        "gates": [{"id": "gorge", "bearing": _r2(g["bearing"]), "position": _p3(f, *g_in), "width": 24.0}],
        "palace": {"position": _p3(f, *c), "radius": cfg["districts"][0]["r_outer"],
                   "height": cfg["districts"][0]["height"]},
    }
    return {"city": rec, "anchors": {"fire_nation_capital:gorge_in": g_in, "fire_nation_capital:gorge_out": g_out}}


def build_fire_harbor(f: Field) -> dict:
    cfg = layout.FIRE_HARBOR
    k = cfg["harbor_center"]
    bay_r = cfg["bay_radius"]
    _carve_bay(f, k, bay_r, cfg["bay_depth"])
    g = layout.fire_gorge()

    def keep_out(r, b):
        return r < bay_r + 1.0

    ramps = list(cfg["ramp_bearings"]) + [g["gate_bearing_from_harbor"]]
    ring_layout(f, k, cfg["tiers"], ramps, cfg["ramp_width"], cfg["ramp_length"], cfg["blend"], keep_out=keep_out)
    upper = cfg["tiers"][-1]
    a0, a1 = upper["arc"]
    north = layout.polar(k, a1 - 6, (upper["r_inner"] + upper["r_outer"]) / 2)
    south = layout.polar(k, a0 + 6, (upper["r_inner"] + upper["r_outer"]) / 2)
    gates = [
        {"id": "gate", "bearing": _r2(g["gate_bearing_from_harbor"]), "position": _p3(f, *g["gate"]), "width": 20.0},
        {"id": "north", "bearing": _r2(a1 - 6), "position": _p3(f, *north), "width": 12.0},
        {"id": "south", "bearing": _r2(a0 + 6), "position": _p3(f, *south), "width": 12.0},
    ]
    rec = {
        "id": cfg["id"], "name": cfg["name"], "region": cfg["region"], "kind": "town",
        "center": _p3(f, *cfg["center"]), "radius": 420.0, "layout": "rings", "ring_center": list(map(_r2, k)),
        "tiers": _tiers_json(cfg["tiers"]),
        "ramps": _ramps_json(ramps, cfg["ramp_width"], cfg["ramp_length"]),
        "harbor": {"center": list(map(_r2, k)), "radius": bay_r, "floor": cfg["bay_depth"], "water_level": 0.0},
        "gates": gates,
    }
    return {"city": rec, "anchors": {"fire_harbor:gate": g["gate"], "fire_harbor:north": north,
                                     "fire_harbor:south": south}}
