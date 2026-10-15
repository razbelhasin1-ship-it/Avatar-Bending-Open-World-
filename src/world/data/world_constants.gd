class_name WorldConstants
extends RefCounted
## Layout and encoding constants of the baked world (assets/world/).
##
## Must match tools/worldgen/wg/export.py and src/world/data/world_height.gdshaderinc.
## See docs/modules/worlddata.md for the full data format.

## World square: x/z in [WORLD_MIN, WORLD_MIN + WORLD_SIZE]. North is -Z, 1 unit = 1 m.
const WORLD_MIN := -4096.0
const WORLD_SIZE := 8192.0
const SEA_LEVEL := 0.0

## Heightmap: HEIGHTMAP_SIZE^2 texels of TEXEL_SIZE metres, texel (i, j) centre at
## x = WORLD_MIN + (i + 0.5) * TEXEL_SIZE, z = WORLD_MIN + (j + 0.5) * TEXEL_SIZE.
const HEIGHTMAP_SIZE := 4096
const TEXEL_SIZE := 2.0
## height = raw_u16 * HEIGHT_SCALE + HEIGHT_MIN  (both exact in float32).
const HEIGHT_MIN := -256.0
const HEIGHT_SCALE := 0.03125
const HEIGHT_MAX := HEIGHT_MIN + 65535.0 * HEIGHT_SCALE

## Auxiliary map resolutions (texels per side, all cover the whole world square).
const SPLAT_SIZE := 2048
const BIOME_SIZE := 2048
const REGION_SIZE := 1024
const ROADS_SIZE := 4096
const GROUND_SIZE := 2048

const DATA_DIR := "res://assets/world/"
const HEIGHTMAP_FILE := "heightmap.r16.zlib"
const JSON_FILE := "world.json"
const SPLAT_FILE := "splat.png"
const BIOME_FILE := "biome.png"
const REGION_FILE := "region.png"
const ROADS_FILE := "roads.png"
const GROUND_FILE := "ground.png"
const MAP_FILE := "map.jpg"

## Region ids by index in region.png (also listed in world.json "regions").
const REGION_IDS: Array[StringName] = [&"ocean", &"water_tribe", &"earth_kingdom", &"fire_nation", &"air_temple", &"wilds"]


## Continuous texel coordinate of a world coordinate on a map of `size` texels.
static func texel_coord(world: float, size: int) -> float:
	return (world - WORLD_MIN) * float(size) / WORLD_SIZE - 0.5


## Nearest texel index of a world coordinate on a map of `size` texels (clamped).
static func texel_index(world: float, size: int) -> int:
	return clampi(int(floor((world - WORLD_MIN) * float(size) / WORLD_SIZE)), 0, size - 1)


## World coordinate of the centre of texel `i` on a map of `size` texels.
static func texel_center(i: int, size: int) -> float:
	return WORLD_MIN + (float(i) + 0.5) * WORLD_SIZE / float(size)
