class_name SettlementSettings
extends RefCounted
## Distance and density budgets of the settlement providers, derived from Settings (main thread;
## providers copy the dictionary in configure() and workers only read their copy).
##
## | key              | low  | medium | high | ultra | meaning |
## | lod0_end         | 100  | 160    | 220  | 300   | full detail (ornaments, props, interiors, lights) |
## | lod1_end         | 220  | 600    | 800  | 1100  | simplified buildings (no small props) |
## | far_end          | 1500 | 2600   | 4000 | 6000  | silhouettes (towers, walls, roofs): read from kilometres |
## | collision_range  | 90   | 110    | 120  | 140   | per-cell static collision attached within (hysteresis +40 m) |
## | cell_lights      | 6    | 10     | 14   | 18    | budgeted lantern/brazier lights created per 128 m cell |
## | props            | 0.5  | 0.75   | 1.0  | 1.0   | density of small street props (crates, stalls goods, boats) |
## | lod1_kit         | 2    | 1      | 1    | 1     | kit LOD of the LOD1 band (2 = silhouette recipes, phones)   |
## | merge_far        | yes  | no     | no   | no    | LOD1 / LOD2 meshes as one surface (one draw call)           |
## | lod0_tight       | yes  | no     | no   | no    | LOD0 ends at the cell half diagonal + 6 m (96.5 m / 74 m)   |
## | quad_lod0        | yes  | no     | no   | no    | LOD0 as 4 quadrants: full detail within 47 m, kit LOD 1 beyond |
## | mesh_lods        | yes  | no     | no   | no    | automatic mesh LODs (MeshLods) on every settlement mesh      |
## | fade_margin      | 0    | 12     | 12   | 12    | m each side of a LOD hand-over cross-faded (fade self)       |
## | far_lod_bias     | 0.25 | 1      | 1    | 1     | GeometryInstance3D.lod_bias of mid quadrants and LOD1        |
## | sil_lod_bias     | 0.15 | 1      | 1    | 1     | GeometryInstance3D.lod_bias of the LOD2 silhouettes          |
## | flat_ice         | yes  | no     | no   | no    | full-detail ice surfaces without the ink outline pass         |
## LOD1 and LOD2 never draw the ink outline pass (it fades out by 60 m: invisible, but it doubled
## their triangles and draw calls), see docs/qa/perf_polish.md.

# Low / mobile (detail 0) trimmed by the mobile perf pass (was 110 / 420: ~0.9 M triangles at
# the Northern Water Tribe spawn): simplified buildings end at 300 m (220 m since perf_polish,
# with the silhouette-kit LOD1; silhouettes beyond), full
# detail at 100 m, which still covers the half-diagonal of the camera's own 128 m cell
# (visibility ranges measure to the cell AABB centre), so props never drop out next to you.
const LOD0_END := [100.0, 160.0, 220.0, 300.0]
const LOD1_END := [220.0, 600.0, 800.0, 1100.0]
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
		# perf_polish (wave 4), see docs/qa/perf_polish.md:
		# Kit LOD the LOD1 band is built with: phones use the silhouette kit (LOD2 recipes) for every
		# mid-distance piece, ~1/4 of the triangles of the regular LOD1.
		"lod1_kit": 2 if detail == 0 else 1,
		# Phones: the merged mid / far meshes fold ice, glow and cloth into the solid surface (one
		# draw call per cell instead of up to four; gloss, emission and cloth sway are invisible there).
		"merge_far": detail == 0,
		# Phones: LOD0 ends just past the half diagonal of a cell (it must still cover the camera's
		# own cell): applied per plan by the providers (cell size).
		"lod0_tight": detail == 0,
		# Phones: LOD0 split into quadrants (SettlementProvider.build_quads): full detail only within
		# ~47 m of a quadrant centre, the rest of the LOD0 band at kit LOD 1 (HLOD under LOD1).
		"quad_lod0": detail == 0,
		# Phones: automatic LOD index buffers on the settlement meshes (MeshLods, built on the
		# workers): the renderer picks coarser versions by screen-space error (4 px on phones).
		"mesh_lods": detail == 0,
		# Cross-fade band (m, each side) of the LOD0 -> LOD1 -> silhouette hand-overs: the engine's
		# visibility-range fade (GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF) instead of a pop.
		# Desktop only: in the band both LODs draw, blended, which phones should not pay for.
		"fade_margin": 0.0 if detail == 0 else 12.0,
		# Phones: the meshes beyond the full-detail quadrants (mid quadrants, LOD1, silhouettes,
		# all >= 47 m away) switch to their coarser mesh LODs 4x sooner (lod_bias 0.25 ~ a 16 px
		# error on top of the phones' 4 px Viewport.mesh_lod_threshold); near detail is untouched.
		"far_lod_bias": 0.25 if detail == 0 else 1.0,
		# ... and the silhouettes beyond lod1_end even sooner (0.15 ~ a 27 px error at >= 220 m).
		"sil_lod_bias": 0.15 if detail == 0 else 1.0,
		# Phones: the glossy ice surfaces of the full-detail quadrants (rim light + specular read
		# against snow and sky) skip the ink outline pass: it doubled ~7k triangles per quadrant
		# in the Northern Water Tribe. Stone, wood and roofs keep their ink lines.
		"flat_ice": detail == 0,
		# Vegetation level: garden plant ranges follow it (cells are rebuilt when it changes).
		"vegetation": int(Settings.get_value("graphics", "vegetation")),
	}


## LOD0 end for a plan's cell size: the preset value, and on phones (`lod0_tight`) no further than
## the cell half diagonal + 6 m (the camera's own cell stays LOD0: visibility ranges measure to the
## cell AABB centre).
static func lod0_end_for(cfg: Dictionary, cell_size: float) -> float:
	var end := float(cfg["lod0_end"])
	if bool(cfg.get("lod0_tight", false)):
		end = minf(end, cell_size * 0.7072 + 6.0)
	return end
