class_name TerrainPatterns
extends RefCounted
## CPU mirror of the terrain shader's large-scale patterns, so scattered content matches what the
## ground is painted with (assets/shaders/world/terrain.gdshader):
## * macro noise (noise_tex at 1/900 and 1/140 m) — vegetation hue drift,
## * farm plots: floor((xz + (nz_mid.rg - 0.5) * 18) / (46, 34)) with wc_hash12 crop types and
##   darker borders — hedges and crops follow them,
## * the regional lush palettes (GRASS_D/L, forest, tundra) — grass tint.
## Thread-safe after load() (read-only data). Falls back to flat noise (0.5) without the texture.

const NOISE_PATH := "res://assets/textures/world/noise.png"
const PLOT_SIZE := Vector2(46.0, 34.0)

## sRGB palettes copied from terrain.gdshader (index: 0 water tribe, 1 earth kingdom, 2 fire nation, 3 air temple)
const GRASS_D: Array[Color] = [Color(0.40, 0.44, 0.35), Color(0.27, 0.43, 0.15), Color(0.09, 0.29, 0.13), Color(0.28, 0.44, 0.26)]
const GRASS_L: Array[Color] = [Color(0.60, 0.61, 0.48), Color(0.60, 0.70, 0.29), Color(0.27, 0.52, 0.21), Color(0.55, 0.68, 0.41)]
const ROCK_L: Array[Color] = [Color(0.58, 0.64, 0.72), Color(0.70, 0.61, 0.48), Color(0.38, 0.31, 0.29), Color(0.72, 0.66, 0.58)]
const ROCK_D: Array[Color] = [Color(0.27, 0.32, 0.41), Color(0.38, 0.32, 0.27), Color(0.13, 0.11, 0.11), Color(0.37, 0.34, 0.33)]

static var _data := PackedByteArray()
static var _size := 0
static var _loaded := false
static var _mutex := Mutex.new()


## Loads the noise texture data once (main thread preferred; safe to call repeatedly).
static func load_data() -> void:
	if _loaded:
		return
	_mutex.lock()
	if not _loaded:
		var img: Image = null
		var tex := load(NOISE_PATH) as Texture2D
		if tex and DisplayServer.get_name() != "headless":
			img = tex.get_image()
		if img == null or img.is_empty():
			img = Image.load_from_file(ProjectSettings.globalize_path(NOISE_PATH))
		if img and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			_size = img.get_width()
			_data = img.get_data()
		_loaded = true
	_mutex.unlock()


static func has_noise() -> bool:
	return _size > 0


## Bilinear, wrapping sample of noise_tex at uv (like texture() with repeat + linear filter, mip 0).
static func noise(u: float, v: float) -> Color:
	if _size == 0:
		return Color(0.5, 0.5, 0.5, 0.5)
	var n := _size
	var fx := u * n - 0.5
	var fy := v * n - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - x0
	var ty := fy - y0
	var x1 := posmod(x0 + 1, n)
	var y1 := posmod(y0 + 1, n)
	x0 = posmod(x0, n)
	y0 = posmod(y0, n)
	var a := _px(x0, y0)
	var b := _px(x1, y0)
	var c := _px(x0, y1)
	var d := _px(x1, y1)
	return a.lerp(b, tx).lerp(c.lerp(d, tx), ty)


static func _px(x: int, y: int) -> Color:
	var k := (y * _size + x) * 4
	return Color(_data[k] / 255.0, _data[k + 1] / 255.0, _data[k + 2] / 255.0, _data[k + 3] / 255.0)


## Terrain "macro" value (0..1): nz_big.r * 0.55 + nz_mid.r * 0.45.
static func macro(x: float, z: float) -> float:
	return noise(x / 900.0, z / 900.0).r * 0.55 + noise(x / 140.0 + 0.37, z / 140.0 + 0.37).r * 0.45


## GLSL wc_hash12 (fract-based) evaluated like the GPU.
static func hash12(px: float, py: float) -> float:
	var p3 := Vector3(fposmod(px * 0.1031, 1.0), fposmod(py * 0.1031, 1.0), fposmod(px * 0.1031, 1.0))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3(33.33, 33.33, 33.33))
	p3 += Vector3(d, d, d)
	return fposmod((p3.x + p3.y) * p3.z, 1.0)


## Farm plot at x/z: {"plot": Vector2 (cell coords), "type": 0 gold wheat / 1 green rice / 2 light
## green / 3 fallow, "fp": Vector2 position inside the plot 0..1, "border": distance to the plot
## edge in metres, "dir": furrow direction}.
static func farm_plot(x: float, z: float) -> Dictionary:
	var nm := noise(x / 140.0 + 0.37, z / 140.0 + 0.37)
	var wx := x + (nm.r - 0.5) * 18.0
	var wz := z + (nm.g - 0.5) * 18.0
	var plot := Vector2(floor(wx / PLOT_SIZE.x), floor(wz / PLOT_SIZE.y))
	var ph := hash12(plot.x, plot.y)
	var t := 0 if ph < 0.38 else (1 if ph < 0.74 else (2 if ph < 0.92 else 3))
	var fp := Vector2(wx / PLOT_SIZE.x - plot.x, wz / PLOT_SIZE.y - plot.y)
	var border := minf(minf(fp.x, 1.0 - fp.x) * PLOT_SIZE.x, minf(fp.y, 1.0 - fp.y) * PLOT_SIZE.y)
	var dir := Vector2(0.94, 0.34) if hash12(plot.x + 7.0, plot.y + 7.0) < 0.5 else Vector2(-0.34, 0.94)
	return {"plot": plot, "type": t, "fp": fp, "border": border, "dir": dir, "hash": ph}


## Region palette index (terrain.gdshader order) for a region id.
static func palette_index(region: StringName) -> int:
	match region:
		&"water_tribe": return 0
		&"fire_nation": return 2
		&"air_temple": return 3
	return 1


## Linear-space lush ground colour matching the terrain at x/z for a biome (grass tint).
static func lush_color(x: float, z: float, region: StringName, biome: int, macro_v: float) -> Color:
	var pi := palette_index(region)
	var d := GRASS_D[pi]
	var l := GRASS_L[pi]
	if biome == WorldData.Biome.FOREST:
		d = Color(0.13, 0.21, 0.10).lerp(Color(0.05, 0.20, 0.09), 1.0 if pi == 2 else 0.0)
		l = Color(0.30, 0.37, 0.17).lerp(Color(0.15, 0.35, 0.13), 1.0 if pi == 2 else 0.0)
	elif biome == WorldData.Biome.TUNDRA or biome == WorldData.Biome.SNOW:
		d = Color(0.47, 0.47, 0.37)
		l = Color(0.66, 0.64, 0.50)
	var c := d.lerp(l, clampf(macro_v * 0.85 + 0.1, 0.0, 1.0))
	# warm drift like the terrain (lush * (1.1, 1.02, 0.8) on high macro)
	var warm := smoothstep(0.4, 0.85, macro_v) * 0.6
	c = Color(c.r * (1.0 + 0.1 * warm), c.g * (1.0 + 0.02 * warm), c.b * (1.0 - 0.2 * warm))
	return c.srgb_to_linear()


## Linear-space rock tint for a region (multiplier for the neutral rock mesh colour).
static func rock_tint(region: StringName, t: float) -> Color:
	var pi := palette_index(region)
	var c := ROCK_D[pi].lerp(ROCK_L[pi], 0.55 + 0.35 * t).srgb_to_linear()
	var base := Color(0.62, 0.60, 0.58).srgb_to_linear()
	return Color(c.r / base.r, c.g / base.g, c.b / base.b)
