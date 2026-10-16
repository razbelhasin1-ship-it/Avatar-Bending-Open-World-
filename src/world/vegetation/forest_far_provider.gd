class_name ForestFarProvider
extends ContentProvider
## Cheap far LOD so forests still read at a kilometre and beyond: 512 m cells of impostor trees
## (LOD2 meshes, 16-60 triangles, no shadows, no outline) from tree_range to far_range. They are
## a thinned, scaled-up subset of exactly the trees VegetationProvider places (same global
## scatter grid), and fade in per instance where the full trees fade out.

const HALF_DIAG := 362.0
const BLOCK := 32.0                # coarse pre-pass block (skips empty land quickly)

var cfg: Dictionary = {}


func _init() -> void:
	id = &"forest_far"
	cell_size = 512.0
	priority = 5
	unload_margin = 160.0


func configure() -> bool:
	TerrainPatterns.load_data()
	VegetationLibrary.build_async()
	var c := VegetationSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	range_m = float(cfg["far_range"])
	VegetationProvider._prepare_materials()
	return changed


func tick() -> void:
	VegetationLibrary.poll()


func wants_cell(_coord: Vector2i) -> bool:
	return VegetationLibrary.is_ready()


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var origin := cell.origin()
	var groups := {}        # species -> [buf, count, lo, hi]
	var per_block := int(BLOCK / VegetationScatter.GRID)
	var blocks := int(cell_size / BLOCK)
	var g0x := int(floor(cell.rect.position.x / VegetationScatter.GRID))
	var g0z := int(floor(cell.rect.position.y / VegetationScatter.GRID))
	var far_cfg := cfg.duplicate()
	for bj in blocks:
		for bi in blocks:
			var cx := cell.rect.position.x + (bi + 0.5) * BLOCK
			var cz := cell.rect.position.y + (bj + 0.5) * BLOCK
			if not _block_may_have_trees(cx, cz):
				continue
			for j in per_block:
				for i in per_block:
					var gx := g0x + bi * per_block + i
					var gz := g0z + bj * per_block + j
					if not VegetationScatter.far_keeps(gx, gz):
						continue
					for it: VegetationScatter.Item in VegetationScatter.evaluate(gx, gz, far_cfg, cell.exclusions, 1):
						if not VegetationLibrary.SPECIES[it.species].get("far", false):
							continue
						if not groups.has(it.species):
							groups[it.species] = [PackedFloat32Array(), 0, Vector3.INF, -Vector3.INF]
						var e: Array = groups[it.species]
						var local := it.pos - origin
						CellPayload.write_instance(e[0], Transform3D(it.basis.scaled(Vector3.ONE * VegetationScatter.FAR_SCALE), local), it.tint)
						e[1] = int(e[1]) + 1
						e[2] = (e[2] as Vector3).min(local)
						e[3] = (e[3] as Vector3).max(local)
	var begin := maxf(float(cfg["tree_range"]) - HALF_DIAG - 40.0, 0.0)
	var end := float(cfg["far_range"]) + HALF_DIAG
	for sp: StringName in groups:
		var e: Array = groups[sp]
		var lo: Vector3 = e[2]
		var hi: Vector3 = e[3]
		var aabb := AABB(lo - Vector3(14, 3, 14), (hi - lo) + Vector3(28, 30, 28))
		p.add_multimesh(VegetationLibrary.get_mesh(sp, 0, 2), VegetationLibrary.get_material(sp, 2), e[0], e[1], aabb,
				{"shadow": false, "vis_begin": begin, "vis_end": end, "tag": StringName("%s_far" % sp)})
	cell.payload = p


## Quick biome check at the block centre and corners: skip blocks of sea, ice and city.
static func _block_may_have_trees(cx: float, cz: float) -> bool:
	for k in 5:
		var x: float = cx + [0.0, -14.0, 14.0, -14.0, 14.0][k]
		var z: float = cz + [0.0, -14.0, -14.0, 14.0, 14.0][k]
		var b := WorldData.get_biome(x, z)
		if b != VegetationRules.Bio.OCEAN and b != VegetationRules.Bio.CITY and b != VegetationRules.Bio.ICE \
				and WorldData.get_height(x, z) > 0.5:
			return true
	return false
