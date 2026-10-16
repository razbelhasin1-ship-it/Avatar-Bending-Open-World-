class_name VegetationRules
extends RefCounted
## Ecology table + site sampling for scattered vegetation (thread-safe, deterministic).
##
## A "site" samples WorldData at a point (biome, region group, splat, ground hints, road, height,
## slope, water). `ecology(site)` returns densities (instances per 100 m²) and weighted species
## for three layers: trees, small (shrubs, ferns, logs) and rocks (rocks, ice, driftwood).
## Densities already include the avoidance rules: roads, settlement paving, farmland (trees),
## water, steep cliffs, snowlines.

## Region groups (palette/ecology): water tribe, earth kingdom, fire nation, air temple.
enum Group { WT, EK, FN, AT }

## Mirror of WorldData.Biome (constants must be compile-time; test_worldcontent checks they match).
enum Bio { OCEAN, BEACH, SNOW, ICE, TUNDRA, GRASSLAND, FOREST, FARMLAND, ROCK, MOUNTAIN, VOLCANIC, ASH, TEMPLE, CITY }

## [tree density, [[species, weight]...], small density, [...], rock density, [...]] per group/biome.
## Biomes not listed fall back to GRASSLAND of the group; CITY/OCEAN have nothing.
const TABLE := {
	Group.WT: {
		Bio.SNOW: [0.42, [[&"pine_snow", 1.0]], 0.35, [[&"shrub_snow", 1.0]], 0.35, [[&"rock_snow", 0.8], [&"ice_chunk", 0.2]]],
		Bio.TUNDRA: [0.28, [[&"pine_snow", 0.85], [&"snag", 0.15]], 0.5, [[&"shrub_snow", 1.0]], 0.3, [[&"rock_snow", 1.0]]],
		Bio.FOREST: [2.0, [[&"pine_snow", 1.0]], 0.4, [[&"shrub_snow", 1.0]], 0.15, [[&"rock_snow", 1.0]]],
		Bio.GRASSLAND: [0.35, [[&"pine_snow", 0.6], [&"fir", 0.4]], 0.4, [[&"shrub_snow", 0.6], [&"shrub", 0.4]], 0.25, [[&"rock_snow", 1.0]]],
		Bio.ICE: [0.0, [], 0.0, [], 0.22, [[&"ice_chunk", 0.65], [&"serac", 0.35]]],
		Bio.MOUNTAIN: [0.08, [[&"pine_snow", 1.0]], 0.0, [], 0.45, [[&"rock_snow", 1.0]]],
		Bio.ROCK: [0.06, [[&"pine_snow", 1.0]], 0.0, [], 0.6, [[&"rock_snow", 1.0]]],
		Bio.BEACH: [0.0, [], 0.0, [], 0.25, [[&"driftwood", 0.45], [&"rock_snow", 0.35], [&"ice_chunk", 0.2]]],
	},
	Group.EK: {
		Bio.FOREST: [2.1, [[&"oak", 0.48], [&"maple", 0.17], [&"fir", 0.2], [&"bamboo", 0.1], [&"cypress", 0.05]], 1.3, [[&"fern", 0.5], [&"shrub", 0.38], [&"log_moss", 0.12]], 0.18, [[&"rock_moss", 1.0]]],
		Bio.GRASSLAND: [0.2, [[&"oak", 0.5], [&"maple", 0.3], [&"cypress", 0.2]], 0.35, [[&"shrub", 1.0]], 0.12, [[&"rock", 0.7], [&"rock_moss", 0.3]]],
		Bio.FARMLAND: [0.025, [[&"oak", 0.5], [&"cypress", 0.5]], 0.0, [], 0.01, [[&"rock", 1.0]]],
		Bio.TUNDRA: [0.3, [[&"fir", 0.7], [&"snag", 0.3]], 0.3, [[&"shrub", 1.0]], 0.25, [[&"rock", 1.0]]],
		Bio.MOUNTAIN: [0.45, [[&"fir", 1.0]], 0.2, [[&"shrub", 1.0]], 0.45, [[&"rock", 1.0]]],
		Bio.ROCK: [0.06, [[&"fir", 0.6], [&"snag", 0.4]], 0.08, [[&"shrub", 1.0]], 0.7, [[&"rock", 1.0]]],
		Bio.SNOW: [0.25, [[&"pine_snow", 1.0]], 0.15, [[&"shrub_snow", 1.0]], 0.3, [[&"rock_snow", 1.0]]],
		Bio.BEACH: [0.03, [[&"oak", 1.0]], 0.0, [], 0.18, [[&"driftwood", 0.5], [&"rock", 0.5]]],
	},
	Group.FN: {
		Bio.FOREST: [3.0, [[&"tropical", 0.42], [&"banyan", 0.1], [&"palm", 0.26], [&"bamboo", 0.22]], 1.4, [[&"fern", 0.55], [&"shrub", 0.45]], 0.12, [[&"rock_moss", 1.0]]],
		Bio.GRASSLAND: [0.28, [[&"palm", 0.5], [&"tropical", 0.4], [&"banyan", 0.1]], 0.4, [[&"shrub", 0.7], [&"fern", 0.3]], 0.12, [[&"rock", 1.0]]],
		Bio.FARMLAND: [0.03, [[&"palm", 1.0]], 0.0, [], 0.01, [[&"rock", 1.0]]],
		Bio.BEACH: [0.3, [[&"palm", 1.0]], 0.0, [], 0.18, [[&"driftwood", 0.35], [&"rock", 0.65]]],
		Bio.VOLCANIC: [0.14, [[&"charred", 1.0]], 0.0, [], 0.9, [[&"lava_rock", 1.0]]],
		Bio.ASH: [0.16, [[&"charred", 0.85], [&"palm", 0.15]], 0.0, [], 0.45, [[&"lava_rock", 0.5], [&"rock", 0.5]]],
		Bio.MOUNTAIN: [0.1, [[&"charred", 0.4], [&"tropical", 0.6]], 0.1, [[&"shrub", 1.0]], 0.5, [[&"rock", 1.0]]],
		Bio.ROCK: [0.04, [[&"charred", 1.0]], 0.0, [], 0.7, [[&"rock", 0.7], [&"lava_rock", 0.3]]],
	},
	Group.AT: {
		Bio.FOREST: [1.6, [[&"fir", 0.6], [&"blossom", 0.25], [&"cypress", 0.15]], 0.7, [[&"shrub", 0.6], [&"fern", 0.4]], 0.2, [[&"rock", 1.0]]],
		Bio.GRASSLAND: [0.5, [[&"fir", 0.4], [&"blossom", 0.45], [&"cypress", 0.15]], 0.4, [[&"shrub", 1.0]], 0.2, [[&"rock", 1.0]]],
		Bio.TEMPLE: [0.4, [[&"blossom", 0.75], [&"cypress", 0.25]], 0.3, [[&"shrub", 1.0]], 0.05, [[&"rock", 1.0]]],
		Bio.MOUNTAIN: [0.3, [[&"fir", 1.0]], 0.1, [[&"shrub", 1.0]], 0.5, [[&"rock", 1.0]]],
		Bio.ROCK: [0.05, [[&"fir", 1.0]], 0.0, [], 0.7, [[&"rock", 1.0]]],
		Bio.SNOW: [0.2, [[&"pine_snow", 1.0]], 0.0, [], 0.35, [[&"rock_snow", 1.0]]],
		Bio.TUNDRA: [0.25, [[&"fir", 0.8], [&"snag", 0.2]], 0.2, [[&"shrub", 1.0]], 0.3, [[&"rock", 1.0]]],
		Bio.BEACH: [0.05, [[&"fir", 1.0]], 0.0, [], 0.2, [[&"driftwood", 0.5], [&"rock", 0.5]]],
	},
}


## Point sample of everything the rules need.
class Site:
	var x := 0.0
	var z := 0.0
	var h := 0.0
	var biome := 0
	var region: StringName = &"wilds"
	var group := 1
	var splat := Color()
	var ground := Color()
	var road := 0.0
	var slope := 0.0
	var normal := Vector3.UP
	var wet := false


static func group_of(region: StringName, x: float, z: float) -> int:
	match region:
		&"water_tribe": return Group.WT
		&"earth_kingdom": return Group.EK
		&"fire_nation": return Group.FN
		&"air_temple": return Group.AT
	if z < -1600.0:
		return Group.WT
	if x < -1500.0 and z > 800.0:
		return Group.FN
	if x > 1500.0 and z > 2300.0:
		return Group.AT
	return Group.EK


## Samples WorldData at x/z (thread-safe). `road_probe` also checks the road map 2.5 m around.
static func sample(x: float, z: float, road_probe: bool = true) -> Site:
	var s := Site.new()
	s.x = x
	s.z = z
	s.h = WorldData.get_height(x, z)
	s.biome = WorldData.get_biome(x, z)
	s.region = WorldData.get_region(x, z)
	s.group = group_of(s.region, x, z)
	s.splat = WorldData.get_splat(x, z)
	s.ground = WorldData.get_ground_hints(x, z)
	var r := WorldData.get_road(x, z)
	if road_probe and r < 0.05:
		r = maxf(r, maxf(maxf(WorldData.get_road(x + 2.5, z), WorldData.get_road(x - 2.5, z)),
				maxf(WorldData.get_road(x, z + 2.5), WorldData.get_road(x, z - 2.5))))
	s.road = r
	s.normal = WorldData.get_normal(x, z)
	s.slope = rad_to_deg(acos(clampf(s.normal.y, -1.0, 1.0)))
	var wh := WorldData.get_water_height(x, z)
	s.wet = wh > -INF and wh > s.h - 0.4
	return s


## {"tree": density, "trees": [[id, w]...], "small": d, "smalls": [...], "rock": d, "rocks": [...]}
## Densities are instances per 100 m² after avoidance rules.
static func ecology(s: Site) -> Dictionary:
	var none := {"tree": 0.0, "trees": [], "small": 0.0, "smalls": [], "rock": 0.0, "rocks": []}
	if s.wet or s.biome == Bio.CITY or s.biome == Bio.OCEAN or s.h < 0.4:
		return none
	var table: Dictionary = TABLE[s.group]
	var row: Array = table.get(s.biome, table.get(Bio.GRASSLAND, []))
	if row.is_empty():
		return none
	var tree := float(row[0])
	var small := float(row[2])
	var rock := float(row[4])
	var trees: Array = row[1]
	# lushness: open biomes need lush ground for trees; forests always qualify
	var lush := s.splat.b
	if s.biome != Bio.FOREST and s.biome != Bio.VOLCANIC and s.biome != Bio.ASH and s.biome != Bio.ICE:
		var need := 0.15 if s.group != Group.WT else 0.0
		tree *= smoothstep(need, need + 0.35, lush + (0.25 if s.biome == Bio.SNOW or s.biome == Bio.TUNDRA else 0.0))
		small *= smoothstep(0.05, 0.35, lush + 0.15)
	# temple terraces are paved: plants only in the lush garden patches
	if s.biome == Bio.TEMPLE:
		var garden := smoothstep(0.4, 0.65, s.splat.b)
		tree *= garden
		small *= garden
		rock *= 0.2
	# groves: open land gets clustered trees (terrain macro noise) instead of an even sprinkle
	var macro := TerrainPatterns.macro(s.x, s.z)
	if s.biome != Bio.FOREST:
		tree *= lerpf(0.12, 2.0, smoothstep(0.32, 0.72, macro))
	else:
		tree *= lerpf(0.75, 1.15, smoothstep(0.3, 0.7, macro))
	# taiga: the Earth Kingdom's arctic edge is snowy pine forest
	if s.group == Group.EK and s.biome == Bio.TUNDRA and s.z < -1300.0:
		trees = [[&"pine_snow", 0.8], [&"fir", 0.2]]
		tree = 1.1 * lerpf(0.3, 1.6, smoothstep(0.3, 0.7, macro))
	# snowline: above it conifers turn snowy, other trees vanish
	var snow := s.splat.r
	if s.group != Group.WT and snow > 0.25 and s.biome != Bio.SNOW:
		trees = [[&"pine_snow", 1.0]]
		tree *= 1.0 - smoothstep(0.35, 0.8, snow)
		small *= 0.3
	# rock cover
	var rocky := s.splat.g
	tree *= 1.0 - smoothstep(0.35, 0.8, rocky) * 0.85
	rock *= 1.0 + smoothstep(0.3, 0.8, rocky) * 1.5
	# slopes
	tree *= 1.0 - smoothstep(24.0, 35.0, s.slope)
	small *= 1.0 - smoothstep(28.0, 40.0, s.slope)
	rock *= 1.0 - smoothstep(42.0, 55.0, s.slope)
	# roads, settlement paving, farmland
	if s.road > 0.04:
		tree = 0.0
		small = 0.0
		rock *= 0.0 if s.road > 0.2 else 0.3
	var paving := s.ground.g
	if paving > 0.04:
		var k := 1.0 - smoothstep(0.04, 0.2, paving)
		tree *= k
		small *= k
		rock *= k
	if s.ground.b > 0.25 and s.biome != Bio.FARMLAND:
		tree *= 0.08
		small *= 0.1
	# snowy ground: snow-capped shrubs and rocks
	var smalls: Array = row[3]
	var rocks: Array = row[5]
	if snow > 0.3 and s.group != Group.WT:
		smalls = [[&"shrub_snow", 1.0]]
		rocks = [[&"rock_snow", 1.0]]
	# wetness favours bamboo in Earth Kingdom / Fire Nation forests
	var wetness := s.ground.a
	if (s.group == Group.EK or s.group == Group.FN) and wetness > 0.35 and s.biome == Bio.FOREST:
		trees = [[&"bamboo", 0.6]] + trees
	return {"tree": tree, "trees": trees, "small": small, "smalls": smalls, "rock": rock, "rocks": rocks}


## Weighted pick from [[id, weight], ...] with u in [0, 1).
static func pick(list: Array, u: float) -> StringName:
	var total := 0.0
	for e: Array in list:
		total += float(e[1])
	if total <= 0.0:
		return &""
	var t := u * total
	for e: Array in list:
		t -= float(e[1])
		if t <= 0.0:
			return e[0]
	return (list[list.size() - 1] as Array)[0]
