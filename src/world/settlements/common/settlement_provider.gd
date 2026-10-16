class_name SettlementProvider
extends ContentProvider
## Streams one settlement plan in 128 m cells (WorldContent provider). Per cell, on a worker:
## every piece is built (archetypes come from KitCache, unique pieces are built in place) and
## merged into ONE mesh per LOD with at most four material surfaces:
##   LOD0  full detail, visible up to cfg.lod0_end, casts shadows
##   LOD1  simplified (no small props), cfg.lod0_end .. cfg.lod1_end
## Both share one AABB (KitMerger.normalize_aabb) so the visibility ranges hand over at the same
## distance. LOD2 silhouettes beyond lod1_end come from SettlementFarProvider. Collision (the
## LOD0 boxes + trimesh faces) is attached only while the focus is within
## cfg.collision_range of the cell (update_cell), lights are capped per cell (LightBudget), and
## piece extras (particles, sounds, animated nodes, markers) are created on the main thread.

const COLLISION_HYSTERESIS := 40.0

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
	var res := build_lods(cell.coord, origin, cell.seed)
	var r0: KitResult = res[0]
	var r1: KitResult = res[1]
	var shadows: bool = cfg.get("shadows", true)
	var tag := String(id)
	r0.add_to_payload(p, Transform3D.IDENTITY, {"vis_end": float(cfg["lod0_end"]), "margin": 12.0, "shadow": shadows,
		"collision": false, "lights": false, "tag": StringName(tag + "_lod0")})
	r1.add_to_payload(p, Transform3D.IDENTITY, {"vis_begin": float(cfg["lod0_end"]), "vis_end": float(cfg["lod1_end"]),
		"margin": 12.0, "shadow": shadows, "collision": false, "lights": false, "tag": StringName(tag + "_lod1")})
	p.data["collision"] = {"boxes": r0.boxes, "faces": r0.faces}
	# budgeted lights: highest priority first, then a stable shuffle
	var lights: Array = r0.lights.duplicate()
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


## LOD0 and LOD1 KitResults of a cell (relative to `origin`). Thread-safe; also used by tests.
func build_lods(coord: Vector2i, origin: Vector3, seed: int = 1) -> Array:
	var m0 := KitMerger.new()
	var m1 := KitMerger.new()
	var k0 := BuildingKit.new(builder.palette(), 0, seed)
	var k1 := BuildingKit.new(builder.palette(), 1, seed)
	for i in plan.cell_pieces(coord):
		var pc: Dictionary = plan.pieces[i]
		if _skipped(pc):
			continue
		var t := Transform3D(Basis(Vector3.UP, float(pc["yaw"])), (pc["pos"] as Vector3) - origin)
		var lod := int(pc["lod"])
		if String(pc["arch"]) != "":
			m0.add(builder.archetype(pc, 0), t)
			if lod >= 1:
				m1.add(builder.archetype(pc, 1), t, {"collision": false, "lights": false})
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
