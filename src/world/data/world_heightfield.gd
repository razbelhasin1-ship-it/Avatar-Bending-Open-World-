class_name WorldHeightfield
extends RefCounted
## The baked 4096^2 heightmap (2 m texels) and every way of reading it.
##
## Storage: one PackedByteArray of little-endian uint16 samples, row-major (row = z index,
## north to south; column = x index, west to east). Sampling formula (identical in
## world_height.gdshaderinc, so CPU and GPU agree exactly at texel centres and to float32
## precision elsewhere):
##   u = clamp((x - WORLD_MIN) / TEXEL - 0.5, 0, N - 1),  v likewise for z
##   i0 = floor(u), j0 = floor(v), i1 = min(i0 + 1, N - 1), j1 = min(j0 + 1, N - 1)
##   fx = u - i0, fz = v - j0,  h(i, j) = raw(i, j) * HEIGHT_SCALE + HEIGHT_MIN
##   a = h00 + (h10 - h00) * fx,  b = h01 + (h11 - h01) * fx,  height = a + (b - a) * fz

const N := WorldConstants.HEIGHTMAP_SIZE
const TEXEL := WorldConstants.TEXEL_SIZE
const ORIGIN := WorldConstants.WORLD_MIN
const SCALE := WorldConstants.HEIGHT_SCALE
const HMIN := WorldConstants.HEIGHT_MIN

var raw: PackedByteArray = PackedByteArray()
var _image: Image = null
var _texture: ImageTexture = null
var _lod_textures: Dictionary = {}
var _mutex := Mutex.new()


## Loads and decompresses the heightmap. Returns an empty string or an error message.
func load_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing %s" % path
	var comp := FileAccess.get_file_as_bytes(path)
	if comp.is_empty():
		return "cannot read %s" % path
	var expected := N * N * 2
	var data := comp.decompress(expected, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != expected:
		return "heightmap decompressed to %d bytes, expected %d" % [data.size(), expected]
	raw = data
	return ""


func is_valid() -> bool:
	return raw.size() == N * N * 2


## Raw uint16 value of texel (i, j) (clamped to the map).
func raw_at(i: int, j: int) -> int:
	i = clampi(i, 0, N - 1)
	j = clampi(j, 0, N - 1)
	return raw.decode_u16((j * N + i) * 2)


## Height of texel (i, j) in metres.
func texel_height(i: int, j: int) -> float:
	return raw_at(i, j) * SCALE + HMIN


## Bilinear terrain height (see class doc for the exact formula).
func sample(x: float, z: float) -> float:
	var u := clampf((x - ORIGIN) / TEXEL - 0.5, 0.0, N - 1.0)
	var v := clampf((z - ORIGIN) / TEXEL - 0.5, 0.0, N - 1.0)
	var i0 := int(u)
	var j0 := int(v)
	var i1 := mini(i0 + 1, N - 1)
	var j1 := mini(j0 + 1, N - 1)
	var fx := u - i0
	var fz := v - j0
	var r0 := j0 * N
	var r1 := j1 * N
	var h00 := raw.decode_u16((r0 + i0) * 2) * SCALE + HMIN
	var h10 := raw.decode_u16((r0 + i1) * 2) * SCALE + HMIN
	var h01 := raw.decode_u16((r1 + i0) * 2) * SCALE + HMIN
	var h11 := raw.decode_u16((r1 + i1) * 2) * SCALE + HMIN
	var a := h00 + (h10 - h00) * fx
	var b := h01 + (h11 - h01) * fx
	return a + (b - a) * fz


## Heights on a regular grid, row-major (z rows of count_x samples): value[j * count_x + i]
## = sample(origin_x + i * step, origin_z + j * step). Texel-aligned grids (origin on a texel
## centre, step a multiple of TEXEL) skip interpolation and are ~3x faster.
func block(origin_x: float, origin_z: float, count_x: int, count_z: int, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(count_x, 0) * maxi(count_z, 0))
	if out.is_empty():
		return out
	var u0 := (origin_x - ORIGIN) / TEXEL - 0.5
	var v0 := (origin_z - ORIGIN) / TEXEL - 0.5
	var st := step / TEXEL
	var aligned := is_equal_approx(u0, roundf(u0)) and is_equal_approx(v0, roundf(v0)) \
			and is_equal_approx(st, roundf(st)) and st >= 1.0
	var k := 0
	if aligned:
		var iu := int(roundf(u0))
		var iv := int(roundf(v0))
		var s := int(roundf(st))
		for j in count_z:
			var jj := clampi(iv + j * s, 0, N - 1) * N
			for i in count_x:
				var ii := clampi(iu + i * s, 0, N - 1)
				out[k] = raw.decode_u16((jj + ii) * 2) * SCALE + HMIN
				k += 1
		return out
	for j in count_z:
		var z := origin_z + j * step
		for i in count_x:
			out[k] = sample(origin_x + i * step, z)
			k += 1
	return out


## The full heightmap as a FORMAT_R16 image (shares memory with `raw`; do not modify it).
func image_r16() -> Image:
	_mutex.lock()
	if _image == null and is_valid():
		_image = Image.create_from_data(N, N, false, Image.FORMAT_R16, raw)
	_mutex.unlock()
	return _image


## Region of the heightmap as a FORMAT_RF image of normalised heights (raw / 65535), ready for
## HeightMapShape3D.update_map_data_from_image(img, HEIGHT_MIN, HEIGHT_MAX). Texel-exact
## (one sample per 2 m texel); result heights match `texel_height` to ~1e-4 m (float32).
func collision_image(texel_x: int, texel_z: int, width: int, depth: int) -> Image:
	var img := image_r16()
	if img == null:
		return null
	var rect := Rect2i(texel_x, texel_z, width, depth).intersection(Rect2i(0, 0, N, N))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return null
	var reg := img.get_region(rect)
	reg.convert(Image.FORMAT_RF)
	return reg


## GPU texture of the raw heightmap: FORMAT_RG8, R = low byte, G = high byte of the uint16.
## Decode with world_height.gdshaderinc (texelFetch, never filtered sampling).
func texture() -> ImageTexture:
	_mutex.lock()
	if _texture == null and is_valid():
		var img := Image.create_from_data(N, N, false, Image.FORMAT_RG8, raw)
		_texture = ImageTexture.create_from_image(img)
	_mutex.unlock()
	return _texture


## Mipmapped float texture (FORMAT_RF, normalised: height = v * (HEIGHT_MAX - HEIGHT_MIN) + HEIGHT_MIN)
## at `size`^2 for far terrain, minimaps and effects that need filtered sampling.
func lod_texture(size: int) -> ImageTexture:
	_mutex.lock()
	if not _lod_textures.has(size) and is_valid():
		var img := Image.create_from_data(N, N, false, Image.FORMAT_R16, raw)
		img.convert(Image.FORMAT_RF)
		if size != N:
			img.resize(size, size, Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
		_lod_textures[size] = ImageTexture.create_from_image(img)
	var tex: ImageTexture = _lod_textures.get(size)
	_mutex.unlock()
	return tex
