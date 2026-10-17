class_name SettlementProvider
extends ContentProvider
## Streams one settlement plan in 128 m cells (WorldContent provider). Per cell, on a worker:
## every piece is built (archetypes come from KitCache, unique pieces are built in place) and
## merged into ONE mesh per LOD with at most four material surfaces:
##   LOD0  full detail, visible up to cfg.lod0_end, casts shadows
##   LOD1  simplified (no small props), cfg.lod0_end .. cfg.lod1_end
## Both share one AABB (KitMerger.normalize_aabb) so the visibility ranges hand over at the same
## distance, with NO visibility margins: Godot's margin hysteresis keeps a freshly streamed,
## not-yet-visible instance hidden inside the whole margin band, so two LODs handing over with
## margins leave a cell invisible while the camera sits in the band. LOD2 silhouettes beyond lod1_end come from SettlementFarProvider. Collision (the
## LOD0 boxes + trimesh faces) is attached only while the focus is within
## cfg.collision_range of the cell (update_cell), lights are capped per cell (LightBudget), and
## piece extras (particles, sounds, animated nodes, markers) are created on the main thread.

const COLLISION_HYSTERESIS := 40.0
## Slot remap of merged distant meshes (cfg.merge_far, phones): one solid surface.
const MERGED_SLOTS := {&"ice": &"solid", &"glow": &"solid", &"cloth": &"solid"}

var plan: SettlementPlan
var builder: SettlementBuilder
var cfg: Dictionary = {}
## Pieces whose spec has a "tag" in this list are skipped (e.g. the airball court while the
## tutorial's training ground stands there).
var skip_tags: Array = []
## Statistics: build ms per cell, triangle counts.
var stats := {"cells": 0, "tris0": 0, "tris1": 0, "build_ms_max": 0.0, "bodies": 0}
var _stats_mutex := Mutex.new()


func _init(p_plan: SettlementPlan = null, p_builder: SettlementBuilder = null) -> void:
	plan = p_plan
	builder = p_builder
	id = StringName("settlement_%s" % (String(plan.id) if plan else "none"))
	cell_size = plan.cell_size if plan else 128.0
	priority = 7
	unload_margin = 96.0


func configure() -> bool:
	var c := SettlementSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	range_m = float(cfg["lod1_end"]) + cell_size * 0.75
	NationPalette.prepare_materials()
	return changed


func wants_cell(coord: Vector2i) -> bool:
	return plan != null and plan.has_cell(coord)


func _skipped(pc: Dictionary) -> bool:
	if skip_tags.is_empty():
		return false
	var tag: Variant = (pc["spec"] as Dictionary).get("tag")
	return tag != null and skip_tags.has(tag)


## WORKER THREAD.
func build_cell(cell: ContentCell) -> void:
	var t0 := Time.get_ticks_usec()
	var p := CellPayload.new()
	var origin := cell.origin()
	var shadows: bool = cfg.get("shadows", true)
	var tag := String(id)
	var l0 := lod0_end()
	var r0: KitResult
	var r1: KitResult
	var lod1_opts := {"vis_begin": l0, "vis_end": float(cfg["lod1_end"]), "margin": 0.0,
		"shadow": shadows and bool(cfg.get("lod1_shadows", true)), "collision": false, "lights": false,
		"tag": StringName(tag + "_lod1"), "outline": false,   # no ink outline pass: it fades out by 60 m
		"lods": bool(cfg.get("mesh_lods", false))}
	if bool(cfg.get("quad_lod0", false)):
		# Phones: quadrant LOD0 under the cell's LOD1 (HLOD visibility parent, see build_quads)
		var q := build_quads(cell.coord, origin, cell.seed)
		r0 = q["r0"]
		r1 = q["lod1"]
		r1.add_to_payload(p, Transform3D.IDENTITY, lod1_opts)
		var parent := StringName(tag + "_lod1") if not r1.surfaces.is_empty() else &""
		var fine := quad_fine()
		for i in 4:
			var of := {"vis_end": fine, "margin": 0.0, "shadow": shadows, "collision": false, "lights": false,
				"tag": StringName("%s_lod0q%d" % [tag, i]), "vis_parent": parent, "lods": bool(cfg.get("mesh_lods", false))}
			var om := {"vis_begin": fine, "margin": 0.0, "shadow": shadows, "collision": false, "lights": false,
				"tag": StringName("%s_lod0m%d" % [tag, i]), "vis_parent": parent, "outline": false,
				"lods": bool(cfg.get("mesh_lods", false))}
			if parent == &"":
				om["vis_end"] = l0
			(q["fine"][i] as KitResult).add_to_payload(p, Transform3D.IDENTITY, of)
			(q["mid"][i] as KitResult).add_to_payload(p, Transform3D.IDENTITY, om)
	else:
		var res := build_lods(cell.coord, origin, cell.seed)
		r0 = res[0]
		r1 = res[1]
		# Desktop: the hand-overs cross-fade over cfg.fade_margin m each side (engine fade, no
		# hysteresis with a fade mode, so the margin band never leaves a gap - perf_polish).
		var fm := float(cfg.get("fade_margin", 0.0))
		var fade := GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if fm > 0.0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		r0.add_to_payload(p, Transform3D.IDENTITY, {"vis_end": l0, "margin": fm, "fade": fade, "shadow": shadows,
			"collision": false, "lights": false, "tag": StringName(tag + "_lod0")})
		lod1_opts["margin"] = fm
		lod1_opts["fade"] = fade
		r1.add_to_payload(p, Transform3D.IDENTITY, lod1_opts)
	p.data["collision"] = {"boxes": r0.boxes, "faces": r0.faces}
	# night glow sprites sit exactly on the LOD0 lamps and lit windows (light records)
	SettlementFx.add_glows(p, SettlementFx.glows_from_lights(r0.lights, origin), origin, plan.cell_aabb(cell.coord, origin),
			0.0, float(cfg["lod1_end"]), StringName(tag + "_glow"))
	# budgeted lights: highest priority first, then a stable shuffle
	var lights: Array = r0.lights.filter(func(l: Dictionary) -> bool: return not l.get("glow_only", false))
	lights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa != pb:
			return pa > pb
		var ha := (a["position"] as Vector3).x * 13.1 + (a["position"] as Vector3).z * 7.7
		var hb := (b["position"] as Vector3).x * 13.1 + (b["position"] as Vector3).z * 7.7
		return fposmod(ha, 1.0) < fposmod(hb, 1.0))
	lights.resize(mini(lights.size(), int(cfg.get("cell_lights", 10))))
	if not lights.is_empty():
		p.add_call(func(c: ContentCell) -> void:
			for l: Dictionary in lights:
				c.root.add_child(LightBudget.make_light(l)))
	var extras: Array = []
	for i in plan.cell_pieces(cell.coord):
		var pc: Dictionary = plan.pieces[i]
		if not _skipped(pc):
			extras.append_array(builder.piece_extras(pc))
			builder.piece_payload(pc, p, origin)
	if not extras.is_empty():
		p.add_call(func(c: ContentCell) -> void: SettlementProvider.spawn_extras(c, extras))
	p.data["tris"] = r0.triangle_count
	cell.payload = p
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_stats_mutex.lock()
	stats["cells"] = int(stats["cells"]) + 1
	stats["tris0"] = int(stats["tris0"]) + r0.triangle_count
	stats["tris1"] = int(stats["tris1"]) + r1.triangle_count
	stats["build_ms_max"] = maxf(float(stats["build_ms_max"]), ms)
	_stats_mutex.unlock()


## LOD0 end of this settlement (the preset's, tighter on phones: SettlementSettings.lod0_end_for).
func lod0_end() -> float:
	return SettlementSettings.lod0_end_for(cfg, cell_size) if not cfg.is_empty() else 220.0


## Phones (cfg.quad_lod0): full detail ends this far from a quadrant's centre: just past the
## quadrant half diagonal, so the quadrant around the camera is always full detail.
func quad_fine() -> float:
	return cell_size * 0.5 * 0.7072 + 7.0


## Phones: the cell's LOD0 split into four quadrant meshes in two versions - `fine` (kit LOD 0,
## ink outline, visible within quad_fine() of the quadrant centre) and `mid` (every piece at kit
## LOD 1 as one surface, beyond it) - both children of the cell's LOD1 mesh (Godot HLOD visibility
## parent: they only show while LOD1 is hidden for being closer than lod0_end, so the hand-over is
## exact). A 128 m cell around the camera costs one quarter of its full detail instead of all of
## it. Collision, lights and glows still come from the full LOD 0 build (`r0`: boxes, faces,
## lights; no surfaces). Each quadrant's fine and mid meshes share one AABB (centred on the
## quadrant, grown 48 m for pieces reaching across its edge). Thread-safe.
## Returns {"r0": KitResult, "lod1": KitResult, "fine": [4 KitResult], "mid": [4 KitResult]}.
func build_quads(coord: Vector2i, origin: Vector3, seed: int = 1) -> Dictionary:
	var lod1_kit := int(cfg.get("lod1_kit", 1))
	var m1 := KitMerger.new()
	if bool(cfg.get("merge_far", false)):
		m1.slot_map = MERGED_SLOTS
	var k1 := BuildingKit.new(builder.palette(), lod1_kit, seed)
	var mf: Array[KitMerger] = []
	var mm: Array[KitMerger] = []
	var kf: Array[BuildingKit] = []
	var km: Array[BuildingKit] = []
	for i in 4:
		mf.append(KitMerger.new())
		var m := KitMerger.new()
		m.slot_map = MERGED_SLOTS
		mm.append(m)
		kf.append(BuildingKit.new(builder.palette(), 0, seed + i))
		km.append(BuildingKit.new(builder.palette(), 1, seed + i))
	for i in plan.cell_pieces(coord):
		var pc: Dictionary = plan.pieces[i]
		if _skipped(pc):
			continue
		var local := (pc["pos"] as Vector3) - origin
		var t := Transform3D(Basis(Vector3.UP, float(pc["yaw"])), local)
		var qi := (1 if local.x >= 0.0 else 0) + (2 if local.z >= 0.0 else 0)
		var lod := int(pc["lod"])
		if String(pc["arch"]) != "":
			mf[qi].add(builder.archetype(pc, 0), t)
			mm[qi].add(builder.archetype(pc, 1), t, {"collision": false, "lights": false})
			if lod >= 1:
				m1.add(builder.archetype(pc, lod1_kit), t, {"collision": false, "lights": false})
		else:
			kf[qi].push(t)
			builder.build_piece(kf[qi], pc)
			kf[qi].pop()
			km[qi].push(t)
			builder.build_piece(km[qi], pc)
			km[qi].pop()
			if lod >= 1:
				k1.push(t)
				builder.build_piece(k1, pc)
				k1.pop()
	m1.add(k1.build(), Transform3D.IDENTITY, {"collision": false, "lights": false})
	var box := plan.cell_aabb(coord, origin)
	m1.normalize_aabb(box)
	var r0 := KitResult.new()
	r0.aabb = box
	var fine: Array = []
	var mid: Array = []
	var half := cell_size * 0.25
	for qi in 4:
		mf[qi].add(kf[qi].build())
		mm[qi].add(km[qi].build(), Transform3D.IDENTITY, {"collision": false, "lights": false})
		# quadrant centre relative to the cell origin (the cell centre), same split as above
		var c := Vector3(half if qi % 2 == 1 else -half, 0.0, half if qi >= 2 else -half)
		var qbox := AABB(Vector3(c.x - half - 48.0, box.position.y, c.z - half - 48.0), Vector3(half * 2.0 + 96.0, box.size.y, half * 2.0 + 96.0))
		mf[qi].normalize_aabb(qbox)
		mm[qi].normalize_aabb(qbox)
		var rf := mf[qi].to_result(qbox)
		fine.append(rf)
		mid.append(mm[qi].to_result(qbox))
		r0.boxes.append_array(rf.boxes)
		r0.faces.append_array(rf.faces)
		r0.lights.append_array(rf.lights)
		r0.triangle_count += rf.triangle_count
	return {"r0": r0, "lod1": m1.to_result(box), "fine": fine, "mid": mid}


## LOD0 and LOD1 KitResults of a cell (relative to `origin`). Thread-safe; also used by tests.
## The LOD1 band is built with the kit LOD cfg.lod1_kit (1; phones 2 = silhouette recipes) and,
## with cfg.merge_far, as one surface.
func build_lods(coord: Vector2i, origin: Vector3, seed: int = 1) -> Array:
	var m0 := KitMerger.new()
	var m1 := KitMerger.new()
	var lod1_kit := int(cfg.get("lod1_kit", 1))
	if bool(cfg.get("merge_far", false)):
		m1.slot_map = MERGED_SLOTS
	var k0 := BuildingKit.new(builder.palette(), 0, seed)
	var k1 := BuildingKit.new(builder.palette(), lod1_kit, seed)
	for i in plan.cell_pieces(coord):
		var pc: Dictionary = plan.pieces[i]
		if _skipped(pc):
			continue
		var t := Transform3D(Basis(Vector3.UP, float(pc["yaw"])), (pc["pos"] as Vector3) - origin)
		var lod := int(pc["lod"])
		if String(pc["arch"]) != "":
			m0.add(builder.archetype(pc, 0), t)
			if lod >= 1:
				m1.add(builder.archetype(pc, lod1_kit), t, {"collision": false, "lights": false})
		else:
			k0.push(t)
			builder.build_piece(k0, pc)
			k0.pop()
			if lod >= 1:
				k1.push(t)
				builder.build_piece(k1, pc)
				k1.pop()
	m0.add(k0.build())
	m1.add(k1.build(), Transform3D.IDENTITY, {"collision": false, "lights": false})
	var box := plan.cell_aabb(coord, origin)
	m0.normalize_aabb(box)
	m1.normalize_aabb(box)
	return [m0.to_result(box), m1.to_result(box)]


## Collision follows the focus: attached within collision_range, removed beyond + hysteresis.
func update_cell(cell: ContentCell, distance: float) -> void:
	var has := cell.user.has("body")
	var r := float(cfg.get("collision_range", 120.0))
	if not has and distance <= r:
		var p := cell.payload as CellPayload
		if p == null or not p.data.has("collision"):
			return
		var body := make_body(p.data["collision"])
		if body:
			cell.root.add_child(body)
			cell.user["body"] = body
			stats["bodies"] = int(stats["bodies"]) + 1
	elif has and distance > r + COLLISION_HYSTERESIS:
		var b: Node = cell.user["body"]
		if is_instance_valid(b):
			b.queue_free()
		cell.user.erase("body")


func release_cell(cell: ContentCell) -> void:
	cell.user.erase("body")


## StaticBody3D (Layers.WORLD) from {"boxes": [[Transform3D, size]], "faces": PackedVector3Array}.
static func make_body(col: Dictionary) -> StaticBody3D:
	var boxes: Array = col.get("boxes", [])
	var faces: PackedVector3Array = col.get("faces", PackedVector3Array())
	if boxes.is_empty() and faces.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "SettlementCollision"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.add_to_group(&"settlement_collision")
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.transform = b[0]
		body.add_child(cs)
	if not faces.is_empty():
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		sh.backface_collision = true
		cs.shape = sh
		body.add_child(cs)
	return body


## Main thread: particles, sounds, animated nodes and markers of a cell (positions are world).
static func spawn_extras(cell: ContentCell, extras: Array) -> void:
	var origin := cell.origin()
	for e: Dictionary in extras:
		match e.get("type"):
			&"particles":
				var fx := PropFx.particles(e["kind"])
				fx.position = (e["position"] as Vector3) - origin
				cell.root.add_child(fx)
			&"sound":
				var sid := Audio.play_loop(e["name"], null, float(e.get("db", -6.0)), 2.0, e["position"])
				if sid > 0:
					cell.loops.append(sid)
			&"node":
				var n: Node3D = (e["make"] as Callable).call(cell)
				if n:
					cell.root.add_child(n)
			&"marker":
				cell.root.add_child(PropFx.marker(e["group"], (e["position"] as Vector3) - origin, float(e.get("yaw", 0.0)),
						e.get("meta", {})))
