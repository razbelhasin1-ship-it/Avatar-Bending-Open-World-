class_name SettlementFarProvider
extends ContentProvider
## LOD2 of a settlement: silhouettes (walls, towers, spires, domes, roofs, lit windows) that read
## from kilometres away. 512 m cells with a long range (cfg.far_end); each cell holds one small
## mesh per 128 m near-grid sub-cell, sharing that sub-cell's AABB with the near provider's
## LOD0/LOD1 meshes, so LOD1 -> LOD2 hands over at exactly cfg.lod1_end. Only pieces with
## "lod" >= 2 are drawn. No collision, lights or shadows.

const FACTOR := 4

var plan: SettlementPlan
var builder: SettlementBuilder
var cfg: Dictionary = {}
var skip_tags: Array = []


func _init(p_plan: SettlementPlan = null, p_builder: SettlementBuilder = null) -> void:
	plan = p_plan
	builder = p_builder
	id = StringName("settlement_far_%s" % (String(plan.id) if plan else "none"))
	cell_size = (plan.cell_size if plan else 128.0) * FACTOR
	priority = 6
	unload_margin = 256.0


func configure() -> bool:
	var c := SettlementSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	range_m = float(cfg["far_end"]) + cell_size * 0.5
	NationPalette.prepare_materials()
	return changed


func wants_cell(coord: Vector2i) -> bool:
	return plan != null and not plan.sub_cells(coord, FACTOR).is_empty()


## WORKER THREAD.
func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var origin := cell.origin()
	for sub in plan.sub_cells(cell.coord, FACTOR):
		# night glows of every piece (also the small ones without a far silhouette)
		var glows: Array = []
		for i in plan.cell_pieces(sub):
			var pc: Dictionary = plan.pieces[i]
			var tag: Variant = (pc["spec"] as Dictionary).get("tag")
			if tag == null or not skip_tags.has(tag):
				glows.append_array(builder.piece_glows(pc))
		SettlementFx.add_glows(p, glows, origin, plan.cell_aabb(sub, origin), float(cfg["lod1_end"]), float(cfg["far_end"]),
				StringName("%s_glow_%d_%d" % [id, sub.x, sub.y]))
		var r := build_sub(sub, origin, cell.seed)
		if r.surfaces.is_empty():
			continue
		# no ink outline pass (it fades out by 60 m; LOD2 starts at >= 300 m); desktop cross-fades
		# with the near provider's LOD1 (same AABB, same margin) and dissolves at the far end
		var fm := float(cfg.get("fade_margin", 0.0))
		r.add_to_payload(p, Transform3D.IDENTITY, {"vis_begin": float(cfg["lod1_end"]), "vis_end": float(cfg["far_end"]),
			"margin": fm, "fade": GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if fm > 0.0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
			"shadow": false, "collision": false, "lights": false,
			"tag": StringName("%s_%d_%d" % [id, sub.x, sub.y]), "outline": false, "lods": bool(cfg.get("mesh_lods", false)),
			"lod_bias": float(cfg.get("sil_lod_bias", 1.0))})
	cell.payload = p


## LOD2 result of one near-grid sub-cell (relative to `origin`).
func build_sub(sub: Vector2i, origin: Vector3, seed: int = 1) -> KitResult:
	var m := KitMerger.new()
	if bool(cfg.get("merge_far", false)):
		m.slot_map = SettlementProvider.MERGED_SLOTS     # phones: one surface, one draw call
	var kit := BuildingKit.new(builder.palette(), 2, seed)
	for i in plan.cell_pieces(sub):
		var pc: Dictionary = plan.pieces[i]
		if int(pc["lod"]) < 2:
			continue
		var tag: Variant = (pc["spec"] as Dictionary).get("tag")
		if tag != null and skip_tags.has(tag):
			continue
		var t := Transform3D(Basis(Vector3.UP, float(pc["yaw"])), (pc["pos"] as Vector3) - origin)
		if String(pc["arch"]) != "":
			m.add(builder.archetype(pc, 2), t, {"collision": false, "lights": false})
		else:
			kit.push(t)
			builder.build_piece(kit, pc)
			kit.pop()
	m.add(kit.build(), Transform3D.IDENTITY, {"collision": false, "lights": false})
	var box := plan.cell_aabb(sub, origin)
	m.normalize_aabb(box)
	return m.to_result(box)
