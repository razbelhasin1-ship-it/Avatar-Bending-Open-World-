class_name VegetationLibrary
extends RefCounted
## Species catalogue + procedural mesh cache. Meshes are generated once per run: geometry on a
## WorkerThreadPool group task (GeoBuilder arrays), ArrayMesh upload on the main thread a few per
## frame (`poll()`), so startup never hitches. Query `is_ready()` before instantiating cells.
##
## Species entry fields:
##   group   &"tree" | &"small" | &"ground"   (material roles + LOD scheme)
##   variants  number of mesh variants
##   cap     material cap (&"none", &"snow", &"moss", &"ash", &"sand", &"ice")
##   radius  collision trunk radius (m, at scale 1) — 0 = no collision
##   collide &"cylinder" | &"sphere" | &""    pooled near-focus collision type
##   height  nominal height (m) for collision/AABBs
##   far     true = has a far impostor (LOD 2) used by the far forest provider

const SPECIES := {
	&"pine_snow": {"group": &"tree", "variants": 2, "cap": &"snow", "radius": 0.28, "collide": &"cylinder", "height": 12.0, "far": true},
	&"fir": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.28, "collide": &"cylinder", "height": 12.0, "far": true},
	&"oak": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.42, "collide": &"cylinder", "height": 10.0, "far": true},
	&"maple": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.34, "collide": &"cylinder", "height": 8.5, "far": true},
	&"blossom": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.3, "collide": &"cylinder", "height": 7.0, "far": true},
	&"tropical": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.45, "collide": &"cylinder", "height": 15.0, "far": true},
	&"banyan": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.8, "collide": &"cylinder", "height": 11.0, "far": true},
	&"cypress": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.25, "collide": &"cylinder", "height": 9.0, "far": true},
	&"palm": {"group": &"tree", "variants": 2, "cap": &"none", "radius": 0.26, "collide": &"cylinder", "height": 10.0, "far": true},
	&"bamboo": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.9, "collide": &"cylinder", "height": 9.0, "far": true},
	&"charred": {"group": &"tree", "variants": 1, "cap": &"ash", "radius": 0.24, "collide": &"cylinder", "height": 7.0, "far": true},
	&"snag": {"group": &"tree", "variants": 1, "cap": &"none", "radius": 0.24, "collide": &"cylinder", "height": 7.0, "far": true},
	&"shrub": {"group": &"small", "variants": 1, "cap": &"none", "radius": 0.0, "collide": &"", "height": 1.3},
	&"shrub_snow": {"group": &"small", "variants": 1, "cap": &"snow", "radius": 0.0, "collide": &"", "height": 1.3},
	&"hedge": {"group": &"small", "variants": 1, "cap": &"none", "radius": 0.0, "collide": &"", "height": 1.5},
	&"fern": {"group": &"small", "variants": 1, "cap": &"none", "radius": 0.0, "collide": &"", "height": 0.9},
	&"rock": {"group": &"small", "variants": 1, "cap": &"none", "radius": 0.85, "collide": &"sphere", "height": 1.2},
	&"rock_snow": {"group": &"small", "variants": 1, "cap": &"snow", "radius": 0.85, "collide": &"sphere", "height": 1.2},
	&"rock_moss": {"group": &"small", "variants": 1, "cap": &"moss", "radius": 0.85, "collide": &"sphere", "height": 1.2},
	&"lava_rock": {"group": &"small", "variants": 1, "cap": &"ash", "radius": 0.85, "collide": &"sphere", "height": 1.2},
	&"ice_chunk": {"group": &"small", "variants": 1, "cap": &"ice", "radius": 0.8, "collide": &"sphere", "height": 1.2},
	&"serac": {"group": &"small", "variants": 1, "cap": &"ice", "radius": 1.2, "collide": &"cylinder", "height": 6.0},
	&"driftwood": {"group": &"small", "variants": 1, "cap": &"none", "radius": 0.0, "collide": &"", "height": 0.6},
	&"log_moss": {"group": &"small", "variants": 1, "cap": &"moss", "radius": 0.0, "collide": &"", "height": 0.6},
	&"grass": {"group": &"ground", "variants": 2},
	&"grass_tall": {"group": &"ground", "variants": 1},
	&"tuft": {"group": &"ground", "variants": 1},
	&"flowers_warm": {"group": &"ground", "variants": 1},
	&"flowers_cool": {"group": &"ground", "variants": 1},
	&"flowers_white": {"group": &"ground", "variants": 1},
	&"reeds": {"group": &"ground", "variants": 1},
	&"wheat": {"group": &"ground", "variants": 1},
	&"rice": {"group": &"ground", "variants": 1},
}

static var _builders: Dictionary = {}      # "id|variant|lod" -> GeoBuilder (worker output)
static var _meshes: Dictionary = {}        # "id|variant|lod" -> ArrayMesh
static var _keys: Array = []
static var _task := -1
static var _state := 0                     # 0 idle, 1 generating, 2 uploading, 3 ready
static var _upload_index := 0
static var _mutex := Mutex.new()
static var build_time_ms := 0.0
static var _t0 := 0


static func lod_count(id: StringName) -> int:
	match SPECIES[id]["group"]:
		&"tree": return 3
		&"small": return 2
	return 1


## Starts generating every species mesh on worker threads (idempotent).
static func build_async() -> void:
	if _state != 0:
		return
	_state = 1
	_t0 = Time.get_ticks_msec()
	_keys.clear()
	for id: StringName in SPECIES:
		for v in int(SPECIES[id]["variants"]):
			for lod in lod_count(id):
				_keys.append([id, v, lod])
	_task = WorkerThreadPool.add_group_task(_build_one, _keys.size(), -1, false, "VegetationLibrary meshes")


static func _build_one(i: int) -> void:
	var k: Array = _keys[i]
	var g := generate(k[0], k[1], k[2])
	_mutex.lock()
	_builders["%s|%d|%d" % [k[0], k[1], k[2]]] = g
	_mutex.unlock()


## Main thread: advances the upload (call every frame/scan until is_ready()). Uploads meshes
## for at most `budget_usec`. Builds synchronously when `blocking`.
static func poll(budget_usec: int = 1500, blocking: bool = false) -> bool:
	if _state == 0:
		build_async()
	if _state == 1:
		if not blocking and not WorkerThreadPool.is_group_task_completed(_task):
			return false
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
		_state = 2
		_upload_index = 0
	if _state == 2:
		var t0 := Time.get_ticks_usec()
		while _upload_index < _keys.size():
			var k: Array = _keys[_upload_index]
			var key := "%s|%d|%d" % [k[0], k[1], k[2]]
			var g: GeoBuilder = _builders.get(key)
			_meshes[key] = g.to_mesh() if g else ArrayMesh.new()
			_upload_index += 1
			if not blocking and Time.get_ticks_usec() - t0 > budget_usec:
				return false
		_builders.clear()
		_state = 3
		build_time_ms = Time.get_ticks_msec() - _t0
	return _state == 3


static func is_ready() -> bool:
	return _state == 3


## Blocks until every mesh exists (tests, dev scenes).
static func ensure_ready() -> void:
	poll(0, true)


## Mesh of a species variant at a LOD (clamped). Null until ready.
static func get_mesh(id: StringName, variant: int = 0, lod: int = 0) -> ArrayMesh:
	var v := clampi(variant, 0, int(SPECIES[id]["variants"]) - 1)
	var l := clampi(lod, 0, lod_count(id) - 1)
	return _meshes.get("%s|%d|%d" % [id, v, l])


## Material for a species at a LOD (0 near, 1 mid, 2 far).
static func get_material(id: StringName, lod: int) -> ShaderMaterial:
	var sp: Dictionary = SPECIES[id]
	var cap: StringName = sp.get("cap", &"none")
	match sp["group"]:
		&"tree":
			return VegetationMaterials.get_material([&"tree_near", &"tree_mid", &"tree_far"][clampi(lod, 0, 2)], cap)
		&"small":
			return VegetationMaterials.get_material(&"small_near" if lod == 0 else &"small_mid", cap)
	return VegetationMaterials.get_material(&"grass")


## Thread-safe deterministic generation of one mesh variant.
static func generate(id: StringName, variant: int, lod: int) -> GeoBuilder:
	var rng := ContentHash.rng(ContentHash.hash4(ContentHash.hash_name(String(id)), variant, 7))
	match id:
		&"pine_snow": return TreeMeshes.conifer(rng, lod, 0.85, 12.0)
		&"fir": return TreeMeshes.conifer(rng, lod, 0.0, 12.5, true)
		&"oak": return TreeMeshes.broadleaf(rng, lod, &"oak")
		&"maple": return TreeMeshes.broadleaf(rng, lod, &"maple")
		&"blossom": return TreeMeshes.broadleaf(rng, lod, &"blossom")
		&"tropical": return TreeMeshes.broadleaf(rng, lod, &"tropical")
		&"banyan": return TreeMeshes.broadleaf(rng, lod, &"banyan")
		&"cypress": return TreeMeshes.broadleaf(rng, lod, &"cypress")
		&"palm": return TreeMeshes.palm(rng, lod)
		&"bamboo": return TreeMeshes.bamboo(rng, lod)
		&"charred": return TreeMeshes.bare(rng, lod, true)
		&"snag": return TreeMeshes.bare(rng, lod, false)
		&"shrub": return PlantMeshes.shrub(rng, lod)
		&"shrub_snow": return PlantMeshes.shrub(rng, lod, true)
		&"hedge": return PlantMeshes.hedge(rng, lod)
		&"fern": return PlantMeshes.fern(rng, lod)
		&"rock": return PlantMeshes.rock(rng, lod, false)
		&"rock_snow", &"rock_moss": return PlantMeshes.rock(rng, lod, true)
		&"lava_rock": return PlantMeshes.rock(rng, lod, false, true)
		&"ice_chunk": return PlantMeshes.ice(rng, lod, false)
		&"serac": return PlantMeshes.ice(rng, lod, true)
		&"driftwood": return PlantMeshes.log_piece(rng, lod, false)
		&"log_moss": return PlantMeshes.log_piece(rng, lod, true)
		&"grass": return PlantMeshes.grass(rng, 12, 0.3, 0.3, 0.6, 0.05, 2)
		&"grass_tall": return PlantMeshes.grass(rng, 10, 0.32, 0.6, 1.05, 0.045, 3)
		&"tuft": return PlantMeshes.grass(rng, 10, 0.18, 0.16, 0.32, 0.035, 2)
		&"flowers_warm": return PlantMeshes.flowers(rng, TreeMeshes.col(0.98, 0.62, 0.16), TreeMeshes.col(0.75, 0.2, 0.1))
		&"flowers_cool": return PlantMeshes.flowers(rng, TreeMeshes.col(0.62, 0.48, 0.92), TreeMeshes.col(1.0, 0.9, 0.4))
		&"flowers_white": return PlantMeshes.flowers(rng, TreeMeshes.col(0.97, 0.96, 0.92), TreeMeshes.col(1.0, 0.82, 0.25))
		&"reeds": return PlantMeshes.reeds(rng)
		&"wheat": return PlantMeshes.wheat(rng)
		&"rice": return PlantMeshes.grass(rng, 12, 0.22, 0.4, 0.62, 0.035, 2)
	push_warning("VegetationLibrary: unknown species %s" % id)
	return GeoBuilder.new()
