class_name ElementDefs
extends RefCounted
## Static definitions for the four bending elements.
##
## `Element` values are stored in saves, so never renumber them.

enum Element { NONE = -1, AIR = 0, EARTH = 1, FIRE = 2, WATER = 3 }

const ALL: Array[int] = [Element.AIR, Element.EARTH, Element.FIRE, Element.WATER]

## Display/meta data per element. Locomotion and combat tuning live in
## LocomotionProfile (src/player) and the bending ability data (src/bending).
const DATA := {
	Element.AIR: {
		"id": &"air",
		"name": "Airbender",
		"element_name": "Air",
		"nation": "Air Nomads",
		"tagline": "Move like the wind. Follow no path. Let nothing hold you down.",
		"philosophy": "Fast, evasive, acrobatic. Circular motion turns every attack into empty space.",
		"home_region": &"air_temple",
		"home_name": "The Southern Air Temple",
		"companion": &"sky_bison",
		"companion_name": "Sky Bison",
		"color": Color(0.96, 0.72, 0.30),
		"color_secondary": Color(0.55, 0.78, 0.86),
		"glyph": "气",
		"virtue": "和",
	},
	Element.EARTH: {
		"id": &"earth",
		"name": "Earthbender",
		"element_name": "Earth",
		"nation": "Earth Kingdom",
		"tagline": "Stand firm. Shape the world. Become an unbreakable force.",
		"philosophy": "Grounded, deliberate, powerful. Wait, listen, and strike when the moment is right.",
		"home_region": &"earth_kingdom",
		"home_name": "Ba Sing Se",
		"companion": &"badgermole",
		"companion_name": "Badgermole",
		"color": Color(0.36, 0.62, 0.30),
		"color_secondary": Color(0.62, 0.52, 0.36),
		"glyph": "土",
		"virtue": "强",
	},
	Element.FIRE: {
		"id": &"fire",
		"name": "Firebender",
		"element_name": "Fire",
		"nation": "Fire Nation",
		"tagline": "Unleash your inner flame. Strike with precision. Burn through every obstacle.",
		"philosophy": "Aggressive, precise, explosive. Breath is the source of fire; drive forward relentlessly.",
		"home_region": &"fire_nation",
		"home_name": "The Fire Nation Capital",
		"companion": &"dragon",
		"companion_name": "Dragon",
		"color": Color(0.86, 0.22, 0.12),
		"color_secondary": Color(0.98, 0.70, 0.20),
		"glyph": "火",
		"virtue": "烈",
	},
	Element.WATER: {
		"id": &"water",
		"name": "Waterbender",
		"element_name": "Water",
		"nation": "Northern Water Tribe",
		"tagline": "Flow with the tides. Adapt to every challenge. Become one with the water.",
		"philosophy": "Fluid, adaptive, defensive. Turn the opponent's momentum against them.",
		"home_region": &"water_tribe",
		"home_name": "The Northern Water Tribe",
		"companion": &"polar_bear_dog",
		"companion_name": "Polar Bear Dog",
		"color": Color(0.18, 0.42, 0.82),
		"color_secondary": Color(0.75, 0.90, 0.98),
		"glyph": "水",
		"virtue": "善",
	},
}


static func is_valid(element: int) -> bool:
	return DATA.has(element)


static func get_data(element: int) -> Dictionary:
	return DATA.get(element, {})


static func id_of(element: int) -> StringName:
	return DATA[element]["id"] if DATA.has(element) else &"none"


static func from_id(id: StringName) -> int:
	for e: int in DATA:
		if DATA[e]["id"] == id:
			return e
	return Element.NONE


static func display_name(element: int) -> String:
	return DATA[element]["name"] if DATA.has(element) else "None"


static func color_of(element: int) -> Color:
	return DATA[element]["color"] if DATA.has(element) else Color.WHITE


static func emblem_path(element: int) -> String:
	return "res://assets/ui/emblem_%s.svg" % String(id_of(element))
