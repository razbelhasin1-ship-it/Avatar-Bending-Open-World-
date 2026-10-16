class_name VegetationProvider
extends ContentProvider
## Trees, shrubs, ferns, logs, rocks, ice and farm hedges in 256 m cells around the focus.
##
## Per cell and species variant: a LOD1 MultiMesh with every instance (it also casts the shadows
## of all of them) and, for cells near the camera, a LOD0 MultiMesh (+ ink outline) holding only
## the instances within tree_lod0 of the camera, rebuilt on the main thread as the camera moves
## (a few cells per scan). The hand-over LOD0 -> LOD1 -> far impostors (ForestFarProvider beyond
## tree_range) is per instance in the shader with dithered bands; cell visibility ranges cull
## whole MultiMeshes outside their band. Tree trunks and boulders register pooled colliders
## (active near the focus only). Budgets: VegetationSettings.

const HALF_DIAG := 181.0          # half diagonal of a 256 m cell
const BLOCK := 32.0               # LOD0 sub-block size
const HEDGE_GRID := 3.0

const LOD0_REBUILD_MOVE := 5.0     # camera metres before a near cell's LOD0 subsets are rebuilt
const SHADOW_REBUILD_MOVE := 14.0  # ... and its shadow proxies (larger radius, change slowly)
const LOD0_REBUILDS_PER_SCAN := 2

var cfg: Dictionary = {}
var _rebuilds_left := LOD0_REBUILDS_PER_SCAN


func _init() -> void:
	id = &"vegetation"
	cell_size = 256.0
	priority = 20
	unload_margin = 40.0


func configure() -> bool:
	TerrainPatterns.load_data()
	VegetationLibrary.build_async()
	var c := VegetationSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	VegetationSettings.apply(cfg)
	range_m = float(cfg["tree_range"]) + 8.0
	_prepare_materials()
	return changed


func tick() -> void:
	VegetationLibrary.poll()
	_rebuilds_left = LOD0_REBUILDS_PER_SCAN


## Near-camera subsets of a cell (main thread, every scan): per species group a LOD0
## MultiMesh (instances within tree/small_lod0, drawn with outlines, no shadows) and a
## shadow-only LOD1 proxy (instances within shadow_range). Whole 32 m blocks are selected, so a
## rebuild is a handful of buffer slices; at most LOD0_REBUILDS_PER_SCAN cells rebuild per scan.
func update_cell(cell: ContentCell, distance: float) -> void:
	var p := cell.payload as CellPayload
	if p == null or not p.data.has("lod0"):
		return
	var groups: Array = p.data["lod0"]
	var st: Dictionary = cell.user.get("near", {})
	var cam := content.camera_position()
	var shadow_r := float(cfg["shadow_range"]) if bool(cfg.get("shadows", true)) else 0.0
	var reach := maxf(maxf(float(cfg["tree_lod0"]), float(cfg["small_lod0"])), shadow_r) + 10.0
	if distance > reach:
		if st.get("shown", false):
			for mmi in st.get("lod0", []) + st.get("shadow", []):
				if mmi and is_instance_valid(mmi):
					(mmi as MultiMeshInstance3D).visible = false
			st["shown"] = false
			st["pos"] = Vector3.INF
		return
	var last: Vector3 = st.get("pos", Vector3.INF)
	if last.is_finite() and last.distance_to(cam) < LOD0_REBUILD_MOVE:
		return
	var last_sh: Vector3 = st.get("shadow_pos", Vector3.INF)
	var redo_shadow := not last_sh.is_finite() or last_sh.distance_to(cam) >= SHADOW_REBUILD_MOVE
	if _rebuilds_left <= 0:
		return
	_rebuilds_left -= 1
	var lod0s: Array = st.get("lod0", [])
	var shadows: Array = st.get("shadow", [])
	lod0s.resize(groups.size())
	shadows.resize(groups.size())
	var local_cam := cam - cell.origin()
	for g in groups.size():
		var e: Dictionary = groups[g]
		lod0s[g] = _subset_mmi(cell, lod0s[g], e, local_cam, float(e["reach"]) + 10.0, e["mesh"], e["material"], false, e["tag"])
		if e["casts"] and shadow_r > 0.0 and redo_shadow:
			shadows[g] = _subset_mmi(cell, shadows[g], e, local_cam, shadow_r + 10.0, e["mesh1"], e["material1"], true, e["tag_shadow"])
	st["lod0"] = lod0s
	st["shadow"] = shadows
	st["pos"] = cam
	if redo_shadow:
		st["shadow_pos"] = cam
	st["shown"] = true
	cell.user["near"] = st


## Creates/updates a MultiMesh with the instances of the blocks within `r` of the camera.
func _subset_mmi(cell: ContentCell, mmi: Variant, e: Dictionary, local_cam: Vector3, r: float, mesh: Mesh, mat: Material,
		shadow_only: bool, tag: StringName) -> MultiMeshInstance3D:
	var nb := int(cell_size / BLOCK)
	var half := cell_size * 0.5
	var src: PackedFloat32Array = e["buffer"]
	var starts: PackedInt32Array = e["starts"]
	var sub := PackedFloat32Array()
	var run_a := -1
	var run_b := -1
	for k in nb * nb:
		var a := starts[k]
		var b := starts[k + 1]
		if a == b:
			continue
		var bx := -half + (k % nb) * BLOCK
		var bz := -half + (k / nb) * BLOCK
		var cx := clampf(local_cam.x, bx, bx + BLOCK) - local_cam.x
		var cz := clampf(local_cam.z, bz, bz + BLOCK) - local_cam.z
		if cx * cx + cz * cz > r * r:
			continue
		if a == run_b:
			run_b = b
		else:
			if run_a >= 0:
				sub.append_array(src.slice(run_a * 16, run_b * 16))
			run_a = a
			run_b = b
	if run_a >= 0:
		sub.append_array(src.slice(run_a * 16, run_b * 16))
	var n := sub.size() / 16
	var node: MultiMeshInstance3D = mmi if mmi != null and is_instance_valid(mmi) else null
	if n == 0:
		if node:
			node.visible = false
		return node
	# capacity: a power of two >= the subset (kept while the subset fits and is not tiny), so a
	# rebuild uploads about the near subset rather than the whole group and re-allocations of
	# instance_count stay rare
	var capacity := 64
	while capacity < n:
		capacity *= 2
	capacity = mini(capacity, src.size() / 16)
	if node and node.multimesh.instance_count >= n and node.multimesh.instance_count <= capacity * 4:
		capacity = node.multimesh.instance_count
	sub.resize(capacity * 16)
	if node == null:
		node = content.spawn_multimesh(cell, {"mesh": mesh, "material": mat, "buffer": sub, "count": capacity,
			"aabb": e["aabb"], "shadow": shadow_only, "tag": tag})
		if shadow_only:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		var mm := node.multimesh
		if mm.instance_count != capacity:
			mm.instance_count = capacity
		mm.buffer = sub
		node.visible = true
	node.multimesh.visible_instance_count = n
	return node


func wants_cell(_coord: Vector2i) -> bool:
	return VegetationLibrary.is_ready()


## Materials are created on the main thread before any worker needs them.
static func _prepare_materials() -> void:
	for id: StringName in VegetationLibrary.SPECIES:
		for lod in VegetationLibrary.lod_count(id):
			VegetationLibrary.get_material(id, lod)


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var origin := cell.origin()
	var groups := {}          # "species|variant" -> [species, variant, layer, buf, count, lo: Vector3, hi: Vector3]
	var g0x := int(floor(cell.rect.position.x / VegetationScatter.GRID))
	var g0z := int(floor(cell.rect.position.y / VegetationScatter.GRID))
	var n := int(cell_size / VegetationScatter.GRID)
	for j in n:
		for i in n:
			for it: VegetationScatter.Item in VegetationScatter.evaluate(g0x + i, g0z + j, cfg, cell.exclusions):
				_add(groups, it, origin)
				_collider(p, it)
	_hedges(cell, groups, origin)
	_emit(p, groups)
	cell.payload = p


func _add(groups: Dictionary, it: VegetationScatter.Item, origin: Vector3) -> void:
	var key := "%s|%d" % [it.species, it.variant]
	if not groups.has(key):
		groups[key] = [it.species, it.variant, it.layer, PackedFloat32Array(), 0, Vector3.INF, -Vector3.INF]
	var e: Array = groups[key]
	var local := it.pos - origin
	CellPayload.write_instance(e[3], Transform3D(it.basis, local), it.tint)
	e[4] = int(e[4]) + 1
	e[5] = (e[5] as Vector3).min(local)
	e[6] = (e[6] as Vector3).max(local)


func _collider(p: CellPayload, it: VegetationScatter.Item) -> void:
	var spec: Dictionary = VegetationLibrary.SPECIES[it.species]
	var type: StringName = spec.get("collide", &"")
	if type == &"":
		return
	var r := float(spec["radius"]) * it.scale
	if type == &"sphere":
		if it.scale < 0.9:
			return
		p.add_collider(&"sphere", Transform3D(Basis(), it.pos + Vector3(0, r * 0.35, 0)), Vector3(r * 0.85, 0, 0))
	else:
		var hgt := minf(float(spec["height"]) * it.scale, 5.0)
		p.add_collider(&"cylinder", Transform3D(Basis(), it.pos + Vector3(0, hgt * 0.5, 0)), Vector3(r, hgt, 0))


## Hedge rows along some farm plot borders (follows the terrain shader's plot layout).
func _hedges(cell: ContentCell, groups: Dictionary, origin: Vector3) -> void:
	var any_farm := false
	for k in 25:
		var x := cell.rect.position.x + (k % 5 + 0.5) * cell_size / 5.0
		var z := cell.rect.position.y + (k / 5 + 0.5) * cell_size / 5.0
		if WorldData.get_ground_hints(x, z).b > 0.35:
			any_farm = true
			break
	if not any_farm or not TerrainPatterns.has_noise():
		return
	var n := int(cell_size / HEDGE_GRID)
	var dens := float(cfg.get("small_density", 1.0))
	for j in n:
		for i in n:
			var x := cell.rect.position.x + (i + 0.5) * HEDGE_GRID
			var z := cell.rect.position.y + (j + 0.5) * HEDGE_GRID
			var gh := WorldData.get_ground_hints(x, z)
			if gh.b < 0.45 or gh.g > 0.05 or WorldData.get_road(x, z) > 0.05:
				continue
			if cell.exclusions and cell.exclusions.blocked(x, z, ContentExclusions.TAG_TREES):
				continue
			var fp := TerrainPatterns.farm_plot(x, z)
			if float(fp["border"]) > 1.3:
				continue
			var f: Vector2 = fp["fp"]
			var plot: Vector2 = fp["plot"]
			var dx := minf(f.x, 1.0 - f.x) * TerrainPatterns.PLOT_SIZE.x
			var dz := minf(f.y, 1.0 - f.y) * TerrainPatterns.PLOT_SIZE.y
			var vertical := dx < dz
			var edge := Vector3i(int(plot.x) + (1 if f.x > 0.5 else 0), int(plot.y), 0) if vertical else Vector3i(int(plot.x), int(plot.y) + (1 if f.y > 0.5 else 0), 1)
			var eh := ContentHash.hash4(VegetationScatter.VEG_SEED, edge.x, edge.y, edge.z + 40)
			if ContentHash.unit(eh) > 0.42 * clampf(dens + 0.3, 0.4, 1.0):
				continue
			var px := x
			var pz := z
			if vertical:
				px += (-f.x * TerrainPatterns.PLOT_SIZE.x) if f.x < 0.5 else (1.0 - f.x) * TerrainPatterns.PLOT_SIZE.x
			else:
				pz += (-f.y * TerrainPatterns.PLOT_SIZE.y) if f.y < 0.5 else (1.0 - f.y) * TerrainPatterns.PLOT_SIZE.y
			var hh := ContentHash.hash4(eh, i, j)
			var it := VegetationScatter.Item.new()
			it.species = &"hedge"
			it.layer = 1
			var yaw := (PI * 0.5 if vertical else 0.0) + (ContentHash.unit(hh) - 0.5) * 0.2
			var s := 0.5 + 0.12 * ContentHash.unit(hh >> 3)
			it.basis = Basis(Vector3.UP, yaw).scaled(Vector3(s, 0.8 + 0.4 * ContentHash.unit(hh >> 6), 0.9 + 0.3 * ContentHash.unit(hh >> 9)))
			it.pos = Vector3(px, WorldData.get_height(px, pz) - 0.1, pz)
			var k := 0.88 + 0.24 * ContentHash.unit(hh >> 12)
			it.tint = Color(k, k, k * 0.95, ContentHash.unit(hh >> 15))
			_add(groups, it, origin)


## Reorders a buffer by 32 m sub-block; returns [buffer, starts (block k = instances [starts[k], starts[k+1]))].
func _sort_blocks(buf: PackedFloat32Array, count: int) -> Array:
	var nb := int(cell_size / BLOCK)
	var half := cell_size * 0.5
	var keys := PackedInt32Array()
	keys.resize(count)
	var counts := PackedInt32Array()
	counts.resize(nb * nb + 1)
	for i in count:
		var bx := clampi(int((buf[i * 16 + 3] + half) / BLOCK), 0, nb - 1)
		var bz := clampi(int((buf[i * 16 + 11] + half) / BLOCK), 0, nb - 1)
		keys[i] = bz * nb + bx
		counts[keys[i] + 1] += 1
	for k in nb * nb:
		counts[k + 1] += counts[k]
	var starts := counts.duplicate()
	var fill := counts.duplicate()
	var out := PackedFloat32Array()
	out.resize(count * 16)
	for i in count:
		var dst := fill[keys[i]] * 16
		fill[keys[i]] += 1
		for c in 16:
			out[dst + c] = buf[i * 16 + c]
	return [out, starts]


func _emit(p: CellPayload, groups: Dictionary) -> void:
	var shadows: bool = cfg.get("shadows", true)
	for key: String in groups:
		var e: Array = groups[key]
		var sp: StringName = e[0]
		var variant: int = e[1]
		var layer: int = e[2]
		var count: int = e[4]
		var spec: Dictionary = VegetationLibrary.SPECIES[sp]
		var hgt := float(spec.get("height", 2.0)) * 1.5
		var lo: Vector3 = e[5]
		var hi: Vector3 = e[6]
		var aabb := AABB(lo - Vector3(10, 3, 10), (hi - lo) + Vector3(20, hgt + 6, 20))
		var sorted := _sort_blocks(e[3], count)
		var buf: PackedFloat32Array = sorted[0]
		var lod0: float
		var end: float
		if layer == 0:
			lod0 = float(cfg["tree_lod0"])
			end = float(cfg["tree_range"])
		else:
			lod0 = float(cfg["small_lod0"])
			end = float(cfg["small_range"])
		var m0 := VegetationLibrary.get_mesh(sp, variant, 0)
		var m1 := VegetationLibrary.get_mesh(sp, variant, 1)
		# LOD1: every instance, no shadows (near shadows come from the proxy subsets)
		var big_rock := sp == &"serac" or sp.begins_with("rock") or sp == &"ice_chunk" or sp == &"lava_rock"
		p.add_multimesh(m1, VegetationLibrary.get_material(sp, 1), buf, count, aabb,
				{"shadow": false, "vis_end": end + HALF_DIAG + 10.0, "tag": StringName("%s_%d_lod1" % [sp, variant])})
		# LOD0: subset near the camera (whole 32 m blocks), maintained by update_cell
		if not p.data.has("lod0"):
			p.data["lod0"] = []
		(p.data["lod0"] as Array).append({"mesh": m0, "material": VegetationLibrary.get_material(sp, 0), "buffer": buf,
			"starts": sorted[1], "aabb": aabb, "reach": lod0, "tag": StringName("%s_%d_lod0" % [sp, variant]),
			"mesh1": m1, "material1": VegetationLibrary.get_material(sp, 1), "casts": shadows and (layer == 0 or big_rock),
			"tag_shadow": StringName("%s_%d_shadow" % [sp, variant])})
