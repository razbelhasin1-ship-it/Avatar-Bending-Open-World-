"""Hand-authored geography of the world (all coordinates in metres, x east, z south).

Everything that gives the world its identity lives here as plain data:
landmass outlines, nation territories, mountain zones, city layouts, villages,
lakes, POIs and road waypoints. The terrain/shape modules turn it into rasters.
"""
from __future__ import annotations

import math

# --------------------------------------------------------------------------------------
# Landmasses: polygons are (x, z) vertex lists; noise roughens them later.
# "bays" are subtracted ellipses: (cx, cz, rx, rz, rotation_deg).
# --------------------------------------------------------------------------------------

ARCTIC = [
    (-3650, -3800), (-3300, -3900), (-2800, -3950), (-2300, -3870), (-1800, -3920), (-1300, -3860),
    (-800, -3960), (-200, -3930), (300, -3880), (800, -3950), (1300, -3900), (1800, -3960),
    (2300, -3870), (2800, -3930), (3300, -3850), (3600, -3700), (3760, -3450), (3650, -3200),
    (3720, -3000), (3480, -2800), (3200, -2760), (2900, -2700), (2600, -2800), (2300, -2720),
    (2000, -2690), (1750, -2580), (1550, -2470), (1300, -2430), (1000, -2440), (760, -2500),
    (560, -2620), (380, -2680), (240, -2600), (160, -2545), (-300, -2525), (-760, -2545),
    (-900, -2620), (-1150, -2690), (-1400, -2740), (-1650, -2660), (-1900, -2700), (-2150, -2650),
    (-2400, -2730), (-2800, -2690), (-3100, -2800), (-3350, -2770), (-3650, -2920), (-3820, -3220),
    (-3760, -3560),
]

FROZEN_STRAIT = [
    (720, -2520), (860, -2300), (960, -2100), (1060, -1900), (1130, -1700), (1660, -1690),
    (1520, -1900), (1420, -2100), (1370, -2300), (1470, -2520),
]

EARTH_KINGDOM = [
    (-1300, -1500), (-1180, -1690), (-950, -1760), (-700, -1720), (-560, -1830), (-300, -1790),
    (-60, -1760), (200, -1690), (480, -1740), (760, -1700), (1000, -1660), (1300, -1640),
    (1700, -1680), (1950, -1820), (2200, -1760), (2550, -1700), (2800, -1800), (2950, -2020),
    (3200, -2080), (3400, -1900), (3450, -1640), (3750, -1480), (3990, -1180), (3920, -860),
    (4000, -560), (3880, -200), (3720, 80), (3930, 380), (3990, 700), (3850, 1000), (3520, 1120),
    (3300, 1330), (3420, 1580), (3880, 1720), (3960, 1900), (3830, 2100), (3880, 2350),
    (3960, 2700), (3850, 3100), (3920, 3400), (3760, 3780), (3420, 3950), (3050, 3900),
    (2700, 3960), (2300, 3900), (1950, 3960), (1600, 3860), (1380, 3700), (1200, 3450),
    (1130, 3200), (1090, 2950), (1180, 2780), (1000, 2580), (800, 2520), (600, 2380), (400, 2420),
    (150, 2330), (-50, 2240), (-250, 2170), (-560, 2180), (-760, 2020), (-900, 1820),
    (-1080, 1600), (-1150, 1420), (-1260, 1150), (-1380, 950), (-1450, 800), (-1330, 620),
    (-1300, 400), (-1420, 200), (-1350, -50), (-1200, -200), (-1350, -400), (-1700, -480),
    (-1880, -680), (-1650, -860), (-1420, -880), (-1300, -1100), (-1350, -1300),
]

FIRE_MAIN = [
    (-2750, 1450), (-2450, 1420), (-2200, 1560), (-1950, 1700), (-1760, 1940), (-1690, 2250),
    (-1760, 2450), (-1830, 2620), (-1800, 2800), (-1920, 2950), (-2080, 3180), (-2250, 3330),
    (-2500, 3560), (-2800, 3600), (-3050, 3680), (-3350, 3500), (-3600, 3250), (-3720, 3000),
    (-3800, 2700), (-3700, 2400), (-3600, 2150), (-3430, 1880), (-3200, 1650), (-3000, 1520),
]

# Islands described as (cx, cz, rx, rz, rotation_deg, kind)
ISLANDS = [
    (-1650, 3480, 430, 400, 0, "fire"),        # active volcano island
    (-3400, 1240, 560, 360, -20, "fire"),      # resort island (Ember-like)
    (-2700, -1300, 260, 200, 30, "wilds"),     # Serpent's Watch
    (-2050, 300, 300, 230, -10, "wilds"),      # Lantern Isle
    (2700, -2230, 210, 150, 15, "wilds"),      # Frostfang Isle
    (350, 2960, 240, 220, 0, "atoll"),         # Turtle-crab Atoll (ring)
    (-3600, -600, 220, 200, 0, "wilds"),       # Misty Crag
    (-1800, -2200, 160, 110, 40, "wilds"),     # Whalefall Skerries
]

# Subtracted water bodies (bays/coves): (cx, cz, rx, rz, rotation_deg)
BAYS = [
    (-300, -2620, 300, 300, 0),     # Northern Water Tribe bay (ringed by the city tiers)
    (-520, 1880, 300, 300, 0),      # Full Moon Bay
    (-1690, 2010, 160, 160, 0),     # Fire Nation harbor cove
    (-300, -1740, 160, 90, 0),      # Northreach harbor inlet (EK north port)
    (1080, 3020, 120, 160, 0),      # Air Temple foothills landing cove
]

# Places where coastline noise must stay small (cx, cz, radius)
PRECISE_COAST = [
    (-300, -2700, 760), (-450, 1800, 520), (-1750, 2030, 470), (-300, -1740, 320),
    (1080, 3020, 260), (1100, -2450, 450), (1400, -1700, 400), (-3350, 1350, 300),
    (1240, -2100, 420), (-3200, 1500, 260),
]

# --------------------------------------------------------------------------------------
# Nation territories (used for regions + per-nation terrain character)
# --------------------------------------------------------------------------------------

REGION_IDS = ["ocean", "water_tribe", "earth_kingdom", "fire_nation", "air_temple", "wilds"]
REGION_NAMES = {
    "ocean": "Open Sea",
    "water_tribe": "Northern Water Tribe",
    "earth_kingdom": "Earth Kingdom",
    "fire_nation": "Fire Nation",
    "air_temple": "Southern Air Temple",
    "wilds": "The Wilds",
}

# Air Temple territory boundary: everything of the Earth Kingdom landmass south of this line.
AIR_BOUNDARY = [(900, 2650), (1400, 2600), (1900, 2560), (2400, 2520), (3200, 2470), (4100, 2420)]

# --------------------------------------------------------------------------------------
# Elevation zones
# --------------------------------------------------------------------------------------

# Mountain ranges along spines: (polyline, half_width, peak_height, ridge_wavelength)
RANGES = [
    # Arctic
    ([(-3400, -3420), (-2700, -3520), (-2000, -3460)], 380, 330, 800),
    ([(-1550, -3420), (-950, -3600), (-300, -3700), (350, -3610), (950, -3480)], 430, 520, 900),
    ([(1350, -3480), (2000, -3560), (2700, -3430), (3350, -3240)], 420, 430, 850),
    # Earth Kingdom
    ([(2350, -1520), (2900, -1260), (3300, -920), (3620, -460), (3720, 0)], 540, 640, 1100),
    ([(-480, -1020), (-40, -720), (380, -420), (820, -160)], 600, 330, 900),
    ([(3420, 250), (3640, 760)], 340, 230, 800),
    ([(2900, -1850), (3200, -1950)], 260, 210, 600),
    ([(-1500, -560), (-1700, -680)], 220, 120, 500),
    ([(760, 2080), (1280, 2170), (1760, 2280)], 330, 170, 700),
    ([(-1150, -1460), (-920, -1160), (-1010, -720)], 300, 150, 700),
    ([(2500, 1250), (2900, 1500), (3300, 1700)], 330, 140, 700),
    ([(560, -1380), (1050, -1290), (1450, -1080)], 300, 120, 600),
    ([(2700, 760), (3000, 1020)], 280, 150, 600),
    ([(-820, -320), (-520, -20), (-330, 260)], 300, 105, 600),
    ([(1150, 980), (1480, 1120)], 240, 80, 500),
    # Southern Air Temple
    ([(1350, 3480), (1900, 3680), (2500, 3740), (3100, 3660), (3650, 3440)], 520, 680, 1000),
    ([(2620, 2930), (3100, 2820), (3500, 2860), (3800, 3060)], 380, 520, 900),
]

# Named peaks (cx, cz, height, radius) shaped as sharp ridged cones on top of zones
PEAKS = [
    (-300, -3720, 650, 330),       # Agnaak summit (polar)
    (3350, -1050, 800, 360),       # Cloudpiercer (EK NE)
    (2850, 3640, 1050, 420),       # Highwind summit (air)
    (2050, 3700, 960, 380),
    (3350, 3150, 980, 400),
    (3550, 3650, 880, 360),
    (1650, 3480, 760, 330),
    (3000, 2950, 820, 320),
    (60, -760, 430, 330),          # Omashu's flanking peaks
    (820, -60, 360, 300),
    (-80, -150, 330, 260),
]

# Polar ice shelves: (polygon) flat ice at ~20 m with sheer seaward cliffs
ICE_SHELVES = [
    [(1750, -2900), (3480, -2900), (3480, -2650), (1750, -2580)],
    [(-3700, -3000), (-2150, -3000), (-2150, -2600), (-3700, -2700)],
]

# Glaciers: smooth U-shaped ice valleys (polyline, width)
GLACIERS = [
    ([(-1550, -3600), (-1400, -3150), (-1260, -2720)], 230),
    ([(2700, -3600), (2650, -3150), (2620, -2800)], 260),
    ([(380, -3550), (560, -3150), (700, -2650)], 200),
    ([(-2600, -3650), (-2650, -3200), (-2700, -2850)], 220),
]

# Crevasse field (sharp narrow ridges): polygon
CREVASSE_FIELDS = [
    [(900, -3250), (2150, -3250), (2150, -2780), (900, -2700)],
]

# Cultivated land (polygons); only gentle slopes inside become FARMLAND
FARMLAND_ZONES = [
    [(640, -380), (1240, -420), (1330, 120), (1300, 760), (980, 940), (640, 820), (560, 260)],   # west of Ba Sing Se
    [(-120, 1380), (260, 1330), (330, 1620), (40, 1700), (-160, 1560)],                         # behind Full Moon Bay
    [(-560, -1560), (-60, -1580), (0, -1380), (-480, -1330)],                                    # Northreach fields
    [(-2620, 3130), (-2160, 3120), (-2120, 3420), (-2560, 3470)],                                # Ashleaf tea terraces
    [(2650, 380), (3150, 330), (3250, 720), (2780, 760)],                                        # eastern fields
]

# Lava fields (VOLCANIC) and ash plains (ASH) in the Fire Nation
LAVA_FIELDS = [
    [(-3420, 2900), (-3000, 2860), (-2820, 3200), (-2900, 3460), (-3300, 3420)],
]
ASH_PLAINS = [
    [(-2480, 1760), (-2180, 1800), (-2140, 2000), (-2420, 2020)],
]

# SW Earth Kingdom rocky plateaus (terraced mesas): (cx, cz, radius)
PLATEAUS = [(-500, 750, 820)]

# Canyons carved into the plateaus: (polyline, width, depth)
CANYONS = [
    ([(420, 180), (150, 420), (-150, 520), (-420, 760), (-700, 820), (-980, 1050), (-1400, 1180)], 70, 85),
    ([(-150, 520), (-280, 260), (-520, 120), (-900, 60), (-1400, 30)], 50, 60),
]

# --------------------------------------------------------------------------------------
# Cities. Ring/tier layouts are evaluated identically by the generator (to flatten the
# terrain) and exported to world.json for the settlement builders.
# --------------------------------------------------------------------------------------

def _deg(a: float) -> float:
    return math.radians(a)


# All "bearing" values are degrees from north, clockwise (0 = -Z, 90 = +X, 180 = +Z, -90 = -X).

# Northern Water Tribe: tiers ring the circular bay (the city's harbour); the sea wall closes the
# bay mouth to the south and the palace tier crowns the northern apex.
NWT = {
    "id": "northern_water_tribe",
    "name": "Northern Water Tribe",
    "region": "water_tribe",
    "center": (-300, -3010),
    "harbor_center": (-300, -2620),
    "bay_radius": 300.0,
    "bay_depth": -10.0,
    "tiers": [
        {"id": "harbor", "name": "Harbor Tier", "r_inner": 300, "r_outer": 372, "height": 2.5, "arc": (-120, 120)},
        {"id": "middle", "name": "Middle Tier", "r_inner": 372, "r_outer": 470, "height": 16.0, "arc": (-112, 112)},
        {"id": "upper", "name": "Upper Tier", "r_inner": 470, "r_outer": 562, "height": 32.0, "arc": (-96, 96)},
        {"id": "palace", "name": "Palace Tier", "r_inner": 562, "r_outer": 700, "height": 54.0, "arc": (-40, 40)},
    ],
    "ramp_bearings": [0.0, -55.0, 55.0, -100.0, 100.0],
    "ramp_width": 16.0,
    "ramp_length": 48.0,
    "blend": 150.0,
    "gates": [{"id": "east", "bearing": 112.0, "radius": 421.0}, {"id": "west", "bearing": -112.0, "radius": 421.0}],
    "palace": {"bearing": 0.0, "radius": 640.0, "platform_radius": 48.0, "height": 58.0},
    "canal_bearings": [-75.0, -30.0, 30.0, 75.0],
    "ring_canal": {"radius": 425.0, "arc": (-100.0, 100.0)},
    "canal_width": 9.0,
    "canal_levels": {"harbor": 0.0, "middle": 14.2},
    "sea_wall": {
        "points": [(-650, -2468), (-480, -2436), (-300, -2426), (-120, -2436), (50, -2468)],
        "height": 42.0, "thickness": 24.0, "base": -7.0,
        "gate": {"center": (-300, -2426), "width": 46.0},
    },
    "spirit_oasis": {"bearing": -24.0, "radius": 628.0, "court_radius": 36.0, "pond_radius": 10.5, "pond_depth": 1.6},
}

BA_SING_SE = {
    "id": "ba_sing_se",
    "name": "Ba Sing Se",
    "region": "earth_kingdom",
    "center": (2000, 200),
    "base_height": 60.0,
    "districts": [
        {"id": "palace", "name": "Royal Palace", "r_inner": 0, "r_outer": 58, "height": 91.0},
        {"id": "upper_ring", "name": "Upper Ring", "r_inner": 58, "r_outer": 150, "height": 86.0},
        {"id": "middle_ring", "name": "Middle Ring", "r_inner": 150, "r_outer": 262, "height": 67.0},
        {"id": "lower_ring", "name": "Lower Ring", "r_inner": 262, "r_outer": 380, "height": 60.0},
        {"id": "agrarian", "name": "Agrarian Zone", "r_inner": 380, "r_outer": 700, "height": 58.0},
    ],
    "walls": [
        {"id": "outer_wall", "name": "Outer Wall", "radius": 700.0, "height": 38.0, "thickness": 22.0},
        {"id": "inner_wall", "name": "Inner Wall", "radius": 380.0, "height": 26.0, "thickness": 14.0},
        {"id": "middle_wall", "name": "Middle Ring Wall", "radius": 262.0, "height": 12.0, "thickness": 6.0},
        {"id": "upper_wall", "name": "Upper Ring Wall", "radius": 150.0, "height": 9.0, "thickness": 5.0},
    ],
    # Gate bearings in degrees from north, clockwise (0 = north/-Z, 90 = east/+X)
    "gates": [
        {"id": "north", "bearing": 0.0}, {"id": "east", "bearing": 90.0},
        {"id": "south", "bearing": 180.0}, {"id": "west", "bearing": 270.0},
        {"id": "southwest", "bearing": 228.0},
    ],
    "ramp_width": 22.0,
    "ramp_length": 60.0,
    "blend": 420.0,
}

OMASHU = {
    "id": "omashu",
    "name": "Omashu",
    "region": "earth_kingdom",
    "center": (380, -420),
    "districts": [
        {"id": "palace", "name": "King's Summit", "r_inner": 0, "r_outer": 62, "height": 222.0},
        {"id": "high", "name": "High Terraces", "r_inner": 62, "r_outer": 132, "height": 198.0},
        {"id": "market", "name": "Market Terraces", "r_inner": 132, "r_outer": 212, "height": 178.0},
        {"id": "gate", "name": "Gate Terrace", "r_inner": 212, "r_outer": 300, "height": 160.0},
    ],
    "chasm": {"r_inner": 300, "r_outer": 352, "floor": 92.0},
    "rim": {"r_inner": 352, "r_outer": 410, "height": 162.0},
    "bridge_bearing": 90.0,     # great bridge over the chasm, toward Ba Sing Se
    "causeway_bearing": 212.0,  # natural rock causeway across the chasm (always walkable)
    "causeway_width": 16.0,
    "ramp_bearings": [90.0, 212.0, 330.0],
    "ramp_width": 14.0,
    "ramp_length": 44.0,
    "blend": 150.0,
}

FIRE_CAPITAL = {
    "id": "fire_nation_capital",
    "name": "Fire Nation Capital",
    "region": "fire_nation",
    "center": (-2600, 2600),
    "districts": [
        {"id": "palace", "name": "Royal Palace", "r_inner": 0, "r_outer": 55, "height": 146.0},
        {"id": "palace_terrace", "name": "Palace Terrace", "r_inner": 55, "r_outer": 145, "height": 138.0},
        {"id": "noble", "name": "Noble Quarter", "r_inner": 145, "r_outer": 265, "height": 124.0},
        {"id": "lower_city", "name": "Lower City", "r_inner": 265, "r_outer": 405, "height": 112.0},
    ],
    "floor_radius": 405.0,
    "rim_radius": 505.0,
    "rim_height": (255.0, 320.0),
    "ramp_bearings": [0.0, 120.0, 240.0],    # the gorge bearing is added at runtime
    "ramp_width": 18.0,
    "ramp_length": 50.0,
    "blend": 24.0,
}

FIRE_HARBOR = {
    "id": "fire_harbor",
    "name": "Crimson Harbor",
    "region": "fire_nation",
    "center": (-1960, 2060),
    "harbor_center": (-1690, 2010),
    "bay_radius": 160.0,
    "bay_depth": -9.0,
    "tiers": [
        {"id": "quay", "name": "Quayside", "r_inner": 160, "r_outer": 225, "height": 3.0, "arc": (-172, -8)},
        {"id": "lower", "name": "Lantern Steps", "r_inner": 225, "r_outer": 285, "height": 16.0, "arc": (-168, -12)},
        {"id": "middle", "name": "Harbor Market", "r_inner": 285, "r_outer": 340, "height": 32.0, "arc": (-160, -20)},
        {"id": "upper", "name": "Admiralty Tier", "r_inner": 340, "r_outer": 400, "height": 52.0, "arc": (-150, -30)},
    ],
    "ramp_bearings": [-120.0, -90.0, -45.0],
    "ramp_width": 12.0,
    "ramp_length": 40.0,
    "blend": 90.0,
    "gate_radius": 372.0,     # gate bearing points at the caldera (the gorge road arrives there)
}

AIR_TEMPLE = {
    "id": "southern_air_temple",
    "name": "Southern Air Temple",
    "region": "air_temple",
    "center": (2500, 3350),
    "tiers": [
        {"id": "sanctum", "name": "Sanctum Spire", "r_inner": 0, "r_outer": 46, "height": 822.0},
        {"id": "temple", "name": "Temple Courtyard", "r_inner": 46, "r_outer": 112, "height": 802.0},
        {"id": "terrace", "name": "Prayer Terraces", "r_inner": 112, "r_outer": 162, "height": 782.0, "arc": (-150, 150)},
        {"id": "landing", "name": "Bison Landing", "r_inner": 162, "r_outer": 214, "height": 762.0, "arc": (-62, 62)},
    ],
    "ramp_bearings": [-30.0, 25.0, 140.0, 220.0],
    "ramp_width": 12.0,
    "ramp_length": 34.0,
    "blend": 10.0,
    "spire_drop": 300.0,     # metres the cliffs fall below the lowest terrace
}

# Air Temple pass: switchback face from the foothills to the Bison Landing
AIR_PASS = {
    "bottom": (2050, 2480),
    "top": (2395, 3160),
    "bottom_height": 175.0,
    "top_height": 762.0,
    "face_width": 420.0,
    "legs": 11,
    "road_width": 7.0,
}

# --------------------------------------------------------------------------------------
# Villages / small towns (flattened pads)
# --------------------------------------------------------------------------------------

VILLAGES = [
    {"id": "full_moon_bay", "name": "Full Moon Bay", "region": "earth_kingdom", "kind": "port_town",
     "center": (-300, 1700), "radius": 150, "height": 6.0, "terraces": [(150, 6.0), (230, 16.0)]},
    {"id": "northreach", "name": "Northreach Harbor", "region": "earth_kingdom", "kind": "port_town",
     "center": (-300, -1610), "radius": 95, "height": 5.0, "terraces": [(95, 5.0), (150, 12.0)]},
    {"id": "millet_hollow", "name": "Millet Hollow", "region": "earth_kingdom", "kind": "farming_village",
     "center": (860, 420), "radius": 90, "height": None, "terraces": []},
    {"id": "cedar_rest", "name": "Cedar Rest", "region": "earth_kingdom", "kind": "forest_village",
     "center": (760, 1420), "radius": 80, "height": None, "terraces": []},
    {"id": "saltspark", "name": "Saltspark Village", "region": "fire_nation", "kind": "fishing_village",
     "center": (-3560, 2660), "radius": 80, "height": 4.0, "terraces": [(80, 4.0)]},
    {"id": "ashleaf", "name": "Ashleaf Terraces", "region": "fire_nation", "kind": "tea_village",
     "center": (-2350, 3300), "radius": 85, "height": None, "terraces": []},
    {"id": "sunflare_resort", "name": "Sunflare Isle Resort", "region": "fire_nation", "kind": "resort",
     "center": (-3300, 1390), "radius": 90, "height": 6.0, "terraces": [(90, 6.0), (140, 12.0)]},
    {"id": "foothill_landing", "name": "Foothills Landing", "region": "air_temple", "kind": "dock",
     "center": (1225, 3020), "radius": 60, "height": 4.0, "terraces": [(60, 4.0)]},
    {"id": "frostwind_camp", "name": "Strait Wardens' Camp", "region": "wilds", "kind": "camp",
     "center": (1270, -2080), "radius": 45, "height": None, "terraces": []},
]

# --------------------------------------------------------------------------------------
# Lakes: (id, name, cx, cz, radius, level or None(auto), depth, frozen, region)
# --------------------------------------------------------------------------------------

LAKES = [
    ("frozen_moon_lake", "Lake of the Pale Moon", -1900, -3240, 230, None, 6.0, True),
    ("frozen_lake_east", "Silent Ice Lake", 1520, -3460, 190, None, 5.0, True),
    ("frozen_lake_west", "Narwhal Mere", -2950, -3180, 250, None, 5.0, True),
    ("ice_flats", "The Ice Flats", -920, -2960, 120, None, 3.0, True),
    ("moonmirror_lake", "Moonmirror Lake", 980, -1060, 210, None, 9.0, False),
    ("yuelan_lake", "Lake Yuelan", 2420, -180, 110, 58.0, 7.0, False),
    ("jade_basin", "Jade Basin", 1300, 1800, 170, None, 8.0, False),
    ("cloud_tarn", "Cloud Tarn", 3080, -860, 120, None, 10.0, False),
    ("ember_tarn", "Ember Tarn", -3120, 2980, 120, None, 6.0, False),
    ("sky_cirque", "Sky Cirque Pool", 3080, 3420, 110, None, 8.0, False),
]

# --------------------------------------------------------------------------------------
# Roads: named waypoint chains; legs between waypoints are path-found on the terrain.
# A waypoint can be a coordinate or the name of a city gate ("ba_sing_se:west").
# --------------------------------------------------------------------------------------

ROADS = [
    {"id": "bss_full_moon_bay", "name": "Old Moon Road", "kind": "main",
     "waypoints": ["ba_sing_se:southwest", (1040, 610), "village:millet_hollow", (780, 980), "village:cedar_rest",
                   (420, 1560), (40, 1690), "village:full_moon_bay"]},
    {"id": "bss_omashu", "name": "King's Highway", "kind": "main",
     "waypoints": ["ba_sing_se:west", (1150, 160), "village:millet_hollow", (1160, -210), "omashu:bridge"]},
    {"id": "bss_north", "name": "Tundra Road", "kind": "main",
     "waypoints": ["ba_sing_se:north", (1900, -760), (1640, -1150), (1430, -1560), (1320, -1880),
                   "village:frostwind_camp", (1140, -2330), (620, -2590), "northern_water_tribe:east"]},
    {"id": "bss_air_pass", "name": "Pass of a Thousand Steps", "kind": "main",
     "waypoints": ["ba_sing_se:south", (2010, 1300), (2020, 2000), "air_pass:bottom"]},
    {"id": "bss_east", "name": "Eastern Trade Road", "kind": "minor",
     "waypoints": ["ba_sing_se:east", (2950, 300), (3450, 700), (3700, 1150)]},
    {"id": "omashu_northreach", "name": "Northreach Trail", "kind": "minor",
     "waypoints": ["omashu:bridge", (840, -700), (520, -1180), (60, -1460), "village:northreach"]},
    {"id": "fn_capital_harbor", "name": "Dragon's Throat Road", "kind": "main",
     "waypoints": ["fire_nation_capital:gorge_in", "fire_nation_capital:gorge_out", "fire_harbor:gate"]},
    {"id": "fn_harbor_ashleaf", "name": "Ashleaf Road", "kind": "minor",
     "waypoints": ["fire_harbor:south", (-1880, 2560), (-2000, 2950), (-2150, 3150), "village:ashleaf"]},
    {"id": "fn_harbor_saltspark", "name": "West Rim Trail", "kind": "minor",
     "waypoints": ["fire_harbor:north", (-2250, 1760), (-2850, 1760), (-3350, 2150), "village:saltspark"]},
    {"id": "resort_paths", "name": "Sunflare Promenade", "kind": "minor",
     "waypoints": ["village:sunflare_resort", (-3560, 1180), (-3700, 1130)]},
    {"id": "air_landing_road", "name": "Landing Path", "kind": "minor",
     "waypoints": ["village:foothill_landing", (1420, 2760), "air_pass:bottom"]},
]

# --------------------------------------------------------------------------------------
# Ports and ferries
# --------------------------------------------------------------------------------------

PORTS = [
    {"id": "port_full_moon_bay", "name": "Full Moon Bay Docks", "region": "earth_kingdom", "settlement": "full_moon_bay",
     "dock": (-410, 1800)},
    {"id": "port_northreach", "name": "Northreach Harbor", "region": "earth_kingdom", "settlement": "northreach",
     "dock": (-300, -1700)},
    {"id": "port_water_tribe", "name": "Water Tribe Harbor", "region": "water_tribe", "settlement": "northern_water_tribe",
     "dock": (-300, -2795)},
    {"id": "port_crimson_harbor", "name": "Crimson Harbor Piers", "region": "fire_nation", "settlement": "fire_harbor",
     "dock": (-1735, 2140)},
    {"id": "port_foothill_landing", "name": "Foothills Landing", "region": "air_temple", "settlement": "foothill_landing",
     "dock": (1130, 3020)},
    {"id": "port_sunflare", "name": "Sunflare Isle Pier", "region": "fire_nation", "settlement": "sunflare_resort",
     "dock": (-3220, 1520)},
]

FERRIES = [
    ("ferry_moon_to_crimson", "port_full_moon_bay", "port_crimson_harbor"),
    ("ferry_northreach_to_tribe", "port_northreach", "port_water_tribe"),
    ("ferry_moon_to_landing", "port_full_moon_bay", "port_foothill_landing"),
    ("ferry_crimson_to_sunflare", "port_crimson_harbor", "port_sunflare"),
]


# --------------------------------------------------------------------------------------
# Geometry helpers shared by the generator stages
# --------------------------------------------------------------------------------------

def bearing_vec(bearing_deg: float) -> tuple[float, float]:
    """Unit (x, z) direction for a bearing in degrees from north, clockwise."""
    b = math.radians(bearing_deg)
    return math.sin(b), -math.cos(b)


def polar(center, bearing_deg: float, r: float) -> tuple[float, float]:
    vx, vz = bearing_vec(bearing_deg)
    return center[0] + vx * r, center[1] + vz * r


def bearing_of(dx: float, dz: float) -> float:
    return math.degrees(math.atan2(dx, -dz))


def fire_gorge() -> dict:
    """The Dragon's Throat: gorge from the caldera floor to the harbour's upper-tier gate."""
    c = FIRE_CAPITAL["center"]
    k = FIRE_HARBOR["harbor_center"]
    to_c = bearing_of(c[0] - k[0], c[1] - k[1])
    gate = polar(k, to_c, FIRE_HARBOR["gate_radius"])
    bearing = bearing_of(gate[0] - c[0], gate[1] - c[1])
    r_gate = math.hypot(gate[0] - c[0], gate[1] - c[1])
    return {
        "bearing": bearing,
        "r_in": FIRE_CAPITAL["floor_radius"] + 12.0,
        "r_out": r_gate - 18.0,
        "floor_in": FIRE_CAPITAL["districts"][-1]["height"],
        "floor_out": FIRE_HARBOR["tiers"][-1]["height"],
        "gate": gate,
        "gate_bearing_from_harbor": to_c,
        "width": 34.0,
    }
