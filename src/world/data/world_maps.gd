class_name WorldMaps
extends RefCounted
## Auxiliary baked rasters: biome ids, splat weights, regions, roads and ground hints.
##
## All maps cover the whole world square with texel-centre convention; lookups use the
## nearest texel (biome/region ids must never be interpolated). Files are plain PNGs marked
## importer="keep" so the exact bytes ship with the game.
##   biome.png  2048^2 L8    WorldData.Biome
##   splat.png  2048^2 RGBA  R snow/ice, G rock/cliff, B lush grass/forest floor, A sand/ash
##   region.png 1024^2 L8    index into WorldConstants.REGION_IDS
##   roads.png  4096^2 L8    road coverage 0..255
##   ground.png 2048^2 RGBA  R paved road, G settlement paving, B farmland, A wetness

var biome: PackedByteArray = PackedByteArray()
var splat: PackedByteArray = PackedByteArray()
var region: PackedByteArray = PackedByteArray()
var roads: PackedByteArray = PackedByteArray()
var ground: PackedByteArray = PackedByteArray()

var _images: Dictionary = {}     # name -> Image
var _textures: Dictionary = {}   # name -> ImageTexture
var _mutex := Mutex.new()

const _SPECS := {
	"biome": [WorldConstants.BIOME_FILE, WorldConstants.BIOME_SIZE, Image.FORMAT_L8],
	"splat": [WorldConstants.SPLAT_FILE, WorldConstants.SPLAT_SIZE, Image.FORMAT_RGBA8],
	"region": [WorldConstants.REGION_FILE, WorldConstants.REGION_SIZE, Image.FORMAT_L8],
	"roads": [WorldConstants.ROADS_FILE, WorldConstants.ROADS_SIZE, Image.FORMAT_L8],
	"ground": [WorldConstants.GROUND_FILE, WorldConstants.GROUND_SIZE, Image.FORMAT_RGBA8],
}


static func map_names() -> Array:
	return _SPECS.keys()


## Loads one map by name (thread-safe; maps can load in parallel). Returns "" or an error.
func load_map(map_name: String, dir: String) -> String:
	var spec: Array = _SPECS[map_name]
	var path := dir.path_join(spec[0])
	if not FileAccess.file_exists(path):
		return "missing %s" % path
	var img := Image.new()
	var err := img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	if err != OK:
		return "cannot decode %s (%s)" % [path, error_string(err)]
	var size: int = spec[1]
	if img.get_width() != size or img.get_height() != size:
		return "%s is %dx%d, expected %d" % [path, img.get_width(), img.get_height(), size]
	if img.get_format() != spec[2]:
		img.convert(spec[2])
	_mutex.lock()
	_images[map_name] = img
	set(map_name, img.get_data())
	_mutex.unlock()
	return ""


func is_valid() -> bool:
	return biome.size() == WorldConstants.BIOME_SIZE * WorldConstants.BIOME_SIZE \
			and region.size() == WorldConstants.REGION_SIZE * WorldConstants.REGION_SIZE


static func _idx(x: float, z: float, size: int) -> int:
	return WorldConstants.texel_index(z, size) * size + WorldConstants.texel_index(x, size)


func biome_at(x: float, z: float) -> int:
	return biome[_idx(x, z, WorldConstants.BIOME_SIZE)]


func region_index_at(x: float, z: float) -> int:
	return region[_idx(x, z, WorldConstants.REGION_SIZE)]


## Road coverage 0..1 (bilinear: roads are thin, nearest texel would alias).
func road_at(x: float, z: float) -> float:
	if roads.is_empty():
		return 0.0
	var n := WorldConstants.ROADS_SIZE
	var u := clampf(WorldConstants.texel_coord(x, n), 0.0, n - 1.0)
	var v := clampf(WorldConstants.texel_coord(z, n), 0.0, n - 1.0)
	var i0 := int(u)
	var j0 := int(v)
	var i1 := mini(i0 + 1, n - 1)
	var j1 := mini(j0 + 1, n - 1)
	var fx := u - i0
	var fz := v - j0
	var a := lerpf(roads[j0 * n + i0], roads[j0 * n + i1], fx)
	var b := lerpf(roads[j1 * n + i0], roads[j1 * n + i1], fx)
	return lerpf(a, b, fz) / 255.0


## Splat weights as Color(snow, rock, lush, sand_ash).
func splat_at(x: float, z: float) -> Color:
	if splat.is_empty():
		return Color(0, 0, 0.6, 0)
	var k := _idx(x, z, WorldConstants.SPLAT_SIZE) * 4
	return Color(splat[k] / 255.0, splat[k + 1] / 255.0, splat[k + 2] / 255.0, splat[k + 3] / 255.0)


## Ground hints as Color(paved_road, settlement, farmland, wetness).
func ground_at(x: float, z: float) -> Color:
	if ground.is_empty():
		return Color(0, 0, 0, 0)
	var k := _idx(x, z, WorldConstants.GROUND_SIZE) * 4
	return Color(ground[k] / 255.0, ground[k + 1] / 255.0, ground[k + 2] / 255.0, ground[k + 3] / 255.0)


func image(map_name: String) -> Image:
	return _images.get(map_name)


## GPU texture of a map (created on first request). Data maps (biome/region) should be read
## with texelFetch or filter_nearest; splat/roads/ground can be filtered.
func texture(map_name: String) -> ImageTexture:
	_mutex.lock()
	if not _textures.has(map_name) and _images.has(map_name):
		var img: Image = (_images[map_name] as Image).duplicate()
		if map_name in ["splat", "roads", "ground"]:
			img.generate_mipmaps()
		_textures[map_name] = ImageTexture.create_from_image(img)
	var tex: ImageTexture = _textures.get(map_name)
	_mutex.unlock()
	return tex
