"""World generator package for Avatar: The Four Nations.

Modules:
    grid      world <-> grid coordinate helpers, resampling, windows
    noise     deterministic vectorised gradient noise (fBm, ridged, warp)
    layout    hand-authored geography: landmasses, zones, cities, POIs, roads
    terrain   base elevation composition (coasts, sea floor, mountains, volcanoes)
    erosion   vectorised droplet hydraulic erosion + thermal erosion
    shapes    shaped features applied at full resolution (cities, roads, lakes...)
    routes    road and ferry path finding
    classify  regions, biomes, splat weights, wetness
    mapart    painterly parchment map illustration
    export    file writers (heightmap, PNG maps, world.json, Godot .import files)
"""
