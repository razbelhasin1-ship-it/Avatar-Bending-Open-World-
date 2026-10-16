class_name VegetationSettings
extends RefCounted
## Vegetation budgets derived from Settings (main thread). Providers copy the dictionary in
## configure(); workers only read their copy.
##
## | key            | mobile/low | medium | high | ultra | meaning |
## | tree_range     | 72  | 132 | 210 | 330 | full trees end, far impostors begin (0.6 x Settings.vegetation_distance_m) |
## | tree_lod0      | 32  | 45  | 60  | 90  | LOD0 (+ ink outline) -> LOD1 (by detail level) |
## | far_range      | 450 | 780 | 1200 | 1600 | impostor forests end (0.3 x view distance) |
## | small_range    | 60  | 110 | 175 | 275 | shrubs, rocks, logs end (0.5 x vegetation distance) |
## | grass_range    | 30  | 45  | 60  | 85  | ground cover end (by vegetation level) |
## | shadow_range   | 40  | 70  | 110 | 160 | vegetation casts shadows within (and Settings shadows on) |
## | tree_density   | 0.59| 0.75| 1.0 | 1.3 | tree count multiplier (forests stay forests on phones) |
## | small_density  | 0.25| 0.55| 1.0 | 1.5 | Settings.vegetation_density() |
## | grass_density  | 0.25| 0.55| 1.0 | 1.5 | clump count multiplier (clumps grow to keep coverage) |


static func current() -> Dictionary:
	var veg := clampi(int(Settings.get_value("graphics", "vegetation")), 0, 3)
	var detail := Settings.detail_level()
	var dens := Settings.vegetation_density()
	var dist := Settings.vegetation_distance_m()
	return {
		"tree_range": dist * 0.6,
		"tree_lod0": [32.0, 45.0, 60.0, 90.0][detail],
		"far_range": clampf(Settings.view_distance_m() * 0.3, 450.0, 1600.0),
		"small_range": dist * 0.5,
		"small_lod0": [18.0, 25.0, 32.0, 45.0][detail],
		"grass_range": [30.0, 45.0, 60.0, 85.0][veg],
		"shadow_range": [40.0, 70.0, 110.0, 160.0][clampi(int(Settings.get_value("graphics", "shadows")) - 1, 0, 3)],
		"tree_density": clampf(0.45 + 0.55 * dens, 0.55, 1.3),
		"small_density": dens,
		"grass_density": dens,
		"shadows": int(Settings.get_value("graphics", "shadows")) > 0,
	}


## Pushes the distance bands of `cfg` into the shared materials.
static func apply(cfg: Dictionary) -> void:
	VegetationMaterials.set_ranges(cfg["tree_range"], cfg["far_range"], cfg["small_range"], cfg["grass_range"],
			cfg["tree_lod0"], cfg["small_lod0"], cfg["shadow_range"])
