class_name EkStyle
extends RefCounted
## Earth Kingdom colour sets per district (linear vertex colours for BuildingKit roles given as
## explicit Colors). The kit palette (&"earth_kingdom") supplies the base roles; these add the
## district variety: earthen Lower Ring homes with weathered brown tiles, white-plastered Middle
## Ring houses under grey-green tiles, Upper Ring mansions in cream and gold under emerald roofs,
## the palace's jade and gold, and the grey-tan masonry of the great walls.

## District styles (index): 0 lower ring / villages, 1 middle ring, 2 upper ring, 3 palace,
## 4 farmstead, 5 Omashu (warm sandstone, green roofs).
const LOWER := 0
const MIDDLE := 1
const UPPER := 2
const PALACE := 3
const FARM := 4
const OMASHU := 5

static func _l(c: Color) -> Color:
	return c.srgb_to_linear()


## Wall plaster / earth colours per style (sRGB authoring, 3 variants each).
static var WALLS: Array = [
	[_l(Color(0.80, 0.68, 0.52)), _l(Color(0.74, 0.62, 0.47)), _l(Color(0.84, 0.76, 0.62))],
	[_l(Color(0.92, 0.89, 0.80)), _l(Color(0.88, 0.84, 0.72)), _l(Color(0.94, 0.90, 0.82))],
	[_l(Color(0.94, 0.88, 0.70)), _l(Color(0.92, 0.84, 0.62)), _l(Color(0.96, 0.92, 0.80))],
	[_l(Color(0.95, 0.86, 0.58)), _l(Color(0.92, 0.82, 0.52)), _l(Color(0.97, 0.90, 0.66))],
	[_l(Color(0.76, 0.64, 0.48)), _l(Color(0.70, 0.58, 0.44)), _l(Color(0.82, 0.72, 0.56))],
	[_l(Color(0.86, 0.74, 0.56)), _l(Color(0.80, 0.68, 0.50)), _l(Color(0.90, 0.80, 0.62))],
]
## Roof tile colours per style.
static var ROOFS: Array = [
	[_l(Color(0.42, 0.37, 0.32)), _l(Color(0.48, 0.40, 0.32)), _l(Color(0.36, 0.42, 0.33))],
	[_l(Color(0.30, 0.42, 0.34)), _l(Color(0.36, 0.44, 0.38)), _l(Color(0.26, 0.38, 0.30))],
	[_l(Color(0.17, 0.46, 0.29)), _l(Color(0.20, 0.50, 0.32)), _l(Color(0.15, 0.42, 0.27))],
	[_l(Color(0.14, 0.46, 0.30)), _l(Color(0.16, 0.50, 0.32)), _l(Color(0.13, 0.42, 0.28))],
	[_l(Color(0.55, 0.46, 0.30)), _l(Color(0.50, 0.42, 0.28)), _l(Color(0.44, 0.38, 0.30))],
	[_l(Color(0.22, 0.44, 0.30)), _l(Color(0.26, 0.48, 0.32)), _l(Color(0.30, 0.40, 0.30))],
]
## Timber frames / pillars per style.
static var TIMBER: Array = [
	_l(Color(0.36, 0.25, 0.17)), _l(Color(0.30, 0.22, 0.16)), _l(Color(0.46, 0.16, 0.10)), _l(Color(0.52, 0.14, 0.09)),
	_l(Color(0.40, 0.29, 0.19)), _l(Color(0.34, 0.24, 0.16)),
]
## Ridge colours per style (the Upper Ring and palace ridges are gold).
static var RIDGES: Array = [
	_l(Color(0.30, 0.27, 0.24)), _l(Color(0.22, 0.30, 0.25)), _l(Color(0.86, 0.68, 0.26)), _l(Color(0.92, 0.74, 0.28)),
	_l(Color(0.40, 0.33, 0.24)), _l(Color(0.20, 0.34, 0.24)),
]
static var BASES: Array = [
	_l(Color(0.52, 0.47, 0.40)), _l(Color(0.58, 0.55, 0.50)), _l(Color(0.66, 0.63, 0.58)), _l(Color(0.70, 0.67, 0.60)),
	_l(Color(0.48, 0.42, 0.34)), _l(Color(0.62, 0.55, 0.44)),
]

## The great walls: grey-tan masonry, darker courses, green tile copings.
static var WALL_STONE := _l(Color(0.62, 0.58, 0.51))
static var WALL_STONE_2 := _l(Color(0.57, 0.53, 0.47))
static var WALL_DARK := _l(Color(0.44, 0.41, 0.37))
static var WALL_TOP := _l(Color(0.70, 0.66, 0.58))
static var COPING := _l(Color(0.20, 0.42, 0.28))
static var GOLD := _l(Color(0.88, 0.70, 0.28))
static var JADE := _l(Color(0.18, 0.52, 0.36))
static var WATER := _l(Color(0.26, 0.46, 0.52))
static var FIELD_DIRT := _l(Color(0.46, 0.36, 0.25))
static var STRAW := _l(Color(0.84, 0.72, 0.42))
static var PAVING := _l(Color(0.66, 0.62, 0.55))
static var PAVING_DARK := _l(Color(0.55, 0.51, 0.45))
static var LACQUER := _l(Color(0.55, 0.15, 0.10))
static var CLOTH_GREEN := _l(Color(0.20, 0.48, 0.24))
static var CLOTH_GOLD := _l(Color(0.88, 0.72, 0.30))
static var AWNINGS: Array = [_l(Color(0.70, 0.30, 0.18)), _l(Color(0.26, 0.50, 0.30)), _l(Color(0.86, 0.70, 0.36)),
	_l(Color(0.80, 0.78, 0.66)), _l(Color(0.42, 0.56, 0.62))]


static func wall(style: int, v: int) -> Color:
	return WALLS[clampi(style, 0, WALLS.size() - 1)][posmod(v, 3)]


static func roof(style: int, v: int) -> Color:
	return ROOFS[clampi(style, 0, ROOFS.size() - 1)][posmod(v, 3)]


static func timber(style: int) -> Color:
	return TIMBER[clampi(style, 0, TIMBER.size() - 1)]


static func ridge(style: int) -> Color:
	return RIDGES[clampi(style, 0, RIDGES.size() - 1)]


static func base(style: int) -> Color:
	return BASES[clampi(style, 0, BASES.size() - 1)]


## Roof options of a style (RoofsLite / KitRoofs).
static func roof_opts(style: int, v: int, extra: Dictionary = {}) -> Dictionary:
	var o := {"role": roof(style, v), "ridge_role": ridge(style), "fascia_role": timber(style), "under_role": timber(style) * 0.8,
		"curve": 0.35 if style == LOWER or style == FARM else 0.55, "concave": 0.4, "horns": style >= MIDDLE and style != FARM}
	o.merge(extra, true)
	return o
