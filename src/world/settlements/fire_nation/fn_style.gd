class_name FnStyle
extends RefCounted
## Fire Nation colour sets per district (linear vertex colours). Red lacquer, black tiles and
## gold; dark basalt masonry; the common districts in cream plaster under charcoal tiles.

## District styles: 0 lower city / harbour town, 1 noble quarter, 2 palace, 3 harbour (sooty
## industrial), 4 fishing / tea village, 5 resort isle.
const LOWER := 0
const NOBLE := 1
const PALACE := 2
const HARBOR := 3
const VILLAGE := 4
const RESORT := 5

static func _l(c: Color) -> Color:
	return c.srgb_to_linear()


static var WALLS: Array = [
	[_l(Color(0.84, 0.76, 0.62)), _l(Color(0.72, 0.52, 0.38)), _l(Color(0.62, 0.22, 0.15))],
	[_l(Color(0.62, 0.14, 0.11)), _l(Color(0.56, 0.12, 0.10)), _l(Color(0.66, 0.18, 0.12))],
	[_l(Color(0.66, 0.13, 0.10)), _l(Color(0.60, 0.11, 0.09)), _l(Color(0.70, 0.16, 0.11))],
	[_l(Color(0.46, 0.40, 0.37)), _l(Color(0.54, 0.20, 0.15)), _l(Color(0.40, 0.36, 0.34))],
	[_l(Color(0.70, 0.56, 0.42)), _l(Color(0.62, 0.48, 0.36)), _l(Color(0.76, 0.64, 0.50))],
	[_l(Color(0.95, 0.92, 0.86)), _l(Color(0.92, 0.88, 0.80)), _l(Color(0.97, 0.94, 0.88))],
]
static var ROOFS: Array = [
	[_l(Color(0.16, 0.14, 0.14)), _l(Color(0.21, 0.17, 0.16)), _l(Color(0.44, 0.12, 0.09))],
	[_l(Color(0.14, 0.12, 0.12)), _l(Color(0.17, 0.14, 0.14)), _l(Color(0.40, 0.09, 0.07))],
	[_l(Color(0.12, 0.10, 0.10)), _l(Color(0.15, 0.12, 0.12)), _l(Color(0.13, 0.11, 0.11))],
	[_l(Color(0.20, 0.18, 0.18)), _l(Color(0.26, 0.22, 0.21)), _l(Color(0.34, 0.14, 0.11))],
	[_l(Color(0.40, 0.22, 0.16)), _l(Color(0.46, 0.28, 0.20)), _l(Color(0.34, 0.24, 0.20))],
	[_l(Color(0.62, 0.18, 0.12)), _l(Color(0.70, 0.26, 0.14)), _l(Color(0.56, 0.16, 0.12))],
]
static var PILLARS: Array = [_l(Color(0.56, 0.13, 0.10)), _l(Color(0.50, 0.10, 0.08)), _l(Color(0.62, 0.12, 0.09)),
	_l(Color(0.30, 0.16, 0.13)), _l(Color(0.38, 0.22, 0.15)), _l(Color(0.62, 0.14, 0.10))]
static var RIDGES: Array = [_l(Color(0.20, 0.18, 0.18)), _l(Color(0.88, 0.66, 0.22)), _l(Color(0.92, 0.70, 0.24)),
	_l(Color(0.18, 0.16, 0.16)), _l(Color(0.30, 0.20, 0.16)), _l(Color(0.88, 0.66, 0.22))]
static var BASES: Array = [_l(Color(0.34, 0.31, 0.30)), _l(Color(0.24, 0.21, 0.21)), _l(Color(0.20, 0.18, 0.18)),
	_l(Color(0.28, 0.26, 0.25)), _l(Color(0.40, 0.34, 0.30)), _l(Color(0.62, 0.58, 0.54))]

static var BASALT := _l(Color(0.24, 0.22, 0.22))
static var BASALT_2 := _l(Color(0.30, 0.27, 0.26))
static var BASALT_DARK := _l(Color(0.15, 0.14, 0.14))
static var RED := _l(Color(0.62, 0.12, 0.09))
static var RED_DARK := _l(Color(0.42, 0.08, 0.06))
static var GOLD := _l(Color(0.92, 0.70, 0.24))
static var BLACK := _l(Color(0.10, 0.09, 0.09))
static var PAVING := _l(Color(0.40, 0.37, 0.35))
static var PAVING_DARK := _l(Color(0.27, 0.25, 0.24))
static var SCORCH := _l(Color(0.12, 0.10, 0.09))
static var CLOTH_RED := _l(Color(0.72, 0.10, 0.07))
static var CLOTH_GOLD := _l(Color(0.92, 0.70, 0.22))
static var STEEL := _l(Color(0.26, 0.27, 0.29))
static var STEEL_DARK := _l(Color(0.16, 0.16, 0.18))
static var WATER := _l(Color(0.20, 0.36, 0.40))
static var AWNINGS: Array = [_l(Color(0.72, 0.16, 0.10)), _l(Color(0.88, 0.62, 0.20)), _l(Color(0.30, 0.20, 0.18)),
	_l(Color(0.86, 0.80, 0.68)), _l(Color(0.56, 0.12, 0.10))]


static func wall(style: int, v: int) -> Color:
	return WALLS[clampi(style, 0, WALLS.size() - 1)][posmod(v, 3)]


## Roof colour of a variant (decorrelated from wall(): v + v / 4, so red walls also get dark roofs).
static func roof(style: int, v: int) -> Color:
	return ROOFS[clampi(style, 0, ROOFS.size() - 1)][posmod(v + floori(v / 4.0), 3)]


static func pillar(style: int) -> Color:
	return PILLARS[clampi(style, 0, PILLARS.size() - 1)]


static func ridge(style: int) -> Color:
	return RIDGES[clampi(style, 0, RIDGES.size() - 1)]


static func base(style: int) -> Color:
	return BASES[clampi(style, 0, BASES.size() - 1)]


## Roof options of a style: steep sweeping eaves, gold ridges for the noble / palace roofs.
static func roof_opts(style: int, v: int, extra: Dictionary = {}) -> Dictionary:
	var o := {"role": roof(style, v), "ridge_role": ridge(style), "fascia_role": RED_DARK if style != LOWER else pillar(style),
		"under_role": RED_DARK, "curve": 0.6 if style >= NOBLE and style != VILLAGE else 0.4, "concave": 0.5,
		"horns": style == NOBLE or style == PALACE or style == RESORT, "alt_role": roof(style, v + 1)}
	o.merge(extra, true)
	return o


## A gold flame finial (ridge ornament): a teardrop with a curling tip.
static func flame_finial(kit: BuildingKit, p: Vector3, size: float) -> void:
	if kit.lod >= 2:
		kit.g().cone(p, p + Vector3(0, size, 0), size * 0.25, 4, kit.col(GOLD))
		return
	var g := kit.g()
	var col := kit.col(GOLD)
	g.blob(p + Vector3(0, size * 0.22, 0), size * 0.22, 0, col)
	var line := PackedVector3Array([p + Vector3(0, size * 0.3, 0), p + Vector3(size * 0.08, size * 0.62, 0), p + Vector3(-size * 0.05, size, 0)])
	g.tube(line, PackedFloat32Array([size * 0.18, size * 0.1, size * 0.01]), 5, col)
	for sx: float in [-1.0, 1.0]:
		var side := PackedVector3Array([p + Vector3(sx * size * 0.12, size * 0.2, 0), p + Vector3(sx * size * 0.26, size * 0.42, 0), p + Vector3(sx * size * 0.2, size * 0.62, 0)])
		g.tube(side, PackedFloat32Array([size * 0.09, size * 0.06, size * 0.01]), 4, col)
