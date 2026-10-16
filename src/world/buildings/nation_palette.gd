class_name NationPalette
extends RefCounted
## Per-nation colour palettes + shared materials for the building kit (BuildingKit).
##
## Geometry is vertex-coloured, so one toon material (ToonMaterials, ink outline) draws every
## solid part of every nation in a single surface; the palette maps *roles* to colours:
##
##   var pal := NationPalette.get_palette(&"fire_nation")
##   pal.color(&"roof")            # linear Color for vertex colours
##   pal.material(&"solid")        # shared ShaderMaterial for a kit slot
##
## Roles: wall, wall_alt, base (plinths/foundations), stone, stone_dark, trim, trim_alt, roof,
## roof_alt, roof_under, ridge, wood, wood_dark, floor, door, window (dark openings), cloth,
## cloth_alt, metal (gold/bronze), accent, glow (lantern paper / fire), ice, snow, interior.
## Nations: &"water_tribe", &"earth_kingdom", &"fire_nation", &"air_nomads", &"neutral".

const NATIONS: Array[StringName] = [&"water_tribe", &"earth_kingdom", &"fire_nation", &"air_nomads", &"neutral"]

## sRGB authoring colours.
const COLORS := {
	&"water_tribe": {
		&"wall": Color(0.90, 0.94, 0.99), &"wall_alt": Color(0.74, 0.85, 0.95), &"base": Color(0.62, 0.75, 0.88),
		&"stone": Color(0.70, 0.80, 0.90), &"stone_dark": Color(0.45, 0.58, 0.74), &"trim": Color(0.18, 0.32, 0.60),
		&"trim_alt": Color(0.93, 0.96, 1.0), &"roof": Color(0.74, 0.86, 0.97), &"roof_alt": Color(0.20, 0.36, 0.64),
		&"roof_under": Color(0.48, 0.62, 0.80), &"ridge": Color(0.93, 0.97, 1.0), &"wood": Color(0.46, 0.38, 0.32),
		&"wood_dark": Color(0.30, 0.25, 0.22), &"floor": Color(0.72, 0.82, 0.92), &"door": Color(0.25, 0.38, 0.62),
		&"window": Color(0.10, 0.16, 0.30), &"cloth": Color(0.16, 0.30, 0.62), &"cloth_alt": Color(0.92, 0.95, 1.0),
		&"metal": Color(0.62, 0.68, 0.80), &"accent": Color(0.30, 0.52, 0.82), &"glow": Color(1.0, 0.86, 0.60),
		&"ice": Color(0.68, 0.84, 0.97), &"snow": Color(0.97, 0.98, 1.0), &"interior": Color(0.38, 0.46, 0.60),
	},
	&"earth_kingdom": {
		&"wall": Color(0.88, 0.81, 0.66), &"wall_alt": Color(0.80, 0.71, 0.55), &"base": Color(0.62, 0.56, 0.46),
		&"stone": Color(0.68, 0.62, 0.52), &"stone_dark": Color(0.46, 0.41, 0.35), &"trim": Color(0.20, 0.38, 0.22),
		&"trim_alt": Color(0.82, 0.70, 0.30), &"roof": Color(0.24, 0.48, 0.30), &"roof_alt": Color(0.18, 0.38, 0.24),
		&"roof_under": Color(0.40, 0.28, 0.18), &"ridge": Color(0.16, 0.32, 0.20), &"wood": Color(0.50, 0.33, 0.20),
		&"wood_dark": Color(0.32, 0.21, 0.14), &"floor": Color(0.58, 0.50, 0.40), &"door": Color(0.36, 0.22, 0.13),
		&"window": Color(0.14, 0.12, 0.10), &"cloth": Color(0.24, 0.52, 0.26), &"cloth_alt": Color(0.86, 0.72, 0.28),
		&"metal": Color(0.78, 0.62, 0.28), &"accent": Color(0.85, 0.70, 0.25), &"glow": Color(1.0, 0.78, 0.40),
		&"ice": Color(0.72, 0.88, 0.98), &"snow": Color(0.94, 0.97, 1.0), &"interior": Color(0.46, 0.36, 0.26),
	},
	&"fire_nation": {
		&"wall": Color(0.62, 0.14, 0.11), &"wall_alt": Color(0.40, 0.10, 0.09), &"base": Color(0.27, 0.24, 0.24),
		&"stone": Color(0.36, 0.32, 0.31), &"stone_dark": Color(0.20, 0.18, 0.18), &"trim": Color(0.12, 0.10, 0.10),
		&"trim_alt": Color(0.90, 0.68, 0.22), &"roof": Color(0.16, 0.13, 0.13), &"roof_alt": Color(0.52, 0.10, 0.08),
		&"roof_under": Color(0.40, 0.08, 0.06), &"ridge": Color(0.88, 0.66, 0.22), &"wood": Color(0.42, 0.16, 0.10),
		&"wood_dark": Color(0.18, 0.10, 0.08), &"floor": Color(0.30, 0.27, 0.26), &"door": Color(0.30, 0.08, 0.06),
		&"window": Color(0.08, 0.05, 0.05), &"cloth": Color(0.74, 0.10, 0.07), &"cloth_alt": Color(0.92, 0.70, 0.22),
		&"metal": Color(0.90, 0.68, 0.22), &"accent": Color(0.92, 0.70, 0.24), &"glow": Color(1.0, 0.62, 0.25),
		&"ice": Color(0.72, 0.88, 0.98), &"snow": Color(0.94, 0.97, 1.0), &"interior": Color(0.34, 0.16, 0.12),
	},
	&"air_nomads": {
		&"wall": Color(0.93, 0.91, 0.86), &"wall_alt": Color(0.84, 0.81, 0.75), &"base": Color(0.74, 0.71, 0.65),
		&"stone": Color(0.82, 0.79, 0.73), &"stone_dark": Color(0.58, 0.55, 0.50), &"trim": Color(0.88, 0.52, 0.16),
		&"trim_alt": Color(0.95, 0.80, 0.40), &"roof": Color(0.17, 0.45, 0.58), &"roof_alt": Color(0.12, 0.34, 0.46),
		&"roof_under": Color(0.62, 0.42, 0.26), &"ridge": Color(0.92, 0.72, 0.30), &"wood": Color(0.56, 0.40, 0.27),
		&"wood_dark": Color(0.36, 0.25, 0.17), &"floor": Color(0.80, 0.76, 0.68), &"door": Color(0.62, 0.36, 0.14),
		&"window": Color(0.12, 0.14, 0.18), &"cloth": Color(0.92, 0.60, 0.16), &"cloth_alt": Color(0.95, 0.82, 0.36),
		&"metal": Color(0.88, 0.70, 0.30), &"accent": Color(0.20, 0.52, 0.66), &"glow": Color(1.0, 0.82, 0.52),
		&"ice": Color(0.72, 0.88, 0.98), &"snow": Color(0.94, 0.97, 1.0), &"interior": Color(0.52, 0.44, 0.36),
	},
	&"neutral": {
		&"wall": Color(0.74, 0.68, 0.58), &"wall_alt": Color(0.64, 0.58, 0.49), &"base": Color(0.52, 0.48, 0.42),
		&"stone": Color(0.60, 0.57, 0.52), &"stone_dark": Color(0.40, 0.38, 0.35), &"trim": Color(0.36, 0.26, 0.18),
		&"trim_alt": Color(0.70, 0.60, 0.40), &"roof": Color(0.46, 0.34, 0.24), &"roof_alt": Color(0.36, 0.26, 0.18),
		&"roof_under": Color(0.34, 0.24, 0.16), &"ridge": Color(0.30, 0.22, 0.16), &"wood": Color(0.50, 0.36, 0.24),
		&"wood_dark": Color(0.32, 0.23, 0.16), &"floor": Color(0.54, 0.46, 0.36), &"door": Color(0.36, 0.25, 0.16),
		&"window": Color(0.10, 0.09, 0.08), &"cloth": Color(0.72, 0.62, 0.44), &"cloth_alt": Color(0.56, 0.20, 0.14),
		&"metal": Color(0.60, 0.52, 0.40), &"accent": Color(0.76, 0.56, 0.26), &"glow": Color(1.0, 0.76, 0.42),
		&"ice": Color(0.72, 0.88, 0.98), &"snow": Color(0.94, 0.97, 1.0), &"interior": Color(0.40, 0.32, 0.24),
	},
}

const SOLID_SHADER_OPTS := {"vertex_color": true, "outline": true, "outline_width": 1.1, "rim": 0.25, "softness": 0.07}
const GLOW_SHADER := preload("res://assets/shaders/content/kit_glow.gdshader")
const CLOTH_SHADER := preload("res://assets/shaders/content/cloth.gdshader")

static var _palettes: Dictionary = {}
static var _materials: Dictionary = {}

var nation: StringName = &"neutral"
var _lin: Dictionary = {}


static func get_palette(p_nation: StringName) -> NationPalette:
	var key := p_nation if COLORS.has(p_nation) else &"neutral"
	if not _palettes.has(key):
		var p := NationPalette.new()
		p.nation = key
		for role: StringName in COLORS[key]:
			p._lin[role] = (COLORS[key][role] as Color).srgb_to_linear()
		_palettes[key] = p
	return _palettes[key]


## Nation of a WorldData region id (&"water_tribe", ..., &"air_temple" -> &"air_nomads").
static func nation_for_region(region: StringName) -> StringName:
	match region:
		&"water_tribe": return &"water_tribe"
		&"earth_kingdom": return &"earth_kingdom"
		&"fire_nation": return &"fire_nation"
		&"air_temple": return &"air_nomads"
	return &"neutral"


## Linear colour of a role (white if unknown). Thread-safe after creation.
func color(role: StringName) -> Color:
	return _lin.get(role, Color.WHITE)


## Shared material of a kit slot: &"solid" (toon + ink outline), &"glow" (emissive, brighter at
## night), &"cloth" (two-sided, wind), &"ice" (glossy toon). Main thread only (first call).
static func material(slot: StringName) -> Material:
	if _materials.has(slot):
		return _materials[slot]
	WorldShaderGlobals.ensure()
	var m: Material
	match slot:
		&"glow":
			var g := ShaderMaterial.new()
			g.shader = GLOW_SHADER
			m = g
		&"cloth":
			var c := ShaderMaterial.new()
			c.shader = CLOTH_SHADER
			m = c
		&"ice":
			m = ToonMaterials.make(Color.WHITE, {"vertex_color": true, "outline": true, "outline_width": 0.9, "rim": 0.7,
				"specular": 0.6, "shade_tint": Color(0.55, 0.72, 1.0)})
		_:
			m = ToonMaterials.make(Color.WHITE, SOLID_SHADER_OPTS)
	_materials[slot] = m
	return m


## Creates every slot material (call on the main thread before building on workers).
static func prepare_materials() -> void:
	for s: StringName in [&"solid", &"glow", &"cloth", &"ice"]:
		material(s)
