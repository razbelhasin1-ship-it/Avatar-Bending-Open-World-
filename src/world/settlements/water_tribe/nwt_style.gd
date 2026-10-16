class_name NwtStyle
extends RefCounted
## Colour script of the Northern Water Tribe (linear colours for kit roles that accept a Color):
## snow-white and ice-blue walls in a few tints so a street never reads as one flat white, glossy
## ice domes and spires in a stronger blue, deep navy trims, warm lit windows.

const WALLS := [Color(0.93, 0.96, 1.0), Color(0.84, 0.91, 0.98), Color(0.82, 0.93, 0.97), Color(0.80, 0.86, 0.95),
	Color(0.90, 0.94, 0.99), Color(0.86, 0.90, 0.97)]
const DOMES := [Color(0.56, 0.74, 0.95), Color(0.66, 0.82, 0.98), Color(0.30, 0.48, 0.82), Color(0.80, 0.90, 0.99)]
const SPIRES := [Color(0.62, 0.80, 0.98), Color(0.28, 0.46, 0.80), Color(0.74, 0.88, 1.0)]
const NAVY := Color(0.12, 0.22, 0.50)
const BLUE := Color(0.24, 0.44, 0.78)
const SNOW := Color(0.97, 0.98, 1.0)


static func wall(v: int) -> Color:
	return (WALLS[posmod(v, WALLS.size())] as Color).srgb_to_linear()


static func dome(v: int) -> Color:
	return (DOMES[posmod(v, DOMES.size())] as Color).srgb_to_linear()


static func spire(v: int) -> Color:
	return (SPIRES[posmod(v, SPIRES.size())] as Color).srgb_to_linear()


static func navy() -> Color:
	return NAVY.srgb_to_linear()


static func blue() -> Color:
	return BLUE.srgb_to_linear()
