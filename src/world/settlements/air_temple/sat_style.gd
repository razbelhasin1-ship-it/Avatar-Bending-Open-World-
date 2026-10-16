class_name SatStyle
extends RefCounted
## Colour script of the Southern Air Temple (linear colours for kit roles that accept a Color):
## warm cream walls in a few tints, grey-beige masonry for the great retaining walls and the
## cliff towers, blue-teal roofs in three shades (deep on the great spire, lighter on the small
## pavilions), orange and saffron trims, gold finials and the monks' orange / yellow cloth.

const WALLS := [Color(0.95, 0.93, 0.88), Color(0.91, 0.89, 0.84), Color(0.93, 0.90, 0.82), Color(0.88, 0.87, 0.84)]
const MASONRY := [Color(0.80, 0.77, 0.70), Color(0.74, 0.71, 0.65), Color(0.84, 0.81, 0.74)]
const ROOFS := [Color(0.16, 0.46, 0.60), Color(0.12, 0.38, 0.52), Color(0.22, 0.54, 0.66)]
const ROOF_STRIPES := [Color(0.11, 0.34, 0.47), Color(0.09, 0.29, 0.41), Color(0.16, 0.44, 0.56)]
const ORANGE := Color(0.90, 0.50, 0.14)
const SAFFRON := Color(0.98, 0.76, 0.26)
const GOLD := Color(0.93, 0.74, 0.30)
const SKY := Color(0.42, 0.70, 0.84)
const ROBE := Color(0.95, 0.58, 0.16)
const GRASS := Color(0.36, 0.56, 0.26)
const SOIL := Color(0.42, 0.33, 0.24)
const HAY := Color(0.86, 0.74, 0.40)


static func wall(v: int) -> Color:
	return (WALLS[posmod(v, WALLS.size())] as Color).srgb_to_linear()


static func masonry(v: int) -> Color:
	return (MASONRY[posmod(v, MASONRY.size())] as Color).srgb_to_linear()


static func roof(v: int) -> Color:
	return (ROOFS[posmod(v, ROOFS.size())] as Color).srgb_to_linear()


static func roof_stripe(v: int) -> Color:
	return (ROOF_STRIPES[posmod(v, ROOF_STRIPES.size())] as Color).srgb_to_linear()


static func orange() -> Color:
	return ORANGE.srgb_to_linear()


static func saffron() -> Color:
	return SAFFRON.srgb_to_linear()


static func gold() -> Color:
	return GOLD.srgb_to_linear()


static func sky() -> Color:
	return SKY.srgb_to_linear()


static func lin(c: Color) -> Color:
	return c.srgb_to_linear()


## Options for KitRoofs.cone in the temple style (deep flare, gold finial, teal stripes).
static func cone_opts(v: int, sides: int = 20, flare: float = 0.6) -> Dictionary:
	return {"role": roof(v), "alt_role": roof_stripe(v), "trim_role": ORANGE.srgb_to_linear(), "finial_role": GOLD.srgb_to_linear(),
		"flare": flare, "sides": sides}
