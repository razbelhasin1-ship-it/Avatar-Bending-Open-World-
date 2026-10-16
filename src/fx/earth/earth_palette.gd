class_name EarthPalette
extends RefCounted
## Colours of bendable ground per surface, so every rock, pillar, spike, plate,
## dust cloud and crack shows the material it was torn from
## (docs/modules/bending_earth.md "Surfaces"):
##
##   var pal := EarthPalette.of(&"sand")   # {rock, dark, band, cap, dust, crack, debris}
##   EarthPalette.key(&"grass")            # palette id (&"grass"); unknown -> &"dirt"
##
## stone  grey granite           dirt   brown earth            grass  earth under a turf cap
## sand   ochre sandstone        ash    dark basalt, red strata snow   grey rock under snow
## mud    wet earth (shallow water)

const PALETTES := {
	&"stone": {"rock": Color(0.6, 0.58, 0.55), "dark": Color(0.4, 0.39, 0.38), "band": Color(0.5, 0.48, 0.46),
		"cap": Color(0.68, 0.66, 0.62), "dust": Color(0.74, 0.72, 0.68), "crack": Color(0.2, 0.19, 0.18), "debris": Color(0.55, 0.53, 0.5)},
	&"dirt": {"rock": Color(0.58, 0.45, 0.32), "dark": Color(0.4, 0.3, 0.21), "band": Color(0.5, 0.38, 0.27),
		"cap": Color(0.63, 0.5, 0.36), "dust": Color(0.68, 0.56, 0.42), "crack": Color(0.2, 0.14, 0.1), "debris": Color(0.5, 0.38, 0.27)},
	&"grass": {"rock": Color(0.56, 0.44, 0.32), "dark": Color(0.38, 0.29, 0.2), "band": Color(0.48, 0.37, 0.27),
		"cap": Color(0.4, 0.55, 0.24), "dust": Color(0.66, 0.56, 0.42), "crack": Color(0.19, 0.14, 0.1), "debris": Color(0.48, 0.38, 0.27)},
	&"sand": {"rock": Color(0.84, 0.72, 0.5), "dark": Color(0.66, 0.53, 0.35), "band": Color(0.77, 0.63, 0.43),
		"cap": Color(0.9, 0.8, 0.6), "dust": Color(0.9, 0.81, 0.62), "crack": Color(0.42, 0.32, 0.2), "debris": Color(0.8, 0.68, 0.47)},
	&"ash": {"rock": Color(0.32, 0.29, 0.29), "dark": Color(0.17, 0.15, 0.15), "band": Color(0.42, 0.27, 0.22),
		"cap": Color(0.46, 0.44, 0.42), "dust": Color(0.42, 0.39, 0.38), "crack": Color(0.1, 0.08, 0.08), "debris": Color(0.27, 0.24, 0.24)},
	&"snow": {"rock": Color(0.53, 0.52, 0.53), "dark": Color(0.35, 0.35, 0.37), "band": Color(0.46, 0.45, 0.47),
		"cap": Color(0.94, 0.96, 1.0), "dust": Color(0.93, 0.96, 1.0), "crack": Color(0.3, 0.33, 0.38), "debris": Color(0.85, 0.88, 0.93)},
	&"mud": {"rock": Color(0.4, 0.31, 0.23), "dark": Color(0.24, 0.18, 0.13), "band": Color(0.33, 0.26, 0.19),
		"cap": Color(0.32, 0.27, 0.21), "dust": Color(0.66, 0.74, 0.78), "crack": Color(0.13, 0.1, 0.07), "debris": Color(0.34, 0.27, 0.2)},
}


## Palette id for a ground surface / earth material (&"water" = mud; unbendable
## surfaces fall back to stone so a stray call still draws something sensible).
static func key(surface: StringName) -> StringName:
	match surface:
		&"stone", &"dirt", &"grass", &"sand", &"ash", &"snow", &"mud":
			return surface
		&"water", &"shallow_water":
			return &"mud"
		&"ice", &"wood", &"deep_water":
			return &"stone"
	return &"dirt"


static func of(surface: StringName) -> Dictionary:
	return PALETTES[key(surface)]


static func color(surface: StringName, part: String) -> Color:
	return (of(surface) as Dictionary).get(part, Color(0.5, 0.42, 0.33))
