class_name SettlementSettings
extends RefCounted
## Distance and density budgets of the settlement providers, derived from Settings (main thread;
## providers copy the dictionary in configure() and workers only read their copy).
##
## | key              | low  | medium | high | ultra | meaning |
## | lod0_end         | 100  | 160    | 220  | 300   | full detail (ornaments, props, interiors, lights) |
## | lod1_end         | 300  | 600    | 800  | 1100  | simplified buildings (no small props) |
## | far_end          | 1500 | 2600   | 4000 | 6000  | silhouettes (towers, walls, roofs): read from kilometres |
## | collision_range  | 90   | 110    | 120  | 140   | per-cell static collision attached within (hysteresis +40 m) |
## | cell_lights      | 6    | 10     | 14   | 18    | budgeted lantern/brazier lights created per 128 m cell |
## | props            | 0.5  | 0.75   | 1.0  | 1.0   | density of small street props (crates, stalls goods, boats) |

# Low / mobile (detail 0) trimmed by the mobile perf pass (was 110 / 420: ~0.9 M triangles at
# the Northern Water Tribe spawn): simplified buildings end at 300 m (silhouettes beyond), full
# detail at 100 m, which still covers the half-diagonal of the camera's own 128 m cell
# (visibility ranges measure to the cell AABB centre), so props never drop out next to you.
const LOD0_END := [100.0, 160.0, 220.0, 300.0]
const LOD1_END := [300.0, 600.0, 800.0, 1100.0]
const COLLISION := [90.0, 110.0, 120.0, 140.0]
const CELL_LIGHTS := [6, 10, 14, 18]
const PROPS := [0.5, 0.75, 1.0, 1.0]


static func current() -> Dictionary:
	var detail := Settings.detail_level()
	var view := Settings.view_distance_m()
	return {
		"detail": detail,
		"lod0_end": LOD0_END[detail],
		"lod1_end": LOD1_END[detail],
		"far_end": clampf(view, 1500.0, 6000.0),
		"collision_range": COLLISION[detail],
		"cell_lights": CELL_LIGHTS[detail],
		"props": PROPS[detail],
		"shadows": int(Settings.get_value("graphics", "shadows")) > 0,
		# Mobile / low detail: only LOD0 (near) cells cast sun shadows. The merged LOD1 meshes
		# (100k+ triangles per draw) dominated the phone shadow pass (mobile perf pass).
		"lod1_shadows": detail >= 1,
		"effects": Settings.effects_scale(),
	}
