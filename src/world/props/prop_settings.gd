class_name PropSettings
extends RefCounted
## Distance budgets of the structure providers, derived from Settings (main thread; providers copy
## the dictionary in configure() and workers read only their copy).
##
## | key             | low  | medium | high | ultra | meaning |
## | poi_range       | 525  | 910  | 1400 | 1400 | POI structures (shrines, camps, ruins...) end (0.35 x view distance) |
## | poi_lod0        | 70   | 100  | 140  | 200  | full-detail kit mesh -> simplified LOD1 (by detail level) |
## | landmark_range  | 1500 | 2340 | 3000 | 3000 | waterfalls, arches, bridges, cave mouths (0.9 x view distance) |
## | cave_range      | 450  | 600  | 800  | 1000 | cave interiors, veils and collision |
## | road_range      | 160  | 220  | 300  | 420  | road dressing (lanterns, fences, signposts, milestones) |
## | shadow_range    | 60   | 100  | 150  | 220  | structures cast shadows within (and Settings shadows on) |


static func current() -> Dictionary:
	var detail := Settings.detail_level()
	var view := Settings.view_distance_m()
	return {
		"poi_range": clampf(view * 0.35, 500.0, 1400.0),
		"poi_lod0": [70.0, 100.0, 140.0, 200.0][detail],
		"landmark_range": clampf(view * 0.9, 1200.0, 3000.0),
		"cave_range": [450.0, 600.0, 800.0, 1000.0][detail],
		"road_range": [160.0, 220.0, 300.0, 420.0][detail],
		"shadow_range": [60.0, 100.0, 150.0, 220.0][detail],
		"shadows": int(Settings.get_value("graphics", "shadows")) > 0,
		"effects": Settings.effects_scale(),
		"detail": detail,
	}
